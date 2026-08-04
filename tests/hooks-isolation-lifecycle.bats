#!/usr/bin/env bats

load test_helper


@test "heredoc commit validation extracts correct message" {
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(core): add heredoc feature\n\nCo-Authored-By: Test\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"does not match format"* ]]
}

@test "heredoc commit does not get overwritten by -m extraction" {
  INPUT='{"tool_input":{"command":"git commit -m \"$(cat <<'"'"'EOF'"'"'\nfeat(test): valid heredoc\nEOF\n)\""}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"does not match format"* ]]
}

@test "invalid heredoc commit is flagged" {
  local input
  input=$(printf '{"tool_input":{"command":"git commit -m \\"$(cat <<EOF)\\"\\nbad commit no type\\nEOF"}}')
  run bash -c "printf '%s' '$input' | bash '$SCRIPTS_DIR/validate-commit.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "does not match format"
}


@test "detect-stack finds Rust via Cargo.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/Cargo.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("rust")' >/dev/null
}

@test "detect-stack finds Go via go.mod" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "module example.com/test" > "$tmpdir/go.mod"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("go")' >/dev/null
}

@test "detect-stack finds Python via pyproject.toml" {
  local tmpdir
  tmpdir=$(mktemp -d)
  touch "$tmpdir/pyproject.toml"
  run bash "$SCRIPTS_DIR/detect-stack.sh" "$tmpdir"
  rm -rf "$tmpdir"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.detected_stack | index("python")' >/dev/null
}


@test "security-filter allows .vbw-planning/ write when VBW marker present" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter blocks .env file access" {
  INPUT='{"tool_input":{"file_path":".env"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q "sensitive file"
}


@test "security-filter blocks build/ as path component (relative)" {
  INPUT='{"tool_input":{"file_path":"build/output.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks build/ as path component (absolute)" {
  INPUT='{"tool_input":{"file_path":"/home/user/project/build/output.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks dist/ as path component" {
  INPUT='{"tool_input":{"file_path":"dist/bundle.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks node_modules/ as path component" {
  INPUT='{"tool_input":{"file_path":"node_modules/lodash/index.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter blocks .git/ as path component" {
  INPUT='{"tool_input":{"file_path":".git/config"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
}

@test "security-filter allows file when parent dir contains build substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/corvex-build/src/app.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file named build-something" {
  INPUT='{"tool_input":{"file_path":"build-orbstack.sh"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file when parent dir contains dist substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/my-dist/bundle.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file when parent dir contains node_modules substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/old-node_modules/lodash/index.js"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}

@test "security-filter allows file when parent dir contains .git substring" {
  INPUT='{"tool_input":{"file_path":"/home/user/repo.git/HEAD"}}'
  run bash -c "echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
}


@test "session config cache file is written at session start" {
  setup_temp_dir
  create_test_config
  CACHE_FILE="$TEST_TEMP_DIR/vbw-config-cache"
  rm -f "$CACHE_FILE" 2>/dev/null
  run env VBW_CONFIG_CACHE="$CACHE_FILE" bash -c "cd '$TEST_TEMP_DIR' && bash '$SCRIPTS_DIR/session-start.sh'"
  [ -f "$CACHE_FILE" ]
  grep -q "VBW_EFFORT=" "$CACHE_FILE"
  grep -q "VBW_AUTONOMY=" "$CACHE_FILE"
  teardown_temp_dir
}


@test "file-guard exits 0 when no plan files exist" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases"
  echo '{}' > "$TEST_TEMP_DIR/.vbw-planning/config.json"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/src/index.ts"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/file-guard.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}


@test "security-filter allows write with only .vbw-session (no .active-agent)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/milestones/default/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter resolves markers from FILE_PATH project root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.vbw-planning"
  touch "$REPO_A/.vbw-planning/.gsd-isolation"
  touch "$REPO_B/.vbw-planning/.gsd-isolation"
  echo "session" > "$REPO_B/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows .vbw-planning write even without markers (self-blocking removed)" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}
