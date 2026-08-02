---
phase: 6
plan: 01
title: Markdown decomposition, Vibe modes, execute-protocol steps, skill-activation payload template
status: complete
completed: 2026-08-02
tasks_completed: 3
tasks_total: 3
commit_hashes:
  - 89c51f9
  - 904b7c5
  - 83d1c02
deviations:
  - "The research consumer table missed 25 raw-parent assertions across 15 direct readers. All were updated to owning references or effective-content fixtures."
  - "Mandatory file-size hooks required testing/verify-commands-contract.sh and testing/verify-skill-activation.sh to keep their entry points while moving checks into sourced modules."
  - "references/vibe-input-parsing.md contained the two shared QA remediation payload sites needed to reach the researched 20-site total, although the plan file list omitted it."
pre_existing_issues: []
ac_results:
  - criterion: "Every extracted Vibe mode retains its parent heading and standalone include without duplicate reference headings"
    verdict: "pass"
    evidence: "89c51f9, byte-equality expansion check, testing/verify-commands-contract.sh"
  - criterion: "execute-protocol.md retains Step 4, Step 4.1, and Step 4.5 headings with runtime Read directives"
    verdict: "pass"
    evidence: "904b7c5, byte-equality step-chain check"
  - criterion: "All 20 payload sites keep local skill-selection and no-skill-reason policy"
    verdict: "pass"
    evidence: "83d1c02, testing/verify-skill-activation.sh"
  - criterion: "No unresolved include reaches a spawned child prompt"
    verdict: "pass"
    evidence: "83d1c02, execute-protocol render-and-prepend contract"
  - criterion: "Expanded Vibe and execute step content preserves behavior"
    verdict: "pass"
    evidence: "empty pre-split versus expanded diffs"
  - criterion: "Moved Non-team and No-tool invariants remain canonical"
    verdict: "pass"
    evidence: "testing/verify-shared-contracts.sh"
  - criterion: "references/vibe-mode-bootstrap.md provides Bootstrap mode body"
    verdict: "pass"
    evidence: "references/vibe-mode-bootstrap.md"
  - criterion: "references/vibe-mode-plan.md provides Plan mode body"
    verdict: "pass"
    evidence: "references/vibe-mode-plan.md"
  - criterion: "references/vibe-mode-archive.md provides Archive mode body without Pure-Vibe Phase Loop"
    verdict: "pass"
    evidence: "references/vibe-mode-archive.md"
  - criterion: "references/execute-post-build-qa.md provides Step 4 body"
    verdict: "pass"
    evidence: "references/execute-post-build-qa.md"
  - criterion: "references/execute-qa-result-gating.md provides Step 4.1 body"
    verdict: "pass"
    evidence: "references/execute-qa-result-gating.md"
  - criterion: "references/execute-uat.md provides Step 4.5 body"
    verdict: "pass"
    evidence: "references/execute-uat.md"
  - criterion: "references/skill-activation-payload.md provides selected and no-selected branches"
    verdict: "pass"
    evidence: "references/skill-activation-payload.md"
  - criterion: "commands/vibe.md links all extracted mode references"
    verdict: "pass"
    evidence: "nine standalone mode includes"
  - criterion: "execute-protocol.md links post-build QA through runtime Read"
    verdict: "pass"
    evidence: "retained Step 4 heading and directive"
  - criterion: "All payload sites render the canonical template"
    verdict: "pass"
    evidence: "20 render directives, zero duplicated literal payload pairs"
  - criterion: "Command contract tests expand all Vibe mode references"
    verdict: "pass"
    evidence: "testing/verify-commands-contract.sh"
---

Nine Vibe mode bodies and three execute steps now live in focused references, and one rendered payload template serves all 20 skill-activation sites without changing child-prompt behavior.

## What Was Built

- Nine `references/vibe-mode-*.md` files with parent-owned mode headings.
- Three execute-step references loaded through explicit runtime Read directives.
- One two-branch skill-activation rendering template used by 20 local-policy sites.
- Effective-content and direct-reader contract coverage for the decomposed files.
- Stable entry points for both oversized contract scripts, with checks moved into sourced modules.

