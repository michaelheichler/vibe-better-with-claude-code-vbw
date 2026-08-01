---
phase: 2
plan: 4
title: Align docs with the consolidated resolver and close out the phase
status: complete
completed: 2026-07-31
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 012aa44
  - 6403c82
  - c1acbed
files_modified:
  - docs/wiki/plugin-root-resolution.md
  - AGENTS.md
  - .vbw-planning/phases/02-structural-resolution-consolidation/02-04-CLOSEOUT.md
deviations:
  - "Task 2 edited AGENTS.md (the real file behind the CLAUDE.md symlink) rather than the CLAUDE.md symlink path itself, because the Edit tool refuses to write through symlinks. The plan was amended to list AGENTS.md in files_modified with a scope note."
pre_existing_issues:
  - '{"test":"bats parallel: phase-detect.bats line 2865 qa_status pending when PASS verification is stale for current code","file":"tests/phase-detect.bats:2865","error":"Failed once under parallel bats-worker-1 shard on the first run-all.sh pass, then passed in isolation (bats --filter) and on a clean full re-run (3700 passed, 0 failed). Docs-only plan 02-04 commits cannot regress phase-detect logic. Declared flaky, not re-fixed."}'
ac_results:
  - criterion: "docs/wiki/plugin-root-resolution.md names scripts/resolve-plugin-root.sh as the single command-cascade source of truth and no longer describes per-command inline cascades as current"
    verdict: pass
    evidence: "Wiki rewritten in commit 012aa44. grep -c resolve-plugin-root.sh docs/wiki/plugin-root-resolution.md returns 7. grep for stale prose (preamble embedded in each / documented canonically in execute-protocol / carries a canonical) returns 0."
  - criterion: "CLAUDE.md Plugin root resolution section describes the trampoline-plus-helper command cascade while keeping the hook cascade (DXP-01) description unchanged in policy"
    verdict: pass
    evidence: "AGENTS.md (real file behind the CLAUDE.md symlink) updated in commit 6403c82. Diff confined to the Command cascade block: now names resolve-plugin-root.sh, the nine-step order with marketplace-root scan at step 5, --require-script/--nonfatal modes, and SessionStart bootstrap. Hook cascade (DXP-01) block left byte-for-byte unchanged."
  - criterion: "Docs describe the SessionStart session-link bootstrap and record the T-301 spike outcome"
    verdict: pass
    evidence: "Wiki adds a SessionStart bootstrap subsection and a Variable propagation through CLAUDE_ENV_FILE (T-301) subsection citing 02-SPIKE-T301.md with the pass verdict in both --plugin-dir and marketplace-root install shapes. AGENTS.md notes SessionStart bootstraps the deterministic session link from its own SCRIPT_DIR/.. location."
  - criterion: "correct the stale claim that references/execute-protocol.md carries a canonical inline copy"
    verdict: pass
    evidence: "Wiki execute-protocol.md subsection now states it no longer carries a divergent inline copy and delegates to resolve-plugin-root.sh through the same session-link trampoline."
  - criterion: "keep the hook-cascade section and the exemption list of seven non-preamble commands accurate"
    verdict: pass
    evidence: "Hook cascade (DXP-01) section preserved verbatim. The seven exempt commands (compress.md, list-todos.md, pause.md, profile.md, teach.md, todo.md, uninstall.md) are listed in the marketplace-root subsection, matching testing/verify-plugin-root-resolution.sh:39 EXEMPT_COMMANDS."
  - criterion: "cascade is defined once (grep counts across commands/ and references/ show zero inline cascade fragments and one helper implementation)"
    verdict: pass
    evidence: "02-04-CLOSEOUT.md records: grep for marketplace/numeric-cache-sort/ps-axww fragments outside the helper and wiki returns 0. ls scripts/resolve-plugin-root.sh count is 1. 19 command files invoke the helper. references/execute-protocol.md invokes the helper at lines 11/13/14."
  - criterion: "marketplace-root resolution has evidence (02-03-SMOKE.md)"
    verdict: pass
    evidence: "02-03-SMOKE.md exists with a Marketplace-root section (1 heading match) recording four fresh-session runs (two --plugin-dir, two source \"./\" with cache removed), all exit 0 resolving to the plugin root. T-301 spike independently confirms SessionStart sentinel visibility in both install shapes."
  - criterion: "bash testing/run-all.sh green"
    verdict: pass
    evidence: "Final run-all.sh reported Lint 1/1, Contracts 54/54, BATS 3700 passed / 0 failed. One first-run flake in tests/phase-detect.bats:2865 (parallel-ordering, passes in isolation and on re-run) declared in pre_existing_issues."
---

## What Was Built

- Rewrote `docs/wiki/plugin-root-resolution.md` to name `scripts/resolve-plugin-root.sh` as the single command-cascade source of truth, documenting the nine-step order, the `--require-script` and `--nonfatal` modes, the session-link trampoline used by the 19 target commands, the SessionStart bootstrap, and the T-301 spike pass verdict. Corrected the stale claim that `references/execute-protocol.md` carries a canonical inline copy. Kept the hook-cascade (DXP-01) section and the seven-command exemption list accurate.
- Updated the CLAUDE.md (real file `AGENTS.md`) Plugin root resolution Key Patterns section to describe the consolidated helper, its nine-step order with the marketplace-root scan at step 5, the trampoline, the `--require-script`/`--nonfatal` modes, and the SessionStart bootstrap. The hook-cascade (DXP-01) block was left semantically unchanged.
- Ran `bash testing/run-all.sh` as phase close-out. Final run green: Lint 1/1, Contracts 54/54, BATS 3700 passed / 0 failed. Gathered grep-count evidence for both phase success criteria into `02-04-CLOSEOUT.md`.

## Files Modified

- `docs/wiki/plugin-root-resolution.md` -- full rewrite around the shared helper (commit 012aa44).
- `AGENTS.md` -- CLAUDE.md Plugin root resolution section updated for the consolidated resolver (commit 6403c82).
- `.vbw-planning/phases/02-structural-resolution-consolidation/02-04-CLOSEOUT.md` -- phase close-out with run-all result and grep-count evidence (commit c1acbed).

## Phase Success Criteria

- [x] Documentation describes the single-definition command cascade and preserved hook policy.
- [x] Phase success criterion A (cascade defined once): 0 inline cascade fragments outside the helper, 1 helper implementation, 19 target commands delegating.
- [x] Phase success criterion B (marketplace-root still resolves): evidenced by `02-03-SMOKE.md` and `02-SPIKE-T301.md`.
- [x] `bash testing/run-all.sh` green (final run).