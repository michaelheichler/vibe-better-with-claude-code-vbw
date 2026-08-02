---
phase: 4
round: 2
plan: R02
title: Record process exceptions for hook-forced scope expansion in R01 commits
type: remediation
autonomous: true
effort_override: fast
skills_used: []
files_modified: [.vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md]
forbidden_commands: []
fail_classifications:
  - {id: "RDEV-01", type: "process-exception", rationale: "The out-of-scope hunks in references/handoff-schemas.md (commit 6a6cc206, four semicolon-to-period splits beyond the planned single-line restore) were forced by the discipline-watcher PostToolUse gate, which hard-blocks any write containing the flagged findings. Reverting them (code-fix) would reintroduce blocked findings and cannot be committed, and would undo verified-correct content. Plan-amendment is unavailable because the deviation arose from R01-PLAN task 1, a remediation-round task, and source_plan may only reference an original phase plan (04-01/04-02/04-03). Final state is verified correct (MH-01, ART-01 PASS) and the suite is green (MH-04 PASS). Non-fixable by policy, so process-exception."}
  - {id: "RDEV-02", type: "process-exception", rationale: "The out-of-scope hunks in README.md (commit 576c9755, sentence splits and TOC section headers beyond the two planned version replacements) were forced by the same discipline-watcher gate. Reverting would reintroduce blocked findings and undo verified-correct, meaning-preserving edits (MH-02, ART-02 PASS, no table counts changed, suite green per MH-04). Plan-amendment is unavailable because the deviation arose from R01-PLAN task 2, not an original phase plan. Non-fixable by policy, so process-exception."}
known_issues_input: []
known_issue_resolutions: []
must_haves:
  truths:
    - "RDEV-01 and RDEV-02 are documented as accepted process exceptions with commit-level evidence, without retroactive edits to R01-PLAN.md task text"
    - "references/handoff-schemas.md and README.md are left untouched by this round"
    - "bash testing/run-all.sh stays green"
  artifacts:
    - {path: ".vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md", provides: "forward-recorded process-exception evidence for RDEV-01 and RDEV-02", contains: "6a6cc206"}
  key_links:
    - {from: ".vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md", to: ".vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-01/R01-VERIFICATION.md", via: "cites the RDEV-01 and RDEV-02 FAIL rows it dispositions"}
---
<objective>
Close QA round 01's two remaining FAILs (RDEV-01, RDEV-02) by recording them as process exceptions.
Both are R01's own declared deviations.
The discipline-watcher hook gate forced meaning-preserving edits in references/handoff-schemas.md (commit 6a6cc206) and README.md (commit 576c9755).
Those edits exceeded the "make no other edits to the file" scope of R01-PLAN tasks 1 and 2.
The final file state is verified correct and the full suite is green, so no product change is needed or permitted.
This round only produces the exception record.
Do not edit R01-PLAN.md, references/handoff-schemas.md, or README.md.
</objective>
<context>
@.vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-01/R01-VERIFICATION.md
@.vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-01/R01-PLAN.md
</context>
<tasks>
<task type="auto">
  <name>Write SCOPE-EXCEPTIONS.md recording RDEV-01 and RDEV-02 as accepted process exceptions</name>
  <files>
    .vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md
  </files>
  <action>
Create .vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md with one section per exception.

RDEV-01 section must state the following facts. File: references/handoff-schemas.md, commit 6a6cc206. R01-PLAN task 1 scope was a single-line sentence restore with "Make no other edits to the file". Actual diff was 5 insertions and 5 deletions (the restored sentence plus four semicolon-to-period splits). The extra hunks were mandatory because the discipline-watcher PostToolUse gate hard-blocks writes containing the flagged findings. A revert would reintroduce blocked findings and cannot land. The edits are meaning-preserving. Final state verified correct in R01-VERIFICATION.md (MH-01 PASS, ART-01 PASS), suite green (MH-04 PASS). Disposition: accepted process exception.

RDEV-02 section must state the following facts. File: README.md, commit 576c9755. R01-PLAN task 2 scope was two version-string replacements with "Make no other edits to the file". Actual diff was 16 insertions and 7 deletions (both replacements plus sentence splits and TOC section headers). Same mandatory hook-gate cause. No accuracy-table counts changed. Final state verified correct (MH-02 PASS, ART-02 PASS), suite green. Disposition: accepted process exception.

Add a closing note: the exception is recorded forward in R02 artifacts. R01-PLAN.md task text is intentionally not amended retroactively. Plan-amendment classification is unavailable because source_plan may only reference an original phase plan (04-01, 04-02, 04-03), not a remediation plan.

Verify the cited commit hashes and diff stats before writing them with "git show --stat 6a6cc206" and "git show --stat 576c9755".
Do not edit R01-PLAN.md, references/handoff-schemas.md, or README.md.
  </action>
  <verify>
grep -c '6a6cc206' .vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md returns at least 1.
grep -c '576c9755' .vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-02/SCOPE-EXCEPTIONS.md returns at least 1.
grep -c 'RDEV-01' and grep -c 'RDEV-02' on the same file each return at least 1.
git status --porcelain shows no change to references/handoff-schemas.md, README.md, or .vbw-planning/phases/04-shared-contract-dedup/remediation/qa/round-01/R01-PLAN.md.
bash testing/run-all.sh exits 0.
  </verify>
  <done>
SCOPE-EXCEPTIONS.md exists with both exception sections, commit hashes, hook-gate rationale, and dispositions. No product or R01 planning file modified. Suite green.
  </done>
</task>
</tasks>
<verification>
1. SCOPE-EXCEPTIONS.md exists at the round-02 path and contains the strings RDEV-01, RDEV-02, 6a6cc206, 576c9755, and "process exception".
2. git status --porcelain reports references/handoff-schemas.md, README.md, and round-01/R01-PLAN.md as unmodified (this round touches only the round-02 artifact).
3. R01-PLAN.md task text is unchanged.
4. bash testing/run-all.sh exits 0.
</verification>
<success_criteria>
- Both R01 FAILs (RDEV-01, RDEV-02) have a process-exception classification with commit-level evidence recorded in a round-02 artifact.
- No retroactive edit to R01-PLAN.md and no edit to the two product files whose final state QA already verified.
- Full suite remains green.
</success_criteria>
<known_issue_workflow>
- No carried known issues this round. Both arrays are set to empty in frontmatter per the input_mode=verification instruction.
</known_issue_workflow>
<output>
R02-SUMMARY.md
</output>
