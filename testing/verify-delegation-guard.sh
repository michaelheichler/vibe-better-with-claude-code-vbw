#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE_GUARD="$ROOT/scripts/file-guard.sh"
DELEG_SCRIPT="$ROOT/scripts/delegated-workflow.sh"
HOOK_WRAPPER="$ROOT/scripts/hook-wrapper.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

setup_project() {
  TMPDIR_BASE=$(mktemp -d)
  PROJECT="$TMPDIR_BASE/project"
  mkdir -p "$PROJECT/.vbw-planning/phases/01-test"
  echo '{"effort":"balanced","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
  cat > "$PROJECT/.vbw-planning/phases/01-test/01-01-PLAN.md" <<'EOF'
---
title: Test Plan
files_modified:
  - src/app.js
  - src/utils.js
---
EOF
}

cleanup() {
  [ -n "$TMPDIR_BASE" ] && rm -rf "$TMPDIR_BASE" 2>/dev/null || true
}
trap cleanup EXIT

run_guard() {
  local project_dir="$1"
  local file_path="$2"
  local agent_role="${3:-}"

  local input
  input=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}')

  if [ -n "$agent_role" ]; then
    (cd "$project_dir" && unset CLAUDE_CODE_CHILD_SESSION CLAUDE_SESSION_ID; VBW_AGENT_ROLE="$agent_role" bash "$FILE_GUARD" <<< "$input") 2>&1
  else
    (cd "$project_dir" && unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE CLAUDE_SESSION_ID; bash "$FILE_GUARD" <<< "$input") 2>&1
  fi
  return ${PIPESTATUS[0]}
}

run_guard_with_session() {
  local project_dir="$1"
  local file_path="$2"
  local session_id="$3"
  local agent_role="${4:-}"

  local input
  input=$(jq -n --arg sid "$session_id" --arg fp "$file_path" '{session_id:$sid,tool_input:{file_path:$fp}}')

  if [ -n "$agent_role" ]; then
    (cd "$project_dir" && unset CLAUDE_CODE_CHILD_SESSION CLAUDE_SESSION_ID; VBW_AGENT_ROLE="$agent_role" bash "$FILE_GUARD" <<< "$input") 2>&1
  else
    (cd "$project_dir" && unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE CLAUDE_SESSION_ID; bash "$FILE_GUARD" <<< "$input") 2>&1
  fi
  return ${PIPESTATUS[0]}
}

run_guard_from() {
  local working_dir="$1"
  local file_path="$2"
  local agent_role="${3:-}"

  local input
  input=$(jq -n --arg fp "$file_path" '{"tool_input":{"file_path":$fp}}')

  if [ -n "$agent_role" ]; then
    (cd "$working_dir" && unset CLAUDE_CODE_CHILD_SESSION VBW_CONFIG_ROOT VBW_PLANNING_DIR CLAUDE_SESSION_ID; VBW_AGENT_ROLE="$agent_role" bash "$FILE_GUARD" <<< "$input") 2>&1
  else
    (cd "$working_dir" && unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE VBW_CONFIG_ROOT VBW_PLANNING_DIR CLAUDE_SESSION_ID; bash "$FILE_GUARD" <<< "$input") 2>&1
  fi
  return ${PIPESTATUS[0]}
}

start_active_agent_session() {
  local project_dir="$1"
  local session_id="$2"
  local role="$3"
  local pid="$4"
  local input

  input=$(jq -n --arg sid "$session_id" --arg agent_type "vbw-$role" --arg pid "$pid" '{session_id:$sid,agent_type:$agent_type,pid:$pid}')
  VBW_PLANNING_DIR="$project_dir/.vbw-planning" bash "$ROOT/scripts/agent-start.sh" <<< "$input" >/dev/null 2>&1 || true
}

setup_sidechain_project() {
  setup_project
  SIDECHAIN="$PROJECT/.claude/worktrees/agent-test"
  mkdir -p "$SIDECHAIN/.vbw-planning/phases/01-copy" "$SIDECHAIN/src"
  echo '{"effort":"turbo","prefer_teams":"always"}' > "$SIDECHAIN/.vbw-planning/config.json"
}

