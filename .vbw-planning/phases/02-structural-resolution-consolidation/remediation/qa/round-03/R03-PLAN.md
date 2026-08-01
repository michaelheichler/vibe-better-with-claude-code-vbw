---
phase: 2
round: 3
plan: R03
title: Round-03 remediation to amend 02-04 scope for the bash-guard coordination fix and correct resolver-wiki shipped-shape errors
type: remediation
autonomous: true
effort_override: balanced
skills_used: []
files_modified:
  - .vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md
  - docs/wiki/plugin-root-resolution.md
forbidden_commands: []
fail_classifications:
  - {id: "DEV-01", type: "plan-amendment", rationale: "Commit 6ae202bf is a legitimate, root-caused, already-tested, already-merged coordination fix. bash-guard.sh's detect_agent_role lacked the payload-based agent_id/agent_type check that file-guard.sh already had, so it fell back to shared session-scoped active-agent markers that do not distinguish concurrent subagents, letting a concurrent QA subagent's registered role leak onto the plan 02-04 Docs agent and block it from committing its own work. The code is correct and independently QA-verified. The only defect is the missing declaration. Resolve by amending 02-04-PLAN.md's files_modified with a scope-amendment note, matching the precedent already accepted for 02-01-PLAN.md's coordination fix 44a0b65f (MH-11). No code change is proposed.", source_plan: "02-04-PLAN.md"}
  - {id: "DOC-01", type: "process-exception", rationale: "Reclassified in round 04. The underlying documentation-content defect was already fixed correctly in commit fd55ba95 during round 03 and independently re-verified PASS. This is reclassified as process-exception only to satisfy qa-result-gate.sh's structural evidence requirement, which currently has no category for 'documentation-content defect fixed by editing that same documentation file' and treats all docs/* changes as insufficient evidence for a code-fix claim (see STATE.md ref:2a7c918e). The FAIL is NOT being left unresolved, it was genuinely fixed. Real content defect in docs/wiki/plugin-root-resolution.md, not a declaration gap. Line 51 describes the 19 command trampolines as expanding 'a small fenced block', while the shipped shape is a standalone one-line backtick directive placed inside a display fence in the command files, and the wiki then renders it as multi-line bash, misrepresenting the shipped form. Line 82 claims a fresh marketplace-root session lacks the exact session link, contradicting the shipped SessionStart bootstrap at scripts/session-start.sh:513-525 and the wiki's own lines 102-106. Both passages must be corrected so the wiki matches the shipped artifacts and is internally consistent."}
known_issues_input:
  - '{"test":"bats parallel: phase-detect.bats line 2865 qa_status pending when PASS verification is stale for current code","file":"tests/phase-detect.bats:2865","error":"Failed once under parallel bats-worker-1 shard on the first run-all.sh pass, then passed in isolation (bats --filter) and on a clean full re-run (3700 passed, 0 failed). Docs-only plan 02-04 commits cannot regress phase-detect logic. Declared flaky, not re-fixed."}'
  - '{"test":"rtk-manager: bash-guard smoke failure prevents proof creation","file":"tests/rtk-manager.bats:2058-2069","error":"Expected status 1 at line 2067 but smoke-finish returned success. An isolated rerun reproduced before subsequent full-suite runs passed."}'
  - '{"test":"rtk-manager: bash-guard smoke failure prevents proof creation","file":"tests/rtk-manager.bats:2058-2069","error":"Expected status 1 at line 2067, but smoke-finish returned success. It reproduced in the requested single full-suite run and is accepted as tracked pre-existing context."}'
known_issue_resolutions:
  - '{"test":"bats parallel: phase-detect.bats line 2865 qa_status pending when PASS verification is stale for current code","file":"tests/phase-detect.bats:2865","error":"Failed once under parallel bats-worker-1 shard on the first run-all.sh pass, then passed in isolation (bats --filter) and on a clean full re-run (3700 passed, 0 failed). Docs-only plan 02-04 commits cannot regress phase-detect logic. Declared flaky, not re-fixed.","disposition":"accepted-process-exception","rationale":"Parallel-shard flake that passes in isolation and on clean full re-runs. This round touches only a planning artifact and wiki prose, which cannot interact with phase-detect logic. Carried as a verified non-blocking flake for this phase."}'
  - '{"test":"rtk-manager: bash-guard smoke failure prevents proof creation","file":"tests/rtk-manager.bats:2058-2069","error":"Expected status 1 at line 2067 but smoke-finish returned success. An isolated rerun reproduced before subsequent full-suite runs passed.","disposition":"accepted-process-exception","rationale":"Tracked pre-existing intermittent failure already accepted by 02-VERIFICATION.md MH-10 as not affecting the phase verdict. This round makes no script or test changes that touch rtk-manager or bash-guard smoke paths."}'
  - '{"test":"rtk-manager: bash-guard smoke failure prevents proof creation","file":"tests/rtk-manager.bats:2058-2069","error":"Expected status 1 at line 2067, but smoke-finish returned success. It reproduced in the requested single full-suite run and is accepted as tracked pre-existing context.","disposition":"accepted-process-exception","rationale":"Duplicate registry entry for the same tracked pre-existing rtk-manager case, observed via 02-VERIFICATION.md instead of 02-03-SUMMARY.md. Same disposition and rationale as the sibling entry."}'
