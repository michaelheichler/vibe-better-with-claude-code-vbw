---
phase: 5
plan: 1
title: Fix adversarial review findings 1-5
status: partial
completed: 2026-08-02
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - e22a02ac4edd496b098b4167e8c443e6d5d51f1d
  - 8cd480fdd54275bd82975153c341694f12ac555a
  - c2876e7a08db9e897a77d050ccd34c6c79dbdfb4
  - 0362a0461b4c9a5d3250a4b3bd3eaf0839383dd4
  - f3171157952dc835a24a0f9b50e4c7bfd6160496
  - 37edcbc6fdaa9a20f14be7561d3302f373016256
deviations:
  - "DEVN-02: Updated the marketplace behavioral smoke fixture after fallback identity validation exposed its missing VBW manifest."
  - "DEVN-03: Full-suite verification is blocked by 10 BATS failures from a concurrent uncommitted vibe phase-state refactor outside this plan."
pre_existing_issues: []
ac_results:
  - criterion: "Cache resolution selects the newest VALID candidate, not the newest candidate: an invalid newer cache entry never masks a usable older one"
    verdict: "pass"
    evidence: "e22a02ac and resolve-plugin-root.bats cases 4 through 7"
  - criterion: "Marketplace and process-derived roots are accepted only when .claude-plugin/plugin.json identifies the plugin as vbw"
    verdict: "pass"
    evidence: "8cd480fd and resolve-plugin-root.bats collision cases 9 and 15"
  - criterion: "A --plugin-dir path containing spaces is recovered intact by the process fallback"
    verdict: "pass"
    evidence: "c2876e7a and resolve-plugin-root.bats quoted-path cases 13 and 14"
  - criterion: "jq -c '.mobile | keys' config/stack-mappings.json lists android-kotlin, flutter, react-native, ios-swift, and swiftui in one object"
    verdict: "pass"
    evidence: "0362a046 and exact jq key assertion"
  - criterion: "SessionStart cache cleanup orders versions correctly on BSD sort without -V support"
    verdict: "pass"
    evidence: "f3171157 and tests/session-start.bats"
  - criterion: "scripts/resolve-plugin-root.sh provides candidate iteration and identity validation"
    verdict: "pass"
    evidence: "scripts/resolve-plugin-root.sh contains ordered scans and plugin.json validation"
  - criterion: "tests/resolve-plugin-root.bats provides regression coverage for findings 1-3"
    verdict: "pass"
    evidence: "23 resolver BATS cases passed"
  - criterion: "config/stack-mappings.json provides a single merged mobile category"
    verdict: "pass"
    evidence: "config/stack-mappings.json and tests/detect-stack.bats"
  - criterion: "scripts/session-start.sh provides portable version sort in cache cleanup"
    verdict: "pass"
    evidence: "scripts/session-start.sh contains sort -V 2>/dev/null with numeric fallback"
  - criterion: "tests/resolve-plugin-root.bats links to scripts/resolve-plugin-root.sh through invalid-newest, collision, and quoted-path cases"
    verdict: "pass"
    evidence: "bats tests/resolve-plugin-root.bats passed 23 of 23"
  - criterion: "scripts/detect-stack.sh consumes the merged config/stack-mappings.json mobile object"
    verdict: "pass"
    evidence: "bats tests/detect-stack.bats passed 9 of 9 mobile and integrity checks"
---

## What Was Built

- Hardened cache candidate selection, fallback identity checks, and quoted process-path parsing.
- Merged all five mobile profiles and added duplicate-key plus detector coverage.
- Added portable cache cleanup sorting for systems without `sort -V`.
- Updated the marketplace smoke fixture to satisfy the fallback identity contract.
- Focused plan checks pass. The full suite reports 3,750 BATS passes and 10 failures in concurrent uncommitted phase-state work.
- Grounding: d04-termination-and-euclid, d05-formal-treatment-of-small-examples, d08-search-permutation-flag-file-merging. Postconditions stated, cache-scan and process-path invariants named, unexamined-candidate variants named

## Files Modified

- `scripts/resolve-plugin-root.sh`: scans ranked candidates, verifies fallback identity, and parses quoted process paths.
- `tests/resolve-plugin-root.bats`: covers invalid candidates, plugin collisions, and paths with spaces.
- `config/stack-mappings.json`: consolidates all mobile profiles under one key.
- `tests/detect-stack.bats`: enforces unique top-level categories and mobile profile detection.
- `scripts/session-start.sh`: adds a portable semantic-version sort fallback.
- `tests/session-start.bats`: covers cache cleanup when `sort -V` is unavailable.
- `testing/verify-plugin-root-resolution.sh`: gives the marketplace smoke root a VBW manifest.
