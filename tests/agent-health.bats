#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export HEALTH_DIR="$TEST_TEMP_DIR/.vbw-planning/.agent-health"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/.claude"
}

teardown() {
  unset CLAUDE_CONFIG_DIR
  teardown_temp_dir
}

run_health_via_wrapper() {
  local cmd="$1"
  local payload="$2"
  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s' '$payload' | CLAUDE_PLUGIN_ROOT='$PROJECT_ROOT' bash '$SCRIPTS_DIR/hook-wrapper.sh' agent-health.sh '$cmd'"
}

@test "agent-health: start creates health file" {
  cd "$TEST_TEMP_DIR"
  run bash -c "echo '{\"pid\":\"12345\",\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' start"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$HEALTH_DIR/dev.json" ]
  run jq -r '.pid' "$HEALTH_DIR/dev.json"
  [ "$output" = "12345" ]
  run jq -r '.role' "$HEALTH_DIR/dev.json"
  [ "$output" = "dev" ]
  run jq -r '.idle_count' "$HEALTH_DIR/dev.json"
  [ "$output" = "0" ]
}

@test "agent-health: start prefers agent_id for health file key" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12345","agent_id":"agent-abc123","agent_type":"vbw-dev","name":"dev-01"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/agent-abc123.json" ]
  run jq -r '.key' "$HEALTH_DIR/agent-abc123.json"
  [ "$output" = "agent-abc123" ]
  run jq -r '.role' "$HEALTH_DIR/agent-abc123.json"
  [ "$output" = "dev" ]
}

@test "agent-health: start accepts legacy agentName field" {
  cd "$TEST_TEMP_DIR"
  echo '{"pid":"12346","agentName":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/qa.json" ]
  run jq -r '.role' "$HEALTH_DIR/qa.json"
  [ "$output" = "qa" ]
}

@test "agent-health: start falls back to explicit legacy VBW name when native agent_type is non-VBW" {
  cd "$TEST_TEMP_DIR"
  echo '{"agent_type":"helper-agent","agent_name":"vbw-dev-01","pid":"12347"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ -f "$HEALTH_DIR/vbw-dev-01.json" ] || [ -f "$HEALTH_DIR/dev-01.json" ]
  if [ -f "$HEALTH_DIR/dev-01.json" ]; then
    run jq -r '.role' "$HEALTH_DIR/dev-01.json"
  else
    run jq -r '.role' "$HEALTH_DIR/vbw-dev-01.json"
  fi
  [ "$output" = "dev" ]
}

@test "agent-health: wrapper-routed start initializes from documented native payload without pid" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-no-pid","agent_type":"vbw-dev"}'
  [ "$status" -eq 0 ]
  [ -f "$HEALTH_DIR/agent-no-pid.json" ]
  run jq -r '.role' "$HEALTH_DIR/agent-no-pid.json"
  [ "$output" = "dev" ]
  run jq -r '.pid' "$HEALTH_DIR/agent-no-pid.json"
  [ -z "$output" ]
}

@test "agent-health: wrapper-routed no-pid start file is reused by idle via agent_id" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-idle","agent_type":"vbw-qa"}'
  [ "$status" -eq 0 ]

  echo '{"agent_id":"agent-idle","agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  run jq -r '.idle_count' "$HEALTH_DIR/agent-idle.json"
  [ "$output" = "1" ]
  run jq -r '.pid' "$HEALTH_DIR/agent-idle.json"
  [ -z "$output" ]
}

@test "agent-health: idle increments count" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

    echo '{"agent_type":"vbw-qa"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

    run jq -r '.idle_count' "$HEALTH_DIR/qa.json"
  [ "$output" = "1" ]
}

@test "agent-health: idle stuck advisory" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-scout\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

    for i in 1 2 3; do
    echo '{"agent_type":"vbw-scout"}' | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done

    run bash -c "echo '{\"agent_type\":\"vbw-scout\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"idle_count=4"* ]]
}

@test "agent-health: orphan recovery clears owner" {
  cd "$TEST_TEMP_DIR"
    TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-test.json" <<EOF
{
  "id": "task-test",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Test task"
}
EOF

    local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

    run bash -c "echo '{\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"Orphan recovery"* ]]
  [[ "$output" == *"task-test"* ]]

    run jq -r '.owner' "$TASKS_DIR/task-test.json"
  [ "$output" = "" ]

    rm -rf "$TASKS_DIR"
}

