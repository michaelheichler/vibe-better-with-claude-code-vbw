#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases" "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A"
  printf '1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count"
  printf 'scout 1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-roles"
  printf 'scout\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "file-guard treats payload without agent fields as orchestrator" {
  local input
  input=$(jq -n '{session_id:"session-A",tool_name:"Write",tool_input:{file_path:"CLAUDE.md",content:"ok"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 0 ]
}

@test "file-guard classifies explicit Scout payload" {
  local field identity input
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/.active-agents"

  for field in agent_type agent_id; do
    identity="vbw:vbw-scout"
    [ "$field" = "agent_id" ] && identity="scout-01"
    input=$(jq -n --arg field "$field" --arg identity "$identity" \
      '{session_id:"session-A",tool_name:"Write",tool_input:{file_path:"CLAUDE.md",content:"blocked"}} + {($field):$identity}')

    run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/file-guard.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"read-only outside .vbw-planning/"* ]]
  done
}

@test "file-guard ignores delegated marker from another session" {
  local input
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set fix balanced subagent
  input=$(jq -n '{session_id:"session-B",tool_name:"Write",tool_input:{file_path:"src/product.js",content:"ok"}}')

  run bash -c 'CLAUDE_SESSION_ID="session-B"; unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 0 ]
}

@test "file-guard applies delegated marker to its owning session" {
  local input
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set fix balanced subagent
  input=$(jq -n '{session_id:"session-A",tool_name:"Write",tool_input:{file_path:"src/product.js",content:"blocked"}}')

  run bash -c 'CLAUDE_SESSION_ID="session-A"; unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"orchestrator cannot write product files"* ]]
}

@test "file-guard delegated rule allows orchestrator writes outside repo" {
  local input outside_path
  outside_path="$BATS_TEST_TMPDIR/claude-plans/foo.md"
  mkdir -p "$(dirname "$outside_path")"
  CLAUDE_SESSION_ID="session-A" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set fix balanced subagent
  input=$(jq -n --arg path "$outside_path" '{session_id:"session-A",tool_name:"Write",tool_input:{file_path:$path,content:"ok"}}')

  run bash -c 'CLAUDE_SESSION_ID="session-A"; unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 0 ]
}

@test "file-guard enforces role from explicit QA payload" {
  local input
  input=$(jq -n '{session_id:"session-A",agent_type:"vbw:vbw-qa",tool_name:"Write",tool_input:{file_path:"src/product.js",content:"blocked"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/file-guard.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"role 'qa' cannot write outside .vbw-planning/"* ]]
}
