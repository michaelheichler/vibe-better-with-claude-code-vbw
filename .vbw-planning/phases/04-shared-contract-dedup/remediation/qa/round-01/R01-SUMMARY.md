---
phase: 4
round: 1
title: Restore dropped retry sentence, fix README version drift, amend plans 04-01 and 04-02
type: remediation
status: complete
completed: 2026-08-02
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 6a6cc206c8944a1849d491749a950eb49e726641
  - 576c9755aca2684dae5c4005e2407fa33b5fe57e
  - 1254b8c7ccba431b2edd700c701fa644c5b18fe3
  - 87deae9207d94f8507fb7640b9e8e408fcb21675
files_modified:
  - references/handoff-schemas.md
  - README.md
  - .vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md
  - .vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md
deviations:
  - "Discipline-watcher blocked task 1 until five pre-existing punctuation findings in references/handoff-schemas.md were repaired. The edits preserve meaning but exceed the task's single-line scope."
  - "Discipline-watcher blocked task 2 until seven pre-existing readability findings in README.md were repaired. The edits split long prose and the table of contents but exceed the two-version-replacement scope."
  - "The first full suite run failed rtk-integration-contract because a watcher-required README sentence split changed a literal contract phrase. The wording was corrected before the final task commits, and the second full suite run passed."
known_issue_outcomes:
  - '{"test":"README accuracy table VERSION row","file":"README.md","error":"row states 1.38.6 but repo VERSION is 1.38.8 (all 4 version files in sync at 1.38.8), drift predates phase 04 and was out of plan scope","disposition":"resolved","rationale":"Task 2 updates both README version claims (accuracy table row at line 46 and the last-verified prose copy at line 51) to 1.38.8, matching VERSION, per the CLAUDE.md README claim-drift rule to fix table and prose copies together."}'
---

Round 01 restored the retry rule, resolved README version drift, and reconciled all plan-scope findings.

## Task 1: Restore orchestrator retry sentence in handoff-schemas.md

### What Was Built
- Restored the exact retry-on-rejection sentence in the conditional-refusal note.
- Preserved the shutdown schema behavior while repairing required punctuation findings.

### Files Modified
- `references/handoff-schemas.md`: restored the retry rule and repaired watcher findings.

### Known Issue Outcomes
None.

### Deviations
- Discipline-watcher required five punctuation repairs outside the planned one-line addition.
## Task 2: Update README version claims to 1.38.8

### What Was Built
- Updated both README version claims from 1.38.6 to 1.38.8.
- Preserved the literal RTK documentation contract while repairing required readability findings.

### Files Modified
- `README.md`: synchronized version claims and repaired watcher findings.

### Known Issue Outcomes
- `README accuracy table VERSION row` (`README.md`), `resolved`: both version claims now match `VERSION` 1.38.8.

### Deviations
- Discipline-watcher required readability edits outside the two planned replacements.
- The first full suite run exposed a changed RTK contract phrase. The wording was corrected, and the final suite passed.
## Task 3: Amend 04-01-PLAN.md for DEV-01 and DEV-02

### What Was Built
- Recorded the hook-driven scope exception from commit `235dae0a`.
- Permitted the test-required inline call-SendMessage marker while preserving MH-05.

### Files Modified
- `.vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md`: added the DEV-01 and DEV-02 amendments.

### Known Issue Outcomes
None.

### Deviations
No deviations.
## Task 4: Amend 04-02-PLAN.md for DEV-04

### What Was Built
- Added all five verifier files to `files_modified` and `files_touched`.
- Recorded why zero-tolerance verification required the scope expansion in commit `260d0560`.

### Files Modified
- `.vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md`: extended file scope and added the DEV-04 amendment.

### Known Issue Outcomes
None.

### Deviations
No deviations.