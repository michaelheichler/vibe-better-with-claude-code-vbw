---
name: vbw:skills
category: supporting
disable-model-invocation: true
description: Browse and install community skills from skills.sh based on your project's tech stack.
argument-hint: [--search <query>] [--list] [--refresh]
allowed-tools: Read, Bash, Glob, Grep, WebFetch, AskUserQuestion, LSP
---

# VBW Skills $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "VBW: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```
Stack detection:
```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/detect-stack.sh" "$(pwd)" 2>/dev/null || echo '{"error":"detect-stack.sh failed"}'`
```

## Guard

1. **Script failure:** Context contains `"error"` → STOP: "Stack detection failed. Make sure jq is installed."

## Steps

### Step 1: Parse arguments

- **No args**: full flow (detect, show installed, suggest, offer install)
- **--search \<query\>**: skip curated, search registry for \<query\>
- **--list**: list installed only, no suggestions
- **--refresh**: force re-run stack detection

### Step 2: Display current state

From Context JSON: display project-installed skills from `installed.project[]` in a single-line box. Display `installed.global[]` separately as informational only. Curated suggestions are suppressed only by project-installed skills. Display detected stack. If `--list`: STOP here.

### Step 3: Curated suggestions

From `suggestions[]` in Context JSON (recommended but not installed). Display in single-line box with `(curated)` tag.
- suggestions non-empty: show them
- empty + stack detected: "✓ All recommended skills already installed."
- no stack + no suggestions: "○ No stack detected. Use --search <query>." and suggest example searches

### Step 4: Dynamic registry search

Search when: --search passed (search for query) | no --search but unmapped stack items (auto-search each) | all mapped → skip.
Run `npx skills find "<query>"`. Display results with `(registry)` tag. If the skills CLI is unavailable (npx missing or the command fails): "⚠ skills CLI not found."

### Step 5: Offer installation

Combine curated + registry, deduplicate, rank (curated first).

- If the combined list is empty: STOP here. Do NOT AskUserQuestion. The Step 3 / Step 4 output already explains the no-results state (for example, all recommended skills already installed, no stack detected, or no registry results).
- For any bounded AskUserQuestion branch below that uses visible options, the built-in `Other` path is still part of that question: accept direct option intent (`install` / `skip`, `yes` / `no`), accept unambiguous visible option-by-number replies (for example `#1` / `#2`), accept hybrid replies anchored to one of those visible option numbers (for example `#2 for now`), and re-ask only when the follow-up is ambiguous or invalid for that same question.
- If the combined list has exactly 1 candidate: keep it structured.
  - AskUserQuestion with a single bounded question.
  - Keep the header short.
  - Question text should show `{skill-name}: {brief description}`.
  - Options:
    - `Install {skill-name}` (Recommended)
    - `Skip for now`
  - Declined → display `○ No skills selected for installation.` and STOP here. Do not enter Step 6.

- If the combined list has 2-4 candidates: keep it structured because this stays within the AskUserQuestion sweet spot.
  - Use AskUserQuestion with 1 question per skill (2-4 questions total), in ranked order.
  - Keep each header short. Use the skill name as the header.
  - Each question should show `{skill-name}: {brief description}` with two options:
    - `Install`
    - `Skip`
  - Collect every selected skill in ranked order.
  - If none were selected, display `○ No skills selected for installation.` and STOP here. Do not enter Step 6.

- If the combined list has more than 4 candidates: use intentional high-cardinality freeform input.
  - Present it as a numbered list in the AskUserQuestion text (do NOT use `options` array: this list is larger than the 2-4 structured-choice sweet spot, so numeric/freeform input is intentional here rather than a faux bounded chooser).

Question text:
```
Available skills for installation:
1. {skill-name}: {brief description}
2. {skill-name}: {brief description}
...N. {skill-name}: {brief description}

This list is larger than the 2-4 structured-choice sweet spot, so use numeric/freeform selection here.
Type numbers to install (comma-separated), or 'skip' to continue:
```

Parse the user's freeform response using these rules:
- Accept comma-separated digits corresponding to the numbered items (e.g., `1,3` or `2, 4, 5`).
- Accept the word `skip` (case-insensitive) to proceed without installing.
- Trim whitespace around each token. Ignore empty tokens from trailing commas.
- Reject out-of-range numbers (less than 1 or greater than the list count), non-numeric tokens (other than `skip`), duplicate numbers, and empty input.
- If invalid, show `Invalid selection. Type numbers (comma-separated) to install, or 'skip' to continue.` and AskUserQuestion again with the same question text.
- Repeat until a valid selection or `skip` is obtained.

If the user typed `skip`, STOP here after displaying `○ No skills selected for installation.` Do not enter Step 6.

### Step 6: Install selected

Run `npx skills add <skill> -y` for each selected skill. This installs into `./.claude/skills/` for the current project. This step runs only when one or more skills were selected in Step 5. Display ✓ or ✗ per skill. "➜ Changes in existing watched skill directories are detected in-session. Creating a top-level skills directory that did not exist at session start requires a restart."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md

Use a single-line box, ✓ installed, ○ suggested, ✗ failed, ⚠ warning, and no ANSI.
