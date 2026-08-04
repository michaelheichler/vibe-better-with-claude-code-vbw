---
name: vbw:vibe
category: lifecycle
description: "The one command. Detects state and parses intent. Routes to lifecycle modes including bootstrap, scope, plan, execute, verify, discuss, archive, and more."
argument-hint: "[intent or flags]. Modes: [--plan] [--execute] [--verify] [--discuss] [--assumptions] [--scope] [--add] [--insert] [--remove] [--archive]. Modifiers: [--yolo] [--effort=level] [--skip-qa] [--skip-audit] [--plan=NN] [N]."
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, AskUserQuestion, Agent, TaskCreate, SendMessage, Skill, LSP, TodoWrite
disable-model-invocation: true
---

# VBW Vibe

## Shared interaction contract

@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md

## Context

Working directory:
```
!`pwd`
```
Plugin root and pre-computed state (first line is `LINK`, remaining lines are `PD`):
```
!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; R="$L/scripts/resolve-phase-state.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-phase-state.sh"; [ -f "$R" ] || { echo "VBW: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R"`
```

Config:
```
!`cat .vbw-planning/config.json 2>/dev/null || echo "No config found"`
```

!`bash "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-compact.sh" execute 2>/dev/null || true`

## Input Parsing

@${CLAUDE_PLUGIN_ROOT}/references/vibe-input-parsing.md

### Confirmation Gate

Every mode triggers confirmation before executing. Follow the shared interaction contract in `references/ask-user-question.md`, then use the AskUserQuestion tool with the question from the routing table's Confirmation column (marked with `→ AskUserQuestion:`). This section stays local to `/vbw:vibe`: it defines when confirmation is skipped, which routing copy to use, and which alternatives belong to each route.
- **Exception:** `--yolo` skips all confirmation gates. Error guards (missing roadmap, uninitialized project) still halt.
- **Exception:** Flags skip confirmation (explicit intent).

**Discussion-aware alternatives:** Alternatives must reflect whether discussion has already happened for the target phase. Never offer "discuss this phase" as if discussion never happened. When `{NN}-CONTEXT.md` exists, use continuation-aware wording like "Start a discussion" (which enters the Discussion Engine's continuation mode, building on existing context rather than repeating it).

| Routing state | Recommended | Alternatives |
| --- | --- | --- |
| `needs_discussion` | "Discuss phase {NN}" | "Skip discussion and plan directly", "View phase goal first" |
| `needs_plan_and_execute` | "Plan and execute phase {NN}" | "Plan only (review before executing)", "Start a discussion (explore gray areas before planning)" |
| `needs_execute` | "Execute phase {NN}" | "Review plans first", "Start a discussion (revisit scope before executing)" |
| `milestone_uat_issues` | "Create remediation phases" | "Start fresh with new work", "Not now" |

## Modes

### Mode: Init Redirect

If `planning_dir_exists=false`: display "Run /vbw:init first to set up your project." STOP.

### Mode: Bootstrap

Read `{LINK}/references/vibe-mode-bootstrap.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Scope

**Guard:** PROJECT.md exists but `phase_count=0`.

**Steps:**
1. Load context: PROJECT.md, REQUIREMENTS.md. If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`.
2. If $ARGUMENTS (excl. flags) provided, use as scope. Else ask: "What do you want to build?" Show uncovered requirements as suggestions.
3. Decompose into 3-5 phases (name, goal, success criteria). Each independently plannable. Map REQ-IDs.
4. Write ROADMAP.md. Create `.vbw-planning/phases/{NN}-{slug}/` dirs.
5. Update STATE.md by calling bootstrap-state.sh. Extract `PROJECT_NAME` from PROJECT.md, derive `MILESTONE_NAME` from the scope description (step 2), and use the phase count from step 3. The script preserves existing project-level sections (Todos, Decisions, Blockers, Codebase Profile) while restoring the `## Current Phase` section:
   ```
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
   ```
   Do NOT write next-action suggestions (e.g. "Run /vbw:vibe --plan 1") into the Todos section. Those are ephemeral display output from suggest-next.sh, not persistent state.
6. Write milestone context to `.vbw-planning/CONTEXT.md` using the template from `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/MILESTONE-CONTEXT.md`. Capture:
   - **Gathered date** and **Calibration** (builder or architect, inferred from conversation signals, using the same calibration as the Discussion Engine)
   - **Scope Boundary:** the user's scope description from step 2
   - **Decomposition Decisions:** rationale for phase count, grouping, and ordering from step 3. Includes **Scope Coverage** (what the milestone covers vs what is explicitly excluded or deferred) as a subsection under Decomposition Decisions per the template structure.
   - **Requirement Mapping:** which REQ-IDs map to which phases (from step 3)
   - **Key Decisions:** project-level decisions surfaced during scoping (tech choices, architecture patterns that transcend the milestone). Also insert these as rows in STATE.md's `## Key Decisions` table (append after the header row, replacing the `_(No decisions yet)_` placeholder if present). Milestone-scoped decisions (phase ordering rationale, scope boundaries) stay only in CONTEXT.md.
   - **Deferred Ideas:** out-of-scope ideas mentioned during steps 2-3
