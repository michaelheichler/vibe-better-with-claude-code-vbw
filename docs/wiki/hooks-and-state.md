# Hooks and State Architecture

VBW enforces quality gates and continuous verification through 24 hook handler scripts routed via a single wrapper, and it persists all workflow state as plain markdown and JSON under `.vbw-planning/`.

## Hooks: events, matchers, handlers

`hooks/hooks.json` registers hook entries across 11 event types. Each entry pairs a `matcher` (which tool or subagent the hook fires for) with one or more `hooks` command blocks. Counting leaf command entries with `jq '[.hooks[][].hooks[]] | length' hooks/hooks.json` gives 30 total registrations, but several scripts are registered more than once with different arguments. For example `validate-summary.sh` runs on both `PostToolUse` and `SubagentStop`, `skill-hook-dispatch.sh` runs on both `PreToolUse` and `PostToolUse`, and `agent-health.sh` runs with four different subcommands. Counting distinct script basenames instead gives 24 unique handler scripts, which is the number CLAUDE.md cites for "24 handlers across 11 event types."

Per-event handler counts (leaf command entries, via `jq -r '.hooks | to_entries[] | "\(.key): \([.value[].hooks[]] | length)"' hooks/hooks.json`):

| Event | Handlers | Scripts |
|---|---|---|
| PreToolUse | 8 | `bash-guard.sh`, `agent-spawn-guard.sh`, `skill-decision-logger.sh` (matcher `Agent\|TaskCreate`), `skill-decision-logger.sh` (matcher `Skill`), `security-filter.sh`, `lsp-nudge.sh`, `skill-hook-dispatch.sh PreToolUse`, `file-guard.sh` |
| PostToolUse | 5 | `validate-summary.sh PostToolUse`, `validate-frontmatter.sh`, `validate-commit.sh`, `skill-hook-dispatch.sh PostToolUse`, `state-updater.sh` |
| SessionStart | 3 | `session-start.sh`, `map-staleness.sh`, `post-compact.sh` (matcher `compact`) |
| SubagentStop | 3 | `validate-summary.sh SubagentStop`, `agent-stop.sh`, `agent-health.sh stop` |
| SubagentStart | 2 | `agent-start.sh`, `agent-health.sh start` |
| TeammateIdle | 2 | `qa-gate.sh`, `agent-health.sh idle` |
| TaskCompleted | 2 | `task-verify.sh`, `blocker-notify.sh` |
| Stop | 2 | `session-stop.sh`, `agent-health.sh cleanup` |
| PreCompact | 1 | `compaction-instructions.sh` |
| UserPromptSubmit | 1 | `prompt-preflight.sh` |
| Notification | 1 | `notification-log.sh` |

The `SubagentStart`, `SubagentStop`, and `TeammateIdle` entries share one long matcher string that covers both the bare agent names (`lead`, `dev`, `qa`, `scout`, `debugger`, `architect`, `docs`) and their fully qualified `vbw-*` / `vbw:vbw-*` / `team-*` forms, so a hook fires regardless of how the platform reports the agent identity.

## Resolution cascade: hook-wrapper.sh

Every hook command in `hooks.json` is a `bash -c '...'` one-liner that resolves the location of `scripts/hook-wrapper.sh` itself before doing anything else, using the DXP-01 cascade documented in CLAUDE.md:

1. Versioned plugin cache glob (`ls .../plugins/cache/vbw-marketplace/vbw/*/scripts/hook-wrapper.sh | sort -V | tail -1`)
2. `CLAUDE_PLUGIN_ROOT` env var (`--plugin-dir` local dev installs)
3. `/tmp/.vbw-plugin-root-link-*/scripts/hook-wrapper.sh` symlink glob
4. `ps axww` scanned for a `--plugin-dir <path>` argument via `grep -oE`
5. If none resolve, the inline command exits 0 with no action, a graceful no-op that never breaks the session

Once `hook-wrapper.sh` itself is located and invoked, it repeats a matching cascade internally (`scripts/hook-wrapper.sh:85-101`) to find the actual target script (`$SCRIPT`, the first argument): plugin cache glob, then `CLAUDE_PLUGIN_ROOT`, then a same-directory sibling lookup. Along the way it:

- traps `SIGHUP` to terminate any tracked agent PIDs (`agent-pid-tracker.sh list`, `SIGTERM` then `SIGKILL` after a 3s grace period) as a backup to the tmux watchdog for direct terminal force-close
- resolves the workspace's `.vbw-planning` root via `lib/vbw-config-root.sh` (`find_vbw_root`), handling the monorepo/submodule case where a bare `.vbw-planning/` lookup fails
- optionally captures stdout to `.vbw-planning/.hook-debug.log` (base64-encoded, trimmed to the last 200 entries) when `VBW_DEBUG=1` or `config.json`'s `debug_logging` is true
- executes the target with `bash "$TARGET" "$@"`, passing stdin through unchanged so the hook JSON payload reaches the target script
- treats exit code 2 as an intentional block (used by `PreToolUse`/`UserPromptSubmit` hooks) and passes it through rather than treating it as failure
- on any other non-zero exit, appends a timestamped line to `.vbw-planning/.hook-errors.log` (trimmed to the last 50 entries) and still exits 0

This is what CLAUDE.md means by "no hook can break a session." Failures are logged, never surfaced as a fatal error to the platform.

## Runtime state: `.vbw-planning/`

`/vbw:init` creates `.vbw-planning/` in the target project. Its top-level files, per CLAUDE.md's Architecture section, are `STATE.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `config.json`, and a `phases/{NN}-{slug}/` directory tree holding one `PLAN.md` and one `SUMMARY.md` per plan.

### STATE.md

