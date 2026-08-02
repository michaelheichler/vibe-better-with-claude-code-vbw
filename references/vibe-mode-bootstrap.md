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
