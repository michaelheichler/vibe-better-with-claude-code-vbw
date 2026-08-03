#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper
@test "agent-start handles vbw: prefixed agent_type" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"vbw:vbw-scout"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  teardown_temp_dir
}

@test "agent-start prefers native agent_type over conflicting legacy aliases" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"vbw-dev","agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  teardown_temp_dir
}

@test "agent-start falls back to legacy name when native fields are absent" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"name":"vbw-qa"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "qa" ]
  teardown_temp_dir
}

@test "agent-start falls back to legacy agentName when native fields are absent" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agentName":"vbw-docs"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "docs" ]
  teardown_temp_dir
}

@test "agent-start ignores non-VBW agent_type payloads" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"helper-agent"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start ignores bare native agent_type even inside a VBW session" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"agent_type":"dev","name":"dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start falls back to explicit legacy name when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_type":"dev","agent_name":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  teardown_temp_dir
}

@test "agent-start counts live per-pid registrations" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & lead_pid=$!
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-lead\",\"pid\":\"$lead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  kill "$scout_pid" "$lead_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-start ignores dead per-pid registrations" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" 2>/dev/null || true)" = "" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  teardown_temp_dir
}

@test "agent-start preserves dead registration files for stale cleanup" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/__vbw_legacy_global/agents/$dead_pid.json" ] || [ -f "$TEST_TEMP_DIR/.vbw-planning/agents/$dead_pid.json" ] || [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents" ]
  teardown_temp_dir
}

@test "agent-start tracks active role counts for live registrations" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_one=$!
  sleep 30 & dev_pid=$!
  sleep 30 & scout_two=$!
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_one\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_two\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  grep -Fqx 'scout 2' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  kill "$scout_one" "$dev_pid" "$scout_two" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-start drops dead registrations from role counts" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  teardown_temp_dir
}

@test "agent-stop removes the matching live registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_one=$!
  sleep 30 & dev_pid=$!
  sleep 30 & scout_two=$!
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_one\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_two\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"

  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_one\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"

  echo "{\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  run ! grep -q '^dev ' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"

  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_two\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  kill "$scout_one" "$dev_pid" "$scout_two" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-stop leaves unrelated live registrations untouched" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & first_pid=$!
  sleep 30 & second_pid=$!
  echo "{\"session_id\":\"stop-session\",\"agent_type\":\"vbw-scout\",\"pid\":\"$first_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"session_id\":\"stop-session\",\"agent_type\":\"vbw-dev\",\"pid\":\"$second_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"session_id\":\"stop-session\",\"pid\":\"$first_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/stop-session/agents/$first_pid.json" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/stop-session/agents/$second_pid.json" ]
  kill "$first_pid" "$second_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-stop does not remove a registration for a dead pid" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  echo "{\"session_id\":\"dead-stop\",\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"session_id\":\"dead-stop\",\"pid\":\"$dead_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop resolves anonymous PID stops through role map" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!
  echo "{\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"
  echo "{\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/agent-start.sh'"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"pid\":\"$scout_pid\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  run ! grep -q '^scout ' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  run ! grep -q "^$scout_pid " "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-stop ignores an unknown pid" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"pid\":\"$dead_pid\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop rejects role-only state without a per-pid file" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  printf '1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  printf 'scout\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"agent_type\":\"vbw-scout\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "active-agent lifecycle maintains per-session state and aggregate role PID map" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count")" = "1" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B/active-agent-count")" = "1" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "2" ]
  grep -Fqx 'scout 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$scout_pid scout" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-stop.sh"

  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/agents/$scout_pid.json" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B/agents/$dev_pid.json" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  run ! grep -q '^scout ' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  run ! grep -q "^$scout_pid " "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "active-agent lifecycle ignores dead session registrations" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  dead_pid=$(get_dead_pid)
  printf '%s\n' "{\"session_id\":\"dead-session\",\"agent_type\":\"vbw-scout\",\"pid\":\"$dead_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/dead-session/active-agent-count" ]
  run bash -c "source '$SCRIPTS_DIR/lib/active-agent-state.sh'; vbw_active_agent_current_scout '$TEST_TEMP_DIR/.vbw-planning' '{\"session_id\":\"dead-session\"}'"
  [ "$status" -eq 1 ]
  teardown_temp_dir
}

@test "agent-stop without session id resolves owning session by PID before legacy fallback" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  sleep 30 & scout_pid=$!
  sleep 30 & dev_pid=$!

  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-scout\",\"pid\":\"$scout_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"
  printf '%s\n' "{\"session_id\":\"session-B\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"pid\":\"$scout_pid\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/agents/$scout_pid.json" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-B/agents/$dev_pid.json" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  grep -Fqx 'dev 1' "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  grep -Fqx "$dev_pid dev" "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "dev" ]
  kill "$scout_pid" "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}