write_live_execute_state() {
  jq -n '{phase:1,status:"running",effort:"balanced",correlation_id:"corr-sidechain",plans:[{id:"01-01",status:"pending"}]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  (cd "$PROJECT" && bash "$DELEG_SCRIPT" set execute balanced subagent)
}

run_sidechain_agent_hook() {
  local hook_script="$1"
  local input
  input=$(jq -n '{agent_type:"vbw:vbw-dev", pid:"12345"}')

  (
    cd "$SIDECHAIN"
    unset VBW_CONFIG_ROOT VBW_PLANNING_DIR
    CLAUDE_CONFIG_DIR="$TMPDIR_BASE/claude" \
      CLAUDE_PLUGIN_ROOT="$ROOT" \
      bash "$HOOK_WRAPPER" "$hook_script" <<< "$input"
  )
}

assert_sidechain_target_message() {
  local output="$1"
  local host_root="$2"
  local label="$3"

  if ! grep -qi 'blocked target:' <<< "$output"; then
    fail "$label: missing blocked target label ($output)"
    return 1
  fi
  if ! grep -q "$host_root" <<< "$output" && ! grep -qi 'host repo' <<< "$output"; then
    fail "$label: missing host repo path/phrase ($output)"
    return 1
  fi
  if ! grep -qi 'retry.*absolute path.*host repo' <<< "$output"; then
    fail "$label: missing retry action for absolute host path ($output)"
    return 1
  fi
  if ! grep -qi 'sidechain' <<< "$output" || ! grep -qiE 'not.*(merge|use)|will not.*(merge|use)' <<< "$output"; then
    fail "$label: missing sidechain not-merged/used reason ($output)"
    return 1
  fi
  if grep -qE 'CRITICAL|MUST' <<< "$output"; then
    fail "$label: message uses aggressive CRITICAL/MUST wording ($output)"
    return 1
  fi
  return 0
}

echo "=== Delegation Guard Tests ==="

test_non_vbw_repo() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/src"

  local input
  input=$(jq -n '{"tool_input":{"file_path":"src/app.js"}}')
  if (cd "$tmpdir" && bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "Non-VBW repo: no block"
  else
    fail "Non-VBW repo: unexpected block (exit $?)"
  fi
  rm -rf "$tmpdir"
}
test_non_vbw_repo

test_no_active_state() {
  setup_project

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "No active delegated state: no block"
  else
    fail "No active delegated state: unexpected block (exit $?)"
  fi
  cleanup
}
test_no_active_state

test_execute_running_blocks() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    if grep -q "orchestrator cannot write product files" <<<"$output"; then
      pass "Execute running, non-turbo, orchestrator product write: blocked (exit 2)"
    else
      fail "Execute running: blocked but wrong message: $output"
    fi
  else
    fail "Execute running, non-turbo, orchestrator product write: expected exit 2, got $rc"
  fi
  cleanup
}
test_execute_running_blocks

test_delegated_marker_blocks() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"balanced", started_at:"2026-03-03T00:00:00Z"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    if grep -q "orchestrator cannot write product files" <<<"$output"; then
      pass "Delegated marker active, non-turbo, orchestrator product write: blocked (exit 2)"
    else
      fail "Delegated marker: blocked but wrong message: $output"
    fi
  else
    fail "Delegated marker active: expected exit 2, got $rc"
  fi
  cleanup
}
test_delegated_marker_blocks

test_planning_artifacts_allowed() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local rc=0
  run_guard "$PROJECT" "$PROJECT/.vbw-planning/STATE.md" "" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "Active delegated state, planning artifact write: allowed"
  else
    fail "Active delegated state, planning artifact write: unexpected block (exit $rc)"
  fi
  cleanup
}
test_planning_artifacts_allowed

test_turbo_allowed() {
  setup_project
  echo '{"effort":"turbo","prefer_teams":"never"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"turbo", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Active delegated state, turbo effort: allowed"
  else
    fail "Active delegated state, turbo effort: unexpected block (exit $?)"
  fi
  cleanup
}
test_turbo_allowed

