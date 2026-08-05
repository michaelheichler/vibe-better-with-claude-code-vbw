#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || exit 0
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$SCRIPT_DIR/lib/agent-manifest.sh" ] || exit 0
. "$SCRIPT_DIR/lib/agent-manifest.sh" || exit 0

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
EVIDENCE_FILE="$PLANNING_DIR/.agent-routing-evidence.jsonl"
COMMAND="${1:-}"
INPUT=$(cat 2>/dev/null || true)

case "$COMMAND" in
  start|stop|check) ;;
  *) exit 0 ;;
esac

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date
}

transcript_path() {
  printf '%s' "$INPUT" | jq -r '
    if (.agent_transcript_path? | type) == "string" then .agent_transcript_path
    elif (.agentTranscriptPath? | type) == "string" then .agentTranscriptPath
    else (.transcript_path // "") end
  ' 2>/dev/null || printf ''
}

transcript_path_field() {
  printf '%s' "$INPUT" | jq -r '
    if (.agent_transcript_path? | type) == "string" then "agent_transcript_path"
    elif (.agentTranscriptPath? | type) == "string" then "agentTranscriptPath"
    elif (.transcript_path? | type) == "string" then "transcript_path"
    else "" end
  ' 2>/dev/null || printf ''
}

agent_name() {
  printf '%s' "$INPUT" | jq -r '.agent_type // .agentType // .subagent_type // .name // .agent_name // .agentName // .tool_input.subagent_type // .tool_input.name // .agent_id // .agentId // ""' 2>/dev/null || printf ''
}

manifest_entry() {
  local name="$1" manifest
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 1
  jq -c --arg name "$name" '.agents[$name] // empty' <<< "$manifest" 2>/dev/null
}

config_hash() {
  local path="$PLANNING_DIR/config.json"
  [ -f "$path" ] || { printf 'missing'; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" 2>/dev/null | awk '{print $1}'
  else
    cksum "$path" 2>/dev/null | awk '{print $1}'
  fi
}

requested_model() {
  local entry="$1"
  printf '%s' "$INPUT" | jq -r --arg fallback "$(jq -r '.model // .spawn.model // ""' <<< "$entry" 2>/dev/null)" '.model // .tool_input.model // $fallback' 2>/dev/null || printf ''
}

requested_effort() {
  local entry="$1"
  printf '%s' "$INPUT" | jq -r --arg fallback "$(jq -r '.effort // .spawn.effort // ""' <<< "$entry" 2>/dev/null)" '.effort // .tool_input.effort // $fallback' 2>/dev/null || printf ''
}

requested_max_turns() {
  local entry="$1"
  printf '%s' "$INPUT" | jq -c --argjson fallback "$(jq -c '.max_turns // .maxTurns // .spawn.max_turns // .spawn.maxTurns // null' <<< "$entry" 2>/dev/null)" '.max_turns // .maxTurns // .tool_input.max_turns // .tool_input.maxTurns // $fallback' 2>/dev/null || printf 'null'
}

start_evidence() {
  local name entry model effort max_turns model_override effort_override started manifest updated start
  model_override=false
  effort_override=false
  [ "${CLAUDE_CODE_SUBAGENT_MODEL+x}" = x ] && model_override=true
  [ "${CLAUDE_CODE_EFFORT_LEVEL+x}" = x ] && effort_override=true

  name=$(agent_name)
  [ -n "$name" ] || return 0
  entry=$(manifest_entry "$name") || return 0
  [ -n "$entry" ] || return 0
  model=$(requested_model "$entry")
  effort=$(requested_effort "$entry")
  max_turns=$(requested_max_turns "$entry")
  started=$(now_iso)
  start=$(jq -cn \
    --arg model "$model" \
    --arg effort "$effort" \
    --arg hash "$(config_hash)" \
    --arg started "$started" \
    --argjson max_turns "$max_turns" \
    --argjson model_override "$model_override" \
    --argjson effort_override "$effort_override" \
    '{requested_model:($model | if length > 0 then . else null end), requested_effort:($effort | if length > 0 then . else null end), requested_max_turns:$max_turns, config_hash:$hash, env_override_model:$model_override, env_override_effort:$effort_override, started_at:$started}') || return 0
  manifest=$(agent_manifest_read "$PLANNING_DIR" 2>/dev/null) || return 0
  updated=$(jq -c --arg name "$name" --argjson start "$start" '.agents[$name].routing_evidence.start = $start' <<< "$manifest" 2>/dev/null) || return 0
  agent_manifest_write "$PLANNING_DIR" "$updated" >/dev/null 2>&1 || true
}

canonical_model() {
  local model="$1" alias
  alias=$(jq -r --arg model "$model" '.aliases[$model] // empty' "$SCRIPT_DIR/../config/model-pricing.json" 2>/dev/null || true)
  printf '%s' "${alias:-$model}"
}

model_verdict() {
  local expected="$1" models="$2" override="$3" canonical
  [ "$override" = true ] && { printf 'env_override'; return; }
  [ -n "$expected" ] || { printf 'unknown'; return; }
  [ "$(jq 'length' <<< "$models")" -eq 1 ] || { printf 'unknown'; return; }
  canonical=$(canonical_model "$expected")
  if jq -e --arg expected "$canonical" '.[0] == $expected or (.[0] | startswith($expected + "-"))' <<< "$models" >/dev/null 2>&1; then
    printf 'pass'
  else
    printf 'mismatch'
  fi
}

effort_verdict() {
  local expected="$1" efforts="$2" override="$3"
  [ "$override" = true ] && { printf 'env_override'; return; }
  [ -n "$expected" ] || { printf 'unknown'; return; }
  [ "$(jq 'length' <<< "$efforts")" -eq 1 ] || { printf 'unknown'; return; }
  jq -e --arg expected "$expected" '.[0] == $expected' <<< "$efforts" >/dev/null 2>&1 && printf 'pass' || printf 'mismatch'
}

read_transcript_evidence() {
  local transcript="$1" models='[]' efforts='[]'
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    models=$(jq -s '[.[] | select(.type == "assistant") | .message.model? | strings] | unique' "$transcript" 2>/dev/null || printf '[]')
    efforts=$(jq -s '[.[] | paths(scalars) as $path | select($path[-1] == "effort") | getpath($path) | select(type == "string" or type == "number") | tostring] | unique' "$transcript" 2>/dev/null || printf '[]')
  fi
  jq -cn --argjson models "$models" --argjson efforts "$efforts" '{models:$models,efforts:$efforts}'
}

build_evidence_record() {
  local name="$1" agent_id="$2" transcript="$3" path_field="$4" start="$5" models="$6" efforts="$7" model_verdict_value="$8" effort_verdict_value="$9"
  jq -cn \
    --arg timestamp "$(now_iso)" \
    --arg name "$name" \
    --arg agent_id "$agent_id" \
    --arg transcript "$transcript" \
    --arg transcript_field "$path_field" \
    --argjson start "$start" \
    --argjson models "$models" \
    --argjson efforts "$efforts" \
    --arg model_verdict "$model_verdict_value" \
    --arg effort_verdict "$effort_verdict_value" \
    '{timestamp:$timestamp,name:$name,agent_id:($agent_id | if length > 0 then . else null end),transcript_path:($transcript | if length > 0 then . else null end),transcript_path_field:($transcript_field | if length > 0 then . else null end),requested:$start,observed:{models:$models,efforts:$efforts},verdict:{model:$model_verdict,effort:$effort_verdict}}'
}

stop_evidence() {
  local name entry start transcript path_field observed models efforts model_verdict_value effort_verdict_value record agent_id
  name=$(agent_name)
  [ -n "$name" ] || return 0
  entry=$(manifest_entry "$name") || return 0
  [ -n "$entry" ] || return 0
  start=$(jq -c '.routing_evidence.start // {}' <<< "$entry" 2>/dev/null) || start='{}'
  transcript=$(transcript_path)
  path_field=$(transcript_path_field)
  observed=$(read_transcript_evidence "$transcript") || observed='{"models":[],"efforts":[]}'
  models=$(jq -c '.models' <<< "$observed")
  efforts=$(jq -c '.efforts' <<< "$observed")
  model_verdict_value=$(model_verdict "$(jq -r '.requested_model // empty' <<< "$start")" "$models" "$(jq -r '.env_override_model // false' <<< "$start")")
  effort_verdict_value=$(effort_verdict "$(jq -r '.requested_effort // empty' <<< "$start")" "$efforts" "$(jq -r '.env_override_effort // false' <<< "$start")")
  agent_id=$(printf '%s' "$INPUT" | jq -r '.agent_id // .agentId // ""' 2>/dev/null || true)
  record=$(build_evidence_record "$name" "$agent_id" "$transcript" "$path_field" "$start" "$models" "$efforts" "$model_verdict_value" "$effort_verdict_value") || return 0
  mkdir -p "$PLANNING_DIR" 2>/dev/null || return 0
  printf '%s\n' "$record" >> "$EVIDENCE_FILE" 2>/dev/null || true
  case "$model_verdict_value:$effort_verdict_value" in
    mismatch:*|*:mismatch)
      jq -cn --arg context "Agent routing evidence mismatch for $name. Model=$model_verdict_value, effort=$effort_verdict_value." '{hookSpecificOutput:{hookEventName:"SubagentStop",additionalContext:$context}}'
      ;;
  esac
}
parse_epoch() {
  local value="$1" parsed
  case "$value" in ''|*[!0-9]*) ;; *) printf '%s' "$value"; return 0 ;; esac
  if [ "$(uname)" = Darwin ]; then
    parsed=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$value" +%s 2>/dev/null || true)
  else
    parsed=$(date -u -d "$value" +%s 2>/dev/null || true)
  fi
  printf '%s' "$parsed"
}