@test "agent-health: stop orphan recovery still uses role when key comes from agent_id" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-stop-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-stop.json" <<EOF
{
  "id": "task-stop",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Stop recovery task"
}
EOF

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-stop-001\",\"agent_type\":\"vbw:vbw-dev\",\"name\":\"dev-01\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-stop-001\",\"agent_type\":\"vbw:vbw-dev\",\"name\":\"dev-01\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run jq -r '.owner' "$TASKS_DIR/task-stop.json"
  [ "$output" = "" ]

  grep -q 'task-stop' .vbw-planning/.hook-errors.log

  rm -rf "$TASKS_DIR"
}

@test "agent-health: orphan recovery preserves role-owned task when another same-role teammate is still alive" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks/test-team-shared-$$"
  mkdir -p "$TASKS_DIR"

  cat > "$TASKS_DIR/task-shared.json" <<EOF
{
  "id": "task-shared",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Shared dev task"
}
EOF

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  echo "{\"pid\":\"$live_pid\",\"agent_id\":\"agent-live\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  echo "{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-dead\",\"agent_type\":\"vbw-dev\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  run bash -c "echo '{\"pid\":\"$dead_pid\",\"agent_id\":\"agent-dead\",\"agent_type\":\"vbw-dev\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run jq -r '.owner' "$TASKS_DIR/task-shared.json"
  [ "$output" = "dev" ]

  grep -q 'another live teammate' .vbw-planning/.hook-errors.log

  rm -rf "$TASKS_DIR"
}

@test "agent-health: no-pid native stop removes health file via agent_id" {
  cd "$TEST_TEMP_DIR"
  run_health_via_wrapper start '{"agent_id":"agent-stop-nopid","agent_type":"vbw-dev"}'
  [ "$status" -eq 0 ]
  [ -f "$HEALTH_DIR/agent-stop-nopid.json" ]

  echo '{"agent_id":"agent-stop-nopid","agent_type":"vbw-dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" stop >/dev/null

  [ ! -f "$HEALTH_DIR/agent-stop-nopid.json" ]
}

@test "agent-health: stop removes health file" {
  cd "$TEST_TEMP_DIR"
  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"
  echo "{\"pid\":\"$live_pid\",\"agent_type\":\"vbw-qa\"}" | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

    [ -f "$HEALTH_DIR/qa.json" ]

    run bash -c "echo '{\"agent_type\":\"vbw-qa\"}' | bash '$SCRIPTS_DIR/agent-health.sh' stop"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

    [ ! -f "$HEALTH_DIR/qa.json" ]
}

@test "agent-health: start ignores bare native agent_type even in a VBW session" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo '{"pid":"12345","agent_type":"dev"}' | bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  [ ! -d "$HEALTH_DIR" ] || [ ! -f "$HEALTH_DIR/dev.json" ]
}

@test "agent-health: idle ignores non-VBW team_name even in a VBW session" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  echo "session" > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"

  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"external-team\",\"pid\":\"$$\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -d "$HEALTH_DIR" ] || [ ! -f "$HEALTH_DIR/dev-01.json" ]
}

@test "agent-health: idle accepts legacy teammate_name for VBW-owned team namespaces" {
  cd "$TEST_TEMP_DIR"

  while IFS='|' read -r teammate expected_role team_name; do
    key="${team_name}__${teammate}"
    run bash -c "echo '{\"teammate_name\":\"$teammate\",\"team_name\":\"$team_name\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle >/dev/null"
    [ "$status" -eq 0 ]

    run jq -r '.key' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$key" ]
    run jq -r '.role' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$expected_role" ]
    run jq -r '.team_name' "$HEALTH_DIR/${key}.json"
    [ "$output" = "$team_name" ]
    run jq -r '.idle_count' "$HEALTH_DIR/${key}.json"
    [ "$output" = "1" ]
  done <<'EOF'
dev-01|dev|vbw-phase-01
debugger-01|debugger|vbw-debug-1741625400
scout-01|scout|vbw-map-duo
scout-02|scout|vbw-map-quad
EOF
}

@test "agent-health: orphan recovery stays within matching legacy team_name scope" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks"
  mkdir -p "$TASKS_DIR/vbw-phase-01" "$TASKS_DIR/vbw-map-duo"

  cat > "$TASKS_DIR/vbw-phase-01/task-phase.json" <<EOF
{
  "id": "task-phase",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Phase team task"
}
EOF

  cat > "$TASKS_DIR/vbw-map-duo/task-map.json" <<EOF
{
  "id": "task-map",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Map team task"
}
EOF

  local live_pid
  assign_live_pid live_pid || fail "assign_live_pid failed"
  kill -0 "$live_pid" 2>/dev/null || fail "live pid fixture is not alive"

  echo "{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-map-duo\",\"pid\":\"$live_pid\"}" | bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-phase-01\",\"pid\":\"$dead_pid\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"task-phase"* ]]

  run jq -r '.owner' "$TASKS_DIR/vbw-phase-01/task-phase.json"
  [ "$output" = "" ]
  run jq -r '.owner' "$TASKS_DIR/vbw-map-duo/task-map.json"
  [ "$output" = "dev" ]
}

