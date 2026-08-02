---
phase: 6
plan: 02
title: phase-detect.sh five-library split plus scoped partial-summary drift fix
status: complete
completed: 2026-08-02
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 577789a4
  - f2e75831
  - aeef6a2b
  - 11d3904c
deviations:
  - "Intentional behavior change: a terminal partial or failed phase summary with a passing current QA remediation round now satisfies execution instead of emitting next_phase_state=needs_execute."
pre_existing_issues: []
ac_results:
  - criterion: "Raw stdout order, keys, and delimiters are byte-identical to pre-split output for every baseline fixture, except the intentional ref:0f9b3be3 change."
    verdict: "pass"
    evidence: "tests/phase-detect-output-contract.bats"
  - criterion: "The transactional EXIT trap survives the split."
    verdict: "pass"
    evidence: "tests/phase-detect.bats transactional late-failure and source-failure cases"
  - criterion: "count_complete_summaries in scripts/summary-utils.sh is not modified."
    verdict: "pass"
    evidence: "testing/verify-summary-utils-contract.sh"
  - criterion: "Only the current QA remediation round may satisfy a phase."
    verdict: "pass"
    evidence: "tests/phase-detect.bats earlier-round PASS regression"
  - criterion: "Strict counts stay unchanged in next_phase_summaries and all other emitted count fields."
    verdict: "pass"
    evidence: "phase-05-remediated.txt keeps next_phase_summaries=0"
  - criterion: "The ref:0f9b3be3 behavior change is recorded as an intentional deviation."
    verdict: "pass"
    evidence: "06-02-SUMMARY.md deviations"
  - criterion: "Global assignments keep their scope."
    verdict: "pass"
    evidence: "scripts/lib/phase-detect-active-routing.sh and scripts/lib/phase-detect-qa-routing.sh"
  - criterion: "scripts/lib/phase-detect-support.sh provides satisfaction predicates."
    verdict: "pass"
    evidence: "aeef6a2b"
  - criterion: "scripts/lib/phase-detect-active-routing.sh provides active-phase routing."
    verdict: "pass"
    evidence: "f2e75831"
  - criterion: "scripts/lib/phase-detect-qa-routing.sh provides QA routing."
    verdict: "pass"
    evidence: "f2e75831"
  - criterion: "scripts/lib/phase-detect-milestone-recovery.sh provides milestone recovery and extraction."
    verdict: "pass"
    evidence: "f2e75831"
  - criterion: "scripts/lib/phase-detect-environment-output.sh provides late environment output."
    verdict: "pass"
    evidence: "f2e75831"
  - criterion: "tests/fixtures/phase-detect-output contains pre-split golden snapshots."
    verdict: "pass"
    evidence: "577789a4"
  - criterion: "tests/phase-detect-output-contract.bats covers routing output."
    verdict: "pass"
    evidence: "11d3904c"
  - criterion: "scripts/phase-detect.sh sources all five libraries at ordered boundaries."
    verdict: "pass"
    evidence: "f2e75831"
  - criterion: "phase_execution_is_satisfied reuses terminal summary and verification semantics."
    verdict: "pass"
    evidence: "aeef6a2b"
  - criterion: "The output-contract suite compares live runs with golden snapshots."
    verdict: "pass"
    evidence: "11d3904c"
---

`phase-detect.sh` is now a 236-line transactional serializer backed by five focused libraries, golden output snapshots, and current-round QA remediation satisfaction.

## What Was Built

- Captured eight deterministic pre-split stdout snapshots in isolated Git sandboxes.
- Extracted support, active routing, QA routing, milestone recovery, and environment output into five sourced libraries.
- Preserved output order, delimiters, global state, and transactional failure behavior.
- Added current-round QA remediation satisfaction at the six active phase predicates.
- Added two behavior regressions and nine output-contract BATS cases.
- Grounding: d02-states-and-semantic-characterization.md and d05-formal-treatment-of-small-examples.md (postcondition stated, unsatisfied-guard invariant and remaining-guard variant named)

## Files Modified

### Detection Runtime

- `scripts/phase-detect.sh`: retained the ordered serializer and guarded source boundaries.
- `scripts/lib/phase-detect-support.sh`: moved shared helpers and added satisfaction predicates.
- `scripts/lib/phase-detect-active-routing.sh`: moved active phase and UAT routing.

### QA and Output

- `scripts/lib/phase-detect-qa-routing.sh`: moved QA remediation and attention routing.
- `scripts/lib/phase-detect-milestone-recovery.sh`: moved milestone scanning and issue extraction.
- `scripts/lib/phase-detect-environment-output.sh`: moved config, codebase, brownfield, and execution-state output.

### Tests

- `tests/phase-detect.bats`: updated failure injection and added regression coverage.
- `tests/phase-detect-output-contract.bats`: added byte-level output contract coverage.
- `tests/fixtures/phase-detect-output/`: added the fixture builder and eight golden snapshots.

## Deviations

The phase-05-shaped fixture intentionally changes from `next_phase_state=needs_execute` to `next_phase_state=all_done`. Its strict summary count remains `next_phase_summaries=0`. This is the scoped ref:0f9b3be3 deviation approved in `06-CONTEXT.md`. No other output fixture changed.
