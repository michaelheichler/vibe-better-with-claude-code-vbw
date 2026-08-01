# Plugin Root Resolution Cascades

VBW resolves its own installed location through two separate cascades, one for hooks and one for slash commands, that share the same steps but run them in a different order on purpose.

## Why two cascades

`CLAUDE_PLUGIN_ROOT` is set in the platform's hook environment but is not exported into the shell that evaluates a slash command's `` !`command` `` template expansions. That single platform fact forces the split:

- **Hooks** fire automatically as part of normal Claude Code operation, in every install shape (marketplace cache, `--plugin-dir` local dev, marketplace-root). A hook must never break a session, so its cascade is written to always find something usable and to always exit 0.
- **Commands** run because the user explicitly typed `/vbw:...`. If the plugin is misconfigured, the user needs to see that immediately, so the command cascade fails loudly (`exit 1`) once every fallback is exhausted.

Both cascades are documented together in `CLAUDE.md` under "Plugin root resolution" and enforced by `testing/verify-plugin-root-resolution.sh`.

## Hook cascade (DXP-01)

Source: `scripts/hook-wrapper.sh` (151 lines). Every hook entry in `hooks/hooks.json` routes through this wrapper. The file's own `_note` field states the policy: "All hooks route through hook-wrapper.sh for graceful degradation (DXP-01) ... Logs failures to `.vbw-planning/.hook-errors.log`, and always exits 0."

Resolution order for the target script, cache-first because hooks fire in production and marketplace installs most often:

1. Versioned cache glob: `ls "$CACHE"/*/scripts/"$SCRIPT" | sort -V | tail -1`, where `CACHE="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"`
2. `CLAUDE_PLUGIN_ROOT` env var (fallback for `--plugin-dir` local-dev installs)
3. Sibling-script fallback: if the wrapper itself is running from a directory that contains `$SCRIPT` next to it, use that
4. Graceful no-op: `[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0`

If the resolved script exits non-zero, `hook-wrapper.sh` logs the failure and still exits 0, except for exit code 2, which it passes through unchanged because `PreToolUse` and `UserPromptSubmit` hooks use 2 to signal an intentional block, not a failure.

`hook-wrapper.sh` also contains a separate SIGHUP cleanup path (`cleanup_on_sighup`) that locates `agent-pid-tracker.sh` to terminate orphaned agent PIDs on terminal force-close. That lookup is its own small cascade: the same versioned-cache glob, then a sibling-script fallback next to the wrapper. It does not consult `CLAUDE_PLUGIN_ROOT` or the marketplace-root branch described below. It is scoped narrowly to the SIGHUP tracker path, not general script resolution.

The hook cascade is deliberately **not** merged with the command cascade. Its cache-first ordering, graceful `exit 0`, and exit-2 pass-through are all load-bearing policy for "no hook may break a session," and must stay unchanged.

## Command cascade

Source: `scripts/resolve-plugin-root.sh`. The nine-step command cascade is implemented exactly once, in that helper, rather than duplicated as a preamble in each command template. Every target command delegates to the helper through a short **session-link trampoline**.

`CLAUDE_PLUGIN_ROOT` is checked first here, because an explicit env var should win when the user is the one invoking the command:

1. `CLAUDE_PLUGIN_ROOT` env var, validated by checking `${CLAUDE_PLUGIN_ROOT}/scripts/${required_script}` exists (defaults to `hook-wrapper.sh`)
2. `cache/local` symlink: `${VBW_CACHE_ROOT}/local/scripts/${required_script}`
3. Versioned cache dir: numeric-looking subdirectories of `$VBW_CACHE_ROOT` filtered with `[[ "$name" =~ ^[0-9]+(\.[0-9]+)*$ ]]` and sorted with `sort -t. -k1,1n -k2,2n -k3,3n`, taking the highest
4. Generic cache dir fallback: same directory listing without the numeric filter, lexically sorted, taking the last entry
5. Marketplace-root branch (see below)
6. Exact-session symlink: `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`
7. Generic `/tmp` symlink glob: `$tmp_root/.vbw-plugin-root-link-*`, first match with a valid `scripts/${required_script}`
8. `ps axww -o args=` piped through `grep -oE -- "--plugin-dir [^ ]+"` to recover the directory passed to a local-dev `--plugin-dir` launch
9. Fail guard: if nothing resolved, print `"VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics."` to stderr and `exit 1`

After resolution the helper canonicalizes the path with `cd "$resolved_root" && pwd -P`, so it survives the cache symlink being deleted mid-session, then calls `scripts/ensure-plugin-root-link.sh` to repair the exact per-session link before printing the canonical root on stdout. A failure to repair the link is itself a fatal `exit 1` in command mode.

