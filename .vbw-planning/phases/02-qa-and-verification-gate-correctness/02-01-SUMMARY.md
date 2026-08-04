---
phase: 2
plan: 1
title: Scope QA freshness working-tree check to the phase under verification
status: partial
completed: 2026-08-04
tasks_completed: 3
tasks_total: 4
commit_hashes:
  - 47270310b805e3ae097491cf287fccd13c93175d
deviations:
  - "The archived phase-05 live phase_execution_is_satisfied check remained unsatisfied because qa_gate_routing_for_phase returned REMEDIATION_REQUIRED before freshness assessment. Direct scoped freshness validation passed under clean and unrelated-dirt conditions."
pre_existing_issues: []
ac_results:
  - criterion: "Unrelated dirt never yields reason=working_tree_changed for a clean phase"
    verdict: pass
    evidence: "tests/phase-detect.bats: qa_status ignores unrelated tracked and untracked working-tree dirt"
  - criterion: "Dirt in the phase's own recorded files still yields working_tree_changed"
    verdict: pass
    evidence: "tests/phase-detect.bats: qa_status is pending when PASS verification has uncommitted product changes"
  - criterion: "phase_execution_is_satisfied is satisfied for the archived phase-05 fixture despite unrelated dirt"
    verdict: partial
    evidence: "Archived fixture output: NOT_SATISFIED plans=1 complete=0 reason=none, qa_gate_routing_for_phase=REMEDIATION_REQUIRED, direct verification_is_stale scoped check remained fresh"
---

Scoped verification freshness to files recorded by the phase plan and summary while preserving repo-wide behavior for unscoped or metadata-free callers.

## What Was Built

- Added phase path extraction from files_modified and files_touched frontmatter.
- Passed phase scoping through phase_verification_assessment into verification_is_stale.
- Added regression coverage for unrelated tracked and untracked dirt.

## Files Modified

- `scripts/verification-freshness.sh` -- scoped git status pathspecs to recorded phase files.
- `scripts/lib/phase-detect-support.sh` -- passed phase directories into freshness checks.
- `tests/phase-detect.bats` -- covered false-positive and preserved true-positive freshness behavior.

## Verification

- `bash -n scripts/verification-freshness.sh scripts/lib/phase-detect-support.sh` passed.
- `shellcheck -S warning scripts/verification-freshness.sh scripts/lib/phase-detect-support.sh` passed.
- `bats tests/phase-detect.bats` passed, 149 tests.
- Scratch repository scoped pathspec check passed for unrelated and phase-owned dirt.
- Archived phase-05 live check exposed the existing QA gate result as `REMEDIATION_REQUIRED`, no additional code change was made.

## Deviations

The archived phase-05 fixture records a pre-archive files_modified path, so qa-result-gate.sh entered the plan-amendment evidence branch with no matching recorded path and emitted a bare REMEDIATION_REQUIRED. Commit a3125ff1 bypasses that stale-path check for terminal done rounds and adds a diagnostic for future nonterminal failures.
