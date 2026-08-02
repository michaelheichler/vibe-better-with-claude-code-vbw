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

@${CLAUDE_PLUGIN_ROOT}/references/subagent-contracts.md

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

**Guard:** `.vbw-planning/` exists but no PROJECT.md.

**Critical Rules (non-negotiable):**
- NEVER fabricate content. Only use what the user explicitly states.
- If answer doesn't match question: STOP, handle their request, let them re-run.
- No silent assumptions. Ask follow-ups for gaps.
- Phases come from the user, not you.

**Constraints:** Do NOT explore/scan codebase (that's /vbw:map). Use existing `.vbw-planning/codebase/` if `.vbw-planning/codebase/META.md` exists.

**Brownfield detection:** `git ls-files` or Glob check for existing code.

**Steps:**
- **B1: PROJECT.md**: If $ARGUMENTS provided (excluding flags), use as description. Otherwise ask name + core purpose. Then call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-project.sh .vbw-planning/PROJECT.md "$NAME" "$DESCRIPTION"
  ```
- **B1.5: Discovery Depth**: Read `discovery_questions` and `active_profile` from config. Map profile to depth:

  | Profile | Depth | Questions |
  | --------- | ------- | ----------- |
  | yolo | skip | 0 |
  | prototype | quick | 1-2 |
  | default | standard | 3-5 |
  | production | thorough | 5-8 |

  If `discovery_questions=false`: force depth=skip. Store DISCOVERY_DEPTH for B2.

- **B2: REQUIREMENTS.md (Discovery)**: Behavior depends on DISCOVERY_DEPTH:
  - **B2.1: Domain Research (if not skip):** If DISCOVERY_DEPTH != skip:

    **Research setup (steps 1-4):**
    **Step 1:** Extract domain from user's project description (the $NAME or $DESCRIPTION from B1)
    **Step 2:** Resolve Scout agent settings before spawn. If helper resolution fails, warn and continue without explicit Scout model/maxTurns so domain research can still fall back gracefully:
       ```bash
       SCOUT_MODEL=""
       SCOUT_MAX_TURNS=""
       if ! SCOUT_SETTINGS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-settings.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json); then
         echo "Warning: failed to resolve Scout agent settings; continuing without explicit Scout model/maxTurns." >&2
       else
         eval "$SCOUT_SETTINGS"
         SCOUT_MODEL="$RESOLVED_MODEL"
         SCOUT_MAX_TURNS="$RESOLVED_MAX_TURNS"
         SCOUT_REASONING="$RESOLVED_REASONING"
       fi
       ```
       Use these variables when you execute the Task invocation in step 6.
    **Step 3:** Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
    **Step 3.25:** If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the bootstrap domain-research Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
     **Step 3.5:** Use this payload prefix as the FIRST lines of the bootstrap domain-research Scout prompt:
       ```text
       <skill_activation>
       Call Skill('{relevant-skill-1}').
       Call Skill('{relevant-skill-2}').
       </skill_activation>
       After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
      <skill_follow_up_files>
      {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
      </skill_follow_up_files>
       ```
       When no installed skills apply, use this prefix instead:
       ```text
       <skill_no_activation>
       Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
       </skill_no_activation>
       After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
       ```
    **Step 4:** Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research topic, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.

    **Research execution (steps 5-8):**
    **Step 5:** Spawn Scout agent via Agent tool with prompt: "Research the {domain} domain. Write your findings directly to the output path. <output_path>.vbw-planning/domain-research.md</output_path> Structure as four sections: ## Table Stakes (features every {domain} app has), ## Common Pitfalls (what projects get wrong), ## Architecture Patterns (how similar apps are structured), ## Competitor Landscape (existing products). Use WebSearch (or relevant MCP tools if available). Be concise (2-3 bullets per section)."
    **Step 6:** Set `subagent_type: "vbw:vbw-scout"` and `timeout: 120000` in the Agent tool invocation. If `SCOUT_MODEL` is non-empty, also pass `model: "${SCOUT_MODEL}"`. If `SCOUT_MODEL` is empty, omit model so the default applies. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
    **Step 7:** On success, read `.vbw-planning/domain-research.md` (Scout wrote it directly). Extract brief summary (3-5 lines max). Display to user: "◆ Domain Research: {brief summary}\n\n✓ Research complete. Now let's explore your specific needs..."
    **Step 8:** On failure, log warning "⚠ Domain research timed out, proceeding with general questions". Set RESEARCH_AVAILABLE=false, continue.
  - **B2.2: Discussion Engine**: Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/discussion-engine.md` and follow its protocol.
    - Context for the engine: "This is a new project. No phases yet." Use project description + domain research (if available) as input.
    - If `.vbw-planning/codebase/META.md` exists and `discussion_mode` in config is `"assumptions"` or `"auto"`, pass "Discussion mode: assumptions" to the engine. The engine's Step 1.7 will form evidence-backed assumptions from codebase context instead of asking questions from scratch.
    - The engine handles calibration, gray area generation, exploration, and capture. The Recommendation Principle applies during bootstrap: lead with enterprise-standard recommendations for technical decisions, present product decisions equally.
    - Output: `discovery.json` with answered/inferred/deferred arrays.
  - **If skip (yolo profile or discovery_questions=false):** Ask 2 minimal static questions via AskUserQuestion:
    1. "What are the must-have features for this project?" Options: ["Core functionality only", "A few essential features", "Comprehensive feature set", "Let me explain..."]
    2. "Who will use this?" Options: ["Just me", "Small team (2-10 people)", "Many users (100+)", "Let me explain..."]
    Record answers to `.vbw-planning/discovery.json` with `{"answered":[],"inferred":[],"deferred":[]}`.
  - **After discovery (all depths):** Call:
    ```
    bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-requirements.sh .vbw-planning/REQUIREMENTS.md .vbw-planning/discovery.json .vbw-planning/domain-research.md
    ```

- **B3: ROADMAP.md**: Suggest 3-5 phases from requirements. If `.vbw-planning/codebase/META.md` exists, read PATTERNS.md, ARCHITECTURE.md, and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Each phase: name, goal, mapped reqs, success criteria. Write phases JSON to temp file, then call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-roadmap.sh .vbw-planning/ROADMAP.md "$PROJECT_NAME" /tmp/vbw-phases.json
  ```
  Script handles ROADMAP.md generation and phase directory creation.
- **B4: STATE.md**: Extract project name, milestone name, and phase count from earlier steps. Call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-state.sh .vbw-planning/STATE.md "$PROJECT_NAME" "$MILESTONE_NAME" "$PHASE_COUNT"
  ```
  Script handles today's date, Phase 1 status, empty decisions, and 0% progress.
- **B5: Brownfield summary**: If BROWNFIELD=true AND no codebase/: count files by ext, check tests/CI/Docker/monorepo, add Codebase Profile to STATE.md.
- **B6: CLAUDE.md**: Extract project name and core value from PROJECT.md. If root CLAUDE.md exists, pass it as EXISTING_PATH for section preservation. Call:
  ```
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/bootstrap/bootstrap-claude.sh CLAUDE.md "$PROJECT_NAME" "$CORE_VALUE" [CLAUDE.md]
  ```
  Script handles new file generation (heading + core value + VBW sections). For existing files, it refreshes only exact canonical VBW-owned sections already emitted by VBW, preserves the user's title/intro/arbitrary headings verbatim, and adds `## Code Intelligence` only if no Code Intelligence heading/guidance already exists anywhere in the file. Omit the fourth argument if no existing CLAUDE.md. Max 200 lines.
- **B7: Planning commit boundary (conditional)**: Run:
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "bootstrap project files" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` + `CLAUDE.md` if changed. Other modes no-op.
- **B8: Transition**: Display "Bootstrap complete. Transitioning to scoping..." Re-evaluate state, route to next match.

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
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "scope milestone" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
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
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "discuss phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
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
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "assumptions phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `{NN}-CONTEXT.md` and `discovery.json` if changed. Other modes no-op.
4. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Mode: UAT Remediation

@${CLAUDE_PLUGIN_ROOT}/references/vibe-uat-remediation.md

### Mode: Milestone UAT Recovery

**Guard:** `milestone_uat_issues=true` from phase-detect.sh. Active phases dir is empty/all_done but the latest shipped milestone has unresolved UAT issues.

This mode handles the case where a milestone was archived before UAT issues were resolved (e.g., due to a missing audit gate in older versions).

**Steps:**
1. After milestone-recovery routing is selected, extract milestone UAT issues with this route-local block:
   ```bash
   MILESTONE_UAT_CONTEXT=$(
     SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
     L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
     P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
     PD=""
     _PD_START_TS=$(date +%s 2>/dev/null || echo 0)
     _phase_detect_cache_fresh() {
       local m=""
       [ -f "$P" ] || return 1
       m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
       [ -n "$m" ] || return 1
       [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
     }
     _phase_detect_cache_retryable() {
       [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]
     }
     REAL_R=$(cd "$L" 2>/dev/null && pwd -P) || REAL_R=""
     if [ -n "$REAL_R" ]
     then
       bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
     fi
     i=0
     while [ $i -lt 100 ]
     do
       if _phase_detect_cache_fresh
       then
         PD=$(cat "$P")
         break
       fi
       sleep 0.1
       i=$((i+1))
     done
     if _phase_detect_cache_retryable && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]
     then
       LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
       i=0
       while [ $i -lt 100 ]
       do
         if _phase_detect_cache_fresh
         then
           PD=$(cat "$P")
           if ! _phase_detect_cache_retryable
           then
             break
           fi
         fi
         if mkdir "$LOCK" 2>/dev/null
         then
           PTMP="${P}.reader.$$.$RANDOM"
           PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
           if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]
           then
             printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
           fi
           rmdir "$LOCK" 2>/dev/null || true
           break
         fi
         sleep 0.1
         i=$((i+1))
       done
     fi
     [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
     if _phase_detect_cache_retryable
     then
       echo "milestone_extract_unavailable=true"
     elif printf '%s' "$PD" | grep -q '^---MILESTONE_UAT_EXTRACT_START---$'
     then
       printf '%s\n' "$PD" | awk '
         /^---MILESTONE_UAT_EXTRACT_START---$/ {
           found=1
           next
         }
         /^---MILESTONE_UAT_EXTRACT_END---$/ {
           exit
         }
         found {
           print
         }
       '
     else
       MS_UAT=$(printf '%s' "$PD" | grep '^milestone_uat_issues=' | head -1 | cut -d= -f2)
       if [ "$MS_UAT" = "true" ]
       then
         echo "milestone_extract_unavailable=true"
       else
         echo "not_milestone_recovery"
       fi
     fi
   )
   ```
   Each extracted block starts with `milestone_phase_dir=<path>` followed by `extract-uat-issues.sh` output (header line plus issue lines). Do NOT read UAT files from the milestone. All issue data is already in `MILESTONE_UAT_CONTEXT`.
   If `milestone_uat_count` > 1, multiple blocks are present, one per affected phase separated by `---`. If `milestone_uat_count` = 1, a single block is present.
2. Display the unresolved issues to the user with milestone context (milestone slug, affected phase count, severity mix). Then call AskUserQuestion with three options:
   - **"Create remediation phases"** (set `isRecommended` when `milestone_uat_major_or_higher=true`): Create one remediation phase per affected milestone phase. Auto-populate each phase goal from the UAT issue descriptions. Route to Plan mode for the first created phase.
   - **"Start fresh with new work"**: Acknowledge the stale UAT issues, mark them as acknowledged (`.remediated`) so they don't re-trigger archive blocking, then proceed as if all_done. The user can define new work via `/vbw:vibe` with arguments.
   - **"Not now"**: Skip milestone UAT recovery without marking anything. The unresolved UAT issues will re-trigger on the next `/vbw:vibe` invocation.
   **`--yolo` exception:** If `--yolo` was passed, skip the AskUserQuestion and auto-select "Create remediation phases" (the recommended action).
3. If the user chooses remediation, create one remediation phase per affected milestone phase via the script:
   ```bash
   IFS='|' read -ra UAT_DIRS <<< "$milestone_uat_phase_dirs"
   for dir in "${UAT_DIRS[@]}"; do
     bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/create-remediation-phase.sh .vbw-planning "$dir"
   done
   ```
   The script also writes a `.remediated` marker in each source milestone phase dir to prevent re-triggering on future sessions. After creating all phases, write a ROADMAP.md and update STATE.md reflecting the remediation phases.
   **Remediation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "create milestone remediation phases" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Then route to Plan mode for the first phase.
4. If the user chooses start-fresh: persist acknowledgement markers for all affected archived phases before continuing:
   ```bash
   TARGET_PHASE_DIRS="$milestone_uat_phase_dirs"
   if [ -z "$TARGET_PHASE_DIRS" ] && [ "$milestone_uat_phase_dir" != "none" ]; then
     TARGET_PHASE_DIRS="$milestone_uat_phase_dir"
   fi
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/mark-milestone-remediated.sh .vbw-planning "$TARGET_PHASE_DIRS"
   ```
   **Re-route after marking (NON-NEGOTIABLE):** The pre-computed routing state is now stale because `.remediated` markers changed on-disk state. Re-run phase-detect to discover existing phases or new-work eligibility:
   ```bash
   FRESH_PD=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/phase-detect.sh 2>/dev/null)
   ```
   **Error guard:** If `FRESH_PD` is empty or contains `phase_detect_error=true`, display "⚠ Phase detection failed after marking milestones. Run `/vbw:vibe` again." and STOP.
   **Re-trigger guard:** If `FRESH_PD` still shows `milestone_uat_issues=true`, check whether `milestone_uat_slug` from `FRESH_PD` matches the slug that was just processed (the original `milestone_uat_slug` from the pre-computed state). If it matches, the marking failed for this milestone. Display "⚠ Some milestone UAT markers could not be written. Manually create `.remediated` files in the affected phase dirs, then run `/vbw:vibe`." and STOP (prevents infinite loop). If it does NOT match, a different older milestone has unresolved UAT. Let routing continue (the priority table will handle it, which may route to Milestone UAT Recovery for that other milestone).
   Otherwise, parse all routing variables from `FRESH_PD` (`next_phase_state`, `phase_count`, `config_auto_uat`, `has_unverified_phases`, etc.) and apply the **full priority table above** (priorities 1 to 11) to determine the correct mode. Route inline in the same turn. Key outcomes:

   **Verification and remediation outcomes:**
   - `needs_uat_remediation` → UAT Remediation mode
   - `needs_reverification` → Re-verify mode
   - `milestone_uat_issues=true` (different milestone) → Milestone UAT Recovery mode
   - `needs_verification` → Verify mode (auto_uat)

   **Planning and milestone outcomes:**
   - `needs_discussion` → Discuss mode
   - `needs_plan_and_execute` → Plan + Execute mode
   - `needs_execute` → Execute mode
   - `phase_count=0` → Scope mode
   - `all_done` → Archive mode
   This list is illustrative. Always defer to the full priority table. Do NOT stop and ask "What would you like to build?" when phases already exist.
5. If the user chooses "Not now": display "Skipping milestone UAT recovery. Run `/vbw:vibe` again when ready to address these issues." and STOP. No `.remediated` markers are written. The unresolved UAT issues will re-trigger on the next `/vbw:vibe` invocation.

### Mode: Plan

**Guard:** Initialized, roadmap exists, phase exists.
**Phase auto-detection:** First phase without PLAN.md. All planned: STOP "All phases planned. Specify phase: `/vbw:vibe --plan N`"
**Milestone path guard:** If `{phases_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot plan inside archived milestones." Archived milestones are read-only.

**Steps:**
1. **Parse args:** Phase number (optional, auto-detected), --effort (optional, falls back to config).
2. **Phase context:** Resolve CONTEXT path:
   ```bash
   CONTEXT_NAME=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh context "{phase-dir}")
   ```
   If `{phase-dir}/${CONTEXT_NAME}` exists, include it in Lead agent context. If not, proceed without it. Users who want context run `/vbw:discuss {NN}` first.
3. **Research persistence (REQ-08, graduated):** If effort != turbo:
   - Determine the next plan number `{MM}` and resolve artifact paths:
     ```bash
     RESOLVE_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh"
     NEXT_PLAN_NAME=$(bash "$RESOLVE_SCRIPT" plan "{phase-dir}")
     MM=$(echo "$NEXT_PLAN_NAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
     RESEARCH_NAME=$(bash "$RESOLVE_SCRIPT" phase-research "{phase-dir}")
     ```
    - Check for phase-wide research `{phase-dir}/${RESEARCH_NAME}` (preferred). If phase-wide does not exist, only treat historical `{phase-dir}/{NN}-01-RESEARCH.md` as brownfield phase research when no higher-numbered per-plan research exists. Compute it with: `OTHER_PLAN_RESEARCH=$(find "{phase-dir}" -maxdepth 1 -name "{NN}-[0-9][0-9]*-RESEARCH.md" ! -name "{NN}-01-RESEARCH.md" -print -quit 2>/dev/null); if [ -f "{phase-dir}/{NN}-01-RESEARCH.md" ] && [ -z "$OTHER_PLAN_RESEARCH" ]; then BROWNFIELD_RESEARCH="{phase-dir}/{NN}-01-RESEARCH.md"; fi`. If `$OTHER_PLAN_RESEARCH` is non-empty, leave `$BROWNFIELD_RESEARCH` empty because multiple per-plan research files remain distinct and do not count as phase-wide research.
   - **If neither exists:** If `config_context_compiler=true`, compile Scout context first: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} scout {phases_dir}`. Include `.context-scout.md` in the Scout prompt if produced, described as: "compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and phase operational context (goal, success criteria, matched requirements, conventions, changed files)."
     Spawn Scout agent to research the phase goal, requirements, and relevant codebase patterns. Scout writes its findings directly to the output path. Pass `<output_path>{phase-dir}/${RESEARCH_NAME}</output_path>` in the Scout prompt so Scout writes the file using its Write tool. After Scout completes, confirm the file exists (read first line). Resolve Scout model:
     ```bash
     if ! AGENT_SETTINGS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-settings.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json "{effort}"); then
       echo "$AGENT_SETTINGS" >&2
       exit 1
     fi
     eval "$AGENT_SETTINGS"
     SCOUT_MODEL="$RESOLVED_MODEL"
     SCOUT_MAX_TURNS="$RESOLVED_MAX_TURNS"
     SCOUT_REASONING="$RESOLVED_REASONING"
     ```
  Pass `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` to the Agent tool. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent or supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected, {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references. Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable. If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
  If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the phase research Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Use this payload prefix as the FIRST lines of the phase research Scout prompt:
  ```text
  <skill_activation>
  Call Skill('{relevant-skill-1}').
  Call Skill('{relevant-skill-2}').
  </skill_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  <skill_follow_up_files>
  {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
  </skill_follow_up_files>
  ```
  When no installed skills apply, use this prefix instead:
  ```text
  <skill_no_activation>
  Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
  </skill_no_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  ```
    - **If exists (phase-wide or legacy single-file brownfield):** Record the RESEARCH.md path (phase-wide `${RESEARCH_NAME}` or brownfield `${BROWNFIELD_RESEARCH}`) for inclusion in the Lead prompt. The Lead prompt MUST include the directive: `Read {research-path} for full research findings before planning.` Do NOT inline a summary of the research as a substitute. The Lead must read the file itself to get the complete, unabridged findings. Multiple per-plan research files are not phase-wide research. If no real phase-wide file exists, Scout should create `${RESEARCH_NAME}`. Lead may update the phase-wide RESEARCH.md if new information emerges.
   - **On failure:** Log warning, continue planning without research. Do not block.
    - **Authenticated live validation policy:** Scout may validate authenticated/private read-only APIs with verified-safe Bash helper scripts or curl wrappers after preflight. Public/anonymous HTTP validation uses WebFetch. Do not route authenticated API validation through WebFetch. If a check is unsafe, mutating, or cannot be verified as read-only, Scout must flag it with `⚠ REQUIRES AUTHENTICATED LIVE VALIDATION` for Dev/Debugger. Research that runs or defers live validation must include `## Live Validation Evidence` with `command_shape`, `exit_status`, `redacted_evidence`, `expected_shape`, `confidence`, and `limitations_or_deferred_reason`.
   - If effort=turbo: skip entirely.
4. **Research commit boundary (conditional):** If Scout was spawned in step 3 (new RESEARCH.md written):
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "research phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping research git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits RESEARCH.md if changed. Skipped when research was pre-existing or effort=turbo.
5. **Context compilation:** If `config_context_compiler=true`, run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} lead {phases_dir}`. Include `.context-lead.md` in Lead agent context if produced. When including it in the Lead prompt, describe its contents: "Read `.context-lead.md` for compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions) and operational context (phase goal, success criteria, matched requirements, active decisions, research findings)."
6. **Turbo shortcut:** If effort=turbo, skip Lead. Resolve the plan filename:
   ```bash
   TURBO_PLAN=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-artifact-path.sh plan "{phase-dir}")
   ```
   Read phase reqs from ROADMAP.md, create single lightweight plan as `${TURBO_PLAN}` in the phase directory.
7. **Other efforts:**
   - Resolve Lead model:
     ```bash
     if ! AGENT_SETTINGS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-settings.sh lead .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json "{effort}"); then
       echo "$AGENT_SETTINGS" >&2
       exit 1
     fi
     eval "$AGENT_SETTINGS"
     LEAD_MODEL="$RESOLVED_MODEL"
     LEAD_MAX_TURNS="$RESOLVED_MAX_TURNS"
     LEAD_REASONING="$RESOLVED_REASONING"
     ```
  **No team creation in Plan mode.** Scout (step 3) and Lead are sequential. Scout must complete before Lead starts (Lead reads the RESEARCH.md). Execute mode may later choose true team mode or serialized Dev subagents based on dependency-aware routing. `prefer_teams` is evaluated there, not here. Always spawn Lead as a plain subagent.
  - Before composing the Lead task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Lead prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  - If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the phase planning Lead. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  - Use this payload prefix as the FIRST lines of the phase planning Lead prompt:
    ```text
    <skill_activation>
    Call Skill('{relevant-skill-1}').
    Call Skill('{relevant-skill-2}').
    </skill_activation>
    After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
    <skill_follow_up_files>
    {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
    </skill_follow_up_files>
    ```
    When no installed skills apply, use this prefix instead:
    ```text
    <skill_no_activation>
    Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
    </skill_no_activation>
    After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
    ```
  - Also evaluate available MCP tools in your system context. If any MCP servers provide capabilities relevant to this planning task, use them to derive concise facts, docs, results, or recommended Dev-stage CLIs/skills for the Lead's task context. Dev subagents may call any MCP tools available in their runtime. No orchestrator-side gating is required.
   - Spawn vbw-lead as subagent via Agent tool with compiled context (or full file list as fallback).
  - **CRITICAL:** Set `subagent_type: "vbw:vbw-lead"` and `model: "${LEAD_MODEL}"` in the Agent tool invocation. If `LEAD_MAX_TURNS` is non-empty, also pass `maxTurns: ${LEAD_MAX_TURNS}`. If `LEAD_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

If `LEAD_REASONING` is non-empty, also pass `effort: "${LEAD_REASONING}"`. If `LEAD_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
   - **CRITICAL:** If a RESEARCH.md was found or created in step 3, include in the Lead prompt: `Read {research-path} for full research findings before planning.` where `{research-path}` is the per-plan or legacy path from step 3. The Lead must read the file itself. Do NOT substitute an inlined summary.
  - Required Lead guidance: "Execute may run plans as true team teammates or as serialized Dev subagents. Model real dependencies accurately. Same-wave plans must be genuinely independent and modify disjoint file sets. Linear chains are valid when dependencies are real. Do not invent independence to increase wave 1 size. Dependency-aware Execute uses teams only for real parallel delegate work, and false same-wave grouping can cause stale inputs or file conflicts."
   - **CRITICAL:** Include in the Lead prompt: `Use resolve-artifact-path.sh to compute plan filenames: bash ${RESOLVE_SCRIPT} plan "{phase-dir}" --plan-number {MM}` where `RESOLVE_SCRIPT` is the path from step 3. The script returns the canonical filename (e.g., `03-01-PLAN.md`). Call it once per plan with the plan number.
   - Display `◆ Spawning Lead agent...` -> `✓ Lead agent complete`.
8. **Normalize plan filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
    This catches any misnamed files written by Lead (e.g., turbo mode or models that bypass the PreToolUse block).
9. **Validate output:** Verify PLAN.md has valid frontmatter (phase, plan, title, wave, depends_on, must_haves) and tasks. Check wave deps acyclic.
10. **Present:** Update STATE.md (phase position, plan count, status=Planned). Resolve model profile:
   ```bash
   MODEL_PROFILE=$(jq -r '.model_profile // "quality"' .vbw-planning/config.json)
   ```
   Display Phase Banner with plan list, effort level, and model profile:
    ```text
   Phase {NN}: {name}
   Plans: {N}
     {plan}: {title} (wave {W}, {N} tasks)
   Effort: {effort}
   Model Profile: {profile}
   ```
11. **Planning commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "plan phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits planning artifacts if changed. `auto_push=always` pushes when upstream exists.
12. **Cautious gate (autonomy=cautious only):** STOP after planning. Ask "Plans ready. Execute Phase {NN}?" Other levels: auto-chain.

### Mode: Execute

**Execute-mode invariant:** Parallel execution is only valid when dependency-aware routing finds real parallel delegate work and the live tool set can create real team-scoped teammates. If routing selects serialized subagents, turbo/internal direct, or real team semantics cannot be established, execute mode must fall back to explicit non-team execution. Never simulate a team with background `Agent` spawns that lack `team_name`.

Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/references/execute-protocol.md` and follow its instructions.

This mode delegates entirely to the protocol file. **Orchestrator read-scope:** Do NOT read product source files. Your job is orchestration: read plans, check summaries, and spawn Dev for remaining work. If you need product-code understanding to route or sequence, delegate that to Dev.

Before reading:
**Step 0, pre-normalize filenames:**
    ```bash
    NORM_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{phase_dir}"
    fi
    ```
**Step 1, parse arguments:** Phase number (auto-detect if omitted), --effort, --skip-qa, --plan=NN.
2. **Run execute guards:**
   - Not initialized: STOP "Run /vbw:init first."
   - No PLAN.md in phase dir: STOP "Phase {NN} has no plans. Run `/vbw:vibe --plan {NN}` first."
   - All plans have SUMMARY.md: cautious/standard -> WARN + confirm. Confident/pure-vibe -> warn + auto-continue.
   - **Milestone path guard:** If `{phases_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot execute inside archived milestones." This prevents writing artifacts into shipped milestone directories.
3. **Compile context:** If `config_context_compiler=true`, run:
   - `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} dev {phases_dir} {plan_path}`
   - `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-context.sh {phase} qa {phases_dir}`
   Include compiled context paths in Dev and QA task descriptions. When referencing `.context-dev.md`, describe it as: "compiled context. It includes milestone scope decisions (decomposition rationale, scope boundaries, cross-phase key decisions). It also includes phase operational context (goal, conventions, active plan, research findings, changed files, code slices)." When referencing `.context-qa.md`, describe it as: "compiled context. It includes milestone scope decisions and phase verification context (success criteria, requirements, conventions to check)."
  If `TODO_SELECTED_JSON` already exists from the numbered-todo path and `DETAIL_STATUS=ok`, reuse the already-loaded detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.`

  Otherwise, if a ref hash was extracted during Input Parsing, load extended detail now:
   ```bash
  bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-details.sh get {hash}
   ```
  Parse the JSON output. If `status` is `"ok"`, include the detail in the Dev task description: `Extended context (from todo detail): {detail.context value}. Related files: {detail.files, comma-separated, or omit if empty}.` If `status` is `"not_found"` or `"error"`, run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/todo-lifecycle.sh detail-warning {hash}` and continue without detail. Do not block. This provides the executing agent with the rich context that motivated the work item.

Then Read the protocol file and execute Steps 2-5 as written.

### Mode: Verify

**Guard:** Initialized, phase has `*-SUMMARY.md` files.
No SUMMARY.md: STOP "Phase {NN} has no completed plans. Run /vbw:vibe first."
**Phase auto-detection:** First phase with `*-SUMMARY.md` but no canonical `*-UAT.md` (exclude `*-SOURCE-UAT.md` copies). All verified: STOP "All phases have UAT results. To re-run UAT for a specific phase, use `/vbw:vibe --verify {NN}`."

**Inline execution (NON-NEGOTIABLE):** UAT is an interactive conversation with the human user via AskUserQuestion CHECKPOINT prompts. Do NOT spawn a QA agent, Dev agent, or any subagent for UAT verification. Do NOT use TaskCreate to delegate UAT. The AskUserQuestion tool is only available to the orchestrator. Subagents cannot interact with the user, so delegating UAT to a subagent bypasses user input entirely and produces auto-written UAT files without human judgment. Run the verify.md CHECKPOINT loop directly in this conversation, the same way UAT Remediation coordinates its stages inline.

**Steps:**
1. Resolve the final target phase from the selected Verify route before compiling context. An explicit `--verify N` target wins. Otherwise, use the phase chosen by state-driven Verify or auto-UAT routing. Set `PHASE_DIR` to that exact active phase directory. If an upstream re-verification or QA-remediation transition in this turn already produced fresh verify context and UAT resume metadata for the same `PHASE_DIR`, reuse it. Otherwise run:
   ```bash
   SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
   L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
   P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
   PDIR="$PHASE_DIR"
   PD=""
   _PD_START_TS=$(date +%s 2>/dev/null || echo 0)
   _phase_detect_cache_fresh() {
     local m=""
     [ -f "$P" ] || return 1
     m=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
     [ -n "$m" ] || return 1
     [ "$m" -ge "$_PD_START_TS" ] 2>/dev/null
   }
   _phase_detect_cache_retryable() {
     [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]
   }
   REAL_R=$(cd "$L" 2>/dev/null && pwd -P) || REAL_R=""
   if [ -n "$REAL_R" ]
   then
     bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
   fi
   i=0
   while [ $i -lt 100 ]
   do
     if _phase_detect_cache_fresh
     then
       PD=$(cat "$P")
       break
     fi
     sleep 0.1
     i=$((i+1))
   done
   if _phase_detect_cache_retryable && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]
   then
     LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"
     i=0
     while [ $i -lt 100 ]
     do
       if _phase_detect_cache_fresh
       then
         PD=$(cat "$P")
         if ! _phase_detect_cache_retryable
         then
           break
         fi
       fi
       if mkdir "$LOCK" 2>/dev/null
       then
         PTMP="${P}.reader.$$.$RANDOM"
         PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
         if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]
         then
           printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
         fi
         rmdir "$LOCK" 2>/dev/null || true
         break
       fi
       sleep 0.1
       i=$((i+1))
     done
   fi
   [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && _phase_detect_cache_fresh && PD=$(cat "$P")
   if _phase_detect_cache_retryable
   then
     PD="phase_detect_error=true"
   fi
   VERIFY_CONTEXT=$(
     if [ "$PD" = "phase_detect_error=true" ]; then
       echo "verify_context=unavailable"
     elif [ -d "$PDIR" ] && [ -f "$L/scripts/compile-verify-context-for-uat.sh" ]; then
       bash "$L/scripts/compile-verify-context-for-uat.sh" "$PDIR" 2>/dev/null || echo "verify_context_error=true"
     else
       echo "verify_context_error=true"
     fi
   )
   UAT_RESUME=$(
     if [ -d "$PDIR" ] && [ -f "$L/scripts/extract-uat-resume.sh" ]; then
       bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=error"
     else
       echo "uat_resume=unavailable"
     fi
   )
   ```
   This runtime call is route-local. Do not compile verify context while parsing inputs or routing to Plan, Discuss, Scope, Archive, or any other non-Verify mode. Read `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/commands/verify.md` and use `VERIFY_CONTEXT` plus `UAT_RESUME` as the active protocol context. **Error guard:** If `VERIFY_CONTEXT` contains `verify_context_error=true` or `verify_context=unavailable`, display: "⚠ Verify context compilation failed. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-verify-context.sh .vbw-planning/phases/{NN}-{slug}` manually to debug." STOP. Do NOT improvise by scanning PLAN/SUMMARY files manually in this routed path.
2. Execute the verify.md steps inline in this conversation. Specifically: generate test scenarios (verify.md Step 4), then run the CHECKPOINT loop (verify.md Step 5) presenting one test at a time via AskUserQuestion and waiting for the user's response before proceeding to the next test. Use the active `VERIFY_CONTEXT` aggregation and `UAT_RESUME` metadata for the target phase. Pass the full UAT resume metadata through to the verify protocol, including `uat_resume_scenario`, `uat_resume_expected`, and summary-deviation source fields when present, so verify.md can ask the first resumed checkpoint without re-reading the UAT file. After each persisted answer, verify.md re-runs `extract-uat-resume.sh` and uses the refreshed deterministic fields for the next checkpoint. Do NOT read individual PLAN/SUMMARY files or scan-parse UAT.md for resume state.
3. Display results per verify.md output format.
4. **UAT Remediation Auto-Continuation:** This step only applies when verify.md emitted `remediation_continue=true` (which happens when `verify_scope=remediation` AND `status=issues_found` AND running in orchestrated mode from vibe.md). If `remediation_continue` was not set (first-time UAT, complete result, or standalone verify), skip this step entirely. The command ends after step 3.

   **Prepare the next remediation round through the safe transition helper:** Run `prepare-reverification.sh` exactly once for this transition. This helper finalizes and validates the active UAT before state mutation, applies the UAT remediation round cap, and then performs the next-round transition when allowed. A direct `needs-round` call is not the transition path here because it can mutate `.uat-remediation-stage` before the current UAT is terminal.

   ```bash
   _prepare_output=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/prepare-reverification.sh "{phase-dir}" 2>&1)
   _prepare_status=$?
   ```

   **If `prepare-reverification.sh` exits nonzero:** Display the helper output and STOP. Do not re-enter remediation with stale state.

   **If `_prepare_output` is empty or malformed:** STOP. Required recognized keys are one of `archived=...` or `skipped=...`. Valid `skipped` values are `already_archived`, `ready_for_verify`, or `cap_reached`. Malformed prepare output means the transition could not be proven safe.

   Parse the helper output:
   ```bash
   _archived=$(printf '%s\n' "$_prepare_output" | awk -F= '/^archived=/{print $2; exit}')
   _skipped=$(printf '%s\n' "$_prepare_output" | awk -F= '/^skipped=/{print $2; exit}')
   _round=$(printf '%s\n' "$_prepare_output" | awk -F= '/^round=/{print $2; exit}')
   _max_rounds=$(printf '%s\n' "$_prepare_output" | awk -F= '/^max_rounds=/{print $2; exit}')
   ```

   **If `_skipped=cap_reached`:** Display the cap-reached banner and STOP. Use `max_rounds={N}` from the helper output:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Reached maximum UAT remediation rounds ({_max_rounds}).
     Review issues manually or adjust max_uat_remediation_rounds
     in config.json.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Do NOT re-enter remediation. STOP.

   **Resolve the new round:** Prefer `round=` from `prepare-reverification.sh` when present. If `round=` is absent after a successful prepare, read the current round as a read-only fallback:
   ```bash
   if [ -z "$_round" ]; then
     _round=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/uat-remediation-state.sh current-round "{phase-dir}" 2>/dev/null)
   fi
   ```
   If `_round` is empty after both attempts, treat the prepare output as malformed and STOP.

   Display the transition banner and re-enter UAT Remediation mode inline:
   ```text
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
     Re-verification found {N} issue(s). Continuing to Round {_round}.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
   Where `{N}` is the issue count from the `remediation_continue` signal (`issues={N}`).
   Re-enter UAT Remediation mode (above) for the same `PHASE_DIR`. The prepare helper set the remediation state to `research` for the new round. The UAT Remediation mode's step 4 (`get-or-init`) will resume correctly from the `research` stage.

  **Continuation loop behavior:** The re-entered UAT Remediation mode chains into Verify mode after its execute stage completes (existing behavior). If that verification again finds issues, verify.md emits `remediation_continue=true` again, and this step 4 re-checks the UAT remediation round cap. This creates the auto-continuation loop, bounded only when `max_uat_remediation_rounds` resolves to a positive integer. The fallback remediation summary section remains the escape hatch when context window limits prevent continuation mid-loop.

### Mode: Add Phase

**Guard:** Initialized. Requires phase name in $ARGUMENTS.
Missing name: STOP "Usage: `/vbw:vibe --add <phase-name>`"

**Steps:**

**Phase setup (steps 1-4):**
**Step 1, codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
**Step 2, parse arguments:** Phase name (first non-flag arg), --goal (optional), slug (lowercase hyphenated).
**Step 3, next number:** Highest in ROADMAP.md + 1, zero-padded.
**Step 4, create directory:** `mkdir -p .vbw-planning/phases/{NN}-{slug}/`
5. **Problem research (conditional):** If $ARGUMENTS contain a problem description (bug report, feature request, multi-sentence intent) rather than just a bare phase name:
  **Scout settings:** Resolve Scout agent settings before spawning Scout. If helper resolution fails, warn and continue without explicit Scout model/maxTurns so this optional research step stays fail-open:
    ```bash
    SCOUT_MODEL=""
    SCOUT_MAX_TURNS=""
    if ! SCOUT_SETTINGS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/resolve-agent-settings.sh scout .vbw-planning/config.json /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/config/model-profiles.json); then
      echo "Warning: failed to resolve Scout agent settings; continuing without explicit Scout model/maxTurns." >&2
    else
      eval "$SCOUT_SETTINGS"
      SCOUT_MODEL="$RESOLVED_MODEL"
      SCOUT_MAX_TURNS="$RESOLVED_MAX_TURNS"
      SCOUT_REASONING="$RESOLVED_REASONING"
    fi
    ```
  **Scout spawn:** Spawn Scout agent (with `subagent_type: "vbw:vbw-scout"`) to research the problem in the codebase. If `SCOUT_MODEL` is non-empty, pass `model: "$SCOUT_MODEL"` to the Task invocation. If `SCOUT_MODEL` is empty, omit model so the default applies. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, omit maxTurns.

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes its findings directly using its Write tool. If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
    **Skill selection:** Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
    **Skill follow-up files:** If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the add-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
    **Scout prompt prefix:** Use this payload prefix as the FIRST lines of the add-phase Scout prompt:
      ```text
      <skill_activation>
      Call Skill('{relevant-skill-1}').
      Call Skill('{relevant-skill-2}').
      </skill_activation>
      After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
      <skill_follow_up_files>
      {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
      </skill_follow_up_files>
      ```
      When no installed skills apply, use this prefix instead:
      ```text
      <skill_no_activation>
      Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
      </skill_no_activation>
      After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
      ```
    **MCP context:** Also evaluate available MCP tools. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context.
    - After Scout completes, confirm the file exists (read first line).
   - Use Scout findings to write an informed phase goal and success criteria in ROADMAP.md.
   - On failure: log warning, write phase goal from $ARGUMENTS alone. Do not block.
   - **This eliminates duplicate research.** Plan mode step 3 checks for existing RESEARCH.md and skips Scout if found.
6. Update ROADMAP.md: append phase list entry, append Phase Details section (using Scout findings if available), add progress row.
7. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
8. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning`
9. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "add phase {NN}-{slug}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
10. Present: Phase Banner with position, goal. Checklist for roadmap update + dir creation. Next Up: `/vbw:vibe --discuss` or `/vbw:vibe --plan`.

### Mode: Insert Phase

**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/vbw:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
2. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated).
3. Identify renumbering: all phases >= position shift up by 1.
4. Renumber dirs in REVERSE order: rename dir {NN}-{slug} -> {NN+1}-{slug}, rename internal PLAN/SUMMARY files, update `phase:` frontmatter, update `depends_on` references.
5. Create dir: `mkdir -p .vbw-planning/phases/{NN}-{slug}/`
6. **Problem research (conditional):** If $ARGUMENTS contain a problem description, spawn Scout with `subagent_type: "vbw:vbw-scout"` to research the codebase. For this non-team spawn, omit `team_name`, `run_in_background`, `isolation`, and worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). `name` is optional label-only metadata and must never be used for routing, lifecycle state, or team semantics. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references. Also evaluate available MCP tools. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context. After Scout completes, confirm the file exists (read first line). This prevents Plan mode from duplicating the research.
  If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the insert-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Use this payload prefix as the FIRST lines of the insert-phase Scout prompt:
  ```text
  <skill_activation>
  Call Skill('{relevant-skill-1}').
  Call Skill('{relevant-skill-2}').
  </skill_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  <skill_follow_up_files>
  {If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning and replace this block with the emitted absolute follow-up file paths. Omit this block when the helper prints nothing.}
  </skill_follow_up_files>
  ```
  When no installed skills apply, use this prefix instead:
  ```text
  <skill_no_activation>
  Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.
  </skill_no_activation>
  After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  ```
