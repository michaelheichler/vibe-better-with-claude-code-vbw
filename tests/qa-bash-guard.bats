#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A"
  printf '1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-count"
  printf 'scout 1\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent-roles"
  printf 'scout\n' > "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-A/active-agent"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

run_qa_bash_guard() {
  local test_project="$1"
  local command="$2"
  local test_input

  test_input=$(jq -n --arg cmd "$command" '{"tool_input":{"command":$cmd}}')
  run bash -c 'cd "$1" && printf "%s\n" "$2" | VBW_AGENT_ROLE=qa bash "$3"' _ \
    "$test_project" "$test_input" "$PROJECT_ROOT/scripts/bash-guard.sh"
}

run_role_bash_guard() {
  local role="$1"
  local test_project="$2"
  local command="$3"
  local test_input

  test_input=$(jq -n --arg cmd "$command" '{"tool_input":{"command":$cmd}}')
  run bash -c 'cd "$1" && printf "%s\n" "$2" | VBW_AGENT_ROLE="$3" bash "$4"' _ \
    "$test_project" "$test_input" "$role" "$PROJECT_ROOT/scripts/bash-guard.sh"
}

new_test_project() {
  local dir="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$dir/.vbw-planning"
  echo '{"bash_guard":true}' > "$dir/.vbw-planning/config.json"
  echo "$dir"
}

@test "bash-guard: qa allows read-only helper and git inspection commands" {
  TEST_PROJECT=$(new_test_project qa-safe)
  run_qa_bash_guard "$TEST_PROJECT" "git status --short && git log -1"
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa allows running the project test suite" {
  TEST_PROJECT=$(new_test_project qa-tests)
  run_qa_bash_guard "$TEST_PROJECT" "bash testing/run-all.sh"
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa allows the sanctioned write-verification.sh persistence path" {
  TEST_PROJECT=$(new_test_project qa-persist)
  run_qa_bash_guard "$TEST_PROJECT" 'echo "$QA_VERDICT_JSON" | bash "/plugin/root/scripts/write-verification.sh" ".vbw-planning/phases/01-x/01-VERIFICATION.md"'
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa blocks shell redirection writes" {
  TEST_PROJECT=$(new_test_project qa-redirect)
  run_qa_bash_guard "$TEST_PROJECT" "echo bad > out.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"shell file write/redirection"* ]]
}

@test "bash-guard: qa allows quoted or piped mutation words in data" {
  TEST_PROJECT=$(new_test_project qa-mutation-evidence)

  run_qa_bash_guard "$TEST_PROJECT" 'echo "JSON payload: mv file done"'
  [ "$status" -eq 0 ]

  run_qa_bash_guard "$TEST_PROJECT" "printf '%s\\n' 'JSON payload: mv file done' | cat"
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa allows file-descriptor redirects without writes" {
  TEST_PROJECT=$(new_test_project qa-fd-redirect)

  for command in "git status 2>/dev/null" "git status >/dev/null" "git status 2>&1"; do
    run_qa_bash_guard "$TEST_PROJECT" "$command"
    [ "$status" -eq 0 ]
  done

  run_qa_bash_guard "$TEST_PROJECT" "git status > out.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"shell file write/redirection"* ]]
}