must_haves:
  truths:
    - "02-04-PLAN.md's files_modified declares scripts/bash-guard.sh and tests/qa-bash-guard.bats with a scope-amendment note referencing commit 6ae202bf, so no Phase 2 commit scope remains undeclared"
    - "docs/wiki/plugin-root-resolution.md describes the 19 trampolines as standalone one-line backtick directives consistent with CLAUDE.md's template-expansion semantics and the shipped command files"
    - "docs/wiki/plugin-root-resolution.md no longer claims a fresh marketplace-root session lacks the exact session link, and the marketplace-root passage is consistent with the SessionStart bootstrap section at lines 102-106 and scripts/session-start.sh:513-525"
    - "No production code changes: scripts/bash-guard.sh and tests/qa-bash-guard.bats are not touched again"
  artifacts:
    - {path: ".vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md", provides: "amended plan scope covering commit 6ae202bf", contains: "6ae202bf"}
    - {path: "docs/wiki/plugin-root-resolution.md", provides: "corrected trampoline shape and marketplace-root fresh-session description", contains: "one-line"}
  key_links:
    - {from: ".vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md", to: "scripts/bash-guard.sh", via: "files_modified amendment declaring commit 6ae202bf"}
    - {from: "docs/wiki/plugin-root-resolution.md", to: "scripts/session-start.sh", via: "marketplace-root passage consistent with the lines 513-525 bootstrap"}
---
<objective>
Resolve the two Phase 2 verification FAILs. DEV-01 is a declaration gap, not a code defect. Amend 02-04-PLAN.md's frontmatter to declare the already-merged, already-verified bash-guard coordination fix (commit 6ae202bf), following the accepted 02-01 precedent (commit 44a0b65f, MH-11). DOC-01 is a real doc content defect. Correct docs/wiki/plugin-root-resolution.md at two locations so it matches the shipped trampoline shape and the shipped SessionStart bootstrap, and is internally consistent.
</objective>
<context>
@.vbw-planning/phases/02-structural-resolution-consolidation/02-VERIFICATION.md
@.vbw-planning/phases/02-structural-resolution-consolidation/02-01-PLAN.md
@.vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md
@docs/wiki/plugin-root-resolution.md
Rationale: 02-01-PLAN.md lines 11-17 are the exact precedent format for a mid-execution coordination-fix scope amendment. 02-VERIFICATION.md anti-pattern rows DEV-01 and DOC-01 define the failures. The wiki plus commands/init.md and scripts/session-start.sh:513-525 are the ground truth for the doc fix.
</context>
<tasks>
<task type="auto">
  <name>Amend 02-04-PLAN.md files_modified for commit 6ae202bf (DEV-01)</name>
  <files>
    .vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md
  </files>
  <action>
Edit the frontmatter files_modified list of .vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md. After the existing three entries (docs/wiki/plugin-root-resolution.md, CLAUDE.md, AGENTS.md), append:

  - scripts/bash-guard.sh
  - tests/qa-bash-guard.bats
  # Scope amendment: These files were added mid-execution as a required coordination fix discovered while running plan 02-04. bash-guard.sh's detect_agent_role lacked the payload-based agent_id/agent_type check that file-guard.sh already had, so it fell back to shared session-scoped active-agent markers that do not distinguish concurrent subagents. A concurrently running QA subagent's marker misclassified the 02-04 Docs agent as read-only "qa" and blocked it from committing its own work. Commit 6ae202bf fixed the root cause, was independently QA-verified, and is already merged.

Match the comment style of 02-01-PLAN.md's existing amendment (line 17, referencing commit 44a0b65f): a single YAML comment directly after the appended entries, inside the files_modified block. Do NOT change any code. scripts/bash-guard.sh and tests/qa-bash-guard.bats must not be edited.
  </action>
  <verify>
grep -n '6ae202bf' .vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md returns the amendment line. grep -n 'bash-guard.sh' returns the files_modified entry. git status shows only 02-04-PLAN.md changed by this task.
  </verify>
  <done>
