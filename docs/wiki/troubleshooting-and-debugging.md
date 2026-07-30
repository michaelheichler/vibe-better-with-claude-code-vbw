# Troubleshooting and Debugging VBW

Practical guide for diagnosing VBW misbehavior: resolving a local debug target repo, locating session transcripts and logs, common search patterns, and which command to run for which situation.

## Start here: which command do I run?

- **`/vbw:doctor`** - health check on the plugin install and the current project. Run this first for "something feels off" reports: missing files, config parse errors, stale teams, orphaned processes, RTK integration status. Add `--cleanup` to apply fixes for the checks that support it.
- **`/vbw:debug "description"`** - investigate an actual bug in the target project's code using the Debugger agent's reproduce/hypothesize/fix protocol. This is for bugs in the *project VBW is managing*, not bugs in VBW itself.
- **`/vbw:report "description"`** - collect diagnostics (`scripts/collect-diagnostics.sh`) and file a GitHub issue against the VBW repo itself. Use this once you've confirmed the misbehavior is in VBW, not in the target project.
- **`/vbw:status`** - project progress dashboard (phase status, velocity, next action). Not a debugging tool per se, but often the fastest way to see whether VBW's state model matches what you expect.

This page covers the manual investigation path: reading transcripts and logs directly when `/vbw:doctor` and `/vbw:report` aren't enough on their own.

## Step 1: resolve the local debug target repo

When someone reports VBW misbehavior in a *consumer* project (pasted session output, a command that did the wrong thing, unexpected file state), you first need the path to that consumer/test repo. VBW resolves this via `scripts/resolve-debug-target.sh`, which checks, in order:

1. `VBW_DEBUG_TARGET_REPO` env var, a one-off override that must be an absolute path.
2. `$(git rev-parse --git-common-dir)/info/vbw-debug-target.txt` in the current clone, the preferred persistent config, shared across all worktrees created from that clone. In a standard non-worktree checkout this resolves to `.git/info/vbw-debug-target.txt`.
3. `<plugin-root>/.claude/vbw-debug-target.txt`, a legacy fallback scoped to a single checkout/worktree. Gitignored, and not copied into new worktrees.
4. `<claude-config-dir>/vbw/debug-target.txt`, a user-global fallback. `<claude-config-dir>` is resolved by `scripts/resolve-claude-dir.sh`: `CLAUDE_CONFIG_DIR` if set, else `$HOME/.config/claude-code` when that directory exists, else `$HOME/.claude`.
5. If none of the above are configured, the script exits non-zero. Do not guess a path. Ask the user for the target repo.

Each config file's first non-empty, non-comment line must be an absolute path to the contributor's primary VBW consumer/test repo. Relative paths are rejected.

Use the script directly instead of re-deriving these paths by hand:

```bash
TARGET_REPO=$(bash scripts/resolve-debug-target.sh repo)
TARGET_PLANNING=$(bash scripts/resolve-debug-target.sh planning-dir)
ENCODED_PATH=$(bash scripts/resolve-debug-target.sh encoded-path)
CLAUDE_PROJECT_DIR=$(bash scripts/resolve-debug-target.sh claude-project-dir)
```

Other supported fields: `source` (which config file won) and `all` (prints every field as `key=value` lines). If the script exits non-zero, stop and ask the user to configure a debug target rather than guessing.

## Step 2: find the logs

Claude Code encodes an absolute project path by replacing every `/` with `-`. For an absolute path the result begins with `-`:

```text
/absolute/path/to/project  ->  -absolute-path-to-project
```

`scripts/resolve-debug-target.sh encoded-path` computes this for you from the resolved target repo, and `claude-project-dir` gives you the full `<claude-config-dir>/projects/{encoded-path}` path directly.

Once you have the target repo and its encoded path, these locations hold the evidence:

| Path | Contents | Use when |
| ------ | ---------- | ---------- |
| `<target-repo>/.vbw-planning/` | Project state (phases, milestones, config, `STATE.md`) | Grounding the investigation in actual workflow state |
| `<claude-config-dir>/projects/{encoded-path}/*.jsonl` | Session transcripts | Replaying what the LLM said/did in a session |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/subagents/agent-*.jsonl` | Subagent transcripts | Checking what a VBW agent team member did |
| `<claude-config-dir>/projects/{encoded-path}/{session-id}/tool-results/` | Tool output snapshots | Seeing exact tool outputs from a session |
| `<claude-config-dir>/debug/{session-id}.txt` | Debug logs (`[DEBUG]`/`[WARN]`) | Startup issues, plugin loading, hook execution failures |
| `<claude-config-dir>/sessions/{pid}.json` | Active session metadata | Mapping a PID to a session ID |
| `<claude-config-dir>/session-env/{session-id}/` | Hook-exported env vars | Verifying `CLAUDE_SESSION_ID` and other env vars |
| `<claude-config-dir>/tasks/{session-id}/` | Task/subagent lock files | Checking for stuck or concurrent task issues |
| `<claude-config-dir>/settings.json` | User-level Claude Code settings and hooks | Verifying hook definitions, permissions, MCP config |

## Common search patterns

```bash
TARGET_REPO=$(bash scripts/resolve-debug-target.sh repo)
CLAUDE_PROJECT_DIR=$(bash scripts/resolve-debug-target.sh claude-project-dir)
CLAUDE_CONFIG_ROOT="$(dirname "$(dirname "$CLAUDE_PROJECT_DIR")")"

