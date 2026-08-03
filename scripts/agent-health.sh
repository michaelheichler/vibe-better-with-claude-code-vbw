#!/bin/bash
set -u

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
HEALTH_DIR="${HEALTH_DIR:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/resolve-claude-dir.sh" 2>/dev/null || true
if [ ! -f "$SCRIPT_DIR/lib/active-agent-state.sh" ] && [ -f "$PWD/scripts/lib/active-agent-state.sh" ]; then
  SCRIPT_DIR="$PWD/scripts"
fi
. "$SCRIPT_DIR/lib/active-agent-state.sh"

normalize_agent_key() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"
  lower="${lower#vbw-}"
  printf '%s' "$lower"
}

normalize_team_name() {
  local value="$1"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

has_vbw_context() {
  [ -f "$PLANNING_DIR/.vbw-session" ] \
    || [ -f "$PLANNING_DIR/.active-agent" ] \
    || [ -f "$PLANNING_DIR/.active-agent-count" ]
}

is_explicit_vbw_agent() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^@?vbw:|^@?vbw-'
}

is_vbw_team_name() {
  local value="$1"
  local lower

  lower=$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')
  echo "$lower" | grep -qE '^vbw-[a-z0-9-]+$'
}

extract_payload_pid() {
  local input="$1"
  local pid=""

  pid=$(echo "$input" | jq -r '.pid // ""' 2>/dev/null)
  if echo "$pid" | grep -Eq '^[1-9][0-9]*$'; then
    printf '%s' "$pid"
  fi
}

process_start_identity() {
  local pid="$1"
  ps -o lstart= -p "$pid" 2>/dev/null | awk '{$1=$1; print}'
}

extract_payload_artifact_path() {
  local input="$1"
  echo "$input" | jq -r '(.artifact_path // .output_path // .artifact // "")' 2>/dev/null
}

update_health_pid_record() {
  local health_file="$1" pid="$2" team_name="$3" identity="$4"
  jq \
    --arg pid "$pid" \
    --arg team_name "$team_name" \
    --arg identity "$identity" \
    'if $pid != "" then .pid = $pid else . end
     | if $identity != "" then .pid_identity = $identity else . end
     | if $team_name != "" then .team_name = $team_name else . end' \
    "$health_file" > "${health_file}.tmp" && mv "${health_file}.tmp" "$health_file"
}

refresh_health_pid_from_payload() {
  local health_file="$1" input="$2" payload_pid payload_team_name payload_identity
  [ -f "$health_file" ] || return 1
  payload_pid=$(extract_payload_pid "$input")
  payload_team_name=$(normalize_team_name "$(echo "$input" | jq -r '.team_name // ""' 2>/dev/null)")
  payload_identity=""
  [ -n "$payload_pid" ] && payload_identity=$(process_start_identity "$payload_pid")
  if [ -n "$payload_pid" ] || [ -n "$payload_team_name" ]; then
    update_health_pid_record "$health_file" "$payload_pid" "$payload_team_name" "$payload_identity"
  fi
  [ -n "$payload_pid" ] || return 1
  printf '%s' "$payload_pid"
}


resolve_health_role_context() {
  local input="$1" native legacy team role_source="" scoped=0
  native=$(echo "$input" | jq -r '.agent_type // ""' 2>/dev/null)
  legacy=$(echo "$input" | jq -r '.agent_name // .agentName // .name // .teammate_name // ""' 2>/dev/null)
  team=$(normalize_team_name "$(echo "$input" | jq -r '.team_name // ""' 2>/dev/null)")
  if [ -n "$native" ]; then
    if is_explicit_vbw_agent "$native"; then role_source="$native"
    elif is_explicit_vbw_agent "$legacy"; then role_source="$legacy"
    else printf '||'; return 0; fi
  elif is_explicit_vbw_agent "$legacy"; then role_source="$legacy"
  elif vbw_active_agent_normalize_role "$legacy" >/dev/null; then
    if [ -n "$team" ]; then
      is_vbw_team_name "$team" || { printf '||'; return 0; }
      role_source="$legacy"; scoped=1
    elif has_vbw_context; then role_source="$legacy"
    else printf '||'; return 0; fi
  else printf '||'; return 0; fi
  printf '%s|%s|%s' "$role_source" "$team" "$scoped"
}

extract_health_key() {
  local input="$1" key
  key=$(echo "$input" | jq -r '(.agent_id // .teammate_name // .name // .task_id // .agent_name // .agentName // .agent_type // "")' 2>/dev/null)
  normalize_agent_key "$key"
}