7. Update ROADMAP.md: insert new phase entry + details at position (using Scout findings if available), renumber subsequent entries/headers/cross-refs, update progress table.
8. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
9. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning --inserted {position}` (where {position} is the insert position from step 2).
10. **Phase mutation commit boundary (conditional):**
    ```bash
   PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
    if [ -f "$PG_SCRIPT" ]; then
      bash "$PG_SCRIPT" commit-boundary "insert phase {NN}-{slug} at position {position}" .vbw-planning/config.json
    else
      echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
    fi
    ```
    Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
11. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Remove Phase

**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/vbw:vibe --remove <phase-number>`"
Not found: STOP "Phase {NN} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {NN} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {NN}."

**Steps:**
1. Parse args: extract phase number, validate, look up name/slug.
2. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
3. Remove dir: `rm -rf .vbw-planning/phases/{NN}-{slug}/`
4. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
5. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
6. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
7. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning --removed {NN}` (where {NN} is the removed phase number from step 1).
8. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "remove phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.

### Mode: Archive

**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/vbw:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Hard UAT gate (always, non-bypassable):**
Before any audit/bypass handling, run:
```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/archive-uat-guard.sh
```
If exit code is 2: STOP. Unresolved UAT (active or milestone) blocks archive regardless of `--skip-audit` or `--force`.

**Hard state-consistency gate (always, non-bypassable):**
After the UAT gate passes, run:
```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/verify-state-consistency.sh .vbw-planning --mode archive
```
If exit code is non-zero: STOP. If exit code is 2, state misalignment at archive means the archived milestone record may be unreliable. Phase counts, completion markers, or project metadata could be inconsistent. Surface the JSON output's `failed_checks` array so the user can fix the drift before retrying. For any other non-zero exit, treat the verifier as failed unexpectedly and do not proceed with archive.

**Pre-gate audit (unless --skip-audit or --force):**
Run 7-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: authoritative QA verification exists and is fresh PASS. Missing=WARN, failed=FAIL. After QA remediation reaches `done`, the authoritative artifact is the round-scoped `R{RR}-VERIFICATION.md`. The frozen phase-level VERIFICATION.md must not be reused.
6. UAT status: any `*-UAT.md` with `status: issues_found` = FAIL. Unresolved UAT issues must be remediated before archiving.
7. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. **Derive milestone slug deterministically (do NOT invent a slug):**
   ```bash
   MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)
   ```
  This reads ROADMAP.md phase names and outputs a numbered kebab-case slug (e.g., `01-setup-api-layer`). Keep this milestone slug separate from any custom git tag passed via `--tag`. **Never use a hardcoded slug like "default". Always use the script output.**
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `rolling_summary=true` in config:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-rolling-summary.sh \
     .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `rolling_summary=false`: skip.
5. Archive: `mkdir -p .vbw-planning/milestones/{SLUG}`. Move ROADMAP.md, STATE.md, and phases/ to milestones/{SLUG}/. If `.vbw-planning/CONTEXT.md` exists, move it to milestones/{SLUG}/CONTEXT.md. Use the **Write** tool (not Bash) to create `.vbw-planning/milestones/{SLUG}/SHIPPED.md`. This ensures PostToolUse hooks fire for artifact tracking. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/persist-state-after-ship.sh \
     .vbw-planning/milestones/{SLUG}/STATE.md .vbw-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "archive milestone {SLUG}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-VBW content. Only replace VBW-managed sections, and keep the user's own sections intact.
9b. Post-archive hook (non-blocking): after successful archive completion, run:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/post-archive-hook.sh "{SLUG}" ".vbw-planning/milestones/{SLUG}" "{tag}" .vbw-planning/config.json
   ```
   Use the tag selected in step 8, or an empty third argument when `--no-tag` was used. Repos without `hooks.post_archive` configured no-op through the dispatcher. Any warnings are non-blocking.
10. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.

### Pure-Vibe Phase Loop

After Execute mode completes (autonomy=pure-vibe only): if more unbuilt phases exist, auto-continue to next phase (Plan + Execute). Loop until `next_phase_state=all_done` or error. Other autonomy levels: STOP after phase.

**CRITICAL: Between iterations:** Before starting the next phase's Plan mode, inspect the prior Execute delegation marker and state. Only when the prior run persisted `delegation_mode=team` with a real `TEAM_NAME`, follow the team-shutdown contract in `references/subagent-contracts.md`.

Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.

After the shared shutdown completes, run Post-shutdown residual cleanup. The team config directory is removed automatically when the session exits. There is no TeamDelete call. If the prior run used serialized subagents, turbo or internal direct execution, or fallback non-team mode, rely on completed subagent or direct execution plus the cleared delegation state. Do not send team shutdown messages without a real team.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md for all output except Verify mode (UAT files use plain markdown. Do NOT read brand-essentials during verification).

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

!`SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"; i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do sleep 0.1; i=$((i+1)); done; bash "$L/scripts/suggest-compact.sh" execute 2>/dev/null || true`
