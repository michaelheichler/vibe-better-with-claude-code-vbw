---
phase: 7
plan: 05
title: Punctuation cleanup in scripts with behavior sensitive handling
status: complete
completed: 2026-08-03
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - fb3500b4
  - b90e8a3a
  - cc4ff97a
  - d1c450ae
  - e45c4a97
  - 789a9423
  - 8573a832
deviations:
  - "Task 3 bootstrap punctuation and oversized-function decomposition are resolved by commits 789a9423 and 8573a832."
  - "Task 1 todo lifecycle compatibility and oversized-function decomposition are resolved by commits 789a9423 and 8573a832."
  - "scripts/rtk-manager.sh and scripts/lib/rtk-manager-runtime.sh were left untouched because an unrelated uncommitted RTK extraction is in progress."
  - "The final lint command remains red on pre existing warnings and the unrelated RTK helper. Details are recorded in pre_existing_issues."
pre_existing_issues:
  - '{"test":"bash testing/run-lint.sh","file":"scripts/todo-lifecycle.sh","error":"SC2034: DETAILS_CACHE_JSON is unused at line 14."}'
  - '{"test":"bash testing/run-lint.sh","file":"scripts/vbw-statusline.sh","error":"SC1083: @{u} is parsed as a literal brace expression at line 417, plus SC2034 for AGENT_N at line 561."}'
  - '{"test":"bash testing/run-lint.sh","file":"scripts/session-start.sh","error":"SC2010: ls piped to grep at lines 510 and 511."}'
  - '{"test":"bash testing/run-lint.sh","file":"scripts/lib/rtk-manager-runtime.sh","error":"SC2148: sourced helper has no shebang or shell directive. The file is untracked external work."}'
  - '{"test":"bash testing/run-lint.sh","file":"scripts/lib/track-known-issues-parsers.sh","error":"SC2148: sourced helper has no shebang or shell directive."}'
  - '{"test":"bash scripts/verify-claude-bootstrap.sh","file":"scripts/bootstrap/bootstrap-claude.sh","error":"Three greenfield checks fail because Active Context, Code Intelligence, and Plugin Isolation headers are absent. Committed HEAD reproduces the same output."}'
  - '{"test":"bash testing/verify-askuserquestion-contract.sh","file":"commands/list-todos.md","error":"Two existing hint checks fail for remove N and delete N."}'
  - '{"test":"bash testing/verify-bash-scripts-contract.sh","file":"scripts/lib/rtk-manager-runtime.sh, scripts/lib/track-known-issues-parsers.sh, scripts/track-known-issues.sh","error":"Unmodified files retain the documented executable or shebang contract failures."}'
ac_results:
  - criterion: "Zero watcher banned dash characters remain in scripts and testing/verify-debug-session-contract.sh"
    verdict: "pass"
    evidence: "Final Perl scan and watcher checks after commit e45c4a97"
  - criterion: "Legacy dash parsing remains compatible"
    verdict: "pass"
    evidence: "Escaped legacy input checks for derive-milestone-slug.sh and rename-default-milestone.sh, plus focused BATS"
  - criterion: "Generated artifact grammar and coupled readers remain coherent"
    verdict: "pass"
    evidence: "bash testing/verify-debug-session-contract.sh reported 142 passed"
  - criterion: "Comment semicolon findings are absent while shell syntax remains valid"
    verdict: "pass"
    evidence: "Watcher checks across every script and bash or awk syntax checks"
  - criterion: "Every touched script has focused verification"
    verdict: "partial"
    evidence: "Focused BATS passed. The bootstrap verifier retains three pre existing failures and final run-lint retains pre existing failures."
---

ASCII punctuation cleanup covers the five plan tasks, with parser compatibility, artifact readers, and extracted lifecycle helpers preserved.

## What Was Built

- Preserved legacy dash input through escaped code points in milestone parsers, and preserved historical verification and todo text parsing.
- Updated debug session artifacts, readers, and contract assertions together, then cleaned script comments, messages, generated prompts, and deferred bootstrap punctuation.
- Extracted oversized todo snapshot, validation, suppression, cleanup, rewrite, and bootstrap migration functions into sourced libraries without changing focused behavior.
- Verified syntax, focused BATS, bootstrap verification, contract checks, and watcher scans. The bootstrap verifier retains its three documented greenfield header failures.
- Grounding: d03-wp-semantics-of-the-language and d04-termination-and-euclid, postconditions preserve validated snapshots, unique live-item matches, suppression signatures, and atomic state updates. Invariants cover accepted rows and staged state lines. Variants are unread input lines.

## Files Modified

- `scripts/`: compatibility parsers, artifact writers and readers, user output, generated prompts, punctuation cleanup, and extracted lifecycle helpers across commits `fb3500b4`, `b90e8a3a`, `cc4ff97a`, `d1c450ae`, `e45c4a97`, `789a9423`, and `8573a832`.
- `scripts/lib/todo-lifecycle-snapshot.sh`: extracted snapshot validation, persistence, selection, and live-item validation.
- `scripts/lib/todo-lifecycle-known-issues.sh`: extracted known-issue lookup, suppression, detail cleanup, and state rewrite.
- `scripts/bootstrap/lib/bootstrap-claude-migration.sh`: extracted Key Decisions migration and deprecated-section handling.
- `testing/verify-debug-session-contract.sh`: coupled debug session artifact assertions.
- `.vbw-planning/phases/07-terminology-and-punctuation/07-05-SUMMARY.md`: recorded completed status, commits, deviations, and acceptance evidence.
- `.vbw-planning/STATE.md`: marked Phase 7 complete after the summary status update.
