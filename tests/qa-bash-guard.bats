#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A"
  printf '1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count"
  printf 'scout 1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-roles"
  printf 'scout\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "bash-guard treats payload without agent fields as orchestrator" {
  local input
  input=$(jq -n '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body ok"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 0 ]
}

@test "bash-guard classifies explicit Scout payload" {
  local field identity input
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/.active-agents"

  for field in agent_type agent_id; do
    identity="vbw:vbw-scout"
    [ "$field" = "agent_id" ] && identity="scout-01"
    input=$(jq -n --arg field "$field" --arg identity "$identity" \
      '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body blocked"}} + {($field):$identity}')

    run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/bash-guard.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"mutating gh command"* ]]
  done
}

@test "bash-guard child caller does not inherit stale Scout marker" {
  local input
  input=$(jq -n '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body ok"}}')

  run bash -c 'CLAUDE_CODE_CHILD_SESSION=1; unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 0 ]
}
