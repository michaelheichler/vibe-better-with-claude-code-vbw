#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
}

teardown() {
  teardown_temp_dir
  rm -f /tmp/vbw-model-* 2>/dev/null
}

make_resolver_fixture() {
  local fixture="$TEST_TEMP_DIR/plugin"
  mkdir -p "$fixture/scripts/lib" "$fixture/config"
  cp "$SCRIPTS_DIR/resolve-agent-model.sh" "$fixture/scripts/resolve-agent-model.sh"
  cp "$SCRIPTS_DIR/detect-models.sh" "$fixture/scripts/detect-models.sh"
  cp "$SCRIPTS_DIR/lib/vbw-cache-key.sh" "$fixture/scripts/lib/vbw-cache-key.sh"
  cp "$CONFIG_DIR/model-profiles.json" "$fixture/config/model-profiles.json"
  cp "$CONFIG_DIR/model-pricing.json" "$fixture/config/model-pricing.json"
  printf '%s\n' "$fixture"
}

run_fixture_resolver() {
  local fixture="$1"
  bash "$fixture/scripts/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$fixture/config/model-profiles.json"
}

@test "resolves dev model from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "resolves scout model from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" scout "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "resolves dev model from balanced profile" {
  jq '.model_profile = "balanced"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "respects per-agent override" {
  jq '.model_overrides.dev = "opus"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "resolves custom alias in a single-value override" {
  jq '.model_overrides.dev = "opus48"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-8" ]
}

@test "resolves custom alias in a matrix value" {
  jq '.model_matrix = {dev: {balanced: "opus48"}}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-8" ]
}

@test "custom alias is eligible in a preference array" {
  printf 'sol\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_matrix = {dev: {balanced: ["opus48", "sol"]}}' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-8" ]
}

@test "custom alias resolves without requiring catalog metadata" {
  local fixture
  fixture=$(make_resolver_fixture)
  jq '.aliases = {fixture: "custom-model"} | .models = {}' "$fixture/config/model-pricing.json" > "$fixture/config/model-pricing.json.tmp"
  mv "$fixture/config/model-pricing.json.tmp" "$fixture/config/model-pricing.json"
  jq '.model_overrides.dev = "fixture"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run run_fixture_resolver "$fixture"
  [ "$status" -eq 0 ]
  [ "$output" = "custom-model" ]
}

@test "missing pricing file leaves alias input unchanged" {
  local fixture
  fixture=$(make_resolver_fixture)
  rm "$fixture/config/model-pricing.json"
  jq '.model_overrides.dev = "opus48"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run run_fixture_resolver "$fixture"
  [ "$status" -eq 0 ]
  [ "$output" = "opus48" ]
}

@test "pricing changes invalidate resolver catalog cache" {
  local fixture pricing fake_bin
  fixture=$(make_resolver_fixture)
  pricing="$fixture/config/model-pricing.json"
  fake_bin="$TEST_TEMP_DIR/fake-claude"
  printf 'opus:"claude-opus-5"\n' > "$fake_bin"
  export CLAUDE_CODE_EXECPATH="$fake_bin"
  jq '.model_overrides.dev = "opus48"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run run_fixture_resolver "$fixture"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-8" ]

  jq '.aliases.opus48 = "claude-opus-4-9"' "$pricing" > "$pricing.tmp"
  mv "$pricing.tmp" "$pricing"
  touch -t 202601010102 "$pricing"
  run run_fixture_resolver "$fixture"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-9" ]
}

@test "rejects invalid agent name" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" invalid "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "rejects missing config file" {
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "/nonexistent/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "uses cache on second call" {
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/no-catalog"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  _fingerprint() {
    if command -v md5sum >/dev/null 2>&1; then
      md5sum "$1" | awk '{print $1}' | cut -c1-8
    elif command -v md5 >/dev/null 2>&1; then
      md5 -q "$1" | cut -c1-8
    else
      cksum "$1" | awk '{print $1}'
    fi
  }
  CONFIG_HASH=$(_fingerprint "$TEST_TEMP_DIR/.vbw-planning/config.json")
  PROFILES_HASH=$(_fingerprint "$CONFIG_DIR/model-profiles.json")
  PRICING_HASH=$(_fingerprint "$SCRIPTS_DIR/../config/model-pricing.json")
  PATH_HASH=$(vbw_hash_path "$TEST_TEMP_DIR/.vbw-planning/config.json|$CONFIG_DIR/model-profiles.json")
  [ -f "/tmp/vbw-model-dev-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}-none-${PRICING_HASH}" ]
}