check_evidence() {
  local limit="${2:-5}" records model_count effort_count now stale=0 name last epoch age
  if [ ! -s "$EVIDENCE_FILE" ]; then
    printf 'Agent routing evidence: no records.\n'
    return 0
  fi
  records=$(jq -s '.' "$EVIDENCE_FILE" 2>/dev/null || printf '[]')
  printf 'Agent routing evidence: %s records\n' "$(jq 'length' <<< "$records")"
  for verdict in pass mismatch env_override unknown; do
    model_count=$(jq --arg verdict "$verdict" '[.[] | select(.verdict.model == $verdict)] | length' <<< "$records")
    effort_count=$(jq --arg verdict "$verdict" '[.[] | select(.verdict.effort == $verdict)] | length' <<< "$records")
    printf '  %-12s model=%s effort=%s\n' "$verdict" "$model_count" "$effort_count"
  done
  printf 'Recent:\n'
  jq -r --argjson limit "$limit" '.[-($limit):][] | "  \(.timestamp) \(.name) model=\(.verdict.model) effort=\(.verdict.effort)"' <<< "$records"
  now=$(date +%s 2>/dev/null || printf '0')
  if [ -f "$PLANNING_DIR/.agent-manifest.json" ]; then
    while IFS=$'\t' read -r name last; do
      epoch=$(parse_epoch "$last")
      case "$epoch" in ''|*[!0-9]*) continue ;; esac
      age=$((now - epoch))
      [ "$age" -ge 600 ] && stale=$((stale + 1))
    done < <(agent_manifest_read "$PLANNING_DIR" 2>/dev/null | jq -r '.agents | to_entries[] | select(.value.state == "running") | [.key, (.value.last_activity_at // .value.started_at // .value.created_at // "")] | @tsv')
  fi
  printf '  stale running entries=%s\n' "$stale"
}

case "$COMMAND" in
  start) start_evidence ;;
  stop) stop_evidence ;;
  check) check_evidence "${2:-5}" ;;
esac
exit 0
