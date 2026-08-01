#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set fix balanced subagent
}

teardown() {
  teardown_temp_dir
}

@test "status-json ignores marker from another session" {
  run bash -c 'CLAUDE_SESSION_ID="session-B" VBW_PLANNING_DIR="$1" bash "$2" status-json' _ \
    "$TEST_TEMP_DIR/.vbw-planning" "$SCRIPTS_DIR/delegated-workflow.sh"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.live')" = "false" ]
  [ "$(printf '%s' "$output" | jq -r '.reason')" = "session_mismatch" ]
}

@test "status-json preserves marker behavior without caller session" {
  run bash -c 'unset CLAUDE_SESSION_ID; VBW_PLANNING_DIR="$1" bash "$2" status-json' _ \
    "$TEST_TEMP_DIR/.vbw-planning" "$SCRIPTS_DIR/delegated-workflow.sh"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.live')" = "true" ]
  [ "$(printf '%s' "$output" | jq -r '.reason')" = "ok" ]
}