`templates/STATE.md` is 24 lines: a project name, a "Current Phase" block (`Phase: {current} of {total}`, plan completion count, percent progress, and a status of `ready`/`active`/`needs_remediation`/`complete`), a Key Decisions table, a Todos section, a Blockers section, and an Activity Log. `state-updater.sh` (fired on `PostToolUse` for `Write|Edit|Bash`) is what keeps this file current as agents work.

### PLAN.md

`templates/PLAN.md` is 51 lines: YAML frontmatter (`phase`, `plan`, `title`, `type`, `wave`, `depends_on`, `cross_phase_deps`, `autonomous`, `effort_override`, `skills_used`, `files_modified`, `forbidden_commands`, and a `must_haves` block of `truths`/`artifacts`/`key_links`) followed by an XML-tagged body: `<objective>`, `<context>` (an `@`-reference to a compiled context file), one or more `<task>` blocks with `<files>`/`<action>`/`<verify>`/`<done>`, `<verification>`, `<success_criteria>`, and `<output>` naming the expected `{plan-number}-SUMMARY.md`.

### SUMMARY.md

`templates/SUMMARY.md` is 35 lines: frontmatter carrying `phase`, `plan`, `title`, `status` (`complete`/`partial`/`failed`), `completed` date, `tasks_completed`/`tasks_total`, `commit_hashes`, `deviations`, an authoritative `pre_existing_issues: []` (its presence tells consumers not to fall back to a legacy free-text section), and an `ac_results` list reconciling each `must_haves` criterion from the plan against a `pass|fail|partial` verdict and evidence. The body has a one-line summary, "What Was Built", "Files Modified", and "Deviations" sections.

`validate-summary.sh` runs on both `PostToolUse` (after a Dev agent writes/edits a SUMMARY.md) and `SubagentStop` (when the subagent finishes) to catch malformed or incomplete summaries at both points.

## Context compilation

`scripts/compile-context.sh <phase-number> <role> [phases-dir] [plan-path]` produces `{phase-dir}/.context-{role}.md`, a role-scoped context file so each agent only loads what it needs. The script (733 lines) works as follows.

1. Resolves the planning dir and phase dir, refusing to compile context for archived `milestones/` paths (execution must target `.vbw-planning/phases/`).
2. Extracts the phase's `Goal`/`Reqs`/`Success` lines out of `ROADMAP.md` by `sed`-slicing the `## Phase {N}:` section.
3. Checks a V3 context cache (`cache-context.sh`) keyed by a content hash. On a cache hit it copies the cached file straight to `.context-{role}.md` and exits, recording a `cache_hit` metric via `collect-metrics.sh`.
4. On a cache miss, branches on `$ROLE` with a `case` statement that builds distinct output for six roles: `lead`, `dev`, `qa`, `scout`, `debugger`, `architect`. Each is written to its own `.context-{role}.md` (for example `.context-lead.md` gets requirements, `.context-dev.md` gets phase goal plus conventions, `.context-qa.md` gets verification targets, matching the split CLAUDE.md describes). An unrecognized role prints an error listing these six valid values.
5. Writes the compiled file back into the cache and updates `.vbw-planning/.cache/context-index.json` (an upsert keyed by content hash, fail-silent since the index is a non-critical introspection aid).

Optional inputs folded into the compiled context when present: `ROLLING-CONTEXT.md` (when `config.json`'s `rolling_summary` is true and the phase is beyond phase 1), `CONTEXT.md` (milestone scope context written by Scope mode), and caveman-style settings (`caveman_style`, `caveman_commit`, `caveman_review`) read from `config.json`.

## Model routing

`scripts/resolve-agent-model.sh <agent-name> <config-path> <profiles-path>` is the companion to context compilation: it decides which model (`opus`/`sonnet`/`haiku`) a given agent runs as. It validates against seven agent names: `lead`, `dev`, `qa`, `scout`, `debugger`, `architect`, `docs` (one more than `compile-context.sh`'s six context-compiling roles, since Docs doesn't get a phase-scoped `.context-docs.md`). It reads `config.json`'s `model_profile` (defaulting to `quality`), looks up the preset in `config/model-profiles.json`, applies any `model_overrides.{agent}` from `config.json`, and prints the resolved model string. Results are cached per-session at `/tmp/vbw-model-{agent}-{path-hash}-{config-hash}-{profiles-hash}`, keyed off content fingerprints (`md5sum`/`md5 -q`/`cksum`, whichever is available) of both input files plus a path hash, so parallel BATS workers using different temp repos never collide on the cache file. The resolved model string is passed as an explicit `model:` parameter on the `Task` tool call, since a session's `/model` setting does not propagate to subagents.

## How the pieces fit together

A typical plan-execution cycle touches all three systems in this doc:

1. `SubagentStart` fires `agent-start.sh` and `agent-health.sh start` as a Dev agent spawns.
2. The command that launched the agent already called `compile-context.sh` to produce `.context-dev.md` and `resolve-agent-model.sh` to pick its model.
3. As the Dev agent writes/edits files, `PostToolUse` hooks (`validate-frontmatter.sh`, `validate-commit.sh` on Bash, `skill-hook-dispatch.sh PostToolUse`, `state-updater.sh`) run after each tool call, updating `STATE.md` and catching malformed output early.
4. When the Dev agent writes its `SUMMARY.md`, `validate-summary.sh` checks it on `PostToolUse`. When the subagent exits, `SubagentStop` re-runs `validate-summary.sh` plus `agent-stop.sh` and `agent-health.sh stop`.
5. Every hook in this chain is wrapped by the same `hook-wrapper.sh` resolution cascade, so a missing plugin cache entry or a stale symlink degrades to a silent no-op rather than aborting the session.
