#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export CLAUDE_SESSION_ID=""
}

teardown() {
  unset CLAUDE_SESSION_ID
  teardown_temp_dir
}

@test "current role rejects stale marker when session role count is zero" {
  local session_id="session-stale"
  mkdir -p "$PLANNING_DIR/.active-agents/$session_id"
  printf '0\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent-count"
  printf 'scout 0\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent-roles"
  printf 'scout\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{\"session_id\":\"session-stale\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"

  [ "$status" -eq 1 ]
}

@test "current role fails closed when session id is unresolvable" {
  printf 'scout\n' > "$PLANNING_DIR/.active-agent"
  local stderr_file="$TEST_TEMP_DIR/stderr"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{}" 2>"$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$stderr_file"

  [ "$status" -eq 1 ]
  [ "$(cat "$stderr_file")" = "session_id unresolvable, role detection skipped (fail-closed)" ]
}