@test "agent-health: orphan recovery preserves role-owned task when same-team teammate has no pid" {
  cd "$TEST_TEMP_DIR"
  TASKS_DIR="$CLAUDE_CONFIG_DIR/tasks"
  mkdir -p "$TASKS_DIR/vbw-phase-01" "$HEALTH_DIR"

  cat > "$TASKS_DIR/vbw-phase-01/task-shared-nopid.json" <<EOF
{
  "id": "task-shared-nopid",
  "owner": "dev",
  "status": "in_progress",
  "subject": "Shared dev task without pid"
}
EOF

  cat > "$HEALTH_DIR/vbw-phase-01__dev-02.json" <<EOF
{
  "pid": "",
  "key": "vbw-phase-01__dev-02",
  "role": "dev",
  "team_name": "vbw-phase-01",
  "started_at": "2026-01-01T00:00:00Z",
  "last_event_at": "2026-01-01T00:00:00Z",
  "last_event": "idle_bootstrap",
  "idle_count": 1
}
EOF

  local dead_pid
  dead_pid=$(get_dead_pid) || fail "get_dead_pid failed"
  run bash -c "echo '{\"teammate_name\":\"dev-01\",\"team_name\":\"vbw-phase-01\",\"pid\":\"$dead_pid\"}' | bash '$SCRIPTS_DIR/agent-health.sh' idle | jq -r '.hookSpecificOutput.additionalContext'"
  [[ "$output" == *"still tracked"* ]]

  run jq -r '.owner' "$TASKS_DIR/vbw-phase-01/task-shared-nopid.json"
  [ "$output" = "dev" ]
}

@test "agent-health: cleanup removes directory" {
  cd "$TEST_TEMP_DIR"
  mkdir -p "$HEALTH_DIR"
  echo '{"pid":"1","role":"dev"}' > "$HEALTH_DIR/dev.json"
  echo '{"pid":"2","role":"qa"}' > "$HEALTH_DIR/qa.json"

  [ -d "$HEALTH_DIR" ]

  bash "$SCRIPTS_DIR/agent-health.sh" cleanup

  [ ! -d "$HEALTH_DIR" ]
}
@test "agent-health: session store keeps same-role teammates distinct" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  local first_pid second_pid
  sleep 30 & first_pid=$!
  sleep 30 & second_pid=$!

  printf '{"session_id":"session-one","agent_id":"agent-one","agent_type":"vbw-dev","pid":"%s"}' "$first_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start
  printf '{"session_id":"session-one","agent_id":"agent-two","agent_type":"vbw-dev","pid":"%s"}' "$second_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start

  [ "$(find "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-one/agents" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 2 ]
  run jq -r '.key' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-one/agents/$first_pid.json"
  [ "$output" = "agent-one" ]
  run jq -r '.key' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-one/agents/$second_pid.json"
  [ "$output" = "agent-two" ]

  kill "$first_pid" "$second_pid" 2>/dev/null || true
}

@test "agent-health: session health state does not cross sessions" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  local first_pid second_pid
  sleep 30 & first_pid=$!
  sleep 30 & second_pid=$!

  printf '{"session_id":"session-one","agent_id":"same-key","agent_type":"vbw-dev","pid":"%s"}' "$first_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  printf '{"session_id":"session-two","agent_id":"same-key","agent_type":"vbw-dev","pid":"%s"}' "$second_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  echo '{"session_id":"session-one","agent_id":"same-key","agent_type":"vbw-dev"}' |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  run jq -r '.idle_count' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-one/agents/$first_pid.json"
  [ "$output" = "1" ]
  run jq -r '.idle_count' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-two/agents/$second_pid.json"
  [ "$output" = "0" ]

  kill "$first_pid" "$second_pid" 2>/dev/null || true
}

@test "agent-health: slugged teammate names normalize to their base role" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  echo session > "$TEST_TEMP_DIR/.vbw-planning/.vbw-session"
  echo '{"session_id":"session-slug","name":"scout-active-agent-lifecycle-2","pid":"$$"}' |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  run jq -r '.role' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-slug/agents/scout-active-agent-lifecycle-2.json"
  [ "$output" = "scout" ]
}

