# Plan 02-04 Phase Close-Out

Date: 2026-07-31
Branch: refactor/vibe-remediation

## Run-all.sh result

`bash testing/run-all.sh` (run directly, no tail/tee wrappers).

First run:

```text
Lint checks: 1/1 passed
Contract checks: 54/54 passed
BATS: 3699 passed, 1 failed
```

The single failure was `tests/phase-detect.bats:2865` ("qa_status is pending when PASS verification is stale for current code"). Root-cause investigation:

- The failure is in `tests/phase-detect.bats`, under the `bats-worker-1` parallel shard.
- This plan's commits (012aa44, 6403c82) touch only `docs/wiki/plugin-root-resolution.md` and `AGENTS.md` (the real file behind the `CLAUDE.md` symlink), both docs-only prose edits in the Plugin root resolution section. No script or command logic changed, so this failure cannot be a regression from plan 02-04.
- Isolated rerun: `bats --filter "stale for current code" tests/phase-detect.bats` reported `ok 1` (passed).
- Full re-run of `bash testing/run-all.sh` reported:

```text
Lint checks: 1/1 passed
Contract checks: 54/54 passed
BATS: 3700 passed, 0 failed

All checks completed.
```

The first-run loss was a parallel-load flake in `phase-detect.bats`, not a real regression. It is not the known `rtk-manager.bats:2058` flake from phase 01/plan 02-03 (a different file and different mechanism). It is a new but genuinely flaky parallel-ordering case that passes in isolation and on a clean re-run. Declared as pre-existing/flaky per the zero-tolerance policy (investigated, isolated rerun passed, full re-run green), not re-fixed.

Final verdict: suite green.

## Criterion A: cascade defined once (grep-count evidence)

Command:

```bash
grep -rEln "plugins/marketplaces|sort -t\..*-k3,3n|ps axww.*--plugin-dir" commands/ references/ 2>/dev/null \
  | grep -vE 'resolve-plugin-root.sh|plugin-root-resolution.md' | wc -l
```

Result: `0` inline cascade fragments outside the helper and the wiki.

Helper implementation count:

```bash
ls -1 scripts/resolve-plugin-root.sh | wc -l
```

Result: `1`.

Target commands invoking the helper through the session-link trampoline:

```bash
grep -rEln 'resolve-plugin-root\.sh' commands/ 2>/dev/null | wc -l
```

Result: `19` (matches the intended 19-command scope).

Files:

```text
commands/config.md      commands/fix.md      commands/qa.md      commands/status.md    commands/vibe.md
commands/debug.md        commands/help.md     commands/report.md   commands/update.md     commands/whats-new.md
commands/discuss.md      commands/init.md    commands/research.md commands/verify.md
commands/doctor.md       commands/map.md     commands/resume.md   commands/rtk.md
commands/skills.md
```

`references/execute-protocol.md` invokes the helper (no longer a divergent inline copy):

```text
references/execute-protocol.md:11:RESOLVER="${SESSION_LINK}/scripts/resolve-plugin-root.sh"
references/execute-protocol.md:13:  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh" ]; then
references/execute-protocol.md:14:    RESOLVER="${CLAUDE_PLUGIN_ROOT}/scripts/resolve-plugin-root.sh"
```

`commands/rtk.md` uses the `--nonfatal` mode (1 occurrence), preserving its observable `status_unavailable` JSON path.

Conclusion for criterion A: the command cascade is defined exactly once in `scripts/resolve-plugin-root.sh`, invoked by all 19 target commands and by `references/execute-protocol.md`, with zero inline cascade fragments remaining outside the helper.

## Criterion B: marketplace-root resolution evidence

`02-03-SMOKE.md` exists and records the marketplace-root verdict:

```bash
test -f .vbw-planning/phases/02-structural-resolution-consolidation/02-03-SMOKE.md && echo exists
grep -c 'Marketplace-root' .../02-03-SMOKE.md
```

Result: file exists. The `Marketplace-root` heading is present (1 match). The smoke doc records four fresh-session runs: two under `--plugin-dir` and two under a marketplace-root `"source":"./"` install with the versioned cache removed before each session. `/vbw:help` and `/vbw:status` both rendered exit 0 with the expected session link pointing at the plugin root in every case, and the marketplace-root run resolved from the marketplace root itself with the cache absent. The T-301 spike (`02-SPIKE-T301.md`) independently confirms that a SessionStart-written sentinel reaches the first command in both install shapes, supporting the SessionStart bootstrap link path.

Conclusion for criterion B: marketplace-root resolution evidence exists and is sufficient.

## Docs naming the helper as canonical

```bash
grep -c 'resolve-plugin-root.sh' docs/wiki/plugin-root-resolution.md AGENTS.md
```

Result:

```text
docs/wiki/plugin-root-resolution.md:7
AGENTS.md:1
```

Both documentation surfaces now name `scripts/resolve-plugin-root.sh` as the single command-cascade source of truth.

## Phase success criteria

- [x] Documentation describes the single-definition command cascade and preserved hook policy (Tasks 1 and 2).
- [x] Phase success criterion A (cascade defined once) evidenced above.
- [x] Phase success criterion B (marketplace-root still resolves) evidenced by `02-03-SMOKE.md` and `02-SPIKE-T301.md`.
- [x] `bash testing/run-all.sh` green (final run).