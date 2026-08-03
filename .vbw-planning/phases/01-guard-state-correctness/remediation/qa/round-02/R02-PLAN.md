---
phase: 1
round: 2
plan: R02
title: Round 02 QA remediation, fixing phase 01 regressions, declaring scope deviations, landing a real green gate
type: remediation
autonomous: true
effort_override: thorough
skills_used: []
files_modified:
  - testing/verify-skill-activation/additive-contracts.bash
  - testing/verify-delegation-guard.sh
  - .vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md
  - references/execute-protocol.md
  - scripts/agent-spawn-guard.sh
  - tests/agent-spawn-guard.bats
  - .vbw-planning/STATE.md
forbidden_commands: []
fail_classifications:
  - {id: "AP-01", type: "code-fix", rationale: "Real phase 01 regression. Commit b80d4891 moved the role normalizer out of scripts/agent-start.sh into scripts/lib/active-agent-state.sh (now vbw_active_agent_normalize_role), so the additive-contracts probe greps 0 lines through a pipefail pipeline and set -e kills verify-skill-activation.sh before its remaining modules run. The probe must follow the function to its new home."}
  - {id: "AP-02", type: "code-fix", rationale: "Real phase 01 regression. verify-delegation-guard.sh:120 feeds fake pid 12345, which the phase 01 live-PID filter correctly drops, so no host .active-agent-count is produced and the sidechain host count assertion breaks. Same fixture class as C32/C33 fixed in round 01. Fixture must migrate to a live background-sleep PID."}
  - {id: "DEV-01", type: "process-exception", rationale: "Commit 44c1acdf (scripts/agent-spawn-guard.sh, scripts/detect-models.sh, AGENTS.md, references/execute-protocol.md) was an undeclared scope expansion, but the changes were legitimate fixes needed to make the round 01 gate runnable. The remedy is verification plus retroactive declaration in this round's summary, not reversion of working fixes."}
  - {id: "DEV-02", type: "process-exception", rationale: "Commit 97c32d3a edited references/execute-protocol.md outside R01 files_modified and the mandated full run was never repeated afterward. The edit itself was a legitimate wording correction. Remedy is retroactive declaration here plus the real green gate run in Task 4, which supersedes the missing re-run."}
  - {id: "DEV-03", type: "process-exception", rationale: "Commit cfda8590 (glob and brace-group support in file-guard.sh plan matching) was an out-of-band shared-hook bug fix commissioned by the orchestrator mid-phase, fixed and tested by a separate debugger subagent, independently verified clean (bash -n, shellcheck, its own bats file, and 63/63 file-guard regression tests). The exact-string-only files_modified matching actively blocked other VBW consumer projects' Dev agents from writing plans with glob or brace-group entries. No code fix needed. It requires retroactive declaration: include cfda8590 in this round's commit_hashes and record a deviation entry explaining it was never part of any existing PLAN.md scope, so process-exception rather than plan-amendment."}
  - {id: "AP-03", type: "process-exception", rationale: "Accounting defect, not a code defect. R01-SUMMARY.md omitted two failures the full run surfaced (tests/auto-uat.bats not ok 64 line 962, tests/run-bats-shard.bats not ok 466 line 39). QA judged both genuinely unrelated to phase 01 (files unchanged in a14a1adc..HEAD). Remedy is complete pre_existing_issues accounting in this round, no code fix."}
  - {id: "MH-06", type: "code-fix", rationale: "The Task 6 gate never passed as written because real phase 01 regressions (AP-01, AP-02) and undeclared commits invalidated the run. Closing it requires the AP-01/AP-02 code fixes to land, then one direct bash testing/run-all.sh run on a clean committed tree whose only residual failures are the carried accepted-process-exception known issues."}
  - {id: "REQ-C31", type: "code-fix", rationale: "Same root as MH-06. The original C31 (phase never ran the full-suite gate) stays open until a real green run is achieved and evidenced. Resolved by Task 4's gate run after the AP-01/AP-02 fixes, excluding only the three long-accepted ShellCheck exceptions (scripts/vbw-statusline.sh, scripts/bootstrap/bootstrap-claude.sh, scripts/todo-lifecycle.sh) and the carried accepted-process-exception issues below."}
