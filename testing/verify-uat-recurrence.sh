#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS_COUNT=0
FAIL_COUNT=0
VIBE_UAT_REMEDIATION="$SCRIPT_DIR/references/vibe-uat-remediation.md"
VIBE_MILESTONE_RECOVERY="$SCRIPT_DIR/references/vibe-mode-milestone-uat-recovery.md"
VIBE_FILES=(
  "$SCRIPT_DIR/commands/vibe.md"
  "$VIBE_UAT_REMEDIATION"
  "$VIBE_MILESTONE_RECOVERY"
)

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }


if grep -q 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md"; then
  pass "verify.md contains CRITICAL BOUNDARY block"
else
  fail "verify.md missing CRITICAL BOUNDARY block"
fi

STEP5_LINE=$(grep -n 'CHECKPOINT loop' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
BOUNDARY_LINE=$(grep -n 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | head -1 | cut -d: -f1)
if [ -n "$STEP5_LINE" ] && [ -n "$BOUNDARY_LINE" ] && [ "$BOUNDARY_LINE" -gt "$STEP5_LINE" ]; then
  pass "CRITICAL BOUNDARY is inside Step 5 CHECKPOINT loop"
else
  fail "CRITICAL BOUNDARY should be inside Step 5 CHECKPOINT loop"
fi

if grep -A5 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | grep -qi 'record.*advance\|advance.*checkpoint\|remaining checkpoints'; then
  pass "Anti-breakout mentions recording and advancing to next checkpoint"
else
  fail "Anti-breakout should mention recording and advancing"
fi

if grep -A5 'CRITICAL BOUNDARY' "$SCRIPT_DIR/commands/verify.md" | grep -qi 'MUST NOT investigate.*debug\|MUST NOT.*implement fix'; then
  pass "Anti-breakout blocks investigation/debugging during UAT"
else
  fail "Anti-breakout should block investigation/debugging during UAT"
fi


if grep -q 'FAILED_IN_ROUNDS' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh references FAILED_IN_ROUNDS"
else
  fail "extract-uat-issues.sh missing FAILED_IN_ROUNDS support"
fi

if grep -q 'uat_round=' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh includes uat_round in header"
else
  fail "extract-uat-issues.sh missing uat_round in header"
fi

if grep -q 'count_uat_rounds' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh calls count_uat_rounds for round computation"
else
  fail "extract-uat-issues.sh should call count_uat_rounds"
fi

if grep -q 'extract_round_issue_ids\|extract-round-issue-ids.awk' "$SCRIPT_DIR/scripts/extract-uat-issues.sh"; then
  pass "extract-uat-issues.sh performs recurrence scanning for archived rounds"
else
  fail "extract-uat-issues.sh should scan archived rounds for recurrence"
fi

if grep -q 'extract_round_issue_ids()' "$SCRIPT_DIR/scripts/uat-utils.sh"; then
  pass "uat-utils.sh has extract_round_issue_ids function"
else
  fail "uat-utils.sh missing extract_round_issue_ids function"
fi


if grep -q 'FAILED_IN_ROUNDS' "${VIBE_FILES[@]}"; then
  pass "vibe.md UAT Remediation references FAILED_IN_ROUNDS"
else
  fail "vibe.md UAT Remediation missing FAILED_IN_ROUNDS reference"
fi

if grep -q 'RR >= 3\|round >= 3\|uat_round >= 3' "${VIBE_FILES[@]}"; then
  pass "vibe.md has phase-level escalation at round >= 3"
else
  fail "vibe.md missing phase-level escalation threshold"
fi

if grep -q 'failure_count descending' "${VIBE_FILES[@]}"; then
  pass "vibe.md has per-test priority ranking by failure_count descending"
else
  fail "vibe.md missing per-test priority ranking"
fi

if grep -q 'active_uat_round' "$VIBE_UAT_REMEDIATION" && grep -q 'less than `RR`' "$VIBE_UAT_REMEDIATION"; then
  pass "vibe-uat-remediation.md distinguishes active UAT round from remediation round"
else
  fail "vibe-uat-remediation.md should distinguish active UAT round from remediation round"
fi

if grep -q 'exclude the active step-2 UAT artifact itself from the scan' "$VIBE_UAT_REMEDIATION" \
  && grep -q 'never.*default to `RR`' "$VIBE_UAT_REMEDIATION"; then
  pass "vibe-uat-remediation.md excludes the active UAT artifact from recurrence scan"
else
  fail "vibe-uat-remediation.md should exclude the active UAT artifact from recurrence scan"
fi

if grep -q 'RECURRING' "$VIBE_UAT_REMEDIATION" && grep -q 'failure_count >= 2' "$VIBE_UAT_REMEDIATION"; then
  pass "vibe-uat-remediation.md has RECURRING annotation for failure_count >= 2"
else
  fail "vibe-uat-remediation.md missing RECURRING annotation logic"
fi

if grep -q 'Investigate WHY previous fixes failed' "${VIBE_FILES[@]}"; then
  pass "vibe.md Scout prompt includes prior-fix investigation directive"
else
  fail "vibe.md Scout prompt missing prior-fix investigation directive"
fi

if grep -q 'Prioritize recurring failures' "${VIBE_FILES[@]}"; then
  pass "vibe.md Lead prompt includes prioritization directive for recurring issues"
else
  fail "vibe.md Lead prompt missing prioritization directive"
fi

if grep -q 'per-test recurrence' "${VIBE_FILES[@]}"; then
  pass "vibe.md remediation summary includes per-test recurrence"
else
  fail "vibe.md remediation summary missing per-test recurrence"
fi


if grep -q 'FRESH_PD.*phase-detect\.sh' "${VIBE_FILES[@]}"; then
  pass "vibe.md Start fresh re-runs phase-detect.sh after marking"
else
  fail "vibe.md Start fresh missing phase-detect.sh re-run after marking"
fi

if grep -q 'phase_detect_error=true.*STOP\|STOP.*phase_detect_error\|empty.*phase_detect_error' "${VIBE_FILES[@]}"; then
  pass "vibe.md Start fresh has error guard for phase-detect failure"
else
  fail "vibe.md Start fresh missing error guard for phase-detect failure"
fi

if grep -q 'milestone_uat_issues=true.*STOP\|Re-trigger guard' "${VIBE_FILES[@]}"; then
  pass "vibe.md Start fresh has re-trigger guard for milestone_uat loop"
else
  fail "vibe.md Start fresh missing re-trigger guard"
fi

if grep -q 'full priority table' "${VIBE_FILES[@]}"; then
  pass "vibe.md Start fresh references full priority table for re-routing"
else
  fail "vibe.md Start fresh missing full priority table reference"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS_COUNT PASS, $FAIL_COUNT FAIL"
echo "==============================="
[ "$FAIL_COUNT" -eq 0 ]
