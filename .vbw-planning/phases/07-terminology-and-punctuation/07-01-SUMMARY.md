---
phase: 7
plan: 01
title: Punctuation cleanup in commands/
status: complete
completed: 2026-08-03
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 67e1ba2
  - a576c9d1
  - 429a6813
deviations:
  - "Reformatted fenced shell loops in assigned command files to remove semicolon matches while preserving execution behavior."
  - "The exact directory-wide semicolon scan still reports pre-existing fenced shell lines in unassigned commands/discuss.md and commands/research.md. Those files were outside this plan's files_modified list."
pre_existing_issues: []
ac_results:
  - criterion: "Zero em dash, en dash, or other watcher-banned dash characters remain in commands/*.md"
    verdict: pass
    evidence: "Dash scan over commands/*.md"
  - criterion: "Zero semicolon-splice matches remain in assigned command prose"
    verdict: pass
    evidence: "Watcher-equivalent semicolon scan over all assigned files"
  - criterion: "No replacement introduces a double hyphen clause break or spaced hyphen standing in for a dash"
    verdict: pass
    evidence: "Watcher reviews and diff checks"
  - criterion: "Behavior and meaning preserved with punctuation-only rewrites"
    verdict: pass
    evidence: "Commits 67e1ba2, a576c9d1, and 429a6813"

Cleaned banned dash and semicolon punctuation in all 19 assigned command files.

## What Was Built

- Rewrote Unicode dash and semicolon-splice prose in the debug and verify commands.
- Rewrote punctuation in the six high-count command files.
- Rewrote punctuation in the remaining 11 assigned command files and expanded fenced shell loops where needed.
- Preserved command frontmatter and template expansion structure.

## Files Modified

### Core workflow commands

- `commands/debug.md`
- `commands/verify.md`
- `commands/qa.md`
- `commands/report.md`
- `commands/fix.md`
- `commands/resume.md`

### Todo commands

- `commands/list-todos.md`
- `commands/todo.md`

### Utility commands

- `commands/compress.md`
- `commands/doctor.md`
- `commands/help.md`
- `commands/map.md`
- `commands/pause.md`

### Remaining utility commands

- `commands/profile.md`
- `commands/status.md`
- `commands/teach.md`
- `commands/uninstall.md`
- `commands/update.md`
- `commands/whats-new.md`

## Deviations

The assigned files passed the required watcher punctuation checks. Two unassigned command files retain fenced shell semicolon matches under the raw directory scan. No files outside the plan scope were changed.
