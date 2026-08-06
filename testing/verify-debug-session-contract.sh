#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

contains_literal() {
  local haystack="$1"
  local needle="$2"

  grep -Fq -- "$needle" <<< "$haystack"
}

matches_ere() {
  local haystack="$1"
  local pattern="$2"

  grep -Eq -- "$pattern" <<< "$haystack"
}

first_matching_line_number() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    index($0, needle) && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}


TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"

if [ -f "$TEMPLATE" ]; then
  pass "DEBUG-SESSION.md template exists"
else
  fail "DEBUG-SESSION.md template missing"
fi

for section in "## Issue" "## Source Todo" "## Investigation" "## Plan" "## Implementation" "## QA" "## UAT"; do
  if grep -q "^${section}" "$TEMPLATE" 2>/dev/null; then
    pass "template has section: $section"
  else
    fail "template missing section: $section"
  fi
done

for field in session_id title status created updated qa_round qa_last_result uat_round uat_last_result; do
  if grep -q "^${field}:" "$TEMPLATE" 2>/dev/null; then
    pass "template has frontmatter field: $field"
  else
    fail "template missing frontmatter field: $field"
  fi
done


STATE_SCRIPT="$ROOT/scripts/debug-session-state.sh"

if [ -f "$STATE_SCRIPT" ]; then
  pass "debug-session-state.sh exists"
else
  fail "debug-session-state.sh missing"
fi

for cmd in start start-with-source-todo start-with-selected-todo get get-or-latest resume set-status increment-qa increment-uat clear-active list; do
  if grep -q "\"$cmd\"\\|'$cmd'\\|${cmd})" "$STATE_SCRIPT" 2>/dev/null; then
    pass "state script handles command: $cmd"
  else
    fail "state script missing command: $cmd"
  fi
done

PRINT_METADATA_BLOCK="$(awk '/print_session_metadata\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)"
if grep -Fq "printf 'session_status=%q\\n'" <<< "$PRINT_METADATA_BLOCK"; then
  pass "debug-session-state.sh metadata-read contract exports session_status"
else
  fail "debug-session-state.sh metadata-read contract missing session_status export"
fi

if grep -Fq "printf 'status=%q\\n'" <<< "$PRINT_METADATA_BLOCK"; then
  fail "debug-session-state.sh metadata-read contract still exports bare status"
else
  pass "debug-session-state.sh metadata-read contract no longer exports bare status"
fi

if contains_literal "$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)" 'echo "status=$STATUS"'; then
  pass "debug-session-state.sh set-status keeps status output contract"
else
  fail "debug-session-state.sh set-status output contract drifted from status=..."
fi

if grep -Eq 'qa_last_result:[[:space:]]+pending \| skipped_no_fix_required \| pass \| fail' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh documents skipped_no_fix_required in qa_last_result vocabulary"
else
  fail "debug-session-state.sh missing skipped_no_fix_required in qa_last_result vocabulary"
fi

if grep -Eq 'uat_last_result:[[:space:]]+pending \| skipped_no_fix_required \| pass \| issues_found' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh documents skipped_no_fix_required in uat_last_result vocabulary"
else
  fail "debug-session-state.sh missing skipped_no_fix_required in uat_last_result vocabulary"
fi

if grep -q 'normalize_completed_no_verification_results()' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh has completed no-verification normalization helper"
else
  fail "debug-session-state.sh missing completed no-verification normalization helper"
fi

if contains_literal "$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$SESSION_PATH"'; then
  pass "debug-session-state.sh set-status normalizes completed no-verification sessions before move"
else
  fail "debug-session-state.sh set-status missing completed no-verification normalization"
fi

if contains_literal "$(awk '/reconcile_session_location\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$file"'; then
  pass "debug-session-state.sh reconcile path normalizes completed no-verification sessions"
else
  fail "debug-session-state.sh reconcile path missing completed no-verification normalization"
fi

if contains_literal "$(awk '/migrate_legacy_session\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'normalize_completed_no_verification_results "$file"'; then
  pass "debug-session-state.sh legacy migration normalizes completed no-verification sessions"
else
  fail "debug-session-state.sh legacy migration missing completed no-verification normalization"
fi


WRITER="$ROOT/scripts/write-debug-session.sh"

if [ -f "$WRITER" ]; then
  pass "write-debug-session.sh exists"
else
  fail "write-debug-session.sh missing"
fi

for mode in source-todo investigation qa uat status; do
  if grep -q "$mode" "$WRITER" 2>/dev/null; then
    pass "writer script handles mode: $mode"
  else
    fail "writer script missing mode: $mode"
  fi
done

INVESTIGATION_BLOCK="$(awk '/investigation\)/,/;;/' "$WRITER" 2>/dev/null || true)"
if ! grep -Eq 'qa_last_result|uat_last_result' <<< "$INVESTIGATION_BLOCK"; then
  pass "write-debug-session.sh investigation mode does not mutate QA/UAT result fields"
else
  fail "write-debug-session.sh investigation mode should not mutate QA/UAT result fields"
fi


COMPILER="$ROOT/scripts/compile-debug-session-context.sh"

if [ -f "$COMPILER" ]; then
  pass "compile-debug-session-context.sh exists"
else
  fail "compile-debug-session-context.sh missing"
