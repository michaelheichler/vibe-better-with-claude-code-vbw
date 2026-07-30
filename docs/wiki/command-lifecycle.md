# Command Lifecycle: /vbw:init through /vbw:verify

A project moves through 26 commands in `commands/`, grouped below by lifecycle stage: init, plan/discuss, execute/fix, verify/qa, status/report, and maintenance.

## The 26 commands

Commands carry a `category:` frontmatter field. The repo's own grouping is:

- `lifecycle` (3): `init.md`, `vibe.md`, `discuss.md`
- `monitoring` (3): `status.md`, `qa.md`, `verify.md`
- `supporting` (15): `fix.md`, `debug.md`, `todo.md`, `list-todos.md`, `pause.md`, `resume.md`, `report.md`, `skills.md`, `rtk.md`, `config.md`, `compress.md`, `profile.md`, `teach.md`, `doctor.md`, `help.md`
- `advanced` (5): `map.md`, `research.md`, `whats-new.md`, `update.md`, `uninstall.md`

That totals 3 + 3 + 15 + 5 = 26 files, matching the count of `commands/*.md`.

This page reorganizes those same 26 into the lifecycle narrative below: init, plan/discuss, execute/fix, verify/qa, status/report, and maintenance.

## State model: phases and milestones

Project state lives under `.vbw-planning/`. Work is broken into phase directories, `phases/{NN}-{slug}/`, each holding a `{NN}-PLAN.md` once planned and a `{NN}-SUMMARY.md` once built. A completed and UAT-passed set of phases can be archived into a milestone using `--archive` mode of `/vbw:vibe` (see below). Archived milestone data moves under `.vbw-planning/milestones/`.

`references/phase-detection.md` is the single source of truth for inferring the target phase when a command omits an explicit phase number. It defines detection algorithms per command type:

- **Planning commands** (`/vbw:vibe --plan`, `--discuss`, `--assumptions`): first phase directory with no `*-PLAN.md` files.
- **Build** (`/vbw:vibe --execute`): first phase with a `*-PLAN.md` but no matching `*-SUMMARY.md`.
- **QA** (`qa.md`): first built phase with no authoritative QA verification artifact, accounting for QA remediation and UAT-cutover dormancy rules.
- **Lifecycle command** (`/vbw:vibe` with no phase argument): a dual-condition scan across "needs plan + execute" and "needs execute only," used by states 3-4 of `vibe.md`'s state machine.

## 1. Init: bootstrap the project

**`/vbw:init`** (`commands/init.md`, category `lifecycle`) is the entry point. Its steps, per the file's `## Steps` headings, run 0 through 8:

- Step 0: environment setup, writes `settings.json`.
- Step 0.5: conditional GSD import (migrating from the separate GSD planning system, kept isolated from VBW per the plugin-isolation convention).
- Step 1: scaffold `.vbw-planning/`.
- Step 1.5: install git hooks.
- Step 1.7: conditional GSD isolation flag.
- Step 2: brownfield detection and discovery. For source trees at or above 200 files, `/vbw:map` runs inline (blocking) before continuing.
- Step 3 / 3.5: convergence and bootstrap `CLAUDE.md` generation.
- Step 4: present summary.
- Steps 5-6: scenario detection (GREENFIELD, GSD_MIGRATION, BROWNFIELD, or the HYBRID edge case) and inference/confirmation.
- Step 7: bootstrap execution, generating the project-defining files.
- Step 8: completion summary.

For an existing codebase, init auto-chains into `/vbw:map` (four parallel Scout teammates covering tech, architecture, quality, and concerns) before handing off to `/vbw:vibe`.

## 2. Plan / discuss

**`/vbw:vibe`** (`commands/vibe.md`, category `lifecycle`) is described in its own frontmatter as "the one command." It detects state, parses intent, and routes to any lifecycle mode. `vibe.md` defines its modes under a `## Modes` heading:

