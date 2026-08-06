#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cp "$SCRIPTS_DIR/phase-state-utils.sh" "$TEST_TEMP_DIR/state-functions.sh"
}

teardown() {
  teardown_temp_dir
}

write_execution_state() {
  printf '%s\n' "$1" > .vbw-planning/.execution-state.json
}

assert_qa_required() {
  local state_json="$1" expected="$2"
  write_execution_state "$state_json"
  run bash -c 'source "$1"; qa_required_for_phase "$2"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "qa_required_for_phase uses explicit true" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"qa_required":true,"effort":"turbo"}' true
}

@test "qa_required_for_phase uses explicit false" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"qa_required":false,"effort":"balanced"}' false
}

@test "qa_required_for_phase falls back to turbo effort" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"effort":"turbo"}' false
}

@test "qa_required_for_phase defaults to required" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"effort":"balanced"}' true
}

@test "qa_required_for_phase isolates historical phases from current policy" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"phase":2,"qa_required":false}' true
}

@test "qa_required_for_phase uses persisted phase policy" {
  cd "$TEST_TEMP_DIR"
  assert_qa_required '{"phase":2,"qa_required":true,"phase_qa_required":{"1":false}}' false
}

@test "qa_gate_routing_for_phase fails closed without execution state" {
  cd "$TEST_TEMP_DIR"
  run bash -c 'source "$1"; qa_gate_routing_for_phase "$2" "$3"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup" "$SCRIPTS_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "QA_RERUN_REQUIRED" ]
}

@test "qa_gate_routing_for_phase fails closed when verification resolver fails" {
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases/01-setup
  cat > "$TEST_TEMP_DIR/failing-resolve-verification-path.sh" <<'SCRIPT'
#!/usr/bin/env bash
exit 1
SCRIPT
  chmod +x "$TEST_TEMP_DIR/failing-resolve-verification-path.sh"
  cp "$SCRIPTS_DIR/qa-result-gate.sh" "$TEST_TEMP_DIR/qa-result-gate.sh"
  run bash -c 'source "$1"; qa_gate_routing_for_phase "$2" "$3"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup" "$TEST_TEMP_DIR"
  [ "$status" -eq 0 ]
  [ "$output" = "QA_RERUN_REQUIRED" ]
}
