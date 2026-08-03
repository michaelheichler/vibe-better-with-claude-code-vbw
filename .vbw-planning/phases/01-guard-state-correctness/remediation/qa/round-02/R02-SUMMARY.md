---
phase: 1
round: 2
title: Round 02 QA remediation, guard regressions and gate closure
type: remediation
status: complete
completed: 2026-08-03
tasks_completed: 5
tasks_total: 5
commit_hashes:
  - 05f441f9
  - e2f73d12
  - 2ecf01b3
  - e0e2df3d
  - 1c388414
  - 44c1acdf
  - 97c32d3a
  - cfda8590
files_modified:
  - testing/verify-skill-activation/additive-contracts.bash
  - testing/verify-delegation-guard.sh
  - references/execute-protocol.md
  - scripts/agent-spawn-guard.sh
  - tests/agent-spawn-guard.bats
  - .vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md
deviations:
  - "DEV-01 process-exception: 44c1acdf was scope-expanded but legitimate gate-enablement work. git show confirms the actual files were AGENTS.md, references/execute-protocol.md, scripts/agent-spawn-guard.sh, and tests/agent-spawn-guard.bats. The originally cited scripts/detect-models.sh is not part of that commit. The working fixes were retained."
  - "DEV-02 process-exception: 97c32d3a edited references/execute-protocol.md outside the R01 files_modified list. The wording correction was legitimate and is retained."
  - "DEV-03 process-exception: cfda8590 was an out-of-band shared-hook fix for glob and brace-group files_modified matching, commissioned for consumer projects. It passed bash -n, ShellCheck, 4/4 new tests, and 63/63 existing file-guard tests."
  - "AP-04 code-fix: 44c1acdf prose tightening dropped the second additive-skill and follow-up-read contract phrases. 2ecf01b3 restored only those phrases. The skill activation suite now passes 469/469."
  - "MH-07 code-fix: 1c388414 makes agent-spawn-guard resolve and enforce configured reasoning effort, including removal when the resolved model rejects the parameter. Tests cover injection, overwrite, and unsupported-effort stripping."
pre_existing_issues:
  - '{"test":"AskUserQuestion contract","file":"testing/verify-askuserquestion-contract.sh","error":"list-todos unfiltered and filtered hints preserve remove/delete N. Target script unchanged in the phase range."}'
  - '{"test":"ShellCheck SC2034","file":"scripts/bootstrap/lib/bootstrap-claude-migration.sh","error":"FOUND_NON_VBW appears unused. File unchanged in a14a1adc..HEAD."}'
  - '{"test":"auto-uat bats","file":"tests/auto-uat.bats","error":"not ok 64 verify.md precomputed UAT resume prefers next_phase_slug during reverification, line 962. File unchanged in the phase range."}'
  - '{"test":"claude-bootstrap contract","file":"scripts/verify-claude-bootstrap.sh","error":"Greenfield Active Context, Code Intelligence and Plugin Isolation sections missing. Bootstrap templates unchanged in the phase range."}'
  - '{"test":"claude-md-staleness contract","file":"testing/verify-claude-md-staleness.sh","error":"Checks 5, 6 and 7 fail on fresh state and refreshed sections. Same bootstrap root cause as the claude-bootstrap contract."}'
  - '{"test":"ghost-team-cleanup contract","file":"testing/verify-ghost-team-cleanup.sh","error":"clean-stale-teams.sh missing vbw-* prefix guard in pass 1 and pass 2. Target script unchanged in the phase range."}'
  - '{"test":"lsp-setup contract","file":"testing/verify-lsp-setup.sh","error":"1 of 20 checks fails on Code Intelligence output. commands/init.md unchanged in the phase range."}'
  - '{"test":"run-bats-shard bats","file":"tests/run-bats-shard.bats","error":"not ok 466 list-bats-files shardable omits serial-only bats file and is sorted, line 39. Expects the deleted tests/adaptive-governance.bats. File unchanged in the phase range."}'
  - '{"test":"summary-utils contract","file":"testing/verify-summary-utils-contract.sh","error":"header: documents scoped status hot path and deviation helper dependencies. scripts/lib/summary-utils.sh unchanged in the phase range."}'
  - '{"test":"todo-pickup contract","file":"testing/verify-todo-pickup-contract.sh","error":"list-todos.sh emits command_text metadata fails. Target script unchanged in the phase range."}'
  - '{"test":"uat-recurrence contract","file":"testing/verify-uat-recurrence.sh","error":"extract-uat-issues.sh missing FAILED_IN_ROUNDS support. Target script unchanged in the phase range."}'
