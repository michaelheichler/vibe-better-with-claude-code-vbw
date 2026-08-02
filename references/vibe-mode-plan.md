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
     Detect team capability and read the team preference:
     ```bash
     TEAM_CAPABILITY_OUTPUT=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/detect-team-capability.sh)
     TEAM_CAPABILITY=$(printf '%s\n' "$TEAM_CAPABILITY_OUTPUT" | grep '^team_capability=' | head -1 | cut -d= -f2)
     PREFER_TEAMS=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/normalize-prefer-teams.sh .vbw-planning/config.json 2>/dev/null || echo "auto")
     ```
     Resolve Scout model:
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
     - **Multi-stream research:** Use this path only when `TEAM_CAPABILITY=available`, `PREFER_TEAMS` is not `never`, and the phase goal decomposes into 2-4 genuinely distinct research facets. Judge facets from the phase goal, choosing only applicable areas such as separate codebase areas, external documentation or APIs, and testing or verification approaches. Do not manufacture facets to enable parallelism.
       Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/clean-stale-teams.sh 2>/dev/null || true` before spawning. Agent teams are experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1). The team forms when the first teammate is spawned via the Agent tool. There is no TeamCreate setup step. Spawn one Scout teammate per facet via the Agent tool so the 2-4 Scouts run in parallel. Set `team_name="vbw-plan-research-{NN}"`, `description="Phase {NN} research"`, `subagent_type: "vbw:vbw-scout"`, and `model: "${SCOUT_MODEL}"` on every Agent call. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If it is empty, omit maxTurns. If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, omit effort because the resolved model rejects it. Do not pass `isolation` or worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). Each prompt must focus on exactly one facet while retaining the phase goal, requirements, relevant compiled context, live-validation policy, and MCP guidance. Apply the skill evaluation and payload-prefix rules below independently to every Scout prompt. Give each Scout a unique slug and `<output_path>{phase-dir}/{NN}-RESEARCH-{facet-slug}.md</output_path>`.
       Wait for all Scouts to return and confirm each facet file exists by reading its first line. Synthesize the available facet files into canonical `{phase-dir}/${RESEARCH_NAME}` by merging findings, noting contradictions, and ranking conclusions by confidence. Leave the facet files in place as provenance. Send `shutdown_request` to every teammate, wait for each `shutdown_response`, then run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/clean-stale-teams.sh 2>/dev/null || true` before continuing. The team config directory is removed automatically when the session exits. There is no TeamDelete call.
     - **Single-Scout fallback:** Use this path when team capability is unavailable, `PREFER_TEAMS=never`, or the phase goal is genuinely single-faceted. Spawn Scout agent to research the phase goal, requirements, and relevant codebase patterns. Scout writes its findings directly to the output path. Pass `<output_path>{phase-dir}/${RESEARCH_NAME}</output_path>` in the Scout prompt so Scout writes the file using its Write tool. After Scout completes, confirm the file exists (read first line).

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

  For the single-Scout fallback, pass `subagent_type: "vbw:vbw-scout"` and `model: "${SCOUT_MODEL}"` to the Task tool. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited). If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, omit effort because the resolved model rejects it. `name` is optional label-only metadata. Never use it for routing, lifecycle state, or team semantics. For either path, before composing each Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent or supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected, {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references. Also evaluate available MCP tools in your system context. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context so it prioritizes those tools over generic WebSearch/WebFetch where applicable.
  If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning each phase research Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in that Scout payload. Otherwise omit that block.
  Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
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
  **Team creation in Plan mode is limited to the step 3 RESEARCH fan-out.** All Scouts must complete and the orchestrator must write canonical RESEARCH.md before Lead starts. Lead is always a single plain subagent. Execute mode may later choose true team mode or serialized Dev subagents based on dependency-aware routing and its own `prefer_teams` evaluation.
  - Before composing the Lead task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent or supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Lead prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected, {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  - If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the phase planning Lead. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  - Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
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
