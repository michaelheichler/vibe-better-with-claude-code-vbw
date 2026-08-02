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
   - **Milestone path guard:** If `{phase_dir}` contains `.vbw-planning/milestones/`, STOP "Cannot execute inside archived milestones." This prevents writing artifacts into shipped milestone directories.
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
