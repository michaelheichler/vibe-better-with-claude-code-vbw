---
phase: 5
title: Adversarial review of phases 1 through 4
type: research
confidence: high
date: 2026-08-02
---

## Findings

### Plugin-root resolution

1. **[major] `scripts/resolve-plugin-root.sh:92-96,108-112` validates only the single highest-ranked cache candidate, so an invalid newer entry masks a usable older entry.**
   - The numeric branch collects every numeric directory name, selects only the greatest name at line 93, then calls `valid_root` once. The generic branch repeats the same pattern at lines 108-112.
   - Example: with valid `1.38.8` and a stale or partial `1.39.0` that lacks `scripts/hook-wrapper.sh`, numeric resolution leaves `resolved_root` empty instead of choosing `1.38.8`. The generic fallback includes the same names and can select the invalid `1.39.0` again. If there is no marketplace, session link, or process fallback, a usable cache installation fails with exit 1.
   - `tests/resolve-plugin-root.bats:72-95` covers two valid numeric candidates and two valid generic candidates, but has no case where the preferred candidate is invalid and a lower-ranked candidate is valid.
   - Fix scope: sort candidates in the documented preference order, validate each candidate in that order, and stop at the first valid root. Add BATS cases for an invalid newest numeric entry and an invalid lexically last generic entry, including the no-lower-fallback environment.

2. **[major] `scripts/resolve-plugin-root.sh:118-123,141-145` can select an unrelated plugin root when cache and session-link sources are unavailable.**
   - The marketplace fallback accepts any directory beneath `plugins/marketplaces` that has `scripts/hook-wrapper.sh` and `commands/vibe.md`. It does not verify that the candidate is the VBW plugin. The process fallback similarly accepts the first `--plugin-dir` path found anywhere in `ps` output if it has a hook wrapper.
   - A second installed plugin with these common file names, or another active Claude process using such a plugin, can become the root selected for VBW. The resolver then repairs the per-session link to that unrelated directory, which makes later VBW script calls execute the wrong plugin files.
   - VBW has stable identity data in `.claude-plugin/plugin.json:2`, where `name` is `vbw`. The current resolver tests create only one marketplace candidate and use fixtures without a plugin manifest, so they do not test identity or collision handling.
   - Fix scope: require an unambiguous VBW identity check for marketplace and process-derived candidates, then add collision tests with a valid-looking non-VBW candidate preceding a real VBW candidate. Keep explicit and cache precedence unchanged unless their source trust model also requires identity validation.

3. **[minor] `scripts/resolve-plugin-root.sh:141-142` cannot recover a `--plugin-dir` path containing spaces.**
   - The expression `grep -oE -- "--plugin-dir [^ ]+"` stops at the first space and leaves any opening quote intact. `valid_root` therefore receives a truncated path and rejects it.
   - This only affects the final process-tree recovery source, but it is meant to rescue a fresh session when the higher-priority sources are absent. Local plugin checkouts under paths such as `/Users/name/Claude Plugins/vbw` cannot use that recovery path.
   - Fix scope: replace the whitespace-delimited extraction with a parser that handles Claude command arguments and quoted paths, or document and enforce a no-spaces constraint before this fallback is claimed to support arbitrary `--plugin-dir` installs. Add a mocked `ps` BATS case for a quoted space-containing path.

### Map and stack inference

4. **[major] `config/stack-mappings.json:237-263,281-299` defines the top-level `mobile` key twice, and jq silently discards Android, Flutter, and React Native mappings.**
   - JSON permits duplicate member names syntactically, and jq retains the later member. The first `mobile` object contains `android-kotlin`, `flutter`, and `react-native`. The later `mobile` object contains only `ios-swift` and `swiftui`.
   - Read-only validation with `jq -c '.mobile | keys' config/stack-mappings.json` returned `["ios-swift","swiftui"]`. `scripts/detect-stack.sh:110-117` consumes jq output, so the earlier mobile profiles are unreachable and their skills are never recommended.
   - `git blame` shows this predates Phase 03, but Phase 03 changed this mapping file and expanded stack detection coverage. It is an adjacent functional defect in the exact configuration that Phase 03 relies on.
   - Fix scope: merge all mobile profiles into one `mobile` object, preserving the intended Swift profile choice, and add detector fixtures that assert Android, Flutter, and React Native are emitted. Add a configuration integrity check that prevents duplicate top-level mapping categories or otherwise validates that all expected mobile profiles remain reachable.

