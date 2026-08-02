---
phase: 4
round: 1
plan: R01
title: Restore dropped retry sentence, fix README version drift, amend plans 04-01 and 04-02
type: remediation
autonomous: true
effort_override: balanced
skills_used: []
files_modified: [references/handoff-schemas.md, README.md, .vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md, .vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md]
forbidden_commands: []
fail_classifications:
  - {id: "UDEV-01", type: "code-fix", rationale: "The 04-02 rewrite of references/handoff-schemas.md silently dropped the sentence 'The orchestrator retries up to 3 times on rejection before proceeding.' from the conditional-refusal note. The behavior it documents exists nowhere else in the repo, so information was lost, not centralized. Restoring the sentence is a one-line root-cause fix."}
  - {id: "DEV-01", type: "plan-amendment", rationale: "Commit 235dae0a edited punctuation, sentences, and lists outside Shutdown Handling in vbw-dev, vbw-lead, vbw-qa, and vbw-debugger. The discipline-watcher hook forced those edits, since it blocks a turn while findings remain in modified files. The work was declared in 04-01-SUMMARY and broke no must_have. Amend the plan's 'do not edit any other section' constraint to record the hook-driven exception rather than reverting the code.", source_plan: "04-01-PLAN.md"}
  - {id: "DEV-02", type: "plan-amendment", rationale: "agents/vbw-debugger.md:118 and agents/vbw-scout.md:109 retain 'A plain-text reply is NOT sufficient' because existing tests/shutdown-protocol.bats assertions require an inline call-SendMessage marker. The retained sentence differs from the prohibited canonical sentence, so MH-05 still passes and no drift marker fires. The plan's 'only pointer, invariant, JSON example, role tail' element list should be amended to include the test-required marker.", source_plan: "04-01-PLAN.md"}
  - {id: "DEV-04", type: "plan-amendment", rationale: "Commit 260d0560 updated five existing verifier files: verify-commands-contract.sh, verify-execute-delegation-routing.sh, verify-uat-remediation-orchestration.sh, verify-debug-session-contract.sh, and tests/shutdown-protocol.bats. Their assertions checked the duplicated prose the plan removed. Zero-tolerance policy required the updates and 04-02-SUMMARY declared them. The correct resolution is amending 04-02 files_modified to cover the verifier updates.", source_plan: "04-02-PLAN.md"}
  - {id: "DEV-05", type: "process-exception", rationale: "plugin-dev:command-development skill activation failed during 04-02 because the plugin cache was missing its build script, an external environment defect. Dev read the SKILL.md and its plugin-features reference directly, which delivers the same content. No repo file can fix a broken external cache. Declared in 04-02-SUMMARY."}
  - {id: "DEV-06", type: "process-exception", rationale: "Same external plugin-cache root cause as DEV-05, recurring in 04-03. The same direct-read workaround was applied and declared in 04-03-SUMMARY. No repo-side fix exists."}
known_issues_input:
  - '{"test":"README accuracy table VERSION row","file":"README.md","error":"row states 1.38.6 but repo VERSION is 1.38.8 (all 4 version files in sync at 1.38.8), drift predates phase 04 and was out of plan scope"}'
known_issue_resolutions:
  - '{"test":"README accuracy table VERSION row","file":"README.md","error":"row states 1.38.6 but repo VERSION is 1.38.8 (all 4 version files in sync at 1.38.8), drift predates phase 04 and was out of plan scope","disposition":"resolved","rationale":"Task 2 updates both README version claims (accuracy table row at line 46 and the last-verified prose copy at line 51) to 1.38.8, matching VERSION, per the CLAUDE.md README claim-drift rule to fix table and prose copies together."}'
