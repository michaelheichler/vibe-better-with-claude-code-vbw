#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-test" "$TEST_TEMP_DIR/.vbw-planning/.contracts"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

write_plan() {
  local declared
  {
    printf '%s\n' '---' 'phase: 1' 'plan: 1' 'title: Pattern matching' 'files_modified:'
    for declared in "$@"; do
      printf '  - %s\n' "$declared"
    done
    printf '%s\n' '---'
  } > "$TEST_TEMP_DIR/.vbw-planning/phases/01-test/01-01-PLAN.md"
}

mark_execution_running() {
  jq -n '{status:"running",effort:"balanced",plans:[]}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.execution-state.json"
}

run_file_guard() {
  local target="$1" input
  input=$(jq -n --arg target "$target" \
    '{tool_name:"Write",tool_input:{file_path:$target,content:"test"}}')
  run bash -c 'printf "%s\n" "$1" | VBW_AGENT_ROLE=dev bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/file-guard.sh"
}

@test "active plan matches an exact literal path" {
  write_plan 'Cargo.toml'
  mark_execution_running

  run_file_guard 'Cargo.toml'

  [ "$status" -eq 0 ]
}

@test "active plan expands one brace group and rejects a non-member" {
  local target
  write_plan '{Cargo.toml,Cargo.lock,rust-toolchain.toml}'
  mark_execution_running

  for target in Cargo.toml Cargo.lock rust-toolchain.toml; do
    run_file_guard "$target"
    [ "$status" -eq 0 ]
  done

  run_file_guard 'README.md'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in active plan's files_modified"* ]]
}

@test "active plan matches nested glob paths and rejects outside paths" {
  write_plan 'crates/phenprocoumon-core/**'
  mark_execution_running

  run_file_guard 'crates/phenprocoumon-core/src/domain/model.rs'
  [ "$status" -eq 0 ]

  run_file_guard 'crates/other-core/src/domain/model.rs'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in active plan's files_modified"* ]]
}

@test "single-star globs stay within one path component" {
  write_plan 'crates/*/Cargo.toml'
  mark_execution_running

  run_file_guard 'crates/core/Cargo.toml'
  [ "$status" -eq 0 ]

  run_file_guard 'crates/core/src/Cargo.toml'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in active plan's files_modified"* ]]
}

@test "contract allowed_paths matches a glob and rejects outside paths" {
  write_plan 'README.md'
  jq -n '{allowed_paths:["crates/phenprocoumon-core/**"],forbidden_paths:[]}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.contracts/01-01.json"

  run_file_guard 'crates/phenprocoumon-core/src/lib.rs'
  [ "$status" -eq 0 ]

  run_file_guard 'crates/other-core/src/lib.rs'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in contract allowed_paths"* ]]
}
