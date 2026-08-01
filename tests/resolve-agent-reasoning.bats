#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  CONFIG="$TEST_TEMP_DIR/.vbw-planning/config.json"
  PROFILES="$CONFIG_DIR/reasoning-profiles.json"
  PRICING="$CONFIG_DIR/model-pricing.json"
}

teardown() {
  teardown_temp_dir
  rm -f /tmp/vbw-reasoning-* 2>/dev/null
}

set_config() {
  jq "$1" "$CONFIG" > "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
}

@test "resolves lead reasoning from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]
}

@test "resolves docs reasoning from quality profile" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" docs "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "medium" ]
}

@test "resolves from balanced profile" {
  set_config '.model_profile = "balanced"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "resolves from budget profile" {
  set_config '.model_profile = "budget"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" qa "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "matrix cell wins over profile preset" {
  set_config '.effort = "thorough" | .reasoning_matrix.dev.thorough = "max"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "max" ]
}

@test "matrix follows the configured effort" {
  set_config '.effort = "fast" | .reasoning_matrix.dev.thorough = "max" | .reasoning_matrix.dev.fast = "low"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "missing matrix cell falls through to profile preset" {
  set_config '.effort = "fast" | .reasoning_matrix.dev.thorough = "max"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]
}

@test "override wins over matrix and profile" {
  set_config '.effort = "thorough" | .reasoning_matrix.dev.thorough = "max" | .reasoning_overrides.dev = "low"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "rejects an invalid reasoning value" {
  set_config '.reasoning_overrides.dev = "turbo"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid reasoning effort"* ]]
}

@test "rejects an invalid agent name" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" nobody "$CONFIG" "$PROFILES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid agent name"* ]]
}

@test "fails when config is missing" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$TEST_TEMP_DIR/nope.json" "$PROFILES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Config not found"* ]]
}

@test "fails on an invalid model_profile" {
  set_config '.model_profile = "bogus"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" dev "$CONFIG" "$PROFILES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid model_profile"* ]]
}

@test "emits empty for a model that rejects the effort parameter" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" docs "$CONFIG" "$PROFILES" haiku "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "resolves the tier alias before checking effort support" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" docs "$CONFIG" "$PROFILES" claude-haiku-4-5 "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "falls back to the model default when the value is outside its ladder" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES" gemini-3.1-pro "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "high" ]
}

@test "keeps a value that the model does support" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES" opus "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]
}

@test "trusts the configured value for a model absent from the pricing file" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES" "vendor:custom-x[1m]" "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]
}

@test "second call hits the cache" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]

  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "xhigh" ]
}

@test "config change invalidates the cache" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$output" = "xhigh" ]

  set_config '.reasoning_overrides.lead = "low"'
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" lead "$CONFIG" "$PROFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "low" ]
}

@test "an empty result is cached and replayed" {
  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" docs "$CONFIG" "$PROFILES" haiku "$PRICING"
  [ "$output" = "" ]

  run bash "$SCRIPTS_DIR/resolve-agent-reasoning.sh" docs "$CONFIG" "$PROFILES" haiku "$PRICING"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "settings resolver emits RESOLVED_REASONING" {
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" lead "$CONFIG" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_REASONING='xhigh'"* ]]
}

@test "settings resolver emits empty reasoning for an unsupported model" {
  set_config '.model_profile = "budget"'
  run bash "$SCRIPTS_DIR/resolve-agent-settings.sh" docs "$CONFIG" "$CONFIG_DIR/model-profiles.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED_MODEL='haiku'"* ]]
  [[ "$output" == *"RESOLVED_REASONING=''"* ]]
}
