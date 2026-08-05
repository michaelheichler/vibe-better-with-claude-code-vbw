#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p .vbw-planning/phases/01-setup
  sed '/^INPUT=$(cat)/,$d' "$SCRIPTS_DIR/state-updater.sh" > "$TEST_TEMP_DIR/state-functions.sh"
}

teardown() {
  teardown_temp_dir
}

write_execution_state() {
  printf '%s\n' "$1" > .vbw-planning/.execution-state.json
}

@test "qa_required_for_phase uses explicit true" {
  cd "$TEST_TEMP_DIR"
  write_execution_state '{"qa_required":true,"effort":"turbo"}'

  run bash -c 'source "$1"; qa_required_for_phase "$2"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "qa_required_for_phase uses explicit false" {
  cd "$TEST_TEMP_DIR"
  write_execution_state '{"qa_required":false,"effort":"balanced"}'

  run bash -c 'source "$1"; qa_required_for_phase "$2"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "qa_required_for_phase falls back to turbo effort" {
  cd "$TEST_TEMP_DIR"
  write_execution_state '{"effort":"turbo"}'

  run bash -c 'source "$1"; qa_required_for_phase "$2"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "qa_required_for_phase defaults to required" {
  cd "$TEST_TEMP_DIR"
  write_execution_state '{"effort":"balanced"}'

  run bash -c 'source "$1"; qa_required_for_phase "$2"' _ "$TEST_TEMP_DIR/state-functions.sh" "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
