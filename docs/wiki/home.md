# VBW Wiki: Overview and Getting Started

VBW is a Claude Code plugin that bolts a plan-execute-verify development lifecycle onto Claude Code sessions.

## What VBW is

Vibe Better With Claude Code (VBW) is a Claude Code plugin: 26 slash commands, 7 specialized agents, and 30 hooks across 11 event types, all implemented as 228 shell scripts plus markdown, with zero non-shell external dependencies beyond `jq` and `git` (and a supported Bash 4.4+ runtime). Current version is 1.37.1 (see `VERSION`). There is no package.json, no npm, and no build step, the whole plugin is bash scripts and markdown consumed by Claude Code and by the agents it spawns.

## The plan-execute-verify lifecycle in one paragraph

You describe what you want, and VBW breaks the work into phases: a Scout agent maps the codebase, an Architect and Lead turn the goal into a plan, Dev agents (run as a coordinated team when a plan has real parallel work, or serialized when the work is a dependency chain) write the code, QA verifies it goal-backward against the plan rather than rubber-stamping the diff, and a Docs agent keeps documentation in sync. State persists across sessions in `.vbw-planning/` (`STATE.md`, `ROADMAP.md`, `PROJECT.md`, `REQUIREMENTS.md`, `config.json`, and per-phase `phases/{NN}-{slug}/PLAN.md` plus `SUMMARY.md`), so `/vbw:init` once and then `/vbw:vibe` repeatedly is enough to drive an entire project: `init`, then `vibe` (repeat), then `vibe --archive`.

## Install and load VBW

There are two ways to run VBW, depending on whether you are a consumer of the plugin or working on VBW itself.

### Marketplace install (for using VBW in your own projects)

Inside a Claude Code session:

```text
/plugin marketplace add michaelheichler/vibe-better-with-claude-code-vbw
/plugin install vbw@vbw-marketplace
```

This resolves VBW from the marketplace plugin cache. It is the normal path for anyone who wants to use VBW's commands and agents on their own codebase.

### `--plugin-dir` (for contributing to VBW itself)

If you are working on the VBW repo itself, load your local clone directly instead of the marketplace copy:

```bash
# From inside the VBW repo (quick smoke test)
claude --plugin-dir .

# From any other project (the typical case, testing VBW against a real codebase)
cd ~/repos/my-other-project
claude --plugin-dir /absolute/path/to/vibe-better-with-claude-code-vbw
```

All `/vbw:*` commands load from your local copy this way. Restart Claude Code to pick up changes after editing VBW files, and make sure you're on the branch with your changes checked out, since `--plugin-dir` loads whatever is on disk, branch included.

For a more permanent local dev setup (symlinked plugin cache, cleared command cache, git pre-push hook, optional `claude-vbw` launcher), run `bash scripts/dev-setup.sh` from the repo root and see `CONTRIBUTING.md` for the full walkthrough, including how to revert to the marketplace version with `bash scripts/dev-setup.sh --teardown`.

### Prerequisites

- Bash 4.4+ is required. Bash 5+ is recommended. macOS's bundled /bin/bash 3.2 is unsupported. Ensure `bash --version` resolves to Bash 4.4 or newer before running VBW or `testing/run-all.sh`.
- Claude Code v1.0.33+ with Opus 4.6+
- Agent Teams enabled
- `jq` and `git` on the machine (VBW's only two non-shell runtime dependencies)

## The two-command loop

Once installed, the day-to-day workflow is two commands:

```text
/vbw:init          # bootstrap .vbw-planning/ for the project
/vbw:vibe          # plan, execute, verify (repeat per phase)
/vbw:vibe --archive  # close out a milestone
```

`/vbw:vibe` auto-detects project state and natural-language intent, so you rarely need explicit flags (`--plan`, `--execute`, `--discuss`, `--assumptions`, and more exist for granular control when you want it).

## Map of the wiki

This page is the entry point. The rest of the wiki goes deeper on each part of the system:

- [Commands](./commands.md), the full `/vbw:*` command reference (26 commands, including `vibe`, `map`, `verify`, `debug`, `qa`, `status`, `config`).
- [Agents](./agents.md), the 7 agent roles (Scout, Architect, Lead, Dev, QA, Debugger, Docs), their tool permissions, and how Agent Teams coordinate parallel Dev work.
- [Hooks and Verification](./hooks.md), the 30 hooks across 11 event types that enforce quality gates automatically, including the database safety guard and plugin-root resolution.
- [Configuration](./configuration.md), `config.json`, model profiles (quality/balanced/budget), effort levels, worktree isolation, and the other switches behind the guardrails.
- [State and Templates](./state-and-templates.md), the `.vbw-planning/` directory layout, artifact templates, and how context compilation keeps each agent's prompt lean.
- [Contributing and Debugging](./contributing-and-debugging.md), local dev setup, the required fix workflow (issue, branch, draft PR, automated QA), testing tiers, and how to debug VBW behavior against a target repo.

## Where the source material lives

This page draws from `README.md` (project description, feature list, lifecycle loop), `CONTRIBUTING.md` (local dev setup and `--plugin-dir` instructions), `CLAUDE.md` (architecture summary), and `VERSION`. Consult those files directly for anything not yet covered by a wiki page above.
