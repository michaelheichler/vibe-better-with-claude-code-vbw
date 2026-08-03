# VBW Execution Protocol

Loaded on demand by /vbw:vibe Execute mode. Not a user-facing command.

## Runtime Plugin Root Resolution (required once per Execute run)

Resolve and validate `VBW_PLUGIN_ROOT` once before running script commands below:

```bash
SESSION_LINK="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"
RESOLVER="${SESSION_LINK}/scripts/resolve-plugin-root.sh"
if [ ! -f "$RESOLVER" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
    RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
  else
    echo "VBW: plugin root resolution failed" >&2
    exit 1
  fi
fi
VBW_PLUGIN_ROOT=$(bash "$RESOLVER") || exit 1
```

All runtime script invocations below assume `VBW_PLUGIN_ROOT` is set.

Before spawning any subagent, read `${VBW_PLUGIN_ROOT}/references/subagent-contracts.md` for the canonical subagent contracts.

### Step 2: Load plans and detect resume state

**Orchestrator read-scope boundary:** You may ONLY read planning/state artifacts: `*-PLAN.md`, `*-SUMMARY.md`, `*-RESEARCH.md`, `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md`, `.execution-state.json`, `.context-*.md`, `config.json`, and `.vbw-planning/` metadata. Do NOT read product source files (application code, tests, configs outside `.vbw-planning/`). If you need to understand product code to make a routing or sequencing decision, that understanding must come from Dev: delegate it via a task.

1. Glob `*-PLAN.md` in phase dir. Read each plan's YAML frontmatter.
2. Check existing SUMMARY.md files: a plan is progression-complete for Execute dependency routing only when its SUMMARY has `status: complete|partial`. Strict phase/build completion still requires `complete|completed`. A SUMMARY with `status: pending` or no status field is NOT progression-complete.
3. `git log --oneline -20` for committed tasks (crash recovery).
4. Build remaining plans list. If `--plan=NN`, filter to that plan.
4b. **Worktree isolation (REQ-WORKTREE):** If `worktree_isolation` is not `"off"` in config, worktrees remain per-plan but are created/refreshed just in time when a plan becomes runnable. Do **not** create every remaining plan worktree up front. a dependent serialized plan must start from a branch that includes prerequisite output.
   ```bash
   WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' .vbw-planning/config.json 2>/dev/null || echo "off")
   ```
  For each plan when it becomes runnable in Step 3:
  - Merge or otherwise make completed prerequisite worktree output visible before creating the dependent plan's worktree.
  - Create/refresh worktree: `WPATH=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-create.sh" {phase} {plan} 2>/dev/null || echo "")`. If `WPATH` is empty, log warning and continue without worktree for this plan.
  - If `WPATH` is non-empty: update that plan's `worktree_path` in `.execution-state.json`, regenerate `WTARGET=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-target.sh" "$WPATH" 2>/dev/null || echo "{}")`, and register `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" set "dev-{plan}" "$WPATH" {phase} {plan} 2>/dev/null || true` before spawning Dev.
  - After merge/cleanup for that plan, clear `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" clear "dev-{plan}" 2>/dev/null || true`.
   When `worktree_isolation="off"`: skip this step silently.
5. Partially-complete plans: note resume-from task number.
6. **Crash recovery:** If `.vbw-planning/.execution-state.json` exists with `"status": "running"`, update plan statuses to match current SUMMARY.md state.
   - **Event Recovery (REQ-17):** If `event_recovery=true` in config, attempt event-sourced recovery first:
  `RECOVERED=$(bash "${VBW_PLUGIN_ROOT}/scripts/recover-state.sh" {phase} 2>/dev/null || echo "{}")`
     If non-empty and has `plans` array, use recovered state as the baseline instead of the stale execution-state.json. This provides more accurate status when execution-state.json was not written (crash before flush).
6b. **Generate correlation_id:** Generate a UUID for this phase execution:
   - If `.vbw-planning/.execution-state.json` already exists and has `correlation_id` (crash-resume):
     preserve it: `CORRELATION_ID=$(jq -r '.correlation_id // ""' .vbw-planning/.execution-state.json 2>/dev/null || echo "")`
   - Otherwise generate fresh:
     `CORRELATION_ID=$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "$(date -u +%s)-${RANDOM}${RANDOM}")`

7. **Write execution state** to `.vbw-planning/.execution-state.json`. First resolve `SESSION_ID=$(printf '%s' "${CLAUDE_SESSION_ID:-}")`, then record that exact value:
```json
{
  "phase": N, "phase_name": "{slug}", "status": "running",
  "session_id": "{SESSION_ID}",
  "started_at": "{ISO 8601}", "wave": 1, "total_waves": N,
  "correlation_id": "{UUID}",
  "effort": "{effective effort}", "phase_effort": "{configured phase effort}",
  "plans": [{"id": "NN-MM", "title": "...", "wave": W, "status": "pending|complete|partial|failed"}]
}
```
Set plan status from verified SUMMARY.md frontmatter: `complete|completed` → `"complete"`, `partial` → `"partial"`, `failed` → `"failed"`, others → `"pending"`. `phase_effort` preserves the configured phase effort. `effort` may be temporarily changed to `turbo` or internal `direct` for segment-local guard visibility and restored before the next non-direct segment.

**Task list hygiene (crash-resume):** When resuming execution (`.execution-state.json` already existed), plans that are already `"complete"` were finished in a prior session. Immediately mark those plans as completed in your task list: do NOT leave them as not-started or in-progress. Only pending plans should be active in your task list.

7b. **Export correlation_id:** Set `VBW_CORRELATION_ID={CORRELATION_ID}` in the execution environment
    so log-event.sh can fall back to it if .execution-state.json is temporarily unavailable.
    Log a confirmation: `◆ Correlation ID: {CORRELATION_ID}`

8. **Event Log (REQ-16, graduated, always-on):**
  - Log phase start: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" phase_start {phase} 2>/dev/null || true`

9. **Snapshot Resume (REQ-18):** If `snapshot_resume=true` in config:
   - On crash recovery (execution-state.json exists with `"status": "running"`): attempt restore:
  `SNAPSHOT=$(bash "${VBW_PLUGIN_ROOT}/scripts/snapshot-resume.sh" restore {phase} {preferred-role} 2>/dev/null || echo "")`
   - If snapshot found, log: `✓ Snapshot found: ${SNAPSHOT}`: use snapshot's `recent_commits` to cross-reference git log for more reliable resume-from detection.

10. **Schema Validation (REQ-17, graduated, always-on):**
   - Validate each PLAN.md frontmatter before execution:
     `VALID=$(bash "${VBW_PLUGIN_ROOT}/scripts/validate-schema.sh" plan {plan_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Plan {NN-MM} schema: ${VALID}`: continue execution (advisory only).
   - Log to metrics: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" schema_check {phase} {plan} result=$VALID 2>/dev/null || true`

11. **Cross-phase deps (PWR-04):** For each plan with `cross_phase_deps`:
   - Verify referenced plan's SUMMARY.md exists with `status: complete`
   - If artifact path specified, verify file exists
   - Unsatisfied → STOP: "Cross-phase dependency not met. Plan {id} depends on Phase {P}, Plan {plan} ({reason}). Status: {failed|missing|not built}. Fix: Run /vbw:vibe {P}"
   - All satisfied: `✓ Cross-phase dependencies verified`
   - No cross_phase_deps: skip silently

### Step 3: Resolve Execute routing and run segments

