#!/usr/bin/env bats


load test_helper

setup() {
  LIVE_PIDS=()
  setup_temp_dir
  create_test_config

  cd "$TEST_TEMP_DIR" || return 1

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt
  git add init.txt
  git commit -q -m "chore: initial commit"

  echo "test-session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"

  rm -rf "$VBW_AGENT_PID_LOCK_DIR" 2>/dev/null || true
}

teardown() {
  local pid
  for pid in "${LIVE_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$VBW_AGENT_PID_LOCK_DIR" 2>/dev/null || true
  teardown_temp_dir
}

next_live_pid() {
  sleep 999 >/dev/null 2>&1 &
  NEXT_PID=$!
  LIVE_PIDS+=("$NEXT_PID")
}

simulate_agent_start() {
  local agent_type="$1"
  local pid="$2"
  echo "{\"agent_type\":\"$agent_type\",\"pid\":\"$pid\"}" \
    | bash "$SCRIPTS_DIR/agent-start.sh"
}

simulate_agent_stop() {
  local pid="$1"
  echo "{\"pid\":\"$pid\"}" \
    | bash "$SCRIPTS_DIR/agent-stop.sh"
}

simulate_session_stop() {
  echo '{"cost_usd":0.01,"duration_ms":5000,"tokens_in":100,"tokens_out":50,"model":"test"}' \
    | bash "$SCRIPTS_DIR/session-stop.sh"
}


@test "agent-start creates .active-agent and sets count to 1" {
  cd "$TEST_TEMP_DIR"
  local pid
  next_live_pid
  pid="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid"

  [ -f ".vbw-planning/.active-agent" ]
  [ -f ".vbw-planning/.active-agent-count" ]
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]
}

@test "two agent-starts increment count to 2" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  next_live_pid
  pid1="$NEXT_PID"
  next_live_pid
  pid2="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"

  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "2" ]
}

@test "agent-stop decrements count from 2 to 1 - markers preserved" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  next_live_pid
  pid1="$NEXT_PID"
  next_live_pid
  pid2="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"

  simulate_agent_stop "$pid1"

  [ -f ".vbw-planning/.active-agent" ]
  [ -f ".vbw-planning/.active-agent-count" ]
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]
}

@test "agent-stop decrements count from 1 to 0 - markers removed" {
  cd "$TEST_TEMP_DIR"
  local pid1
  next_live_pid
  pid1="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_stop "$pid1"

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
}

@test "two starts then two stops - all markers cleaned" {
  cd "$TEST_TEMP_DIR"
  local pid1 pid2
  next_live_pid
  pid1="$NEXT_PID"
  next_live_pid
  pid2="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-qa" "$pid2"
  simulate_agent_stop "$pid1"
  simulate_agent_stop "$pid2"

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
}

@test "agent-stop with no count file but active-agent marker - removes marker" {
  cd "$TEST_TEMP_DIR"
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "dev" > ".vbw-planning/.active-agent"

  echo "{\"pid\":\"$dead_pid\"}" | bash "$SCRIPTS_DIR/agent-stop.sh"

  [ ! -f ".vbw-planning/.active-agent" ]
}

@test "agent-stop always exits 0" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'echo "{}" | bash "'"$SCRIPTS_DIR"'/agent-stop.sh"'
  [ "$status" -eq 0 ]
}


@test "agent-start registers PID - agent-stop unregisters it" {
  cd "$TEST_TEMP_DIR"
  local pid
  next_live_pid
  pid="$NEXT_PID"

  simulate_agent_start "vbw-dev" "$pid"

  [ -f ".vbw-planning/.agent-pids" ]
  run grep "^${pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -eq 0 ]

  simulate_agent_stop "$pid"

  run grep "^${pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]
}


