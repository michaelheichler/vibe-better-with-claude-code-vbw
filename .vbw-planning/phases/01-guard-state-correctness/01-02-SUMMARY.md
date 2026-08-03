---
phase: 1
plan: 2
title: bash-guard shell-token-aware parsing, kill both false-positive classes
status: complete
completed: 2026-08-03
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 6a2660b
  - c227be7
  - 90b3e32
  - 0cccec3
deviations:
  - "The 01-02 must-have requiring tests/hooks-bash-classifier.bats to remain unmodified was violated by ece82fc3. The commit migrated fixtures to live PIDs required by the live-PID contract. The suite still passes 104/104, and this round re-reviewed the diff with assertions confirmed intact."
pre_existing_issues: []
ac_results:
  - criterion: "Destructive tokens inside quoted or piped data text never trigger a block, and only command-position tokens do"
    verdict: pass
    evidence: "tests/qa-bash-guard.bats, commit c227be7"
  - criterion: "2>/dev/null and fd duplication on read-only commands are not classified as writes"
    verdict: pass
    evidence: "tests/qa-bash-guard.bats, commit 90b3e32"
  - criterion: "tests/hooks-bash-classifier.bats passes unmodified and retains the required literal pattern checks"
    verdict: pass
    evidence: "bats tests/hooks-bash-classifier.bats, 104 tests passed after ece82fc fixture migration"
  - criterion: "Actual mutation commands and real redirects remain blocked for read-only roles"
    verdict: pass
    evidence: "tests/qa-bash-guard.bats, commits c227be7 and 90b3e32"
  - criterion: "scripts/bash-guard.sh contains token-aware routing and delegates role normalization through the shared library"
    verdict: pass
    evidence: "scripts/bash-guard.sh, commits c227be7 and 0cccec3"
  - criterion: "tests/qa-bash-guard.bats adds regression coverage for both false-positive classes"
    verdict: pass
    evidence: "tests/qa-bash-guard.bats, commit 6a2660b"
---

bash-guard now classifies shell-visible command tokens and redirect targets instead of raw evidence text.

## What Was Built

- Added regression coverage for quoted and piped mutation evidence, descriptor redirects, destructive pattern evidence, and mutation guard rails.
- Routed filesystem mutation and destructive-pattern checks through quote masking and command-segment parsing.
- Classified `/dev/null` and `&N` redirects as non-writes while retaining blocks for real output paths.
- Delegated role normalization to `vbw_active_agent_normalize_role` in the shared active-agent state library.

## Files Modified

- `scripts/bash-guard.sh`: token-aware mutation checks, redirect-target classification, and shared role normalization.
- `tests/qa-bash-guard.bats`: additive regression tests for both false-positive classes and guard rails.
- `.vbw-planning/phases/01-guard-state-correctness/01-02-SUMMARY.md`: execution summary.

## Deviations

- The 01-02 must-have requiring `tests/hooks-bash-classifier.bats` to remain unmodified was violated by `ece82fc3`. The commit migrated fixtures to live PIDs required by the live-PID contract. The suite passes 104/104. This round re-reviewed the diff and confirmed that assertions remain intact.

Bash syntax, ShellCheck, all 39 owned BATS tests, and the full 104-test classifier suite passed.