test_subagent_allowed() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "dev" >/dev/null 2>&1; then
    pass "Active delegated state, VBW_AGENT_ROLE=dev: allowed"
  else
    fail "Active delegated state, VBW_AGENT_ROLE=dev: unexpected block (exit $?)"
  fi
  cleanup
}
test_subagent_allowed

test_malformed_state_failopen() {
  setup_project
  echo "not json" > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Malformed state file: fail-open"
  else
    fail "Malformed state file: unexpected block (exit $?)"
  fi
  cleanup
}
test_malformed_state_failopen

test_stale_state_failopen() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2024-01-01T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  touch -t "202501010000" "$PROJECT/.vbw-planning/.execution-state.json" 2>/dev/null || true

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Stale state file (>4h): fail-open"
  else
    fail "Stale state file: unexpected block (exit $?)"
  fi
  cleanup
}
test_stale_state_failopen

test_direct_effort_allowed() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"direct", started_at:"2026-03-03T00:00:00Z"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Delegated marker, direct effort: allowed"
  else
    fail "Delegated marker, direct effort: unexpected block (exit $?)"
  fi
  cleanup
}
test_direct_effort_allowed

test_execute_direct_marker_allowed() {
  setup_project
  jq -n '{phase:1,status:"running",effort:"direct",correlation_id:"corr-direct",plans:[{id:"01-01",status:"pending"}]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  (cd "$PROJECT" && bash "$DELEG_SCRIPT" set execute direct direct)

  local status_json
  status_json=$(cd "$PROJECT" && bash "$DELEG_SCRIPT" status-json)
  if jq -e '.live == true and .delegation_mode == "direct" and .mode == "execute"' >/dev/null <<< "$status_json"; then
    pass "execute direct marker: status-json reports live direct mode"
  else
    fail "execute direct marker: expected live direct mode, got $status_json"
  fi

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "execute direct marker: file-guard allows direct effort product write"
  else
    fail "execute direct marker: file-guard unexpectedly blocked direct effort product write"
  fi
  cleanup
}
test_execute_direct_marker_allowed

test_complete_status_no_block() {
  setup_project
  jq -n '{status:"complete", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "Execution complete status: no block"
  else
    fail "Execution complete status: unexpected block (exit $?)"
  fi
  cleanup
}
test_complete_status_no_block

new_delegated_test_dir() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.vbw-planning"
  echo '{"effort":"balanced"}' > "$tmpdir/.vbw-planning/config.json"
  printf '%s\n' "$tmpdir"
}

set_live_execute_marker() {
  local tmpdir="$1"
  jq -n '{phase:1,status:"running",effort:"balanced",correlation_id:"corr-123",plans:[]}' \
    > "$tmpdir/.vbw-planning/.execution-state.json"
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set execute balanced team vbw-phase-01)
}

assert_delegated_status() {
  local tmpdir="$1" filter="$2" success="$3" failure="$4" status
  status=$(cd "$tmpdir" && bash "$DELEG_SCRIPT" status-json)
  if echo "$status" | jq -e "$filter" >/dev/null 2>&1; then
    pass "$success"
  else
    fail "$failure ($status)"
  fi
}

test_execute_marker_metadata() {
  local tmpdir marker metadata
  tmpdir=$(new_delegated_test_dir)
  set_live_execute_marker "$tmpdir"
  marker="$tmpdir/.vbw-planning/.delegated-workflow.json"
  metadata=$(jq -r '[.mode, .delegation_mode, .team_name, .correlation_id] | join("|")' "$marker" 2>/dev/null)
  if [ "$metadata" = "execute|team|vbw-phase-01|corr-123" ]; then
    pass "delegated-workflow.sh set execute records runtime metadata"
  else
    fail "delegated-workflow.sh set execute wrote unexpected metadata ($metadata)"
  fi
  rm -rf "$tmpdir"
}
test_execute_marker_metadata

