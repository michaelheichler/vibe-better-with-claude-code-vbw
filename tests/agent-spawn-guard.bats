#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  cd "$TEST_TEMP_DIR"
  jq -n '{status:"running",session_id:"session-A",correlation_id:"corr-test",effort:"balanced",plans:[]}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set execute balanced subagent
}

teardown() {
  teardown_temp_dir
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
