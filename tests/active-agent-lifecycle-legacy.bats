#!/usr/bin/env bats

load test_helper
@test "session-stop removes only current session active-agent state and rebuilds aggregate" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"session-B\"}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A" ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$scout_pid scout" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "session-stop filters dead registrations from aggregate rebuild" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"session-A\"}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A" ]
  teardown_temp_dir
}

@test "session-stop leaves another session live registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & keep_pid=$!
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$keep_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"session_id\":\"session-A\"}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  kill "$keep_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "session-stop without session id rebuilds aggregate while session-local state remains" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_SESSION_ID && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$scout_pid scout" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  kill "$scout_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "session-stop without session id ignores dead session-local state" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_SESSION_ID && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "active-agent aggregate preserves no-session legacy Scout when safe session starts" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!

  printf '%s\n' "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global" ]
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$scout_pid scout" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "active-agent aggregate excludes a dead legacy registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  printf '%s\n' "{\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "session-stop without session id removes only legacy source and preserves safe sessions" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!

  printf '%s\n' "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_SESSION_ID && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global" ]
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "session-stop without session id removes dead legacy state" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  printf '%s\n' "{\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_SESSION_ID && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}


@test "active-agent aggregate migrates brownfield root-only legacy state before safe rebuild" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & legacy_pid=$!
  sleep 30 & new_pid=$!
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "$legacy_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"

  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$new_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  kill "$legacy_pid" "$new_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "active-agent migration ignores dead root role-pid entries" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "$dead_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  printf '%s\n' '{"session_id":"session-B","agent_type":"vbw-dev","pid":"'"$$'"'}' | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  teardown_temp_dir
}

@test "active-agent legacy migration removes degraded marker-only state" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "lead" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"

  run bash -c "cd '$TEST_TEMP_DIR' && unset CLAUDE_SESSION_ID && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  teardown_temp_dir
}

@test "active-agent helper rejects dot-only session ids as unsafe path components" {
  run bash -c "source '$SCRIPTS_DIR/lib/active-agent-state.sh'; vbw_active_agent_is_safe_session_id ."
  [ "$status" -ne 0 ]

  run bash -c "source '$SCRIPTS_DIR/lib/active-agent-state.sh'; vbw_active_agent_is_safe_session_id .."
  [ "$status" -ne 0 ]

  run bash -c "source '$SCRIPTS_DIR/lib/active-agent-state.sh'; vbw_active_agent_is_safe_session_id __vbw_legacy_global"
  [ "$status" -ne 0 ]

  run bash -c "source '$SCRIPTS_DIR/lib/active-agent-state.sh'; vbw_active_agent_is_safe_session_id session-A_01.ok"
  [ "$status" -eq 0 ]
}

@test "agent-start treats reserved legacy source id as internal fallback" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & pid=$!
  printf '%s\n' "{\"session_id\":\"__vbw_legacy_global\",\"agent_type\":\"vbw-scout\",\"pid\":\"$pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  grep -Fqx "$pid scout" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  kill "$pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-start treats dot-only session ids as legacy fallback, not session directories" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & first_pid=$!
  printf '%s\n' "{\"session_id\":\"..\",\"agent_type\":\"vbw-scout\",\"pid\":\"$first_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/active-agent-role-pids" ]
  kill "$first_pid" 2>/dev/null || true

  rm -rf "$TEST_TEMP_DIR/.vbw-planning"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & second_pid=$!
  printf '%s\n' "{\"session_id\":\".\",\"agent_type\":\"vbw-scout\",\"pid\":\"$second_pid\"}" | \
    env -u CLAUDE_SESSION_ID VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/active-agent-role-pids" ]
  kill "$second_pid" 2>/dev/null || true
  teardown_temp_dir
}


@test "doctor-cleanup reports and removes stale active-agent session directories" {
  setup_temp_dir
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-roles"
  echo "$dead_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-role-pids"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "$dead_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude" \
    bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale_marker|.active-agents/session-A|dead session-local PIDs"* ]]

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude" \
    bash "$SCRIPTS_DIR/doctor-cleanup.sh" cleanup
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids" ]
  teardown_temp_dir
}

@test "doctor-cleanup reports and removes stale legacy active-agent source" {
  setup_temp_dir
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/active-agent-roles"
  echo "$dead_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/active-agent-role-pids"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "scout 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "$dead_pid scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude" \
    bash "$SCRIPTS_DIR/doctor-cleanup.sh" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale_marker|.active-agents/__vbw_legacy_global|dead session-local PIDs"* ]]

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude" \
    bash "$SCRIPTS_DIR/doctor-cleanup.sh" cleanup
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids" ]
  teardown_temp_dir
}

@test "agent-stop drops unreliable role markers after anonymous mixed-role stop" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  cat > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" <<'EOF'
scout 1
dev 1
EOF

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  teardown_temp_dir
}

@test "agent-stop removes stale single-role state without a registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "dev 2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  teardown_temp_dir
}

@test "agent-stop removes marker-only state without a registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "lead" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop removes marker when last agent stops" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop ignores a second stop after stale state cleanup" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agents" ]
  teardown_temp_dir
}

@test "agent-stop clears stale state with malformed role files" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop leaves no stale root aggregate after cleanup" {
  setup_temp_dir
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "dev 1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "$dead_pid dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids" ]
  teardown_temp_dir
}

@test "agent-stop cleans a marker when role registration is absent" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "qa" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  teardown_temp_dir
}

@test "agent-stop remains idempotent after aggregate cleanup" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}
