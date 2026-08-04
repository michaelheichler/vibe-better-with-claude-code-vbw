#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
fi

SESSION="${1:-}"
if [ -z "$SESSION" ]; then
  if [ -n "${TMUX:-}" ]; then
    SESSION=$(tmux display-message -p '#S' 2>/dev/null || true)
  fi
fi

if [ -z "$SESSION" ]; then
  echo "ERROR: No session name provided and not running in tmux" >&2
  exit 1
fi

LOG="$PLANNING_DIR/.watchdog.log"
mkdir -p "$PLANNING_DIR"

log() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $*" >> "$LOG" 2>/dev/null || echo "[$timestamp] $*" >&2
}

cleanup_detached_agent_state() {
  if command -v vbw_active_agent_clear_all >/dev/null 2>&1; then
    vbw_active_agent_clear_all "$PLANNING_DIR"
    if [ -e "$PLANNING_DIR/.active-agent" ] || [ -e "$PLANNING_DIR/.active-agent-count" ]; then
      rm -rf "$PLANNING_DIR/.active-agent-count.lock" 2>/dev/null || true
      vbw_active_agent_clear_all "$PLANNING_DIR"
    fi
  else
    rm -f \
      "$PLANNING_DIR/.active-agent" \
      "$PLANNING_DIR/.active-agent-count" \
      "$PLANNING_DIR/.active-agent-roles" \
      "$PLANNING_DIR/.active-agent-role-pids" \
      2>/dev/null || true
    rm -rf "$PLANNING_DIR/.active-agents" "$PLANNING_DIR/.active-agent-count.lock" 2>/dev/null || true
  fi
  rm -f "$PLANNING_DIR/.agent-panes" 2>/dev/null || true
}

log "Watchdog started for session: $SESSION (PID=$$)"