- Init Redirect, Bootstrap, Scope
- Discuss, Assumptions
- UAT Remediation, Milestone UAT Recovery
- Plan, Execute, Verify
- Add Phase, Insert Phase, Remove Phase
- Archive

Routing into these modes happens three ways, under `## Input Parsing`: Path 1 flag detection (`--plan`, `--execute`, `--discuss`, `--assumptions`, `--scope`, `--add`, `--insert`, `--remove`, `--archive`, `--yolo`, `--effort=`, `--skip-qa`, `--skip-audit`, `--plan=NN`), Path 2 natural-language intent parsing, and Path 3 state detection when no arguments are given (evaluating `phase-detect.sh` output).

**`/vbw:discuss [phase]`** (`commands/discuss.md`, category `lifecycle`) is the standalone entry to the same discussion engine that `/vbw:vibe --discuss` uses. It has its own Context, Guards, Phase Resolution, Discussion Mode Resolution, Execute, and After Discussion sections. Discussion captures decisions to `{phase}-CONTEXT.md` before planning begins. When `require_phase_discussion=true` in `config.json`, `phase-detect.sh` inserts a discussion gate ahead of planning for phases lacking both a `PLAN.md` and a `CONTEXT.md`.

Planning itself, `Mode: Plan` in `vibe.md`, generates `{NN}-PLAN.md` for the target phase.

## 3. Execute / fix

Execution is driven by `references/execute-protocol.md`, invoked from `Mode: Execute` in `vibe.md`. Its top-level steps:

- Step 2: load plans and detect resume state.
- Step 3: resolve Execute routing and run segments (the largest section of the file).
- Step 3b: two-phase completion.
- Step 3c: mandatory `SUMMARY.md` verification gate.
- Step 4: optional post-build QA, including Step 4.1 QA result gating and Step 4.5 human acceptance testing (UAT).
- Step 5: update state and present the summary.

Execute routes work to the **Lead** agent, which never writes code itself but routes runnable plan segments to **Dev** agents, using true Agent Teams for genuinely parallel work or serialized Dev subagents for linear dependency chains.

**`/vbw:fix`** (`commands/fix.md`, category `supporting`) is the escape hatch for small changes, described as turbo mode with no planning ceremony. Its structure is minimal: `## Context`, `## Guard`, `## Steps`. One commit, no phase plan required.

**`/vbw:debug [N]`** (`commands/debug.md`, category `supporting`) runs the Debugger agent's scientific-method protocol against a bug, optionally resuming a prior session (`--resume`, `--session <id>`) or claiming a todo directly from `/vbw:list-todos`. At thorough effort with an ambiguous bug it can spawn three competing-hypothesis debugger teammates in parallel before handing implementation to one fresh debugger.

## 4. Verify / QA

Two distinct verification commands cover machine and human checks.

**`/vbw:qa [phase]`** (`commands/qa.md`, category `monitoring`) runs the read-only QA agent and persists findings to `VERIFICATION.md`. `references/verification-protocol.md` defines the three-tier model it draws on:

- Quick (5-10 checks), Standard (15-25 checks), Deep (30+ checks), chosen by an auto-selection heuristic.
- Goal-backward methodology, convention verification, anti-pattern scanning, requirement mapping, and test-execution best practices.
- Output structure: `Must-Have Checks`, `Artifact Checks`, `Key Link Checks`, `Anti-Pattern Scan` (standard+), `Requirement Mapping` (deep only), `Convention Compliance` (standard+, if `CONVENTIONS.md` exists), `Skill-Augmented Checks`, `Summary`.

**`/vbw:verify [phase]`** (`commands/verify.md`, category `monitoring`) runs human UAT. Its `## Steps` walk from phase/summary resolution through a CHECKPOINT loop that presents one test scenario at a time (conversational, blocking), response mapping, issue handling (including issues discovered mid-session), persisting after every response, and session completion.