@test "cache is isolated by config path even when mtimes match" {
  local alt_dir="$TEST_TEMP_DIR/alt"
  mkdir -p "$alt_dir/.vbw-planning"
  cp "$TEST_TEMP_DIR/.vbw-planning/config.json" "$alt_dir/.vbw-planning/config.json"

  jq '.model_profile = "balanced"' "$alt_dir/.vbw-planning/config.json" > "$alt_dir/.vbw-planning/config.json.tmp"
  mv "$alt_dir/.vbw-planning/config.json.tmp" "$alt_dir/.vbw-planning/config.json"

  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json" "$alt_dir/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$alt_dir/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "cache invalidates for same-path config edits within the same second" {
  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  jq '.model_profile = "balanced"' "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  touch -t 202601010101 "$TEST_TEMP_DIR/.vbw-planning/config.json"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "cache invalidates when profiles file changes within the same second" {
  local profiles_copy="$TEST_TEMP_DIR/model-profiles.json"
  cp "$CONFIG_DIR/model-profiles.json" "$profiles_copy"
  touch -t 202601010101 "$profiles_copy"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$profiles_copy"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]

  jq '.quality.dev = "sonnet"' "$profiles_copy" > "$profiles_copy.tmp"
  mv "$profiles_copy.tmp" "$profiles_copy"
  touch -t 202601010101 "$profiles_copy"

  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$profiles_copy"
  [ "$status" -eq 0 ]
  [ "$output" = "sonnet" ]
}

@test "matrix string value resolves by effort" {
  jq '.effort = "fast" | .model_matrix = {dev: {fast: "glm52", balanced: "sol"}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "glm52" ]
}

@test "matrix follows effort change in config" {
  jq '.effort = "balanced" | .model_matrix = {dev: {fast: "glm52", balanced: "sol"}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sol" ]
}

@test "matrix missing cell falls through to profile" {
  jq '.effort = "turbo" | .model_matrix = {dev: {balanced: "sol"}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "opus" ]
}

@test "preference array picks first entry present in catalog" {
  printf 'sol\nkimi3\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_matrix = {dev: {balanced: ["nope", "sol"]}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sol" ]
}

@test "model_catalog_extra makes an undetected sneak id eligible" {
  printf 'sol\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_overrides.dev = ["nope", "claude-opus-4-8"] | .model_catalog_extra = ["claude-opus-4-8"]' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-4-8" ]
}

@test "preference array with empty catalog trusts first entry" {
  : > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_matrix = {dev: {balanced: ["nope", "sol"]}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "nope" ]
}

@test "override beats matrix beats profile" {
  printf 'kimi3\nsol\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_overrides.dev = "kimi3" | .model_matrix = {dev: {balanced: "sol"}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "kimi3" ]
}

@test "override preference array resolves against catalog" {
  printf 'sol\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_overrides.dev = ["nope", "sol"]' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sol" ]
}

@test "gateway id with brackets passes shape validation" {
  jq '.model_overrides.dev = "leverframe:opencode-go:glm-5.2[1m]"' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "leverframe:opencode-go:glm-5.2[1m]" ]
}

@test "model with whitespace fails shape validation" {
  jq '.model_overrides.dev = "bad model"' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 1 ]
}

@test "catalog change invalidates resolver cache" {
  printf 'sol\n' > "$TEST_TEMP_DIR/catalog.txt"
  export VBW_MODEL_CATALOG_FILE="$TEST_TEMP_DIR/catalog.txt"
  jq '.model_matrix = {dev: {balanced: ["nope", "sol"]}}' \
    "$TEST_TEMP_DIR/.vbw-planning/config.json" > "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp"
  mv "$TEST_TEMP_DIR/.vbw-planning/config.json.tmp" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "sol" ]

  printf 'nope\n' > "$TEST_TEMP_DIR/catalog.txt"
  run bash "$SCRIPTS_DIR/resolve-agent-model.sh" dev "$TEST_TEMP_DIR/.vbw-planning/config.json" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [ "$output" = "nope" ]
}