test_live_execute_status() {
  local tmpdir
  tmpdir=$(new_delegated_test_dir)
  set_live_execute_marker "$tmpdir"
  assert_delegated_status "$tmpdir" '.live and .preserve_on_session_start and .reason == "ok"' \
    "delegated-workflow.sh validates live execute marker" "delegated-workflow.sh rejected live execute marker"
  rm -rf "$tmpdir"
}
test_live_execute_status

test_stale_execute_status() {
  local tmpdir
  tmpdir=$(new_delegated_test_dir)
  set_live_execute_marker "$tmpdir"
  touch -t 202001010000 "$tmpdir/.vbw-planning/.execution-state.json"
  assert_delegated_status "$tmpdir" '.live == false and .reason == "stale_execution_state"' \
    "delegated-workflow.sh rejects stale execution state" "delegated-workflow.sh accepted stale execution state"
  rm -rf "$tmpdir"
}
test_stale_execute_status

test_fix_marker_status() {
  local tmpdir
  tmpdir=$(new_delegated_test_dir)
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set fix balanced)
  assert_delegated_status "$tmpdir" '.live and (.preserve_on_session_start == false) and .mode == "fix"' \
    "delegated-workflow.sh keeps fix marker session-local" "delegated-workflow.sh returned unexpected fix status"
  rm -rf "$tmpdir"
}
test_fix_marker_status

test_delegated_set_and_check() {
  local tmpdir marker mode
  tmpdir=$(new_delegated_test_dir)
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set fix balanced)
  marker="$tmpdir/.vbw-planning/.delegated-workflow.json"
  mode=$(jq -r '.mode' "$marker" 2>/dev/null)
  [ "$mode" = "fix" ] && pass "delegated-workflow.sh set creates marker" || fail "delegated-workflow.sh set wrote mode $mode"
  if (cd "$tmpdir" && bash "$DELEG_SCRIPT" check) >/dev/null 2>&1; then
    pass "delegated-workflow.sh check returns active"
  else
    fail "delegated-workflow.sh check missed active marker"
  fi
  rm -rf "$tmpdir"
}
test_delegated_set_and_check

test_delegated_clear_and_check() {
  local tmpdir marker check_status
  tmpdir=$(new_delegated_test_dir)
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" set fix balanced && bash "$DELEG_SCRIPT" clear)
  marker="$tmpdir/.vbw-planning/.delegated-workflow.json"
  [ ! -f "$marker" ] && pass "delegated-workflow.sh clear removes marker" || fail "delegated-workflow.sh clear retained marker"
  check_status=0
  (cd "$tmpdir" && bash "$DELEG_SCRIPT" check) >/dev/null 2>&1 || check_status=$?
  [ "$check_status" -ne 0 ] && pass "delegated-workflow.sh check returns inactive" || fail "delegated-workflow.sh check accepted missing marker"
  rm -rf "$tmpdir"
}
test_delegated_clear_and_check

test_gsd_unaffected() {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/.planning/phases/01-test"

  local input
  input=$(jq -n '{"tool_input":{"file_path":"src/app.js"}}')
  if (cd "$tmpdir" && bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "GSD-only repo (.planning/ without .vbw-planning/): no block"
  else
    fail "GSD-only repo: unexpected block (exit $?)"
  fi
  rm -rf "$tmpdir"
}
test_gsd_unaffected

test_active_agent_count_does_not_classify_orchestrator() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  local output rc
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q "orchestrator cannot write product files" <<< "$output"; then
    pass "Active agent count does not classify payload-less orchestrator"
  else
    fail "Active agent count bypassed orchestrator guard (rc=$rc output=$output)"
  fi
  cleanup
}
test_active_agent_count_does_not_classify_orchestrator

test_scout_marker_does_not_classify_orchestrator() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "scout" > "$PROJECT/.vbw-planning/.active-agent"

  if run_guard "$PROJECT" "CLAUDE.md" "" >/dev/null 2>&1; then
    pass "Scout marker does not restrict payload-less orchestrator"
  else
    fail "Scout marker restricted payload-less orchestrator (exit $?)"
  fi

  local output rc
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q "orchestrator cannot write product files" <<< "$output"; then
    pass "Delegated workflow still blocks payload-less orchestrator"
  else
    fail "Payload-less orchestrator escaped delegated workflow guard (rc=$rc output=$output)"
  fi
  cleanup
}
test_scout_marker_does_not_classify_orchestrator

