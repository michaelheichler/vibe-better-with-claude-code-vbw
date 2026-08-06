#!/usr/bin/env bats

load test_helper

create_mock_plugin() {
  local d="$TEST_TEMP_DIR/mock-plugin"
  mkdir -p "$d/references" "$d/templates/agent-roles" "$d/templates"
  printf '%*s' 25000 '' > "$d/references/execute-protocol.md"
  printf '%*s' 5000  '' > "$d/references/handoff-schemas.md"
  printf '%*s' 1000  '' > "$d/references/vbw-brand-essentials.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-balanced.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-thorough.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-fast.md"
  printf '%*s' 1000  '' > "$d/references/effort-profile-turbo.md"
  printf '%*s' 5000  '' > "$d/templates/agent-roles/dev.md.tpl"
  printf '%*s' 3000  '' > "$d/templates/agent-roles/qa.md.tpl"
  printf '%*s' 5000  '' > "$d/references/verification-protocol.md"
  printf '%*s' 500   '' > "$d/templates/SUMMARY.md"
  printf '%*s' 4000  '' > "$d/templates/agent-roles/lead.md.tpl"
  printf '%*s' 500   '' > "$d/templates/PLAN.md"
  printf '%*s' 500   '' > "$d/templates/UAT.md"
  printf '%*s' 5000  '' > "$d/references/discussion-engine.md"
  export CLAUDE_PLUGIN_ROOT="$d"
}

setup() {
  setup_temp_dir
  create_test_config
  create_mock_plugin
  mkdir -p "$TEST_TEMP_DIR/claude-config"
  echo '{"env":{"DISABLE_AUTO_COMPACT":"false"}}' > "$TEST_TEMP_DIR/claude-config/settings.json"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude-config"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  unset CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

AUTH_SID="test-session-auth"

write_authenticated_usage() {
  local pct="$1"
  local second="${2:-}"
  local third="${3:-}"
  local size sid

  if [ -n "$second" ] && [[ "$second" =~ ^[0-9]+$ ]]; then
    size="$second"
    sid="${third:-$AUTH_SID}"
  else
    sid="${second:-$AUTH_SID}"
    size="${third:-200000}"
  fi

  printf '%s|%s|%s\n' "$sid" "$pct" "$size" > .vbw-planning/.context-usage
}

write_unknown_usage() {
  local pct="$1"
  local size="${2:-200000}"
  printf 'unknown|%s|%s\n' "$pct" "$size" > .vbw-planning/.context-usage
}

write_legacy_usage() {
  local pct="$1"
  local size="${2:-200000}"
  printf '%s|%s\n' "$pct" "$size" > .vbw-planning/.context-usage
}


@test "suggest-compact: silent when no .context-usage file" {
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


@test "suggest-compact: silent when context at 30% (200K window)" {
  write_authenticated_usage 30
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: silent when context at 50%" {
  write_authenticated_usage 50
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: silent when context at 70% for light command" {
  write_authenticated_usage 70
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


@test "suggest-compact: warns when context at 95% for execute mode" {
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
  [[ "$output" == *"95%"* ]]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: warns when context at 99% for any mode" {
  write_authenticated_usage 99
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: warns when context at 94% for execute mode" {
  write_authenticated_usage 94
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}


@test "suggest-compact: recommends /compact for standard autonomy" {
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"RECOMMENDED"* ]]
  [[ "$output" == *"/compact"* ]]
}

@test "suggest-compact: auto-triggers for confident autonomy" {
  write_authenticated_usage 95
  jq '.autonomy = "confident"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"confident"* ]]
}

@test "suggest-compact: auto-triggers for pure-vibe autonomy" {
  write_authenticated_usage 95
  jq '.autonomy = "pure-vibe"' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"ACTION REQUIRED"* ]]
  [[ "$output" == *"pure-vibe"* ]]
}


@test "suggest-compact: plan mode has lower cost than execute" {
  write_authenticated_usage 94
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" plan
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: verify is lighter than execute" {
  write_authenticated_usage 94
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}


@test "suggest-compact: phase plans increase execute cost" {
  write_authenticated_usage 93
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 15000 '' > .vbw-planning/phases/01-setup/01-PLAN.md
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: state files contribute to cost" {
  printf '%*s' 5000 '' > .vbw-planning/STATE.md
  printf '%*s' 5000 '' > .vbw-planning/ROADMAP.md
  write_authenticated_usage 97
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" qa
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}


@test "suggest-compact: respects compaction_threshold from config" {
  write_authenticated_usage 60
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: no warn when below compaction_threshold" {
  write_authenticated_usage 40
  jq '.compaction_threshold = 130000' .vbw-planning/config.json > .vbw-planning/config.json.tmp \
    && mv .vbw-planning/config.json.tmp .vbw-planning/config.json
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}


@test "suggest-compact: handles corrupt .context-usage gracefully" {
  echo "garbage" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles empty .context-usage gracefully" {
  echo "" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles 0|0 context size gracefully" {
  echo "0|0" > .vbw-planning/.context-usage
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: handles missing config.json gracefully" {
  rm -f .vbw-planning/config.json
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: defaults to execute mode when no mode given" {
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"execute"* ]]
}

@test "suggest-compact: unknown mode uses fallback cost" {
  write_authenticated_usage 96
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" unknown_mode
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}


@test "suggest-compact: warns at 100% usage" {
  write_authenticated_usage 100
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" discuss
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}


