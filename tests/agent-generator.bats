#!/usr/bin/env bats

load test_helper

status=0
output=""

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  cp "$CONFIG_DIR/defaults.json" "$TEST_TEMP_DIR/.vbw-planning/config.json"
  export VBW_AGENT_SETTINGS_SCRIPT=""
  export VBW_AGENT_WORDLIST_A=""
  export VBW_AGENT_WORDLIST_B=""
  export VBW_AGENT_RANDOM_SEED=""
}

teardown() {
  unset VBW_AGENT_SETTINGS_SCRIPT VBW_AGENT_WORDLIST_A VBW_AGENT_WORDLIST_B VBW_AGENT_RANDOM_SEED
  teardown_temp_dir
}

run_generator() {
  (cd "$TEST_TEMP_DIR" && bash "$SCRIPTS_DIR/agent-generator.sh" "$@")
}

make_settings_stub() {
  cat > "$TEST_TEMP_DIR/settings.sh" <<'EOF'
#!/usr/bin/env bash
printf "RESOLVED_AGENT='%s'\n" "$1"
printf "RESOLVED_MODEL='sonnet'\n"
printf "RESOLVED_MAX_TURNS='20'\n"
printf "RESOLVED_EFFORT='balanced'\n"
printf "RESOLVED_REASONING='%s'\n" "${VBW_TEST_REASONING-high}"
EOF
  chmod +x "$TEST_TEMP_DIR/settings.sh"
  export VBW_AGENT_SETTINGS_SCRIPT="$TEST_TEMP_DIR/settings.sh"
}

@test_generator_happy_path_registers_agent() { # @test
  run run_generator dev --job 'Build the assigned task.'

  [ "$status" -eq 0 ]
  name=$(sed -n 's/^SPAWN_READY //p' <<< "$output")
  [ -n "$name" ]
  [[ "$output" == *"subagent_type: $name"* ]]
  [ -f "$TEST_TEMP_DIR/.claude/agents/$name.md" ]
  jq -e --arg name "$name" '.agents[$name].state == "registered" and .agents[$name].role == "dev"' "$TEST_TEMP_DIR/.vbw-planning/.agent-manifest.json" >/dev/null
}

@test_generator_retries_name_collision() { # @test
  printf 'red\nblue\n' > "$TEST_TEMP_DIR/adjectives"
  printf 'fox\n' > "$TEST_TEMP_DIR/nouns"
  mkdir -p "$TEST_TEMP_DIR/.claude/agents"
  touch "$TEST_TEMP_DIR/.claude/agents/vbw-dev-red-red-fox.md"
  touch "$TEST_TEMP_DIR/.claude/agents/vbw-dev-blue-blue-fox.md"
  make_settings_stub
  export VBW_AGENT_WORDLIST_A="$TEST_TEMP_DIR/adjectives"
  export VBW_AGENT_WORDLIST_B="$TEST_TEMP_DIR/nouns"
  export VBW_AGENT_RANDOM_SEED=0

  run run_generator dev --job collision

  [ "$status" -eq 0 ]
  [[ "$output" == *'SPAWN_READY vbw-dev-red-blue-fox'* ]]
  [ -f "$TEST_TEMP_DIR/.claude/agents/vbw-dev-red-blue-fox.md" ]
}

@test_generator_refuses_four_live_agents() { # @test
  jq -n '{agents:{one:{state:"registered"},two:{state:"running"},three:{state:"registered"},four:{state:"running"}}}' \
    > "$TEST_TEMP_DIR/.vbw-planning/.agent-manifest.json"

  run run_generator dev --job blocked

  [ "$status" -eq 1 ]
  [[ "$output" == *'agent cap reached'* ]]
}

@test_generator_overrides_reach_frontmatter() { # @test
  make_settings_stub

  run run_generator dev --job override \
    --description 'Custom description' --tools 'Read' --disallowed-tools 'Bash' \
    --permission-mode plan --max-turns 12 --skills 'testing' --mcp-servers 'docs' \
    --memory local --background true --isolation worktree --color cyan \
    --initial-prompt 'Start here.' --model haiku --effort fast

  [ "$status" -eq 0 ]
  name=$(sed -n 's/^SPAWN_READY //p' <<< "$output")
  file="$TEST_TEMP_DIR/.claude/agents/$name.md"
  grep -q '^description: "Custom description"$' "$file"
  grep -q '^tools: "Read"$' "$file"
  grep -q '^disallowedTools: "Bash"$' "$file"
  grep -q '^permissionMode: "plan"$' "$file"
  grep -q '^maxTurns: "12"$' "$file"
  grep -q '^model: "haiku"$' "$file"
  grep -q '^effort: "fast"$' "$file"
}

@test_generator_omits_empty_resolved_effort() { # @test
  make_settings_stub
  export VBW_TEST_REASONING=""

  run run_generator dev --job 'No effort line.'

  [ "$status" -eq 0 ]
  name=$(sed -n 's/^SPAWN_READY //p' <<< "$output")
  ! grep -q '^effort:' "$TEST_TEMP_DIR/.claude/agents/$name.md"
}
