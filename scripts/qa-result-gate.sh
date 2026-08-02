#!/usr/bin/env bash
set -euo pipefail

# qa-result-gate.sh — Deterministic QA result evaluator
#
# Reads VERIFICATION.md and outputs an unambiguous routing directive.
# The orchestrator follows the directive literally — no judgment, no rationalization.
#
# Usage: qa-result-gate.sh <phase-dir> [verif-name]
#   phase-dir:  path to the phase directory (required)
#   verif-name: VERIFICATION.md filename (optional, defaults to VERIFICATION.md)
#
# Output (key=value, always exits 0):
#   qa_gate_writer=<value>           — writer field from frontmatter (or "missing")
#   qa_gate_result=<value>           — result field from frontmatter (or "missing"/"unreadable")
#   qa_gate_fail_count=<N>           — count of FAIL rows in body
#   qa_gate_deviation_count=<N>      — count of non-placeholder deviations across SUMMARY.md files
#   qa_gate_known_issue_count=<N>    — unresolved phase known issues tracked on disk
#   qa_gate_plan_count=<N>           — count of *-PLAN.md files in phase dir
#   qa_gate_plans_verified_count=<N> — count of plans_verified entries in VERIFICATION.md frontmatter
#   qa_gate_routing=<DIRECTIVE>      — the routing decision
#
# Optional override diagnostics (only present when an override fires):
#   qa_gate_deviation_override=true  — PASS overridden because deviations exist but no FAIL checks
#   qa_gate_metadata_only_override=true — PASS overridden because remediation round changed only metadata
#   qa_gate_known_issues_override=true — PASS overridden because unresolved known issues remain
#   qa_gate_phase_deviation_count=<N> — deviations in phase-root SUMMARYs (metadata-only override)
#   qa_gate_plan_coverage=N/M        — plans verified vs plans expected
#
# Routing values:
#   PROCEED_TO_UAT       — QA passed cleanly, safe to enter UAT
#   REMEDIATION_REQUIRED — code has failures, needs plan→execute→verify cycle
#   QA_RERUN_REQUIRED    — no trustworthy QA result, re-spawn QA (not code remediation)

PHASE_DIR="${1:-}"
VERIF_NAME="${2:-}"
EXPLICIT_VERIF_NAME=false
if [ -n "$VERIF_NAME" ]; then
  EXPLICIT_VERIF_NAME=true
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVE_VERIF_SCRIPT="$SCRIPT_DIR/resolve-verification-path.sh"
if [ -f "$SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$SCRIPT_DIR/summary-utils.sh"
fi
TRACK_UAT_DEVIATIONS_SCRIPT="$SCRIPT_DIR/track-uat-deviations.sh"
: "$TRACK_UAT_DEVIATIONS_SCRIPT"

# shellcheck source=lib/qa-result-gate-path-evidence.sh
. "$SCRIPT_DIR/lib/qa-result-gate-path-evidence.sh"
# shellcheck source=lib/qa-result-gate-fail-classifications.sh
. "$SCRIPT_DIR/lib/qa-result-gate-fail-classifications.sh"
# shellcheck source=lib/qa-result-gate-known-issues.sh
. "$SCRIPT_DIR/lib/qa-result-gate-known-issues.sh"
# shellcheck source=lib/qa-result-gate-summary-deviations.sh
. "$SCRIPT_DIR/lib/qa-result-gate-summary-deviations.sh"

if [ -z "$PHASE_DIR" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Auto-resolve VERIFICATION.md filename using the same convention as
# phase-detect.sh and hard-gate.sh: {NN}-VERIFICATION.md is the primary
# convention, with plain VERIFICATION.md as a brownfield fallback.
if [ -z "$VERIF_NAME" ]; then
  VERIF_PATH=$(bash "$RESOLVE_VERIF_SCRIPT" phase "$PHASE_DIR" 2>/dev/null || true)
  if [ -n "$VERIF_PATH" ]; then
    VERIF_NAME=$(basename "$VERIF_PATH")
  else
    PHASE_NUM=$(basename "$PHASE_DIR" | grep -oE '^[0-9]+' 2>/dev/null || true)
    VERIF_NAME="${PHASE_NUM:-01}-VERIFICATION.md"
    VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
  fi
else
  VERIF_PATH="$PHASE_DIR/$VERIF_NAME"
fi

# Detect active QA remediation — deviation override is suppressed during remediation
# because SUMMARY.md deviations are historical (the code has been fixed)
IN_REMEDIATION="false"
PLAN_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level plans
SUMMARY_SCOPE_DIR="$PHASE_DIR"  # Default: phase-level summaries
if [ -f "$PHASE_DIR/remediation/qa/.qa-remediation-stage" ]; then
  _gate_stage=$(grep '^stage=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_stage="${_gate_stage:-none}"
  case "$_gate_stage" in
    plan|execute|verify|done) IN_REMEDIATION="true" ;;
    *) _gate_stage="none" ;;
  esac
  _gate_round=$(grep '^round=' "$PHASE_DIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]' || true)
  _gate_round="${_gate_round:-01}"
  # Defensive: ensure round is numeric before arithmetic
  if ! [[ "$_gate_round" =~ ^[0-9]+$ ]]; then
    _gate_round="01"
  fi
  # Defensive zero-padding (consistent with phase-detect.sh)
  _gate_round=$(printf '%02d' "$((10#${_gate_round}))")
  _gate_round_dir="$PHASE_DIR/remediation/qa/round-${_gate_round}"
  _gate_round_verif="${_gate_round_dir}/R${_gate_round}-VERIFICATION.md"
  if [ "$EXPLICIT_VERIF_NAME" = false ]; then
    case "$_gate_stage" in
      verify)
        VERIF_PATH="$_gate_round_verif"
        VERIF_NAME=$(basename "$VERIF_PATH")
        ;;
      done)
        _gate_authoritative_verif=$(bash "$RESOLVE_VERIF_SCRIPT" authoritative "$PHASE_DIR" 2>/dev/null || true)
        if [ -n "${_gate_authoritative_verif:-}" ]; then
          VERIF_PATH="$_gate_authoritative_verif"
          VERIF_NAME=$(basename "$VERIF_PATH")
        fi
        ;;
    esac
  fi
  if [ "$VERIF_PATH" = "$_gate_round_verif" ]; then
    PLAN_SCOPE_DIR="$_gate_round_dir"
    SUMMARY_SCOPE_DIR="$_gate_round_dir"
  fi