@test "prune removes all dead PIDs and deletes the file" {
  cd "$TEST_TEMP_DIR"
  local dead1 dead2 dead3
  dead1=$(get_dead_pid) || fail "get_dead_pid failed"
  dead2=$(get_dead_pid) || fail "get_dead_pid failed"
  dead3=$(get_dead_pid) || fail "get_dead_pid failed"
  printf '%s\n%s\n%s\n' "$dead1" "$dead2" "$dead3" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  [ ! -f ".vbw-planning/.agent-pids" ]
}

@test "prune keeps alive PIDs and removes dead ones" {
  cd "$TEST_TEMP_DIR"
  local alive_pid
  assign_live_pid alive_pid || fail "assign_live_pid failed"
  kill -0 "$alive_pid" 2>/dev/null || fail "live pid fixture is not alive"

  local dead1 dead2
  dead1=$(get_dead_pid) || fail "get_dead_pid failed"
  dead2=$(get_dead_pid) || fail "get_dead_pid failed"
  printf '%s\n%s\n%s\n' "${alive_pid}" "$dead1" "$dead2" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  [ -f ".vbw-planning/.agent-pids" ]
  run grep "^${alive_pid}$" ".vbw-planning/.agent-pids"
  [ "$status" -eq 0 ]

  run grep "^${dead1}$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]
  run grep "^${dead2}$" ".vbw-planning/.agent-pids"
  [ "$status" -ne 0 ]
}

@test "prune is a no-op when .agent-pids does not exist" {
  cd "$TEST_TEMP_DIR"
  rm -f ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]
  [ ! -f ".vbw-planning/.agent-pids" ]
}

@test "prune ignores leftover .agent-pids.tmp from interrupted prune" {
  cd "$TEST_TEMP_DIR"
  local stale_pid
  stale_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "$stale_pid" > ".vbw-planning/.agent-pids.tmp"

  local alive_pid
  assign_live_pid alive_pid || fail "assign_live_pid failed"
  kill -0 "$alive_pid" 2>/dev/null || fail "live pid fixture is not alive"

  local dead1
  dead1=$(get_dead_pid) || fail "get_dead_pid failed"
  printf '%s\n%s\n' "${alive_pid}" "$dead1" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  [ -f ".vbw-planning/.agent-pids" ]
  run cat ".vbw-planning/.agent-pids"
  [ "$output" = "$alive_pid" ]

  [ ! -f ".vbw-planning/.agent-pids.tmp" ]
}

@test "prune recovers from stale lock left by crashed process" {
  cd "$TEST_TEMP_DIR"
  local stale_lock_pid dead1 dead2
  stale_lock_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  dead1=$(get_dead_pid) || fail "get_dead_pid failed"
  dead2=$(get_dead_pid) || fail "get_dead_pid failed"
  mkdir -p "$VBW_AGENT_PID_LOCK_DIR"
  echo "$stale_lock_pid" > "$VBW_AGENT_PID_LOCK_DIR/pid"

  printf '%s\n%s\n' "$dead1" "$dead2" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  [ ! -f ".vbw-planning/.agent-pids" ]

  [ ! -d "$VBW_AGENT_PID_LOCK_DIR" ]
}

@test "prune recovers from stale lock directory with no pid file" {
  cd "$TEST_TEMP_DIR"
  local dead1 dead2
  dead1=$(get_dead_pid) || fail "get_dead_pid failed"
  dead2=$(get_dead_pid) || fail "get_dead_pid failed"
  mkdir -p "$VBW_AGENT_PID_LOCK_DIR"

  printf '%s\n%s\n' "$dead1" "$dead2" > ".vbw-planning/.agent-pids"

  run bash "$SCRIPTS_DIR/agent-pid-tracker.sh" prune
  [ "$status" -eq 0 ]

  [ ! -f ".vbw-planning/.agent-pids" ]

  [ ! -d "$VBW_AGENT_PID_LOCK_DIR" ]
}


