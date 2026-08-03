---
phase: 1
plan: 4
title: Health-store unification and three-tier auto-despawn
status: complete
completed: 2026-08-03
tasks_completed: 4
tasks_total: 4
commit_hashes:
  - 9f217ae
deviations:
  - "agent-stop.sh and agent-pid-tracker.sh required no source edits because the stop path already unregisters PID entries. The new health termination path also unregisters them."
  - "The full run-all suite was not run because the shared tree contains parallel edits and an unrelated executable-mode failure in testing/verify-agent-spawn-guard.sh."
pre_existing_issues: []
ac_results:
  - criterion: "agent-health.sh state is session-scoped onto the per-agent registration files and preserves per-teammate keys"
    verdict: pass
    evidence: "9f217ae. tests/agent-health.bats session store and session isolation cases"
  - criterion: "One liveness check and one role-normalization function serve the unified lifecycle"
    verdict: pass
    evidence: "scripts/lib/active-agent-state.sh. ShellCheck and focused BATS"
  - criterion: "Artifact delivery terminates live agents for Lead, Dev, Scout, and QA without idle waiting"
    verdict: pass
    evidence: "tests/agent-health.bats artifact suffixes and registration cleanup cases"
  - criterion: "Dead PID orphan recovery remains available"
    verdict: pass
    evidence: "tests/agent-health.bats orphan recovery cases. tests/agent-health-integration.bats"
  - criterion: "Idle remediation nudges once, then terminates and flags one respawn cycle"
    verdict: pass
    evidence: "tests/agent-health.bats nudge, termination, activity reset, and one-cycle cases"
  - criterion: "Unified cleanup unregisters the PID tracker entry"
    verdict: pass
    evidence: "9f217ae. Lifecycle simulation and agent-start registers PID, agent-stop unregisters it"
  - criterion: "Slugged teammate names normalize to their base role"
    verdict: pass
    evidence: "tests/agent-health.bats slugged teammate normalization case"
  - criterion: "Health reads and writes use the active-agent registration files as the lifecycle store"
    verdict: pass
    evidence: "scripts/agent-health.sh health_state_dir and health_file_for"
---

Unified agent health state with session-scoped registration files and script-owned artifact, orphan, and idle remediation.

## What Was Built

- Moved production health metadata into Plan 01-01 per-agent registration files while retaining an explicit test-directory override.
- Delegated role normalization and PID liveness to active-agent-state.sh, including descriptive slug matching.
- Added artifact suffix detection for Lead, Dev, Scout, and QA with registration-time mtime protection.
- Added nudge-first idle remediation, activity reset, one terminate-and-respawn cycle, and PID tracker cleanup.
- Added lifecycle tests for session isolation, same-role keys, all artifact roles, pre-existing artifacts, idle transitions, and cleanup.

## Files Modified

- `scripts/agent-health.sh` -- unified health storage and implemented three-tier remediation.
- `scripts/lib/active-agent-state.sh` -- centralized PID liveness and widened role normalization.
- `tests/agent-health.bats` -- added session, artifact, idle state-machine, and slugged-role coverage.

## Deviations

The existing agent-stop PID unregister path already covered normal stop cleanup, so no source change was needed in `scripts/agent-stop.sh` or `scripts/agent-pid-tracker.sh`. The health termination path now invokes the same unregister command. Focused checks passed, including Bash syntax, ShellCheck, 48 lifecycle BATS cases, the hook classifier suite, the active-agent-state suite, and the pipefail contract. The full suite remains for the quiescent shared tree because parallel edits currently make its unrelated executable-mode check fail.