known_issue_outcomes:
  - '{"test":"AskUserQuestion contract","file":"testing/verify-askuserquestion-contract.sh","error":"list-todos unfiltered and filtered hints preserve remove/delete N. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"ShellCheck SC2034","file":"scripts/bootstrap/lib/bootstrap-claude-migration.sh","error":"FOUND_NON_VBW appears unused. File unchanged in a14a1adc..HEAD.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"auto-uat bats","file":"tests/auto-uat.bats","error":"not ok 64 verify.md precomputed UAT resume prefers next_phase_slug during reverification, line 962. File unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, outside phase 01 scope. One of the two failures AP-03 requires this round to account for explicitly."}'
  - '{"test":"claude-bootstrap contract","file":"scripts/verify-claude-bootstrap.sh","error":"Greenfield Active Context, Code Intelligence and Plugin Isolation sections missing. Bootstrap templates unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Bootstrap templates unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"claude-md-staleness contract","file":"testing/verify-claude-md-staleness.sh","error":"Checks 5, 6 and 7 fail on fresh state and refreshed sections. Same bootstrap root cause as the claude-bootstrap contract.","disposition":"accepted-process-exception","rationale":"Shares the claude-bootstrap root cause, unchanged in a14a1adc..HEAD, outside phase 01 scope."}'
  - '{"test":"ghost-team-cleanup contract","file":"testing/verify-ghost-team-cleanup.sh","error":"clean-stale-teams.sh missing vbw-* prefix guard in pass 1 and pass 2. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"lsp-setup contract","file":"testing/verify-lsp-setup.sh","error":"1 of 20 checks fails on Code Intelligence output. commands/init.md unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"run-bats-shard bats","file":"tests/run-bats-shard.bats","error":"not ok 466 list-bats-files shardable omits serial-only bats file and is sorted, line 39. Expects the deleted tests/adaptive-governance.bats. File unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, expects a bats file deleted before phase 01. Outside phase 01 scope. One of the two failures AP-03 requires this round to account for explicitly."}'
  - '{"test":"summary-utils contract","file":"testing/verify-summary-utils-contract.sh","error":"header: documents scoped status hot path and deviation helper dependencies. scripts/lib/summary-utils.sh unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target lib unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"todo-pickup contract","file":"testing/verify-todo-pickup-contract.sh","error":"list-todos.sh emits command_text metadata fails. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"uat-recurrence contract","file":"testing/verify-uat-recurrence.sh","error":"extract-uat-issues.sh missing FAILED_IN_ROUNDS support. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