@test "session-stop removes transient markers" {
  cd "$TEST_TEMP_DIR"
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "dev" > ".vbw-planning/.active-agent"
  echo "2" > ".vbw-planning/.active-agent-count"
  echo "scout 1" > ".vbw-planning/.active-agent-roles"
  echo "$dead_pid scout" > ".vbw-planning/.active-agent-role-pids"
  mkdir -p ".vbw-planning/.active-agent-count.lock"
  echo "$dead_pid %1" > ".vbw-planning/.agent-panes"

  simulate_session_stop

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  [ ! -f ".vbw-planning/.active-agent-roles" ]
  [ ! -f ".vbw-planning/.active-agent-role-pids" ]
  [ ! -d ".vbw-planning/.active-agent-count.lock" ]
  [ ! -f ".vbw-planning/.agent-panes" ]
}

@test "session-stop with session id removes only that session active-agent state" {
  cd "$TEST_TEMP_DIR"
  local pid_a pid_b
  next_live_pid
  pid_a="$NEXT_PID"
  next_live_pid
  pid_b="$NEXT_PID"

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$pid_a\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$pid_b\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c 'printf "%s\n" "{\"session_id\":\"session-B\",\"cost_usd\":0,\"duration_ms\":0}" | bash "$1"' _ \
    "$SCRIPTS_DIR/session-stop.sh"
  [ "$status" -eq 0 ]

  [ -d ".vbw-planning/.active-agents/session-A" ]
  [ ! -d ".vbw-planning/.active-agents/session-B" ]
  [ "$(cat ".vbw-planning/.active-agent-count")" = "1" ]
  [ "$(cat ".vbw-planning/.active-agent")" = "scout" ]
  grep -Fqx "$pid_a scout" ".vbw-planning/.active-agent-role-pids"
}

@test "session-stop preserves current active-agent state while VBW background task runs" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw:vbw-dev\",\"pid\":\"$live_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  mkdir ".vbw-planning/.active-agent-count.lock"

  local stop_input final_stop_input
  stop_input=$(jq -n --arg cwd "$TEST_TEMP_DIR" '{session_id:"session-A",transcript_path:($cwd + "/session.jsonl"),cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false,background_tasks:[{type:"subagent",agent_type:"vbw:vbw-dev"}],cost_usd:0,duration_ms:0}')
  final_stop_input=$(jq -n --arg cwd "$TEST_TEMP_DIR" '{session_id:"session-A",transcript_path:($cwd + "/session.jsonl"),cwd:$cwd,hook_event_name:"Stop",stop_hook_active:false,background_tasks:[],cost_usd:0,duration_ms:0}')
  run bash -c 'cd "$1" && printf "%s\n" "$2" | bash "$3"' _ "$TEST_TEMP_DIR" "$stop_input" "$SCRIPTS_DIR/session-stop.sh"
  [ "$status" -eq 0 ]
  [ -d ".vbw-planning/.active-agents/session-A" ]
  [ "$(cat ".vbw-planning/.active-agents/session-A/active-agent-count")" = "1" ]
  [ -d ".vbw-planning/.active-agent-count.lock" ]

  run bash -c 'cd "$1" && printf "%s\n" "$2" | bash "$3"' _ "$TEST_TEMP_DIR" "$final_stop_input" "$SCRIPTS_DIR/session-stop.sh"
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/.active-agents/session-A" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  [ ! -d ".vbw-planning/.active-agent-count.lock" ]
}

@test "tmux-watchdog detach cleanup removes stale active-agent role markers" {
  cd "$TEST_TEMP_DIR"
  local fakebin dead_pid test_input
  fakebin="$TEST_TEMP_DIR/fakebin"
  mkdir -p "$fakebin" ".vbw-planning/.active-agent-count.lock" ".vbw-planning/.compacting"

  cat > "$fakebin/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session)
    exit 0
    ;;
  list-clients)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$fakebin/tmux"

  cat > "$fakebin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fakebin/sleep"

  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "scout" > ".vbw-planning/.active-agent"
  echo "2" > ".vbw-planning/.active-agent-count"
  cat > ".vbw-planning/.active-agent-roles" <<'EOF'
