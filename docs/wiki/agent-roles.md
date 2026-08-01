# Agent Roles: Scout, Architect, Lead, Dev, QA, Debugger, Docs

VBW ships 7 specialized agents (`agents/vbw-{role}.md`) that cover research, planning, execution, verification, investigation, and documentation, coordinating through a typed JSON message protocol.

## Roster at a Glance

| Agent | File | `permissionMode` | `memory` | Read-only? |
| --- | --- | --- | --- | --- |
| Scout | `agents/vbw-scout.md` | `plan` | `local` | Yes |
| Architect | `agents/vbw-architect.md` | `acceptEdits` | `project` | No |
| Lead | `agents/vbw-lead.md` | `acceptEdits` | `project` | No |
| Dev | `agents/vbw-dev.md` | `acceptEdits` | `project` | No |
| QA | `agents/vbw-qa.md` | `plan` | `project` | Yes |
| Debugger | `agents/vbw-debugger.md` | `acceptEdits` | `project` | No |
| Docs | `agents/vbw-docs.md` | `acceptEdits` | `local` | No |

`permissionMode: plan` is the platform mechanism that makes an agent read-only. It cannot accept file edits during the session. Scout and QA are the two read-only agents. Every other role runs under `acceptEdits`.

## Tool Permissions

Each agent's frontmatter grants tools two ways: an explicit `tools:` allowlist, or a `disallowedTools:` denylist (which implicitly allows every other current and future Claude Code tool). Source: each agent's YAML frontmatter block.

| Agent | Permission model | Notes |
| --- | --- | --- |
| Scout | `disallowedTools: Edit, NotebookEdit, Task, TaskCreate, Agent` | Cannot edit existing files or spawn subagents/teams. Bash is allowed but restricted by policy to read-only research and live-validation commands (no mutation, no `eval`, no command substitution, no heredoc file writes). |
| Architect | `tools: Read, Glob, Grep, Write, LSP, Skill` | No Edit, WebFetch, or Bash. Write-only for new planning artifacts, no subagents. |
| Lead | `tools: Read, Glob, Grep, Write, Bash, WebFetch, LSP, Skill, Task(vbw-dev)` | The only agent with a scoped `Task` grant, and only for spawning `vbw-dev`. Bash is restricted to research (git log, directory listing, pattern search). WebFetch is for external docs only. |
| Dev | `disallowedTools: Task, TaskCreate, Agent, AskUserQuestion` | Denylist model: every built-in tool (Bash, Read, Edit, Write, Glob, Grep, LSP, Skill, WebFetch, WebSearch) is available except recursive-delegation and user-question tools. New Claude Code tools are available by default unless added to the denylist. |
| QA | `disallowedTools: Task` | Read-only verification agent (`permissionMode: plan`). It persists `VERIFICATION.md` via `write-verification.sh` run through Bash rather than by editing files directly. |
| Debugger | `disallowedTools: Task` | Full codebase access for investigation. No subagents. |
| Docs | `tools: Read, Grep, Glob, Bash, Write, Edit, LSP, Skill` | No WebFetch/WebSearch in the allowlist. Write/Edit access is scoped by policy to documentation files: `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `docs/**/*.md`, inline code comments, and API docs/guides, not source code. |

All 7 agents set `model: inherit`. Lead is the only agent with team-spawn capability (`Task(vbw-dev)`). Every other agent's frontmatter or protocol text explicitly forbids forming an agent team or spawning teammates.

### LSP-First Navigation

`references/lsp-first-policy.md` is a repo-wide rule that applies to all 7 LSP-capable agents (Scout, Architect, Lead, Dev, QA, Debugger, Docs). All of them use LSP first for semantic navigation (go-to-definition, find-references, workspace/document symbols, call hierarchy, diagnostics) and fall back immediately to Grep/Glob for literal strings, filenames, non-code assets, or when LSP is unavailable or errors. There is no retry of a failing LSP call. The Lead has an extra nuance: when a plan already has `RESEARCH.md`, it must avoid broad exploratory scans, but targeted LSP validation of specific known symbols is still preferred over Grep for that case.

## Role Responsibilities

### Scout: Research

`agents/vbw-scout.md`. Gathers information from the web, docs, MCP tools, and the codebase. It writes findings directly to `RESEARCH.md` files, never returning them only as chat text when an `<output_path>`/`<output_paths>` is supplied. Up to 4 Scouts can run in parallel. Write access is scoped to paths inside `.vbw-planning/` named in its output directives, and it rejects any path outside that directory. Scout also performs read-only live validation (curl wrappers, `jq`/`grep` searches, safe read-only `git` inspection) and must record a `## Live Validation Evidence` section with `command_shape`, `exit_status`, `redacted_evidence`, `expected_shape`, `confidence`, and `limitations_or_deferred_reason` whenever it runs or defers a check.

### Architect: Requirements to Roadmap

