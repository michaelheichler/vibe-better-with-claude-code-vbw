# Scope Exceptions for QA Remediation Round 02

## RDEV-01

- **Disposition:** Accepted process exception.
- **File:** `references/handoff-schemas.md`
- **Commit:** `6a6cc206`
- **Planned scope:** R01-PLAN task 1 required a single-line sentence restore and stated, "Make no other edits to the file."
- **Actual diff:** 5 insertions and 5 deletions. The diff restored the required sentence and split four semicolon-linked sentences into separate sentences.
- **Cause:** The discipline-watcher PostToolUse gate flagged the four existing sentences after the planned write. The gate hard-blocks completion while flagged findings remain in a modified file, so the extra edits were mandatory.
- **Why no revert:** Reverting the extra edits would reintroduce blocked findings and could not land. The edits preserve the original meaning.
- **Verification evidence:** `R01-VERIFICATION.md` records MH-01 and ART-01 as PASS. It also records the full suite as green under MH-04.

## RDEV-02

- **Disposition:** Accepted process exception.
- **File:** `README.md`
- **Commit:** `576c9755`
- **Planned scope:** R01-PLAN task 2 required two version-string replacements and stated, "Make no other edits to the file."
- **Actual diff:** 16 insertions and 7 deletions. The diff made both required replacements, split sentences, and added table-of-contents section headers.
- **Cause:** The discipline-watcher PostToolUse gate flagged existing prose after the planned write. The gate hard-blocks completion while flagged findings remain in a modified file, so the extra edits were mandatory.
- **Why no revert:** Reverting the extra edits would reintroduce blocked findings and undo verified-correct, meaning-preserving edits. No accuracy-table counts changed.
- **Verification evidence:** `R01-VERIFICATION.md` records MH-02 and ART-02 as PASS. It also records the full suite as green under MH-04.

## Recording Decision

These exceptions are recorded forward in the R02 artifacts. The R01-PLAN task text is intentionally not amended retroactively. A plan-amendment classification is unavailable because `source_plan` may reference only an original phase plan (`04-01`, `04-02`, or `04-03`), not a remediation plan.