known_issues_input:
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
known_issue_resolutions:
  - '{"test":"AskUserQuestion contract","file":"testing/verify-askuserquestion-contract.sh","error":"list-todos unfiltered and filtered hints preserve remove/delete N. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"ShellCheck SC2034","file":"scripts/bootstrap/lib/bootstrap-claude-migration.sh","error":"FOUND_NON_VBW appears unused. File unchanged in a14a1adc..HEAD.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"auto-uat bats","file":"tests/auto-uat.bats","error":"not ok 64 verify.md precomputed UAT resume prefers next_phase_slug during reverification, line 962. File unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, outside phase 01 scope. One of the two failures AP-03 requires this round to account for explicitly."}'
  - '{"test":"claude-bootstrap contract","file":"scripts/verify-claude-bootstrap.sh","error":"Greenfield Active Context, Code Intelligence and Plugin Isolation sections missing. Bootstrap templates unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Bootstrap templates unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"claude-md-staleness contract","file":"testing/verify-claude-md-staleness.sh","error":"Checks 5, 6 and 7 fail on fresh state and refreshed sections. Same bootstrap root cause as the claude-bootstrap contract.","disposition":"accepted-process-exception","rationale":"Shares the claude-bootstrap root cause, unchanged in a14a1adc..HEAD, outside phase 01 scope."}'
  - '{"test":"ghost-team-cleanup contract","file":"testing/verify-ghost-team-cleanup.sh","error":"clean-stale-teams.sh missing vbw-* prefix guard in pass 1 and pass 2. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"lsp-setup contract","file":"testing/verify-lsp-setup.sh","error":"1 of 20 checks fails on Code Intelligence output. commands/init.md unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"commands/init.md unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"run-bats-shard bats","file":"tests/run-bats-shard.bats","error":"not ok 466 list-bats-files shardable omits serial-only bats file and is sorted, line 39. Expects the deleted tests/adaptive-governance.bats. File unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"File unchanged in a14a1adc..HEAD, expects a bats file deleted before phase 01. Outside phase 01 scope. One of the two failures AP-03 requires this round to account for explicitly."}'
  - '{"test":"summary-utils contract","file":"testing/verify-summary-utils-contract.sh","error":"header: documents scoped status hot path and deviation helper dependencies. scripts/lib/summary-utils.sh unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target lib unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"todo-pickup contract","file":"testing/verify-todo-pickup-contract.sh","error":"list-todos.sh emits command_text metadata fails. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
  - '{"test":"uat-recurrence contract","file":"testing/verify-uat-recurrence.sh","error":"extract-uat-issues.sh missing FAILED_IN_ROUNDS support. Target script unchanged in the phase range.","disposition":"accepted-process-exception","rationale":"Target script unchanged in a14a1adc..HEAD, outside phase 01 scope. Verified pre-existing by round 01 QA."}'
must_haves:
  truths:
    - "bash testing/verify-skill-activation.sh runs all modules to completion, including explicit-outcome, subagent-hook, and agent-contract, with the role normalization probe passing against scripts/lib/active-agent-state.sh"
    - "bash testing/verify-delegation-guard.sh passes with the sidechain fixture registering a live PID that survives the live-PID filter"
    - "One direct bash testing/run-all.sh run on a clean committed tree is evidenced. Its only failures are the 11 carried accepted-process-exception known issues and the 3 long-accepted ShellCheck exceptions."
    - "Commits 44c1acdf, 97c32d3a, and cfda8590 are declared in R02-SUMMARY.md with deviation entries and cfda8590 appears in commit_hashes"
  artifacts:
    - {path: "testing/verify-skill-activation/additive-contracts.bash", provides: "role normalization probe pointed at the function's current home", contains: "active-agent-state.sh"}
    - {path: "testing/verify-delegation-guard.sh", provides: "sidechain fixture with live PID", contains: "sleep"}
    - {path: ".vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md", provides: "retroactive deviation declarations and complete pre_existing_issues accounting", contains: "cfda8590"}
  key_links:
    - {from: "testing/verify-skill-activation/additive-contracts.bash", to: "scripts/lib/active-agent-state.sh", via: "vbw_active_agent_normalize_role probe"}
    - {from: "testing/verify-delegation-guard.sh", to: "scripts/agent-start.sh", via: "live-PID sidechain registration fixture"}
