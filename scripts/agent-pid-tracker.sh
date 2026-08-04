#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/vbw-cache-key.sh"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
PID_FILE="$PLANNING_DIR/.agent-pids"
LOCK_ROOT=$(cd "$(dirname "$PLANNING_DIR")" 2>/dev/null && pwd -P 2>/dev/null || pwd -P 2>/dev/null || pwd)
LOCK_KEY=$(vbw_hash_path "$LOCK_ROOT")
LOCK_DIR="${VBW_AGENT_PID_LOCK_DIR:-/tmp/vbw-agent-pid-lock-$(id -u)-${LOCK_KEY}}"

acquire_lock() {
  local retries=50
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    retries=$((retries - 1))
    if [ "$retries" -le 0 ]; then
      echo "ERROR: Failed to acquire lock after 50 attempts" >&2
      return 1
    fi
    if [ -f "${LOCK_DIR}/pid" ]; then
      local lock_pid
      lock_pid=$(cat "${LOCK_DIR}/pid" 2>/dev/null || echo "")
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "${LOCK_DIR}/pid"
        rmdir "$LOCK_DIR" 2>/dev/null || true
        continue
      fi
    else
      local pid_wait=0
      while [ "$pid_wait" -lt 5 ] && [ ! -f "${LOCK_DIR}/pid" ]; do
        sleep 0.1
        pid_wait=$((pid_wait + 1))
      done
      if [ -f "${LOCK_DIR}/pid" ]; then
        continue
      fi
      rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    sleep 0.1
  done
  echo $$ > "${LOCK_DIR}/pid" 2>/dev/null || true
  return 0
}

release_lock() {
  rm -f "${LOCK_DIR}/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

cmd_register() {
  local pid="$1"
  if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid PID format: $pid" >&2
    return 1
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  mkdir -p "$(dirname "$PID_FILE")"

  if [ -f "$PID_FILE" ]; then
    if grep -q "^${pid}$" "$PID_FILE" 2>/dev/null; then
      return 0  # Already registered
    fi
  fi

  echo "$pid" >> "$PID_FILE"
  release_lock
  trap - EXIT
}

cmd_unregister() {
  local pid="$1"
  if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: Invalid PID format: $pid" >&2
    return 1
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  if [ ! -f "$PID_FILE" ]; then
    release_lock
    trap - EXIT
    return 0
  fi

  rm -f "${PID_FILE}.tmp" 2>/dev/null || true
  grep -v "^${pid}$" "$PID_FILE" > "${PID_FILE}.tmp" 2>/dev/null || true
  mv "${PID_FILE}.tmp" "$PID_FILE"

  if [ ! -s "$PID_FILE" ]; then
    rm -f "$PID_FILE"
  fi

  release_lock
  trap - EXIT
}

cmd_list() {
  if [ ! -f "$PID_FILE" ]; then
    return 0
  fi

  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
      continue
    fi
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
    fi
  done < "$PID_FILE"
}

cmd_prune() {
  if [ ! -f "$PID_FILE" ]; then
    return 0
  fi

  acquire_lock || return 1
  trap release_lock EXIT

  local temp_file="${PID_FILE}.tmp"
  local kept=0

  rm -f "$temp_file" 2>/dev/null || true

  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      echo "$pid" >> "$temp_file"
      kept=$((kept + 1))
    fi
  done < "$PID_FILE"

  if [ "$kept" -gt 0 ] && [ -f "$temp_file" ]; then
    mv "$temp_file" "$PID_FILE"
  else
    rm -f "$PID_FILE"
  fi
  rm -f "$temp_file" 2>/dev/null || true

  release_lock
  trap - EXIT
}

CMD="${1:-}"
case "$CMD" in
  register)
    [ -z "${2:-}" ] && { echo "Usage: $0 register <pid>" >&2; exit 1; }
    cmd_register "$2"
    ;;
  unregister)
    [ -z "${2:-}" ] && { echo "Usage: $0 unregister <pid>" >&2; exit 1; }
    cmd_unregister "$2"
    ;;
  list)
    cmd_list
    ;;
  prune)
    cmd_prune
    ;;
  *)
    echo "Usage: $0 {register|unregister|list|prune} [pid]" >&2
    exit 1
    ;;
esac
