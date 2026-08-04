---
name: vbw:discuss
category: lifecycle
description: "Start or continue phase discussion to build context before planning."
argument-hint: "[N] [--assumptions]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, AskUserQuestion, LSP
disable-model-invocation: true
---

# VBW Discuss: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "VBW: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; bash "$L/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in script/reference lookups below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

Phase state:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PD=""
_refresh_phase_detect() {
  local resolver root
  resolver="$L/scripts/resolve-plugin-root.sh"
  if [ ! -f "$resolver" ]; then
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
      resolver="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
    else
      return 1
    fi
  fi
  root=$(bash "$resolver" --require-script phase-detect.sh 2>/dev/null) || return 1
  PD=$(bash "$root/scripts/phase-detect.sh" 2>/dev/null) || PD=""
  if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
    return 1
  fi
  printf '%s' "$PD" > "$P"
  return 0
}
if ! _refresh_phase_detect; then
  PD="phase_detect_error=true"
  printf '%s\n' "$PD" > "$P"
fi
[ -f "$P" ] && PD=$(cat "$P")
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  echo "phase_detect_error=true"
fi`
```

!`bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-compact.sh" discuss 2>/dev/null || true`

## Guards

- No `.vbw-planning/` directory: STOP "Run /vbw:init first."
- No phases in ROADMAP.md: STOP "No phases defined. Run /vbw:vibe first."

## Phase Resolution

1. If `$ARGUMENTS` contains a number N, target phase N.
2. If the target phase has a `*-CONTEXT.md` file with `pre_seeded: true` in its YAML frontmatter (remediation phase): WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning.
3. If the target phase has a `*-CONTEXT.md` file WITHOUT `pre_seeded: true` (organic discussion already happened): This is a **continuation discussion**. Display: "Phase {NN} already has discussion context. Continuing to explore additional topics." The Discussion Engine's Step 1.5 will handle loading existing decisions as baseline.
4. If no target was set by step 1 (no explicit phase number): auto-detect by finding the first phase directory without a `*-CONTEXT.md` file. If all phases already have context: STOP "All phases discussed. Specify a phase number to deepen an existing discussion."

## Discussion Mode Resolution

Determine the discussion mode before invoking the engine:

1. If `$ARGUMENTS` contains `--assumptions` → mode is `assumptions`
2. Else read `discussion_mode` from `.vbw-planning/config.json` (via `jq -r '.discussion_mode // "questions"'`)
3. If config value is `"assumptions"` → mode is `assumptions`
4. If config value is `"auto"` and `.vbw-planning/codebase/META.md` exists → mode is `assumptions`
5. Otherwise → mode is `questions`

Pass the resolved mode to the engine: "Discussion mode: {resolved_mode}"

## Execute

Read `{plugin-root}/references/discussion-engine.md` and follow its protocol for the target phase. The engine's Step 1.7 uses the resolved discussion mode to branch between assumptions and questions paths.

## After Discussion

**Discussion commit boundary (conditional):**
```bash
PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "discuss phase {NN}" .vbw-planning/config.json
else
  echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
fi
```
Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.

Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh discuss`.
