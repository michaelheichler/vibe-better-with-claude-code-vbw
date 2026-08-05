#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || exit 0
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$SCRIPT_DIR/lib/agent-manifest.sh" ] || exit 0
. "$SCRIPT_DIR/lib/agent-manifest.sh" || exit 0
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
COMMAND="${1:-}"
case "$COMMAND" in
  touch|check|sweep) ;;
  *) exit 0 ;;
esac

lifecycle_now_epoch() {
  local value="${VBW_LIFECYCLE_NOW:-}"
  case "$value" in
    ''|*[!0-9]*) date +%s 2>/dev/null || printf '0\n' ;;
    *) printf '%s\n' "$value" ;;
  esac
}

lifecycle_epoch_iso() {
  local epoch="$1" result=""
  if [ "$(uname)" = "Darwin" ]; then
    result=$(date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  else
    result=$(date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  fi
  [ -n "$result" ] && printf '%s\n' "$result"
}

lifecycle_timestamp_epoch() {
  local value="$1" result=""
  case "$value" in
    ''|*[!0-9]*) ;;
    *) printf '%s\n' "$value"; return 0 ;;
  esac
  if [ "$(uname)" = "Darwin" ]; then
    result=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null || true)
  fi
  [ -n "$result" ] || result=$(date -u -d "$value" +%s 2>/dev/null || true)
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

emit_context() {
  local event="$1" context="$2"
  jq -cn --arg event "$event" --arg context "$context" \
    '{hookSpecificOutput:{hookEventName:$event,additionalContext:$context}}'
}

extract_agent_name() {
  printf '%s' "$INPUT" | jq -r '
    first(
      .agent_type, .agentType, .subagent_type, .subagentType,
      .name, .agent_name, .agentName, .teammate_name,
      .tool_input.agent_type, .tool_input.agentType,
      .tool_input.subagent_type, .tool_input.subagentType,
      .tool_input.name, .tool_input.agent_name, .tool_input.teammate_name,
      .agent_id, .agentId
      | select(type == "string" and length > 0)
    ) // ""
  ' 2>/dev/null
}

extract_agent_role() {
  local raw normalized
  raw=$(printf '%s' "$INPUT" | jq -r '.role // .agent_role // .agent_type // .subagent_type // .tool_input.role // .tool_input.subagent_type // ""' 2>/dev/null) || raw=""
  if command -v vbw_active_agent_normalize_role >/dev/null 2>&1 && normalized=$(vbw_active_agent_normalize_role "$raw" 2>/dev/null); then
    printf '%s\n' "$normalized"
  else
    printf '%s\n' "$raw"
  fi
}