test_mixed_role_markers_do_not_classify_orchestrator() {
  setup_project
  echo "2" > "$PROJECT/.vbw-planning/.active-agent-count"
  cat > "$PROJECT/.vbw-planning/.active-agent-roles" <<'EOF'
scout 1
dev 1
EOF

  if run_guard "$PROJECT" "CLAUDE.md" "" >/dev/null 2>&1; then
    pass "Mixed role markers do not classify payload-less orchestrator"
  else
    fail "Mixed role markers restricted payload-less orchestrator (exit $?)"
  fi
  cleanup
}
test_mixed_role_markers_do_not_classify_orchestrator

test_session_local_count_never_classifies_orchestrator() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  start_active_agent_session "$PROJECT" "session-A" "dev" "31401"

  local output rc sid
  for sid in session-A session-B; do
    output=$(run_guard_with_session "$PROJECT" "src/app.js" "$sid" "" 2>&1) && rc=$? || rc=$?
    if [ "$rc" -ne 2 ] || ! grep -q "orchestrator cannot write product files" <<< "$output"; then
      fail "Session-local count bypassed orchestrator guard for $sid (rc=$rc output=$output)"
      cleanup
      return
    fi
  done
  pass "Session-local count never classifies payload-less orchestrator"
  cleanup
}
test_session_local_count_never_classifies_orchestrator

test_session_local_scout_never_classifies_orchestrator() {
  setup_project
  start_active_agent_session "$PROJECT" "session-A" "scout" "31402"

  local sid
  for sid in session-A session-B; do
    if ! run_guard_with_session "$PROJECT" "CLAUDE.md" "$sid" "" >/dev/null 2>&1; then
      fail "Session-local Scout restricted payload-less orchestrator for $sid"
      cleanup
      return
    fi
  done
  pass "Session-local Scout never classifies payload-less orchestrator"
  cleanup
}
test_session_local_scout_never_classifies_orchestrator

test_child_session_bypasses_orchestrator_without_inheriting_scout() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "scout" > "$PROJECT/.vbw-planning/.active-agent"
  local input
  input=$(jq -n '{tool_input:{file_path:"src/app.js"}}')

  if (cd "$PROJECT" && unset VBW_AGENT_ROLE VBW_ACTIVE_AGENT CLAUDE_SESSION_ID; CLAUDE_CODE_CHILD_SESSION=1 bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "Child session bypasses orchestrator guard without inheriting Scout"
  else
    fail "Child session was blocked by orchestrator or Scout guard"
  fi
  cleanup
}
test_child_session_bypasses_orchestrator_without_inheriting_scout

test_zero_agent_count_still_blocks() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  echo "0" > "$PROJECT/.vbw-planning/.active-agent-count"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "Active agent count = 0, no VBW_AGENT_ROLE: blocked (orchestrator)"
  else
    fail "Active agent count = 0: expected exit 2, got $rc"
  fi
  cleanup
}
test_zero_agent_count_still_blocks

test_no_count_file_still_blocks() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "No agent count file, no VBW_AGENT_ROLE: blocked (orchestrator)"
  else
    fail "No agent count file: expected exit 2, got $rc"
  fi
  cleanup
}
test_no_count_file_still_blocks

test_execute_team_marker_bypasses_guard() {
  local tmp
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  tmp=$(mktemp)
  jq '.correlation_id = "corr-123"' "$PROJECT/.vbw-planning/.execution-state.json" > "$tmp" && mv "$tmp" "$PROJECT/.vbw-planning/.execution-state.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "execute team marker, active execution, no agent count: allowed"
  else
    fail "execute team marker: unexpected block (exit $?)"
  fi
  cleanup
}
test_execute_team_marker_bypasses_guard

