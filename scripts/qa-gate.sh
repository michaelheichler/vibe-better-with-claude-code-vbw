#!/bin/bash
set -u

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

[ ! -d "$PLANNING_DIR" ] && exit 0

_QG_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_QG_SUPPORT_LOADED=false
_QG_SUPPORT_READY=true

if [ -f "$_QG_SCRIPT_DIR/summary-utils.sh" ]; then
  if ! . "$_QG_SCRIPT_DIR/summary-utils.sh" >/dev/null 2>&1; then
    _QG_SUPPORT_READY=false
  fi
else
  _QG_SUPPORT_READY=false
fi

for _qg_dependency in \
  verification-freshness.sh \
  lib/phase-detect-support.sh \
  resolve-verification-path.sh \
  qa-result-gate.sh \
  track-known-issues.sh \
  lib/qa-result-gate-path-evidence.sh \
  lib/qa-result-gate-fail-classifications.sh \
  lib/qa-result-gate-known-issues.sh \
  lib/qa-result-gate-summary-deviations.sh \
  lib/track-known-issues-parsers.sh; do
  [ -r "$_QG_SCRIPT_DIR/$_qg_dependency" ] || _QG_SUPPORT_READY=false
done

if [ "$_QG_SUPPORT_READY" = true ]; then
  _SCRIPT_DIR_PD="$_QG_SCRIPT_DIR"
  if ! . "$_QG_SCRIPT_DIR/verification-freshness.sh" >/dev/null 2>&1 ||
     ! . "$_QG_SCRIPT_DIR/lib/phase-detect-support.sh" >/dev/null 2>&1; then
    _QG_SUPPORT_READY=false
  else
    _QG_SUPPORT_LOADED=true
  fi
fi

if [ "$_QG_SUPPORT_READY" = false ] && ! declare -F count_complete_summaries >/dev/null 2>&1; then
  count_complete_summaries() { echo "0"; }
fi

cat >/dev/null 2>&1 || exit 0

SUMMARY_OK=false
PLANS_TOTAL=0
SUMMARIES_TOTAL=0

for phase_dir in "$PLANNING_DIR/phases"/*/; do
  [ -d "$phase_dir" ] || continue
  PLANS=$(ls -1 "$phase_dir"*-PLAN.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$_QG_SUPPORT_LOADED" = true ]; then
    COMPLETE_SUMMARIES=$(count_complete_summaries "$phase_dir")
    if phase_execution_is_satisfied "$phase_dir" "$PLANS" "$COMPLETE_SUMMARIES"; then
      SUMMARIES="$PLANS"
    else
      SUMMARIES=0
    fi
  else
    SUMMARIES=$(count_complete_summaries "$phase_dir")
  fi
  PLANS_TOTAL=$(( PLANS_TOTAL + PLANS ))
  SUMMARIES_TOTAL=$(( SUMMARIES_TOTAL + SUMMARIES ))
done

if [ "$PLANS_TOTAL" -eq 0 ] || [ "$SUMMARIES_TOTAL" -ge "$PLANS_TOTAL" ]; then
  SUMMARY_OK=true
fi

NOW=$(date +%s 2>/dev/null) || exit 0
TWO_HOURS=7200
if command -v jq &>/dev/null && [ -f "$PLANNING_DIR/config.json" ]; then
  _window=$(jq -r '.qa_commit_window_seconds // 7200' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "${_window:-0}" -gt 0 ] 2>/dev/null && TWO_HOURS="$_window"
fi

FORMAT_MATCH=false
RECENT_COMMITS=$(git log --oneline -10 --format="%ct %s" 2>/dev/null) || exit 0
[ -z "$RECENT_COMMITS" ] && exit 0

while IFS= read -r line; do
  [ -z "$line" ] && continue
  COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
  COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)

  if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - COMMIT_TS ))
    if [ "$AGE" -le "$TWO_HOURS" ]; then
      if echo "$COMMIT_MSG" | grep -qE '^(feat|fix|refactor|docs|test|chore)\([0-9]{2}-[0-9]{2}\):'; then
        FORMAT_MATCH=true
        break
      fi
    fi
  fi
done <<< "$RECENT_COMMITS"

if [ "$PLANS_TOTAL" -eq 0 ]; then
  exit 0  # No plans, nothing to verify
fi

if [ "$SUMMARY_OK" = true ]; then
  exit 0  # All summaries present
fi

SUMMARY_GAP=$(( PLANS_TOTAL - SUMMARIES_TOTAL ))
if [ "$FORMAT_MATCH" = true ] && [ "$SUMMARY_GAP" -le 1 ]; then
  exit 0  # Active work, at most 1 summary behind, allow
fi

echo "QA gate: SUMMARY.md gap detected ($SUMMARIES_TOTAL summaries for $PLANS_TOTAL plans)" >&2
exit 2
