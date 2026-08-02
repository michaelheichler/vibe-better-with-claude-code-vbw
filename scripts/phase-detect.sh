#!/bin/bash
set -u
_pd_normal_exit=false
_pd_output_file=
exec 3>&1
if _pd_output_file=$(mktemp "${TMPDIR:-/tmp}/vbw-phase-detect.XXXXXX" 2>/dev/null) &&
   [ -n "$_pd_output_file" ] && [ -f "$_pd_output_file" ]; then
  if ! exec >"$_pd_output_file"; then
    rm -f "$_pd_output_file"
    _pd_output_file=
    exit 0
  fi
else
  [ -n "$_pd_output_file" ] && rm -f "$_pd_output_file"
  _pd_output_file=
  exit 0
fi
trap '
  if [ "$_pd_normal_exit" = true ] && [ -n "$_pd_output_file" ] && [ -f "$_pd_output_file" ]; then
    cat "$_pd_output_file" >&3
  else
    printf "%s\n" "phase_detect_error=true" >&3
  fi
  [ -n "$_pd_output_file" ] && rm -f "$_pd_output_file"
  exit 0
' EXIT
# Pre-compute all project state for implement.md and other commands.
# Output: key=value pairs on stdout, one per line. Exit 0 always.

_SCRIPT_DIR_PD="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="$_SCRIPT_DIR_PD"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
if [ -f "$_SCRIPT_DIR_PD/summary-utils.sh" ]; then
  . "$_SCRIPT_DIR_PD/summary-utils.sh"
fi
if [ -f "$_SCRIPT_DIR_PD/uat-utils.sh" ]; then
  . "$_SCRIPT_DIR_PD/uat-utils.sh"
fi
if [ -f "$_SCRIPT_DIR_PD/phase-state-utils.sh" ]; then
  . "$_SCRIPT_DIR_PD/phase-state-utils.sh"
fi
if [ -f "$_SCRIPT_DIR_PD/verification-freshness.sh" ]; then
  . "$_SCRIPT_DIR_PD/verification-freshness.sh"
else
  extract_verified_at_commit() { :; }
  verification_is_stale() { return 0; }
fi

if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-support.sh"; then
  exit 0
fi
# --- jq availability ---
JQ_AVAILABLE=false
if command -v jq &>/dev/null; then
  JQ_AVAILABLE=true
fi
echo "jq_available=$JQ_AVAILABLE"

# --- Planning directory ---
if [ -d "$PLANNING_DIR" ]; then
  echo "planning_dir_exists=true"
else
  echo "planning_dir_exists=false"
  echo "project_exists=false"
  echo "phases_dir=none"
  echo "phase_count=0"
  echo "next_phase=none"
  echo "next_phase_slug=none"
  echo "next_phase_state=no_phases"
  echo "next_phase_plans=0"
  echo "next_phase_summaries=0"
  echo "uat_issues_phase=none"
  echo "uat_issues_slug=none"
  echo "uat_issues_major_or_higher=false"
  echo "uat_issues_phases="
  echo "uat_issues_count=0"
  echo "uat_blocking_phase=none"
  echo "uat_blocking_slug=none"
  echo "uat_blocking_status=none"
  echo "uat_blocking_file=none"
  echo "uat_file=none"
  echo "uat_round_count=0"
  echo "has_shipped_milestones=false"
  echo "needs_milestone_rename=false"
  echo "milestone_uat_issues=false"
  echo "milestone_uat_phase=none"
  echo "milestone_uat_slug=none"
  echo "milestone_uat_major_or_higher=false"
  echo "milestone_uat_phase_dir=none"
  echo "milestone_uat_count=0"
  echo "milestone_uat_phase_dirs="
  echo "config_effort=balanced"
  echo "config_autonomy=standard"
  echo "config_auto_commit=true"
  echo "config_planning_tracking=manual"
  echo "config_auto_push=never"
  echo "config_verification_tier=standard"
  echo "config_prefer_teams=auto"
  echo "config_max_tasks_per_plan=5"
  echo "config_context_compiler=true"
  echo "config_require_phase_discussion=false"
  echo "config_auto_uat=false"
  echo "has_unverified_phases=false"
  echo "first_unverified_phase="
  echo "first_unverified_slug="
  echo "first_qa_attention_phase="
  echo "first_qa_attention_slug="
  echo "qa_attention_status=none"
  echo "qa_attention_reason=none"
  echo "qa_status=none"
  echo "qa_reason=none"
  echo "qa_after_uat_dormant=false"
  echo "qa_round=00"
  echo "has_codebase_map=false"
  echo "brownfield=false"
  echo "execution_state=none"
  echo "phase_detect_complete=true"
  _pd_normal_exit=true
  exit 0
fi

# --- Rename legacy milestones/default (brownfield hardening) ---
# SessionStart normally performs this migration, but hooks can be unavailable
# in some local-dev setups. Running it here keeps command routing grounded in
# canonical milestone slugs even when SessionStart didn't run.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$PLANNING_DIR/milestones/default" ] && [ -f "$SCRIPT_DIR/rename-default-milestone.sh" ]; then
  bash "$SCRIPT_DIR/rename-default-milestone.sh" "$PLANNING_DIR" 2>/dev/null || true
fi

# --- Project existence ---
PROJECT_EXISTS=false
if [ -f "$PLANNING_DIR/PROJECT.md" ]; then
  if ! grep -q '{project-description}' "$PLANNING_DIR/PROJECT.md" 2>/dev/null; then
    PROJECT_EXISTS=true
  fi