`agents/vbw-architect.md`. Turns raw requirements/input plus codebase context into planning artifacts: `PROJECT.md` (identity, requirements, constraints, decisions), `REQUIREMENTS.md` (catalog with unique IDs like `AGNT-01`, acceptance criteria, traceability), and `ROADMAP.md` (phases, goals, dependencies, criteria, plan stubs). It uses goal-backward derivation of observable, testable success criteria with no subjective measures. Requirements are grouped into testable phases (2-4 plans/phase, 3-5 tasks/plan) with explicit cross-phase dependencies. Architect is planning-only: no Edit, WebFetch, or Bash, and it is explicitly excluded from the teammate shutdown protocol since it never runs inside an execution team.

### Lead: Planning and Team Coordination

`agents/vbw-lead.md`. Runs a 4-stage protocol in one compaction-extended session:

1. **Research.** Reads compiled context, `STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md`, and dependency `SUMMARY.md` files. Trusts an existing `RESEARCH.md` from Scout rather than re-scanning, or scans the codebase itself (LSP-first) when no research exists.
2. **Decompose.** Breaks the phase into 3-5 plans, each sized for one Dev session (3-5 tasks/plan), modeling real dependencies and minimizing same-wave file overlap between parallel plans.
3. **Self-Review.** Checks requirement coverage, absence of circular dependencies and same-wave file conflicts, and that skill references are complete. Fixes issues inline.
4. **Output.** Writes each `PLAN.md` to disk using `resolve-artifact-path.sh` for the filename, then reports plans written per phase.

Lead is also the only agent that can spawn a Dev subagent (`Task(vbw-dev)`) and is the aggregation point for `pre_existing_issues` reported by teammates across `execution_update`, `qa_verdict`, `blocker_report`, and `debugger_report` messages.

### Dev: Execution

`agents/vbw-dev.md`. Implements `PLAN.md` tasks sequentially with one atomic commit per task (`{type}({phase}-{plan}): {task-name}`), then produces `SUMMARY.md` as a terminal artifact. Status must be `complete`, `partial`, or `failed`, never a non-terminal status. A PreToolUse hook blocks invalid writes. Dev bootstraps from `.vbw-planning/codebase/META.md`-linked files (`CONVENTIONS.md`, `PATTERNS.md`, `STRUCTURE.md`, `DEPENDENCIES.md`) when present. It classifies deviations via a fixed table (DEVN-01 through DEVN-05, default DEVN-04 when unsure) and pre-existing test/build failures via a documented decision tree, persisting DEVN-05 issues into `SUMMARY.md` frontmatter's `pre_existing_issues` array. Dev has a "Blocked Task Self-Start" behavior: it re-checks `TaskGet` on every turn to detect cleared blockers without waiting for explicit Lead notification.

Dev also applies a Dijkstra correctness discipline for correctness-critical work (loops, algorithms, boundary logic, concurrency, recursion, or tasks flagged `correctness: dijkstra` by Lead): it states the postcondition before writing code, derives or verifies the loop invariant and variant (termination) function, and records a `Grounding:` bullet in `SUMMARY.md`. The method and its 17 on-demand reference briefs live in `references/dijkstra/DISCIPLINE.md`, which routes Dev to at most 1-3 briefs per task. QA verifies the reasoning backward on flagged tasks and treats a missing `Grounding:` bullet as a finding.

### QA: Verification

`agents/vbw-qa.md`. Read-only agent (`permissionMode: plan`) that verifies completed work using goal-backward methodology: it derives testable conditions from a plan's `must_haves`, executes checks, and classifies each PASS/FAIL/PARTIAL. It supports three tiers (quick: 5-10 checks, standard: 15-25, deep: 30+). QA treats every plan deviation, whether declared in `SUMMARY.md`'s `deviations:` array or discovered via an "undeclared deviation scan" comparing plan deliverables against actual code, as a FAIL check. A deviation present anywhere means the result cannot be PASS. Results persist to `VERIFICATION.md` (frontmatter with `tier`, `result`, `passed`/`failed`/`total`, `plans_verified`) via `write-verification.sh` run through Bash, since QA cannot edit files directly. QA also runs in a distinct "Debug session QA mode" when invoked without phase artifacts, to verify a Debugger's root-cause fix.

### Debugger: Investigation

`agents/vbw-debugger.md`. Runs a 7-step scientific-method protocol: reproduce, hypothesize (1-3 ranked hypotheses), gather evidence per hypothesis, diagnose the root cause, apply a minimal fix, verify by re-running repro steps and related tests, and document (summary, root cause, fix, files modified, commit hash, timeline). One issue per standalone session. In **Teammate Mode** (spawned by `/vbw:debug` Path A), it is restricted to investigation only: it is assigned exactly one hypothesis, reports via `debugger_report`, and is explicitly barred from editing files, running mutating Bash, committing, or claiming ownership of the session outcome. Only Steps 1-4 of the protocol apply. Debugger also supports a **Standalone Debug Session Mode** with persistent state written through `write-debug-session.sh`, preserving every hypothesis considered (not just the winner) for resume support.

### Docs: Documentation

