#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLEAN_SCRIPT="$ROOT/scripts/clean-stale-teams.sh"
DOCTOR_SCRIPT="$ROOT/scripts/doctor-cleanup.sh"

PASS=0
FAIL=0
TEST_PARENT=$(mktemp -d)
TMPDIR_BASE=""

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

cleanup() {
  rm -rf "$TEST_PARENT" 2>/dev/null || true
}
trap cleanup EXIT

test_configless_vbw_team_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-03/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-phase-03/inboxes/team-lead.json"
  touch "$claude_dir/teams/vbw-phase-03/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-03" ]; then
    fail "configless VBW team dir should be removed (vbw-phase-03 still exists)"
  else
    pass "configless VBW team dir removed immediately"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_non_vbw_configless_preserved() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/my-custom-team/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/my-custom-team/inboxes/agent.json"
  touch "$claude_dir/teams/my-custom-team/inboxes/agent.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/my-custom-team" ]; then
    pass "non-VBW configless team dir preserved"
  else
    fail "non-VBW configless team dir was incorrectly removed"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_vbw_team_with_config_preserved() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-01/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-01"}' > "$claude_dir/teams/vbw-phase-01/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-01/inboxes/team-lead.json"
  touch "$claude_dir/teams/vbw-phase-01/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-01" ]; then
    pass "VBW team with config.json preserved"
  else
    fail "VBW team with config.json was incorrectly removed"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_paired_tasks_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-plan-02/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-plan-02"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-plan-02/inboxes/team-lead.json"
  touch "$claude_dir/teams/vbw-plan-02/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/tasks/vbw-plan-02" ]; then
    fail "paired tasks dir should be removed with configless team"
  else
    pass "paired tasks dir removed with configless team"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_multiple_configless_cleaned() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  for team in vbw-phase-03 vbw-phase-04 vbw-plan-02 vbw-plan-03; do
    mkdir -p "$claude_dir/teams/$team/inboxes"
    echo '{}' > "$claude_dir/teams/$team/inboxes/team-lead.json"
    touch "$claude_dir/teams/$team/inboxes/team-lead.json"
  done

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  local remaining=0
  for team in vbw-phase-03 vbw-phase-04 vbw-plan-02 vbw-plan-03; do
    [ -d "$claude_dir/teams/$team" ] && remaining=$((remaining + 1))
  done

  if [ "$remaining" -eq 0 ]; then
    pass "all 4 configless VBW teams cleaned in single pass"
  else
    fail "expected 0 remaining configless teams, got $remaining"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_configless_vbw_debug_team_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-debug-1741625400/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-debug-1741625400/inboxes/debugger.json"
  touch "$claude_dir/teams/vbw-debug-1741625400/inboxes/debugger.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-debug-1741625400" ]; then
    fail "configless vbw-debug-* team dir should be removed"
  else
    pass "configless vbw-debug-* team dir removed immediately"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_pass2_stale_team_with_config_removed() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-09/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-09"}' > "$claude_dir/teams/vbw-phase-09/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-09/inboxes/team-lead.json"
  touch -t 202001010000 "$claude_dir/teams/vbw-phase-09/inboxes/team-lead.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/vbw-phase-09" ]; then
    fail "stale VBW team with config.json should be removed by pass 2"
  else
    pass "pass 2 removes stale VBW team with config.json after threshold"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_doctor_scan_reports_orphaned() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-05/inboxes"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-phase-05/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if grep -q "orphaned_team|vbw-phase-05" <<<"$output"; then
    pass "doctor scan reports orphaned VBW configless team"
  else
    fail "doctor scan did not report orphaned VBW team. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_doctor_scan_skips_non_vbw_orphan() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/my-custom-team/inboxes"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/my-custom-team/inboxes/agent.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if grep -q "orphaned_team|my-custom-team" <<<"$output"; then
    fail "doctor scan should not report non-VBW configless team"
  else
    pass "doctor scan skips non-VBW configless team"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_exec_protocol_post_teamdelete_cleanup() {
  if grep -q 'Post-shutdown residual cleanup' "$ROOT/references/execute-protocol.md"; then
    pass "execute-protocol.md has post-shutdown residual cleanup"
  else
    fail "execute-protocol.md missing post-shutdown residual cleanup"
  fi
}

test_exec_protocol_pre_teamcreate_cleanup() {
  if grep -q 'Pre-spawn stale-team cleanup' "$ROOT/references/execute-protocol.md"; then
    pass "execute-protocol.md has pre-spawn stale-team cleanup"
  else
    fail "execute-protocol.md missing pre-spawn stale-team cleanup"
  fi
}

test_vibe_no_team_in_plan_mode() {
  if grep -q 'No team creation in Plan mode' "$ROOT/commands/vibe.md"; then
    pass "vibe.md enforces no team creation in Plan mode"
  else
    fail "vibe.md missing 'No team creation in Plan mode' statement"
  fi
}