fi

if grep -q 'Source Todo' "$COMPILER" 2>/dev/null; then
  pass "context compiler emits Source Todo content"
else
  fail "context compiler missing Source Todo content"
fi

for mode in qa uat; do
  if grep -q "$mode" "$COMPILER" 2>/dev/null; then
    pass "context compiler handles mode: $mode"
  else
    fail "context compiler missing mode: $mode"
  fi
done

if grep -Fq 'skipped \xE2\x80\x94 no fix required' "$COMPILER" 2>/dev/null; then
  pass "context compiler has friendly label for skipped no-fix-required results"
else
  fail "context compiler missing friendly label for skipped no-fix-required results"
fi

if grep -Fq '**QA Round:** ${QA_ROUND} (last result: ${QA_LAST_DISPLAY})' "$COMPILER" 2>/dev/null \
  && grep -Fq '**UAT Round:** ${UAT_ROUND} (last result: ${UAT_LAST_DISPLAY})' "$COMPILER" 2>/dev/null \
  && grep -Fq 'QA round ${QA_ROUND}: ${QA_LAST_DISPLAY}' "$COMPILER" 2>/dev/null; then
  pass "context compiler renders display-mapped QA/UAT result labels in all three summary sites"
else
  fail "context compiler still interpolates raw QA/UAT result labels in one or more summary sites"
fi