must_haves:
  truths:
    - "references/handoff-schemas.md again documents the orchestrator retry-on-rejection behavior in the conditional-refusal note"
    - "README.md contains no occurrence of 1.38.6 and both version claims read 1.38.8"
    - "04-01-PLAN.md and 04-02-PLAN.md carry amendment notes matching the declared deviations, so DEV-01, DEV-02, and DEV-04 reconcile on re-verification"
    - "bash testing/run-all.sh stays green after all edits (zero-tolerance policy)"
  artifacts:
    - {path: "references/handoff-schemas.md", provides: "restored orchestrator retry rule", contains: "retries up to 3 times on rejection"}
    - {path: "README.md", provides: "version claims matching VERSION", contains: "1.38.8"}
    - {path: ".vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md", provides: "amended files_modified covering verifier updates", contains: "tests/shutdown-protocol.bats"}
  key_links:
    - {from: ".vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md", to: "04-01-SUMMARY.md deviations", via: "amendment note recording DEV-01 and DEV-02"}
    - {from: "README.md", to: "VERSION", via: "accuracy-table cited command cat VERSION"}
---
<objective>
Resolve the six FAIL checks from 04-VERIFICATION.md and the one carried known issue. One code fix restores the silently dropped orchestrator-retry sentence in references/handoff-schemas.md (UDEV-01). One code fix updates both README version claims to 1.38.8 (carried known issue). Two plan amendments record the hook-forced and test-forced deviations in 04-01-PLAN.md (DEV-01, DEV-02) and the verifier-file scope expansion in 04-02-PLAN.md (DEV-04). DEV-05 and DEV-06 are accepted process exceptions caused by a broken external plugin cache and need no repo change.
</objective>
<context>
@.vbw-planning/phases/04-shared-contract-dedup/04-VERIFICATION.md
@.vbw-planning/phases/04-shared-contract-dedup/04-01-SUMMARY.md
@.vbw-planning/phases/04-shared-contract-dedup/04-02-SUMMARY.md
Rationale: the verification file names each FAIL with evidence, and the two summaries carry the declared deviations the plan amendments must mirror.
</context>
<tasks>
<task type="auto">
  <name>Restore orchestrator retry sentence in handoff-schemas.md</name>
  <files>
    references/handoff-schemas.md
  </files>
  <action>
In references/handoff-schemas.md, the Conditional refusal blockquote in the Delivery format section (near line 337) currently reads: "Currently all agents are instructed to always approve. If a future agent needs to delay shutdown ...". Insert the dropped sentence between those two sentences so the blockquote reads: "Currently all agents are instructed to always approve. The orchestrator retries up to 3 times on rejection before proceeding. If a future agent needs to delay shutdown ...". The sentence must match the pre-25fedfcc wording byte for byte: "The orchestrator retries up to 3 times on rejection before proceeding." Make no other edits to the file. This stays inside the Delivery format region that MH-10 already allows the phase to touch, leaving the V2 schema blocks and Backward Compatibility section untouched.
  </action>
  <verify>
grep -F 'The orchestrator retries up to 3 times on rejection before proceeding.' references/handoff-schemas.md matches exactly once. git diff shows a single-line addition in the conditional-refusal blockquote and no other hunk.
  </verify>
  <done>
The retry rule is documented again in its original home. Committed as docs(references): restore orchestrator retry rule in conditional refusal note.
  </done>
</task>
<task type="auto">
  <name>Update README version claims to 1.38.8</name>
  <files>
    README.md
  </files>
  <action>
Replace both occurrences of 1.38.6 in README.md with 1.38.8: the accuracy-table VERSION row (line 46, "VERSION (1.38.6)") and the prose copy below the table (line 51, "last verified against `VERSION` 1.38.6"). Per the CLAUDE.md README claim-drift rule, confirm no other prose copy of the version exists: grep -n '1\.38\.' README.md must return only the two edited lines afterward. Do not change any other count in the table. MH-14 already verified script and BATS counts match recomputed values at this commit.
  </action>
  <verify>
grep -c '1\.38\.6' README.md returns 0. grep -c '1\.38\.8' README.md returns 2. cat VERSION prints 1.38.8.
  </verify>
  <done>
README version claims match VERSION. Committed as docs(readme): sync version claims to 1.38.8.
  </done>
</task>
<task type="auto">
  <name>Amend 04-01-PLAN.md for DEV-01 and DEV-02</name>
  <files>
    .vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md
  </files>
  <action>