### Trampoline in the target commands

Each of the 19 target commands carries a standalone one-line backtick directive at the top, rendered inside a plain display fence after a `Plugin root:` label, that resolves the root and nothing else. The equivalent logic is expanded below across multiple lines for readability. The shipped command files keep the entire trampoline on one directive line:

```bash
SESSION_KEY="${CLAUDE_SESSION_ID:-default}"; SESSION_LINK="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
RESOLVER="${SESSION_LINK}/scripts/resolve-plugin-root.sh"
if [ ! -f "$RESOLVER" ]; then
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
    RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
  else echo "VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics." >&2; exit 1; fi
fi
bash "$RESOLVER" >/dev/null || exit 1
echo "$SESSION_LINK"
```

The trampoline reaches the helper through the deterministic session link (`$SESSION_LINK`), and falls back to `CLAUDE_PLUGIN_ROOT` only when that link is not yet a file. Because SessionStart creates the link before the first command runs (see "SessionStart bootstrap" below), the `$CLAUDE_PLUGIN_ROOT` branch is a defensive fallback for a fresh session whose SessionStart bootstrap lost the race, not the load-bearing path.

The five phase-detect preambles (`discuss.md`, `qa.md`, `resume.md`, `status.md`, `verify.md`) and `vibe.md` invoke the same helper, then run only their own phase-detect cache write, lock, and retry logic outside the helper. Their nested `_refresh_phase_detect_link` refresh blocks call the helper with `--require-script phase-detect.sh` rather than reproducing the fallback ordering themselves.

### Helper modes

`resolve-plugin-root.sh` exposes two opt-in modes that the command templates use:

- `--require-script <name>`: replace the default `hook-wrapper.sh` sentinel with another script name, so the five phase-detect preambles and `vibe.md` can ask the helper to validate `scripts/phase-detect.sh` instead of `scripts/hook-wrapper.sh`. The name must be a bare basename (no `/`, `.`, or `..`), enforced to prevent path traversal.
- `--nonfatal`: suppress the normal `exit 1` on total resolution failure and return `exit 0` instead. `commands/rtk.md` uses this for its JSON status block so an unresolvable root emits the existing observable `status_unavailable` object rather than the command-mode diagnostic. The `--nonfatal` mode is intentionally restricted to RTK status, not a general contract, because every other command needs the loud `exit 1` to surface misconfiguration.

### execute-protocol.md

`references/execute-protocol.md` no longer carries a divergent inline copy of the cascade. It delegates to `resolve-plugin-root.sh` through the same session-link trampoline, exports `VBW_PLUGIN_ROOT` once, and the rest of the Execute-mode instructions treat that variable as set. This also fixes the older copy's absent marketplace-root branch: Execute mode now resolves through the same nine-step helper as the slash commands.

### The marketplace-root branch

When a marketplace declares the plugin with `"source": "./"`, Claude Code installs it at `plugins/marketplaces/<name>/` (the repo root is the plugin) and creates no `plugins/cache/<name>/vbw/<version>/` copy. On a fresh session, `CLAUDE_PLUGIN_ROOT` is not exported to command bash expansions, there is no cache copy, and there is no `--plugin-dir` argument to recover from `ps`, but the exact `/tmp` session link normally exists because SessionStart creates it before the first command runs. The marketplace-root branch at step 5 is the in-cascade safety net when that bootstrap failed, raced, or the link was cleaned from `/tmp`.

Commit `9467b312` ("fix(resolver): resolve plugin root on marketplace-root (source:./) installs") added step 5, which scans `plugins/marketplaces/*/` and one level deeper `plugins/marketplaces/*/*` for a directory containing both `scripts/hook-wrapper.sh` (or the `--require-script` target) and `commands/vibe.md` as a sentinel. The branch lives in the shared helper now, so all 19 target commands and Execute mode inherit it.

The seven exempt commands (`compress.md`, `list-todos.md`, `pause.md`, `profile.md`, `teach.md`, `todo.md`, `uninstall.md`) carry no trampoline at all. They are covered by the contract test separately, as the "non-preamble" exemption class, and are tracked in `testing/verify-plugin-root-resolution.sh`'s `EXEMPT_COMMANDS` list.

That same commit added a sibling-script fallback to `hook-wrapper.sh`'s SIGHUP tracker lookup, but did not add an equivalent `plugins/marketplaces` branch to the hook cascade's main script-resolution logic (the four steps listed above). A marketplace-root install with no cache copy therefore still relies on the platform injecting `CLAUDE_PLUGIN_ROOT` directly into hooks (step 2) rather than a cascade-level marketplace scan, plus the SessionStart bootstrap link described below.