`agents/vbw-docs.md`. Specialized for READMEs, changelogs, inline docs, API docs, and guides. Read access spans the whole codebase for context, but write/edit access is scoped to documentation file types only (see the Tool Permissions table). Docs follows the same PLAN.md-driven execution protocol shape as Dev (load plan, execute tasks with one commit each, produce a terminal `SUMMARY.md`), and follows brand conventions in `references/vbw-brand-essentials.md`: horizontal-bar banners, `◆`/`✓`/`✗`/`○` status symbols, no emoji in formal docs.

## Handoffs Between Agents

Inter-agent coordination in teammate mode uses the V2 typed protocol defined in `references/handoff-schemas.md`. Every message carries a mandatory envelope (`id`, `type`, `phase`, `task`, `author_role`, `timestamp`, `schema_version`, `payload`, `confidence`) and is checked against a role authorization matrix. An unauthorized sender's message is rejected.

| Message type | Allowed senders | Typical receivers | Purpose |
| --- | --- | --- | --- |
| `scout_findings` | scout | lead, architect | Research handoff from Scout into planning |
| `plan_contract` | lead, architect | dev, qa, scout | Issued task scope: objective, `allowed_paths`, `must_haves`, `forbidden_paths`, `verification_checks` |
| `execution_update` | dev, docs | lead | Per-task progress/completion, including `pre_existing_issues` |
| `blocker_report` | dev, docs | lead | Escalation when execution cannot proceed |
| `debugger_report` | debugger | lead | Hypothesis evidence and `resolution_observation` (`already_fixed`/`needs_change`/`inconclusive`) |
| `qa_verdict` | qa | lead | Structured PASS/FAIL/PARTIAL verdict with `checks_detail` and `plans_verified` |
| `approval_request` / `approval_response` | dev, lead / lead, architect | lead, architect / dev, lead | Scope changes, plan approval, gate overrides |
| `shutdown_request` / `shutdown_response` | lead (orchestrator) / dev, qa, scout, lead, debugger, docs | all teammates / lead (orchestrator) | Graceful team termination |

Typical flow through a phase:

1. **Scout to Lead/Architect.** Scout writes domain `RESEARCH.md` files and, in teammate mode, sends `scout_findings` with only cross-cutting findings, since the file contents are already persisted.
2. **Architect to Lead.** Architect's `ROADMAP.md`/`REQUIREMENTS.md` outputs seed the Lead's Stage 1 research. The Lead reads these from disk rather than over the message bus.
3. **Lead to Dev/QA/Scout.** Lead issues `plan_contract` per plan, defining `allowed_paths`, `must_haves`, and `verification_checks` that Dev, QA, and any further Scouts must respect.
4. **Dev/Docs to Lead.** Dev and Docs report `execution_update` per task, or `blocker_report` if stuck, including any `pre_existing_issues` discovered outside their task's file scope.
5. **QA to Lead.** QA returns `qa_verdict` with per-check `checks_detail`, forcing FAIL/PARTIAL whenever any deviation is present.
6. **Debugger to Lead.** In `/vbw:debug` Path A, each Debugger teammate investigates one hypothesis and reports `debugger_report`. The orchestrator, not the Debugger, owns synthesis and any follow-up implementation spawn.
7. **Lead to all teammates.** At phase/plan completion the Lead broadcasts `shutdown_request`. Every teammate (Scout, Lead itself, Dev, QA, Debugger, Docs) must respond with a tool-call `shutdown_response`, not plain text acknowledgement. Architect is excluded since it never runs inside an execution team. The orchestrator retries up to 3 times on rejection before proceeding.

### Backward Compatibility Note

Per `references/handoff-schemas.md`, the `v2_typed_protocol` flag has been always-on since v1.20 and is stripped from configs by `migrate-config.sh`. `validate-message.sh` always validates against the V2 schema. Flat shutdown messages without a full envelope are normalized by the validator into V2 envelope shape before validation, so simplified inbox delivery still works without agents constructing a full envelope by hand.

## Cross-Cutting Constraints (All Agents)

- **Skill activation.** Every agent follows the same three-branch protocol: honor an inbound `<skill_activation>` block as a starting set (not a ceiling), treat `<skill_no_activation>` as "no preselection" rather than a ban on adding skills, and in standalone/ad-hoc mode run one bounded completeness pass over `<available_skills>`.
- **Circuit breaker.** On 3 consecutive identical errors, try exactly one alternative approach before escalating a blocker. Never a 4th retry of the same failing operation.
- **V2 Role Isolation.** Architect and Lead may only write inside `.vbw-planning/` and may never modify `.vbw-planning/config.json` or `.vbw-planning/.contracts/`. Dev, QA, and Debugger may only write files listed in their active contract's `allowed_paths` and are likewise barred from `.vbw-planning/.contracts/`, `config.json`, and `ROADMAP.md`. Docs may only write documentation files.
- **Effort levels.** All 7 agents follow the effort level (`max|high|medium|low`) passed in their task description and re-read source-of-truth files from disk after compaction.