fi

GIT_ROOT=$(git -C "$PHASE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
KNOWN_ISSUES_STATUS="missing"
KNOWN_ISSUES_COUNT=0
if [ -f "$SCRIPT_DIR/track-known-issues.sh" ]; then
  _known_issues_meta=$(bash "$SCRIPT_DIR/track-known-issues.sh" status "$PHASE_DIR" 2>/dev/null || true)
  _known_issues_status=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_status=/{print $2; exit}')
  _known_issues_count_raw=$(printf '%s\n' "${_known_issues_meta:-}" | awk -F= '/^known_issues_count=/{print $2; exit}')
  case "${_known_issues_status:-}" in
    present|missing|malformed)
      case "${_known_issues_count_raw:-}" in
        '')
          if [ "$_known_issues_status" = "present" ]; then
            KNOWN_ISSUES_STATUS="probe_error"
            KNOWN_ISSUES_COUNT=0
          else
            KNOWN_ISSUES_STATUS="$_known_issues_status"
            KNOWN_ISSUES_COUNT=0
          fi
          ;;
        *[!0-9]*)
          KNOWN_ISSUES_STATUS="probe_error"
          KNOWN_ISSUES_COUNT=0
          ;;
        *)
          if [ "$_known_issues_status" != "present" ] && [ "$_known_issues_count_raw" -gt 0 ] 2>/dev/null; then
            KNOWN_ISSUES_STATUS="probe_error"
            KNOWN_ISSUES_COUNT=0
          else
            KNOWN_ISSUES_STATUS="$_known_issues_status"
            KNOWN_ISSUES_COUNT="$_known_issues_count_raw"
          fi
          ;;
      esac
      ;;
    *)
      KNOWN_ISSUES_STATUS="probe_error"
      KNOWN_ISSUES_COUNT=0
      ;;
  esac
fi

if [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
  _known_issues_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
  _known_issues_registry_count=$(json_object_array_length "${_known_issues_registry_json:-[]}")
  case "${_known_issues_registry_count:-}" in
    ''|*[!0-9]*)
      KNOWN_ISSUES_COUNT=0
      ;;
    *)
      KNOWN_ISSUES_COUNT="$_known_issues_registry_count"
      ;;
  esac
fi