## Files Modified

### Command content

- `commands/vibe.md`
- `commands/research.md`
- `commands/fix.md`
- `commands/map.md`
- `commands/qa.md`
- `commands/debug.md`

### Existing protocol references

- `references/execute-protocol.md`
- `references/vibe-input-parsing.md`
- `references/vibe-uat-remediation.md`

### New lifecycle mode references

- `references/vibe-mode-bootstrap.md`
- `references/vibe-mode-milestone-uat-recovery.md`
- `references/vibe-mode-plan.md`
- `references/vibe-mode-execute.md`
- `references/vibe-mode-verify.md`
- `references/vibe-mode-archive.md`

### New phase mutation references

- `references/vibe-mode-add-phase.md`
- `references/vibe-mode-insert-phase.md`
- `references/vibe-mode-remove-phase.md`

### New execute and payload references

- `references/execute-post-build-qa.md`
- `references/execute-qa-result-gating.md`
- `references/execute-uat.md`
- `references/skill-activation-payload.md`

### Contract entry points

- `scripts/verify-vibe.sh`
- `testing/verify-commands-contract.sh`
- `testing/verify-skill-activation.sh`

### Command contract modules

- `testing/verify-commands-contract/base-contracts.bash`
- `testing/verify-commands-contract/installation-contracts.bash`
- `testing/verify-commands-contract/verification-guardrails.bash`
- `testing/verify-commands-contract/vibe-lifecycle.bash`
- `testing/verify-commands-contract/qa-gating.bash`
- `testing/verify-commands-contract/reference-contracts.bash`

### Skill payload contract modules

- `testing/verify-skill-activation/runtime-fixtures.bash`
- `testing/verify-skill-activation/payload-contract-helpers.bash`
- `testing/verify-skill-activation/explicit-outcome-contracts.bash`

### Skill agent contract modules

- `testing/verify-skill-activation/agent-contracts.bash`
- `testing/verify-skill-activation/execute-agent-contracts.bash`
- `testing/verify-skill-activation/additive-contracts.bash`
- `testing/verify-skill-activation/subagent-hook-contracts.bash`

### Execute contract readers

- `testing/verify-askuserquestion-contract.sh`
- `testing/verify-execute-delegation-routing.sh`
- `testing/verify-human-only-uat-contract.sh`
- `testing/verify-qa-persistence-contract.sh`

### Vibe contract readers

- `testing/verify-uat-recurrence.sh`
- `testing/verify-uat-autocontinue.sh`
- `testing/verify-lead-research-conditional.sh`
- `testing/verify-live-validation-policy.sh`
- `testing/verify-ghost-team-cleanup.sh`

### Vibe BATS readers

- `tests/milestone-context.bats`
- `tests/auto-uat.bats`
- `tests/resolve-artifact-path.bats`
- `tests/template-nesting.bats`
- `tests/planning-git-callsites.bats`
- `tests/compile-verify-context-for-uat.bats`

### Execute BATS readers

- `tests/discovered-issues-surfacing.bats`
- `tests/debugger-codebase-mapping.bats`

## Deviations

The research table missed 25 raw-parent assertions across these 15 readers: `testing/verify-uat-recurrence.sh`, `testing/verify-uat-autocontinue.sh`, `testing/verify-lead-research-conditional.sh`, `testing/verify-live-validation-policy.sh`, `testing/verify-ghost-team-cleanup.sh`, `testing/verify-askuserquestion-contract.sh`, `scripts/verify-vibe.sh`, `tests/milestone-context.bats`, `tests/auto-uat.bats`, `tests/resolve-artifact-path.bats`, `tests/template-nesting.bats`, `tests/planning-git-callsites.bats`, `tests/discovered-issues-surfacing.bats`, `tests/debugger-codebase-mapping.bats`, and `tests/compile-verify-context-for-uat.bats`. Each now reads the owning extracted reference or an effective expanded fixture.

Mandatory file-size hooks also required the two large contract scripts to retain their public entry paths while sourcing focused modules. The payload inventory additionally required `references/vibe-input-parsing.md`, which held two logical QA remediation render sites omitted from the plan file list.