extract_agent_key_and_role() {
  local input="$1" context role_source team_name scoped key role
  context=$(resolve_health_role_context "$input")
  role_source="${context%%|*}"; context="${context#*|}"
  team_name="${context%%|*}"; scoped="${context#*|}"
  [ -n "$role_source" ] || { printf '%s|%s' "$team_name" ""; return 0; }
  key=$(extract_health_key "$input")
  [ "$scoped" -eq 1 ] && [ -n "$team_name" ] && [ -n "$key" ] && key="${team_name}__${key}"
  role=$(vbw_active_agent_normalize_role "$role_source" 2>/dev/null) || {
    role=$(normalize_agent_key "$role_source"); role=$(echo "$role" | sed -E 's/-[0-9]+$//')
  }
  printf '%s|%s|%s' "$key" "$role" "$team_name"
}

orphan_peer_advisory() {
  local role="$1" key="$2" team_name="$3" pid="$4" health_file live_key live_role live_pid live_team respawn_done
  [ -d "$HEALTH_DIR" ] || return 1
  for health_file in "$HEALTH_DIR"/*.json; do
    [ -f "$health_file" ] || continue
    live_key=$(jq -r '.key // ""' "$health_file" 2>/dev/null)
    live_role=$(jq -r '.role // ""' "$health_file" 2>/dev/null)
    live_pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)
    live_team=$(jq -r '.team_name // ""' "$health_file" 2>/dev/null)
    [ -n "$key" ] && [ "$live_key" = "$key" ] && continue
    [ "$live_role" = "$role" ] || continue
    [ -z "$team_name" ] || [ "$live_team" = "$team_name" ] || continue
    respawn_done=$(jq -r '.respawn_cycle_done // false' "$health_file" 2>/dev/null)
    [ "$respawn_done" = "true" ] && continue
    if [ -z "$live_pid" ]; then
      printf 'AGENT HEALTH: Orphan recovery, agent %s PID %s is dead, but another same-role teammate is still tracked%s; leaving role-owned tasks unchanged' "$role" "$pid" "${team_name:+ for team $team_name}"
      return 0
    fi
    if vbw_active_agent_pid_is_live "$live_pid"; then
      printf 'AGENT HEALTH: Orphan recovery, agent %s PID %s is dead, but another live teammate with the same role is still active; leaving role-owned tasks unchanged' "$role" "$pid"
      return 0
    fi
  done
  return 1
}

clear_orphan_tasks() {
  local tasks_dir="$1" role="$2" key="$3" pid="$4" team_name="$5" advisory="" task_file task_owner task_status task_id team_dir
  if [ -n "$team_name" ]; then set -- "$tasks_dir/$team_name"; else set -- "$tasks_dir"/*; fi
  for team_dir in "$@"; do
    [ -d "$team_dir" ] || continue
    for task_file in "$team_dir"/*.json; do
      [ -f "$task_file" ] || continue
      task_owner=$(jq -r '.owner // ""' "$task_file" 2>/dev/null)
      task_status=$(jq -r '.status // ""' "$task_file" 2>/dev/null)
      task_id=$(jq -r '.id // ""' "$task_file" 2>/dev/null)
      if [ "$task_status" = "in_progress" ] && { [ "$task_owner" = "$key" ] || [ "$task_owner" = "$role" ]; }; then
        jq '.owner = ""' "$task_file" > "${task_file}.tmp" && mv "${task_file}.tmp" "$task_file"
        advisory="AGENT HEALTH: Orphan recovery, cleared ownership of task $task_id (owner $role PID $pid is dead)"
      fi
    done
  done
  printf '%s' "$advisory"
}

orphan_recovery() {
  local role="$1" pid="$2" key="${3:-}" team_name="${4:-}"
  local tasks_dir="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/tasks" advisory
  [ -d "$tasks_dir" ] || { echo 'AGENT HEALTH: Orphan recovery, no tasks directory found'; return; }
  if orphan_peer_advisory "$role" "$key" "$team_name" "$pid"; then return; fi
  advisory=$(clear_orphan_tasks "$tasks_dir" "$role" "$key" "$pid" "$team_name")
  [ -n "$advisory" ] || advisory="AGENT HEALTH: Orphan recovery, agent $role PID $pid is dead (no orphaned tasks found)"
  printf '%s\n' "$advisory"
}

log_health_advisory() {
  local advisory="$1"
  local timestamp

  [ -n "$advisory" ] || return 0
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
  mkdir -p "$PLANNING_DIR" 2>/dev/null || true
  echo "[$timestamp] $advisory" >> "$PLANNING_DIR/.hook-errors.log" 2>/dev/null || true
}

health_state_dir() {
  local input="${1:-}" sid
  if [ -n "$HEALTH_DIR" ]; then printf '%s' "$HEALTH_DIR"; return; fi
  sid=$(vbw_active_agent_session_id "$input" 2>/dev/null) || sid="$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID"
  _vbw_active_agent_agents_dir "$PLANNING_DIR" "$sid"
}

health_file_for() {
  local input="$1" key="$2" pid="${3:-}" dir file
  dir=$(health_state_dir "$input")
  if [ -n "$HEALTH_DIR" ]; then printf '%s/%s.json' "$dir" "$key"; return; fi
  if _vbw_active_agent_valid_pid "$pid" && [ -f "$dir/$pid.json" ]; then printf '%s/%s.json' "$dir" "$pid"; return; fi
  for file in "$dir"/*.json; do
    [ -f "$file" ] || continue
    [ "$(jq -r '.key // ""' "$file" 2>/dev/null)" = "$key" ] && { printf '%s' "$file"; return; }
  done
  if _vbw_active_agent_valid_pid "$pid"; then printf '%s/%s.json' "$dir" "$pid"; else printf '%s/%s.json' "$dir" "$key"; fi
}

prepare_health_file() {
  local input="$1" key="$2" role="$3" pid="$4" file dir
  dir=$(health_state_dir "$input")
  mkdir -p "$dir"
  file=$(health_file_for "$input" "$key" "$pid")
  if [ ! -f "$file" ] && [ -z "$HEALTH_DIR" ] && _vbw_active_agent_valid_pid "$pid"; then
    vbw_active_agent_start "$PLANNING_DIR" "$input" "$role" "$pid"
    file=$(health_file_for "$input" "$key" "$pid")
  fi
  printf '%s' "$file"
}

write_health_record() {
  local file="$1" pid="$2" key="$3" role="$4" team_name="$5" event="$6" artifact_path="${7:-}" now epoch pid_identity
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  epoch=$(date +%s)
  pid_identity=""
  [ -n "$pid" ] && pid_identity=$(process_start_identity "$pid")
  if [ -f "$file" ]; then
    jq --arg pid "$pid" --arg key "$key" --arg role "$role" --arg team "$team_name" --arg ts "$now" --arg event "$event" --arg artifact "$artifact_path" --arg identity "$pid_identity" --argjson epoch "$epoch" \
      '.pid=$pid | .key=$key | .role=$role | .team_name=$team | .started_at=$ts | .started_epoch=$epoch | .last_event_at=$ts | .last_event=$event | .idle_count=0 | .nudge_sent=false | .respawn_cycle_done=false
       | if $artifact != "" then .artifact_path=$artifact else . end
       | if $identity != "" then .pid_identity=$identity else . end' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    jq -n --arg pid "$pid" --arg key "$key" --arg role "$role" --arg team "$team_name" --arg ts "$now" --arg event "$event" --arg artifact "$artifact_path" --arg identity "$pid_identity" --argjson epoch "$epoch" \
      '{pid:$pid,key:$key,role:$role,team_name:$team,started_at:$ts,started_epoch:$epoch,last_event_at:$ts,last_event:$event,idle_count:0,nudge_sent:false,respawn_cycle_done:false,artifact_path:$artifact,pid_identity:$identity}' > "$file"
  fi
}

pid_identity_matches() {
  local file="$1" pid="$2" recorded current
  case "$pid" in ''|0|*[!0-9]*) return 1 ;; esac
  recorded=$(jq -r '.pid_identity // ""' "$file" 2>/dev/null)
  [ -n "$recorded" ] || return 1
  current=$(process_start_identity "$pid")
  [ -n "$current" ] && [ "$current" = "$recorded" ]
}

normalize_artifact_path() {
  local path="$1" planning_abs relative artifact_dir artifact_base
  planning_abs=$(cd "$PLANNING_DIR" 2>/dev/null && pwd -P) || return 1
  if [[ "$path" = /* ]]; then
    artifact_dir=$(cd "$(dirname "$path")" 2>/dev/null && pwd -P) || return 1
    artifact_base=$(basename "$path")
    path="$artifact_dir/$artifact_base"
  fi
  relative="${path#"$planning_abs"/}"
  if [ "$relative" != "$path" ]; then
    printf '%s' "$path"
  elif [[ "$path" = /* ]]; then
    return 1
  else
    printf '%s/%s' "$planning_abs" "${path#./}"
  fi
}

artifact_delivered() {
  local file="$1" role="$2" suffix epoch artifact mtime artifact_path
  suffix=$(artifact_suffix_for_role "$role") || return 1
  epoch=$(jq -r '.started_epoch // 0' "$file" 2>/dev/null)
  [ "$epoch" -gt 0 ] || return 1
  artifact_path=$(jq -r '.artifact_path // ""' "$file" 2>/dev/null)
  [ -n "$artifact_path" ] || return 1
  artifact=$(normalize_artifact_path "$artifact_path") || return 1
  case "$artifact" in *-"$suffix") ;; *) return 1 ;; esac
  [ -f "$artifact" ] || return 1
  if [ "$(uname -s)" = "Darwin" ]; then
    mtime=$(stat -f %m "$artifact" 2>/dev/null || echo 0)
  else
    mtime=$(stat -c %Y "$artifact" 2>/dev/null || echo 0)
  fi
  [ "$mtime" -ge "$epoch" ]
}

can_terminate_pid() {
  local target="$1" current="$$" parent
  case "$target" in ''|0|*[!0-9]*) return 1 ;; esac
  while _vbw_active_agent_valid_pid "$current" && [ "$current" -gt 1 ]; do
    [ "$current" = "$target" ] && return 1
    parent=$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ')
    [ "$parent" = "$current" ] && break
    current="$parent"
  done
  return 0
}

terminate_health_agent() {
  local file="$1" pid="$2" key="$3" reason="$4" grace
  can_terminate_pid "$pid" || return 1
  pid_identity_matches "$file" "$pid" || return 1
  kill -TERM "$pid" 2>/dev/null || true
  grace="${VBW_AGENT_STOP_GRACE_SECONDS:-2}"
  case "$grace" in ''|*[!0-9]*) grace=2 ;; esac
  [ "$grace" -eq 0 ] || sleep "$grace"
  vbw_active_agent_pid_is_live "$pid" && kill -KILL "$pid" 2>/dev/null || true
  if [ "$reason" = "artifact" ]; then rm -f "$file"; else
    jq '.pid="" | .last_event="terminate" | .nudge_sent=true | .respawn_cycle_done=true' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi
  [ -f "$SCRIPT_DIR/agent-pid-tracker.sh" ] && bash "$SCRIPT_DIR/agent-pid-tracker.sh" unregister "$pid" 2>/dev/null || true
  vbw_active_agent_rebuild_aggregate "$PLANNING_DIR" 2>/dev/null || true
  return 0
}

emit_health_context() {
  local context="$1"
  jq -n --arg event "TeammateIdle" --arg context "$context" '{hookSpecificOutput:{hookEventName:$event,additionalContext:$context}}'
}

reset_idle_streak_if_active() {
  local file="$1" input="$2" activity
  activity=$(echo "$input" | jq -r '.activity // .event // .agent_status // ""' 2>/dev/null)
  case "$activity" in
    active|activity|working|completed|task_completed)
      jq '.idle_count=0 | .nudge_sent=false | .last_event="activity"' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      ;;
  esac
}

cmd_start() {
  local input pid key role team_name key_role role_and_team health_file artifact_path
  input=$(cat)
  pid=$(extract_payload_pid "$input")
  artifact_path=$(extract_payload_artifact_path "$input")
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"; role_and_team="${key_role#*|}"
  role="${role_and_team%%|*}"; team_name="${role_and_team#*|}"
  [ -n "$key" ] || return 0
  health_file=$(prepare_health_file "$input" "$key" "$role" "$pid")
  write_health_record "$health_file" "$pid" "$key" "$role" "$team_name" start "$artifact_path"
}


artifact_suffix_for_role() {
  case "$1" in
    lead) printf 'PLAN.md' ;;
    dev) printf 'SUMMARY.md' ;;
    scout) printf 'RESEARCH.md' ;;
    qa) printf 'VERIFICATION.md' ;;
    *) return 1 ;;
  esac
}

idle_context_for() {
  local file="$1" key="$2" role="$3" pid="$4" count nudge respawn now context=""
  count=$(jq -r '.idle_count // 0' "$file" 2>/dev/null); count=$((count + 1))
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  if [ "$count" -lt 3 ]; then
    jq --arg ts "$now" --argjson count "$count" '.last_event_at=$ts | .last_event="idle" | .idle_count=$count' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  else
    nudge=$(jq -r '.nudge_sent // false' "$file" 2>/dev/null)
    respawn=$(jq -r '.respawn_cycle_done // false' "$file" 2>/dev/null)
    if [ "$nudge" != "true" ]; then
      jq --arg ts "$now" --argjson count "$count" '.last_event_at=$ts | .last_event="idle_nudge" | .idle_count=$count | .nudge_sent=true' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
      context="AGENT HEALTH: Agent $key (role=$role) appears stuck (idle_count=$count). Auto-nudge sent."
    elif [ "$respawn" != "true" ] && terminate_health_agent "$file" "$pid" "$key" idle; then
      context="AGENT HEALTH: Agent $key (role=$role) terminated after a second idle strike. Flagged for respawn."
    else
      context="AGENT HEALTH: Agent $key (role=$role) remains stuck (idle_count=$count). Auto-nudge already sent."
    fi
  fi
  printf '%s' "$context"
}

cmd_idle() {
  local input key role team_name key_role role_and_team health_file pid advisory recovery_role artifact_path
  input=$(cat)
  artifact_path=$(extract_payload_artifact_path "$input")
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"; role_and_team="${key_role#*|}"
  role="${role_and_team%%|*}"; team_name="${role_and_team#*|}"
  [ -n "$key" ] || return 0
  pid=$(extract_payload_pid "$input")
  health_file=$(prepare_health_file "$input" "$key" "$role" "$pid")
  [ -f "$health_file" ] || write_health_record "$health_file" "$pid" "$key" "$role" "$team_name" idle_bootstrap "$artifact_path"
  [ -n "$HEALTH_DIR" ] || HEALTH_DIR=$(dirname "$health_file")
  pid=$(refresh_health_pid_from_payload "$health_file" "$input") || pid=""
  [ -n "$pid" ] || pid=$(jq -r '.pid // ""' "$health_file" 2>/dev/null)
  reset_idle_streak_if_active "$health_file" "$input"
  if [ -n "$pid" ] && artifact_delivered "$health_file" "$role" && terminate_health_agent "$health_file" "$pid" "$key" artifact; then
    emit_health_context "AGENT HEALTH: Agent $key (role=$role) delivered its artifact and was terminated."
    return 0
  fi
  if [ -n "$pid" ] && ! vbw_active_agent_pid_is_live "$pid"; then
    recovery_role="$role"; [ -n "$recovery_role" ] || recovery_role="$key"
    advisory=$(orphan_recovery "$recovery_role" "$pid" "$key" "$team_name")
    emit_health_context "$advisory"
    return 0
  fi
  advisory=$(idle_context_for "$health_file" "$key" "$role" "$pid")
  emit_health_context "$advisory"
}


stop_health_record() {
  local input="$1" file="$2" key="$3" role="$4" team_name="$5" pid advisory recovery_role
  [ -f "$file" ] || return 0
  pid=$(refresh_health_pid_from_payload "$file" "$input") || pid=""
  [ -n "$pid" ] || pid=$(jq -r '.pid // ""' "$file" 2>/dev/null)
  if [ -n "$pid" ] && ! vbw_active_agent_pid_is_live "$pid"; then
    recovery_role="$role"; [ -n "$recovery_role" ] || recovery_role="$key"
    advisory=$(orphan_recovery "$recovery_role" "$pid" "$key" "$team_name")
    log_health_advisory "$advisory"
  fi
  rm -f "$file"
  vbw_active_agent_rebuild_aggregate "$PLANNING_DIR" 2>/dev/null || true
}

cmd_stop() {
  local input key role team_name key_role health_file role_and_team pid
  input=$(cat)
  key_role=$(extract_agent_key_and_role "$input")
  key="${key_role%%|*}"; role_and_team="${key_role#*|}"
  role="${role_and_team%%|*}"; team_name="${role_and_team#*|}"
  [ -n "$key" ] || return 0
  pid=$(extract_payload_pid "$input")
  health_file=$(health_file_for "$input" "$key" "$pid")
  [ -n "$HEALTH_DIR" ] || HEALTH_DIR=$(dirname "$health_file")
  stop_health_record "$input" "$health_file" "$key" "$role" "$team_name"
}

cmd_cleanup() {
  local input
  input=$(cat)
  if [ -n "$HEALTH_DIR" ]; then rm -rf "$HEALTH_DIR"; else vbw_active_agent_remove_current_session "$PLANNING_DIR" "$input"; fi
  exit 0
}


CMD="${1:-}"

case "$CMD" in
  start)
    cmd_start
    ;;
  idle)
    cmd_idle
    ;;
  stop)
    cmd_stop
    ;;
  cleanup)
    cmd_cleanup
    ;;
  *)
    echo "Usage: $0 {start|idle|stop|cleanup}" >&2
    exit 1
    ;;
esac
