#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR"
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

run_preflight() {
  local input="$1"
  run env VBW_TEST_INPUT="$input" TEST_TEMP_DIR="$TEST_TEMP_DIR" SCRIPT_PATH="$SCRIPTS_DIR/prompt-preflight.sh" bash -c '
    cd "$TEST_TEMP_DIR" || exit 1
    printf "%s" "$VBW_TEST_INPUT" | bash "$SCRIPT_PATH"
  '
}

@test "prompt-preflight exits quietly without a planning directory" {
  rm -rf .vbw-planning

  run_preflight '{"prompt":"hello"}'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt-preflight emits no reminder without execution state" {
  run_preflight '{"prompt":"hello"}'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt-preflight reminds the orchestrator for active execution state" {
  printf '%s\n' '{"status":"running"}' > .vbw-planning/.execution-state.json

  run_preflight '{"prompt":"hello"}'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Never implement") and contains("vbw-qa")' >/dev/null
}

@test "prompt-preflight emits no reminder for complete execution state" {
  printf '%s\n' '{"status":"complete"}' > .vbw-planning/.execution-state.json

  run_preflight '{"prompt":"hello"}'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt-preflight fails open for malformed execution state" {
  printf '%s\n' '{"status":' > .vbw-planning/.execution-state.json

  run_preflight '{"prompt":"hello"}'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt-preflight fails open when jq is unavailable" {
  local fake_bin="$TEST_TEMP_DIR/no-jq-bin"
  local command_name command_path
  mkdir -p "$fake_bin"
  for command_name in bash cat dirname basename pwd; do
    command_path=$(type -P "$command_name")
    ln -s "$command_path" "$fake_bin/$command_name"
  done

  run env PATH="$fake_bin" VBW_TEST_INPUT='{"prompt":"hello"}' TEST_TEMP_DIR="$TEST_TEMP_DIR" SCRIPT_PATH="$SCRIPTS_DIR/prompt-preflight.sh" bash -c '
    cd "$TEST_TEMP_DIR" || exit 1
    printf "%s" "$VBW_TEST_INPUT" | bash "$SCRIPT_PATH"
  '

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "prompt-preflight combines the plan warning with the orchestrator reminder" {
  mkdir -p .vbw-planning/phases/01-core
  printf '%s\n' '## Current Phase: 01-core' > .vbw-planning/STATE.md
  printf '%s\n' '{"status":"running"}' > .vbw-planning/.execution-state.json

  run_preflight '{"prompt":"/vbw:vibe --execute"}'

  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("No PLAN.md") and contains("Never implement")' >/dev/null
}

@test "prompt-preflight combines the archive block with the orchestrator reminder" {
  printf '%s\n' '# Project' > .vbw-planning/PROJECT.md
  mkdir -p .vbw-planning/phases/01-core
  touch .vbw-planning/phases/01-core/01-01-PLAN.md
  printf '%s\n' '---' 'status: complete' '---' 'Done.' > .vbw-planning/phases/01-core/01-01-SUMMARY.md
  printf '%s\n' '---' 'phase: 01' 'status: issues_found' '---' '- Severity: major' > .vbw-planning/phases/01-core/01-UAT.md
  printf '%s\n' '{"status":"running"}' > .vbw-planning/.execution-state.json

  run_preflight '{"prompt":"/vbw:vibe --archive"}'

  [ "$status" -eq 2 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("VBW pre-flight block") and contains("Never implement") and contains("vbw-qa")' >/dev/null
}
