#!/usr/bin/env bats

load test_helper
@test "prompt-preflight creates .vbw-session for expanded command content" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"prompt":"---\nname: vbw:vibe\ndescription: Main entry point\n---\n# VBW Vibe\nPlan mode..."}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT delete .vbw-session on plain text follow-up" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"prompt":"yes, go ahead"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight preserves .vbw-session on non-VBW slash command" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"prompt":"/gsd:status"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "prompt-preflight does NOT create .vbw-session from plain text containing name: vbw:" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"prompt":"Please explain this YAML fragment: name: vbw:vibe"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "security-filter resolves .planning marker checks from FILE_PATH root" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.planning" "$REPO_B/.vbw-planning"
  touch "$REPO_A/.vbw-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter blocks .planning write when target repo has active marker" {
  setup_temp_dir
  local REPO_A="$TEST_TEMP_DIR/repo-a"
  local REPO_B="$TEST_TEMP_DIR/repo-b"
  mkdir -p "$REPO_A/.vbw-planning" "$REPO_B/.planning" "$REPO_B/.vbw-planning"
  touch "$REPO_B/.vbw-planning/.active-agent"
  INPUT='{"tool_input":{"file_path":"'"$REPO_B"'/.planning/STATE.md"}}'
  run bash -c "cd '$REPO_A' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  teardown_temp_dir
}

@test "security-filter ignores root aggregate active-agent for other safe session" {
  setup_temp_dir
  local REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO/.planning" "$REPO/.vbw-planning"
  printf '%s\n' '{"session_id":"session-A","agent_type":"vbw-scout","pid":"10101"}' | \
    VBW_PLANNING_DIR="$REPO/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  INPUT=$(jq -n --arg sid 'session-B' --arg fp "$REPO/.planning/STATE.md" '{session_id:$sid,tool_input:{file_path:$fp}}')
  run bash -c "cd '$REPO' && printf '%s\n' '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter blocks .planning for current safe active-agent session" {
  setup_temp_dir
  local REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO/.planning" "$REPO/.vbw-planning"
  sleep 30 & dev_pid=$!
  printf '%s\n' "{\"session_id\":\"session-A\",\"agent_type\":\"vbw-dev\",\"pid\":\"$dev_pid\"}" | \
    VBW_PLANNING_DIR="$REPO/.vbw-planning" bash "$SCRIPTS_DIR/agent-start.sh"

  INPUT=$(jq -n --arg sid 'session-A' --arg fp "$REPO/.planning/STATE.md" '{session_id:$sid,tool_input:{file_path:$fp}}')
  run bash -c "cd '$REPO' && printf '%s\n' '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  kill "$dev_pid" 2>/dev/null || true
  teardown_temp_dir
}

@test "security-filter treats .vbw-session as project-global .planning guard" {
  setup_temp_dir
  local REPO="$TEST_TEMP_DIR/repo"
  mkdir -p "$REPO/.planning" "$REPO/.vbw-planning"
  echo "session" > "$REPO/.vbw-planning/.vbw-session"

  INPUT=$(jq -n --arg sid 'session-B' --arg fp "$REPO/.planning/STATE.md" '{session_id:$sid,tool_input:{file_path:$fp}}')
  run bash -c "cd '$REPO' && printf '%s\n' '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 2 ]
  teardown_temp_dir
}

@test "security-filter allows .vbw-planning writes regardless of marker staleness" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  touch -t 202401010101 "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "session-stop preserves .vbw-session and removes transient agent markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo "scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent"
  echo "2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count"
  echo "scout 2" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles"
  echo "12345 scout" > "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-roles" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agent-role-pids" ]
  teardown_temp_dir
}

@test "vbw session marker survives Stop and non-VBW slash commands" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/milestones/default/phases/05-migration-preview-completeness"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/vbw:verify 5\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"it says 16 positions to move\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  INPUT='{"tool_input":{"file_path":"'"$TEST_TEMP_DIR"'/.vbw-planning/milestones/default/phases/05-migration-preview-completeness/05-UAT.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]

  run bash -c "cd '$TEST_TEMP_DIR' && echo '{\"prompt\":\"/gsd:status\"}' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]

  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows role-only task subjects like Lead" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_subject\":\"Lead\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "security-filter falls back to CWD for relative FILE_PATH" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"tool_input":{"file_path":".vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "security-filter allows relative .vbw-planning FILE_PATH without markers" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  INPUT='{"tool_input":{"file_path":".vbw-planning/STATE.md"}}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/security-filter.sh'"
  teardown_temp_dir
  [ "$status" -eq 0 ]
}

@test "prompt-preflight does NOT delete .vbw-session when prompt is a file path" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  touch "$TEST_TEMP_DIR/.vbw-planning/.gsd-isolation"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  INPUT='{"prompt":"/home/user/project/file.txt"}'
  run bash -c "cd '$TEST_TEMP_DIR' && echo '$INPUT' | bash '$SCRIPTS_DIR/prompt-preflight.sh'"
  [ "$status" -eq 0 ]
  [ -f "$TEST_TEMP_DIR/.vbw-planning/.vbw-session" ]
  teardown_temp_dir
}

@test "session-stop cleans up stale lock directory" {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count.lock"
  run bash -c "cd '$TEST_TEMP_DIR' && echo '{}' | bash '$SCRIPTS_DIR/session-stop.sh'"
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_TEMP_DIR/.vbw-planning/.active-agent-count.lock" ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_subject" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_subject\":\"Hypothesis 1: race condition in sync [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] tag in task_description fallback" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_description\":\"Investigate memory leak [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "task-verify allows non-execute tasks without matching commit" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "chore(test): seed commit"
  run bash -c "echo '{\"task_subject\":\"Implement caching layer for database queries\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  teardown_temp_dir
}

@test "task-verify emits advisory for execute task without matching commit" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  git commit -q -m "docs: unrelated change"
  run bash -c "echo '{\"task_subject\":\"Execute 07-01: Implement caching layer for database queries\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "TaskCompleted"' >/dev/null
  echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "recent matching commit"
  teardown_temp_dir
}

@test "task-verify allows [analysis-only] even with no recent commits" {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  mkdir -p .vbw-planning
  echo "hello" > file.txt
  git add file.txt
  GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
    git commit -q -m "chore(test): ancient seed commit"
  run bash -c "echo '{\"task_subject\":\"Hypothesis 2: deadlock in worker pool [analysis-only]\"}' | bash '$SCRIPTS_DIR/task-verify.sh'"
  [ "$status" -eq 0 ]
  teardown_temp_dir
}

@test "hooks matcher includes prefixed VBW agent names" {
  run bash -c "grep -q 'vbw:vbw-scout' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}

@test "hooks matcher includes team role aliases" {
  run bash -c "grep -q 'team-lead' '$PROJECT_ROOT/hooks/hooks.json'"
  [ "$status" -eq 0 ]
}
