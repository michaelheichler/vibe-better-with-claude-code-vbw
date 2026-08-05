#!/usr/bin/env bats

load test_helper

status=0
output=""

run_renderer() {
  bash "$SCRIPTS_DIR/render-agent-template.sh" "$@"
}

@test_full_render_includes_frontmatter_and_job() { # @test
  run run_renderer dev NAME=vbw-test DESCRIPTION='A test agent' JOB='Implement the assigned work.'

  [ "$status" -eq 0 ]
  [[ "$output" == *'name: "vbw-test"'* ]]
  [[ "$output" == *'description: "A test agent"'* ]]
  [[ "$output" == *'model: "claude-sonnet-5"'* ]]
  [[ "$output" == *'**VBW Dev**'* ]]
  [[ "$output" == *'## Your job'* ]]
  [[ "$output" == *'Implement the assigned work.'* ]]
  ! [[ "$output" == *'{{'* ]]
}

@test_optional_frontmatter_lines_are_dropped_when_empty() { # @test
  run run_renderer scout NAME=vbw-scout DESCRIPTION=Scout JOB=Research. effort=

  [ "$status" -eq 0 ]
  [[ "$output" == *'model: "claude-sonnet-5"'* ]]
  ! [[ "$output" == *$'effort:'* ]]
  ! [[ "$output" == *$'maxTurns:'* ]]
}

@test_unresolved_required_token_fails() { # @test
  run run_renderer dev NAME=vbw-test DESCRIPTION='A test agent'

  [ "$status" -eq 1 ]
  [[ "$output" == *'missing required field JOB'* ]]
}