## Session symlink mechanism

Once the command helper resolves the root, it calls `scripts/ensure-plugin-root-link.sh` to create or repair a per-session symlink so later template expansions and hooks in the same session do not have to re-run the full cascade:

```text
/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}
```

`ensure-plugin-root-link.sh` exists specifically to avoid a race. A naive `rm -f "$LINK"; ln -s "$REAL_R" "$LINK"` sequence can have one parallel `!`-backtick block recreate the link between another block's `rm` and `ln`, causing `ln` to fail with `EEXIST`. The script checks the link's current target first and exits 0 immediately if it already points at the right directory, otherwise removes whatever is at the path (symlink, file, or stray directory from a corrupted older session) and retries the `ln -s`. It also rejects any link-path basename that does not match `.vbw-plugin-root-link-*` as a defensive guard against being called with the wrong argument.

Later readers, both inside the same command's later steps and in some hook fallback paths, construct the identical deterministic path independently via `echo "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"` rather than sharing a mutable temp file. There is no single shared `/tmp/.vbw-plugin-root` file in the current resolver design, and `verify-plugin-root-resolution.sh` explicitly checks for the absence of that legacy pattern.

### SessionStart bootstrap

SessionStart creates the link before the first command runs, so the trampoline can reach the helper without having resolved the root itself. `scripts/session-start.sh` derives the canonical root from its own `SCRIPT_DIR/..` location, validates that both `scripts/hook-wrapper.sh` and `scripts/ensure-plugin-root-link.sh` exist there, sanitizes the session id (falling back to `default` if it contains non-`[a-zA-Z0-9._-]` characters), and calls `ensure-plugin-root-link.sh` to create the deterministic link. If that bootstrap fails it logs `"VBW: SessionStart plugin root link bootstrap failed"` to stderr but does not fail the session.

This bridge matters most for the marketplace-root install shape, where there is no cache copy on a fresh session. It also bridges local-dev `--plugin-dir` installs by creating `${VBW_CACHE_ROOT}/local -> $CLAUDE_PLUGIN_ROOT`, and a low-priority `${VBW_CACHE_ROOT}/0.0.0-marketplace` link when the cache is empty but the marketplace directory exists, reducing but not replacing the helper's own fallback branches.

### Variable propagation through CLAUDE_ENV_FILE (T-301)

The trampoline relies on the session link, not on `CLAUDE_PLUGIN_ROOT` being exported into command bash, because that export is the one platform fact that forced the split. A separate question (spike T-301) was whether arbitrary variables written by SessionStart to `CLAUDE_ENV_FILE` become visible to later top-level command template expansions at all.

Spike verdict (`02-SPIKE-T301.md`, 2026-07-31): **pass** in both tested install shapes. A fresh first-command expansion received a SessionStart-written sentinel and its matching `CLAUDE_SESSION_ID` under both a `--plugin-dir` launch (session `70f8d1a3-...`) and a marketplace-root `"source":"./"` install with no cache copy (session `d448e106-...`), in each case scoped to the current session and resolved from the marketplace root itself.

As a secondary fast path, SessionStart therefore also exports the canonical root as `VBW_PLUGIN_ROOT` into `CLAUDE_ENV_FILE`, deduplicating it against an existing identical export. The per-session link remains the load-bearing bootstrap mechanism. The `VBW_PLUGIN_ROOT` export is a convenience for template expansions that read it directly, not a replacement for the link, and the helper's own validation still runs on every call. Static session-ID unit tests prove `session-start.sh` writes the variable. They do not by themselves prove generic environment propagation, which is why the runtime spike was required.

## Summary of the divergence

| | Hook cascade (DXP-01) | Command cascade |
|---|---|---|
| Source | `scripts/hook-wrapper.sh` | `scripts/resolve-plugin-root.sh`, invoked through the session-link trampoline in 19 `commands/*.md` and in `references/execute-protocol.md` |
| First check | versioned cache glob | `CLAUDE_PLUGIN_ROOT` |
| On total failure | `exit 0` (no-op, no hook may break a session) | `exit 1` with a diagnostic message (`exit 0` only under `--nonfatal`, used by RTK status) |
| Marketplace-root branch | not present in main script resolution | present in step 5 of the helper, inherited by all 19 target commands and Execute mode |
| Session symlink | consulted only as one of several fallback branches | created at SessionStart, repaired by the helper, then consulted by the trampoline and later steps |

This asymmetry is a deliberate consequence of who is running the code: the platform, automatically, for hooks, versus the user, explicitly, for commands. It is not an inconsistency to reconcile, but it is easy to misread the two orderings as copy-paste drift if you are not aware of the underlying constraint.