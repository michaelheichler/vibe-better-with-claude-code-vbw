---
name: vbw:help
category: supporting
disable-model-invocation: true
description: Display all available VBW commands with descriptions and usage examples.
argument-hint: [command-name]
allowed-tools: Read, Glob, Bash
---

# VBW Help $ARGUMENTS

## Context

Plugin root:
```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "VBW: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in command lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a command file.

## Behavior

### No args: Display all commands

Run the help output script and display the result exactly as-is (pre-formatted terminal output):

```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/help-output.sh" || echo "VBW: help-output.sh failed , run /vbw:doctor for diagnostics"`
```

Display the output above verbatim. Do not reformat, summarize, or add commentary. The script dynamically reads all command files and generates grouped output.

### With arg: Display specific command details

Read `{plugin-root}/commands/{name}.md` (strip `vbw:` prefix if present). Display:
- **Name** and **description** from frontmatter
- **Category** from frontmatter
- **Usage:** `/vbw:{name} {argument-hint}`
- **Arguments:** list from argument-hint with brief explanation
- **Related:** suggest 1-2 related commands based on category

If command not found: "⚠ Unknown command: {name}. Run /vbw:help for all commands."