### Shell portability

5. **[minor] `scripts/session-start.sh:569` uses GNU-only `sort -V` without the BSD fallback used elsewhere in the same script.**
   - The phase directory helper at `scripts/session-start.sh:57-58` already uses `sort -V 2>/dev/null ||` followed by a portable numeric fallback. The cache-cleanup branch assigns `VERSIONS=$(ls ... | sort -V)` with no fallback.
   - Stock macOS `sort` does not support `-V`. The repository requires Bash 4.4 or newer on macOS, but does not require GNU coreutils. In that environment the command substitution produces no version list, `COUNT` becomes zero, and cache cleanup silently does nothing.
   - This is adjacent to Phase 02 SessionStart root bootstrap work. It does not normally stop command resolution, but stale cache versions remain and increase the chance of the cache-selection defect in finding 1.
   - Fix scope: use the existing portable version-order fallback or a shared helper for cache cleanup. Add a test that shadows `sort` with a BSD-like implementation that rejects `-V` and verifies that only the latest cache version remains.

## Relevant Patterns

- Phase 01 repaired the missing planning-git fallback diagnostic, documented AskUserQuestion metadata, removed the obsolete `find_skills_available` gate, and documented the Bash 4.4 runtime floor. Evidence is in `01-01-SUMMARY.md`.
- Phase 02 added the shared command resolver, SessionStart session-link bootstrap, and resolver BATS coverage. The resolver is the highest-risk change because 19 command preambles depend on it through `testing/verify-plugin-root-resolution.sh:33-108`.
- Phase 03 hardened map META parsing, established the `## Purpose` map contract, repaired answered-requirement rendering, and changed project skill recommendation behavior. The canonical headings and bare META keys agree with the current parsers. No separate defect was verified in `scripts/map-staleness.sh`, `scripts/infer-project-context.sh`, or `scripts/bootstrap/bootstrap-requirements.sh`.
- Phase 04 centralized the shutdown, non-team spawn, and no-tool text in `references/subagent-contracts.md`. `bash testing/verify-shared-contracts.sh` completed with exit status 0 and reported 65 passing checks. The verifier checks included canonical invariants, all six command includes, Execute runtime guidance, and its current anti-drift markers.
- The Phase 04 verifier does not exercise resolver candidate validity or source identity. Those failure modes need BATS or behavioral smoke coverage in the plugin-root test suite, not additional prose-marker checks.

## Risks

- Findings 1 and 2 can leave a fresh command unable to resolve VBW, or worse, point its repaired session link at another plugin. They affect every command that uses the Phase 02 trampoline.
- Finding 4 makes several supported mobile stacks invisible to `/vbw:init` and `/vbw:skills`. The defect is silent because jq accepts the file and returns a plausible subset.
- Finding 5 is platform-specific, but it conflicts with the documented macOS support position and leaves stale cache state that aggravates root selection.
- The shared-contract dedup work is structurally covered by its verifier. Its remaining risk is runtime include and agent behavior, which requires a separate smoke test rather than static contract checks.

## Recommendations

1. Plan one root-resolver remediation task for findings 1 through 3. Preserve the documented source precedence, choose the first valid candidate within each source, validate fallback roots as VBW, and add focused BATS cases for invalid candidates, plugin collisions, and quoted paths.
2. Plan one stack-mapping remediation task for finding 4. Consolidate the duplicate `mobile` category and add behavior tests through `scripts/detect-stack.sh` for each previously lost mobile stack.
3. Plan one portable SessionStart cache-cleanup task for finding 5. Reuse the existing numeric fallback and test a `sort -V` failure path.
4. After fixes, run the focused resolver and detector suites, `bash testing/verify-shared-contracts.sh`, and the full `bash testing/run-all.sh` in a clean environment. A fresh-session smoke test should cover cache-only, marketplace-only, and `--plugin-dir` installs.