test_vibe_no_team_machinery_in_plan() {
  local plan_section
  plan_section=$(sed -n '/^### Mode: Plan$/,/^### Mode:/p' "$ROOT/commands/vibe.md")
  if [ -z "$plan_section" ]; then
    fail "Could not extract Plan mode section from vibe.md (heading format may have changed)"
    return
  fi
  if grep -q 'TeamCreate' <<<"$plan_section" || grep -q 'TeamDelete' <<<"$plan_section"; then
    fail "vibe.md Plan mode section still references TeamCreate/TeamDelete"
  else
    pass "vibe.md Plan mode section has no team machinery"
  fi
}

test_debug_prefer_teams_never() {
  if grep -q "prefer_teams='never'" "$ROOT/commands/debug.md"; then
    pass "debug.md has prefer_teams=never decision tree entry"
  else
    fail "debug.md missing prefer_teams=never decision tree entry"
  fi
}

test_map_prefer_teams_never() {
  if grep -q "prefer_teams.*never" "$ROOT/commands/map.md" && grep -q 'force solo' "$ROOT/commands/map.md"; then
    pass "map.md enforces prefer_teams=never to solo mode"
  else
    fail "map.md missing prefer_teams=never to solo enforcement"
  fi
}

test_map_post_teamdelete_cleanup() {
  if grep -q 'Post-shutdown residual cleanup' "$ROOT/commands/map.md"; then
    pass "map.md has post-shutdown residual cleanup"
  else
    fail "map.md missing post-shutdown residual cleanup"
  fi
}

test_debug_post_teamdelete_cleanup() {
  if grep -q 'Post-shutdown residual cleanup' "$ROOT/commands/debug.md"; then
    pass "debug.md has post-shutdown residual cleanup"
  else
    fail "debug.md missing post-shutdown residual cleanup"
  fi
}

test_clean_script_has_configless_pass() {
  if grep -q 'config.json' "$CLEAN_SCRIPT" && grep -q 'Orphaned team cleanup' "$CLEAN_SCRIPT"; then
    pass "clean-stale-teams.sh has configless orphan detection"
  else
    fail "clean-stale-teams.sh missing configless orphan detection"
  fi
}

test_clean_script_vbw_prefix_guard() {
  local pass1_region
  pass1_region=$(sed -n '/^# Pass 1/,/^# Pass 2/p' "$CLEAN_SCRIPT")
  if grep -q 'case "$team_name" in vbw-\*)' <<<"$pass1_region"; then
    pass "clean-stale-teams.sh has vbw-* prefix guard in configless pass (pass 1)"
  else
    fail "clean-stale-teams.sh missing vbw-* prefix guard in pass 1"
  fi
}

test_debug_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-spawn stale-team cleanup' "$ROOT/commands/debug.md" | head -1 | cut -d: -f1)
  naming_line=$(grep -n 'team_name="vbw-debug-' "$ROOT/commands/debug.md" | head -1 | cut -d: -f1)
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "debug.md has pre-spawn stale-team cleanup before teammate spawn"
  else
    fail "debug.md pre-spawn stale-team cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