**Smart Routing (REQ-15):** If `smart_routing=true` in config, build a transient route map before selecting team/subagent mode:
```bash
ROUTE_MAP=.vbw-planning/.cache/execute-route-map.json
mkdir -p .vbw-planning/.cache
printf '{"plans":{}}\n' > "$ROUTE_MAP"
```
- For each remaining plan, assess risk before team selection:
  ```bash
  RISK=$(bash "${VBW_PLUGIN_ROOT}/scripts/assess-plan-risk.sh" {plan_path} 2>/dev/null || echo "medium")
  TASK_COUNT=$(grep -c '^### Task [0-9]' {plan_path} 2>/dev/null || echo "0")
  ```
- If `RISK=low` AND `TASK_COUNT<=3` AND effort is not `thorough`: write route `turbo` for that plan in `$ROUTE_MAP` and log numeric metrics:
  `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=turbo 2>/dev/null || true`
- Otherwise: omit the route-map entry or write route `delegate`. log non-turbo delegated metrics as:
  `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" smart_route {phase} {plan} risk=$RISK tasks=$TASK_COUNT routed=team 2>/dev/null || true`
- Internal route `direct` is only for explicit route-map entries supplied by existing guard/delegation machinery. Do not add a user-facing `direct` phase effort.
- On script error: leave the plan unlisted in the route map. missing entries default to delegate.

**Dependency-aware routing helper:** After `.execution-state.json` and the optional route map exist, resolve routing before writing `.delegated-workflow.json`:
```bash
ROUTE_ARGS=()
[ -f .vbw-planning/.cache/execute-route-map.json ] && ROUTE_ARGS=(--route-map .vbw-planning/.cache/execute-route-map.json)
ROUTING=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-execute-delegation-mode.sh" \
  --phase-dir "{phase_dir}" \
  --config .vbw-planning/config.json \
  --execution-state .vbw-planning/.execution-state.json \
  "${ROUTE_ARGS[@]}" \
  --segments)
```
The helper canonicalizes `prefer_teams` with `normalize-prefer-teams.sh`, computes remaining dependency waves from the execution state and plan frontmatter, and emits compact JSON (`delegation_mode`, `requested_mode`, `reason`, `max_parallel_width`, `delegate_count`, route-specific plan IDs, and ordered `segments`).
If the helper exits non-zero or returns `reason=invalid_dependency_graph`, stop before spawning agents and surface the diagnostic. Valid serial graphs are not errors: `prefer_teams=auto` with `max_parallel_width <= 1` uses serialized Dev subagents.

Team request policy from helper output:
- `prefer_teams='always'`: request team mode for delegate-eligible work regardless of dependency width. it does not override phase-level turbo, smart-routed turbo, or explicit internal-direct segments.
- `prefer_teams='auto'`: request team mode only when dependency analysis finds real parallel delegate work (`max_parallel_width > 1`).
- `prefer_teams='never'`: request explicit non-team mode.
- Unknown normalized values preserve the raw value, use `delegation_mode=subagent`, and report `unknown_prefer_teams:<value>`.

Determine whether **real team semantics** are available before spawning anything. Real team semantics require CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 and a live Agent tool that spawns teammates. `team_name` is accepted but ignored, so it is not a capability signal. When teams are unavailable, fall back to plain sequential subagent Agent calls.
- If the live tool set only supports plain background spawns (for example `Agent` with `run_in_background: true` and no teammate `name`), then real team semantics are **NOT** available.
- **Plain background `Agent` spawns without team semantics are NOT an agent team. Do NOT use them as a substitute for team mode.**

Process `ROUTING.segments[]` in order. For each segment, extract `route`, `plan_ids`, `effort`, `delegation_mode`, and optional `team_name` from the helper output. Before any direct, turbo, fallback, or serialized subagent segment starts, check the current delegation marker. If a live execute marker has `delegation_mode=team`, follow the team-shutdown contract in `references/subagent-contracts.md` before continuing.

Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.

After the shared shutdown completes, run Post-shutdown residual cleanup. The team config directory is removed automatically when the session exits. There is no TeamDelete call. Clear the marker only after teardown completes. Do not start a non-team segment while `.delegated-workflow.json` still reports a live team marker.

Branch each segment into exactly one runtime path and persist that segment's actual mode **before the first spawn or orchestrator product-file write**:

1. **True team mode**
   - Use this path only when the helper segment has `delegation_mode=team` **and** real team semantics are available.
   - **Pre-spawn stale-team cleanup** (remove orphaned VBW team directories from prior sessions before spawning the first teammate):
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true
     ```
   - Set `TEAM_NAME` from the segment (`team_name`) or default to `"vbw-phase-{NN}"` for VBW's own bookkeeping. The platform's real team name is session-derived ("session-" + first 8 chars of the session id). `team_name` on `Agent` is accepted but ignored, so it is not a capability signal.
   - Agent teams are experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1). The team forms when the first teammate is spawned via the Agent tool. There is no TeamCreate setup step.
   - Persist the actual runtime mode:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} team "$TEAM_NAME"
     ```
   - All Dev and QA teammates below MUST carry `team_name: "$TEAM_NAME"` plus `name: "dev-{MM}"` (from plan number) or `name: "qa"` / `name: "qa-wave{W}"` on the live spawn call. No plain task-management `TaskCreate` may happen after the team marker is set unless it carries the selected `TEAM_NAME` and teammate `name`.

2. **Explicit non-team mode**
   - Use this path when `prefer_teams='never'`, `prefer_teams='auto'` with `max_parallel_width <= 1`, unknown `prefer_teams`, no delegate-eligible plans, segment route `turbo`/internal `direct`, or team-tooling-unavailable fallback.
   - For serialized delegate segments (`route=delegate`, `delegation_mode=subagent`), persist the actual runtime mode as subagent, do not form an agent team (do not spawn teammates), spawn one Dev subagent, and wait for completion before the next spawn:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} subagent
     ```
   - For `turbo` or internal `direct` segments (`delegation_mode=direct`), update `.execution-state.json.effort` to `turbo` or `direct` before orchestrator product-file writes. keep `phase_effort` unchanged, persist the actual runtime mode as direct, and restore `.execution-state.json.effort` to `phase_effort` before the next non-direct segment:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} direct
     ```
   - **Do NOT use `run_in_background: true` to simulate parallelism in non-team mode.**