# Find sessions for the configured target repo
ls "$CLAUDE_PROJECT_DIR"/*.jsonl

# Search session transcripts for a VBW hook or command
grep -l 'vbw' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Find hook errors in debug logs
grep -El 'hook.*error|hook.*fail' "$CLAUDE_CONFIG_ROOT"/debug/*.txt

# Search for a specific tool invocation across sessions
grep -Erl 'bootstrap-state|state-updater' "$CLAUDE_PROJECT_DIR"/*.jsonl

# Check what a subagent did in a specific session
cat "$CLAUDE_PROJECT_DIR"/<session-id>/subagents/agent-*.jsonl
```

Session transcripts and tool-result snapshots are JSON/JSONL. Parse them with `jq`, not grep/sed, once you've located the relevant lines with the patterns above.

## `/vbw:doctor` in detail

`commands/doctor.md` runs 18 numbered checks and reports PASS/WARN/FAIL for each, then a summary line (`Result: {N}/18 passed, {W} warnings, {F} failures`). Checks cover, in order: `jq` availability, `VERSION` file presence, version sync across the 4 version files, plugin cache presence, `hooks.json` validity, the 7 agent files, project `config.json` validity, script executable bits, `gh` CLI availability, `sort -V` support, then runtime health: stale agent teams, orphaned processes, dangling PIDs, stale markers, watchdog status (tmux only), `CLAUDE.md` section staleness, `.vbw-planning/` state consistency, and RTK integration status.

Any WARN from the stale-team/process/marker checks, `CLAUDE.md` staleness, or state-consistency checks can be cleared with:

```text
/vbw:doctor --cleanup
```

This runs `scripts/doctor-cleanup.sh cleanup` for runtime findings and `scripts/check-claude-md-staleness.sh --fix` for a stale `CLAUDE.md`. The fix refreshes only VBW-owned sections in place and preserves the rest of the file verbatim.

`/vbw:doctor` is read-only diagnosis by default. It does not touch project files unless you pass `--cleanup`.

## `/vbw:debug` in detail

`commands/debug.md` investigates a bug in the target project's own code (not VBW itself) using the Debugger agent's protocol: bootstrap, reproduce, hypothesize, gather evidence, diagnose, fix, verify, document. Invocation forms:

```text
/vbw:debug "description of the bug or error message" [--competing|--parallel|--serial]
/vbw:debug <todo-number> [--competing|--parallel|--serial]
/vbw:debug --resume
/vbw:debug --session <id>
```

Routing between a single Debugger (Path B) and three competing-hypothesis investigators (Path A) is governed by the project's `prefer_teams` config plus an ambiguity classifier. The classifier looks for keywords like "intermittent", "flaky", or "sporadic", multiple candidate root-cause areas, or previously reverted fixes in `git log`. `--competing`/`--parallel` force Path A. `--serial` forces Path B.

Debug sessions persist to `.vbw-planning/` and carry a lifecycle status (`investigating`, `qa_pending`, `qa_failed`, `uat_pending`, `uat_failed`, `complete`). `--resume` picks the active or latest unresolved session back up at whatever stage it was left, including jumping straight to inline QA or UAT when a fix was already applied.

## Other diagnostic entry points

- **`/vbw:report "description"`** (`commands/report.md`) runs `scripts/collect-diagnostics.sh`, displays the report, classifies the issue as `bug` or `feature`, and files it against `swt-labs/vibe-better-with-claude-code-vbw` via `gh` CLI, GitHub MCP, or a manual fallback link. It only collects diagnostics and files the issue. It does not modify project state.
- **`/vbw:status [--verbose] [--metrics]`** (`commands/status.md`) shows phase/plan progress, velocity, and (with `--metrics`) RTK external metrics. Useful for confirming VBW's own view of project state before digging into transcripts.
- **Destructive-command blocking**: if a report involves a Bash command being unexpectedly blocked (or, more urgently, one that should have been blocked but wasn't), see [`../database-safety-guard.md`](../database-safety-guard.md) for the three-layer defense (`bash-guard.sh` PreToolUse hook, agent prompt rules, `forbidden_commands` contract) and how to extend or override the blocklist.

## Plugin root resolution failures

Several of the paths above assume plugin root resolution succeeded. If a command reports `VBW: plugin root resolution failed`, the resolution cascade (`CLAUDE_PLUGIN_ROOT` env var, `cache/local` symlink, versioned cache dir, generic cache dir fallback, `/tmp/.vbw-plugin-root-link-*` symlink glob, `ps axww --plugin-dir` extraction) failed at every step. Check:

- `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/cache/vbw-marketplace/vbw/` has at least one version directory (`/vbw:doctor` check 4 covers this).
- The `--plugin-dir` flag, if used, points at a directory containing `scripts/hook-wrapper.sh`.
- `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`, the session symlink commands create after resolving the root, actually points somewhere valid.

Hooks resolve the plugin root independently and always exit 0 regardless of outcome, since no hook can break a session. A hook-side resolution failure therefore shows up as silent no-op behavior rather than an error. Check `<claude-config-dir>/debug/{session-id}.txt` for `[WARN]`/`[DEBUG]` lines from `scripts/hook-wrapper.sh` in that case.