---
<objective>
Close the 8 round 01 FAILs. Two are real phase 01 regressions needing code fixes (AP-01 probe location, AP-02 dead-PID fixture). Four are process failures needing retroactive declaration, not code (DEV-01, DEV-02, DEV-03, AP-03). Two are the still-open gate (MH-06, REQ-C31). The gate closes only with a real green bash testing/run-all.sh run on a clean tree after the code fixes land. In that run the only residual failures may be the 11 carried accepted-process-exception known issues plus the 3 long-accepted ShellCheck exceptions.
</objective>
<context>
@.vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-01/R01-VERIFICATION.md
@.vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-KNOWN-ISSUES.json
</context>
<tasks>
<task type="auto">
  <name>Fix AP-01: point the additive-contracts role probe at the normalizer's new home</name>
  <files>
    testing/verify-skill-activation/additive-contracts.bash
  </files>
  <action>
Line 69 extracts printf role lines via sed -n '/normalize_agent_role/,/^}/p' against scripts/agent-start.sh. Commit b80d4891 removed that function from agent-start.sh. It now lives as vbw_active_agent_normalize_role in scripts/lib/active-agent-state.sh (case arms at lines ~37-45 use printf 'lead', printf 'dev', and so on). Update the probe: target scripts/lib/active-agent-state.sh with the range /vbw_active_agent_normalize_role/,/^}/ and adjust the printf extraction so all seven roles (architect debugger dev docs lead qa scout) are found. Keep the per-role pass/fail assertions intact, do not weaken them. Update the pass/fail message labels to name the file actually probed. Guard against the silent-abort failure mode. The extraction must not kill the suite under set -e -o pipefail when it matches nothing. Append || true to the pipeline the same way other probes in this file handle empty matches. An empty result must produce seven explicit FAILs instead of a dead suite.
  </action>
  <verify>
bash -n testing/verify-skill-activation/additive-contracts.bash. Then bash testing/verify-skill-activation.sh: the seven role probes pass and the explicit-outcome, subagent-hook, and agent-contract modules all execute (their output appears after the role probes). Exit code 0.
  </verify>
  <done>
verify-skill-activation.sh exits 0 with all modules run and all seven role probes passing against scripts/lib/active-agent-state.sh.
  </done>
</task>
<task type="auto">
  <name>Fix AP-02: migrate the delegation-guard sidechain fixture to a live PID</name>
  <files>
    testing/verify-delegation-guard.sh
  </files>
  <action>
run_sidechain_agent_hook (line ~117) builds hook input with pid:"12345", a dead PID the phase 01 live-PID filter drops, so no host .active-agent-count is written and the sidechain host count assertion fails. Migrate to the same live-PID pattern round 01 used for C32/C33 (see the fixtures in tests/agent-shutdown-integration.bats and tests/role-isolation-runtime.bats). Start a background sleep, for example sleep 300 & then capture $!. Pass that PID in the jq input. Kill it in the existing cleanup/teardown path so no sleep processes leak on any exit path. Do not weaken the host count assertion.
  </action>
  <verify>