# 1. File doesn't exist
if [ ! -f "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=missing"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 2. File unreadable
if [ ! -r "$VERIF_PATH" ]; then
  echo "qa_gate_writer=missing"
  echo "qa_gate_result=unreadable"
  echo "qa_gate_fail_count=0"
  echo "qa_gate_deviation_count=0"
  echo "qa_gate_known_issue_count=0"
  echo "qa_gate_plan_count=0"
  echo "qa_gate_plans_verified_count=0"
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# Parse frontmatter fields
WRITER=$(awk '
  BEGIN { in_fm=0 }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^writer:/ { sub(/^writer:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit }
' "$VERIF_PATH" 2>/dev/null)

RESULT=$(awk '
  BEGIN { in_fm=0; result_seen=0; status_seen=0; result=""; status="" }
  NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
  in_fm && /^---[[:space:]]*$/ { exit }
  in_fm && /^result:/ {
    result_seen=1
    result=$0
    sub(/^result:[[:space:]]*/, "", result)
    sub(/[[:space:]]+$/, "", result)
    next
  }
  in_fm && /^status:/ {
    status_seen=1
    status=$0
    sub(/^status:[[:space:]]*/, "", status)
    sub(/[[:space:]]+$/, "", status)
    next
  }
  END {
    if (result_seen) {
      print toupper(result)
    } else if (status_seen && (toupper(status) == "PASS" || toupper(status) == "FAIL" || toupper(status) == "PARTIAL")) {
      print toupper(status)
    }
  }
' "$VERIF_PATH" 2>/dev/null)

# Body FAIL count (defense-in-depth cross-check)
FAIL_COUNT=$(count_fail_rows_in_verification "$VERIF_PATH")

# Deviation count — scan SUMMARY.md files for non-placeholder deviations
DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$SUMMARY_SCOPE_DIR")

ROUND_SOURCE_VERIFICATION_MISSING="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  if [ -n "${_gate_round:-}" ] && [ "$((10#${_gate_round}))" -gt 1 ] 2>/dev/null; then
    _expected_source_round=$(printf '%02d' "$((10#${_gate_round} - 1))")
    _expected_source_verification="$PHASE_DIR/remediation/qa/round-${_expected_source_round}/R${_expected_source_round}-VERIFICATION.md"
    if [ ! -r "$_expected_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  else
    _phase_source_verification=$(bash "$SCRIPT_DIR/resolve-verification-path.sh" phase "$PHASE_DIR" 2>/dev/null || true)
    if [ -z "$_phase_source_verification" ] || [ ! -r "$_phase_source_verification" ]; then
      ROUND_SOURCE_VERIFICATION_MISSING="true"
    fi
  fi
fi

SOURCE_VERIFICATION_PATH=""
SOURCE_VERIFIED_AT_COMMIT=""
SOURCE_FAIL_IDS=""
SOURCE_FAIL_ROW_COUNT=0
ROUND_STARTED_AT_COMMIT=""
ROUND_STARTED_AFTER_SOURCE="true"
ROUND_ACTUAL_DIFF_PATHS=""
ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="false"
ROUND_ACTUAL_DIFF_PATHS_CANONICAL=""
ROUND_WORKTREE_PATHS_CANONICAL=""
ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=""
ROUND_INPUT_MODE="none"
ROUND_KNOWN_ISSUE_BACKLOG_PATH=""
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  _qa_remediation_state=$(bash "$SCRIPT_DIR/qa-remediation-state.sh" get "$PHASE_DIR" 2>/dev/null || true)
  SOURCE_VERIFICATION_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^source_verification_path=/{print $2; exit}')
  ROUND_STARTED_AT_COMMIT=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^round_started_at_commit=/{print $2; exit}')
  ROUND_INPUT_MODE=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^input_mode=/{print $2; exit}')
  ROUND_KNOWN_ISSUE_BACKLOG_PATH=$(printf '%s\n' "${_qa_remediation_state:-}" | awk -F= '/^known_issues_path=/{print $2; exit}')
  if [ -z "$SOURCE_VERIFICATION_PATH" ] || [ ! -r "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="true"
  fi
  if [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ "${_gate_stage:-none}" = "done" ] && [ "${ROUND_INPUT_MODE:-none}" = "none" ] && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi
  if [ -n "$SOURCE_VERIFICATION_PATH" ] && [ -r "$SOURCE_VERIFICATION_PATH" ]; then
    SOURCE_VERIFIED_AT_COMMIT=$(extract_verified_at_commit "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_IDS=$(extract_fail_ids_from_verification "$SOURCE_VERIFICATION_PATH")
    SOURCE_FAIL_ROW_COUNT=$(count_fail_rows_in_verification "$SOURCE_VERIFICATION_PATH")
  fi
  if [ -n "$SOURCE_VERIFIED_AT_COMMIT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && ! commit_is_ancestor_or_same "$GIT_ROOT" "$SOURCE_VERIFIED_AT_COMMIT" "$ROUND_STARTED_AT_COMMIT"; then
    ROUND_STARTED_AFTER_SOURCE="false"
  fi
  if [ -n "$GIT_ROOT" ] && [ -n "$ROUND_STARTED_AT_COMMIT" ] && git -C "$GIT_ROOT" cat-file -e "${ROUND_STARTED_AT_COMMIT}^{commit}" 2>/dev/null; then
    ROUND_ACTUAL_DIFF_PATHS_AVAILABLE="true"
    ROUND_ACTUAL_DIFF_PATHS=$(git_diff_paths_since_commit "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
    ROUND_ACTUAL_DIFF_PATHS_CANONICAL=$(printf '%s\n' "$ROUND_ACTUAL_DIFF_PATHS" | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_WORKTREE_PATHS_CANONICAL=$(git_current_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
    ROUND_IGNORED_WORKTREE_PATHS_CANONICAL=$(git_ignored_metadata_worktree_paths "$GIT_ROOT" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u) | canonicalize_recorded_paths "$PHASE_DIR")
  fi
fi

# Metadata-only round detection — if remediation round modified only
# .vbw-planning/ files (no production code), phase-level deviations
# are still unresolved and the override must fire.
METADATA_ONLY_ROUND="false"
ROUND_SUMMARY_MISSING="false"
ROUND_PLAN_MISSING="false"
ROUND_CHANGE_EVIDENCE_UNAVAILABLE="false"
ROUND_CHANGE_EVIDENCE_EMPTY="false"
ROUND_IGNORED_EVIDENCE_USED="false"
ROUND_SUMMARY_NONTERMINAL="false"
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  # Scan round SUMMARY.md files_modified for non-metadata paths. When
  # files_modified is absent (older summaries / partial installs), fall back to
  # commit_hashes only when they can be proven to belong to this round's history
  # after the round-start anchor and, when available, the source verification's
  # verified_at_commit.
  _mo_has_code_changes="false"
  _mo_found_summary="false"
  _mo_all_recorded_paths=""
  _mo_structural_recorded_paths=""
  _mo_effective_files=""
  while IFS= read -r _mo_summary; do
    [ -f "$_mo_summary" ] || continue
    _mo_found_summary="true"
    _mo_status=$(awk '
      BEGIN { in_fm=0 }
      NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
      in_fm && /^---[[:space:]]*$/ { exit }
      in_fm && /^status:/ { sub(/^status:[[:space:]]*/, ""); print; exit }
    ' "$_mo_summary" 2>/dev/null)
    case "${_mo_status:-}" in
      complete|completed|partial|failed) ;;
      *) ROUND_SUMMARY_NONTERMINAL="true" ;;
    esac
    _mo_files=$(extract_frontmatter_array_items "$_mo_summary" files_modified)
    _mo_recorded_files=$(printf '%s\n' "$_mo_files" | canonicalize_recorded_paths "$PHASE_DIR")
    _mo_commit_hashes=$(extract_frontmatter_array_items "$_mo_summary" commit_hashes)
    _mo_commits=$(printf '%s\n' "$_mo_commit_hashes" | awk 'NF { count++ } END { print count + 0 }')
    _mo_commits="${_mo_commits:-0}"
    if [ -z "$_mo_files" ] && [ "$_mo_commits" -eq 0 ] 2>/dev/null; then
      ROUND_CHANGE_EVIDENCE_EMPTY="true"
    fi
    if [ -n "$_mo_files" ]; then
      _mo_structural_recorded_paths=$(printf '%s\n%s\n' "${_mo_structural_recorded_paths:-}" "$_mo_recorded_files")
      if [ -z "$_mo_recorded_files" ]; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      elif [ -n "$GIT_ROOT" ]; then
        if [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] || [ "$ROUND_ACTUAL_DIFF_PATHS_AVAILABLE" != "true" ]; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        _mo_effective_files=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL")
        if [ -z "$_mo_effective_files" ] || ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_effective_files"; then
          ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
          break
        fi
        # Detect whether gitignored-metadata evidence was needed for corroboration
        if [ "$ROUND_IGNORED_EVIDENCE_USED" != "true" ] && [ -n "$ROUND_IGNORED_WORKTREE_PATHS_CANONICAL" ]; then
          _mo_without_ignored=$(resolve_corroborated_recorded_paths "$PHASE_DIR" "$_mo_recorded_files" "$ROUND_ACTUAL_DIFF_PATHS_CANONICAL" "$ROUND_WORKTREE_PATHS_CANONICAL" "")
          if ! recorded_paths_are_fully_corroborated "$_mo_recorded_files" "$_mo_without_ignored"; then
            ROUND_IGNORED_EVIDENCE_USED="true"
          fi
        fi
      else
        _mo_effective_files="$_mo_recorded_files"
      fi
      _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_effective_files")
      if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_effective_files"; then
        _mo_has_code_changes="true"
      fi
    elif [ "$_mo_commits" -gt 0 ] 2>/dev/null; then
      if ! commit_hashes_resolve_cleanly "$GIT_ROOT" "$_mo_commit_hashes" \
        || [ "$ROUND_STARTED_AFTER_SOURCE" != "true" ] \
        || ! commit_hashes_are_round_local "$GIT_ROOT" "$ROUND_STARTED_AT_COMMIT" "$_mo_commit_hashes"; then
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
      _mo_commit_files="$(commit_hashes_to_changed_files "$GIT_ROOT" "$_mo_commit_hashes" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))"
      if [ -n "$_mo_commit_files" ]; then
        _mo_all_recorded_paths=$(printf '%s\n%s\n' "${_mo_all_recorded_paths:-}" "$_mo_commit_files")
        if paths_include_non_metadata "$PHASE_DIR" <<< "$_mo_commit_files"; then
          _mo_has_code_changes="true"
        fi
      else
        ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
        break
      fi
    fi
    [ "$_mo_has_code_changes" = "true" ] && break
  done < <(find "$SUMMARY_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
  # Only flag metadata-only when a round SUMMARY.md exists — if no summary was
  # found, the remediation round is structurally incomplete and PASS must not
  # proceed without the artifact that carries change evidence.
  if [ "$_mo_found_summary" = "false" ]; then
    ROUND_SUMMARY_MISSING="true"
  elif [ "$_mo_has_code_changes" = "false" ]; then
    METADATA_ONLY_ROUND="true"
  fi
fi

# Plan coverage — count PLAN.md files and plans_verified entries
PLAN_COUNT=0
while IFS= read -r plan_file; do
  [ -f "$plan_file" ] || continue
  PLAN_COUNT=$((PLAN_COUNT + 1))
done < <(find "$PLAN_SCOPE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))

# Parse plans_verified from VERIFICATION.md frontmatter (YAML array)
PLANS_VERIFIED_COUNT=$(extract_frontmatter_array_items "$VERIF_PATH" plans_verified | awk '
  {
    if (!seen[$0]++) count++
  }
  END { print count + 0 }
' 2>/dev/null)
PLANS_VERIFIED_COUNT="${PLANS_VERIFIED_COUNT:-0}"

if [ "$IN_REMEDIATION" = "true" ] && [ "$PLAN_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$PLAN_COUNT" -eq 0 ] 2>/dev/null; then
  ROUND_PLAN_MISSING="true"
fi

ROUND_ALL_RECORDED_PATHS=$(printf '%s\n' "${_mo_all_recorded_paths:-}" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
ROUND_RECORDED_STRUCTURAL_PATHS=$(printf '%s\n' "${_mo_structural_recorded_paths:-}" | sed '/^[[:space:]]*$/d' | (sort -u 2>/dev/null || sort -u))
ROUND_CLASSIFICATION_TYPES=""
ROUND_CLASSIFICATION_IDS=""
ROUND_CLASSIFICATION_TYPE_COUNT=0
ROUND_CLASSIFICATION_ID_COUNT=0
ROUND_CODE_FIX_COUNT=0
ROUND_PLAN_AMENDMENT_COUNT=0
ROUND_PLAN_AMENDMENT_SOURCE_PLANS=""
ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=0
ROUND_CLASSIFICATIONS_VALID=true
ROUND_KNOWN_ISSUE_INPUTS_JSON='[]'
ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON='[]'
ROUND_KNOWN_ISSUE_OUTCOMES_JSON='[]'
ROUND_CARRIED_KNOWN_ISSUES_JSON='[]'
ROUND_KNOWN_ISSUE_INPUT_COUNT=0
ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=0
ROUND_KNOWN_ISSUE_OUTCOME_COUNT=0
ROUND_CARRIED_KNOWN_ISSUE_COUNT=0
ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="false"
ROUND_KNOWN_ISSUES_VALID=true
ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=false
if [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; then
  ROUND_CLASSIFICATION_TYPES=$(collect_fail_classification_types_in_dir "$PLAN_SCOPE_DIR")
  ROUND_CLASSIFICATION_IDS=$(collect_fail_classification_ids_in_dir "$PLAN_SCOPE_DIR" | (sort -u 2>/dev/null || sort -u))
  ROUND_CLASSIFICATION_TYPE_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CLASSIFICATION_ID_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_IDS" | awk 'NF { count++ } END { print count + 0 }')
  ROUND_CODE_FIX_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "code-fix" { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_COUNT=$(printf '%s\n' "$ROUND_CLASSIFICATION_TYPES" | awk '$0 == "plan-amendment" { count++ } END { print count + 0 }')
  ROUND_PLAN_AMENDMENT_SOURCE_PLANS=$(collect_fail_classification_source_plans_in_dir "$PLAN_SCOPE_DIR")
  ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT=$(printf '%s\n' "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" | awk 'NF { count++ } END { print count + 0 }')

  if [ "$ROUND_CLASSIFICATION_ID_COUNT" -ne "$ROUND_CLASSIFICATION_TYPE_COUNT" ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null && ! fail_classification_types_are_valid <<< "$ROUND_CLASSIFICATION_TYPES"; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$METADATA_ONLY_ROUND" = "true" ] && [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && [ "$ROUND_CLASSIFICATION_ID_COUNT" -eq 0 ] 2>/dev/null; then
    ROUND_CLASSIFICATIONS_VALID=false
  elif [ "$SOURCE_FAIL_ROW_COUNT" -gt 0 ] 2>/dev/null && {
    [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -ne "$SOURCE_FAIL_ROW_COUNT" ] 2>/dev/null \
      || ! classification_ids_cover_source_fail_ids "$SOURCE_FAIL_IDS" "$ROUND_CLASSIFICATION_IDS";
  }; then
    ROUND_CLASSIFICATIONS_VALID=false
  fi
  if [ -z "$GIT_ROOT" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
    ROUND_CHANGE_EVIDENCE_UNAVAILABLE="true"
  fi

  ROUND_KNOWN_ISSUE_INPUTS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issues_input issue)
  ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON=$(collect_frontmatter_json_object_array_in_dir "$PLAN_SCOPE_DIR" plan known_issue_resolutions resolution)
  ROUND_KNOWN_ISSUE_OUTCOMES_JSON=$(collect_frontmatter_json_object_array_in_dir "$SUMMARY_SCOPE_DIR" summary known_issue_outcomes outcome)
  ROUND_CARRIED_KNOWN_ISSUES_JSON=$(load_known_issue_registry_json "$ROUND_KNOWN_ISSUE_BACKLOG_PATH")
  ROUND_KNOWN_ISSUE_INPUT_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_INPUTS_JSON")
  ROUND_KNOWN_ISSUE_RESOLUTION_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON")
  ROUND_KNOWN_ISSUE_OUTCOME_COUNT=$(json_object_array_length "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON")
  ROUND_CARRIED_KNOWN_ISSUE_COUNT=$(json_object_array_length "$ROUND_CARRIED_KNOWN_ISSUES_JSON")

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_RESOLUTION_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
    || [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null \
    || [ "${ROUND_INPUT_MODE:-none}" = "known-issues" ] \
    || [ "${ROUND_INPUT_MODE:-none}" = "both" ]; then
    ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED="true"
  fi

  if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ]; then
    if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif [ "$ROUND_CARRIED_KNOWN_ISSUE_COUNT" -gt 0 ] 2>/dev/null && ! json_object_array_covers_full_issue_objects "$ROUND_CARRIED_KNOWN_ISSUES_JSON" "$ROUND_KNOWN_ISSUE_INPUTS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_covers_full_issue_objects "$ROUND_KNOWN_ISSUE_INPUTS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif ! json_object_array_dispositions_match "$ROUND_KNOWN_ISSUE_RESOLUTIONS_JSON" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
      ROUND_KNOWN_ISSUES_VALID=false
    elif json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" && [ "$KNOWN_ISSUES_COUNT" -eq 0 ] 2>/dev/null; then
      ROUND_KNOWN_ISSUES_VALID=false
    fi
  fi

  if [ "$ROUND_KNOWN_ISSUE_INPUT_COUNT" -gt 0 ] 2>/dev/null && [ "$SOURCE_FAIL_ROW_COUNT" -eq 0 ] 2>/dev/null && [ -z "$SOURCE_VERIFICATION_PATH" ]; then
    ROUND_SOURCE_VERIFICATION_MISSING="false"
  fi

  if paths_include_process_exception_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
    ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=true
  elif [ "$METADATA_ONLY_ROUND" = "true" ] \
    && [ "$ROUND_CHANGE_EVIDENCE_UNAVAILABLE" = "true" ] \
    && paths_are_process_exception_evidence_artifacts "$PHASE_DIR" <<< "$ROUND_RECORDED_STRUCTURAL_PATHS"; then
    ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID=true
  fi
fi

# Output diagnostic fields
echo "qa_gate_writer=${WRITER:-missing}"
echo "qa_gate_result=${RESULT:-missing}"
echo "qa_gate_fail_count=$FAIL_COUNT"
echo "qa_gate_deviation_count=$DEVIATION_COUNT"
echo "qa_gate_known_issue_count=$KNOWN_ISSUES_COUNT"
echo "qa_gate_plan_count=$PLAN_COUNT"
echo "qa_gate_plans_verified_count=$PLANS_VERIFIED_COUNT"
if [ "$ROUND_IGNORED_EVIDENCE_USED" = "true" ]; then
  echo "qa_gate_planning_ignored_evidence=true"
fi

# 3. Writer provenance check
if [ -z "$WRITER" ] || [ "$WRITER" != "write-verification.sh" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 4. Result field empty
if [ -z "$RESULT" ]; then
  echo "qa_gate_routing=QA_RERUN_REQUIRED"
  exit 0
fi

# 5-7. Route based on result + fail count + deviation cross-check + plan coverage + metadata-only
case "$RESULT" in
  PASS)
    if [ "$FAIL_COUNT" -gt 0 ] 2>/dev/null; then
      # 6. PASS with FAIL rows → defense-in-depth override
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_NONTERMINAL" = "true" ]; then
      echo "qa_gate_round_summary_nonterminal=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SOURCE_VERIFICATION_MISSING" = "true" ]; then
      echo "qa_gate_source_verification_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_SUMMARY_MISSING" = "true" ]; then
      echo "qa_gate_round_summary_missing=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_PLAN_MISSING" = "true" ]; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_UNAVAILABLE" = "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
      echo "qa_gate_round_change_evidence_unavailable=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$ROUND_CHANGE_EVIDENCE_EMPTY" = "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
      echo "qa_gate_round_change_evidence_empty=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] \
      && [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
      && [ "$ROUND_KNOWN_ISSUES_VALID" != "true" ]; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_CLASSIFICATIONS_VALID" != "true" ]; then
      if [ "$METADATA_ONLY_ROUND" = "true" ]; then
        PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$PHASE_DIR")
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
      fi
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$METADATA_ONLY_ROUND" != "true" ] && [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null && ! paths_include_code_fix_evidence "$PHASE_DIR" <<< "$ROUND_ALL_RECORDED_PATHS"; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$IN_REMEDIATION" = "true" ] && [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ] && [ "$ROUND_PLAN_AMENDMENT_COUNT" -gt 0 ] 2>/dev/null && {
      [ "$ROUND_PLAN_AMENDMENT_SOURCE_PLAN_COUNT" -ne "$ROUND_PLAN_AMENDMENT_COUNT" ] 2>/dev/null \
        || ! plan_amendment_source_plans_are_valid "$PHASE_DIR" <<< "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" \
        || ! paths_cover_required_original_plan_artifacts "$PHASE_DIR" "$ROUND_PLAN_AMENDMENT_SOURCE_PLANS" <<< "$ROUND_ALL_RECORDED_PATHS";
    }; then
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$DEVIATION_COUNT" -gt 0 ] && { [ "$IN_REMEDIATION" = "false" ] || [ "$SUMMARY_SCOPE_DIR" != "$PHASE_DIR" ]; }; then
      # 5a. PASS but deviations exist without FAIL checks → QA rationalized deviations.
      # During remediation, phase-root SUMMARY.md deviations are historical and must
      # not override a fresh PASS. Current-round SUMMARY.md deviations are still real
      # and must be reflected as FAIL checks, so scoped round summaries keep the override.
      echo "qa_gate_deviation_override=true"
      # Also check plan coverage so both diagnostics surface simultaneously
      if [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      fi
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$METADATA_ONLY_ROUND" = "true" ]; then
      # 5c. Remediation round made no implementation/config changes — only
      # metadata/planning/documentation updates. Re-check phase-level deviations.
      # Metadata-only rounds are invalid when they still claim a code-fix path.
      # Pure plan-amendment rounds can resolve cleanly when the original plan was
      # actually updated. Pure process-exception rounds can resolve cleanly only
      # when the recorded evidence includes planning/remediation artifacts rather
      # than delivered docs/README changes alone. Semantic correctness of a
      # process-exception (i.e. whether it is truly non-fixable) is still enforced
      # by remediation QA re-verifying the original FAILs; this deterministic gate
      # only validates structural evidence.
      PHASE_DEVIATION_COUNT=$(count_deviations_in_dir "$PHASE_DIR" "$PHASE_DIR")
      if [ "$ROUND_CODE_FIX_COUNT" -gt 0 ] 2>/dev/null; then
        echo "qa_gate_metadata_only_override=true"
        echo "qa_gate_phase_deviation_count=$PHASE_DEVIATION_COUNT"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$ROUND_PLAN_AMENDMENT_COUNT" -eq 0 ] 2>/dev/null \
        && [ "$ROUND_CLASSIFICATION_TYPE_COUNT" -gt 0 ] 2>/dev/null \
        && [ "$ROUND_PROCESS_EXCEPTION_EVIDENCE_VALID" != "true" ]; then
        echo "qa_gate_process_exception_evidence_missing=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
        echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
        echo "qa_gate_routing=QA_RERUN_REQUIRED"
      elif [ "$KNOWN_ISSUES_STATUS" = "malformed" ] || [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
        echo "qa_gate_known_issues_override=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
        # Metadata-only round claims clean, but known issues exist in registry.
        # Apply the same coverage guard as the non-metadata-only known-issues path:
        # outcomes must cover every live registry entry, not just the carried snapshot.
        _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
        if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
           && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
           && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
           && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
          echo "qa_gate_known_issues_all_addressed=true"
          echo "qa_gate_routing=PROCEED_TO_UAT"
        else
          echo "qa_gate_known_issues_override=true"
          echo "qa_gate_routing=REMEDIATION_REQUIRED"
        fi
      else
        echo "qa_gate_routing=PROCEED_TO_UAT"
      fi
    elif [ "$PLAN_COUNT" -gt 0 ] && [ "$PLANS_VERIFIED_COUNT" -lt "$PLAN_COUNT" ]; then
      # 5b. PASS but incomplete plan coverage → QA skipped some plans
      echo "qa_gate_plan_coverage=${PLANS_VERIFIED_COUNT}/${PLAN_COUNT}"
      echo "qa_gate_routing=QA_RERUN_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "malformed" ] || [ "$KNOWN_ISSUES_STATUS" = "probe_error" ]; then
      echo "qa_gate_known_issues_override=true"
      echo "qa_gate_routing=REMEDIATION_REQUIRED"
    elif [ "$KNOWN_ISSUES_STATUS" = "present" ] && [ "$KNOWN_ISSUES_COUNT" -gt 0 ] 2>/dev/null; then
      # Known issues exist in the registry. If this remediation round properly
      # addressed all of them (contract valid, outcomes recorded, none unresolved,
      # AND outcomes cover every live registry entry — not just carried snapshot),
      # allow proceeding rather than blocking on stale registry entries.
      _live_registry_json=$(load_known_issue_registry_json "$PHASE_DIR/known-issues.json")
      if [ "$ROUND_KNOWN_ISSUE_CONTRACT_REQUIRED" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUES_VALID" = "true" ] \
         && [ "$ROUND_KNOWN_ISSUE_OUTCOME_COUNT" -gt 0 ] 2>/dev/null \
         && ! json_object_array_has_disposition "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON" "unresolved" \
         && json_object_array_covers_full_issue_objects "$_live_registry_json" "$ROUND_KNOWN_ISSUE_OUTCOMES_JSON"; then
        echo "qa_gate_known_issues_all_addressed=true"
        echo "qa_gate_routing=PROCEED_TO_UAT"
      else
        echo "qa_gate_known_issues_override=true"
        echo "qa_gate_routing=REMEDIATION_REQUIRED"
      fi
    else
      # 5. Clean PASS
      echo "qa_gate_routing=PROCEED_TO_UAT"
    fi
    ;;
  FAIL|PARTIAL)
    # 7. Explicit failure
    echo "qa_gate_routing=REMEDIATION_REQUIRED"
    ;;
  *)
    # Unknown result value — treat as untrustworthy
    echo "qa_gate_routing=QA_RERUN_REQUIRED"
    ;;
esac

exit 0