DEBUG_CMD="$ROOT/commands/debug.md"
DEBUG_PATH_A_BLOCK="$(sed -n '/^[[:space:]]*\*\*Path A:/,/^[[:space:]]*\*\*Path B:/p' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_PATH_B_BLOCK="$(sed -n '/^[[:space:]]*\*\*Path B:/,/^5\./p' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_ACCEPTED_EXCEPTION_BLOCK="$(sed -n '/^[[:space:]]*<accepted_exception_debug_semantics>[[:space:]]*$/,/^[[:space:]]*<\/accepted_exception_debug_semantics>[[:space:]]*$/p' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_STEP5_BLOCK="$(sed -n '/^5\. \*\*Persist to debug session/,/^If `INVESTIGATION_OUTCOME=fixed_now`/p' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_INLINE_UAT_BLOCK="$(sed -n '/^[[:space:]]*<debug_inline_uat>[[:space:]]*$/,/^[[:space:]]*<\/debug_inline_uat>[[:space:]]*$/p' "$DEBUG_CMD" 2>/dev/null || true)"

if grep -q "debug_session_routing" "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md has debug_session_routing section"
else
  fail "debug.md missing debug_session_routing section"
fi

if contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" '<accepted_exception_debug_semantics>' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'historical phase/round waivers and backlog pointers' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" '[KNOWN-ISSUE]' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'Disposition: accepted-process-exception' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'known_issue_signature.disposition' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" '[UAT-DEVIATION]' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'source: "uat-deviation"' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'uat_deviation' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'Accepted UAT summary deviation' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'active remediation request' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'fresh current evidence' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'needs_change' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'inconclusive' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'no_fix_yet'; then
  pass "debug.md defines shared accepted-exception debug semantics"
else
  fail "debug.md missing shared accepted-exception debug semantics"
fi

if contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'resolution_observation=needs_change' \
  && contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'resolution_observation=inconclusive'; then
  pass "debug.md shared accepted-exception block uses debugger-facing resolution_observation field names"
else
  fail "debug.md shared accepted-exception block missing debugger-facing resolution_observation field names"
fi

if contains_literal "$DEBUG_ACCEPTED_EXCEPTION_BLOCK" 'RESOLUTION_OBSERVATION'; then
  fail "debug.md shared accepted-exception block leaks orchestrator RESOLUTION_OBSERVATION variable"
else
  pass "debug.md shared accepted-exception block avoids orchestrator RESOLUTION_OBSERVATION variable"
fi

if contains_literal "$DEBUG_PATH_A_BLOCK" '<accepted_exception_debug_semantics>' \
  && contains_literal "$DEBUG_PATH_A_BLOCK" 'Include the accepted-exception debug semantics block before the task context.'; then
  pass "debug.md Path A injects accepted-exception semantics into investigator and implementation-owner prompts"
else
  fail "debug.md Path A missing accepted-exception semantics injection"
fi

if contains_literal "$DEBUG_PATH_A_BLOCK" 'accepted metadata alone cannot establish `already_fixed`' \
  && contains_literal "$DEBUG_PATH_A_BLOCK" 'Require fresh evidence' \
  && contains_literal "$DEBUG_PATH_A_BLOCK" 'Use `needs_change` when remediation remains'; then
  pass "debug.md Path A synthesis protects accepted exceptions from already_fixed closure"
else
  fail "debug.md Path A synthesis can still treat accepted exceptions as already_fixed"
fi

if contains_literal "$DEBUG_PATH_B_BLOCK" '<accepted_exception_debug_semantics>' \
  && contains_literal "$DEBUG_PATH_B_BLOCK" 'immediately after the Path B payload prefix' \
  && contains_literal "$DEBUG_PATH_B_BLOCK" 'Accepted-process-exception/backlog metadata alone is not enough for `already_fixed`' \
  && contains_literal "$DEBUG_PATH_B_BLOCK" 'Fresh current evidence that the current branch already contains a real fix is required before using `already_fixed`' \
  && contains_literal "$DEBUG_PATH_B_BLOCK" 'Paste only the inner contents of the shared accepted-exception debug semantics block from Step 1 here' \
  && contains_literal "$DEBUG_PATH_B_BLOCK" 'do not include the outer <accepted_exception_debug_semantics> tags here'; then
  pass "debug.md Path B injects accepted-exception semantics and fresh-evidence already_fixed rule"
else
  fail "debug.md Path B missing accepted-exception semantics or fresh-evidence already_fixed rule"
fi

if contains_literal "$DEBUG_PATH_B_BLOCK" 'Paste the shared accepted-exception debug semantics block from Step 1 here'; then
  fail "debug.md Path B accepted-exception template can nest duplicate XML tags"
else
  pass "debug.md Path B accepted-exception template avoids nested XML tags"
fi

if contains_literal "$DEBUG_STEP5_BLOCK" 'Before mapping `already_fixed` to `INVESTIGATION_OUTCOME=already_fixed`' \
  && contains_literal "$DEBUG_STEP5_BLOCK" 'fresh current evidence of actual resolution' \
  && contains_literal "$DEBUG_STEP5_BLOCK" 'accepted disposition alone is insufficient' \
  && contains_literal "$DEBUG_STEP5_BLOCK" 'A no-commit session may still complete as `already_fixed`' \
  && contains_literal "$DEBUG_STEP5_BLOCK" 'Use `needs_change` when remediation remains' \
  && contains_literal "$DEBUG_STEP5_BLOCK" '`inconclusive` when no safe fix can be applied' \
  && contains_literal "$DEBUG_STEP5_BLOCK" 'RESOLUTION_OBSERVATION=needs_change|inconclusive` → `INVESTIGATION_OUTCOME=no_fix_yet`'; then
  pass "debug.md Step 5 validates already_fixed against fresh evidence for accepted exceptions"
else
  fail "debug.md Step 5 missing accepted-exception already_fixed normalization"
fi

if contains_literal "$DEBUG_STEP5_BLOCK" 'use `inconclusive` / `no_fix_yet`' \
  || contains_literal "$DEBUG_STEP5_BLOCK" 'RESOLUTION_OBSERVATION=no_fix_yet'; then
  fail "debug.md Step 5 treats no_fix_yet as a resolution_observation value"
else
  pass "debug.md Step 5 keeps no_fix_yet as an investigation outcome only"
fi

DEBUG_START_SCRIPT="$ROOT/scripts/debug-start-selected-todo.sh"
if grep -q 'debug-start-selected-todo\.sh' "$DEBUG_CMD" 2>/dev/null \
  && grep -q 'start-with-selected-todo' "$DEBUG_START_SCRIPT" 2>/dev/null; then
  pass "debug.md uses debug-start-selected-todo helper and helper uses start-with-selected-todo"
else
  fail "debug selected-todo integration missing helper boundary or helper session creation"
fi

if grep -q 'HEAD_BEFORE' "$DEBUG_CMD" 2>/dev/null && grep -q 'HEAD_AFTER' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md compares HEAD_BEFORE and HEAD_AFTER for investigation outcomes"
else
  fail "debug.md missing HEAD_BEFORE/HEAD_AFTER outcome comparison"
fi

if grep -qF 'resolution_observation' <<< "$DEBUG_PATH_B_BLOCK"; then
  pass "debug.md Path B instructs the single debugger to return resolution_observation"
else
  fail "debug.md Path B missing resolution_observation contract"
fi

if grep -Fq 'Keep the task report-only.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'Do not edit, mutate, commit, request implementation approval, or claim the final outcome.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'debugger_report' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A investigator prompts are explicitly report-only"
else
  fail "debug.md Path A investigator prompts missing explicit report-only contract"
fi

if grep -Fq 'Wait until ALL spawned hypothesis investigators have returned `debugger_report`.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A waits for all spawned hypothesis investigators before synthesis"
else
  fail "debug.md Path A missing all-spawned-investigators synthesis barrier"
fi

if grep -Fq 'Winning hypothesis with fix: apply + commit' <<< "$DEBUG_PATH_A_BLOCK"; then
  fail "debug.md still contains winning-hypothesis apply shortcut"
else
  pass "debug.md removes winning-hypothesis apply shortcut"
fi

if grep -Fq 'If `RESOLUTION_OBSERVATION=already_fixed` or `inconclusive`: do NOT spawn an implementation owner.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A skips implementation owner for already_fixed and inconclusive"
else
  fail "debug.md Path A missing already_fixed/inconclusive no-implementation-owner guard"
fi

if grep -Fq 'If `RESOLUTION_OBSERVATION=needs_change`: spawn ONE fresh post-synthesis implementation owner via TaskCreate with `subagent_type: "${DEBUGGER_AGENT_NAME}"` and `model: "${DEBUGGER_MODEL}"`.' <<< "$DEBUG_PATH_A_BLOCK" \
  && grep -Fq 'This is a new debugger instance, not one of the earlier hypothesis investigators.' <<< "$DEBUG_PATH_A_BLOCK"; then
  pass "debug.md Path A uses a fresh vbw-debugger as the sole post-synthesis implementation owner"
else
  fail "debug.md Path A missing fresh vbw-debugger implementation-owner contract"
fi

patha_teardown_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" '**Teardown phase, HARD GATE before any implementation:**')
patha_zero_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" 'Verify: after shutdown, there must be ZERO active teammates.')
patha_impl_line=$(first_matching_line_number "$DEBUG_PATH_A_BLOCK" 'If `RESOLUTION_OBSERVATION=needs_change`: spawn ONE fresh post-synthesis implementation owner')

if [ -n "$patha_teardown_line" ] && [ -n "$patha_zero_line" ] && [ -n "$patha_impl_line" ] \
  && [ "$patha_teardown_line" -lt "$patha_zero_line" ] && [ "$patha_zero_line" -lt "$patha_impl_line" ]; then
  pass "debug.md finishes teammate teardown before implementation-owner spawn"
else
  fail "debug.md does not prove teammate teardown completes before implementation-owner spawn"
fi

if grep -qF 'INVESTIGATION_OUTCOME=fixed_now' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF 'INVESTIGATION_OUTCOME=already_fixed' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF 'INVESTIGATION_OUTCOME=no_fix_yet' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md Step 5 maps fixed_now, already_fixed, and no_fix_yet outcomes"
else
  fail "debug.md Step 5 missing fixed_now/already_fixed/no_fix_yet mapping"
fi

if grep -qF 'set-status .vbw-planning complete' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md already_fixed path reuses completed-state workflow via set-status complete"
else
  fail "debug.md already_fixed path missing set-status complete workflow"
fi

DEBUG_HINT_LINE="$(awk '/^argument-hint:/{print; exit}' "$DEBUG_CMD" 2>/dev/null || true)"
if contains_literal "$DEBUG_HINT_LINE" 'bug description' \
  && contains_literal "$DEBUG_HINT_LINE" 'todo number' \
  && contains_literal "$DEBUG_HINT_LINE" '--resume' \
  && contains_literal "$DEBUG_HINT_LINE" '--session ID'; then
  pass "debug.md argument-hint advertises bug text, todo number, --resume, and --session"
else
  fail "debug.md argument-hint missing one or more supported entry points"
fi

DEBUG_USAGE_LINES="$(grep -F 'Usage:' "$DEBUG_CMD" 2>/dev/null || true)"
DEBUG_USAGE_COUNT=$(grep -c 'Usage:' <<<"$DEBUG_USAGE_LINES" || true)
if [ "$DEBUG_USAGE_COUNT" -ge 2 ] \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug <todo-number>' \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug --resume' \
  && contains_literal "$DEBUG_USAGE_LINES" '/vbw:debug --session <id>' \
  && contains_literal "$DEBUG_USAGE_LINES" '[--competing|--parallel|--serial]'; then
  pass "debug.md keeps both expanded Usage strings with resume/session and ambiguity flags"
else
  fail "debug.md missing expanded Usage strings with resume/session and ambiguity flags"
fi

if grep -Fq 'No active debug session to resume. Use `/vbw:debug --session <id>` to open a specific session' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md resume stop message advertises session override and new-session entry points"
else
  fail "debug.md resume stop message still uses freeform-only guidance"
fi

if grep -Fq 'This debug session is already complete. Use `/vbw:debug --session <id>` to inspect another session' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md complete-session stop message advertises session override and new-session entry points"
else
  fail "debug.md complete-session stop message still uses freeform-only guidance"
fi

if grep -Fq 'Use `session_status` for lifecycle checks after `eval`, do not rely on a bare `status` variable.' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md names the safe debug-session helper contract explicitly"
else
  fail "debug.md missing explicit session_status helper contract"
fi

if grep -Fq 'session_status=qa_pending' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=qa_failed' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=uat_pending' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=uat_failed' "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq 'session_status=complete' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md lifecycle routing keys off session_status for metadata-read helpers"
else
  fail "debug.md lifecycle routing not fully aligned to session_status contract"
fi

debug_complete_matches=$(grep -nF 'bash "{plugin-root}/scripts/debug-session-state.sh" set-status .vbw-planning complete' "$DEBUG_CMD" 2>/dev/null || true)
debug_pg_matches=$(grep -nF 'PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"' "$DEBUG_CMD" 2>/dev/null || true)
debug_commit_matches=$(grep -nF 'bash "$PG_SCRIPT" commit-boundary "complete debug session" .vbw-planning/config.json' "$DEBUG_CMD" 2>/dev/null || true)
debug_warning_matches=$(grep -nF '⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit.' "$DEBUG_CMD" 2>/dev/null || true)

debug_complete_first=$(printf '%s\n' "$debug_complete_matches" | sed -n '1s/:.*//p')
debug_complete_second=$(printf '%s\n' "$debug_complete_matches" | sed -n '2s/:.*//p')
debug_complete_third=$(printf '%s\n' "$debug_complete_matches" | sed -n '3s/:.*//p')

debug_pg_first=$(printf '%s\n' "$debug_pg_matches" | sed -n '1s/:.*//p')
debug_pg_second=$(printf '%s\n' "$debug_pg_matches" | sed -n '2s/:.*//p')
debug_pg_third=$(printf '%s\n' "$debug_pg_matches" | sed -n '3s/:.*//p')

debug_commit_first=$(printf '%s\n' "$debug_commit_matches" | sed -n '1s/:.*//p')
debug_commit_second=$(printf '%s\n' "$debug_commit_matches" | sed -n '2s/:.*//p')
debug_commit_third=$(printf '%s\n' "$debug_commit_matches" | sed -n '3s/:.*//p')

debug_warning_first=$(printf '%s\n' "$debug_warning_matches" | sed -n '1s/:.*//p')
debug_warning_second=$(printf '%s\n' "$debug_warning_matches" | sed -n '2s/:.*//p')
debug_warning_third=$(printf '%s\n' "$debug_warning_matches" | sed -n '3s/:.*//p')

if [ -n "$debug_complete_first" ] && [ -n "$debug_complete_second" ] && [ -z "$debug_complete_third" ] && \
   [ -n "$debug_pg_first" ] && [ -n "$debug_pg_second" ] && [ -z "$debug_pg_third" ] && \
   [ -n "$debug_commit_first" ] && [ -n "$debug_commit_second" ] && [ -z "$debug_commit_third" ] && \
   [ -n "$debug_warning_first" ] && [ -n "$debug_warning_second" ] && [ -z "$debug_warning_third" ] && \
   [ "$debug_complete_first" -lt "$debug_pg_first" ] && [ "$debug_pg_first" -lt "$debug_commit_first" ] && [ "$debug_commit_first" -lt "$debug_warning_first" ] && \
   [ "$debug_complete_second" -lt "$debug_pg_second" ] && [ "$debug_pg_second" -lt "$debug_commit_second" ] && [ "$debug_commit_second" -lt "$debug_warning_second" ]; then
  pass "debug.md completion paths run planning boundary commit immediately after set-status complete"
else
  fail "debug.md completion paths missing ordered planning boundary commit after set-status complete"
fi

if grep -Fq "already_fixed = 'Already fixed before this investigation, no new fix commit was required." "$DEBUG_CMD" 2>/dev/null \
  && grep -Fq "already_fixed = \"Already fixed on the current branch, no new fix commit was required. this completion path may still create a planning-artifact commit when planning_tracking=commit" "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md already_fixed wording distinguishes fix commits from planning-artifact commits"
else
  fail "debug.md already_fixed wording still blurs fix commits and planning-artifact commits"
fi

if grep -Fq "already_fixed = 'Already fixed before this investigation, no new commit created.'" "$DEBUG_CMD" 2>/dev/null \
  || grep -Fq "already_fixed = \"Already fixed on the current branch, no new commit created\"" "$DEBUG_CMD" 2>/dev/null; then
  fail "debug.md still contains stale already_fixed wording that claims no commit was created"
else
  pass "debug.md removes stale already_fixed no-new-commit wording"
fi

if grep -qF 'For `no_fix_yet`' "$DEBUG_CMD" 2>/dev/null && \
   grep -qF '`investigating`' "$DEBUG_CMD" 2>/dev/null; then
  pass "debug.md no_fix_yet path keeps the session investigating"
else
  fail "debug.md no_fix_yet path missing investigating-state guidance"
fi

QA_CMD="$ROOT/commands/qa.md"
if grep -q "debug_session_qa" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug_session_qa section"
else
  fail "qa.md missing debug_session_qa section"
fi

if grep -Fq 'use `session_status` for lifecycle checks after `eval`.' "$QA_CMD" 2>/dev/null \
  && grep -Fq 'use `session_status` for routing after `eval`.' "$QA_CMD" 2>/dev/null \
  && grep -Fq 'exported `session_status` is `qa_pending` or `qa_failed`' "$QA_CMD" 2>/dev/null; then
  pass "qa.md debug-session override uses the explicit session_status helper contract"
else
  fail "qa.md debug-session override missing explicit session_status helper contract"
fi

VERIFY_CMD="$ROOT/commands/verify.md"
if grep -q "debug_session_uat" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug_session_uat section"
else
  fail "verify.md missing debug_session_uat section"
fi

if grep -Fq 'use `session_status` for lifecycle checks after `eval`.' "$VERIFY_CMD" 2>/dev/null \
  && grep -Fq 'use `session_status` for routing after `eval`.' "$VERIFY_CMD" 2>/dev/null \
  && grep -Fq 'exported `session_status` is `uat_pending` or `uat_failed`' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md debug-session override uses the explicit session_status helper contract"
else
  fail "verify.md debug-session override missing explicit session_status helper contract"
fi


DEBUGGER_AGENT="$ROOT/templates/agent-roles/debugger.md.tpl"
if grep -q "Standalone Debug Session" "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "templates/agent-roles/debugger.md.tpl has standalone debug session section"
else
  fail "templates/agent-roles/debugger.md.tpl missing standalone debug session section"
fi

DEBUGGER_PROTOCOL_BLOCK="$(sed -n '/## Investigation Protocol/,/^## /p' "$DEBUGGER_AGENT" 2>/dev/null || true)"
DEBUGGER_TEAMMATE_BLOCK="$(sed -n '/## Teammate Mode/,/^## /p' "$DEBUGGER_AGENT" 2>/dev/null || true)"

if contains_literal "$DEBUGGER_PROTOCOL_BLOCK" 'Historical `accepted-process-exception` or backlog/UAT-deviation metadata is not an `already_fixed` signal.' \
  && contains_literal "$DEBUGGER_PROTOCOL_BLOCK" 'Use `already_fixed` only with fresh current evidence.' \
  && contains_literal "$DEBUGGER_PROTOCOL_BLOCK" 'Report an explicit blocker instead of claiming completion when remediation is impossible.'; then
  pass "templates/agent-roles/debugger.md.tpl Investigation Protocol rejects historical accepted metadata as already_fixed evidence"
else
  fail "templates/agent-roles/debugger.md.tpl Investigation Protocol missing accepted-exception already_fixed invariant"
fi

if grep -Fq 'When `/vbw:debug` Path A spawns you as a hypothesis investigator' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq 'overrides any conflicting implementation language' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "templates/agent-roles/debugger.md.tpl teammate mode explicitly defers to /vbw:debug orchestration"
else
  fail "templates/agent-roles/debugger.md.tpl teammate mode missing /vbw:debug orchestration override"
fi

if grep -Fq 'Teammate mode ends at diagnosis plus `debugger_report`.' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq '`resolution_observation` does NOT grant fix authority.' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "templates/agent-roles/debugger.md.tpl teammate mode ends at diagnosis and keeps resolution observations analysis-only"
else
  fail "templates/agent-roles/debugger.md.tpl teammate mode missing diagnosis-only boundary or analysis-only resolution language"
fi

if grep -Fq 'Historical `accepted-process-exception` or backlog/UAT-deviation metadata alone is not fresh evidence for `already_fixed`.' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "templates/agent-roles/debugger.md.tpl teammate mode rejects accepted metadata alone as already_fixed evidence"
else
  fail "templates/agent-roles/debugger.md.tpl teammate mode missing accepted-metadata already_fixed guard"
fi

if grep -Fq '`/vbw:debug` owns synthesis, session status, teardown, and any later implementation handoff.' <<< "$DEBUGGER_TEAMMATE_BLOCK" \
  && grep -Fq 'That implementation owner is not this teammate.' <<< "$DEBUGGER_TEAMMATE_BLOCK"; then
  pass "templates/agent-roles/debugger.md.tpl teammate mode reserves implementation ownership for a fresh post-synthesis owner"
else
  fail "templates/agent-roles/debugger.md.tpl teammate mode missing fresh post-synthesis ownership boundary"
fi

QA_AGENT="$ROOT/templates/agent-roles/qa.md.tpl"
if grep -q "Debug Session QA" "$QA_AGENT" 2>/dev/null; then
  pass "templates/agent-roles/qa.md.tpl has debug session QA section"
else
  fail "templates/agent-roles/qa.md.tpl missing debug session QA section"
fi


if grep -q "Debug session override" "$QA_CMD" 2>/dev/null; then
  pass "qa.md has debug session override in Guard"
else
  fail "qa.md missing debug session override in Guard"
fi

if grep -q "Debug session override" "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md has debug session override in Guard"
else
  fail "verify.md missing debug session override in Guard"
fi


if grep -q '"result"' "$VERIFY_CMD" 2>/dev/null && grep -q 'pass|issues_found' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md UAT template includes result field"
else
  fail "verify.md UAT template missing result field"
fi


if grep -q 'qa_pending' "$DEBUGGER_AGENT" 2>/dev/null && ! grep -q 'fix_applied' "$DEBUGGER_AGENT" 2>/dev/null; then
  pass "templates/agent-roles/debugger.md.tpl uses qa_pending (not fix_applied) for post-fix status"
else
  fail "templates/agent-roles/debugger.md.tpl should use qa_pending for post-fix status, not fix_applied"
fi


TEMPLATE="$ROOT/templates/DEBUG-SESSION.md"
if grep -q '## Remediation History' "$TEMPLATE" 2>/dev/null; then
  pass "DEBUG-SESSION.md template has Remediation History section"
else
  fail "DEBUG-SESSION.md template missing Remediation History section"
fi


if grep -q 'phase_count=0' "$QA_CMD" 2>/dev/null || grep -q 'phase_count' "$QA_CMD" 2>/dev/null; then
  pass "qa.md debug session guard checks phase_count"
else
  fail "qa.md debug session guard does not check phase_count"
fi

if grep -q 'phase_count=0' "$VERIFY_CMD" 2>/dev/null || grep -q 'phase_count' "$VERIFY_CMD" 2>/dev/null; then
  pass "verify.md debug session guard checks phase_count"
else
  fail "verify.md debug session guard does not check phase_count"
fi


if grep -q 'skip' "$WRITER" 2>/dev/null && grep -q 'user_response' "$WRITER" 2>/dev/null; then
  pass "write-debug-session.sh handles skip result and user_response"
else
  fail "write-debug-session.sh missing skip or user_response handling"
fi


if [ -f "$ROOT/tests/debug-session-lifecycle.bats" ]; then
  pass "debug-session-lifecycle.bats end-to-end test exists"
else
  fail "debug-session-lifecycle.bats missing"
fi


if grep -q 'phase_count.*0.*debugging' "$ROOT/scripts/suggest-next.sh" 2>/dev/null || \
   grep -q '_qa_debug_handled' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh qa branch has standalone debug-session detection"
else
  fail "suggest-next.sh qa branch missing standalone debug-session detection"
fi


if grep -q 'phase_count=0.*--session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md debug-session routing decision supports --session flag"
else
  fail "qa.md debug-session routing decision missing --session flag support"
fi


if grep -q 'phase_count=0.*--session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md debug-session routing decision supports --session flag"
else
  fail "verify.md debug-session routing decision missing --session flag support"
fi


if grep -q 'suggest-next qa.*pass.*debug session' "$ROOT/tests/suggest-next-debug-session.bats" 2>/dev/null; then
  pass "suggest-next-debug-session.bats covers qa pass with debug session"
else
  fail "suggest-next-debug-session.bats missing qa pass with debug session test"
fi


if grep -q '\-\-session' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md guard mentions --session flag"
else
  fail "qa.md guard missing --session flag"
fi

if grep -q '\-\-session' "$ROOT/commands/verify.md" 2>/dev/null; then
  pass "verify.md guard mentions --session flag"
else
  fail "verify.md guard missing --session flag"
fi


if grep -q 'vbw:debug --resume' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh routes debug sessions to /vbw:debug --resume"
else
  fail "suggest-next.sh missing /vbw:debug --resume routing for debug sessions"
fi


if grep -q 'phase_count.*0.*debugging' "$ROOT/scripts/suggest-next.sh" 2>/dev/null; then
  pass "suggest-next.sh qa/verify debug handlers guard on phase_count=0"
else
  fail "suggest-next.sh qa/verify debug handlers not guarded by phase_count=0"
fi


if ! grep -q "sed -i ''" "$ROOT/scripts/debug-session-state.sh" 2>/dev/null; then
  pass "debug-session-state.sh uses portable sed (no BSD-only -i '')"
else
  fail "debug-session-state.sh uses non-portable sed -i ''"
fi

if grep -q 'in_fm' "$ROOT/scripts/debug-session-state.sh" 2>/dev/null; then
  pass "debug-session-state.sh uses awk-based frontmatter-scoped field updates"
else
  fail "debug-session-state.sh missing awk-based frontmatter scoping"
fi

if ! grep -q "sed -i ''" "$ROOT/scripts/write-debug-session.sh" 2>/dev/null; then
  pass "write-debug-session.sh uses portable sed (no BSD-only -i '')"
else
  fail "write-debug-session.sh uses non-portable sed -i ''"
fi

if grep -q 'in_fm' "$ROOT/scripts/write-debug-session.sh" 2>/dev/null; then
  pass "write-debug-session.sh uses awk-based frontmatter-scoped field updates"
else
  fail "write-debug-session.sh missing awk-based frontmatter scoping"
fi


if grep -q 'debug_inline_qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md has inline QA section (debug_inline_qa)"
else
  fail "debug.md missing inline QA section (debug_inline_qa)"
fi

if grep -q 'debug_inline_uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md has inline UAT section (debug_inline_uat)"
else
  fail "debug.md missing inline UAT section (debug_inline_uat)"
fi

if [ -n "$DEBUG_INLINE_UAT_BLOCK" ]; then
  pass "debug.md inline UAT block extracted for scoped contract checks"
else
  fail "debug.md inline UAT block missing; scoped contract checks cannot run"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'CHECKPOINT display plus the `AskUserQuestion` tool_use MUST be emitted in the same assistant response'; then
  pass "debug.md inline UAT requires checkpoint display and AskUserQuestion in the same assistant response"
else
  fail "debug.md inline UAT missing same-response checkpoint + AskUserQuestion contract"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'one atomic presentation step' \
  && contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'never split them across turns'; then
  pass "debug.md inline UAT treats checkpoint display and tool call as atomic and unsplittable"
else
  fail "debug.md inline UAT missing atomic unsplittable presentation contract"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'A text-only checkpoint is invalid'; then
  pass "debug.md inline UAT invalidates text-only checkpoints"
else
  fail "debug.md inline UAT missing text-only checkpoint invalidation"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'Do NOT end the turn after displaying checkpoint text' \
  && contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'only valid pause is waiting for the blocking `AskUserQuestion` response'; then
  pass "debug.md inline UAT forbids ending the turn after checkpoint text"
else
  fail "debug.md inline UAT missing no-end-turn/blocking-tool boundary"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'Do not process an answer, advance to later checkpoints, persist UAT state, or finalize the session until that tool response is available'; then
  pass "debug.md inline UAT blocks answer processing and persistence until tool response"
else
  fail "debug.md inline UAT missing blocking response-before-advance contract"
fi

if contains_literal "$(awk '
  BEGIN { delim=0 }
  /^---$/ {
    delim++
    if (delim == 2) exit
    next
  }
  delim == 1 { print }
' "$ROOT/commands/debug.md" 2>/dev/null || true)" 'AskUserQuestion'; then
  pass "debug.md frontmatter includes AskUserQuestion tool"
else
  fail "debug.md frontmatter missing AskUserQuestion tool"
fi

if grep -Fq 'question: "Scenario: {scenario description}\n\nExpected: {expected result}\n\nDoes the behavior match this checkpoint?"' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md inline UAT modal question includes Scenario and Expected"
else
  fail "debug.md inline UAT modal question missing Scenario and Expected"
fi

if contains_literal "$DEBUG_INLINE_UAT_BLOCK" 'question: "Scenario: {scenario description}\n\nExpected: {expected result}\n\nDoes the behavior match this checkpoint?"'; then
  pass "debug.md inline UAT scoped block keeps Scenario and Expected in modal question"
else
  fail "debug.md inline UAT scoped block missing Scenario and Expected modal question"
fi

if grep -Fq 'question: "Expected: {expected result}"' "$ROOT/commands/debug.md" 2>/dev/null; then
  fail "debug.md inline UAT modal still uses expected-only question"
else
  pass "debug.md inline UAT modal avoids expected-only question"
fi

if grep -q '\-\-session.*Run UAT on the debug fix' "$ROOT/commands/qa.md" 2>/dev/null; then
  pass "qa.md next-step for PASS includes --session"
else
  fail "qa.md next-step for PASS missing --session flag"
fi

if grep -q 'qa_pending.*debug_inline_qa\|fix_applied.*debug_inline_qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume routing for qa_pending/fix_applied enters inline QA"
else
  fail "debug.md resume routing for qa_pending/fix_applied missing inline QA entry"
fi

if grep -q 'session_status=uat_pending.*debug_inline_uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume routing for uat_pending enters inline UAT"
else
  fail "debug.md resume routing for uat_pending missing inline UAT entry"
fi


if grep -q 'Phase-Scoped QA' "$ROOT/templates/agent-roles/qa.md.tpl" 2>/dev/null; then
  pass "templates/agent-roles/qa.md.tpl persistence section scoped to phase QA"
else
  fail "templates/agent-roles/qa.md.tpl persistence section not scoped to phase QA"
fi

if grep -q 'Debug-session QA exception' "$ROOT/templates/agent-roles/qa.md.tpl" 2>/dev/null || \
   grep -q 'debug-session QA.*do NOT use.*write-verification' "$ROOT/templates/agent-roles/qa.md.tpl" 2>/dev/null; then
  pass "templates/agent-roles/qa.md.tpl explicitly exempts debug-session QA from write-verification.sh"
else
  fail "templates/agent-roles/qa.md.tpl missing debug-session QA exception from write-verification.sh"
fi


if grep -q 'FAILURE_CONTEXT.*compile-debug-session-context' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume captures FAILURE_CONTEXT from compile-debug-session-context.sh"
else
  fail "debug.md resume missing FAILURE_CONTEXT capture from compile-debug-session-context.sh"
fi

if grep -q 'Previous QA failed.*FAILURE_CONTEXT' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume injects QA failure context into debugger prompt"
else
  fail "debug.md resume missing QA failure context injection"
fi

if grep -q 'Previous UAT failed.*FAILURE_CONTEXT' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md resume injects UAT failure context into debugger prompt"
else
  fail "debug.md resume missing UAT failure context injection"
fi


if grep -q 'compile-debug-session-context\.sh.*qa' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md qa_failed resume passes 'qa' mode to compile-debug-session-context.sh"
else
  fail "debug.md qa_failed resume missing 'qa' mode argument"
fi

if grep -q 'compile-debug-session-context\.sh.*uat' "$ROOT/commands/debug.md" 2>/dev/null; then
  pass "debug.md uat_failed resume passes 'uat' mode to compile-debug-session-context.sh"
else
  fail "debug.md uat_failed resume missing 'uat' mode argument"
fi


if grep -q 'ACTIVE_DIR=' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh defines ACTIVE_DIR"
else
  fail "debug-session-state.sh missing ACTIVE_DIR definition"
fi

if grep -q 'COMPLETED_DIR=' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh defines COMPLETED_DIR"
else
  fail "debug-session-state.sh missing COMPLETED_DIR definition"
fi

if grep -q 'migrate_legacy_session' "$STATE_SCRIPT" 2>/dev/null; then
  pass "debug-session-state.sh has migrate_legacy_session function"
else
  fail "debug-session-state.sh missing migrate_legacy_session function"
fi

_set_status_block="$(awk '/set-status\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)"
if matches_ere "$_set_status_block" '"\$STATUS" = "complete"' && \
   matches_ere "$_set_status_block" 'safe_move_session.*\$COMPLETED_DIR'; then
  pass "debug-session-state.sh set-status branch moves complete sessions to COMPLETED_DIR"
else
  fail "debug-session-state.sh set-status branch does not move complete sessions to COMPLETED_DIR"
fi

_list_block="$(awk '/list\)/,/;;/' "$STATE_SCRIPT" 2>/dev/null || true)"
if contains_literal "$_list_block" '|active' && \
   contains_literal "$_list_block" '|completed'; then
  pass "debug-session-state.sh list outputs both active and completed location fields"
else
  fail "debug-session-state.sh list missing location field in output (must include both |active and |completed)"
fi

if grep -q 'safe_move_session()' "$STATE_SCRIPT" 2>/dev/null && \
   contains_literal "$(awk '/safe_move_session\(\)/,/^}/' "$STATE_SCRIPT" 2>/dev/null || true)" 'return 1'; then
  pass "debug-session-state.sh has safe_move_session helper with collision guard"
else
  fail "debug-session-state.sh missing safe_move_session helper or collision guard"
fi


echo ""
echo "=== Debug Session Contract: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
