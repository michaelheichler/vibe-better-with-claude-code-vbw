#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULTS="$ROOT/templates/agent-roles/defaults.json"
VIBE_INPUT_PARSING="$ROOT/references/vibe-input-parsing.md"

PASS=0
FAIL=0

pass() {
  local message="$1"
  echo "PASS  $message"
  printf -v PASS '%d' "$((PASS + 1))"
}

fail() {
  local message="$1"
  echo "FAIL  $message"
  printf -v FAIL '%d' "$((FAIL + 1))"
}

QA_AGENT="$ROOT/templates/agent-roles/qa.md.tpl"

if grep -qi 'heredoc' "$QA_AGENT"; then
  fail "1: templates/agent-roles/qa.md.tpl still mentions heredoc"
else
  pass "1: templates/agent-roles/qa.md.tpl does not mention heredoc"
fi

if grep -q 'write-verification\.sh' "$QA_AGENT"; then
  pass "2: templates/agent-roles/qa.md.tpl references write-verification.sh"
else
  fail "2: templates/agent-roles/qa.md.tpl does not reference write-verification.sh"
fi

DISALLOWED_LINE=$(jq -r '.qa.disallowedTools // empty' "$DEFAULTS")
TOOLS_LINE=$(jq -r '.qa.tools // empty' "$DEFAULTS")
PERM_MODE=$(jq -r '.qa.permissionMode // empty' "$DEFAULTS")
if [ -n "$DISALLOWED_LINE" ] && grep -q 'plan' <<<"$PERM_MODE"; then
  pass "3: templates/agent-roles/qa.md.tpl uses disallowedTools + permissionMode: plan (Write blocked by platform)"
elif [ -n "$TOOLS_LINE" ] && grep -qv 'Write' <<<"$TOOLS_LINE"; then
  pass "3: templates/agent-roles/qa.md.tpl tools allowlist omits Write"
else
  fail "3: templates/agent-roles/qa.md.tpl: Write access not adequately restricted"
fi

if [ -n "$DISALLOWED_LINE" ] && grep -qv 'Bash' <<<"$DISALLOWED_LINE"; then
  pass "4: templates/agent-roles/qa.md.tpl disallowedTools does not block Bash"
elif [ -n "$TOOLS_LINE" ] && grep -q 'Bash' <<<"$TOOLS_LINE"; then
  pass "4: templates/agent-roles/qa.md.tpl still has Bash in tools"
else
  fail "4: templates/agent-roles/qa.md.tpl Bash access not available"
fi

QA_CMD="$ROOT/commands/qa.md"

if grep -q 'echo.*QA_VERDICT.*write-verification' "$QA_CMD"; then
  fail "5: commands/qa.md still pipes qa_verdict through write-verification.sh"
else
  pass "5: commands/qa.md does not pipe qa_verdict through write-verification.sh"
fi

if grep -qi 'output.path\|verification.path\|VERIFICATION.md.*path\|persist.*write-verification' "$QA_CMD"; then
  pass "6: commands/qa.md passes persistence info to QA in task description"
else
  fail "6: commands/qa.md does not pass persistence info to QA"
fi

if grep -Eq 'track-known-issues\.sh"? sync-summaries' "$QA_CMD"; then
  pass "6b: commands/qa.md backfills summary-known-issues before first phase-level QA run"
else
  fail "6b: commands/qa.md missing summary-known-issues backfill before phase-level QA"
fi

EXEC_PROTO="$ROOT/references/execute-post-build-qa.md"

EXEC_PIPE_COUNT=$(grep -c 'echo.*QA_VERDICT.*write-verification' "$EXEC_PROTO" || true)
if [ "$EXEC_PIPE_COUNT" -gt 0 ]; then
  fail "7: execute-post-build-qa.md still has orchestrator-side pipe to write-verification.sh ($EXEC_PIPE_COUNT occurrences)"
else
  pass "7: execute-post-build-qa.md does not have orchestrator-side pipe to write-verification.sh"
fi

if grep -qi 'QA.*persist\|QA.*write-verification\|QA.*calls.*write-verification\|task description.*output.path\|task description.*write-verification' "$EXEC_PROTO"; then
  pass "8: execute-post-build-qa.md describes QA-side persistence"
else
  fail "8: execute-post-build-qa.md does not describe QA-side persistence"
fi

VERIF_PROTO="$ROOT/references/verification-protocol.md"

if grep -qi 'parent command persists' "$VERIF_PROTO"; then
  fail "9: verification-protocol.md still says 'parent command persists'"
else
  pass "9: verification-protocol.md no longer says 'parent command persists'"
fi

if grep -qi 'QA.*write-verification\|QA.*persists\|QA agent.*calls\|agent.*write-verification' "$VERIF_PROTO"; then
  pass "10: verification-protocol.md reflects QA-side persistence"
else
  fail "10: verification-protocol.md does not reflect QA-side persistence"
fi