fi
echo "project_exists=$PROJECT_EXISTS"

# --- Root-canonical phases (no ACTIVE indirection) ---
PHASES_DIR="$PLANNING_DIR/phases"
echo "phases_dir=$PHASES_DIR"

# --- Shipped milestones detection ---
HAS_SHIPPED_MILESTONES=false
NEEDS_MILESTONE_RENAME=false
MILESTONE_SCAN_DIRS=()
if [ -d "$PLANNING_DIR/milestones" ]; then
  MILESTONE_DIRS=()
  while IFS= read -r _ms_dir; do
    [ -n "$_ms_dir" ] || continue
    MILESTONE_DIRS+=("${_ms_dir%/}/")
  done < <(list_child_dirs_sorted "$PLANNING_DIR/milestones")

  if [ ${#MILESTONE_DIRS[@]} -gt 0 ]; then
  for _ms_dir in "${MILESTONE_DIRS[@]}"; do
    [ -d "$_ms_dir" ] || continue

    # Canonical archived milestone marker
    if [ -f "${_ms_dir}SHIPPED.md" ]; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
      continue
    fi

    # Brownfield fallback: legacy milestones may be missing SHIPPED.md but still
    # contain archived phase artifacts. Treat as shipped for recovery scanning.
    if [ -d "${_ms_dir}phases" ] && ls -d "${_ms_dir}phases"/*/ >/dev/null 2>&1; then
      HAS_SHIPPED_MILESTONES=true
      MILESTONE_SCAN_DIRS+=("$_ms_dir")
    fi
  done
  fi  # end MILESTONE_DIRS length check
  [ -d "$PLANNING_DIR/milestones/default" ] && NEEDS_MILESTONE_RENAME=true
fi
echo "has_shipped_milestones=$HAS_SHIPPED_MILESTONES"
echo "needs_milestone_rename=$NEEDS_MILESTONE_RENAME"

# --- Early config read: require_phase_discussion + auto_uat (needed before phase scanning) ---
CFG_REQUIRE_PHASE_DISCUSSION="false"
CFG_AUTO_UAT_EARLY="false"
CONFIG_FILE_EARLY="$PLANNING_DIR/config.json"
if [ "$JQ_AVAILABLE" = true ] && [ -f "$CONFIG_FILE_EARLY" ]; then
  _rpd=$(jq -r 'if .require_phase_discussion == null then false else .require_phase_discussion end' "$CONFIG_FILE_EARLY" 2>/dev/null) || true
  [ -n "${_rpd:-}" ] && CFG_REQUIRE_PHASE_DISCUSSION="$_rpd"
  _aue=$(jq -r 'if .auto_uat == null then false else .auto_uat end' "$CONFIG_FILE_EARLY" 2>/dev/null) || true
  [ -n "${_aue:-}" ] && CFG_AUTO_UAT_EARLY="$_aue"
fi
: "$CFG_REQUIRE_PHASE_DISCUSSION" "$CFG_AUTO_UAT_EARLY"

if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-active-routing.sh"; then
  exit 0
fi
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-qa-routing.sh"; then
  exit 0
fi
echo "phase_count=$PHASE_COUNT"
echo "next_phase=$NEXT_PHASE"
echo "next_phase_slug=$NEXT_PHASE_SLUG"
echo "next_phase_state=$NEXT_PHASE_STATE"
echo "next_phase_plans=$NEXT_PHASE_PLANS"
echo "next_phase_summaries=$NEXT_PHASE_SUMMARIES"
echo "has_unverified_phases=$HAS_UNVERIFIED_PHASES"
echo "first_unverified_phase=$FIRST_UNVERIFIED_PHASE"
echo "first_unverified_slug=$FIRST_UNVERIFIED_SLUG"
echo "first_qa_attention_phase=$FIRST_QA_ATTENTION_PHASE"
echo "first_qa_attention_slug=$FIRST_QA_ATTENTION_SLUG"
echo "qa_attention_status=$QA_ATTENTION_STATUS"
echo "qa_attention_reason=$QA_ATTENTION_REASON"
echo "qa_status=$QA_STATUS"
echo "qa_reason=$QA_REASON"
echo "qa_after_uat_dormant=$QA_AFTER_UAT_DORMANT"
echo "qa_round=$QA_ROUND"
echo "uat_issues_phase=$UAT_ISSUES_PHASE"
echo "uat_issues_slug=$UAT_ISSUES_SLUG"
echo "uat_issues_major_or_higher=$UAT_ISSUES_MAJOR_OR_HIGHER"
echo "uat_issues_phases=$UAT_ISSUES_PHASES"
echo "uat_issues_count=$UAT_ISSUES_COUNT"
echo "uat_blocking_phase=$UAT_BLOCKING_PHASE"
echo "uat_blocking_slug=$UAT_BLOCKING_SLUG"
echo "uat_blocking_status=$UAT_BLOCKING_STATUS"
echo "uat_blocking_file=$UAT_BLOCKING_RELATIVE_FILE"
echo "uat_file=$UAT_ISSUES_RELATIVE_FILE"
echo "uat_round_count=$UAT_ROUND_COUNT"
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-milestone-recovery.sh"; then
  exit 0
fi
if ! . "$_SCRIPT_DIR_PD/lib/phase-detect-environment-output.sh"; then
  exit 0
fi
if ! phase_detect_output_milestone_extraction; then
  exit 0
fi
echo "phase_detect_complete=true"
_pd_normal_exit=true
exit 0
