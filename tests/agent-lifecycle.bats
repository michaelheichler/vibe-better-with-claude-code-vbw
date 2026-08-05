#!/usr/bin/env bats

load test_helper

status=0

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning" "$TEST_TEMP_DIR/.claude/agents"
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export VBW_LIFECYCLE_NOW=1000
  cd "$TEST_TEMP_DIR" || return 1
}

teardown() {
  unset VBW_LIFECYCLE_NOW
  teardown_temp_dir
}

run_lifecycle() {
  printf '%s' "$1" | bash "$SCRIPTS_DIR/agent-lifecycle.sh" "$2" "${3:-}"
}

write_manifest() {
  printf '%s\n' "$1" > "$VBW_PLANNING_DIR/.agent-manifest.json"
}

@test_touch_creates_and_updates_entry() { # @test
  local input first_activity
  input='{"name":"alpha","role":"dev"}'
  printf 'generated\n' > "$TEST_TEMP_DIR/.claude/agents/alpha.md"

  run run_lifecycle "$input" touch start
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents.alpha.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "running" ]
  [ "$(jq -r '.agents.alpha.role' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "dev" ]
  first_activity=$(jq -r '.agents.alpha.last_activity_at' "$VBW_PLANNING_DIR/.agent-manifest.json")

  VBW_LIFECYCLE_NOW=1100 run run_lifecycle "$input" touch start
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents.alpha.last_activity_at' "$VBW_PLANNING_DIR/.agent-manifest.json")" != "$first_activity" ]

  VBW_LIFECYCLE_NOW=1200 run run_lifecycle "$input" touch stop
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents.alpha.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "used" ]
  [ ! -e "$TEST_TEMP_DIR/.claude/agents/alpha.md" ]
}

@test "canonical agent type identifies generated entries before labels" {
  run run_lifecycle '{"agent_type":"generated","name":"display-label","agent_id":"agent-1"}' touch start
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents.generated.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "running" ]
  [ "$(jq -r '.agents | has("display-label")' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "false" ]
}

@test_warning_ladder_fires_once_per_threshold() { # @test
  write_manifest '{"agents":{"alpha":{"name":"alpha","role":"dev","state":"running","created_at":"1970-01-01T00:00:00Z","last_activity_at":"1970-01-01T00:00:00Z","warnings_sent":[]}}}'

  VBW_LIFECYCLE_NOW=301 run run_lifecycle '{"name":"alpha"}' check
  [ "$status" -eq 0 ]
  [[ "$output" == *"5 minutes remain"* ]]
  [ "$(jq -c '.agents.alpha.warnings_sent' "$VBW_PLANNING_DIR/.agent-manifest.json")" = '["5"]' ]

  VBW_LIFECYCLE_NOW=301 run run_lifecycle '{"name":"alpha"}' check
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  VBW_LIFECYCLE_NOW=481 run run_lifecycle '{"name":"alpha"}' check
  [[ "$output" == *"2 minutes remain"* ]]
  VBW_LIFECYCLE_NOW=541 run run_lifecycle '{"name":"alpha"}' check
  [[ "$output" == *"1 minute remain"* ]]
  [ "$(jq -c '.agents.alpha.warnings_sent' "$VBW_PLANNING_DIR/.agent-manifest.json")" = '["5","2","1"]' ]
}

@test_idle_termination_marks_used_and_removes_definition() { # @test
  printf 'generated\n' > "$TEST_TEMP_DIR/.claude/agents/alpha.md"
  printf 'generated\n' > "$TEST_TEMP_DIR/.claude/agents/beta.md"
  write_manifest '{"agents":{"alpha":{"name":"alpha","role":"dev","state":"running","created_at":"1970-01-01T00:00:00Z","last_activity_at":"1970-01-01T00:00:00Z","warnings_sent":[]},"beta":{"name":"beta","role":"dev","state":"running","created_at":"1970-01-01T00:00:00Z","last_activity_at":"1970-01-01T00:00:00Z","warnings_sent":[]}}}'

  VBW_LIFECYCLE_NOW=600 run run_lifecycle '{"agent_type":"alpha","name":"display-label"}' check
  [ "$status" -eq 0 ]
  [[ "$output" == *"expired"* ]]
  [ "$(jq -r '.agents.alpha.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "used" ]
  [ "$(jq -r '.agents.beta.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "running" ]
  [ ! -e "$TEST_TEMP_DIR/.claude/agents/alpha.md" ]
  [ -e "$TEST_TEMP_DIR/.claude/agents/beta.md" ]
}

@test "lifecycle update does not bypass the manifest lock" {
  write_manifest '{"agents":{}}'
  mkdir "$VBW_PLANNING_DIR/.agent-manifest.lock"

  run bash -c 'printf "%s" "$1" | VBW_AGENT_MANIFEST_LOCK_TIMEOUT=0 VBW_PLANNING_DIR="$2" bash "$3" touch start' _ '{"name":"alpha"}' "$VBW_PLANNING_DIR" "$SCRIPTS_DIR/agent-lifecycle.sh"
  [ "$status" -eq 0 ]
  [ "$(jq '.agents | length' "$VBW_PLANNING_DIR/.agent-manifest.json")" -eq 0 ]
}

@test_sweep_expires_old_registered_and_running_entries() { # @test
  printf 'generated\n' > "$TEST_TEMP_DIR/.claude/agents/alpha.md"
  write_manifest '{"agents":{"alpha":{"name":"alpha","role":"dev","state":"registered","created_at":"1970-01-01T00:00:00Z","last_activity_at":"1970-01-01T00:00:00Z","warnings_sent":[]}}}'

  VBW_LIFECYCLE_NOW=87401 run run_lifecycle '' sweep
  [ "$status" -eq 0 ]
  [ "$(jq -r '.agents.alpha.state' "$VBW_PLANNING_DIR/.agent-manifest.json")" = "expired" ]
  [ ! -e "$TEST_TEMP_DIR/.claude/agents/alpha.md" ]
}

@test_missing_manifest_is_a_noop() { # @test
  run bash "$SCRIPTS_DIR/agent-lifecycle.sh" check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$VBW_PLANNING_DIR/.agent-manifest.json" ]

  run bash "$SCRIPTS_DIR/agent-lifecycle.sh" sweep
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