02-04-PLAN.md declares scripts/bash-guard.sh and tests/qa-bash-guard.bats with a rationale note referencing 6ae202bf, in the same style as the 02-01 precedent, and no code files changed.
  </done>
</task>
<task type="auto">
  <name>Correct docs/wiki/plugin-root-resolution.md shipped-shape errors (DOC-01)</name>
  <files>
    docs/wiki/plugin-root-resolution.md
  </files>
  <action>
Two corrections. Read the actual shipped artifacts first: any two of the 19 target command files (for example commands/init.md lines 29-32 and commands/config.md lines 14-16) plus scripts/session-start.sh lines 505-530.

1. "Trampoline in the target commands" section (around line 51). The current text says each command "expands a small fenced block". The shipped shape is a standalone ONE-LINE backtick directive: the entire trampoline is a single directive line, which the command files place inside a plain display fence after a "Plugin root:" label. Per CLAUDE.md's documented template-expansion semantics, standalone one-line directives and fenced directive blocks both execute, while embedded spans inside prose do not. Rewrite the sentence to say each of the 19 target commands carries a standalone one-line directive (rendered inside a display fence in the command files) that resolves the root and nothing else. Keep the existing multi-line bash listing as documentation, but introduce it explicitly as a reformatted-for-readability expansion of the one-line directive, so no reader concludes the shipped artifact is multi-line.

2. "The marketplace-root branch" section (around line 82). The current text claims that on a fresh marketplace-root session "the /tmp session link does not exist yet". This contradicts scripts/session-start.sh:513-525, which bootstraps the deterministic per-session link from SCRIPT_DIR self-location for BOTH the plugin-dir and marketplace-root install shapes, and contradicts the wiki's own "SessionStart bootstrap" section (lines 102-106). Correct the passage. On a fresh marketplace-root session, CLAUDE_PLUGIN_ROOT is not exported to command bash expansions, there is no cache copy, and there is no plugin-dir argument to recover from ps, but the exact session link normally DOES exist because SessionStart creates it before the first command runs. The marketplace-root branch (step 5) is the in-cascade safety net for the cases where that bootstrap failed, raced, or was cleaned from /tmp. If you state that it was the load-bearing fix at the time commit 9467b312 landed, verify that ordering with git log first. Ensure the corrected passage no longer contradicts lines 102-106.

Keep all other wiki content unchanged. This is a prose-accuracy fix, not a restructure.
  </action>
  <verify>
The line-51 section no longer describes the trampoline as a fenced block. The marketplace-root section no longer claims the fresh-session link is absent. A manual read confirms the marketplace-root section and the SessionStart bootstrap section agree. bash testing/verify-plugin-root-resolution.sh still passes.
  </verify>
  <done>
The wiki describes the trampoline as a standalone one-line directive matching the shipped command files, the marketplace-root passage is consistent with scripts/session-start.sh:513-525 and wiki lines 102-106, and no other content changed.
  </done>
</task>
</tasks>
<verification>
1. grep -n '6ae202bf' .vbw-planning/phases/02-structural-resolution-consolidation/02-04-PLAN.md is non-empty, and files_modified lists scripts/bash-guard.sh and tests/qa-bash-guard.bats
2. git diff for this round touches only 02-04-PLAN.md and docs/wiki/plugin-root-resolution.md, with no script or test files
3. docs/wiki/plugin-root-resolution.md describes the trampoline as a standalone one-line directive, no longer claims the fresh-session link is absent in the marketplace-root section, and is internally consistent with the SessionStart bootstrap section
4. bash testing/run-all.sh green, modulo the accepted known issues above
</verification>
<success_criteria>
- DEV-01 resolved as plan-amendment: commit 6ae202bf's scope is declared in 02-04-PLAN.md with rationale, matching the 02-01 precedent for 44a0b65f, and no code is re-touched
- DOC-01 resolved as doc-fix: both wiki inaccuracies corrected against shipped artifacts, wiki internally consistent
- All three carried known issues covered by accepted-process-exception dispositions
</success_criteria>
<known_issue_workflow>
- Always include `known_issues_input` and `known_issue_resolutions` in frontmatter. If there are no carried known issues, set both to empty arrays: `known_issues_input: []` and `known_issue_resolutions: []`.
- Copy every carried known issue from the remediation input backlog into `known_issues_input` using the canonical `{test,file,error}` shape.
- Add a matching `known_issue_resolutions` entry for every carried known issue. Use `resolved` when this round fixes it, `accepted-process-exception` when QA should treat it as a verified non-blocking carryover for this phase, and `unresolved` only when the issue is intentionally carried into the next round.
- Do not omit a carried known issue from these arrays. The deterministic gate treats missing coverage as a failed remediation round.
</known_issue_workflow>
<output>
R03-SUMMARY.md
</output>
