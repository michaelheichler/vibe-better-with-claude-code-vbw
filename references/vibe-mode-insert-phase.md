**Guard:** Initialized. Requires position + name.
Missing args: STOP "Usage: `/vbw:vibe --insert <position> <phase-name>`"
Invalid position (out of range 1 to max+1): STOP with valid range.
Inserting before completed phase: WARN + confirm.

**Steps:**
1. **Codebase context:** If `.vbw-planning/codebase/META.md` exists, read ARCHITECTURE.md and CONCERNS.md (whichever exist) from `.vbw-planning/codebase/`. Use this to inform phase goal scoping and identify relevant modules/services.
2. Parse args: position (int), phase name, --goal (optional), slug (lowercase hyphenated). Format the position as a zero-padded two-digit `{NN}` (for example, position 3 is `03`).
3. Identify renumbering: all phases >= position shift up by 1.
4. Renumber dirs in REVERSE order: rename dir `{NN}-{slug}` -> `{NN+1}-{slug}`, rename every number-prefixed internal artifact (`PLAN`, `SUMMARY`, `RESEARCH`, `CONTEXT`, `UAT`, `VERIFICATION`, and per-plan `{NN}-{MM}-*` files), update `phase:` frontmatter, update `depends_on` references.
5. Create dir: `mkdir -p .vbw-planning/phases/{NN}-{slug}/` (with `{NN}` zero-padded).
6. **Problem research (conditional):** If $ARGUMENTS contain a problem description, spawn Scout with `subagent_type: "${SCOUT_AGENT_NAME}"` to research the codebase. For this non-team spawn, omit `team_name`, `run_in_background`, `isolation`, and worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). `name` is optional label-only metadata and must never be used for routing, lifecycle state, or team semantics. Pass `<output_path>{phase-dir}/{NN}-RESEARCH.md</output_path>` in the Scout prompt so Scout writes the file directly. Before composing the Scout task description, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for this task, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context, not just the single most direct skill. The Scout prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected. {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references. Also evaluate available MCP tools. If any MCP servers provide documentation, search, or data retrieval capabilities relevant to this research, note them in the Scout's task context. After Scout completes, confirm the file exists (read first line). This prevents Plan mode from duplicating the research.
  If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning the insert-phase Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.
  Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.
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