start_manifest_entry() {
  local manifest="$1" name="$2" role="$3" now="$4"
  jq -c --arg name "$name" --arg role "$role" --arg now "$now" '
    .agents[$name] = ((.agents[$name] // {}) + {
      name: $name,
      role: (if $role != "" then $role else (.agents[$name].role // "") end),
      state: "running",
      created_at: $now,
      last_activity_at: $now,
      warnings_sent: []
    })
  ' <<< "$manifest" 2>/dev/null
}

stop_manifest_entry() {
  local manifest="$1" name="$2" role="$3" now="$4"
  jq -e --arg name "$name" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1 || return 1
  jq -c --arg name "$name" --arg role "$role" --arg now "$now" '
    .agents[$name].state = "used"
    | .agents[$name].last_activity_at = $now
    | .agents[$name].stopped_at = $now
    | if $role != "" then .agents[$name].role = $role else . end
  ' <<< "$manifest" 2>/dev/null
}

touch_manifest_locked() {
  local action="$1" name="$2" role="$3" now_iso="$4" manifest updated path
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  if [ "$action" = "stop" ]; then
    updated=$(stop_manifest_entry "$manifest" "$name" "$role" "$now_iso") || return 1
  else
    updated=$(start_manifest_entry "$manifest" "$name" "$role" "$now_iso") || return 1
  fi
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || return 1
  if [ "$action" = "stop" ]; then
    path=$(agent_manifest_definition_path "$PLANNING_DIR" "$name" 2>/dev/null) || return 1
    rm -f "$path" 2>/dev/null || return 1
  fi
}

touch_agent() {
  local action="${1:-start}" name role now_iso
  INPUT=$(cat 2>/dev/null) || INPUT=""
  [ -n "$INPUT" ] || exit 0
  name=$(extract_agent_name)
  agent_manifest_safe_name "$name" || exit 0
  role=$(extract_agent_role)
  now_iso=$(lifecycle_epoch_iso "$(lifecycle_now_epoch)") || exit 0
  [ -n "$now_iso" ] || exit 0
  agent_manifest_with_lock "$PLANNING_DIR" touch_manifest_locked "$action" "$name" "$role" "$now_iso" || exit 0
} # activity signals: SubagentStart and SubagentStop refresh last_activity_at.

append_check_notice() {
  local notice="$1"
  CHECK_NOTICES="${CHECK_NOTICES}${CHECK_NOTICES:+$'\n'}${notice}"
}

expire_check_agent() {
  local name="$1" now_iso="$2" path
  CHECK_MANIFEST=$(jq -c --arg name "$name" --arg now "$now_iso" '
    .agents[$name].state = "used"
    | .agents[$name].expired_at = $now
  ' <<< "$CHECK_MANIFEST" 2>/dev/null) || return 1
  CHECK_CHANGED=1
  path=$(agent_manifest_definition_path "$PLANNING_DIR" "$name" 2>/dev/null || true)
  [ -n "$path" ] && rm -f "$path" 2>/dev/null || true
  append_check_notice "Agent '$name' expired after 10 minutes of inactivity. Stop waiting for it and continue with another spawned agent."
}

check_warning() {
  local name="$1" warning="$2" threshold_seconds="$3" idle="$4" sent idle_minutes remaining_label
  [ "$idle" -ge "$threshold_seconds" ] || return 0
  idle_minutes=$((threshold_seconds / 60))
  remaining_label="minutes"
  [ "$warning" -eq 1 ] && remaining_label="minute"
  sent=$(jq -r --arg name "$name" --arg warning "$warning" '
    (.agents[$name].warnings_sent // []) as $sent
    | if ($sent | type) == "array" then any($sent[]; tostring == $warning) else ($sent | tostring == $warning) end
  ' <<< "$CHECK_MANIFEST" 2>/dev/null) || sent="false"
  [ "$sent" = "true" ] && return 0
  CHECK_MANIFEST=$(jq -c --arg name "$name" --arg warning "$warning" '
    .agents[$name].warnings_sent = ((.agents[$name].warnings_sent // [])
      | if type == "array" then . else [tostring] end
      | if any(.[]; tostring == $warning) then . else . + [$warning] end)
  ' <<< "$CHECK_MANIFEST" 2>/dev/null) || return 1
  CHECK_CHANGED=1
  append_check_notice "Agent '$name' has been idle for $idle_minutes minutes. $warning $remaining_label remain before VBW expires it. Delegate or stop it."
}

check_agent_entry() {
  local name="$1" now="$2" now_iso="$3" entry state last last_epoch idle
  entry=$(jq -c --arg name "$name" '.agents[$name] // {}' <<< "$CHECK_MANIFEST" 2>/dev/null) || return 0
  state=$(jq -r '.state // ""' <<< "$entry" 2>/dev/null) || state=""
  [ "$state" = "running" ] || return 0
  last=$(jq -r '.last_activity_at // .created_at // ""' <<< "$entry" 2>/dev/null) || last=""
  last_epoch=$(lifecycle_timestamp_epoch "$last" 2>/dev/null) || return 0
  idle=$((now - last_epoch))
  [ "$idle" -ge 0 ] || idle=0
  if [ "$idle" -ge 600 ]; then
    expire_check_agent "$name" "$now_iso"
    return 0
  fi
  check_warning "$name" 5 300 "$idle"
  check_warning "$name" 2 480 "$idle"
  check_warning "$name" 1 540 "$idle"
}

check_agents_locked() {
  local name="$1" now="$2" now_iso="$3"
  CHECK_MANIFEST=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  check_agent_entry "$name" "$now" "$now_iso"
  if [ "$CHECK_CHANGED" -eq 1 ]; then
    agent_manifest_write "$PLANNING_DIR" "$CHECK_MANIFEST" >/dev/null 2>&1 || return 1
  fi
}

check_agents() {
  local now now_iso name
  INPUT=$(cat 2>/dev/null) || INPUT=""
  [ -n "$INPUT" ] || exit 0
  name=$(extract_agent_name)
  agent_manifest_safe_name "$name" || exit 0
  now=$(lifecycle_now_epoch)
  now_iso=$(lifecycle_epoch_iso "$now") || exit 0
  [ -n "$now_iso" ] || exit 0
  CHECK_NOTICES=""
  CHECK_CHANGED=0
  agent_manifest_with_lock "$PLANNING_DIR" check_agents_locked "$name" "$now" "$now_iso" || exit 0
  [ -n "$CHECK_NOTICES" ] && emit_context TeammateIdle "$CHECK_NOTICES"
} # TeammateIdle evaluates only the agent reported by that event.

sweep_agents_locked() {
  local now="$1" now_iso="$2" names name entry state created created_epoch age updated path
  SWEEP_MANIFEST=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  names=$(jq -r '.agents | keys[]' <<< "$SWEEP_MANIFEST" 2>/dev/null) || return 1
  SWEEP_CHANGED=0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    entry=$(jq -c --arg name "$name" '.agents[$name] // {}' <<< "$SWEEP_MANIFEST" 2>/dev/null) || continue
    state=$(jq -r '.state // ""' <<< "$entry" 2>/dev/null) || state=""
    case "$state" in registered|running) ;;
      *) continue ;;
    esac
    created=$(jq -r '.created_at // ""' <<< "$entry" 2>/dev/null) || created=""
    created_epoch=$(lifecycle_timestamp_epoch "$created" 2>/dev/null) || continue
    age=$((now - created_epoch))
    [ "$age" -gt 86400 ] || continue
    updated=$(jq -c --arg name "$name" --arg now "$now_iso" '
      .agents[$name].state = "expired"
      | .agents[$name].expired_at = $now
    ' <<< "$SWEEP_MANIFEST" 2>/dev/null) || continue
    SWEEP_MANIFEST="$updated"
    SWEEP_CHANGED=1
    path=$(agent_manifest_definition_path "$PLANNING_DIR" "$name" 2>/dev/null || true)
    [ -n "$path" ] && rm -f "$path" 2>/dev/null || true
  done <<< "$names"
  if [ "$SWEEP_CHANGED" -eq 1 ]; then
    agent_manifest_write "$PLANNING_DIR" "$SWEEP_MANIFEST" >/dev/null 2>&1 || return 1
  fi
}

sweep_agents() {
  local now now_iso
  now=$(lifecycle_now_epoch)
  now_iso=$(lifecycle_epoch_iso "$now") || exit 0
  [ -n "$now_iso" ] || exit 0
  agent_manifest_with_lock "$PLANNING_DIR" sweep_agents_locked "$now" "$now_iso" || exit 0
} # sweep uses the manifest lock for expiry and definition cleanup.

case "$COMMAND" in
  touch) touch_agent "${2:-start}" ;;
  check) check_agents ;;
  sweep) sweep_agents ;;
esac
exit 0