@test "suggest-compact: output shows byte breakdown" {
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"B fixed"* ]]
  [[ "$output" == *"project files"* ]]
}


@test "statusline: writes .context-usage with session ID, pct, and size" {
  mkdir -p .vbw-planning
  export CLAUDE_SESSION_ID="test-session-abc"
  echo '{"context_window":{"used_percentage":42,"remaining_percentage":58,"context_window_size":200000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f ".vbw-planning/.context-usage" ]
  IFS='|' read -r sid pct size < .vbw-planning/.context-usage
  [ "$sid" = "test-session-abc" ]
  [ "$pct" = "50" ]
  [ "$size" = "167000" ]
}

@test "statusline: .context-usage defaults session ID to unknown" {
  mkdir -p .vbw-planning
  unset CLAUDE_SESSION_ID
  echo '{"context_window":{"used_percentage":50,"remaining_percentage":50,"context_window_size":100000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f ".vbw-planning/.context-usage" ]
  IFS='|' read -r sid pct size < .vbw-planning/.context-usage
  [ "$sid" = "unknown" ]
  [ "$pct" = "75" ]
  [ "$size" = "67000" ]
}


@test "vibe.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/vibe.md"
}

@test "qa.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/qa.md"
}

@test "verify.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/verify.md"
}

@test "discuss.md includes suggest-compact.sh expansion" {
  grep -q 'suggest-compact.sh' "$PROJECT_ROOT/commands/discuss.md"
}

@test "suggest-compact: verify excludes SOURCE-UAT from cost" {
  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 100 '' > .vbw-planning/STATE.md

  printf '%*s' 2000 '' > .vbw-planning/phases/01-setup/01-UAT.md

  printf '%*s' 50000 '' > .vbw-planning/phases/01-setup/01-SOURCE-UAT.md

  write_authenticated_usage 99

  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
}

@test "suggest-compact: verify mode does not count SOURCE-UAT bytes" {
  mkdir -p .vbw-planning/phases/01-setup
  printf '%*s' 100 '' > .vbw-planning/STATE.md
  printf '%*s' 1000 '' > .vbw-planning/phases/01-setup/01-UAT.md

  write_authenticated_usage 96
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf '%*s' 100000 '' > .vbw-planning/phases/01-setup/01-SOURCE-UAT.md
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" verify
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "vibe.md passes execute mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/vibe.md" | grep -q 'execute'
}

@test "qa.md passes qa mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/qa.md" | grep -q 'qa'
}

@test "verify.md passes verify mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/verify.md" | grep -q 'verify'
}

@test "discuss.md passes discuss mode to suggest-compact.sh" {
  grep 'suggest-compact.sh' "$PROJECT_ROOT/commands/discuss.md" | grep -q 'discuss'
}


@test "suggest-compact: stale session ID causes silent skip" {
  echo "old-session-id|95|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="new-session-id" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: matching session ID triggers normal guard" {
  echo "my-session|95|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]
}

@test "suggest-compact: legacy 2-field format skips silently" {
  write_legacy_usage 95
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: unknown session placeholder is not authoritative" {
  write_unknown_usage 95
  unset CLAUDE_SESSION_ID
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: unknown 43 percent cache skips silently" {
  write_unknown_usage 43
  unset CLAUDE_SESSION_ID
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: unknown 58 percent cache skips silently" {
  write_unknown_usage 58
  unset CLAUDE_SESSION_ID
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: 3-field format with low usage no warn" {
  write_authenticated_usage 30 my-session
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: 3-field format respects compaction threshold" {
  echo '{"compaction_threshold":165000}' > .vbw-planning/config.json
  echo "my-session|82|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [[ "$output" == *"PRE-FLIGHT CONTEXT GUARD"* ]]

  echo "my-session|30|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="my-session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: missing CLAUDE_SESSION_ID skips high-pressure cache" {
  write_authenticated_usage 95 test-session-auth
  unset CLAUDE_SESSION_ID
  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: empty CLAUDE_SESSION_ID skips high-pressure cache" {
  write_authenticated_usage 95 test-session-auth
  CLAUDE_SESSION_ID="" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: invalid cache session ID skips silently" {
  write_authenticated_usage 95 200000 "bad session"
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: invalid current session ID skips silently" {
  write_authenticated_usage 95
  CLAUDE_SESSION_ID="bad session" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: malformed 3-field used percentage skips silently" {
  echo "$AUTH_SID|abc|200000" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: malformed 3-field context size skips silently" {
  echo "$AUTH_SID|95|abc" > .vbw-planning/.context-usage
  CLAUDE_SESSION_ID="$AUTH_SID" run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "suggest-compact: statusline unknown cache stays silent in suggest-compact" {
  mkdir -p .vbw-planning
  unset CLAUDE_SESSION_ID
  echo '{"context_window":{"used_percentage":95,"remaining_percentage":5,"context_window_size":200000,"current_usage":{"input_tokens":10000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},"cost":{"total_cost_usd":0,"total_duration_ms":0,"total_api_duration_ms":0,"total_lines_added":0,"total_lines_removed":0},"model":{"display_name":"Claude"},"version":"1.0"}' \
    | bash "$SCRIPTS_DIR/vbw-statusline.sh" > /dev/null 2>&1
  [ -f .vbw-planning/.context-usage ]

  run bash "$SCRIPTS_DIR/suggest-compact.sh" execute
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
