#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
RESULT="$ROOT/testing/.gate-agent-generation-result.json"
SANDBOX_ROOT=""
RUN_ROOT=""
CONFIG_DIR=""
PROJECT_LOG_DIR=""
SANDBOX=""
HOOK_FIRED_FILE=""
REAL_CONFIG=false
MODE="isolated"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$ROOT}"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLAUDE_VERSION="$(claude --version 2>/dev/null || true)"
ERRORS_FILE=""

if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "--real-config" ]; }; then
  printf 'usage: %s [--real-config]\n' "$0" >&2
  exit 2
fi
if [ "${1:-}" = "--real-config" ]; then
  REAL_CONFIG=true
  MODE="real-config"
fi

progress() {
  printf '[gate] %s\n' "$*" >&2
}

cleanup() {
  if [ -n "$SANDBOX_ROOT" ]; then
    rm -rf "$SANDBOX_ROOT"
  fi
}
trap cleanup EXIT

record_error() {
  local probe="$1"
  local status="$2"
  local output_file="$3"
  local error_file="$4"
  local result_text=""
  local stderr_text=""

  result_text=$(jq -r '.result // .terminal_reason // empty' "$output_file" 2>/dev/null || true)
  stderr_text=$(tr '\n' ' ' < "$error_file" 2>/dev/null || true)
  if [ "$status" -ne 0 ] || [ -n "$result_text" ] || [ -n "$stderr_text" ]; then
    jq -n \
      --arg probe "$probe" \
      --arg status "$status" \
      --arg result "$result_text" \
      --arg stderr "$stderr_text" \
      '{probe:$probe,status:($status|tonumber),result:($result | if length > 0 then . else null end),stderr:($stderr | if length > 0 then . else null end)}' \
      >> "$ERRORS_FILE"
  fi
}

find_main_transcript() {
  local session_id="$1"
  if [ -z "$session_id" ]; then
    return 0
  fi
  if [ "$REAL_CONFIG" = true ]; then
    find "$CONFIG_DIR/projects" -type f -name "${session_id}.jsonl" -print 2>/dev/null | sort | head -1
  else
    find "$PROJECT_LOG_DIR" -type f -name "${session_id}.jsonl" -print 2>/dev/null | sort | head -1
  fi
}

find_agent_transcripts() {
  local session_id="$1"
  if [ -z "$session_id" ]; then
    return 0
  fi
  find "$PROJECT_LOG_DIR" -type f -path "*/${session_id}/subagents/agent-*.jsonl" -print 2>/dev/null | sort
}

invoke_claude() {
  local repo="$1"
  local prompt="$2"
  local plugin_root="$3"
  local output_file="$4"
  local error_file="$5"
  local -a args

  if [ "$REAL_CONFIG" = true ]; then
    args=(-p "$prompt" --output-format json --model sonnet --dangerously-skip-permissions)
  else
    args=(-p "$prompt" --output-format json --model sonnet --dangerously-skip-permissions)
  fi
  if [ -n "$plugin_root" ]; then
    args+=(--plugin-dir "$plugin_root")
  fi
  if (
    cd "$repo"
    unset CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_MODEL
    unset ANTHROPIC_MODEL ANTHROPIC_SMALL_FAST_MODEL
    if [ "$REAL_CONFIG" = true ]; then
      claude "${args[@]}"
    else
      CLAUDE_CONFIG_DIR="$CONFIG_DIR" claude "${args[@]}"
    fi
  ) > "$output_file" 2> "$error_file"; then
    return 0
  fi
  return $?
}

run_session() {
  local label="$1"
  local repo="$2"
  local prompt="$3"
  local plugin_root="${4:-}"
  local output_file="$RUN_ROOT/${label}.json"
  local error_file="$RUN_ROOT/${label}.stderr"
  local files_file="$RUN_ROOT/${label}.files"
  local session_id
  local main_file
  local status

  progress "running ${label}"
  if invoke_claude "$repo" "$prompt" "$plugin_root" "$output_file" "$error_file"; then
    status=0
  else
    status=$?
  fi
  session_id=$(jq -r '.session_id // empty' "$output_file" 2>/dev/null || true)
  main_file=$(find_main_transcript "$session_id" || true)
  if [ "$REAL_CONFIG" = true ] && [ -n "$main_file" ]; then
    PROJECT_LOG_DIR=$(dirname "$main_file")
  fi
  find_agent_transcripts "$session_id" > "$files_file" || true
  printf '%s\n' "$main_file" > "$RUN_ROOT/${label}.main"
  record_error "$label" "$status" "$output_file" "$error_file"
  progress "${label} exited ${status}, session ${session_id:-unavailable}"
  printf '%s\n' "$main_file"
}

