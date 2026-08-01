#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
}

teardown() {
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
  teardown_temp_dir
}

@test "reports capability when environment enables teams" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=available\nteam_capability_reason=env_enabled' ]
}

@test "reports disabled when environment disables teams" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=unavailable\nteam_capability_reason=env_disabled' ]
}

@test "empty environment value falls through to enabled settings" {
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=""
  printf '%s\n' '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > "$CLAUDE_CONFIG_DIR/settings.json"

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=available\nteam_capability_reason=settings_enabled' ]
}

@test "reports capability when settings enable teams" {
  printf '%s\n' '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"1"}}' > "$CLAUDE_CONFIG_DIR/settings.json"

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=available\nteam_capability_reason=settings_enabled' ]
}

@test "reports disabled when settings disable teams" {
  printf '%s\n' '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"0"}}' > "$CLAUDE_CONFIG_DIR/settings.json"

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=unavailable\nteam_capability_reason=settings_disabled' ]
}

@test "fails safe when settings are malformed" {
  printf '%s\n' '{"env":' > "$CLAUDE_CONFIG_DIR/settings.json"

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=unavailable\nteam_capability_reason=settings_unreadable' ]
}

@test "valid settings without the key are not configured" {
  printf '%s\n' 'null' > "$CLAUDE_CONFIG_DIR/settings.json"

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=unavailable\nteam_capability_reason=not_configured' ]
}

@test "reports not configured when settings file is absent" {
  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=unavailable\nteam_capability_reason=not_configured' ]
}

@test "enabled environment overrides disabled settings" {
  printf '%s\n' '{"env":{"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS":"0"}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

  run bash "$SCRIPTS_DIR/detect-team-capability.sh"

  [ "$status" -eq 0 ]
  [ "$output" = $'team_capability=available\nteam_capability_reason=env_enabled' ]
}
