#!/usr/bin/env bats

load test_helper

setup() {
  LIVE_PIDS=()
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.contracts"
}

teardown() {
  local pid
  for pid in "${LIVE_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  teardown_temp_dir
}

create_plan_with_files() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md" << 'PLAN'
---
phase: 1
plan: 1
title: Test Plan
wave: 1
depends_on: []
files_modified:
  - src/allowed.js
tasks:
  - id: 1-1-T1
    title: Test task
    files: [src/allowed.js]
---
PLAN
}

create_contract() {
  cat > "$TEST_TEMP_DIR/.vbw-planning/.contracts/01-01.json" << 'CONTRACT'
{"phase_id":"phase-1","plan_id":"01-01","phase":1,"plan":1,"objective":"Test","task_ids":["1-1-T1"],"task_count":1,"allowed_paths":["src/allowed.js"],"forbidden_paths":[],"depends_on":[],"must_haves":["Works"],"verification_checks":[],"max_token_budget":50000,"timeout_seconds":300,"contract_hash":"abc123"}
CONTRACT
}

@test "file-guard: blocks lead from writing outside .vbw-planning/ when role isolation enabled" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/code.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=lead echo '$INPUT' | VBW_AGENT_ROLE=lead bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot write outside .vbw-planning/"* ]]
}

@test "file-guard: allows lead to write planning files" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/test.md","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=lead echo '$INPUT' | VBW_AGENT_ROLE=lead bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: blocks scout from any non-planning write" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/file.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "file-guard: payload-less orchestrator does not inherit active Scout marker" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md","content":"ok"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: payload-less orchestrator can write planning artifact while Scout is active" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/phases/01-test/01-RESEARCH.md","content":"ok"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: payload-less orchestrator ignores mixed active role set" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  cat > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" <<'EOF'
scout 1
dev 1
EOF

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"CLAUDE.md","content":"ok"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: session-local Scout marker never classifies payload-less orchestrator" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  local scout_pid
  sleep 30 >/dev/null 2>&1 & scout_pid=$!
  LIVE_PIDS+=("$scout_pid")
  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw:vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  kill -0 "$scout_pid" 2>/dev/null || fail "live scout fixture is not alive"

  for sid in session-A session-B; do
    INPUT=$(jq -n --arg sid "$sid" '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"CLAUDE.md",content:"ok"}}')
    run bash -c 'unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
    [ "$status" -eq 0 ]
  done
}

@test "file-guard: active qa marker blocks non-planning writes before delegation-guard bypass" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "qa" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  INPUT='{"agent_id":"qa-1","agent_type":"vbw:vbw-qa","tool_name":"Write","tool_input":{"file_path":"src/file.js","content":"bad"}}'
  run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot write outside .vbw-planning/"* ]]
}

@test "file-guard: active qa marker allows planning artifact writes" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "qa" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/phases/01-test/01-RESEARCH.md","content":"ok"}}'
  run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: active qa marker still allows always-exempt files, unlike scout" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "qa" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  for target in "CLAUDE.md" "STATE.md" "foo-VERIFICATION.md"; do
    INPUT=$(jq -n --arg fp "$target" '{"tool_name":"Write","tool_input":{"file_path":$fp,"content":"ok"}}')
    run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
    [ "$status" -eq 0 ]
  done
}

@test "file-guard: active QA in session A does not restrict writes in session B" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  printf '%s\n' '{"session_id":"session-A","agent_type":"vbw:vbw-qa","pid":"10102"}' | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  INPUT=$(jq -n --arg sid 'session-B' '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"src/allowed.js",content:"ok"}}')
  run bash -c 'unset VBW_AGENT_ROLE; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]

  INPUT=$(jq -n --arg sid 'session-A' '{session_id:$sid,agent_id:"qa-1",agent_type:"vbw:vbw-qa",tool_name:"Write",tool_input:{file_path:"src/allowed.js",content:"bad"}}')
  run bash -c 'unset VBW_AGENT_ROLE; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot write outside .vbw-planning/"* ]]
}

@test "file-guard: active count in session A does not bypass delegated write block in session B" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  mkdir -p src
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON
  CLAUDE_SESSION_ID="session-orchestrator" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set execute balanced subagent
  printf '%s\n' '{"session_id":"session-A","agent_type":"vbw:vbw-dev","pid":"20202"}' | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  for sid in session-A session-B; do
    INPUT=$(jq -n --arg sid "$sid" '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"src/allowed.js",content:"blocked"}}')
    run bash -c 'CLAUDE_SESSION_ID="session-orchestrator"; unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"orchestrator cannot write product files"* ]]
  done
}