@test "bash-guard: qa blocks bare filesystem mutation commands" {
  TEST_PROJECT=$(new_test_project qa-mv-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "mv old.txt new.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: quoted CLI arguments remain executable evidence" {
  TEST_PROJECT=$(new_test_project qa-quoted-cli)
  run_role_bash_guard dev "$TEST_PROJECT" "php artisan 'migrate:fresh'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"destructive command detected"* ]]
}

@test "bash-guard: long sudo options do not hide filesystem mutations" {
  TEST_PROJECT=$(new_test_project qa-sudo-long)
  run_qa_bash_guard "$TEST_PROJECT" "sudo --user bob rm file"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: leading redirection does not hide filesystem mutations" {
  TEST_PROJECT=$(new_test_project qa-leading-redirect)
  run_qa_bash_guard "$TEST_PROJECT" "< /dev/null rm file"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: read-write redirection does not hide filesystem mutations" {
  TEST_PROJECT=$(new_test_project qa-read-write-redirect)
  run_qa_bash_guard "$TEST_PROJECT" "<> /dev/null rm file"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: attached read-write redirection does not hide filesystem mutations" {
  TEST_PROJECT=$(new_test_project qa-attached-read-write-redirect)
  run_qa_bash_guard "$TEST_PROJECT" "<>/dev/null rm -rf build/"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: destructive SQL in a quoted CLI argument is executable evidence" {
  TEST_PROJECT=$(new_test_project qa-quoted-sql)
  run_qa_bash_guard "$TEST_PROJECT" "mysql appdb -e \"DROP TABLE users\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"destructive command detected"* ]]
}

@test "bash-guard: destructive text in git predicates is not executable evidence" {
  TEST_PROJECT=$(new_test_project qa-git-predicate)
  run_role_bash_guard dev "$TEST_PROJECT" "git log --grep='artisan migrate:fresh'"
  [ "$status" -eq 0 ]
}

@test "bash-guard: git alias payloads remain executable evidence" {
  TEST_PROJECT=$(new_test_project qa-git-alias-payload)
  run_role_bash_guard dev "$TEST_PROJECT" "git -c alias.danger='!php artisan migrate:fresh' danger"
  [ "$status" -eq 2 ]
  [[ "$output" == *"destructive command detected"* ]]
}

@test "bash-guard: quoted destructive evidence does not trigger the pattern blocklist" {
  TEST_PROJECT=$(new_test_project destructive-evidence)
  run_role_bash_guard dev "$TEST_PROJECT" 'echo "artisan migrate:fresh output"'
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa blocks tee" {
  TEST_PROJECT=$(new_test_project qa-tee)
  run_qa_bash_guard "$TEST_PROJECT" "echo bad | tee out.txt"
  [ "$status" -eq 2 ]
  [[ "$output" == *"tee can write files"* ]]
}

@test "bash-guard: qa blocks in-place edit commands" {
  TEST_PROJECT=$(new_test_project qa-sed)
  run_qa_bash_guard "$TEST_PROJECT" "sed -i 's/a/b/' src/app.js"
  [ "$status" -eq 2 ]
  [[ "$output" == *"in-place edit command"* ]]
}

@test "bash-guard: qa blocks git state mutation" {
  TEST_PROJECT=$(new_test_project qa-git-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "git commit -am 'oops'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git state mutation command"* ]]
}

@test "bash-guard: qa blocks filesystem mutation commands" {
  TEST_PROJECT=$(new_test_project qa-fs-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "rm -rf build/"
  [ "$status" -eq 2 ]
  [[ "$output" == *"filesystem mutation command"* ]]
}

@test "bash-guard: qa blocks package mutation commands" {
  TEST_PROJECT=$(new_test_project qa-pkg-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "npm install left-pad"
  [ "$status" -eq 2 ]
  [[ "$output" == *"package or dependency mutation command"* ]]
}

@test "bash-guard: qa blocks service/container mutation commands" {
  TEST_PROJECT=$(new_test_project qa-service-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "docker compose up -d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"service/container mutation command"* ]]
}

@test "bash-guard: qa blocks eval commands" {
  TEST_PROJECT=$(new_test_project qa-eval)
  run_qa_bash_guard "$TEST_PROJECT" "eval \"\$(cat payload.sh)\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"command substitution"* || "$output" == *"eval command"* ]]
}

@test "bash-guard: qa blocks command substitution" {
  TEST_PROJECT=$(new_test_project qa-cmdsub)
  run_qa_bash_guard "$TEST_PROJECT" 'echo "$(rm -rf /)"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"command substitution"* ]]
}

@test "bash-guard: qa blocks process substitution" {
  TEST_PROJECT=$(new_test_project qa-procsub)
  run_qa_bash_guard "$TEST_PROJECT" "diff <(echo a) <(echo b)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"process substitution"* ]]
}

@test "bash-guard: qa blocks nested shell execution" {
  TEST_PROJECT=$(new_test_project qa-nested-shell)
  run_qa_bash_guard "$TEST_PROJECT" "bash -c 'echo bad > out.txt'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nested shell execution"* ]]
}

@test "bash-guard: qa blocks sensitive file reads" {
  TEST_PROJECT=$(new_test_project qa-sensitive)
  run_qa_bash_guard "$TEST_PROJECT" "cat .env"
  [ "$status" -eq 2 ]
  [[ "$output" == *"sensitive file read"* ]]
}

@test "bash-guard: qa blocks raw SQL mutation via mysql CLI" {
  TEST_PROJECT=$(new_test_project qa-mysql-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "mysql -uroot appdb -e \"UPDATE users SET admin=1\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa blocks raw SQL mutation via psql CLI" {
  TEST_PROJECT=$(new_test_project qa-psql-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "psql appdb -c \"DELETE FROM sessions\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa blocks raw mutation via mongosh CLI" {
  TEST_PROJECT=$(new_test_project qa-mongo-mutate)
  run_qa_bash_guard "$TEST_PROJECT" "mongosh appdb --eval 'db.users.insertOne({a:1})'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa allows read-only database queries" {
  TEST_PROJECT=$(new_test_project qa-db-read)
  run_qa_bash_guard "$TEST_PROJECT" "mysql -uroot appdb -e \"SELECT * FROM users\""
  [ "$status" -eq 0 ]

  run_qa_bash_guard "$TEST_PROJECT" "psql appdb -c \"EXPLAIN SELECT 1\""
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa blocks path-qualified raw SQL mutation" {
  TEST_PROJECT=$(new_test_project qa-mysql-path-qualified)
  run_qa_bash_guard "$TEST_PROJECT" "/usr/bin/mysql -uroot appdb -e \"UPDATE users SET admin=1\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa allows a read-only query whose literal text contains a mutation word" {
  TEST_PROJECT=$(new_test_project qa-db-read-literal)
  run_qa_bash_guard "$TEST_PROJECT" "mysql -uroot appdb -e \"SELECT * FROM users WHERE status='UPDATE_PENDING'\""
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa blocks DB CLI reading SQL from a redirected file" {
  TEST_PROJECT=$(new_test_project qa-mysql-redirect)
  run_qa_bash_guard "$TEST_PROJECT" "mysql appdb < mutation.sql"
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa blocks DB CLI reading SQL from a quoted redirected filename" {
  TEST_PROJECT=$(new_test_project qa-mysql-redirect-quoted)
  run_qa_bash_guard "$TEST_PROJECT" 'mysql appdb < "mutation.sql"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa blocks stored-procedure invocation via CALL" {
  TEST_PROJECT=$(new_test_project qa-mysql-call)
  run_qa_bash_guard "$TEST_PROJECT" "mysql appdb --execute=\"CALL mutate_users()\""
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa allows a read-only query containing a quoted less-than comparison" {
  TEST_PROJECT=$(new_test_project qa-db-lt-comparison)
  run_qa_bash_guard "$TEST_PROJECT" "mysql -uroot appdb -e \"SELECT * FROM t WHERE id < 10\""
  [ "$status" -eq 0 ]
}

@test "bash-guard: qa blocks unquoted escaped-space mutation arguments" {
  TEST_PROJECT=$(new_test_project qa-mysql-unquoted-mutate)
  run_qa_bash_guard "$TEST_PROJECT" 'mysql -e UPDATE\ users\ SET\ admin=1'
  [ "$status" -eq 2 ]
  [[ "$output" == *"raw database mutation via CLI"* ]]
}

@test "bash-guard: qa blocks framework destructive-command patterns like scout does" {
  TEST_PROJECT=$(new_test_project qa-framework-destructive)
  run_qa_bash_guard "$TEST_PROJECT" "php artisan migrate:fresh"
  [ "$status" -eq 2 ]
}

@test "bash-guard: payload-less caller does not inherit active-agent marker as qa" {
  TEST_PROJECT=$(new_test_project qa-marker)
  echo qa > "$TEST_PROJECT/.vbw-planning/.active-agent"

  TEST_INPUT='{"tool_input":{"command":"cat .env"}}'
  run env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
    bash -c "cd '$TEST_PROJECT' && printf '%s\n' '$TEST_INPUT' | bash '$PROJECT_ROOT/scripts/bash-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "bash-guard: payload-less caller does not inherit active-agent-roles file as qa" {
  TEST_PROJECT=$(new_test_project qa-roles-file)
  cat > "$TEST_PROJECT/.vbw-planning/.active-agent-roles" <<'EOF'
qa 1
dev 1
EOF

  TEST_INPUT='{"tool_input":{"command":"rm -rf build/"}}'
  run env -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
    bash -c "cd '$TEST_PROJECT' && printf '%s\n' '$TEST_INPUT' | bash '$PROJECT_ROOT/scripts/bash-guard.sh'"
  [ "$status" -eq 0 ]
}

@test "bash-guard: payload role wins over shared session qa state for concurrent subagents" {
  TEST_PROJECT=$(new_test_project concurrent-docs-qa)
  SESSION_ID="shared-orchestrator-session"
  mkdir -p "$TEST_PROJECT/.vbw-planning/.active-agents/$SESSION_ID"
  printf 'qa 1\n' > "$TEST_PROJECT/.vbw-planning/.active-agents/$SESSION_ID/active-agent-roles"

  TEST_INPUT=$(jq -n \
    --arg session_id "$SESSION_ID" \
    --arg agent_id "docs-agent-1" \
    --arg agent_type "vbw:vbw-docs" \
    --arg command "git commit -am 'wip'" \
    '{session_id:$session_id,agent_id:$agent_id,agent_type:$agent_type,tool_input:{command:$command}}')
  run env -u VBW_AGENT_ROLE -u VBW_ACTIVE_AGENT -u VBW_PLANNING_DIR \
    -u CLAUDE_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
    bash -c 'cd "$1" && printf "%s\n" "$2" | bash "$3"' _ \
    "$TEST_PROJECT" "$TEST_INPUT" "$PROJECT_ROOT/scripts/bash-guard.sh"

  [ "$status" -eq 0 ]
}

@test "bash-guard: non-restricted roles are unaffected by the qa/scout read-only blocklist" {
  TEST_PROJECT=$(new_test_project role-dev-unrestricted)
  for role in dev debugger docs architect lead; do
    run_role_bash_guard "$role" "$TEST_PROJECT" "echo bad > out.txt"
    [ "$status" -eq 0 ]
    run_role_bash_guard "$role" "$TEST_PROJECT" "git commit -am 'wip'"
    [ "$status" -eq 0 ]
  done
}

@test "bash-guard: qa block reason survives destructive override env var" {
  TEST_PROJECT=$(new_test_project qa-override)
  test_input=$(jq -n --arg cmd "echo bad > out.txt" '{"tool_input":{"command":$cmd}}')
  run bash -c 'cd "$1" && printf "%s\n" "$2" | VBW_AGENT_ROLE=qa VBW_ALLOW_DESTRUCTIVE=1 bash "$3"' _ \
    "$TEST_PROJECT" "$test_input" "$PROJECT_ROOT/scripts/bash-guard.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"shell file write/redirection"* ]]
}

@test "bash-guard treats payload without agent fields as orchestrator" {
  local input
  input=$(jq -n '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body ok"}}')

  run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 0 ]
}

@test "bash-guard classifies explicit Scout payload" {
  local field identity input
  rm -rf "$TEST_TEMP_DIR/.vbw-planning/.active-agents"

  for field in agent_type agent_id; do
    identity="vbw:vbw-scout"
    [ "$field" = "agent_id" ] && identity="scout-01"
    input=$(jq -n --arg field "$field" --arg identity "$identity" \
      '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body blocked"}} + {($field):$identity}')

    run bash -c 'unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ "$input" "$SCRIPTS_DIR/bash-guard.sh"

    [ "$status" -eq 2 ]
    [[ "$output" == *"mutating gh command"* ]]
  done
}

@test "bash-guard child caller does not inherit stale Scout marker" {
  local input
  input=$(jq -n '{session_id:"session-A",tool_input:{command:"gh issue comment 1 --body ok"}}')

  run bash -c 'CLAUDE_CODE_CHILD_SESSION=1; unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT; printf "%s\n" "$1" | bash "$2"' _ \
    "$input" "$SCRIPTS_DIR/bash-guard.sh"

  [ "$status" -eq 0 ]
}