scout 1
dev 1
EOF
  echo "$dead_pid scout" > ".vbw-planning/.active-agent-role-pids"
  mkdir -p ".vbw-planning/.active-agents/session-A"
  echo "scout" > ".vbw-planning/.active-agents/session-A/active-agent"
  echo "1" > ".vbw-planning/.active-agents/session-A/active-agent-count"
  echo "scout 1" > ".vbw-planning/.active-agents/session-A/active-agent-roles"
  echo "$dead_pid scout" > ".vbw-planning/.active-agents/session-A/active-agent-role-pids"
  echo "$dead_pid" > ".vbw-planning/.agent-pids"
  echo "$dead_pid %1" > ".vbw-planning/.agent-panes"
  echo "{\"pid\":$dead_pid,\"started_at\":1,\"agent_name\":\"stale\"}" > ".vbw-planning/.compacting/stale.json"

  run env PATH="$fakebin:$PATH" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/tmux-watchdog.sh" test-session
  [ "$status" -eq 0 ]

  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  [ ! -f ".vbw-planning/.active-agent-roles" ]
  [ ! -f ".vbw-planning/.active-agent-role-pids" ]
  [ ! -d ".vbw-planning/.active-agents" ]
  [ ! -d ".vbw-planning/.active-agent-count.lock" ]
  [ ! -f ".vbw-planning/.agent-pids" ]
  [ ! -f ".vbw-planning/.agent-panes" ]
  [ ! -d ".vbw-planning/.compacting" ]
  [ -f ".vbw-planning/.vbw-session" ]

  test_input='{"tool_input":{"command":"cat .env"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s\n' '$test_input' | bash '$SCRIPTS_DIR/bash-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "tmux-watchdog clears session-scoped registrations after stale lock" {
  cd "$TEST_TEMP_DIR"
  local fakebin
  fakebin="$TEST_TEMP_DIR/fakebin"
  mkdir -p "$fakebin" ".vbw-planning/.active-agent-count.lock" \
    ".vbw-planning/.active-agents/session-A" ".vbw-planning/.compacting"

  cat > "$fakebin/tmux" <<'EOF'
#!/bin/bash
case "$1" in
  has-session|list-clients)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$fakebin/tmux"
  cat > "$fakebin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$fakebin/sleep"

  echo "scout" > ".vbw-planning/.active-agents/session-A/active-agent"
  echo "1" > ".vbw-planning/.active-agents/session-A/active-agent-count"

  run env PATH="$fakebin:$PATH" VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" \
    bash "$SCRIPTS_DIR/tmux-watchdog.sh" test-session
  [ "$status" -eq 0 ]
  [ ! -d ".vbw-planning/.active-agents" ]
  [ ! -d ".vbw-planning/.active-agent-count.lock" ]
  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
}

@test "session-stop preserves live execute delegated workflow marker" {
  cd "$TEST_TEMP_DIR"
  echo '{"phase":1,"status":"running","effort":"balanced","correlation_id":"corr-123","plans":[]}' > ".vbw-planning/.execution-state.json"
  echo '{"mode":"execute","active":true,"effort":"balanced","delegation_mode":"team","team_name":"vbw-phase-01","session_id":"session-test","correlation_id":"corr-123","started_at":"2026-04-07T00:00:00Z"}' > ".vbw-planning/.delegated-workflow.json"

  simulate_session_stop

  [ -f ".vbw-planning/.delegated-workflow.json" ]
}

@test "session-stop removes non-execute delegated workflow marker" {
  cd "$TEST_TEMP_DIR"
  echo '{"mode":"fix","active":true,"effort":"balanced","delegation_mode":"","team_name":"","session_id":"session-test","correlation_id":"","started_at":"2026-04-07T00:00:00Z"}' > ".vbw-planning/.delegated-workflow.json"

  simulate_session_stop

  [ ! -f ".vbw-planning/.delegated-workflow.json" ]
}

