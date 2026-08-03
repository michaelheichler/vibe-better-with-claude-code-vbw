#!/usr/bin/env bats

load test_helper
@test "agent-start does nothing when agent fields are missing" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-start ignores non-numeric legacy count and records a live registration" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  sleep 30 & pid=$!
  INPUT="{\"agent_type\":\"vbw-scout\",\"pid\":\"$pid\"}"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "scout" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  kill "$pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-start does not count a dead pid beside a non-numeric legacy count" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  pid=$(get_dead_pid)
  INPUT="{\"agent_type\":\"vbw-scout\",\"pid\":\"$pid\"}"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  teardown_temp_dir
}

@test "agent-start accepts team-lead alias when VBW session marker exists" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  sleep 30 & pid=$!
  INPUT="{\"agent_name\":\"team-lead\",\"pid\":\"$pid\"}"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent")" = "lead" ]
  [ "$(cat "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count")" = "1" ]
  kill "$pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "agent-start ignores team-lead alias without VBW context markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  INPUT='{"agent_name":"team-lead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-start.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop cleans up when count is non-numeric" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "abc" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop ignores bare native agent_type even inside a VBW session" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"agent_type\":\"dev\"}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop falls back to explicit legacy name when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  INPUT='{"agent_type":"helper-agent","agent_name":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop falls back to explicit legacy agentName when native agent_type is non-VBW" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "dev" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "1" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  INPUT='{"agent_type":"helper-agent","agentName":"vbw-dev-01"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  teardown_temp_dir
}

@test "agent-stop repeatedly cleans stale count and marker state" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/agent-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
}
