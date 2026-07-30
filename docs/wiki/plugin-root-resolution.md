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

## Command cascade

Source: the resolver preamble embedded in each of 19 command files (for example `commands/vibe.md`) and documented canonically in `references/execute-protocol.md` under "Runtime Plugin Root Resolution." `CLAUDE_PLUGIN_ROOT` is checked first here, because an explicit env var should win when the user is the one invoking the command:

1. `CLAUDE_PLUGIN_ROOT` env var, validated by checking `${CLAUDE_PLUGIN_ROOT}/scripts/hook-wrapper.sh` exists
2. `cache/local` symlink: `${VBW_CACHE_ROOT}/local/scripts/hook-wrapper.sh`
3. Versioned cache dir: numeric-looking subdirectories of `$VBW_CACHE_ROOT` filtered with `grep -E '^[0-9]+(\.[0-9]+)*$'` and sorted with `sort -t. -k1,1n -k2,2n -k3,3n`, taking the highest
4. Generic cache dir fallback: same directory listing without the numeric filter, lexically sorted, taking the last entry
5. Marketplace-root branch (see below)
6. Exact-session symlink: `/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}`
7. Generic `/tmp` symlink glob: `find -H /tmp -maxdepth 1 -name '.vbw-plugin-root-link-*'`, first match with a valid `scripts/hook-wrapper.sh`
8. `ps axww -o args=` piped through `grep -oE -- "--plugin-dir [^ ]+"` to recover the directory passed to a local-dev `--plugin-dir` launch
9. Fail guard: if nothing resolved, print `"VBW: plugin root resolution failed (checked CLAUDE_PLUGIN_ROOT, cache local/, versioned dirs, symlink fallback, process tree)."` to stderr and `exit 1`

After resolution the preamble canonicalizes the path with `cd "$VBW_PLUGIN_ROOT" && pwd -P`, so it survives the cache symlink being deleted mid-session.

`testing/verify-plugin-root-resolution.sh` locks this cascade down with three phases: inline-resolution safety (every `CLAUDE_PLUGIN_ROOT` reference in commands or references must sit inside a safe context, such as a `!` backtick block, an `@` file reference, or a guarded conditional, and never bare in model-executed prose), preamble fallback checks (every preamble `!`-backtick expansion of `${CLAUDE_PLUGIN_ROOT}` must carry a `:-` fallback), and runtime resolver safety (no legacy `/tmp/.vbw-plugin-root` shared temp file, canonical no-space link path present, `CLAUDE_SESSION_ID` used for session isolation, `pwd -P` used for canonical resolution). Running it locally currently reports all phases passing across the tracked command and reference files.

### The marketplace-root branch

When a marketplace declares the plugin with `"source": "./"`, Claude Code installs it at `plugins/marketplaces/<name>/` (the repo root is the plugin) and creates no `plugins/cache/<name>/vbw/<version>/` copy. On a fresh session every other cascade branch misses in that install shape: `CLAUDE_PLUGIN_ROOT` is not exported to command bash expansions, there is no cache copy, the `/tmp` session link does not exist yet (a chicken-and-egg problem on the first command), and there is no `--plugin-dir` argument to recover from `ps`.

Commit `9467b312` ("fix(resolver): resolve plugin root on marketplace-root (source:./) installs") added a branch, step 5 above, that scans `plugins/marketplaces/*/` and one level deeper for a directory containing both `scripts/hook-wrapper.sh` and `commands/vibe.md` as a sentinel. `grep -rl 'plugins/marketplaces' commands/*.md` currently matches 19 of the 26 files under `commands/`. The other 7 (`compress.md`, `list-todos.md`, `pause.md`, `profile.md`, `teach.md`, `todo.md`, `uninstall.md`) do not carry a resolver preamble at all and are covered separately by the "Todo Command Non-Preamble Resolver Contract" phase of the verify script.

That same commit added a sibling-script fallback to `hook-wrapper.sh`'s SIGHUP tracker lookup, but did not add an equivalent `plugins/marketplaces` branch to the hook cascade's main script-resolution logic (the four steps listed above). A marketplace-root install with no cache copy therefore still relies on the platform injecting `CLAUDE_PLUGIN_ROOT` directly into hooks (step 2) rather than a cascade-level marketplace scan.

## Session symlink mechanism

Once a command resolves `VBW_PLUGIN_ROOT`, it creates or repairs a per-session symlink so later template expansions and hooks in the same session do not have to re-run the full cascade:

```text
/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}
```

The link is created idempotently by `scripts/ensure-plugin-root-link.sh <link-path> <target-dir>`, invoked as `bash "$REAL_R/scripts/ensure-plugin-root-link.sh" "$LINK" "$REAL_R"`. The script exists specifically to avoid a race. A naive `rm -f "$LINK"; ln -s "$REAL_R" "$LINK"` sequence can have one parallel `!`-backtick block recreate the link between another block's `rm` and `ln`, causing `ln` to fail with `EEXIST`. `ensure-plugin-root-link.sh` checks the link's current target first and exits 0 immediately if it already points at the right directory, otherwise removes whatever is at the path (symlink, file, or stray directory from a corrupted older session) and retries the `ln -s`. It also rejects any link-path basename that does not match `.vbw-plugin-root-link-*` as a defensive guard against being called with the wrong argument.

Later readers, both inside the same command's later steps and in some hook fallback paths, construct the identical deterministic path independently via `echo "/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"` rather than sharing a mutable temp file. There is no single shared `/tmp/.vbw-plugin-root` file left in the current resolver design, and `verify-plugin-root-resolution.sh` phase 3 explicitly checks for the absence of that legacy pattern.

## Summary of the divergence

| | Hook cascade (DXP-01) | Command cascade |
|---|---|---|
| Source | `scripts/hook-wrapper.sh` | preambles in `commands/*.md`, documented in `references/execute-protocol.md` |
| First check | versioned cache glob | `CLAUDE_PLUGIN_ROOT` |
| On total failure | `exit 0` (no-op, no hook may break a session) | `exit 1` with a diagnostic message |
| Marketplace-root branch | not present in main script resolution | present in step 5, in 19 of 26 command files |
| Session symlink | consulted only as one of several fallback branches | created and repaired by the resolving command, then consulted by later steps |

This asymmetry is a deliberate consequence of who is running the code: the platform, automatically, for hooks, versus the user, explicitly, for commands. It is not an inconsistency to reconcile, but it is easy to misread the two orderings as copy-paste drift if you are not aware of the underlying constraint.
