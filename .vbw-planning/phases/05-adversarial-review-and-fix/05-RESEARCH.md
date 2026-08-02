---
phase: 5
title: Adversarial review of phases 1 through 4
type: research
confidence: high
date: 2026-08-02
---

## Findings

All five findings are resolved in the current branch. The original severity is retained for historical context.

### Plugin-root resolution

1. **[resolved, major] Cache resolution validates ordered candidates until it finds the first usable root.**
   - Commit `e22a02ac` replaced the single-candidate checks with ordered iteration.
   - Current `scripts/resolve-plugin-root.sh` lines 88-110 collect and rank numeric entries, then call `valid_root` for each candidate. Lines 112-133 do the same for generic entries.
   - Regression cases in `tests/resolve-plugin-root.bats` cover an invalid newest numeric entry, no valid numeric fallback, and an invalid lexically last generic entry.

2. **[resolved, major] Marketplace and process fallbacks require VBW identity.**
   - Commit `8cd480fd` added `valid_vbw_root`. Current lines 48-53 require `.claude-plugin/plugin.json` and a `name` value of `vbw`.
   - The marketplace loop uses this check at lines 135-143. The process fallback uses it at lines 159-179. Explicit and cache roots retain their original trust model.
   - Regression cases reject valid-looking non-VBW collisions in both fallback sources.

3. **[resolved, minor] Process fallback preserves quoted `--plugin-dir` paths containing spaces.**
   - Commit `c2876e7a` added quoted argument extraction and quote removal.
   - Current lines 161-173 remove surrounding single or double quotes. Line 179 extracts quoted values as one path before `valid_vbw_root` validates them.
   - Regression cases cover both single-quoted and double-quoted paths with spaces. Escaped unquoted spaces remain an explicit documented ceiling at line 178.

### Map and stack inference

4. **[resolved, major] The mobile mappings are merged into one top-level category.**
   - Commit `0362a046` consolidated the duplicate objects in `config/stack-mappings.json`.
   - `jq -c '.mobile | keys' config/stack-mappings.json` now returns `android-kotlin`, `flutter`, `ios-swift`, `react-native`, and `swiftui`.
   - `tests/detect-stack.bats` contains a top-level duplicate-key integrity check and detector cases for Android Kotlin, Flutter, and React Native.

### Shell portability

5. **[resolved, minor] All SessionStart cache-version callers share the portable sort fallback.**
   - Commit `f3171157` added the first BSD fallback. Follow-up commit `ce969141` centralized it in `sort_cache_versions` and routed every cache operation through that helper.
   - Current `scripts/session-start.sh` lines 547-554 define the GNU and BSD paths. Cache cleanup, integrity checking, and marketplace auto-sync call the helper at lines 579, 594, and 611.
   - `tests/session-start.bats` contains separate BSD-like sort cases for all three callers.

## Relevant Patterns

- Phase 01 repaired the missing planning-git fallback diagnostic, documented AskUserQuestion metadata, removed the obsolete `find_skills_available` gate, and documented the Bash 4.4 runtime floor. Evidence is in `01-01-SUMMARY.md`.
- Phase 02 added the shared command resolver, SessionStart session-link bootstrap, and resolver BATS coverage. Phase 05 hardened the resolver with ordered validation, identity checks, and quoted-path handling.
- Phase 03 hardened map META parsing and stack inference. Phase 05 restored all mobile profiles and added duplicate-key protection.
- Phase 04 centralized the shutdown, non-team spawn, and no-tool text in `references/subagent-contracts.md`. Its verifier remains the structural guard for that work.
- The resolver, mobile mappings, and SessionStart portability fixes now have behavior-level regression cases rather than prose-only checks.

## Risks

- The cache masking, cross-plugin selection, quoted-path truncation, lost mobile profiles, and BSD sort failure modes described above are closed in the current code.
- Escaped unquoted spaces in process arguments remain outside the parser contract. The named ceiling at `scripts/resolve-plugin-root.sh:178` states when shell-argument parsing would be needed.
- Runtime command behavior still needs integrated smoke coverage in addition to static contract checks. This is a validation concern, not an open instance of any finding above.

## Validation Status

- Resolver regression coverage includes invalid preferred candidates, plugin identity collisions, and quoted paths.
- Stack regression coverage includes duplicate top-level categories and all three formerly unreachable mobile profiles.
- SessionStart regression coverage exercises the BSD fallback through cleanup, integrity checking, and marketplace auto-sync.
- The full repository gate passed on 2026-08-02 with 56/56 contracts, 3,769 BATS tests, and lint clean. No additional remediation task is required for these five findings.