test_aged_live_execute_team_marker_bypasses_guard() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"corr-123", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  touch -t 202001010000 "$PROJECT/.vbw-planning/.delegated-workflow.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "aged live execute team marker: allowed"
  else
    fail "aged live execute team marker: unexpected block (exit $?)"
  fi
  cleanup
}
test_aged_live_execute_team_marker_bypasses_guard

test_execute_team_marker_mismatch_does_not_bypass() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"live-corr", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"stale-corr"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"
  touch -t 202001010000 "$PROJECT/.vbw-planning/.delegated-workflow.json"

  rm -f "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "mismatched execute team marker: blocked (no stale teams bypass)"
  else
    fail "mismatched execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_execute_team_marker_mismatch_does_not_bypass

test_prefer_teams_always_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"always"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "prefer_teams=always without execute team marker: blocked"
  else
    fail "prefer_teams=always without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_always_alone_does_not_bypass

test_prefer_teams_auto_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"auto"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "prefer_teams=auto without execute team marker: blocked"
  else
    fail "prefer_teams=auto without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_auto_alone_does_not_bypass

test_prefer_teams_legacy_when_parallel_alone_does_not_bypass() {
  setup_project
  echo '{"effort":"balanced","prefer_teams":"when_parallel"}' > "$PROJECT/.vbw-planning/config.json"
  jq -n '{status:"running", phase:1, effort:"balanced", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"

  local output
  output=$(run_guard "$PROJECT" "src/app.js" "" 2>&1) && local rc=$? || local rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "legacy prefer_teams=when_parallel without execute team marker: blocked"
  else
    fail "legacy prefer_teams=when_parallel without execute team marker: expected exit 2, got $rc"
  fi
  cleanup
}
test_prefer_teams_legacy_when_parallel_alone_does_not_bypass

test_session_start_clears_fresh_fix_marker() {
  setup_project
  jq -n '{mode:"fix", active:true, effort:"balanced", delegation_mode:"", team_name:"", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:""}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  (cd "$PROJECT" && bash "$ROOT/scripts/session-start.sh") >/dev/null 2>&1

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "session-start clears fresh fix marker before next-session file-guard evaluation"
  else
    fail "session-start should clear fresh fix marker before next-session guard evaluation"
  fi
  cleanup
}
test_session_start_clears_fresh_fix_marker

test_session_stop_preserves_live_execute_team_marker() {
  setup_project
  jq -n '{status:"running", phase:1, effort:"balanced", correlation_id:"corr-123", started_at:"2026-03-03T00:00:00Z", plans:[]}' \
    > "$PROJECT/.vbw-planning/.execution-state.json"
  jq -n '{mode:"execute", active:true, effort:"balanced", delegation_mode:"team", team_name:"vbw-phase-01", started_at:"2026-03-03T00:00:00Z", session_id:"session-test", correlation_id:"corr-123"}' \
    > "$PROJECT/.vbw-planning/.delegated-workflow.json"

  echo '{"cost_usd":0.01,"duration_ms":5000,"tokens_in":100,"tokens_out":50,"model":"test"}' \
    | (cd "$PROJECT" && bash "$ROOT/scripts/session-stop.sh") >/dev/null 2>&1

  [ -f "$PROJECT/.vbw-planning/.delegated-workflow.json" ] || {
    fail "session-stop should preserve live execute team marker"
    cleanup
    return
  }

  if run_guard "$PROJECT" "src/app.js" "" >/dev/null 2>&1; then
    pass "session-stop preserves live execute team marker for file-guard bypass"
  else
    fail "session-stop preserved marker path did not keep file-guard bypass"
  fi
  cleanup
}
test_session_stop_preserves_live_execute_team_marker