7. **Scope commit boundary (conditional):**
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "scope milestone" .vbw-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed (ROADMAP.md, STATE.md, CONTEXT.md, phase dirs). Other modes no-op.
8. Display "Scoping complete. {N} phases created." STOP. Do not auto-continue to planning.

### Mode: Discuss

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** First phase without `*-CONTEXT.md`. All discussed: STOP "All phases discussed. Specify: `/vbw:vibe --discuss N`"

**Continuation mode:** When the target phase already has a `{NN}-CONTEXT.md`, this is a **continuation discussion**, not a fresh one. If the CONTEXT.md has `pre_seeded: true` in its YAML frontmatter (remediation phase), WARN the user that this phase has pre-seeded UAT context and ask whether they want to re-discuss (which overwrites the pre-seeded content) or skip discussion and proceed to planning. Otherwise display: "Phase {NN} already has discussion context. Continuing to explore additional topics." The Discussion Engine will load existing decisions as baseline and focus on uncovered gray areas.

**Steps:**
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase.
3. **Discussion commit boundary (conditional):**
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "discuss phase {NN}" .vbw-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: Assumptions

**Guard:** Initialized, phase exists in roadmap.
**Phase auto-detection:** Same as Discuss mode.

**Continuation mode:** Same as Discuss mode. If a `{NN}-CONTEXT.md` exists, this is a continuation. Pre-seeded remediation phases get the same warning.

**Steps:**
1. Determine target phase from $ARGUMENTS or auto-detection.
2. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol for the target phase. Pass "Discussion mode: assumptions" to the engine. Step 1.7 handles the assumptions workflow (codebase analysis, assumption formation, user correction, capture).
3. **Discussion commit boundary (conditional):**
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh commit-boundary "assumptions phase {NN}" .vbw-planning/config.json
   ```
   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

Read `{LINK}/references/vibe-uat-remediation.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Milestone UAT Recovery

Read `{LINK}/references/vibe-mode-milestone-uat-recovery.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Plan

Read `{LINK}/references/vibe-mode-plan.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Execute

Read `{LINK}/references/vibe-mode-execute.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Verify

Read `{LINK}/references/vibe-mode-verify.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Add Phase

Read `{LINK}/references/vibe-mode-add-phase.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Insert Phase

Read `{LINK}/references/vibe-mode-insert-phase.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Remove Phase

Read `{LINK}/references/vibe-mode-remove-phase.md` and follow it. `{LINK}` is the first line of the Context block output.

### Mode: Archive

Read `{LINK}/references/vibe-mode-archive.md` and follow it. `{LINK}` is the first line of the Context block output.

### Pure-Vibe Phase Loop

After Execute mode completes (autonomy=pure-vibe only): if more unbuilt phases exist, auto-continue to next phase (Plan + Execute). Loop until `next_phase_state=all_done` or error. Other autonomy levels: STOP after phase.

Before handling a team shutdown, Read `{LINK}/references/subagent-contracts.md` and follow its contract. `{LINK}` is the first line of the Context block output.

**CRITICAL: Between iterations:** Before starting the next phase's Plan mode, inspect the prior Execute delegation marker and state. Only when the prior run persisted `delegation_mode=team` with a real `TEAM_NAME`, follow the team-shutdown contract.

Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.

After the shared shutdown completes, run Post-shutdown residual cleanup. The team config directory is removed automatically when the session exits. There is no TeamDelete call. If the prior run used serialized subagents, turbo or internal direct execution, or fallback non-team mode, rely on completed subagent or direct execution plus the cleared delegation state. Do not send team shutdown messages without a real team.

## Output Format

Before rendering output, read `{LINK}/references/vbw-brand-essentials.md` and follow it. `{LINK}` is the first line of the Context block output. Skip this read for Verify mode because UAT files use plain markdown.

Per-mode output:
- **Bootstrap:** project-defined banner + transition to scoping
- **Scope:** phases-created summary + STOP
- **Discuss:** ✓ for captured answers, Next Up Block
- **Assumptions:** numbered list with confidence indicators: ✓ confirmed (high), ⚡ validated (medium), ? resolved (low), ✗ corrected, ○ expanded (user added nuance), Next Up
- **Plan:** Phase Banner (double-line box), plan list with waves/tasks, Effort, Next Up
- **Execute:** Phase Banner, plan results (✓/✗), Metrics (plans, effort, deviations), QA result, "What happened" (NRW-02), Next Up
- **Add/Insert/Remove Phase:** Phase Banner, ✓ checklist, Next Up
- **Archive:** Phase Banner, Metrics (phases, tasks, commits, reqs, deviations), archive path, tag, branch, memory status, Next Up

Rules: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.

Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe {result}` for Next Up suggestions.