@test "agent-health: activity resets the idle nudge streak" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  local live_pid
  sleep 30 & live_pid=$!
  printf '{"session_id":"session-reset","agent_id":"reset-agent","agent_type":"vbw-dev","pid":"%s"}' "$live_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  for _ in 1 2 3; do
    echo '{"session_id":"session-reset","agent_id":"reset-agent","agent_type":"vbw-dev"}' |
      VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done
  echo '{"session_id":"session-reset","agent_id":"reset-agent","agent_type":"vbw-dev","activity":"working"}' |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  run jq -r '.idle_count' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-reset/agents/$live_pid.json"
  [ "$output" = "1" ]
  run jq -r '.nudge_sent' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-reset/agents/$live_pid.json"
  [ "$output" = "false" ]
  kill "$live_pid" 2>/dev/null || true
}

@test "agent-health: delivered artifact terminates a live agent immediately" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  local live_pid termination_marker="$TEST_TEMP_DIR/artifact-terminated" artifact_path
  artifact_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact/01-01-SUMMARY.md"
  (
    trap 'printf terminated > "$termination_marker"; exit 0' TERM
    while true; do sleep 1; done
  ) & live_pid=$!
  printf '{"session_id":"session-artifact","agent_id":"artifact-agent","agent_type":"vbw-dev","pid":"%s","artifact_path":"%s"}' "$live_pid" "$artifact_path" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  mkdir -p "$(dirname "$artifact_path")"
  printf '# complete\n' > "$artifact_path"

  run bash -c "echo '{\"session_id\":\"session-artifact\",\"agent_id\":\"artifact-agent\",\"agent_type\":\"vbw-dev\",\"pid\":\"$live_pid\",\"artifact_path\":\"$artifact_path\"}' | VBW_PLANNING_DIR='$TEST_TEMP_DIR/.vbw-planning' VBW_AGENT_STOP_GRACE_SECONDS=1 bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [ "$status" -eq 0 ]
  ! kill -0 "$live_pid" 2>/dev/null
  [ -f "$termination_marker" ]
  [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-artifact/agents/$live_pid.json" ]
  wait "$live_pid" 2>/dev/null || true
}

@test "agent-health: artifact suffixes terminate all artifact-producing roles" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  export VBW_AGENT_STOP_GRACE_SECONDS=1
  local role suffix pid marker session payload artifact_path
  for role in lead dev scout qa; do
    case "$role" in
      lead) suffix=PLAN.md ;;
      dev) suffix=SUMMARY.md ;;
      scout) suffix=RESEARCH.md ;;
      qa) suffix=VERIFICATION.md ;;
    esac
    session="session-$role"
    marker="$TEST_TEMP_DIR/$role-terminated"
    artifact_path="$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact-roles/01-01-$suffix"
    (
      trap 'printf terminated > "$marker"; exit 0' TERM
      while true; do sleep 1; done
    ) & pid=$!
    payload="{\"session_id\":\"$session\",\"agent_id\":\"$role-agent\",\"agent_type\":\"vbw-$role\",\"pid\":\"$pid\",\"artifact_path\":\"$artifact_path\"}"
    printf '%s' "$payload" | VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
    mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact-roles"
    sleep 1
    printf '# complete\n' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact-roles/01-01-$suffix"
    printf '%s' "$payload" | VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" VBW_AGENT_STOP_GRACE_SECONDS=1 bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
    [ -f "$marker" ]
    ! kill -0 "$pid" 2>/dev/null
    [ ! -f "$TEST_TEMP_DIR/.vbw-planning/.active-agents/$session/agents/$pid.json" ]
    wait "$pid" 2>/dev/null || true
  done
}

@test "agent-health: non-positive recorded PID cannot be terminated" {
  cd "$TEST_TEMP_DIR"
  local artifact_file="$TEST_TEMP_DIR/.vbw-planning/phases/01-zero/01-01-SUMMARY.md"
  mkdir -p "$(dirname "$artifact_file")"
  printf '# complete\n' > "$artifact_file"
  local epoch
  epoch=$(date +%s)
  mkdir -p "$HEALTH_DIR"
  jq -n --arg artifact "$artifact_file" --argjson epoch "$epoch" \
    '{pid:"0",key:"zero-agent",role:"dev",started_epoch:$epoch,artifact_path:$artifact}' \
    > "$HEALTH_DIR/zero-agent.json"

  run bash -c "echo '{\"session_id\":\"session-zero\",\"agent_id\":\"zero-agent\",\"agent_type\":\"vbw-dev\"}' | VBW_PLANNING_DIR='$TEST_TEMP_DIR/.vbw-planning' HEALTH_DIR='$HEALTH_DIR' bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [ "$status" -eq 0 ]
  [ -f "$HEALTH_DIR/zero-agent.json" ]
}

