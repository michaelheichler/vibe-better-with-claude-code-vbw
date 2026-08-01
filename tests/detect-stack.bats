#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PROJECT_DIR="$TEST_TEMP_DIR/project"
  CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  export PROJECT_DIR CLAUDE_CONFIG_DIR
  mkdir -p "$PROJECT_DIR"
}

teardown() {
  teardown_temp_dir
}

create_bash_project() {
  mkdir -p "$PROJECT_DIR/scripts"
  printf '#!/bin/bash\n' > "$PROJECT_DIR/scripts/main.sh"
  chmod +x "$PROJECT_DIR/scripts/main.sh"
  printf '# Fixture\n' > "$PROJECT_DIR/README.md"
}

@test "detect-stack finds Bash in a shell and Markdown repo" {
  create_bash_project

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("bash") != null' <<< "$output"
  jq -e '.recommended_skills | index("bash-skill") != null' <<< "$output"
}

@test "detect-stack does not infer Bash from an empty repo" {
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("bash") == null' <<< "$output"
}

@test "detect-stack reports Bash alongside GitHub Actions" {
  create_bash_project
  mkdir -p "$PROJECT_DIR/.github/workflows"
  printf 'name: CI\n' > "$PROJECT_DIR/.github/workflows/ci.yml"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("bash") != null' <<< "$output"
  jq -e '.detected_stack | index("github-actions") != null' <<< "$output"
}

@test "global-only skill remains a project suggestion" {
  create_bash_project
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/bash-skill"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.installed.global | index("bash-skill") != null' <<< "$output"
  jq -e '.installed.project | index("bash-skill") == null' <<< "$output"
  jq -e '.suggestions | index("bash-skill") != null' <<< "$output"
}
