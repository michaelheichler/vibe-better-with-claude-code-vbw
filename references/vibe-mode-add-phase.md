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
      echo "Warning: failed to resolve Scout agent settings. Continuing without explicit Scout model/maxTurns." >&2
    else
      eval "$SCOUT_SETTINGS"
      SCOUT_MODEL="$RESOLVED_MODEL"
      SCOUT_MAX_TURNS="$RESOLVED_MAX_TURNS"
      SCOUT_REASONING="$RESOLVED_REASONING"
    fi
    ```
  **Scout spawn:** Spawn Scout agent (with `subagent_type: "${SCOUT_AGENT_NAME}"`) to research the problem in the codebase. If `SCOUT_MODEL` is non-empty, pass `model: "$SCOUT_MODEL"` to the Task invocation. If `SCOUT_MODEL` is empty, omit model so the default applies. If `SCOUT_MAX_TURNS` is non-empty, also pass `maxTurns: ${SCOUT_MAX_TURNS}`. If `SCOUT_MAX_TURNS` is empty, omit maxTurns.

  Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

  Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes its findings directly using its Write tool. If `SCOUT_REASONING` is non-empty, also pass `effort: "${SCOUT_REASONING}"`. If `SCOUT_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
  **Skill selection:** Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.
  **Skill follow-up files:** If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the add-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
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