test_claude_sidechain_agent_hooks_use_host_planning_dir() {
  setup_sidechain_project
  write_live_execute_state

  run_sidechain_agent_hook agent-start.sh >/dev/null 2>&1 || true

  local host_count sidechain_count
  host_count=$(cat "$PROJECT/.vbw-planning/.active-agent-count" 2>/dev/null || true)
  sidechain_count=$(cat "$SIDECHAIN/.vbw-planning/.active-agent-count" 2>/dev/null || true)
  if [ "$host_count" = "1" ] && [ -z "$sidechain_count" ]; then
    pass "Claude sidechain agent-start writes active count to host planning dir"
  else
    fail "Claude sidechain agent-start should write host count=1 and no sidechain count (host=$host_count sidechain=$sidechain_count)"
  fi

  run_sidechain_agent_hook agent-stop.sh >/dev/null 2>&1 || true
  if [ ! -f "$PROJECT/.vbw-planning/.active-agent-count" ] && [ ! -f "$PROJECT/.vbw-planning/.active-agent" ] && [ ! -f "$PROJECT/.vbw-planning/.active-agent-roles" ]; then
    pass "Claude sidechain agent-stop cleans host active-agent markers"
  else
    fail "Claude sidechain agent-stop should remove host active-agent markers"
  fi
  cleanup
}
test_claude_sidechain_agent_hooks_use_host_planning_dir

test_claude_sidechain_host_absolute_write_allowed_after_agent_start() {
  local input
  setup_sidechain_project
  write_live_execute_state
  run_sidechain_agent_hook agent-start.sh >/dev/null 2>&1 || true
  input=$(jq -n --arg fp "$PROJECT/src/app.js" \
    '{agent_id:"agent-sidechain",agent_type:"vbw:vbw-dev",tool_input:{file_path:$fp}}')

  if (cd "$SIDECHAIN" && unset CLAUDE_CODE_CHILD_SESSION VBW_AGENT_ROLE VBW_CONFIG_ROOT VBW_PLANNING_DIR CLAUDE_SESSION_ID; bash "$FILE_GUARD" <<< "$input") >/dev/null 2>&1; then
    pass "Claude sidechain active subagent: host-root declared product write allowed"
  else
    fail "Claude sidechain active subagent: host-root declared product write unexpectedly blocked"
  fi

  run_sidechain_agent_hook agent-stop.sh >/dev/null 2>&1 || true
  cleanup
}
test_claude_sidechain_host_absolute_write_allowed_after_agent_start

test_claude_sidechain_host_absolute_write_blocks_without_agent_marker() {
  setup_sidechain_project
  write_live_execute_state

  rm -f "$PROJECT/.vbw-planning/.active-agent" "$PROJECT/.vbw-planning/.active-agent-count"
  local output rc
  output=$(run_guard_from "$SIDECHAIN" "$PROJECT/src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'orchestrator cannot write product files' <<< "$output"; then
    pass "Claude sidechain orchestrator host-root product write: blocked"
  else
    fail "Claude sidechain orchestrator host-root product write should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_host_absolute_write_blocks_without_agent_marker

test_claude_sidechain_relative_write_target_blocks() {
  setup_sidechain_project
  write_live_execute_state
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  local output rc
  output=$(run_guard_from "$SIDECHAIN" "src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ]; then
    if assert_sidechain_target_message "$output" "$PROJECT" "Claude sidechain relative target"; then
      pass "Claude sidechain relative Write/Edit target: blocked with retry guidance"
    fi
  else
    fail "Claude sidechain relative Write/Edit target should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_relative_write_target_blocks

test_claude_sidechain_absolute_sidechain_target_blocks() {
  setup_sidechain_project
  write_live_execute_state
  echo "1" > "$PROJECT/.vbw-planning/.active-agent-count"
  echo "dev" > "$PROJECT/.vbw-planning/.active-agent"

  local output rc
  output=$(run_guard_from "$SIDECHAIN" "$SIDECHAIN/src/app.js" "" 2>&1) && rc=$? || rc=$?
  if [ "$rc" -eq 2 ]; then
    if assert_sidechain_target_message "$output" "$PROJECT" "Claude sidechain absolute target"; then
      pass "Claude sidechain absolute sidechain target: blocked with retry guidance"
    fi
  else
    fail "Claude sidechain absolute target should block (rc=$rc, output=$output)"
  fi
  cleanup
}
test_claude_sidechain_absolute_sidechain_target_blocks

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All delegation guard checks passed."
exit 0
