#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  # Deterministic base URL so cache paths are test-scoped
  export ANTHROPIC_BASE_URL="http://detect-models-test.invalid"
  DM_CACHE="/tmp/vbw-models-$(vbw_hash_path "$ANTHROPIC_BASE_URL")"
  export DM_CACHE
  rm -f "$DM_CACHE"
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN VBW_MODEL_CATALOG_FILE 2>/dev/null || true
}

teardown() {
  rm -f "$DM_CACHE" 2>/dev/null
  teardown_temp_dir
}

make_fake_curl() {
  # $1 = behavior: ok | fail
  mkdir -p "$TEST_TEMP_DIR/bin"
  if [ "$1" = "ok" ]; then
    cat > "$TEST_TEMP_DIR/bin/curl" <<'FAKE'
#!/usr/bin/env bash
printf '{"data":[{"id":"sol"},{"id":"kimi3"},{"id":"claude-sonnet-5"}]}\n'
FAKE
  else
    cat > "$TEST_TEMP_DIR/bin/curl" <<'FAKE'
#!/usr/bin/env bash
exit 7
FAKE
  fi
  chmod +x "$TEST_TEMP_DIR/bin/curl"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

@test "no auth env: empty output, exit 0, no cache write" {
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$DM_CACHE" ]
}

@test "catalog file hook emits its lines without network" {
  printf 'm1\nm2\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "m1" ]
  [ "${lines[1]}" = "m2" ]
}

@test "fetch parses Anthropic-shaped response and writes cache" {
  export ANTHROPIC_API_KEY="test-key"
  make_fake_curl ok
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "sol" ]
  [ "${lines[2]}" = "claude-sonnet-5" ]
  [ -f "$DM_CACHE" ]
  grep -Fxq "kimi3" "$DM_CACHE"
}

@test "failed fetch: empty output, exit 0, negative cache written" {
  export ANTHROPIC_API_KEY="test-key"
  make_fake_curl fail
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$DM_CACHE" ]
  [ ! -s "$DM_CACHE" ]
}

@test "fresh cache served without invoking curl" {
  export ANTHROPIC_API_KEY="test-key"
  printf 'cached-model\n' > "$DM_CACHE"
  make_fake_curl fail
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "cached-model" ]
}
