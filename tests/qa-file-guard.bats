#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  cd "$TEST_TEMP_DIR"
  MARKER_SESSION_A="qa-$(basename "$TEST_TEMP_DIR")-a"
  MARKER_SESSION_B="qa-$(basename "$TEST_TEMP_DIR")-b"
  MARKER_A="/tmp/.vbw-orchestrator-instance-${MARKER_SESSION_A}"
  MARKER_B="/tmp/.vbw-orchestrator-instance-${MARKER_SESSION_B}"
}

teardown() {
  rm -f "$MARKER_A" "$MARKER_B"
  teardown_temp_dir
}

@test "session-start writes distinct orchestrator markers per session" {
  local first second
  rm -f "$MARKER_A" "$MARKER_B"

  run bash -c "printf '%s\n' '{\"session_id\":\"$MARKER_SESSION_A\"}' | CLAUDE_CONFIG_DIR='$TEST_TEMP_DIR/claude' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  [ -s "$MARKER_A" ]
  first=$(cat "$MARKER_A")

  run bash -c "printf '%s\n' '{\"session_id\":\"$MARKER_SESSION_B\"}' | CLAUDE_CONFIG_DIR='$TEST_TEMP_DIR/claude' bash '$SCRIPTS_DIR/session-start.sh'"
  [ "$status" -eq 0 ]
  [ -s "$MARKER_B" ]
  second=$(cat "$MARKER_B")
  [ "$first" != "$second" ]
}

@test "bash-guard recognizes marker-backed orchestrator payload" {
  run bash -c 'source "$1"; vbw_orchestrator_write_marker "$2"' _ \
    "$PROJECT_ROOT/scripts/lib/orchestrator-identity.sh" "$MARKER_SESSION_A"
  [ "$status" -eq 0 ]
  local input
  input=$(jq -n --arg sid "$MARKER_SESSION_A" '{session_id:$sid,tool_input:{command:"rm -rf build/"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 0 ]
  [[ "$output" != *"unrecognized agent evidence"* ]]
}

@test "bash-guard fails loud for unrecognized agent evidence" {
  local input
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:unknown",agent_id:"mystery",tool_input:{command:"git status"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unrecognized agent evidence"* ]]
}

@test "file-guard blocks payload-identified Dev outside its worktree" {

  local worktree input
  worktree="$TEST_TEMP_DIR/.vbw-worktrees/dev-1"
  mkdir -p "$worktree" "$TEST_TEMP_DIR/src"
  jq --arg path "$worktree" '.worktree_isolation = "on"' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.agent-worktrees"
  jq -n --arg path "$worktree" '{worktree_path:$path}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.agent-worktrees/dev-1.json"
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-dev",agent_id:"dev-1",tool_name:"Write",tool_input:{file_path:"src/product.js",content:"blocked"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; export VBW_AGENT_NAME=vbw-dev-1; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"outside worktree boundary"* ]]
}

@test "file-guard fails loud for unrecognized agent evidence" {
  local input
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:unknown",agent_id:"mystery",tool_name:"Write",tool_input:{file_path:"src/product.js",content:"blocked"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unrecognized agent evidence"* ]]
}

@test "file-guard keeps payload-less calls unrestricted without a marker" {
  rm -f "$MARKER_A"
  local input
  input=$(jq -n --arg sid "$MARKER_SESSION_A" '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"src/product.js",content:"ok"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 0 ]
}
