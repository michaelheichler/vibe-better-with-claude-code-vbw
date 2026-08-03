#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  setup_temp_dir
  save_optional_env VBW_MODEL_CATALOG_FILE
  create_test_config
  jq '.effort = "balanced" | .model_matrix = {dev:{balanced:["resolved-dev"]},qa:{balanced:["resolved-qa"]}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  printf '%s\n' resolved-dev resolved-qa > "$TEST_TEMP_DIR/model-catalog"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/model-catalog"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  cd "$TEST_TEMP_DIR"
  jq -n '{status:"running",session_id:"session-A",correlation_id:"corr-test",effort:"balanced",plans:[]}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set execute balanced subagent
}

teardown() {
  teardown_temp_dir
  restore_optional_env VBW_MODEL_CATALOG_FILE
}

run_spawn_guard() {
  local input="$1"
  run --separate-stderr bash -c 'export CLAUDE_SESSION_ID="session-A"; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/agent-spawn-guard.sh"
}

spawn_input() {
  jq -n '{tool_name:"TaskCreate",tool_input:{name:"next",description:"spawn",subagent_type:"vbw-dev"}}'
}

@test "agent-spawn-guard blocks when session id is unresolvable" {
  printf '0\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  local input
  input=$(spawn_input)

  run bash -c 'unset CLAUDE_SESSION_ID VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"must serialize non-team TaskCreate spawns"* ]]
}

@test "agent-spawn-guard ignores aggregate count for a resolvable idle session" {
  printf '9\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  local input
  input=$(spawn_input | jq '.session_id = "session-A"')

  run bash -c 'export CLAUDE_SESSION_ID="session-A"; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 0 ]
}

@test "agent-spawn-guard preserves blocking for a resolvable active session" {
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A"
  printf '1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count"
  printf 'dev 1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-roles"
  local input
  input=$(spawn_input)
  input=$(printf '%s' "$input" | jq '.session_id = "session-A"')

  run bash -c 'export CLAUDE_SESSION_ID="session-A"; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/agent-spawn-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"must serialize non-team TaskCreate spawns"* ]]
}

@test "agent-spawn-guard overwrites a wrong VBW model" {
  local input
  input=$(spawn_input | jq '.tool_input.model = "wrong-model"')

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.model')" = "resolved-dev" ]
}

@test "agent-spawn-guard injects a missing VBW model" {
  local input
  input=$(spawn_input)

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.model')" = "resolved-dev" ]
}

@test "agent-spawn-guard leaves non-VBW spawns untouched" {
  local input
  input=$(spawn_input | jq '.tool_input.subagent_type = "other-agent" | .tool_input.model = "caller-model"')

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "agent-spawn-guard passes through when model resolution fails" {
  local input
  input=$(spawn_input | jq '.tool_input += {isolation:"worktree",model:"caller-model"}')
  rm -f "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"could not resolve model"* ]]
}

@test "agent-spawn-guard combines stripping with model injection" {
  local input
  input=$(spawn_input | jq '.tool_input += {isolation:"worktree",model:"wrong-model"}')

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.model')" = "resolved-dev" ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.isolation')" = "null" ]
}

@test "agent-spawn-guard maps qa-author to the qa model" {
  local input
  input=$(spawn_input | jq '.tool_input.subagent_type = "vbw:vbw-qa-author"')

  run_spawn_guard "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput.model')" = "resolved-qa" ]
}