write_agent() {
  local path="$1"
  local name="$2"
  local model="$3"
  local effort="$4"
  local marker="$5"

  cat > "$path" <<EOF
---
name: $name
description: A deterministic gate probe agent.
tools: []
model: $model
effort: $effort
---
Reply with exactly $marker.
EOF
}

marker_records() {
  local label="$1"
  local marker="$2"
  local files_file="$RUN_ROOT/${label}.files"
  local -a files=()

  if [ ! -s "$files_file" ]; then
    printf '[]\n'
    return 0
  fi
  mapfile -t files < "$files_file"
  if [ "${#files[@]}" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi
  jq -s --arg marker "$marker" '
    def field($name): [paths(scalars) as $path | select($path[-1] == $name) | getpath($path)] | first // null;
    [.[]
      | select(.type == "assistant")
      | select(any(.. | strings; contains($marker)))
      | {model: field("model"), effort: field("effort")}
    ] | unique
  ' "${files[@]}" 2>/dev/null || printf '[]\n'
}

marker_seen() {
  local records
  records=$(marker_records "$1" "$2")
  [ "$(jq 'length' <<< "$records")" -gt 0 ]
}

transcript_has_marker() {
  local label="$1"
  local marker="$2"
  local files_file="$RUN_ROOT/${label}.files"
  local -a files=()

  if [ ! -s "$files_file" ]; then
    return 1
  fi
  mapfile -t files < "$files_file"
  [ "${#files[@]}" -gt 0 ] || return 1
  jq -s -e --arg marker "$marker" '[.[] | select(.type == "assistant") | select(any(.. | strings; contains($marker)))] | length > 0' "${files[@]}" >/dev/null 2>/dev/null
}

marker_models() {
  local records
  records=$(marker_records "$1" "$2")
  jq -c '[.[].model | select(. != null)] | unique' <<< "$records"
}

marker_efforts() {
  local records
  records=$(marker_records "$1" "$2")
  jq -c '[.[].effort | select(. != null)] | unique' <<< "$records"
}

verdict_for_marker() {
  if marker_seen "$1" "$2"; then
    printf 'true'
  elif [ -s "$RUN_ROOT/$1.files" ] || [ -s "$RUN_ROOT/$1.main" ]; then
    printf 'false'
  else
    printf 'indeterminate'
  fi
}

verdict_for_marker_value() {
  local label="$1"
  local marker="$2"
  local field="$3"
  local expected="$4"
  local values
  if [ ! -s "$RUN_ROOT/$label.files" ]; then
    [ -s "$RUN_ROOT/$label.main" ] && printf 'false' || printf 'indeterminate'
    return 0
  fi
  if ! marker_seen "$label" "$marker"; then
    printf 'false'
    return 0
  fi
  if [ "$field" = model ]; then
    values=$(marker_models "$label" "$marker")
  else
    values=$(marker_efforts "$label" "$marker")
  fi
  if [ "$(jq 'length' <<< "$values")" -eq 0 ]; then
    printf 'indeterminate'
  elif jq -e --arg expected "$expected" 'index($expected) != null' <<< "$values" >/dev/null; then
    printf 'true'
  else
    printf 'false'
  fi
}

verdict_for_transcript_marker() {
  if transcript_has_marker "$1" "$2"; then
    printf 'true'
  elif [ -s "$RUN_ROOT/$1.files" ]; then
    printf 'false'
  else
    printf 'indeterminate'
  fi
}

discover_evidence_paths() {
  local -a files=()
  mapfile -t files < <(find "$PROJECT_LOG_DIR" -type f -path '*/subagents/agent-*.jsonl' -print 2>/dev/null | sort)
  if [ "${#files[@]}" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi
  jq -s '[.[] | paths(scalars) as $path | select(($path[-1] == "model") or ($path[-1] == "effort")) | ("." + ($path | map(tostring) | join(".")))] | unique' "${files[@]}" 2>/dev/null || printf '[]\n'
}

main_task_inputs() {
  local main_file="$1"
  if [ -z "$main_file" ] || [ ! -s "$main_file" ]; then
    printf '[]\n'
    return 0
  fi
  jq -s '[.[] | .. | objects | select(.type? == "tool_use" and (.name? == "Task" or .name? == "Agent")) | .input] | unique' "$main_file" 2>/dev/null || printf '[]\n'
}

task_inputs_for_agent() {
  local main_file="$1"
  local agent_name="$2"
  local inputs
  inputs=$(main_task_inputs "$main_file")
  jq -c --arg name "$agent_name" '[.[] | select((.subagent_type // .name // "") == $name)]' <<< "$inputs"
}

write_hook() {
  local hook="$SANDBOX_ROOT/rewrite-hook.sh"
  local marker="$SANDBOX_ROOT/rewrite-hook-fired"
  local marker_q
  printf -v marker_q '%q' "$marker"
  HOOK_FIRED_FILE="$marker"
  cat > "$hook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
: > $marker_q
jq -c '.tool_input + {subagent_type:"probe-rewrite"} | {hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:.}}'
EOF
  chmod +x "$hook"
  jq -n --arg command "$hook" \
    '{hooks:{PreToolUse:[{matcher:"Task|Agent",hooks:[{type:"command",command:$command}]}]}}' \
    > "$SANDBOX/.claude/settings.json"
}

hook_fired_verdict() {
  if [ -f "$HOOK_FIRED_FILE" ]; then
    printf 'true'
  else
    printf 'indeterminate'
  fi
}

rewrite_verdict() {
  local hook_fired="$1"
  if [ "$hook_fired" = true ]; then
    verdict_for_marker "rewrite-ordering" "GATE_REWRITE_OK"
  else
    printf 'indeterminate'
  fi
}

make_sandbox() {
  local sandbox_root run_root config_dir sandbox errors_file encoded_sandbox

  sandbox_root=$(mktemp -d)
  run_root="$sandbox_root/run"
  if [ "$REAL_CONFIG" = true ]; then
    source "$ROOT/scripts/resolve-claude-dir.sh"
    config_dir="$CLAUDE_DIR"
  else
    config_dir="$sandbox_root/config"
  fi
  sandbox="$sandbox_root/repo"
  mkdir -p "$run_root" "$sandbox/.claude/agents"
  if [ "$REAL_CONFIG" != true ]; then
    mkdir -p "$config_dir"
  fi
  errors_file="$run_root/errors.jsonl"
  : > "$errors_file"
  git -C "$sandbox" init -q
  encoded_sandbox="${sandbox//\//-}"
  printf -v SANDBOX_ROOT '%s' "$sandbox_root"
  printf -v RUN_ROOT '%s' "$run_root"
  printf -v CONFIG_DIR '%s' "$config_dir"
  printf -v PROJECT_LOG_DIR '%s' "$config_dir/projects/$encoded_sandbox"
  printf -v SANDBOX '%s' "$sandbox"
  printf -v ERRORS_FILE '%s' "$errors_file"
}

make_sandbox
progress "Claude ${CLAUDE_VERSION:-unavailable}"
progress "sandbox ${SANDBOX}"

write_agent \
  "$SANDBOX/.claude/agents/probe-preloaded.md" \
  "probe-preloaded" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_PRELOADED_OK"

load_prompt=$(cat <<'EOF'
Use Bash to create "$PWD/.claude/agents/probe-mid.md" with exactly this content:
---
name: probe-mid
description: A deterministic gate probe agent.
tools: []
model: claude-haiku-4-5-20251001
effort: low
---
Reply with exactly GATE_MID_OK.
Then immediately use the Agent tool exactly once with subagent_type probe-mid and prompt Reply exactly GATE_MID_OK. Do not answer until the Agent call returns.
EOF
)
run_session "load-mid" "$SANDBOX" "$load_prompt" >/dev/null
load_mid_verdict=$(verdict_for_marker "load-mid" "GATE_MID_OK")

fallback_prompt='Use the Agent tool exactly once with subagent_type probe-preloaded and prompt Reply exactly GATE_PRELOADED_OK. Do not answer until the Agent call returns.'
run_session "load-preloaded" "$SANDBOX" "$fallback_prompt" >/dev/null
load_preloaded_verdict=$(verdict_for_marker "load-preloaded" "GATE_PRELOADED_OK")

write_agent \
  "$SANDBOX/.claude/agents/probe-model.md" \
  "probe-model" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_MODEL_OK"
write_agent \
  "$SANDBOX/.claude/agents/probe-effort-low.md" \
  "probe-effort-low" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_EFFORT_LOW_OK"
write_agent \
  "$SANDBOX/.claude/agents/probe-tool-effort.md" \
  "probe-tool-effort" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_TOOL_EFFORT_OK"

frontmatter_prompt=$(cat <<'EOF'
Use the Agent tool exactly three times, sequentially, with these inputs and no other Agent calls:
1. subagent_type probe-model, prompt Reply exactly GATE_MODEL_OK.
2. subagent_type probe-effort-low, prompt Reply exactly GATE_EFFORT_LOW_OK.
3. subagent_type probe-tool-effort, effort high, prompt Reply exactly GATE_TOOL_EFFORT_OK.
Do not answer until all three Agent calls return.
EOF
)
frontmatter_main=$(run_session "frontmatter" "$SANDBOX" "$frontmatter_prompt")
model_verdict=$(verdict_for_marker_value "frontmatter" "GATE_MODEL_OK" model "claude-haiku-4-5-20251001")
model_values=$(marker_models "frontmatter" "GATE_MODEL_OK")
effort_verdict=$(verdict_for_marker_value "frontmatter" "GATE_EFFORT_LOW_OK" effort low)
effort_values=$(marker_efforts "frontmatter" "GATE_EFFORT_LOW_OK")
tool_effort_verdict="indeterminate"
tool_effort_inputs=$(task_inputs_for_agent "$frontmatter_main" "probe-tool-effort")
tool_effort_input_value=$(jq -r '.[0].effort // empty' <<< "$tool_effort_inputs")
tool_effort_values=$(marker_efforts "frontmatter" "GATE_TOOL_EFFORT_OK")
if [ -n "$tool_effort_input_value" ] && [ "$(jq 'length' <<< "$tool_effort_values")" -gt 0 ]; then
  if jq -e --arg value "$tool_effort_input_value" 'index($value) != null and $value == "high"' <<< "$tool_effort_values" >/dev/null; then
    tool_effort_verdict="true"
  else
    tool_effort_verdict="false"
  fi
elif [ "$(jq 'length' <<< "$tool_effort_values")" -gt 0 ]; then
  tool_effort_verdict="false"
fi

write_agent \
  "$SANDBOX/.claude/agents/vbw-dev-probe.md" \
  "vbw-dev-probe" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_BARE_NAME_OK"

names_prompt=$(cat <<'EOF'
Use the Agent tool exactly twice, sequentially, with these inputs:
1. subagent_type vbw-dev-probe, prompt Reply exactly GATE_BARE_NAME_OK.
2. subagent_type vbw:vbw-dev, prompt Reply exactly GATE_NAMESPACED_OK.
Do not answer until both Agent calls return.
EOF
)
run_session "bare-names" "$SANDBOX" "$names_prompt" "$PLUGIN_ROOT" >/dev/null
bare_verdict=$(verdict_for_marker "bare-names" "GATE_BARE_NAME_OK")
namespaced_verdict=$(verdict_for_transcript_marker "bare-names" "GATE_NAMESPACED_OK")

write_agent \
  "$SANDBOX/.claude/agents/probe-rewrite.md" \
  "probe-rewrite" \
  "claude-haiku-4-5-20251001" \
  "low" \
  "GATE_REWRITE_OK"
write_hook
rewrite_prompt='Use the Agent tool exactly once with subagent_type decoy-probe and prompt Reply exactly GATE_REWRITE_OK. Do not answer until the Agent call returns.'
rewrite_main=$(run_session "rewrite-ordering" "$SANDBOX" "$rewrite_prompt")
rewrite_hook_fired=$(hook_fired_verdict)
rewrite_verdict=$(rewrite_verdict "$rewrite_hook_fired")
rewrite_inputs=$(task_inputs_for_agent "$rewrite_main" "decoy-probe")
rewrite_real_inputs=$(task_inputs_for_agent "$rewrite_main" "probe-rewrite")
evidence_field_paths=$(discover_evidence_paths)

jq -n \
  --arg schema_version "1" \
  --arg mode "$MODE" \
  --arg claude_version "$CLAUDE_VERSION" \
  --arg started_at "$STARTED_AT" \
  --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project_log_dir "$PROJECT_LOG_DIR" \
  --arg sandbox_removed "true" \
  --arg mid_session_loaded "$load_mid_verdict" \
  --arg pre_session_loaded "$load_preloaded_verdict" \
  --arg frontmatter_model_honored "$model_verdict" \
  --arg frontmatter_effort_honored "$effort_verdict" \
  --arg tool_input_effort_honored "$tool_effort_verdict" \
  --arg bare_name_ok "$bare_verdict" \
  --arg namespaced_ok "$namespaced_verdict" \
  --arg updated_input_rewrite_effective "$rewrite_verdict" \
  --arg rewrite_hook_fired "$rewrite_hook_fired" \
  --arg hook_marker "$HOOK_FIRED_FILE" \
  --argjson real_config "$REAL_CONFIG" \
  --argjson model_values "$model_values" \
  --argjson effort_values "$effort_values" \
  --arg tool_input_effort_value "$tool_effort_input_value" \
  --argjson tool_effort_inputs "$tool_effort_inputs" \
  --argjson tool_effort_values "$tool_effort_values" \
  --argjson rewrite_decoy_inputs "$rewrite_inputs" \
  --argjson rewrite_real_inputs "$rewrite_real_inputs" \
  --argjson errors "$(jq -s '.' "$ERRORS_FILE")" \
  --argjson evidence_field_paths "$evidence_field_paths" \
  '{
    schema_version: ($schema_version | tonumber),
    mode: $mode,
    claude_version: $claude_version,
    started_at: $started_at,
    finished_at: $finished_at,
    sandbox_removed: ($sandbox_removed == "true"),
    transcript_project_dir: $project_log_dir,
    caveats: {
      global_user_hooks: $real_config,
      note: (if $real_config then "Real-config mode runs with global user hooks, including rtk rewriting." else null end)
    },
    probes: {
      load_timing: {
        mode: $mode,
        mid_session_loaded: $mid_session_loaded,
        pre_session_loaded: $pre_session_loaded
      },
      frontmatter_honored: {
        mode: $mode,
        frontmatter_model_honored: $frontmatter_model_honored,
        frontmatter_effort_honored: $frontmatter_effort_honored,
        tool_input_effort_honored: $tool_input_effort_honored,
        observed_model_values: $model_values,
        observed_effort_values: $effort_values,
        tool_input_effort_value: ($tool_input_effort_value | if length > 0 then . else null end),
        tool_input_task_inputs: $tool_effort_inputs,
        observed_tool_effort_values: $tool_effort_values
      },
      bare_name_spawn: {
        mode: $mode,
        bare_name_ok: $bare_name_ok,
        namespaced_ok: $namespaced_ok
      },
      rewrite_ordering: {
        mode: $mode,
        updated_input_rewrite_effective: $updated_input_rewrite_effective,
        hook_fired: $rewrite_hook_fired,
        hook_marker: $hook_marker,
        decoy_task_inputs: $rewrite_decoy_inputs,
        rewritten_task_inputs: $rewrite_real_inputs
      }
    },
    verdict_modes: {
      "load_timing.mid_session_loaded": $mode,
      "load_timing.pre_session_loaded": $mode,
      "frontmatter_honored.frontmatter_model_honored": $mode,
      "frontmatter_honored.frontmatter_effort_honored": $mode,
      "frontmatter_honored.tool_input_effort_honored": $mode,
      "bare_name_spawn.bare_name_ok": $mode,
      "bare_name_spawn.namespaced_ok": $mode,
      "rewrite_ordering.updated_input_rewrite_effective": $mode
    },
    evidence: {
      jq_field_paths: $evidence_field_paths,
      candidate_jq_field_paths: [".effort", ".message.effort", ".message.model", ".model"],
      model_path: ([$evidence_field_paths[] | select(endswith(".model"))] | first // null),
      effort_path: ([$evidence_field_paths[] | select(endswith(".effort"))] | first // null)
    },
    errors: $errors
  }' | tee "$RESULT"
progress "result written to ${RESULT}"