gate_run:
  commit: 1c3884144905a13aac66d3be02e03ed2c3ea3a4c
  command: bash testing/run-all.sh
  exit_status: 1
  tree_clean: true
  outcome: pass-with-accepted-process-exceptions
  residual_failures:
    - '{"test":"AskUserQuestion contract","file":"testing/verify-askuserquestion-contract.sh","error":"list-todos unfiltered and filtered hints preserve remove/delete N.","mapping":"known_issue_outcomes[0]"}'
    - '{"test":"ShellCheck SC2034","file":"scripts/bootstrap/lib/bootstrap-claude-migration.sh","error":"FOUND_NON_VBW appears unused.","mapping":"known_issue_outcomes[1]"}'
    - '{"test":"auto-uat bats","file":"tests/auto-uat.bats","error":"not ok 64 verify.md precomputed UAT resume prefers next_phase_slug during reverification, line 962.","mapping":"known_issue_outcomes[2]"}'
    - '{"test":"claude-bootstrap contract","file":"scripts/verify-claude-bootstrap.sh","error":"Greenfield Active Context, Code Intelligence and Plugin Isolation sections missing.","mapping":"known_issue_outcomes[3]"}'
    - '{"test":"claude-md-staleness contract","file":"testing/verify-claude-md-staleness.sh","error":"Checks 5, 6 and 7 fail on fresh state and refreshed sections.","mapping":"known_issue_outcomes[4]"}'
    - '{"test":"ghost-team-cleanup contract","file":"testing/verify-ghost-team-cleanup.sh","error":"clean-stale-teams.sh missing vbw-* prefix guard in pass 1 and pass 2.","mapping":"known_issue_outcomes[5]"}'
    - '{"test":"lsp-setup contract","file":"testing/verify-lsp-setup.sh","error":"1 of 20 checks fails on Code Intelligence output.","mapping":"known_issue_outcomes[6]"}'
    - '{"test":"run-bats-shard bats","file":"tests/run-bats-shard.bats","error":"not ok 466 list-bats-files shardable omits serial-only bats file and is sorted, line 39.","mapping":"known_issue_outcomes[7]"}'
    - '{"test":"summary-utils contract","file":"testing/verify-summary-utils-contract.sh","error":"header: documents scoped status hot path and deviation helper dependencies.","mapping":"known_issue_outcomes[8]"}'
    - '{"test":"todo-pickup contract","file":"testing/verify-todo-pickup-contract.sh","error":"list-todos.sh emits command_text metadata fails.","mapping":"known_issue_outcomes[9]"}'
    - '{"test":"uat-recurrence contract","file":"testing/verify-uat-recurrence.sh","error":"extract-uat-issues.sh missing FAILED_IN_ROUNDS support.","mapping":"known_issue_outcomes[10]"}'
    - '{"test":"ShellCheck accepted exception","file":"scripts/vbw-statusline.sh","error":"SC1083 literal braces at line 417 and SC2034 AGENT_N at line 561.","mapping":"long-accepted-shellcheck-exception"}'
    - '{"test":"ShellCheck accepted exception","file":"scripts/bootstrap/bootstrap-claude.sh","error":"SC1090 non-constant source at line 13 and SC2034 DEPRECATED_HAS_USER_CONTENT at line 164.","mapping":"long-accepted-shellcheck-exception"}'
    - '{"test":"ShellCheck accepted exception","file":"scripts/todo-lifecycle.sh","error":"SC2034 DETAILS_PATH and DETAILS_CACHE_JSON appear unused.","mapping":"long-accepted-shellcheck-exception"}'
---
Round 02 fixes both phase 01 guard regressions, enforces reasoning effort on VBW spawns, restores the contract phrases exposed by the repaired suite, and closes the full-suite gate with only accepted residuals.

## What Was Built
- Repointed the role probe, made extraction pipefail-safe, and verified the complete skill activation suite at 469/469.
- Migrated sidechain hook registration to a live PID and verified delegation guard at 45/45 with no leaked fixture sleep.
- Verified and declared the three historical deviation commits, accounted for all 11 carried known issues, and restored the two contract phrases removed by 44c1acdf.
- Enforced configured reasoning effort, stripped unsupported effort values, and verified the final gate at commit `1c388414` with only mapped accepted residuals.

## Files Modified
- `testing/verify-skill-activation/additive-contracts.bash` -- role probe location and pipefail-safe extraction.
- `testing/verify-delegation-guard.sh` -- live PID fixture and teardown.
- `references/execute-protocol.md` -- restored second contract phrase occurrences.
- `scripts/agent-spawn-guard.sh` -- enforced configured reasoning effort and removed unsupported values.
- `tests/agent-spawn-guard.bats` -- covered reasoning injection, overwrite, and stripping.
- `.vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md` -- declarations, gate evidence, and issue accounting.