@test "file-guard: active agent count never bypasses delegated orchestrator block" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  mkdir -p src
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  for sid in session-A session-B; do
    INPUT=$(jq -n --arg sid "$sid" '{session_id:$sid,tool_name:"Write",tool_input:{file_path:"src/allowed.js",content:"blocked"}}')
    run bash -c 'unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
    [ "$status" -eq 2 ]
    [[ "$output" == *"orchestrator cannot write product files"* ]]
  done
}

@test "file-guard: runtime Dev identity works when SubagentStart marker is absent" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  mkdir -p src
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON

  INPUT=$(jq -n --arg cwd "$TEST_TEMP_DIR" '{session_id:"session-A",transcript_path:($cwd + "/session.jsonl"),cwd:$cwd,hook_event_name:"PreToolUse",agent_id:"agent-123",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_use_id:"toolu-123",tool_input:{file_path:"src/allowed.js",content:"allowed"}}')
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents" ]
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]
}

@test "file-guard: agent type alone from payload classifies role and unblocks contract-scoped write" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  mkdir -p src
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON

  INPUT=$(jq -n --arg cwd "$TEST_TEMP_DIR" '{session_id:"session-A",transcript_path:($cwd + "/session.jsonl"),cwd:$cwd,hook_event_name:"PreToolUse",agent_type:"vbw:vbw-dev",tool_name:"Write",tool_use_id:"toolu-123",tool_input:{file_path:"src/allowed.js",content:"allowed"}}')
  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; printf "%s\n" "$1" | bash "$2"' _ "$INPUT" "$SCRIPTS_DIR/file-guard.sh"
  [ "$status" -eq 0 ]
}

@test "file-guard: degraded mixed-role markers do not leave stale Scout write block" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  local scout_pid dev_pid
  sleep 30 >/dev/null 2>&1 & scout_pid=$!
  LIVE_PIDS+=("$scout_pid")
  sleep 30 >/dev/null 2>&1 & dev_pid=$!
  LIVE_PIDS+=("$dev_pid")
  printf '%s\n' "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_CODE_CHILD_SESSION CLAUDE_SESSION_ID && printf '%s\\n' '{\"pid\":\"$scout_pid\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  run grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  [ "$status" -eq 0 ]
  run grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  [ "$status" -ne 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"allowed-after-degrade"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: scout env role blocks non-planning writes before phases exist" {
  cd "$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/phases"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/outside.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only outside .vbw-planning/"* ]]
}

@test "file-guard: payload-less nested orchestrator ignores Scout marker before phases exist" {
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/phases"
  mkdir -p "$TEST_TEMP_DIR/packages/app"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  cd "$TEST_TEMP_DIR/packages/app"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/outside.js","content":"ok"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: scout allows planning writes before phases exist" {
  cd "$TEST_TEMP_DIR"
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/phases"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":".vbw-planning/research.md","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: scout fails open when no VBW config or phases exist" {
  NON_VBW="$BATS_TEST_TMPDIR/non-vbw-no-config"
  mkdir -p "$NON_VBW"
  cd "$NON_VBW"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/outside.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=scout VBW_CONFIG_ROOT='$NON_VBW' echo '$INPUT' | VBW_AGENT_ROLE=scout VBW_CONFIG_ROOT='$NON_VBW' bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: allows dev to write contract-scoped files" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  create_contract
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: role isolation always enforced (v2_role_isolation graduated)" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=scout echo '$INPUT' | VBW_AGENT_ROLE=scout bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"read-only"* ]]
}

@test "file-guard: fails open when VBW_AGENT_ROLE unset" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: unfinalized plan alone does not block arbitrary writes when no execution is live" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/unrelated.js","content":"maintainer work"}}'
  run bash -c "unset VBW_AGENT_ROLE; echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: files_modified still blocks undeclared writes while execution-state is running" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/undeclared.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in active plan's files_modified"* ]]

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/allowed.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: stale execution-state does not enforce files_modified" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  cat > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json" <<'JSON'
{"phase":1,"phase_name":"test","status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}
JSON
  touch -t 202001010000 "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/undeclared.js","content":"ok"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "file-guard: live delegated-workflow marker enforces files_modified" {
  cd "$TEST_TEMP_DIR"
  create_plan_with_files
  CLAUDE_SESSION_ID="session-marker" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/delegated-workflow.sh" set fix balanced subagent

  INPUT='{"tool_name":"Write","tool_input":{"file_path":"src/undeclared.js","content":"bad"}}'
  run bash -c "VBW_AGENT_ROLE=dev echo '$INPUT' | VBW_AGENT_ROLE=dev bash '$SCRIPTS_DIR/file-guard.sh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in active plan's files_modified"* ]]
}
