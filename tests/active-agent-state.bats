#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export CLAUDE_SESSION_ID=""
}

teardown() {
  unset CLAUDE_SESSION_ID
  teardown_temp_dir
}

@test "role normalization accepts QA Author roles and numeric suffixes only" {
  run bash -c 'source "$1"; vbw_active_agent_normalize_role "$2"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "vbw-qa-author"
  [ "$status" -eq 0 ]
  [ "$output" = "qa-author" ]

  run bash -c 'source "$1"; vbw_active_agent_normalize_role "$2"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "vbw-qa-author-2"
  [ "$status" -eq 0 ]
  [ "$output" = "qa-author" ]

  run bash -c 'source "$1"; vbw_active_agent_normalize_role "$2"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "vbw-qa-author-2x"
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "current role rejects stale marker when session role count is zero" {
  local session_id="session-stale"
  mkdir -p "$PLANNING_DIR/.active-agents/$session_id"
  printf '0\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent-count"
  printf 'scout 0\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent-roles"
  printf 'scout\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{\"session_id\":\"session-stale\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"

  [ "$status" -eq 1 ]
}

@test "current role rejects marker when session count is zero without role file" {
  local session_id="session-count-zero"
  mkdir -p "$PLANNING_DIR/.active-agents/$session_id"
  printf '0\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent-count"
  printf 'scout\n' > "$PLANNING_DIR/.active-agents/$session_id/active-agent"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{\"session_id\":\"session-count-zero\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"

  [ "$status" -eq 1 ]
}

@test "current role fails closed when session id is unresolvable" {
  printf 'scout\n' > "$PLANNING_DIR/.active-agent"
  local stderr_file="$TEST_TEMP_DIR/stderr"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{}" 2>"$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$stderr_file"

  [ "$status" -eq 1 ]
  [ "$(cat "$stderr_file")" = "session_id unresolvable, role detection skipped (fail-closed)" ]
}

@test "start stores one registration file per live pid" {
  local session_id="session-files"
  local first_pid second_pid third_pid
  sleep 30 & first_pid=$!
  sleep 30 & second_pid=$!
  sleep 30 & third_pid=$!

  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-files\",\"agent_id\":\"agent-1\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$first_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-files\",\"agent_id\":\"agent-2\"}" scout "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$second_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-files\",\"agent_id\":\"agent-3\"}" qa "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$third_pid"

  [ "$(find "$PLANNING_DIR/.active-agents/$session_id/agents" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 3 ]
  run jq -r '.role + ":" + .key' "$PLANNING_DIR/.active-agents/$session_id/agents/$first_pid.json"
  [ "$output" = "dev:agent-1" ]

  kill "$first_pid" "$second_pid" "$third_pid" 2>/dev/null || true
}

@test "stop removes only the matching pid registration" {
  local session_id="session-stop"
  local first_pid second_pid
  sleep 30 & first_pid=$!
  sleep 30 & second_pid=$!
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-stop\",\"agent_id\":\"agent-1\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$first_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-stop\",\"agent_id\":\"agent-2\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$second_pid"

  bash -c 'source "$1"; vbw_active_agent_stop "$2" "{\"session_id\":\"session-stop\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$first_pid"

  [ ! -f "$PLANNING_DIR/.active-agents/$session_id/agents/$first_pid.json" ]
  [ -f "$PLANNING_DIR/.active-agents/$session_id/agents/$second_pid.json" ]
  kill "$first_pid" "$second_pid" 2>/dev/null || true
}

@test "current role resolves from a live per-pid registration" {
  local live_pid dev_pid qa_pid
  sleep 30 & live_pid=$!
  sleep 30 & dev_pid=$!
  sleep 30 & qa_pid=$!
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-live-role\",\"agent_id\":\"agent-live\"}" scout "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$live_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-live-role\",\"agent_id\":\"agent-dev\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$dev_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-live-role\",\"agent_id\":\"agent-qa\"}" qa "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$qa_pid"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{\"session_id\":\"session-live-role\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  run bash -c 'source "$1"; vbw_active_agent_current_qa "$2" "{\"session_id\":\"session-live-role\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"
  [ "$status" -eq 0 ]
  kill "$live_pid" "$dev_pid" "$qa_pid" 2>/dev/null || true
}

@test "current role does not resolve another live role as scout" {
  local dev_pid qa_pid
  sleep 30 & dev_pid=$!
  sleep 30 & qa_pid=$!
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-live-negative\",\"agent_id\":\"agent-dev\"}" dev "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$dev_pid"
  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-live-negative\",\"agent_id\":\"agent-qa\"}" qa "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$qa_pid"

  run bash -c 'source "$1"; vbw_active_agent_current_scout "$2" "{\"session_id\":\"session-live-negative\"}"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR"
  [ "$status" -eq 1 ]
  kill "$dev_pid" "$qa_pid" 2>/dev/null || true
}

@test "start migrates legacy files into a session source once" {
  local session_id="session-migration"
  local live_pid
  sleep 30 & live_pid=$!
  printf '1\n' > "$PLANNING_DIR/.active-agent-count"
  printf 'dev 1\n' > "$PLANNING_DIR/.active-agent-roles"
  printf '%s dev\n' "$live_pid" > "$PLANNING_DIR/.active-agent-role-pids"

  bash -c 'source "$1"; vbw_active_agent_start "$2" "{\"session_id\":\"session-migration\",\"agent_id\":\"new-agent\"}" scout "$3"' _ \
    "$SCRIPTS_DIR/lib/active-agent-state.sh" "$PLANNING_DIR" "$live_pid"

  [ -f "$PLANNING_DIR/.active-agents/__vbw_legacy_global/agents/$live_pid.json" ]
  [ -f "$PLANNING_DIR/.active-agents/$session_id/agents/$live_pid.json" ]
  kill "$live_pid" 2>/dev/null || true
}
