#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export ANTHROPIC_BASE_URL="http://detect-models-test.invalid"
  # Pinned so the host claude install cannot leak into assertions.
  export CLAUDE_CODE_EXECPATH="$TEST_TEMP_DIR/no-such-binary"
  unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN VBW_MODEL_CATALOG_FILE 2>/dev/null || true
  dm_cache_path
}

teardown() {
  rm -f /tmp/vbw-models-* 2>/dev/null
  teardown_temp_dir
}

dm_cache_path() {
  local auth=""
  [ -n "${ANTHROPIC_API_KEY:-}${ANTHROPIC_AUTH_TOKEN:-}" ] && auth="$ANTHROPIC_BASE_URL"
  local bin="$CLAUDE_CODE_EXECPATH"
  [ -f "$bin" ] || bin=""
  local stamp="0:0"
  if [ -n "$bin" ]; then
    stamp="$(stat -f '%m:%z' "$bin" 2>/dev/null || stat -c '%Y:%s' "$bin" 2>/dev/null || echo 0:0)"
  fi
  DM_CACHE="/tmp/vbw-models-$(vbw_hash_path "bin:${bin:-none}:${stamp}|${auth}")"
  export DM_CACHE
}

make_fake_binary() {
  printf 'junk opus:"claude-opus-5" sonnet:"claude-sonnet-5" haiku:"claude-haiku-4-5" fable:"claude-fable-5" default:"claude-sonnet-5" old claude-opus-4-1 junk\n' \
    > "$TEST_TEMP_DIR/fake-claude"
  printf '%s\n' '[{value:"sol",label:"Sol",description:"GPT-5.6 Sol (OpenAI (ChatGPT))"},{value:"kimi3",label:"Kimi3",description:"k3 (Kimi (Coding Plan))"}].forEach(function(x){})' \
    >> "$TEST_TEMP_DIR/fake-claude"
  printf '%s\n' 'Additional custom models: kimi3 = k3 (Kimi (Coding Plan)); sol = GPT-5.6 Sol (OpenAI (ChatGPT)).`' \
    >> "$TEST_TEMP_DIR/fake-claude"
  export CLAUDE_CODE_EXECPATH="$TEST_TEMP_DIR/fake-claude"
  dm_cache_path
}

make_fake_curl() {
  mkdir -p "$TEST_TEMP_DIR/bin"
  # The marker file lets tests assert whether the endpoint was probed at all.
  if [ "$1" = "ok" ]; then
    cat > "$TEST_TEMP_DIR/bin/curl" <<FAKE
#!/usr/bin/env bash
touch "$TEST_TEMP_DIR/curl-called"
printf '{"data":[{"id":"sol"},{"id":"kimi3"},{"id":"claude-sonnet-5"}]}\n'
FAKE
  else
    cat > "$TEST_TEMP_DIR/bin/curl" <<FAKE
#!/usr/bin/env bash
touch "$TEST_TEMP_DIR/curl-called"
exit 7
FAKE
  fi
  chmod +x "$TEST_TEMP_DIR/bin/curl"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

@test "no auth and no binary: empty output, exit 0, no cache write" {
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$DM_CACHE" ]
}

@test "catalog file hook emits its lines without probing" {
  printf 'm1\nm2\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "m1" ]
  [ "${lines[1]}" = "m2" ]
}

@test "binary is the primary source: current ids and injected ids, no historic ids" {
  make_fake_binary
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  grep -Fxq "claude-opus-5" <<< "$output"
  grep -Fxq "claude-fable-5" <<< "$output"
  grep -Fxq "claude-haiku-4-5" <<< "$output"
  grep -Fxq "sol" <<< "$output"
  grep -Fxq "kimi3" <<< "$output"
  ! grep -Fxq "claude-opus-4-1" <<< "$output"
  [ -f "$DM_CACHE" ]
}

@test "labeled mode emits id and description separated by a tab" {
  make_fake_binary
  run bash "$SCRIPTS_DIR/detect-models.sh" --labeled
  [ "$status" -eq 0 ]
  grep -Fq "$(printf 'sol\tGPT-5.6 Sol')" <<< "$output"
  grep -Fq "$(printf 'claude-opus-5\tClaude (built-in)')" <<< "$output"
}

@test "endpoint is skipped when the binary yields a catalog" {
  make_fake_binary
  export ANTHROPIC_API_KEY="test-key"
  dm_cache_path
  make_fake_curl ok
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  grep -Fxq "claude-opus-5" <<< "$output"
  grep -Fxq "kimi3" <<< "$output"
  [ ! -f "$TEST_TEMP_DIR/curl-called" ]
}

@test "auth without binary: endpoint catalog alone" {
  export ANTHROPIC_API_KEY="test-key"
  dm_cache_path
  make_fake_curl ok
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "claude-sonnet-5" ]
  grep -Fxq "sol" <<< "$output"
  [ -f "$TEST_TEMP_DIR/curl-called" ]
}

@test "failed endpoint fetch with no binary: empty output, exit 0, negative cache" {
  export ANTHROPIC_API_KEY="test-key"
  dm_cache_path
  make_fake_curl fail
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$DM_CACHE" ]
  [ ! -s "$DM_CACHE" ]
}

@test "fresh cache served without probing" {
  make_fake_binary
  printf 'cached-model\n' > "$DM_CACHE"
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "cached-model" ]
}

@test "a re-patched binary invalidates the cache" {
  make_fake_binary
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  [ -f "$DM_CACHE" ]
  local old_cache="$DM_CACHE"
  printf 'junk fable:"claude-fable-9" junk\n' > "$TEST_TEMP_DIR/fake-claude"
  touch -t 202001010101 "$TEST_TEMP_DIR/fake-claude"
  dm_cache_path
  [ "$DM_CACHE" != "$old_cache" ]
  run bash "$SCRIPTS_DIR/detect-models.sh"
  [ "$status" -eq 0 ]
  grep -Fxq "claude-fable-9" <<< "$output"
  ! grep -Fxq "claude-opus-5" <<< "$output"
}
