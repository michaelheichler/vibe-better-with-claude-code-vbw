---
name: vbw:whats-new
category: advanced
disable-model-invocation: true
description: View changelog and recent updates since your installed version.
argument-hint: "[version]"
allowed-tools: Read, Glob
---

# VBW What's New $ARGUMENTS

## Context

Plugin root:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; RESOLVER="${SESSION_LINK}/scripts/resolve-plugin-root.sh"; if [ ! -f "$RESOLVER" ]; then if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"; else echo "VBW: plugin root resolution failed" >&2; exit 1; fi; fi; bash "$RESOLVER" >/dev/null || exit 1; echo "$SESSION_LINK"`
```

Store the plugin root path output above as `{plugin-root}` for use in file lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references VERSION or CHANGELOG.md.

## Guard

1. **Missing changelog:** `{plugin-root}/CHANGELOG.md` missing → STOP: "No CHANGELOG.md found."

## Steps

1. Read `{plugin-root}/VERSION` for current_version.
2. Read `{plugin-root}/CHANGELOG.md`, split by `## [` headings.
   - With version arg: show entries newer than that version.
   - No args: show current version's entry.
3. Display Phase Banner "VBW Changelog" with version context, entries, Next Up (/vbw:help). No entries: "✓ No changelog entry found for v{version}."

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, ✓ up-to-date, Next Up, no ANSI.