@test "agent-health: PID start identity must match before termination" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  local live_pid
  sleep 999 & live_pid=$!
  printf '{"session_id":"session-identity","agent_id":"identity-agent","agent_type":"vbw-dev","pid":"%s"}' "$live_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  local health_file="$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-identity/agents/$live_pid.json"
  jq '.pid_identity = "not-the-live-process"' "$health_file" > "$health_file.tmp"
  mv "$health_file.tmp" "$health_file"

  for _ in 1 2 3 4; do
    echo '{"session_id":"session-identity","agent_id":"identity-agent","agent_type":"vbw-dev"}' |
      VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" VBW_AGENT_STOP_GRACE_SECONDS=0 bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done

  kill -0 "$live_pid" 2>/dev/null
  kill "$live_pid" 2>/dev/null || true
}

@test "agent-health: pre-existing artifact does not terminate a live agent" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  export VBW_AGENT_STOP_GRACE_SECONDS=0
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact"
  printf '# old\n' > "$TEST_TEMP_DIR/.vbw-planning/phases/01-artifact/01-01-SUMMARY.md"
  sleep 1
  local live_pid termination_marker="$TEST_TEMP_DIR/old-artifact-terminated"
  (
    trap 'printf terminated > "$termination_marker"; exit 0' TERM
    while true; do sleep 1; done
  ) & live_pid=$!
  printf '{"session_id":"session-old-artifact","agent_id":"old-artifact-agent","agent_type":"vbw-dev","pid":"%s"}' "$live_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null
  echo '{"session_id":"session-old-artifact","agent_id":"old-artifact-agent","agent_type":"vbw-dev"}' |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" VBW_AGENT_STOP_GRACE_SECONDS=0 bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null

  kill -0 "$live_pid" 2>/dev/null
  [ ! -f "$termination_marker" ]
  kill -TERM "$live_pid" 2>/dev/null || true
  sleep 0.1
  wait "$live_pid" 2>/dev/null || true
}

@test "agent-health: idle sends one nudge before terminating on the next strike" {
  cd "$TEST_TEMP_DIR"
  unset HEALTH_DIR
  export VBW_AGENT_STOP_GRACE_SECONDS=0
  local live_pid termination_marker="$TEST_TEMP_DIR/idle-terminated"
  (
    trap 'printf terminated > "$termination_marker"; exit 0' TERM
    while true; do sleep 1; done
  ) & live_pid=$!
  printf '{"session_id":"session-idle","agent_id":"idle-agent","agent_type":"vbw-dev","pid":"%s"}' "$live_pid" |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" start >/dev/null

  for _ in 1 2; do
    echo '{"session_id":"session-idle","agent_id":"idle-agent","agent_type":"vbw-dev"}' |
      VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  done
  run bash -c "echo '{\"session_id\":\"session-idle\",\"agent_id\":\"idle-agent\",\"agent_type\":\"vbw-dev\"}' | VBW_PLANNING_DIR='$TEST_TEMP_DIR/.vbw-planning' bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [[ "$output" == *"nudge"* ]]
  kill -0 "$live_pid" 2>/dev/null

  run bash -c "echo '{\"session_id\":\"session-idle\",\"agent_id\":\"idle-agent\",\"agent_type\":\"vbw-dev\"}' | VBW_PLANNING_DIR='$TEST_TEMP_DIR/.vbw-planning' VBW_AGENT_STOP_GRACE_SECONDS=1 bash '$SCRIPTS_DIR/agent-health.sh' idle"
  [[ "$output" == *"respawn"* ]]
  ! kill -0 "$live_pid" 2>/dev/null
  [ -f "$termination_marker" ]
  echo '{"session_id":"session-idle","agent_id":"idle-agent","agent_type":"vbw-dev"}' |
    VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$SCRIPTS_DIR/agent-health.sh" idle >/dev/null
  run jq -r '.respawn_cycle_done' "$TEST_TEMP_DIR/.vbw-planning/.active-agents/session-idle/agents/$live_pid.json"
  [ "$output" = "true" ]
  wait "$live_pid" 2>/dev/null || true
}
