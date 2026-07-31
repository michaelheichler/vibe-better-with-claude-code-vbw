---
name: vbw:resume
category: supporting
disable-model-invocation: true
description: Restore project context from .vbw-planning/ state.
argument-hint:
allowed-tools: Read, Bash, Glob
---

# VBW Resume

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; RESOLVER="${SESSION_LINK}/scripts/resolve-plugin-root.sh"; if [ ! -f "$RESOLVER" ]; then if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"; else echo "VBW: plugin root resolution failed" >&2; exit 1; fi; fi; bash "$RESOLVER" >/dev/null || exit 1; bash "$SESSION_LINK/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt" 2>/dev/null || echo "phase_detect_error=true" > "/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"; echo "$SESSION_LINK"`
```

Pre-computed state (via phase-detect.sh):
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

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **Brownfield normalization:** If Pre-computed state (from Context above) contains `misnamed_plans=true`, normalize all phase directories before proceeding:
   ```bash
   NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
   if [ -f "$NORM_SCRIPT" ]; then
     for pdir in .vbw-planning/phases/*/; do
       [ -d "$pdir" ] && bash "$NORM_SCRIPT" "$pdir"
     done
   fi
   ```
   Display: "⚠ Renamed misnamed plan files to `{NN}-PLAN.md` convention."
   Then re-run phase-detect.sh to refresh state:
   ```bash
   bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh" > "/tmp/.vbw-phase-detect-${CLAUDE_SESSION_ID:-default}.txt"
   ```
   Use the refreshed phase-detect output for all subsequent steps.
3. **No roadmap:** `.vbw-planning/ROADMAP.md` missing → STOP: "No roadmap found. Run /vbw:vibe."
4. **Phase-detect error:** If output contains `phase_detect_error=true`, display: "⚠ Phase detection failed. Run phase-detect.sh manually to debug." and STOP.

## Steps

1. **Read ground truth (top-level only):** Read these files from `.vbw-planning/` (NOT from `milestones/` — those are archived):
   - `.vbw-planning/PROJECT.md` — name, core value
   - `.vbw-planning/STATE.md` — decisions, todos, blockers
   - `.vbw-planning/ROADMAP.md` — phases overview
   - `.vbw-planning/.execution-state.json` — interrupted builds
   - `.vbw-planning/RESUME.md` — session notes
   - Glob `.vbw-planning/phases/**/*-PLAN.md` and `.vbw-planning/phases/**/*-SUMMARY.md` — plan/completion counts
   - Most recent SUMMARY.md from `.vbw-planning/phases/` — last work
   - Skip missing files. **Never read from `.vbw-planning/milestones/`.**
2. **Compute progress from phase-detect.sh output:** Use the pre-computed `phase_count`, `next_phase`, `next_phase_state`, `next_phase_plans`, `next_phase_summaries`, `uat_issues_phase`, `uat_issues_slug`, `uat_issues_phases`, and `uat_issues_count` values. Map `next_phase_state` to display: `needs_uat_remediation` → "⚠ Needs remediation", `needs_verification` → "⏳ Needs UAT verification", `needs_plan_and_execute` → "not started", `needs_execute` → "in progress", `all_done` → "complete". **Per-phase status:** any phase whose number appears in the comma-separated `uat_issues_phases` list has unresolved UAT issues — mark it "⚠ Needs remediation". Only mark a phase as "✓ Done" if its number is NOT in `uat_issues_phases` and it has completed execution (SUMMARY count ≥ PLAN count). Phases not yet executed are "not started".
   **Known issues check:** For each phase directory, run:
   ```bash
   bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
   bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/track-known-issues.sh" status "{phase-dir}" 2>/dev/null
   ```
   Parse `known_issues_count` from the status output. For each phase with `known_issues_count > 0`, include in the dashboard after the phase table: `⚠ Phase {NN}: N known issue(s) deferred — run /vbw:list-todos to review`. Omit for phases with zero known issues. The `promote-todos` call is a backfill — it ensures any known issues not yet in `STATE.md ## Todos` are promoted on resume.
3. **Detect interrupted builds:** If `.execution-state.json` status="running": all SUMMARYs present = completed since last session; some missing = interrupted.
4. **Present dashboard:** Phase Banner "Context Restored / {project name}" with: core value, phase/progress, overall progress bar, key decisions, todos, blockers (⚠), last completed, build status (✓ completed / ⚠ interrupted), session notes. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh resume`.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md — double-line box, Metrics Block, ⚠ warnings, ✓ completions, ➜ Next Up, no ANSI.