mkdir -p "$PLANNING_DIR/.compacting" 2>/dev/null || true
for _stale_marker in "$PLANNING_DIR/.compacting"/*.json; do
  [ ! -f "$_stale_marker" ] && continue
  _stale_pid=$(jq -r '.pid // ""' "$_stale_marker" 2>/dev/null)
  _stale_ts=$(jq -r '.started_at // ""' "$_stale_marker" 2>/dev/null)
  if ! echo "$_stale_pid" | grep -Eq '^[1-9][0-9]{0,9}$' \
     || ! echo "$_stale_ts" | grep -Eq '^[1-9][0-9]{0,9}$' \
     || ! kill -0 "$_stale_pid" 2>/dev/null; then
    rm -f "$_stale_marker" 2>/dev/null || true
  fi
done

COMPACTION_TIMEOUT="${VBW_COMPACTION_TIMEOUT:-300}"
if ! echo "$COMPACTION_TIMEOUT" | grep -Eq '^[1-9][0-9]{0,5}$'; then
  log "Invalid VBW_COMPACTION_TIMEOUT='$COMPACTION_TIMEOUT', using default 300"
  COMPACTION_TIMEOUT=300
fi

resolve_agent_pane() {
  local pid="$1" pane_list walk_pid resolved
  pane_list=$(tmux list-panes -a -F '#{pane_pid} #{pane_id}' 2>/dev/null) || pane_list=""
  [ -n "$pane_list" ] || return 0
  walk_pid="$pid"
  while [ -n "$walk_pid" ] && [ "$walk_pid" != "0" ] && [ "$walk_pid" != "1" ]; do
    resolved=$(echo "$pane_list" | awk -v p="$walk_pid" '$1 == p { print $2; exit }')
    if [ -n "$resolved" ]; then
      printf '%s\n' "$resolved"
      return 0
    fi
    walk_pid=$(ps -o ppid= -p "$walk_pid" 2>/dev/null | tr -d ' ')
  done
}

terminate_timed_out_agent() {
  local pid="$1" pane_id="$2"
  (
    log "Sending SIGTERM to stuck agent PID $pid"
    kill -TERM "$pid" 2>/dev/null || true
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
      log "Agent PID $pid survived SIGTERM, sending SIGKILL"
      kill -KILL "$pid" 2>/dev/null || true
    fi
    if [ -n "$pane_id" ]; then
      log "Killing tmux pane $pane_id"
      tmux kill-pane -t "$pane_id" 2>/dev/null || true
    fi
  ) &
}

cleanup_timed_out_agent() {
  local pid="$1" agent_name="$2" marker="$3" age="$4" pane_id pane_map
  pane_id=$(resolve_agent_pane "$pid")
  log "COMPACTION TIMEOUT: agent=$agent_name pid=$pid pane=$pane_id age=${age}s (limit=${COMPACTION_TIMEOUT}s)"
  terminate_timed_out_agent "$pid" "$pane_id"
  if [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
    bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$pid" 2>/dev/null || true
  fi
  pane_map="$PLANNING_DIR/.agent-panes"
  if [ -f "$pane_map" ]; then
    grep -v "^${pid} " "$pane_map" > "${pane_map}.tmp" 2>/dev/null || true
    mv "${pane_map}.tmp" "$pane_map" 2>/dev/null || true
  fi
  rm -f "$marker" 2>/dev/null || true
  log "Compaction timeout cleanup complete for $agent_name (PID $pid)"
}

check_compaction_timeouts() {
  local compacting_dir="$PLANNING_DIR/.compacting"
  [ ! -d "$compacting_dir" ] && return
  local now marker pid agent_name started_at age
  now=$(date +%s)
  for marker in "$compacting_dir"/*.json; do
    [ ! -f "$marker" ] && continue
    pid=$(jq -r '.pid // ""' "$marker" 2>/dev/null)
    agent_name=$(jq -r '.agent_name // "unknown"' "$marker" 2>/dev/null)
    started_at=$(jq -r '.started_at // 0' "$marker" 2>/dev/null)
    if ! echo "$pid" | grep -Eq '^[1-9][0-9]{0,9}$' || ! echo "$started_at" | grep -Eq '^[1-9][0-9]{0,9}$'; then
      rm -f "$marker" 2>/dev/null || true
      continue
    fi
    if [ "$started_at" -gt $((now + 60)) ]; then
      rm -f "$marker" 2>/dev/null || true
      continue
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      log "Compaction marker for dead PID $pid ($agent_name), cleaning up"
      rm -f "$marker" 2>/dev/null || true
      continue
    fi
    age=$((now - started_at))
    if [ "$age" -gt "$COMPACTION_TIMEOUT" ]; then
      cleanup_timed_out_agent "$pid" "$agent_name" "$marker" "$age"
    fi
  done
}

consecutive_empty=0
while true; do
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    log "Session $SESSION no longer exists, exiting"
    break
  fi

  CLIENTS=$(tmux list-clients -t "$SESSION" 2>/dev/null | wc -l | tr -d ' ')

  if [ "${CLIENTS:-0}" -eq 0 ]; then
    consecutive_empty=$((consecutive_empty + 1))
    log "No clients attached (consecutive: $consecutive_empty)"

    if [ "$consecutive_empty" -ge 2 ]; then
      log "Session detached (2 consecutive polls), cleaning up agents"

      PIDS=""
      if [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ]; then
        PIDS=$(bash "$SCRIPT_DIR/agent-pid-tracker.sh" list 2>/dev/null || true)
      fi

      if [ -z "$PIDS" ]; then
        log "No active agent PIDs to terminate"
      else
        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Sending SIGTERM to agent PID $pid"
            kill -TERM "$pid" 2>/dev/null || true
          fi
        done

        sleep 3

        for pid in $PIDS; do
          if kill -0 "$pid" 2>/dev/null; then
            log "Agent PID $pid survived SIGTERM, sending SIGKILL"
            kill -KILL "$pid" 2>/dev/null || true
          fi
        done

        log "Agent cleanup complete"
      fi

      if [ -f "$PLANNING_DIR/.agent-pids" ]; then
        rm -f "$PLANNING_DIR/.agent-pids" 2>/dev/null || true
        log "Removed .agent-pids file"
      fi
      cleanup_detached_agent_state
      rm -rf "$PLANNING_DIR/.compacting" 2>/dev/null || true

      log "Watchdog exiting"
      break
    fi
  else
    if [ "$consecutive_empty" -gt 0 ]; then
      log "Client attached, resetting empty counter"
    fi
    consecutive_empty=0
  fi

  check_compaction_timeouts

  sleep 5
done

exit 0