@test "session-stop removes .task-verify-seen (circuit breaker state)" {
  cd "$TEST_TEMP_DIR"
  echo "abc123hash" > ".vbw-planning/.task-verify-seen"

  simulate_session_stop

  [ ! -f ".vbw-planning/.task-verify-seen" ]
}

@test "session-stop preserves .vbw-session" {
  cd "$TEST_TEMP_DIR"

  simulate_session_stop

  [ -f ".vbw-planning/.vbw-session" ]
  run cat ".vbw-planning/.vbw-session"
  [ "$output" = "test-session" ]
}

@test "session-stop appends to session log" {
  cd "$TEST_TEMP_DIR"

  simulate_session_stop

  [ -f ".vbw-planning/.session-log.jsonl" ]
  run jq -r '.model' ".vbw-planning/.session-log.jsonl"
  [ "$output" = "test" ]
}

@test "session-stop persists and removes cost ledger" {
  cd "$TEST_TEMP_DIR"
  echo '{"lead":0.05,"dev":0.10}' > ".vbw-planning/.cost-ledger.json"

  simulate_session_stop

  [ ! -f ".vbw-planning/.cost-ledger.json" ]

  run jq -s '[.[] | select(.type == "cost_summary")] | length' ".vbw-planning/.session-log.jsonl"
  [ "$output" = "1" ]
}

@test "session-stop always exits 0 even with no planning dir" {
  cd "$TEST_TEMP_DIR"
  rm -rf ".vbw-planning"

  run simulate_session_stop
  [ "$status" -eq 0 ]
}


@test "full chain: advisory task-verify does not create circuit breaker state" {
  cd "$TEST_TEMP_DIR"

  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "docs: update README"

  run bash -c 'echo "{\"task_subject\": \"Execute 07-01: Implement widget renderer\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "TaskCompleted"' >/dev/null
  [ ! -f ".vbw-planning/.task-verify-seen" ]

  local pid
  next_live_pid
  pid="$NEXT_PID"
  simulate_agent_start "vbw-dev" "$pid"
  simulate_agent_stop "$pid"
  simulate_session_stop

  [ ! -f ".vbw-planning/.task-verify-seen" ]
  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.active-agent-count" ]
  [ -f ".vbw-planning/.vbw-session" ]
}

@test "full chain: multi-agent start - advisory mismatch - matching execute task - session cleanup" {
  cd "$TEST_TEMP_DIR"

  local pid1 pid2
  next_live_pid
  pid1="$NEXT_PID"
  next_live_pid
  pid2="$NEXT_PID"
  simulate_agent_start "vbw-dev" "$pid1"
  simulate_agent_start "vbw-dev" "$pid2"

  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "2" ]

  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "docs: unrelated change"
  run bash -c 'echo "{\"task_subject\": \"Execute 07-01: Create detail view\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "TaskCompleted"' >/dev/null
  [ ! -f ".vbw-planning/.task-verify-seen" ]

  echo "$RANDOM" >> dummy.txt && git add dummy.txt && git commit -q -m "feat(07-02): wire navigation to detail view"
  run bash -c 'echo "{\"task_subject\": \"Execute 07-02: Wire navigation to detail view\"}" | bash "'"$SCRIPTS_DIR"'/task-verify.sh"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  simulate_agent_stop "$pid1"
  run cat ".vbw-planning/.active-agent-count"
  [ "$output" = "1" ]

  simulate_agent_stop "$pid2"
  [ ! -f ".vbw-planning/.active-agent-count" ]

  simulate_session_stop

  [ ! -f ".vbw-planning/.task-verify-seen" ]
  [ ! -f ".vbw-planning/.active-agent" ]
  [ ! -f ".vbw-planning/.agent-panes" ]
  [ -f ".vbw-planning/.vbw-session" ]
  [ -f ".vbw-planning/.session-log.jsonl" ]
}
