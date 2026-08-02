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

top_level_keys_are_unique() {
  jq --stream -s -e '
    reduce .[] as $event (
      {group_keys: [], at_group_boundary: true};
      ($event[0][0] // null) as $key |
      if $key != null and ($event | length) == 2 and
          ((.group_keys | length) == 0 or .group_keys[-1] != $key or .at_group_boundary)
      then .group_keys += [$key]
      else .
      end |
      .at_group_boundary = (
        (($event | length) == 1 and ($event[0] | length) == 2) or
        (($event | length) == 2 and ($event[0] | length) == 1)
      )
    ) |
    .group_keys | length == (unique | length)
  ' "$1" >/dev/null
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

@test "stack mappings have unique top-level categories" {
  run top_level_keys_are_unique "$SCRIPTS_DIR/../config/stack-mappings.json"

  [ "$status" -eq 0 ]
}

@test "top-level category integrity check rejects a non-adjacent duplicate fixture copy" {
  local fixture mapping mapping_json
  fixture="$TEST_TEMP_DIR/duplicate-stack-mappings.json"
  mapping="$SCRIPTS_DIR/../config/stack-mappings.json"
  mapping_json=$(jq -c '.' "$mapping")
  printf '{"mobile":{},%s\n' "${mapping_json:1}" > "$fixture"

  run top_level_keys_are_unique "$fixture"

  [ "$status" -ne 0 ]
}

@test "top-level category integrity check rejects adjacent duplicate objects" {
  local fixture
  fixture="$TEST_TEMP_DIR/adjacent-duplicate-stack-mappings.json"
  printf '%s\n' '{"mobile":{"android-kotlin":{}},"mobile":{"flutter":{}}}' > "$fixture"

  run top_level_keys_are_unique "$fixture"

  [ "$status" -ne 0 ]
}

@test "detect-stack emits the Android Kotlin mobile profile" {
  mkdir -p "$PROJECT_DIR/app/src/main/kotlin"
  printf 'plugins { kotlin("android") }\n' > "$PROJECT_DIR/build.gradle.kts"
  printf 'class MainActivity\n' > "$PROJECT_DIR/app/src/main/kotlin/MainActivity.kt"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("android-kotlin") != null' <<< "$output"
  jq -e '.recommended_skills | index("android-skill") != null' <<< "$output"
}

@test "detect-stack emits the Flutter mobile profile" {
  mkdir -p "$PROJECT_DIR/lib"
  printf 'name: fixture\n' > "$PROJECT_DIR/pubspec.yaml"
  printf 'void main() {}\n' > "$PROJECT_DIR/lib/main.dart"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("flutter") != null' <<< "$output"
  jq -e '.recommended_skills | index("flutter-skill") != null' <<< "$output"
}

@test "detect-stack emits the React Native mobile profile" {
  printf '%s\n' '{"dependencies":{"react-native":"0.80.0"}}' > "$PROJECT_DIR/package.json"

  run bash "$SCRIPTS_DIR/detect-stack.sh" "$PROJECT_DIR"

  [ "$status" -eq 0 ]
  jq -e '.detected_stack | index("react-native") != null' <<< "$output"
  jq -e '.recommended_skills | index("react-native-skill") != null' <<< "$output"
}