Append a "## Amendments (R01)" section at the end of .vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md with two entries. Amendment 1 (DEV-01): relax task 2's constraint "Do not edit any other section of the agent files". Permit discipline-watcher hook remediation edits (punctuation, sentence, and list cleanup) in agents/vbw-dev.md, agents/vbw-lead.md, agents/vbw-qa.md, and agents/vbw-debugger.md. State the reason: the hook blocks turn completion while findings remain in modified files. Reference commit 235dae0a. Amendment 2 (DEV-02): extend task 2's condensed-section element list (pointer, invariant, JSON example, role tail) with a fifth permitted element. That element is an inline call-SendMessage marker sentence ("A plain-text reply is NOT sufficient") retained in agents/vbw-debugger.md and agents/vbw-scout.md. State the reason: tests/shutdown-protocol.bats asserts it. Note explicitly that this sentence differs from the prohibited canonical sentence "Plain text acknowledgement is NOT sufficient.", so MH-05 and the anti-drift verifier still hold. Do not alter the original frontmatter or task bodies. The amendment section is additive.
  </action>
  <verify>
grep -F 'Amendments (R01)' .vbw-planning/phases/04-shared-contract-dedup/04-01-PLAN.md matches. grep -F '235dae0a' and grep -F 'shutdown-protocol.bats' both match in the file. git diff for the file shows additions only.
  </verify>
  <done>
04-01-PLAN.md records both amendments, reconciling DEV-01 and DEV-02 on re-verification. Committed as docs(04-R01): amend plan 04-01 for hook and test forced deviations.
  </done>
</task>
<task type="auto">
  <name>Amend 04-02-PLAN.md for DEV-04</name>
  <files>
    .vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md
  </files>
  <action>
In .vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md, extend the files_modified and files_touched frontmatter arrays with the five verifier files updated in commit 260d0560: testing/verify-commands-contract.sh, testing/verify-execute-delegation-routing.sh, testing/verify-uat-remediation-orchestration.sh, testing/verify-debug-session-contract.sh, tests/shutdown-protocol.bats. Append a "## Amendments (R01)" section at the end. Record three facts: the verifiers held stale duplicated-prose assertions exposed by the full suite after centralization, updating them was required by the zero-tolerance test policy, and the update was declared in 04-02-SUMMARY deviations. Reference commit 260d0560. Make no other frontmatter or body changes.
  </action>
  <verify>
grep -F 'tests/shutdown-protocol.bats' .vbw-planning/phases/04-shared-contract-dedup/04-02-PLAN.md matches in files_modified. grep -F 'Amendments (R01)' and grep -F '260d0560' both match. git diff for the file shows additions only within frontmatter arrays and the new section.
  </verify>
  <done>
04-02-PLAN.md scope covers the verifier updates, reconciling DEV-04 on re-verification. Committed as docs(04-R01): amend plan 04-02 file scope for verifier updates.
  </done>
</task>
</tasks>
<verification>
1. grep -F 'The orchestrator retries up to 3 times on rejection before proceeding.' references/handoff-schemas.md matches exactly once.
2. grep '1\.38\.6' README.md returns nothing and both claims read 1.38.8.
3. Both amended plans contain an "## Amendments (R01)" section whose content matches the declared deviations in the corresponding SUMMARY.
4. bash testing/run-all.sh passes: lint, all contract checks including verify-shared-contracts.sh, and the full BATS suite.
</verification>
<success_criteria>
- UDEV-01 resolved by code fix, DEV-01, DEV-02, DEV-04 resolved by plan amendment, DEV-05 and DEV-06 accepted as process exceptions with external root cause.
- The carried known issue is resolved and no version claim drift remains in README.md.
- No must_have that passed in 04-VERIFICATION.md regresses.
</success_criteria>
<known_issue_workflow>
- Always include `known_issues_input` and `known_issue_resolutions` in frontmatter. If there are no carried known issues, set both to empty arrays: `known_issues_input: []` and `known_issue_resolutions: []`.
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>
<output>
R01-SUMMARY.md
</output>