bash -n testing/verify-delegation-guard.sh, then bash testing/verify-delegation-guard.sh exits 0 with the sidechain host count assertion passing. Confirm no leaked sleep processes afterward (pgrep -f "sleep 300" scoped to the test's PIDs returns nothing).
  </verify>
  <done>
verify-delegation-guard.sh exits 0 including the sidechain host count check, with fixture PID lifecycle fully cleaned up.
  </done>
</task>
<task type="auto">
  <name>Declare DEV-01, DEV-02, DEV-03 deviations and complete AP-03 accounting</name>
  <files>
    .vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md
  </files>
  <action>
First verify, then declare. Verification for 44c1acdf and 97c32d3a: read each diff with git show. Confirm the changes to scripts/agent-spawn-guard.sh, scripts/detect-models.sh, AGENTS.md, and references/execute-protocol.md are correct and non-regressive. Run tests/agent-spawn-guard.bats and any bats file covering detect-models.sh. Run bash testing/verify-shared-contracts.sh for the execute-protocol.md wording change. Do not revert them. For cfda8590, confirm its own suite still passes (tests/file-guard-plan-pattern-matching.bats plus the existing file-guard bats files, 63/63) but make no code changes.

Declaration, in R02-SUMMARY.md when this round's summary is written:
(1) A deviation entry for 44c1acdf and 97c32d3a. They were legitimate scope-expanded fixes required to make the round 01 gate runnable and to correct execute-protocol.md wording, undeclared at the time.
(2) A deviation entry for cfda8590 classified process-exception. It was an out-of-band shared-hook bug fix commissioned mid-phase by the orchestrator. Exact-string-only files_modified matching blocked consumer projects' Dev agents from using glob or brace-group plan entries. It was fixed and verified by a separate debugger subagent and requires documentation only.
(3) Include cfda8590 (and this round's own commits) in commit_hashes.
(4) A pre_existing_issues list covering all 11 carried known issues from R02-KNOWN-ISSUES.json. Explicitly include the two AP-03 omissions (tests/auto-uat.bats not ok 64 line 962, tests/run-bats-shard.bats not ok 466 line 39). Cite the rationale that both files are unchanged in a14a1adc..HEAD.
  </action>
  <verify>
git show --stat 44c1acdf 97c32d3a cfda8590 confirms the declared file lists match reality. R02-SUMMARY.md contains all three commit hashes and both deviation entries. It also lists 11 pre_existing_issues entries including the two bats failures.
  </verify>
  <done>
All three previously undeclared commits are verified non-regressive and declared with rationale, and the pre_existing_issues accounting is complete.
  </done>
</task>
<task type="auto">
  <name>Close MH-06 and REQ-C31: one real green full-suite gate run</name>
  <files>
    .vbw-planning/phases/01-guard-state-correctness/remediation/qa/round-02/R02-SUMMARY.md
  </files>
  <action>
Precondition: Tasks 1-3 committed and git status clean. The currently modified AGENTS.md, references/execute-protocol.md, scripts/agent-spawn-guard.sh, and tests/agent-spawn-guard.bats must be committed or intentionally accounted for before the run. A dirty tree invalidates the gate as it did in round 01. Then run bash testing/run-all.sh directly, exactly once, foreground, no tail, tee, or pipe wrappers. Acceptable residual failures are ONLY the 3 long-accepted ShellCheck exceptions (scripts/vbw-statusline.sh, scripts/bootstrap/bootstrap-claude.sh, scripts/todo-lifecycle.sh) and the 11 carried accepted-process-exception issues in this plan's known_issues_input. Verify each residual name-for-name against R02-KNOWN-ISSUES.json. Any other failure blocks this round. Fix it in this round (root cause, per repo policy), commit, and re-run the gate on the again-clean tree. Do not defer new failures to round 03. Record the evidence in R02-SUMMARY.md: gate commit hash (git rev-parse HEAD at run time), exit status, and the exact residual failure list. Map each residual to its known-issue entry.
  </action>
  <verify>
The recorded run's residual failures map one-to-one onto the 11 carried known issues plus the 3 ShellCheck exceptions. Zero unexplained failures remain. The tree at the recorded gate commit is clean.
  </verify>
  <done>
A green-modulo-accepted-exceptions bash testing/run-all.sh run is evidenced in R02-SUMMARY.md with commit hash, residual list, and known-issue mapping. MH-06 and REQ-C31 close.
  </done>
</task>
</tasks>
<verification>
1. bash testing/verify-skill-activation.sh exits 0 with all modules executed and seven role probes passing.
2. bash testing/verify-delegation-guard.sh exits 0 including the sidechain host count assertion.
3. R02-SUMMARY.md declares 44c1acdf, 97c32d3a, and cfda8590 with deviation entries and lists 11 pre_existing_issues including the two AP-03 bats failures.
4. The gate run evidence shows residual failures equal to exactly the 11 carried known issues plus the 3 accepted ShellCheck exceptions, on a clean committed tree.
</verification>
<success_criteria>
- AP-01 and AP-02 fixed at root cause with no weakened assertions.
- DEV-01, DEV-02, DEV-03 retroactively declared with verified non-regression, no reverts of working fixes.
- AP-03 accounting complete: all 11 carried known issues appear in pre_existing_issues with rationale.
- MH-06 and REQ-C31 closed by one evidenced direct full-suite run whose only residuals are accepted exceptions.
- Every carried known issue from R02-KNOWN-ISSUES.json has a matching known_issue_resolutions entry (11/11, all accepted-process-exception).
</success_criteria>
<known_issue_workflow>
- Always include `known_issues_input` and `known_issue_resolutions` in frontmatter. If there are no carried known issues, set both to empty arrays: `known_issues_input: []` and `known_issue_resolutions: []`.
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>
<output>
R02-SUMMARY.md
</output>
