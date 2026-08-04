---
phase: 2
plan: 3
title: qa-result-gate correctness for known-issue dedup and doc-content fixes
status: complete
completed: 2026-08-04
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - f313968d8fb7c342ea295f964fa8636c836a49f9
deviations:
  - "Added the required classification guidance to references and the remediation plan template because doc-fix is a new contract value."
pre_existing_issues: []
ac_results:
  - criterion: "A deduped known_issues_input covering every (test, file) pair with one raw error variant passes coverage"
    verdict: pass
    evidence: "tests/qa-result-gate.bats, known-issue coverage accepts one raw error variant per test and file pair"
  - criterion: "A genuinely missing (test, file) pair still fails closed"
    verdict: pass
    evidence: "tests/qa-result-gate.bats, carried known-issue contract fails closed when known_issues_input covers only a subset of the backlog"
  - criterion: "A doc-content FAIL fixed by editing that same doc resolves without the process-exception workaround"
    verdict: pass
    evidence: "tests/qa-result-gate.bats, doc-fix classification accepts the named documentation path"
  - criterion: "Unrelated doc/README churn never satisfies code-fix evidence"
    verdict: pass
    evidence: "tests/qa-result-gate.bats, absolute documentation and repo-hygiene paths do not satisfy code-fix evidence"
  - criterion: "Known-issues and doc-fix gate scripts pass syntax and lint checks"
    verdict: pass
    evidence: "bash -n and shellcheck -S warning"
---

Known-issue coverage now tolerates deduped error wording per test and file pair, while documentation-content remediation uses explicit path-matched doc-fix evidence without weakening code-fix safeguards.

## What Was Built

- Pair-scoped known-issue coverage that accepts one raw error variant and rejects missing pairs or wrong errors.
- Explicit doc-fix classification and changed-path evidence matching for documentation product surfaces.
- Regression coverage for dedup tolerance, wrong-error rejection, named documentation fixes, and unrelated documentation edits.
- Updated remediation guidance and plan template for the doc-fix classification.

## Files Modified

- `scripts/lib/qa-result-gate-known-issues.sh` - matched required issues by test and file pair while preserving raw error validation.
- `scripts/lib/qa-result-gate-fail-classifications.sh` - accepted and extracted doc-fix classifications and paths.
- `scripts/lib/qa-result-gate-path-evidence.sh` - added named documentation path evidence matching.
- `scripts/qa-result-gate.sh` - routed validated doc-fix rounds to UAT and failed closed on missing evidence.
- `tests/qa-result-gate.bats` - added known-issue and doc-fix regressions.
- `references/execute-qa-result-gating.md` - documented doc-fix classification and verification behavior.
- `references/vibe-input-parsing.md` - documented doc-fix classification in remediation input guidance.
- `templates/REMEDIATION-PLAN.md` - added doc-fix frontmatter example.

## Deviations

The plan's file list did not name reference docs or the remediation template. They were updated because the plan explicitly requires classification-value documentation to remain synchronized.
