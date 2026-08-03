---
phase: 07
plan: 03
title: Punctuation cleanup in docs/
status: complete
completed: 2026-08-03
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 5e05093
  - 8c9d91d
  - 3b00133
deviations:
  - "None"
pre_existing_issues: []
ac_results:
  - criterion: "Zero watcher-banned dash characters remain in the assigned docs/ files"
    verdict: "pass"
    evidence: "Agent Discipline Watcher review passed for all nine assigned files"
  - criterion: "Zero semicolon-splice matches remain in the assigned docs/ files"
    verdict: "pass"
    evidence: "Semicolon scans passed for all nine assigned files"
  - criterion: "Table nulls use intentional values"
    verdict: "pass"
    evidence: "3b00133, docs/vbw-1-10-7-context-compiler-token-analysis.md"
  - criterion: "Analysis conclusions and numbers remain unchanged"
    verdict: "pass"
    evidence: "Punctuation-only edits, with sentence splits required by the watcher"
---

Cleaned banned dash and semicolon punctuation in all nine assigned docs files while preserving analysis figures and table meaning.

## What Was Built

- Rewrote Unicode dash and semicolon-splice usage in the Paul and GSD comparison documents.
- Rewrote punctuation in the database safety guide and six token analysis documents.
- Replaced visual null dashes in the context compiler tables with N/A.
- Split watcher-flagged long sentences without changing measured figures or conclusions.

## Files Modified

Comparison and safety docs:

- `docs/vbw-vs-paul-analysis.md` -- cleaned comparison prose and table separators.
- `docs/vbw-vs-gsd-source-validated.md` -- cleaned comparison prose and table separators.
- `docs/database-safety-guard.md` -- cleaned safety guide prose.

Token analysis docs:

- `docs/vbw-1-0-99-vs-stock-teams-token-analysis.md` -- cleaned token analysis punctuation.
- `docs/vbw-1-10-2-vs-stock-agent-teams-token-analysis.md` -- cleaned token analysis punctuation.
- `docs/vbw-1-10-7-context-compiler-token-analysis.md` -- cleaned punctuation and table nulls.
- `docs/vbw-1-20-0-full-spec-token-analysis.md` -- cleaned token analysis punctuation.
- `docs/vbw-1-21-30-full-spec-token-analysis.md` -- cleaned token analysis punctuation.
- `docs/vbw-1-30-0-full-spec-token-analysis.md` -- cleaned token analysis punctuation.

## Deviations

None.