Both commands participate in the QA/UAT gate that `execute-protocol.md` Step 4.1 and Step 4.5 enforce before a phase can be considered done, and both feed the routing table in `phase-detection.md`'s QA Protocol section (result parsing, remediation staging, UAT-cutover dormancy).

## 5. Status / report

**`/vbw:status`** (`commands/status.md`, category `monitoring`) shows the progress dashboard: phase status, completion, velocity metrics, and suggested next action, with a `--metrics` flag for per-agent token consumption.

**`/vbw:list-todos`** and **`/vbw:todo`** (`commands/list-todos.md`, `commands/todo.md`, category `supporting`) manage the persistent backlog in `STATE.md`. They add items and browse/filter them, with routing into `/vbw:fix`, `/vbw:debug`, `/vbw:research`, or `/vbw:vibe` from unfiltered list views.

**`/vbw:report`** (`commands/report.md`, category `supporting`) collects diagnostic context (version, environment, hook errors, session logs, config, project state), classifies the issue as bug or feature, and files a GitHub issue. Its steps: `## Context`, `## Parse Arguments`, `## Scope`, `## Steps`.

**`/vbw:pause`** and **`/vbw:resume`** (category `supporting`) bookend a session. `/vbw:pause` saves session notes, since state auto-persists regardless. `/vbw:resume` restores context from `.vbw-planning/` ground truth (`STATE.md`, `ROADMAP.md`, plans, and summaries) without requiring a prior pause, and detects interrupted builds via execution state.

## 6. Maintenance

**Category `advanced`** (5 commands) covers heavier or occasional operations:

- `/vbw:map`: codebase analysis via 4 parallel Scout teammates, structured in steps: parse arguments/detect mode, size the codebase and select a tier, detect monorepo layout, execute mapping (tier-branched), verify the mapping documents Scouts wrote, synthesize `INDEX.md`/`PATTERNS.md`, and write `META.md`.
- `/vbw:research`: standalone Scout research decoupled from planning.
- `/vbw:whats-new`: view changelog entries since the installed version.
- `/vbw:update`: update VBW, including a nuclear cache wipe (Step 4) and update verification (Step 6).
- `/vbw:uninstall`: remove all VBW traces, statusLine, the Agent Teams env var, project data, and `CLAUDE.md` cleanup, each its own numbered step.

**Category `supporting`** also includes several maintenance/configuration commands not covered above:

- `/vbw:compress`: compress a natural-language file into caveman format to save tokens, preserving code blocks, URLs, and structure. Keeps an `.original` backup.
- `/vbw:config`: view/modify effort profile, autonomy level, verification tier, and skill-hook wiring. Step 0 always migrates brownfield config first.
- `/vbw:profile`: switch between or create work profiles (effort, autonomy, and verification bundled together).
- `/vbw:teach`: view, add, or remove project conventions, or refresh auto-detection. Conventions are injected into agent context and checked by QA.
- `/vbw:skills`: browse and install community skills from skills.sh based on detected stack, with a registry search step and an install-scope choice.
- `/vbw:rtk`: manage optional RTK tool-output compression: status, install, hook enable/repair, verify, uninstall.
- `/vbw:doctor`: 18 numbered health checks (`jq` presence through RTK integration) plus a runtime-health block (stale teams, orphaned processes, dangling PIDs, stale markers, watchdog status) and a `### Cleanup` action.
- `/vbw:help`: command reference, either the full list or details for one named command.

## Reference documents behind the commands

- `references/phase-detection.md`: phase auto-detection algorithms, shared by `/vbw:vibe` and the QA protocol.
- `references/execute-protocol.md`: the execution state machine that `Mode: Execute` in `vibe.md` runs, including the QA/UAT gates.
- `references/verification-protocol.md`: the three-tier QA methodology `/vbw:qa` applies.

## See also

- [Migration: GSD to VBW](../migration-gsd-to-vbw.md)
