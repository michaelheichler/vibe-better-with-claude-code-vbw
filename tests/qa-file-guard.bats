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

make_live_execution() {
  printf '%s\n' '{"status":"running"}' > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
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

@test "bash-guard fails loud for unrecognized agent evidence during live execution" {
  make_live_execution
  local input
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:unknown",agent_id:"mystery",tool_input:{command:"git status"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"unrecognized agent evidence"* ]]
}

@test "file-guard blocks payload-identified Dev outside its worktree" {
  make_live_execution
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

@test "file-guard fails loud for unrecognized agent evidence during live execution" {
  make_live_execution
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

@test "guards are silent outside a VBW project despite unrecognized evidence" {
  local outside input
  outside=$(mktemp -d)
  input=$(jq -n '{agent_type:"vbw:unknown",agent_id:"mystery",tool_input:{command:"rm -rf build/",file_path:"src/product.js"}}')

  run bash -c 'cd "$1" && unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$2" | bash "$3"' _ \
    "$outside" "$input" "$SCRIPTS_DIR/bash-guard.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c 'cd "$1" && unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$2" | bash "$3"' _ \
    "$outside" "$input" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$outside"
}

@test "idle VBW project logs advisory blocks without output" {
  local input
  rm -f "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" "$TEST_TEMP_DIR/.vbw-planning/.event-log.jsonl"
  input=$(jq -n '{agent_type:"vbw:unknown",agent_id:"mystery",tool_input:{command:"rm -rf build/",file_path:"src/product.js"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -s length "$TEST_TEMP_DIR/.vbw-planning/.event-log.jsonl")" -eq 1 ]
}

@test "bare payload qa does not claim the QA role" {
  local input
  input=$(jq -n '{session_id:"session-A",agent_type:"qa",tool_input:{command:"printf ok > src/file"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"
  [ "$status" -eq 0 ]

  make_live_execution
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-qa",tool_input:{command:"printf ok > src/file"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"
  [ "$status" -eq 2 ]
}

@test "active plan scope expands declared files to their directory" {
  local input
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md" <<'EOF'
---
files_modified:
  - scripts/foo.sh
---
EOF
  make_live_execution
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_input:{file_path:"scripts/bar.sh",content:"ok"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]

  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_input:{file_path:"docs/x.md",content:"blocked"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 2 ]
}

@test "contract scope expands allowed paths but keeps forbidden paths" {
  local input
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test" "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md" <<'EOF'
---
files_modified:
  - src/foo.js
---
EOF
  jq -n '{allowed_paths:["src/foo.js"],forbidden_paths:["src/secret.txt"]}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.contracts/01-01.json"
  make_live_execution
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_input:{file_path:"src/bar.js",content:"ok"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]

  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_input:{file_path:"src/secret.txt",content:"blocked"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 2 ]
}

@test "bash destructive commands are disabled outside a VBW project" {
  local outside input
  outside=$(mktemp -d)
  input=$(jq -n '{agent_type:"vbw:unknown",tool_input:{command:"rm -rf build/"}}')
  run bash -c 'cd "$1" && unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$2" | bash "$3"' _ \
    "$outside" "$input" "$SCRIPTS_DIR/bash-guard.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$outside"
}