test_map_duo_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-spawn stale-team cleanup' "$ROOT/commands/map.md" | grep -i 'duo\|step 3-duo' | head -1 | cut -d: -f1)
  [ -z "$cleanup_line" ] && cleanup_line=$(grep -n 'Pre-spawn stale-team cleanup' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  naming_line=$(grep -n 'description="Codebase Map (duo)"' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "map.md Step 3-duo has pre-spawn stale-team cleanup before duo team formation"
  else
    fail "map.md Step 3-duo pre-spawn stale-team cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

test_map_quad_pre_teamcreate_cleanup() {
  local cleanup_line naming_line
  cleanup_line=$(grep -n 'Pre-spawn stale-team cleanup' "$ROOT/commands/map.md" | tail -1 | cut -d: -f1)
  naming_line=$(grep -n 'description="Codebase Map (quad)"' "$ROOT/commands/map.md" | head -1 | cut -d: -f1)
  if [ -n "$cleanup_line" ] && [ -n "$naming_line" ] && [ "$cleanup_line" -le "$naming_line" ]; then
    pass "map.md Step 3-quad has pre-spawn stale-team cleanup before quad team formation"
  else
    fail "map.md Step 3-quad pre-spawn stale-team cleanup missing or out of order (cleanup=$cleanup_line, naming=$naming_line)"
  fi
}

test_debug_uses_vbw_prefix_naming() {
  if grep -q 'team_name="vbw-debug-{timestamp}"' "$ROOT/commands/debug.md"; then
    pass "debug.md uses parameter-style vbw-debug- team naming"
  else
    fail "debug.md does not use parameter-style vbw-debug- team naming"
  fi
}

test_map_duo_naming() {
  if grep -q 'description="Codebase Map (duo)"' "$ROOT/commands/map.md"; then
    pass "map.md specifies duo team-formation marker"
  else
    fail "map.md missing duo team-formation marker"
  fi
}

test_map_quad_naming() {
  if grep -q 'description="Codebase Map (quad)"' "$ROOT/commands/map.md"; then
    pass "map.md specifies quad team-formation marker"
  else
    fail "map.md missing quad team-formation marker"
  fi
}

test_non_vbw_stale_configless_preserved_pass2() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/other-plugin-team/inboxes"
  mkdir -p "$claude_dir/tasks"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/other-plugin-team/inboxes/agent.json"
  touch -t 202001010000 "$claude_dir/teams/other-plugin-team/inboxes/agent.json"

  CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$CLEAN_SCRIPT" 2>/dev/null

  if [ -d "$claude_dir/teams/other-plugin-team" ]; then
    pass "non-VBW configless team with stale inbox preserved by pass 2"
  else
    fail "non-VBW configless team with stale inbox was incorrectly removed by pass 2"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_clean_script_pass2_vbw_prefix_guard() {
  local pass2_region
  pass2_region=$(sed -n '/^# Pass 2/,/^done$/p' "$CLEAN_SCRIPT")
  if grep -q 'case "$team_name" in vbw-\*)' <<<"$pass2_region"; then
    pass "clean-stale-teams.sh pass 2 has vbw-* prefix guard"
  else
    fail "clean-stale-teams.sh pass 2 missing vbw-* prefix guard"
  fi
}

test_doctor_scan_reports_paired_tasks() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-07/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-phase-07"
  mkdir -p "$planning_dir"
  echo '{}' > "$claude_dir/teams/vbw-phase-07/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if grep -q "orphaned_tasks|vbw-phase-07" <<<"$output"; then
    pass "doctor scan reports paired tasks dir for orphaned team"
  else
    fail "doctor scan did not report paired tasks dir. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

test_doctor_scan_reports_stale_paired_tasks() {
  TMPDIR_BASE=$(mktemp -d "$TEST_PARENT/XXXXXX")
  local claude_dir="$TMPDIR_BASE/claude"
  local planning_dir="$TMPDIR_BASE/project/.vbw-planning"
  mkdir -p "$claude_dir/teams/vbw-phase-12/inboxes"
  mkdir -p "$claude_dir/tasks/vbw-phase-12"
  mkdir -p "$planning_dir"
  echo '{"name":"vbw-phase-12"}' > "$claude_dir/teams/vbw-phase-12/config.json"
  echo '{}' > "$claude_dir/teams/vbw-phase-12/inboxes/team-lead.json"
  touch -t 202001010000 "$claude_dir/teams/vbw-phase-12/inboxes/team-lead.json"

  local output
  output=$(cd "$TMPDIR_BASE/project" && \
    CLAUDE_CONFIG_DIR="$claude_dir" VBW_PLANNING_DIR="$planning_dir" \
    bash "$DOCTOR_SCRIPT" scan 2>/dev/null) || true

  if grep -q "stale_tasks|vbw-phase-12" <<<"$output"; then
    pass "doctor scan reports paired tasks dir for stale team"
  else
    fail "doctor scan did not report stale paired tasks dir. Output: $output"
  fi
  rm -rf "$TMPDIR_BASE"
}

echo "=== Ghost Team Cleanup Tests (#203) ==="
echo ""

test_configless_vbw_team_removed
test_non_vbw_configless_preserved
test_vbw_team_with_config_preserved
test_paired_tasks_removed
test_multiple_configless_cleaned
test_configless_vbw_debug_team_removed
test_pass2_stale_team_with_config_removed
test_doctor_scan_reports_orphaned
test_doctor_scan_skips_non_vbw_orphan
test_exec_protocol_post_teamdelete_cleanup
test_exec_protocol_pre_teamcreate_cleanup
test_vibe_no_team_in_plan_mode
test_vibe_no_team_machinery_in_plan
test_debug_prefer_teams_never
test_map_prefer_teams_never
test_map_post_teamdelete_cleanup
test_debug_post_teamdelete_cleanup
test_debug_pre_teamcreate_cleanup
test_map_duo_pre_teamcreate_cleanup
test_map_quad_pre_teamcreate_cleanup
test_debug_uses_vbw_prefix_naming
test_map_duo_naming
test_map_quad_naming
test_clean_script_has_configless_pass
test_clean_script_vbw_prefix_guard
test_non_vbw_stale_configless_preserved_pass2
test_clean_script_pass2_vbw_prefix_guard
test_doctor_scan_reports_paired_tasks
test_doctor_scan_reports_stale_paired_tasks

echo ""
echo "==============================="
echo "Ghost Team Cleanup: $PASS passed, $FAIL failed"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