if grep -qi 'teammate.*persist\|sending.*qa_verdict.*persist\|After sending.*persist' "$QA_AGENT"; then
  pass "11: templates/agent-roles/qa.md.tpl teammate Communication references persistence"
else
  fail "11: templates/agent-roles/qa.md.tpl teammate Communication does not reference persistence"
fi

if grep -qi 'both modes\|teammate and subagent' "$QA_AGENT"; then
  pass "12: templates/agent-roles/qa.md.tpl Persistence section covers both modes"
else
  fail "12: templates/agent-roles/qa.md.tpl Persistence section does not explicitly cover both modes"
fi


if grep -q 'Plugin root:.*`echo /tmp/' "$EXEC_PROTO"; then
  fail "13: execute-post-build-qa.md passes literal echo snippet instead of resolved plugin root"
else
  pass "13: execute-post-build-qa.md does not pass literal echo snippet as plugin root"
fi

if grep -q 'Plugin root: \${CLAUDE_PLUGIN_ROOT}' "$EXEC_PROTO"; then
  fail "15: execute-post-build-qa.md QA task descriptions use CLAUDE_PLUGIN_ROOT instead of VBW_PLUGIN_ROOT"
else
  pass "15: execute-post-build-qa.md QA task descriptions use correct plugin root variable"
fi

FALLBACK_COUNT=0
for f in "$QA_CMD" "$EXEC_PROTO"; do
  if grep -qi 'fall back to writing.*VERIFICATION' "$f"; then
    FALLBACK_COUNT=$((FALLBACK_COUNT + 1))
  fi
done
if [ "$FALLBACK_COUNT" -gt 0 ]; then
  fail "14: orchestrator docs still contain manual VERIFICATION.md fallback ($FALLBACK_COUNT files)"
else
  pass "14: no orchestrator manual VERIFICATION.md fallback found"
fi


PLUGIN_ROOT_COUNT=$(grep -c 'Plugin root: \${VBW_PLUGIN_ROOT}' "$EXEC_PROTO" || true)
if [ "$PLUGIN_ROOT_COUNT" -ge 2 ]; then
  pass "16: execute-post-build-qa.md QA task descriptions use \${VBW_PLUGIN_ROOT} consistently ($PLUGIN_ROOT_COUNT occurrences)"
else
  fail "16: execute-post-build-qa.md QA task descriptions missing \${VBW_PLUGIN_ROOT} (found $PLUGIN_ROOT_COUNT, expected ≥2)"
fi

if grep -q 'track-known-issues\.sh" sync-summaries' "$VIBE_INPUT_PARSING"; then
  pass "16b: references/vibe-input-parsing.md backfills summary-known-issues before resumed phase-level QA"
else
  fail "16b: references/vibe-input-parsing.md missing summary-known-issues backfill before resumed phase-level QA"
fi

if grep -q 'No file modification\.' "$QA_AGENT" && ! grep -q 'No direct file modification' "$QA_AGENT"; then
  fail "17: templates/agent-roles/qa.md.tpl Constraints has unqualified 'No file modification' contradicting Persistence section"
else
  pass "17: templates/agent-roles/qa.md.tpl Constraints properly qualifies file modification prohibition"
fi

if grep -q "QA.*Can verify, can't write" "$ROOT/README.md"; then
  fail "18: README permission model still says QA 'can't write' without qualifying deterministic writer"
else
  pass "18: README permission model QA line does not have unqualified 'can't write'"
fi

if grep -q 'Process-exception.*justification is credible for this specific FAIL' "$QA_AGENT"; then
  pass "19: templates/agent-roles/qa.md.tpl requires QA to judge process-exception credibility"
else
  fail "19: templates/agent-roles/qa.md.tpl still treats process-exception as documentation-only"
fi

if grep -q 'documentation alone is insufficient when code-fix or plan-amendment is still realistically available' "$QA_AGENT"; then
  pass "20: templates/agent-roles/qa.md.tpl keeps fixable FAILs open despite process-exception paperwork"
else
  fail "20: templates/agent-roles/qa.md.tpl missing guard against laundering fixable FAILs through process-exception paperwork"
fi

if grep -q 'track-known-issues\.sh.*promote-todos' "$VIBE_INPUT_PARSING"; then
  pass "21: references/vibe-input-parsing.md calls promote-todos for known-issues lifecycle"
else
  fail "21: references/vibe-input-parsing.md missing promote-todos call, known issues will not auto-promote to STATE.md"
fi

if grep -q 'track-known-issues\.sh.*promote-todos' "$QA_CMD"; then
  pass "22: commands/qa.md calls promote-todos for known-issues lifecycle"
else
  fail "22: commands/qa.md missing promote-todos call, known issues won't auto-promote to STATE.md"
fi

echo ""
echo "==============================="
echo "QA persistence contract: $PASS passed, $FAIL failed"
echo "==============================="
[ "$FAIL" -eq 0 ] || exit 1