3. **Team-tooling-unavailable fallback**
   - Use this path when the helper requests `delegation_mode=team` but the live tool set cannot express real team semantics.
   - Display: `⚠ Agent Teams not enabled: using non-team mode`
   - Persist the fallback runtime mode:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" set execute {segment_effort} subagent
     ```
   - Do not form an agent team (do not spawn teammates). Use plain sequential subagent Agent calls, continuing in explicit non-team mode.
   - **Do NOT preserve “parallelism” by launching multiple background `Agent` spawns without `team_name`.**

After each segment completes, verify each plan's SUMMARY.md through Step 3c and write the verified status (`complete`, `partial`, or `failed`) into `.execution-state.json`. Only `complete|partial` unlock dependents. Re-run the helper against the updated execution state until no pending plans remain.

**Delegation directive (all except Turbo):**
You are the team LEAD. NEVER implement tasks yourself.
- Delegate ALL implementation to Dev teammates via TaskCreate
- NEVER Write/Edit files in a plan's `files_modified`: only state files: STATE.md, ROADMAP.md, .execution-state.json, SUMMARY.md
- If Dev fails: guidance via SendMessage, not takeover. If all Devs unavailable: create new Dev.
- **Subagent return handling (non-team model):** When a Dev subagent Task returns, inspect the result immediately:
  1. **platform/tool provisioning failure:** Follow the no-tool circuit breaker in `references/subagent-contracts.md`. Stop immediately, surface the provisioning blocker, and do not consume the normal retry budget.

    No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  2. **blocker_report received:** Read the blocker details. If the blocker is a tool precondition error (e.g., "File has not been read yet"), amend the task description with explicit "Read {file} first, then edit" and re-spawn once. If the blocker is a validation contradiction or empty-result failure, do NOT blindly re-spawn, the same subagent prompt will hit the same wall. Instead: (a) verify the validation target yourself (run the bash/curl command Lead can execute), (b) if the data truly contradicts expectations, update the plan task to reflect reality, (c) re-spawn with the corrected task.
  3. **Task returned without SUMMARY.md or with incomplete work:** Check what the Dev actually accomplished (git log, file changes). If partial progress was made, spawn a new Dev with "Continue from where the previous Dev stopped, files X, Y already modified, remaining work is Z." If zero progress, check whether the task description was ambiguous or missing context and re-spawn with clarification.
  4. **Max retry: 2 re-spawns per plan.** After 2 failed Dev spawns for the same plan, stop and surface the blocker to the user: "Dev agent failed {N} times on plan {plan_id}. Last blocker: {details}. Manual intervention needed."
- At Turbo (or smart-routed to turbo): no team: Dev executes directly.
- **Runtime enforcement:** This directive is structurally enforced by the `file-guard.sh` PreToolUse hook. When `.execution-state.json` has `status: running` and effort is not turbo/direct, the hook blocks product-file Write/Edit from the orchestrator. Two bypass mechanisms exist:
  - **Subagent model:** `.active-agents/{session_id}/active-agent-count` (written by `agent-start.sh`): when a safe Claude session id is available and the current session count is > 0, a VBW subagent is running in this session and the write is allowed. Session-local `active-agent-roles` drives Scout-safe fallback for ambiguous calls in the same session only, preventing cross-terminal/session role leakage. Root `.active-agent*` files are aggregate display/legacy fallback state and are used for enforcement only when no safe session id is available.
  - **Execute team mode:** `scripts/delegated-workflow.sh set execute {effort} team {team_name}` records true team mode before teammate spawns. `file-guard.sh` bypasses only when that execute marker is active. This avoids assuming that `prefer_teams` or background `Agent` spawns automatically imply a real team.
  - When neither bypass applies, the write is treated as an orchestrator action and blocked. Planning/state artifacts (`.vbw-planning/*`, `STATE.md`, `SUMMARY.md`, etc.) remain exempt.

**Monorepo Routing (REQ-17):** If `monorepo_routing=true` in config:
- Before context compilation, detect relevant package paths:
  `PACKAGES=$(bash "${VBW_PLUGIN_ROOT}/scripts/route-monorepo.sh" {phase_dir} 2>/dev/null || echo "[]")`
- If non-empty array (not `[]`): pass package paths to context compilation for scoped file inclusion.
  Log: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" monorepo_route {phase} packages=$PACKAGES 2>/dev/null || true`
- If empty or error: proceed with default (full repo) context compilation.

**Control Plane Coordination (REQ-05):** If `${VBW_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
- **Once per plan (before first task):** Run the `full` action to generate contract and compile context:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" full {phase} {plan} 1 \
    --plan-path={plan_path} --role=dev --phase-dir={phase-dir} 2>/dev/null || echo '{"action":"full","steps":[]}')
  ```
  Extract `contract_path` and `context_path` from result for subsequent per-task calls.
- **Before each task:** Run the `pre-task` action:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" pre-task {phase} {plan} {task} \
    --plan-path={plan_path} --task-id={phase}-{plan}-T{task} \
    --claimed-files={files_from_task} 2>/dev/null || echo '{"action":"pre-task","steps":[]}')
  ```
  If the result contains a gate failure (step with `status=fail`), treat as gate failure and follow existing auto-repair + escalation flow.
- **After each task:** Run the `post-task` action:
  ```bash
  CP_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" post-task {phase} {plan} {task} \
    --task-id={phase}-{plan}-T{task} 2>/dev/null || echo '{"action":"post-task","steps":[]}')
  ```
- If `control-plane.sh` does NOT exist: fall through to the individual script calls below (backward compatibility).
- On any `control-plane.sh` error: fall through to individual script calls (fail-open).

The existing individual script call sections (V3 Contract-Lite, V2 Hard Gates, Context compilation, Token Budgets) remain unchanged below as the fallback path.

**Context compilation (REQ-11):** If control-plane.sh `full` action was used above and returned a `context_path`, use that path directly. Otherwise, if `config_context_compiler=true` from Context block above, before creating Dev tasks run:
`bash "${VBW_PLUGIN_ROOT}/scripts/compile-context.sh" {phase} dev {phases_dir} {plan_path}`
This produces `{phase-dir}/.context-dev.md` with phase goal and conventions.
The plan_path argument is passed for context. **Research resolution:** For a specific plan `{NN}-{MM}-PLAN.md`, resolve research in this order:
1. Per-plan research: `{phase-dir}/{NN}-{MM}-RESEARCH.md` (if the plan has its own research)
2. Phase-wide research: resolve via `bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" phase-research "{phase-dir}"` → `{phase-dir}/{NN}-RESEARCH.md`
3. Wildcard fallback: first `*-RESEARCH.md` in the phase directory

Include the first match in the Dev task prompt alongside the compiled context. Phase-wide research (`{NN}-RESEARCH.md`) is the default: Plan mode creates it before Lead plans. Per-plan research (`{NN}-{MM}-RESEARCH.md`) is used only for plan-specific research added after initial planning. Skill activation uses a plan-driven architecture:
- **Orchestrator skill selection:** When composing subagent task descriptions, the orchestrator uses a two-pass rubric. **Pass 1:** derive technical domains from the task text plus structured metadata already available: logs, error text, related files, prior detail context, and any bounded sparse-input enrichment. When the input is sparse but names a concrete symbol, service, type, or file, reuse existing detail metadata first. if that is absent, resolve at most 1-3 likely files or framework markers before final preselection. SwiftData markers such as `import SwiftData`, `@Model`, `ModelContext`, `ModelContainer`, `FetchDescriptor`, `VersionedSchema`, `SchemaMigrationPlan`, or `PersistentModel` are sufficient evidence to select `swiftdata`. Do NOT add `core-data` as a generic persistence fallback unless the actual evidence instead shows Core Data APIs such as `import CoreData`, `NSManagedObject`, `NSPersistentContainer`, `NSFetchRequest`, or `NSManagedObjectContext`. **Pass 2:** select all materially helpful direct matches plus only the narrowly adjacent support skills surfaced by those domains: not just the single most direct skill. Every spawned prompt that performs this evaluation must begin with exactly one explicit outcome block: `<skill_activation>` when one or more skills are preselected at orchestration time, or `<skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. The orchestrator also states the skill evaluation outcome in its visible response before spawning the agent, giving the user visibility into which skills were preselected or why none were. If bounded enrichment influenced the decision, the orchestrator cites that explicitly in the visible outcome and reason text.
- **Lead (planning time):** Wires the final skill set into plans via `skills_used` frontmatter and `@`-references to SKILL.md files, including materially helpful adjacent/supporting domain skills surfaced during research or error analysis.
- **Spawned agents (Lead/Dev/QA/Scout/Docs/Debugger/Architect):** Treat `<skill_activation>` and `<skill_no_activation>` as explicit orchestrator starting state, not as a ceiling. Call preselected skills first, honor any plan `skills_used`, then run one bounded completeness pass over `<available_skills>` to add any missing adjacent/domain skills surfaced by the prompt or context. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting: do not scan entire skill folders or read unrelated references. When a `<skill_follow_up_files>` block is present, treat it as the authoritative resolved path list for the preselected skills and read those exact paths before any other skill-related exploration.
- **Ad-hoc paths (`/vbw:fix`, `/vbw:debug`, `/vbw:research`):** Debugger/Dev/Scout still evaluate installed skills directly because no plan exists, but they follow the same additive model: start with any orchestrator preselection, apply the same bounded sparse-input enrichment rule when the task names a concrete symbol/service/type/file but lacks richer metadata, then add materially helpful adjacent/domain skills discovered from the active task context.
- **Architect (scoping time):** Evaluates installed skills in system context. Activates relevant skills before producing requirements and roadmap artifacts.
- **Runtime skill hooks preserved:** `skill-hook-dispatch.sh` dispatches skill-defined PostToolUse/PreToolUse hooks at runtime. This is separate from skill *activation* and is unaffected by the plan-driven model.
If compilation fails, proceed without it: Dev reads files directly.

**Correctness flag (Dijkstra):** Plan tasks may carry the task attribute `correctness: dijkstra`, set by Lead at planning time for tasks involving algorithm or loop derivation, concurrency, or boundary-sensitive logic. The flag makes the trigger deterministic: Dev engages `references/dijkstra/DISCIPLINE.md` and QA verifies the invariant/variant reasoning. The orchestrator does not act on the flag itself. It passes through PLAN.md to the agents. Keep this wording in sync with Stage 2 of `agents/vbw-lead.md` (covered by `testing/verify-dijkstra-discipline.sh`).

**V2 Token Budgets (REQ-12):** If control-plane.sh `compile` or `full` action was used and included token budget enforcement, skip this step. Otherwise:
- After context compilation, enforce per-role token budgets. Pass the contract path and task number for per-task budget computation:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/token-budget.sh" dev {phase-dir}/.context-dev.md {contract_path} {task_number} > {phase-dir}/.context-dev.md.tmp && mv {phase-dir}/.context-dev.md.tmp {phase-dir}/.context-dev.md
  ```
  Where `{contract_path}` is `.vbw-planning/.contracts/{phase}-{plan}.json` (generated by generate-contract.sh in Step 3) and `{task_number}` is the current task being executed (1-based). When no contract is available, omit the contract_path and task_number arguments (per-role fallback).
- Same for QA context: `bash "${VBW_PLUGIN_ROOT}/scripts/token-budget.sh" qa {phase-dir}/.context-qa.md {contract_path} {task_number} > ...`
- Role caps defined in `config/token-budgets.json`: Scout (200 lines), Lead/Architect (500), QA (600), Dev/Debugger (800).
- Per-task budgets use contract metadata (must_haves, allowed_paths, depends_on) to compute a complexity score, which maps to a tier multiplier applied to the role's base budget.
- Overage logged to metrics as `token_overage` event with role, lines truncated, and budget_source (task or role).
- **Escalation:** When overage occurs, token-budget.sh emits a `token_cap_escalated` event and reduces the remaining budget for subsequent tasks in the plan. The budget reduction state is stored in `.vbw-planning/.token-state/{phase}-{plan}.json`. Escalation is advisory only. execution continues regardless.
- **Cleanup:** At phase end, clean up token state: `rm -f .vbw-planning/.token-state/*.json 2>/dev/null || true`
- Truncation uses tail strategy (keep most recent context).

**Pre-code validation gate (mandatory when plan requires it):**
If a plan task contains validation requirements, the validation result is a hard gate. Examples include "MUST be done before any code changes", "Expected: ...", and "If absent, stop and re-analyze":

1. **Execute the validation** using the tool appropriate to the data source:
   - **Public/anonymous endpoints** (docs pages, open APIs, status endpoints): WebFetch is acceptable.
   - **Authenticated/private APIs** (signed requests, tokens, env-based secrets, custom headers): use Bash helper scripts, curl wrappers, or repo helper commands. Do not route authenticated API validation through WebFetch.
2. **Evaluate the result:**
   - If the result matches the task's expected shape: gate passes, proceed with code changes.
   - If the result contradicts expectations (wrong values, missing fields, empty when non-empty expected): gate fails.

**Failure handling:**
1. **On gate failure:**
   - Run ONE broadened sanity-check query (remove filters, broaden search, confirm environment/account context).
   - If the contradiction remains: send `blocker_report` immediately. Do NOT proceed to the next task or begin code changes.
   - Empty filtered results (`[]`, no matches) are contradictory when the task expected specific data: do not treat empty as success unless the task explicitly defines empty as the expected outcome.
2. **Operator fallback:** If automated respawn after a blocker is not possible, surface a message to the user: "Validation gate failed for task {N}. Restart `/vbw:vibe` from current plan state to retry."


**Model resolution:** Resolve models for Dev and QA agents. The PreToolUse guard enforces the resolved model on `vbw:*` agent spawns and wins on conflicts. Keep the explicit `model:` parameter as redundancy:
```bash
DEV_MODEL=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-model.sh" dev .vbw-planning/config.json "${VBW_PLUGIN_ROOT}/config/model-profiles.json")
if [ $? -ne 0 ]; then echo "$DEV_MODEL" >&2; exit 1; fi
DEV_MAX_TURNS=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh" dev .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$DEV_MAX_TURNS" >&2; exit 1; fi

QA_MODEL=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-model.sh" qa .vbw-planning/config.json "${VBW_PLUGIN_ROOT}/config/model-profiles.json")
if [ $? -ne 0 ]; then echo "$QA_MODEL" >&2; exit 1; fi
QA_MAX_TURNS=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-max-turns.sh" qa .vbw-planning/config.json "{effort}")
if [ $? -ne 0 ]; then echo "$QA_MAX_TURNS" >&2; exit 1; fi
```

**Skill activation for Dev/QA tasks:** Before composing task descriptions, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful skills for the tasks, including adjacent support skills surfaced by the prompt, logs, errors, related files, or stack context.

Every spawned prompt that performs this evaluation MUST begin with exactly one explicit outcome block. Use `<skill_activation>` as the FIRST line when skills are preselected at orchestration time. Use `<skill_no_activation>` as the FIRST line when none are preselected. Silent omission of both blocks is invalid.

After evaluating, state the skill outcome in your response so the user has visibility before the agent is spawned. Example: `Skills: activating {skill-name}` or `Skills: none preselected: {reason}`. If the prompt or error mentions SwiftData, include `swiftdata` with relevant test, build, or debug skills.

After calling `Skill(...)`, read any relevant files named by its instructions. Do not scan unrelated skill folders. When preselected skills expose local follow-up docs, resolve them with `extract-skill-follow-up-files.sh` and paste the emitted `<skill_follow_up_files>` block immediately after the follow-up-read sentence in the spawned payload.

**Spawn-shape rule:** This applies to non-team and true-team spawns. On every live teammate spawn call, use `Agent` or `TaskCreate` without Claude-side `isolation:"worktree"`. Do not pass a `cwd` pointing into `.claude/worktrees/...` or `.vbw-worktrees/...`.

`agent-spawn-guard.sh` validates these fields before branching on delegation mode. The rule therefore applies to true-team and non-team spawns. Passing either field produces a hard `cross-worktree spawn` rejection.

Prepared VBW worktree targeting means the `Working directory:` and `Worktree targeting:` lines in the task description, derived from `.execution-state.json` `worktree_path` and `scripts/worktree-target.sh`. It is not an `isolation` or `cwd` field on the spawn call. Claude-side `isolation:"worktree"` can create unmanaged `.claude/worktrees/agent-*` sidechains with different tool and artifact assumptions. VBW's current isolation uses its own `.vbw-worktrees` git worktrees.

Non-team spawns must omit `team_name` and `run_in_background`. `name` is optional label-only metadata and must never be used for routing, lifecycle state, or team semantics. In true team mode, every spawn/TaskCreate after the marker is set must include the selected `TEAM_NAME` and teammate `name`.

For each runnable plan in the current segment, create the teammate task using the live teammate spawn tool (for example `TaskCreate` or `Agent`). In non-team mode, spawn exactly one Dev and wait for its result before spawning the next runnable plan. In true team mode, every spawn/TaskCreate after the marker is set must include the selected `TEAM_NAME` and teammate `name`.

Render the prompt prefix from `${VBW_PLUGIN_ROOT}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to `description` so the rendered skill outcome tag is the first child-prompt line. Do not paste the template path, variables, the render instruction, or an unresolved `@` include into the child prompt.

```yaml
subject: "Execute {NN-MM}: {plan-title}"
description: |
  Execute all tasks in {PLAN_PATH}.
  Effort: {DEV_EFFORT}. Working directory: {worktree_path (from execution-state.json for this plan) if worktree_isolation is enabled and worktree_path is set, else {pwd}}.
  {If worktree_isolation enabled and WTARGET non-empty: "Worktree targeting: {WTARGET}"}
  Model: ${DEV_MODEL}
  Phase context: {phase-dir}/.context-dev.md (if compiled)
  If `.vbw-planning/codebase/META.md` exists, read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before executing.
  {If resuming: "Resume from Task {NN}. Tasks 1-{NN-1} already committed."}
  {If autonomous: false: "This plan has checkpoints . Pause for user input."}
activeForm: "Executing {NN-MM}"
```

**TaskCompleted advisory scope:** Commit verification is advisory and only applies to canonical execute-task subjects (`Execute {NN-MM}: {plan-title}`). Manual, research, setup, and other non-execute tasks are allowed to complete without commit matching.

Display: `◆ Spawning Dev teammate (${DEV_MODEL})...`

**CRITICAL:** Set `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"` on the live spawn call when spawning Dev teammates. If `DEV_MAX_TURNS` is non-empty, also pass `maxTurns: ${DEV_MAX_TURNS}`. If `DEV_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited). If `DEV_REASONING` is non-empty, also pass `effort: "${DEV_REASONING}"`. If `DEV_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
**CRITICAL:** When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"` on the live spawn call. If the live spawn tool is `Agent`, those parameters belong on `Agent(...)`. If the live spawn tool is `TaskCreate`, put the same parameters there. Team mode without `team_name` is invalid.
**CRITICAL:** In explicit non-team mode or team-tooling-unavailable fallback, do NOT use `run_in_background: true` to imitate parallel team execution.

Dependency ordering is enforced by the routing helper's segment plan, not by speculative background spawns. Use TaskUpdate dependency metadata only as a task-list mirror of `depends_on`. do not spawn a dependent plan until the helper recomputes it as runnable from updated execution state. If `--plan=NN`: single task, no dependencies.

Just before spawning a runnable plan with `worktree_isolation` enabled, create or refresh that plan's worktree, update its `worktree_path` in execution state, regenerate `WTARGET`, and register `dev-{plan}` with `worktree-agent-map.sh`. After the plan's worktree is merged or cleaned up, clear the mapping.

**Blocked agent notification (mandatory):** When a Dev teammate completes a plan (task marked completed + SUMMARY.md verified), check if any other tasks have `blockedBy` containing that completed task's ID. For each newly-unblocked task, send its assigned Dev a message: "Blocking task {id} complete. Your task is now unblocked. Proceed with execution." This ensures blocked agents resume without manual intervention.

**Opt-in TDD wave sequence (delegate plans only):** Read `tdd_pipeline` from config with `.tdd_pipeline // false`. The key defaults to `false` when absent. Direct and turbo segments keep their existing path.

When `tdd_pipeline=true`, run these stages for each runnable delegate plan:
1. **Red:** Spawn `vbw:vbw-qa-author` with `${QA_MODEL}` and `${QA_MAX_TURNS}` when set. Apply the QA skill-activation prompt rules above. It reads the plan's `must_haves`, writes and commits only failing test files, then reports the `tests_ready` payload from `references/handoff-schemas.md`. Do not spawn that plan's Dev until its payload reports at least one expected failing test.
2. **Green:** Spawn the normal `vbw:vbw-dev` agent. Include the complete `tests_ready` payload in its task description and direct it to implement the plan until `test_command` passes.
3. **Verify:** Keep the standard QA timing, spawn shape, and Step 4 verification unchanged.

In true team mode, launch the current wave's QA Author teammates with `team_name: "$TEAM_NAME"` and `name: "qa-author-{MM}"`. Launch all red teammates first, then launch each matching Dev after that plan's `tests_ready` message arrives. In explicit non-team mode and team-tooling-unavailable fallback, use plain sequential subagents for each plan: spawn QA Author and wait for its returned `tests_ready` payload, then spawn Dev and wait for completion before starting the next plan. Give both stages the same plan worktree target. All spawn-shape and prepared-worktree rules above still apply.

**Opt-in cross-phase research pipeline (true team mode, first wave only):** After wave 1 Dev work is dispatched, read `pipeline_research` from config with `.pipeline_research // false`. The key defaults to `false` when absent. Spawn exactly one additional `vbw:vbw-scout` teammate only when the value is `true`, phase N+1 exists in ROADMAP.md, the Plan mode Step 3 research-exists check finds no phase research in that phase directory, and team capability is available. On any gate failure, skip silently with no banner.

Research phase N+1's ROADMAP goal and include `<output_path>{phase-N+1-dir}/${NEXT_RESEARCH_NAME}</output_path>` in the prompt, using `resolve-artifact-path.sh phase-research` to resolve `NEXT_RESEARCH_NAME`. Spawn it in the current team with `team_name: "$TEAM_NAME"` and `name: "scout-phase-{N+1}"`. Apply the Scout model resolution and skill-outcome block rules from Plan mode research in `commands/vibe.md` Step 3 rather than duplicating them here. The Scout writes only into the phase N+1 planning directory, so it cannot conflict with wave Dev work. Plan mode consumes the resulting file through its existing research-exists check in `commands/vibe.md` Step 3 when phase N+1 is planned.

**Validation Gates (REQ-13, REQ-14):** If `validation_gates=true` in config:
- **Per plan:** Assess risk and resolve gate policy:
  ```bash
  RISK=$(bash "${VBW_PLUGIN_ROOT}/scripts/assess-plan-risk.sh" {plan_path} 2>/dev/null || echo "medium")
  GATE_POLICY=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-gate-policy.sh" {effort} $RISK {autonomy} 2>/dev/null || echo '{}')
  ```
- Extract policy fields: `qa_tier`, `approval_required`, `communication_level`, `two_phase`
- Use these to override the static tables below for this plan
- Log to metrics: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" gate_policy {phase} {plan} risk=$RISK qa_tier=$QA_TIER approval=$APPROVAL 2>/dev/null || true`
- On script error: fall back to static tables below

**Plan approval gate (effort-gated, autonomy-gated):**
When `validation_gates=true`: use `approval_required` from gate policy above.
When `validation_gates=false` (default): use static table:

| Autonomy | Approval active at |
|----------|-------------------|
| cautious | Thorough + Balanced |
| standard | Thorough only |
| confident/pure-vibe | OFF |

When active: spawn Devs with `plan_mode_required`. Dev reads PLAN.md, proposes approach, waits for lead approval. Lead approves/rejects via plan_approval_response.
When off: Devs begin immediately.

**Teammate communication (effort-gated):**
When `validation_gates=true`: use `communication_level` from gate policy (none/blockers/blockers_findings/full).
When `validation_gates=false` (default): use static table:

Schema ref: `${VBW_PLUGIN_ROOT}/references/handoff-schemas.md`

| Effort | Messages sent |
|--------|--------------|
| Thorough | blockers (blocker_report), findings (scout_findings), progress (execution_update), contracts (plan_contract) |
| Balanced | blockers (blocker_report), progress (execution_update) |
| Fast | blockers only (blocker_report) |
| Turbo | N/A (no team) |

Use targeted `message` not `broadcast`. Reserve broadcast for critical blocking issues only.

**Typed Protocol (REQ-04, REQ-05, graduated, always-on):**
- **On message receive** (from any teammate): validate before processing:
  `VALID=$(echo "$MESSAGE_JSON" | bash "${VBW_PLUGIN_ROOT}/scripts/validate-message.sh" 2>/dev/null || echo '{"valid":true}')`
  If `valid=false`: log rejection, send error back to sender with `errors` array. Do not process the message.
- **On message send** (before sending): agents should construct messages using full V2 envelope (id, type, phase, task, author_role, timestamp, schema_version, payload, confidence). Reference `${VBW_PLUGIN_ROOT}/references/handoff-schemas.md` for schema details.

**Execution state updates:**
- Task completion: update plan status in .execution-state.json (`"complete"`, `"partial"`, or `"failed"` from verified SUMMARY.md status)
- Wave transition: update `"wave"` when first wave N+1 task starts
- Use `jq` for atomic updates

Hooks handle continuous verification: PostToolUse validates SUMMARY.md, TaskCompleted emits advisory execute-task commit checks, TeammateIdle runs quality gate.

**Event Log: plan lifecycle (REQ-16, graduated, always-on):**
- At plan start: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_start {phase} {plan} 2>/dev/null || true`
- At agent spawn: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" agent_spawn {phase} {plan} role=dev model=$DEV_MODEL 2>/dev/null || true`
- At agent shutdown: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" agent_shutdown {phase} {plan} role=dev 2>/dev/null || true`
- At plan complete: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_end {phase} {plan} status=complete 2>/dev/null || true`
- At plan failure: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" plan_end {phase} {plan} status=failed 2>/dev/null || true`
- On error: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" error {phase} {plan} message={error_summary} 2>/dev/null || true`

**Full Event Types (REQ-09, REQ-10, graduated, always-on):** Emit all 13 event types at correct lifecycle points.

> **Naming convention:** Event types (`shutdown_sent`/`shutdown_received`) log _what happened_: the orchestrator sent or received a message. Message types (`shutdown_request`/`shutdown_response`) define _what was communicated_: the typed payload in SendMessage. Events are emitted by `log-event.sh`. messages are validated by `validate-message.sh`.
- `phase_planned`: at plan completion (after Lead writes PLAN.md): `log-event.sh phase_planned {phase}`
- `task_created`: when task is defined in plan: `log-event.sh task_created {phase} {plan} task_id={id}`
- `task_claimed`: when Dev starts a task: `log-event.sh task_claimed {phase} {plan} task_id={id} role=dev`
- `task_started`: when task execution begins: `log-event.sh task_started {phase} {plan} task_id={id}`
- `artifact_written`: after writing/modifying a file: `log-event.sh artifact_written {phase} {plan} path={file} task_id={id}`
  - Also register in artifact registry: `bash "${VBW_PLUGIN_ROOT}/scripts/artifact-registry.sh" register {file} {event_id} {phase} {plan}`

**Outcome events:**
- `gate_passed` / `gate_failed`: already emitted by hard-gate.sh
- `task_completed_candidate`: emitted by two-phase-complete.sh
- `task_completed_confirmed`: emitted by two-phase-complete.sh after validation
- `task_blocked`: already emitted by auto-repair.sh
- `task_reassigned`: when task is re-assigned to different agent: `log-event.sh task_reassigned {phase} {plan} task_id={id} from={old} to={new}`
- `shutdown_sent`: when orchestrator sends shutdown_request to teammates: `log-event.sh shutdown_sent {phase} team={team_name} targets={count}`
- `shutdown_received`: when orchestrator has collected all shutdown_response messages: `log-event.sh shutdown_received {phase} team={team_name} approved={count} rejected={count}`

**Snapshot: per-plan checkpoint (REQ-18):** If `snapshot_resume=true` in config:
- After each plan completes (SUMMARY.md verified):
  `bash "${VBW_PLUGIN_ROOT}/scripts/snapshot-resume.sh" save {phase} .vbw-planning/.execution-state.json {agent-role} {trigger} 2>/dev/null || true`
- This captures execution state + recent git context for crash recovery. The optional `{agent-role}` and `{trigger}` arguments add metadata to the snapshot for role-filtered restore.

**Metrics instrumentation (REQ-09):** If `metrics=true` in config:
- At phase start: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_phase_start {phase} plan_count={N} effort={effort}`
- At each plan completion: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_plan_complete {phase} {plan} task_count={N} commit_count={N}`
- At phase end: `bash "${VBW_PLUGIN_ROOT}/scripts/collect-metrics.sh" execute_phase_complete {phase} plans_completed={N} total_tasks={N} total_commits={N} deviations={N}`
All metrics calls should be `2>/dev/null || true`: never block execution.

**V3 Contract-Lite (REQ-10, graduated):**
- **Once per plan (before first task):** Generate contract sidecar:
  `bash "${VBW_PLUGIN_ROOT}/scripts/generate-contract.sh" {plan_path} 2>/dev/null || true`
  This produces `.vbw-planning/.contracts/{phase}-{plan}.json` with allowed_paths and must_haves.
- **Before each task:** Validate task start:
  `bash "${VBW_PLUGIN_ROOT}/scripts/validate-contract.sh" start {contract_path} {task_number} 2>/dev/null || true`
- **After each task:** Validate modified files against contract:
  `bash "${VBW_PLUGIN_ROOT}/scripts/validate-contract.sh" end {contract_path} {task_number} {modified_files...} 2>/dev/null || true`
  Where `{modified_files}` comes from `git diff --name-only HEAD~1` after the task's commit.
- Violations are advisory only (logged to metrics, not blocking).

**V2 Hard Gates (REQ-02, REQ-03, graduated):**
- **Pre-task gate sequence (before each task starts):**
  1. `contract_compliance` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" contract_compliance {phase} {plan} {task} {contract_path}`
  2. **Lease acquisition** (V2 control plane): acquire exclusive file lease before protected_file check:
    `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" acquire {task_id} --ttl=300 {claimed_files...}`
     - Lease conflict → auto-repair attempt (wait + re-acquire), then escalate blocker if unresolved.
  3. `protected_file` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" protected_file {phase} {plan} {task} {contract_path}`
  - If any gate fails (exit 2): attempt auto-repair:
    `REPAIR=$(bash "${VBW_PLUGIN_ROOT}/scripts/auto-repair.sh" {gate_type} {phase} {plan} {task} {contract_path})`
  - If `repaired=true`: re-run the failed gate to confirm, then proceed.
  - If `repaired=false`: emit blocker, halt task execution. Send Lead a message with the failure evidence and next action from the blocker event.
- **Post-task gate sequence (after each task commit):**
  1. `required_checks` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" required_checks {phase} {plan} {task} {contract_path}`
  2. `commit_hygiene` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" commit_hygiene {phase} {plan} {task} {contract_path}`
  3. **Lease release**: release file lease after task completes:
    `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" release {task_id}`
  - Gate failures trigger auto-repair with same flow as pre-task.
- **Post-plan gate (after all tasks complete, before marking plan done):**
  1. `artifact_persistence` gate: `bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" artifact_persistence {phase} {plan} {task} {contract_path}`
  - This gate fires AFTER SUMMARY.md verification but BEFORE updating execution-state.json to the verified terminal status.
- **YOLO mode:** Hard gates ALWAYS fire regardless of autonomy level. YOLO only skips confirmation prompts.
- **Fallback:** If hard-gate.sh or auto-repair.sh errors (not a gate fail, but a script error), log to metrics and continue (fail-open on script errors, hard-stop only on gate verdicts).

**Lease Locks (REQ-17):** If `lease_locks=true` in config:
- Use `lease-lock.sh` for all lock operations:
  - Acquire: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" acquire {task_id} --ttl=300 {claimed_files...} 2>/dev/null || true`
  - Release: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" release {task_id} 2>/dev/null || true`
- **During long-running tasks** (>2 minutes estimated): renew lease periodically:
  `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" renew {task_id} 2>/dev/null || true`
- Check for expired leases before acquiring: `bash "${VBW_PLUGIN_ROOT}/scripts/lease-lock.sh" check {task_id} {claimed_files...} 2>/dev/null || true`

### Step 3b: Two-Phase Completion (REQ-09)

**If `two_phase_completion=true` in config:**

After each task commit (and after post-task gates pass), run two-phase completion:
```bash
RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/two-phase-complete.sh" {task_id} {phase} {plan} {contract_path} {evidence...})
```
- If `result=confirmed`: proceed to next task.
- If `result=rejected`: treat as gate failure: attempt auto-repair (re-run checks), then escalate blocker if still failing.
- Artifact registration: after each file write during task execution, register the artifact:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/artifact-registry.sh" register {file_path} {event_id} {phase} {plan}
  ```
- When `two_phase_completion=false`: skip (direct task completion as before).

### Step 3c: SUMMARY.md verification gate (mandatory)

**This is a hard gate. Do NOT proceed to QA or mark a plan terminal in .execution-state.json without verifying its SUMMARY.md.**

When a Dev teammate reports plan completion (task marked completed):
1. **Check:** Verify `{phase_dir}/{plan_id}-SUMMARY.md` exists and contains commit hashes, task statuses, and files modified.
2. **Status validation:** Verify SUMMARY.md frontmatter `status` is one of `complete|partial|failed`. Never accept `pending`, `draft`, or other non-terminal values. The `file-guard.sh` PreToolUse hook blocks SUMMARY writes with non-terminal status values. **Exception:** Remediation round summaries (`R{RR}-SUMMARY.md`) are exempt from this guard: they use an incremental lifecycle where the first Dev creates the file with `status: in-progress`, subsequent Devs append task sections, and the Lead finalizes the frontmatter to a terminal status after all tasks complete.
3. **If missing or incomplete:** Send the Dev a message: "Write {plan_id}-SUMMARY.md using the template at templates/SUMMARY.md. Include commit hashes, tasks completed, files modified, and any deviations." Wait for confirmation before proceeding.
4. **If Dev is unavailable:** Write it yourself from `git log --oneline` and the PLAN.md.
5. **Schema Validation: SUMMARY.md (REQ-17, graduated, always-on):**
  - Validate SUMMARY.md frontmatter: `VALID=$(bash "${VBW_PLUGIN_ROOT}/scripts/validate-schema.sh" summary {summary_path} 2>/dev/null || echo "valid")`
   - If `invalid`: log warning `⚠ Summary {plan_id} schema: ${VALID}`: advisory only.
6. **Only after SUMMARY.md is verified with terminal status:** Canonicalize and write the verified status to `.execution-state.json`: `complete|completed` → `"complete"`, `partial` → `"partial"`, `failed` → `"failed"`. Only `complete|partial` satisfy Execute dependencies. `failed` is terminal but does not unlock dependents.

**SUMMARY.md timing rule:** A SUMMARY.md represents completed execution. Never create a SUMMARY.md as a placeholder or stub before execution begins. Do not write SUMMARY.md with `status: pending` or any non-terminal status. **Exception:** Remediation round summaries (`R{RR}-SUMMARY.md`) are built incrementally across multiple Dev agents: the first Dev creates the file with `status: in-progress` and subsequent Devs append task sections. The Lead finalizes the frontmatter after all tasks complete.

### Step 4: Post-build QA (optional)

Read the file at `${VBW_PLUGIN_ROOT}/references/execute-post-build-qa.md` and follow it, then continue at the QA Result Gating heading below.

### Step 4.1: QA Result Gating (NON-NEGOTIABLE)

Read the file at `${VBW_PLUGIN_ROOT}/references/execute-qa-result-gating.md` and follow it, then continue at the UAT heading below.

### Step 4.5: Human acceptance testing (UAT)

Read the file at `${VBW_PLUGIN_ROOT}/references/execute-uat.md` and follow it, then continue at the Step 5 heading below.

### Step 5: Update state and present summary

**HARD GATE: Shutdown before ANY output or state updates:** Run team shutdown only when the persisted or helper-resolved runtime state says `delegation_mode=team` and a real `TEAM_NAME` exists. If the helper selected `subagent`, turbo, internal `direct`, no delegate-eligible plans, or team-tooling-unavailable fallback, skip the shutdown sequence and clear the marker. For actual team mode, follow the team-shutdown contract in `references/subagent-contracts.md` before updating state, presenting results, or asking the user anything.

Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.

1. Send `shutdown_request` via SendMessage to every active teammate in `TEAM_NAME`. The orchestrator controls the sequence and is not a teammate target. The SendMessage JSON body must include at minimum: `{"type": "shutdown_request", "id": "<unique-id>", "reason": "phase_complete", "team_name": "<TEAM_NAME>"}`. This is a simplified form. The full V2 envelope nests these fields under `payload`, with `id` at envelope level. Agents echo the `id` back as `request_id` in their `shutdown_response`.
2. Log event: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" shutdown_sent {phase} team={team_name} targets={count} 2>/dev/null || true`
3. Follow the shared contract orchestrator response procedure, including its bounded per-teammate retry cap across both plain-text and rejected responses, and its residual-cleanup fallback once that cap is exhausted.
4. Log event: `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" shutdown_received {phase} team={team_name} approved={count} rejected={count} 2>/dev/null || true`
5. **Post-shutdown residual cleanup** catches race-condition residuals where agents recreate inbox files after shutdown. The team config directory itself is removed automatically when the session exits.
   ```bash
   bash "${VBW_PLUGIN_ROOT}/scripts/clean-stale-teams.sh" 2>/dev/null || true
   ```
6. Only then proceed to state updates and user-facing output below
Failure to shut down an actual team leaves agents running in the background, consuming API credits (visible as hanging panes in tmux, invisible but still costly without tmux). If no actual team was created: skip shutdown sequence. **Recovery:** If shutdown stalls or agents linger after Post-shutdown residual cleanup, do NOT manually `rm -rf ~/.claude/teams`. Use `/vbw:doctor --cleanup` which runs `doctor-cleanup.sh` and `clean-stale-teams.sh` with safe atomic cleanup. These scripts detect stale teams, orphan processes, and dangling PIDs. `clean-stale-teams.sh` immediately removes VBW team directories missing `config.json` (orphaned residuals) without waiting for the 2-hour stale threshold.

Regardless of whether a real team was created, clear the execute delegation marker before state updates:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/delegated-workflow.sh" clear 2>/dev/null || true
```

> **Runtime enforcement limitation:** Claude Code does not expose agent-team message tool calls (e.g., `SendMessage`) to `PreToolUse`/`PostToolUse` hooks with stable `tool_name` values. Therefore VBW cannot hook-validate malformed shutdown responses at runtime. Enforcement relies on: (1) mechanical SendMessage instructions in all 6 agent prompts, (2) compaction-instructions.sh reminders that survive context compaction, (3) orchestrator retry (re-send if teammate responds in plain text), and (4) `/vbw:doctor --cleanup` as a recovery path for stuck teams.

**Worktree merge and cleanup (post-shutdown):** If `worktree_isolation` is not `"off"` in config:
For each plan that has a `worktree_path` entry in execution-state.json (completed or failed):
1. **Copy SUMMARY.md** from worktree to phase dir (ensure it is present in the main working tree before merge changes branch context):
   `cp "{worktree_path}/.vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" ".vbw-planning/phases/{phase-dir}/{plan_id}-SUMMARY.md" 2>/dev/null || true`
2. **Merge worktree branch:**
  `MERGE_RESULT=$(bash "${VBW_PLUGIN_ROOT}/scripts/worktree-merge.sh" {phase} {plan} 2>/dev/null || echo "conflict")`
3. **If `MERGE_RESULT=clean`:**
  - `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-cleanup.sh" {phase} {plan} 2>/dev/null || true`
  - `bash "${VBW_PLUGIN_ROOT}/scripts/worktree-agent-map.sh" clear "dev-{plan}" 2>/dev/null || true`
4. **If `MERGE_RESULT=conflict`:**
   - Log deviation in `{plan_id}-SUMMARY.md`: append "DEVIATION: worktree merge conflict: manual resolution required before cleanup."
   - Display: `⚠ Worktree merge conflict for plan {plan_id}. Resolve conflicts in {worktree_path}, then run: git worktree remove {worktree_path} --force`
   - Skip worktree-cleanup.sh: leave worktree in place for manual resolution.
All worktree operations are fail-open: script errors are suppressed (2>/dev/null || true). Merge failures are surfaced as warnings, not blockers.
When `worktree_isolation="off"`: skip this block silently.

**Post-shutdown verification:** After the shutdown sequence completes for an actual `delegation_mode=team` run, there must be ZERO active teammates. If the Pure-Vibe loop or auto-chain will re-enter Plan mode next, confirm no prior agents linger before spawning new ones. For serialized subagent, turbo, direct, or fallback runs, rely on completed subagent/direct execution plus the cleared delegation marker. Do not send team shutdown messages without a real `TEAM_NAME`.

**Control Plane cleanup:** Lock and token state cleanup already handled by existing Lease Lock and Token Budget cleanup blocks.

**Rolling Summary (REQ-03):** If `rolling_summary=true` in config:
- After the shutdown sequence when an actual team was fully shut down, before phase_end event log:
  ```bash
  bash "${VBW_PLUGIN_ROOT}/scripts/compile-rolling-summary.sh" \
    .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
  ```
  This compiles all completed SUMMARY.md files into a condensed digest for the next phase's agents.
  Fail-open: if script errors, log warning and continue: never block phase completion.
- When `rolling_summary=false` (default): skip this step silently.

**Event Log: phase end (REQ-16, graduated, always-on):**
- `bash "${VBW_PLUGIN_ROOT}/scripts/log-event.sh" phase_end {phase} plans_completed={N} total_tasks={N} 2>/dev/null || true`

**Observability Report (REQ-14):** After phase completion, if `metrics=true`:
- Generate observability report: `bash "${VBW_PLUGIN_ROOT}/scripts/metrics-report.sh" {phase}`
- The report aggregates 7 V2 metrics: task latency, tokens/task, gate failure rate, lease conflicts, resume success, regression escape, fallback %.
- Display summary table in phase completion output.
- Dashboards show by profile (thorough|balanced|fast|turbo) and autonomy (cautious|standard|confident|pure-vibe).

**Mark complete:** Set .execution-state.json `"status"` to `"complete"` (statusline auto-deletes on next refresh).
**Update STATE.md:** phase position, plan completion counts, effort used.
**Update ROADMAP.md:** mark completed plans.

**Advisory state-consistency verification:** After state updates, run:
```bash
VERIFY_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/verify-state-consistency.sh"
if [ -f "$VERIFY_SCRIPT" ]; then
  _vsc_out="$(bash "$VERIFY_SCRIPT" .vbw-planning --mode advisory 2>/dev/null || true)"
  if [ -n "$_vsc_out" ] && echo "$_vsc_out" | jq -e '.verdict == "fail"' >/dev/null 2>&1; then
    echo "VBW state-consistency warning: $(echo "$_vsc_out" | jq -c '.failed_checks')" >&2
  fi
fi
```
If the captured output's `verdict` is `"fail"`, the warning above surfaces the `failed_checks` in the phase completion output. This is non-blocking: the reactive state updater handles most drift, but crashes, compaction, or manual edits can cause silent misalignment that propagates to the next phase. This catch-net surfaces those issues early. If the script is unavailable or errors, continue normally.

**Caveman commit messages (conditional):** If `caveman_commit` is `true` in config, write commit messages using the rules in `references/caveman-commit.md`. The conventional commit format (`type(scope): description`) still applies: caveman language applies to the description text only.

**Planning artifact boundary commit (conditional):**
```bash
PG_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" commit-boundary "complete phase {NN}" .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable. skipping planning git boundary commit" >&2
fi
```
- `planning_tracking=commit`: commits `.vbw-planning/` + `CLAUDE.md` when changed
- `planning_tracking=manual|ignore`: no-op
- `auto_push=always`: push happens inside the boundary commit command when upstream exists

**After-phase push (conditional):**
```bash
PG_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/planning-git.sh"
if [ -f "$PG_SCRIPT" ]; then
  bash "$PG_SCRIPT" push-after-phase .vbw-planning/config.json
else
  echo "VBW: planning-git.sh unavailable. skipping planning git push-after-phase" >&2
fi
```
- `auto_push=after_phase`: pushes once after phase completion (if upstream exists)
- other modes: no-op

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md:
```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Phase {NN}: {name} -- Built
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Plan Results:
    ✓ Plan 01: {title}  /  ✗ Plan 03: {title} (failed)

  Metrics:
    Plans: {completed}/{total}  Effort: {profile}  Model Profile: {profile}  Deviations: {count}

  QA: {PASS|PARTIAL|FAIL|skipped}
```

**"What happened" (NRW-02):** If config `plain_summary` is true (default), append 2-4 plain-English sentences between QA and Next Up. No jargon. Source from SUMMARY.md files + QA result. If false, skip.

**Discovered Issues:** If any Dev or QA agent reported pre-existing failures, out-of-scope bugs, or issues unrelated to this phase's work, collect and de-duplicate them by test name and file. When the same test and file pair has different error messages, keep the first message encountered.

List the issues in the summary output between "What happened" and Next Up. Cap the list at 20 entries to keep context size manageable. If more exist, show the first 20 and append `... and {N} more`. Format each bullet as `⚠ testName (path/to/file): error message`:
```text
  Discovered Issues:
    ⚠ {issue-1}
    ⚠ {issue-2}
  Registry: {phase-dir}/known-issues.json
```
This display is supplemental to the phase registry. The orchestrator should already have synced these issues into `{phase-dir}/known-issues.json` and auto-promoted surviving entries to `STATE.md ## Todos` via `promote-todos` before rendering this summary. The display block is informational only: do not enter an interactive loop here. If no discovered issues: omit the section entirely. After displaying discovered issues, STOP. Do not take further action.

Run `bash "${VBW_PLUGIN_ROOT}/scripts/suggest-next.sh" execute {qa-result}` and display output.

**STOP.** Execute mode is complete. Return control to the user. Do NOT take further actions: no file edits, no additional commits, no interactive prompts, no improvised follow-up work. The user will decide what to do next based on the summary and suggest-next output.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: Phase Banner (double-line box), ◆ running, ✓ complete, ✗ failed, ○ skipped, Metrics Block, Next Up Block, no ANSI color codes.
