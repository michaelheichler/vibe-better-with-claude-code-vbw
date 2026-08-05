#!/usr/bin/env bats

load test_helper

status=0

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  export CLAUDE_SESSION_ID="session-main"
  write_execution_state running
  cd "$TEST_TEMP_DIR" || return 1
}

teardown() {
  teardown_temp_dir
}

write_execution_state() {
  jq -n --arg status "$1" '{status:$status,session_id:"session-main"}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
}

run_hook() {
  printf '%s' "$1" | bash "$SCRIPTS_DIR/vibe-write-guard.sh"
}

test_allows_markdown_writes() { # @test
  local input
  input=$(jq -n --arg path "$TEST_TEMP_DIR/src/notes.md" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

test_allows_planning_writes() { # @test
  local input
  input=$(jq -n --arg path "$TEST_TEMP_DIR/.vbw-planning/STATE.md" \
    '{session_id:"session-main",tool_name:"Edit",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

test_allows_agent_definition_writes() { # @test
  local input
  input=$(jq -n --arg path "$TEST_TEMP_DIR/.claude/agents/custom-agent.md" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

test_denies_exempt_symlink_to_product_file() { # @test
  local input
  mkdir -p "$TEST_TEMP_DIR/src"
  printf 'product\n' > "$TEST_TEMP_DIR/src/app.js"
  ln -s ../src/app.js "$TEST_TEMP_DIR/.vbw-planning/allowed.js"
  input=$(jq -n --arg path "$TEST_TEMP_DIR/.vbw-planning/allowed.js" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
}

test_denies_product_writes() { # @test
  input=$(jq -n --arg path "$TEST_TEMP_DIR/src/app.js" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  [[ "$output" == *"Delegate this change to a spawned agent"* ]]
}

test_denies_product_path_traversal() { # @test
  local input
  input=$(jq -n --arg path "$TEST_TEMP_DIR/.vbw-planning/../src/app.js" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  [[ "$output" == *"Delegate this change to a spawned agent"* ]]
}

test_inactive_vibe_execution_is_noop() { # @test
  local input
  write_execution_state complete
  input=$(jq -n --arg path "$TEST_TEMP_DIR/src/app.js" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

test_subagent_payload_is_noop() { # @test
  local input
  input=$(jq -n --arg path "$TEST_TEMP_DIR/src/app.js" \
    '{session_id:"session-main",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_input:{file_path:$path}}')

  run run_hook "$input"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

test_denies_symlink_cycle_in_exempt_path() { # @test
  local input
  ln -s "$TEST_TEMP_DIR/.vbw-planning/loop-b" "$TEST_TEMP_DIR/.vbw-planning/loop-a"
  ln -s "$TEST_TEMP_DIR/.vbw-planning/loop-a" "$TEST_TEMP_DIR/.vbw-planning/loop-b"
  input=$(jq -n --arg path "$TEST_TEMP_DIR/.vbw-planning/loop-a/state.json" \
    '{session_id:"session-main",tool_name:"Write",tool_input:{file_path:$path}}')

  run timeout 10 bash -c 'printf %s "$2" | bash "$1"' _ "$SCRIPTS_DIR/vibe-write-guard.sh" "$input"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  [[ "$output" == *"Delegate this change to a spawned agent"* ]]
}
