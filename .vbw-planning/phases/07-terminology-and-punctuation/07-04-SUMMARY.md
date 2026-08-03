---
phase: 7
plan: 04
title: Punctuation cleanup in testing/
status: complete
completed: 2026-08-03
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - a2601da
  - 3ad8404
  - 352e77b
  - 014fa79
deviations:
  - "None. The three excluded contract tests remained untouched."
pre_existing_issues: []
ac_results:
  - criterion: "Zero watcher-banned dash characters remain in the assigned testing files"
    verdict: "pass"
    evidence: "Full assigned-file Perl dash scan after commit 014fa79"
  - criterion: "Zero semicolon-splice matches remain in comment material of assigned shell files and anywhere in assigned Markdown files"
    verdict: "pass"
    evidence: "ADW punctuation checks and targeted comment rewrites in testing/README.md, testing/debug-path-a-isolation-smoke.md, and assigned shell files"
  - criterion: "Every touched verify script still passes after editing"
    verdict: "pass"
    evidence: "All touched contract scripts ran successfully, including the final config sync, UAT auto-continuation, and QA persistence checks"
  - criterion: "Shell semicolons that are real syntax are untouched"
    verdict: "pass"
    evidence: "Punctuation-only diffs and bash -n checks across all assigned shell files"
---

Removed banned dash punctuation and comment semicolon splices from the assigned testing harness files without changing test behavior.

## What Was Built

- Reworded 40 assigned testing files using ASCII punctuation and sentence-level rewrites.
- Preserved shell syntax and contract-test behavior, including coupled source needles.
- Verified all assigned files with the watcher punctuation checks and a directory-level dash scan.

## Files Modified

Task 1, filename convention:

- `testing/verify-plan-filename-convention.sh`: rewrote all test diagnostics and comments, commit `a2601da`.

Task 2, multi-occurrence checks:

- `testing/verify-exec-state-reconciliation.sh`, `testing/verify-lead-research-conditional.sh`, `testing/verify-report-diag-handoff.sh`, `testing/verify-report-template-contract.sh`: rewrote fixture comments, diagnostics, and contract messages, commit `3ad8404`.
- `testing/verify-qa-persistence-contract.sh`, `testing/verify-summary-status-contract.sh`, `testing/verify-summary-utils-contract.sh`, `testing/run-all.sh`: rewrote diagnostics and comments, commit `3ad8404`, with the final QA persistence comment in `014fa79`.

Task 3, bulk script headers:

- `testing/list-bats-files.sh`, `testing/measure-shard-weights.sh`, `testing/run-all-state-utils.sh`, `testing/run-bats-shard.sh`, `testing/run-lint.sh`: rewrote headers, commit `352e77b`.
- `testing/verify-agent-spawn-guard.sh`, `testing/verify-bash-scripts-contract.sh`, `testing/verify-ci-workflow-contract.sh`, `testing/verify-claude-md-staleness.sh`, `testing/verify-codex-agent-assets-contract.sh`, `testing/verify-dev-recovery-guidance.sh`, `testing/verify-hook-event-name.sh`, `testing/verify-human-only-uat-contract.sh`, `testing/verify-issue-157-migration-contract.sh`, `testing/verify-live-validation-policy.sh`, `testing/verify-lsp-first-policy.sh`, `testing/verify-lsp-setup.sh`, `testing/verify-no-inline-exec-spans.sh`, `testing/verify-permission-mode-contract.sh`, `testing/verify-pipefail-safety.sh`, `testing/verify-prefer-teams-canonicalization.sh`, `testing/verify-readme-config-reference.sh`, `testing/verify-research-storage-contract.sh`, `testing/verify-run-all-execution-contract.sh`, `testing/verify-statusline-429-backoff.sh`, `testing/verify-statusline-qa-lifecycle.sh`, `testing/verify-uat-remediation-orchestration.sh`: rewrote headers and diagnostics, commit `352e77b`.

Task 4, Markdown and semicolon cleanup:

- `testing/README.md`, `testing/debug-path-a-isolation-smoke.md`, `testing/verify-config-defaults-sync.sh`, `testing/verify-uat-autocontinue.sh`: rewrote Markdown prose, fenced commands, and comment lists, commit `014fa79`.
- `testing/verify-qa-persistence-contract.sh`: rewrote the remaining comment semicolon, commit `014fa79`.

All files above are part of the assigned set. The excluded contract tests were not modified.

## Deviations

None. The excluded `testing/verify-discussion-engine-contract.sh`, `testing/verify-github-fix-workflow-contract.sh`, and `testing/verify-debug-session-contract.sh` files were not modified.
