After QA writes its VERIFICATION artifact, sync tracked known issues from that artifact before reading the gate:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification-output-path}" 2>/dev/null || true
```
After sync, auto-promote surviving known issues to `STATE.md ## Todos`:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
```
- Phase-level VERIFICATION writes merge new pre-existing issues into the existing registry without clearing the execution-time backlog.
- Round-scoped `R{RR}-VERIFICATION.md` writes are authoritative for unresolved known issues and may prune or clear `{phase-dir}/known-issues.json`.

After QA completes (subagent returns or teammate sends `qa_verdict`), run the deterministic gate:
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
```

**Follow `qa_gate_routing` output literally: no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
- **`qa_gate_routing=PROCEED_TO_UAT`:** Display `◆ QA: PASS`: proceed to Step 4.5 (UAT)
- **`qa_gate_routing=REMEDIATION_REQUIRED`:** Display `◆ QA: ${qa_gate_result} (${qa_gate_fail_count} FAIL)`: enter QA remediation loop below. If `qa_gate_known_issues_override=true`, the contract verification passed but `{qa_gate_known_issue_count}` unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
- **`qa_gate_routing=QA_RERUN_REQUIRED`:** Display `⚠ QA result invalid (writer=${qa_gate_writer}, result=${qa_gate_result}). Re-running QA.`: re-spawn QA agent immediately (no plan→execute cycle). Max 2 retries. If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain ${qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check: do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified ${qa_gate_plans_verified_count}/${qa_gate_plan_count} plans. Every plan in the phase must be verified: include all plan IDs in plans_verified." If QA still fails to produce a valid result, STOP and escalate: "QA failed to produce a valid VERIFICATION.md after {N} attempts. Manual intervention needed."

**QA Remediation Loop (inline, same session):**

This loop runs inline during execution: no second `/vbw:vibe` call needed. If the session ends mid-loop, phase-detect will detect the `.qa-remediation-stage` state file and route to `needs_qa_remediation` on the next `/vbw:vibe` call.

1. **Init state:**
   ```bash
   bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" init "{phase-dir}"
   ```
  Parse output: `stage`, `round`, `round_dir`, `source_verification_path`, `source_fail_count`, `known_issues_path`, `known_issues_count`, `input_mode`, `verification_path`
  <qa_remediation_artifact_contract>
  `round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths. Claude Code may run subagents from `.claude/worktrees/agent-*` sidechain CWDs. pass these exact paths to Lead, Dev, and QA prompts and never rewrite them relative to the current CWD. Rewriting those paths relative to sidechain CWDs can write or read remediation artifacts from the wrong location and break resume or verification.
  </qa_remediation_artifact_contract>
  <qa_remediation_spawn_contract>
  QA remediation uses plain sequential subagent calls. Do not form an agent team, do not spawn teammates, use plain sequential subagent Agent calls.

Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

Use remediation metadata paths in prompts. VBW worktree targeting is task prompt/state metadata, not a spawn isolation or cwd handoff.
  </qa_remediation_spawn_contract>
  <qa_remediation_no_tool_circuit_breaker>
  After any QA remediation Lead, Dev, or QA subagent returns, follow the no-tool circuit breaker in `references/subagent-contracts.md` before artifact validation, deterministic gates, or state advancement. If it triggers, STOP without advancing `.qa-remediation-stage` and report the failed role and stage or task.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  </qa_remediation_no_tool_circuit_breaker>

2. **Loop (until PROCEED_TO_UAT or user intervention):**

   **stage=plan:** Create `R{RR}-PLAN.md` in `{round_dir}`:
  - Read `source_verification_path` from `qa-remediation-state.sh get` metadata for failed checks when `source_fail_count>0`
  - Read `known_issues_path` when `known_issues_count>0`: this is the phase-scoped unresolved known-issues backlog that must clear before UAT

     **Source selection:**
     - Round 01 uses the phase-level VERIFICATION (`{NN}-VERIFICATION.md` or brownfield `VERIFICATION.md`)
     - Round 02+ first checks the previous round's `R{RR}-VERIFICATION.md`. If that artifact still contains FAIL checks, use it. If it passed QA but the deterministic gate still required another remediation round, carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs.

    - If `source_verification_path` is empty and `known_issues_count=0`, STOP and restore the earlier verification artifact that should have carried the unresolved FAILs before planning. Do NOT silently continue when the previous round verification is missing or when the carried-forward phase-level source artifact no longer exists.

   - **Deviation Classification (NON-NEGOTIABLE):** For each FAIL check in the source VERIFICATION.md, classify as exactly one of:
      **Implementation fixes:**
      - **`code-fix`**: The code/config must change to match the plan. The remediation plan MUST include tasks that modify the executable/config/test artifacts that actually implement the fix: not just planning or documentation files.

      **Plan and process decisions:**
      - **`plan-amendment`**: The deviation was a valid improvement over the original plan. The remediation plan MUST include a task to update the original PLAN.md with the actual approach and rationale, marking the deviation as resolved-by-amendment.
      - **`process-exception`**: Genuinely non-fixable retroactive issue (e.g., cannot un-batch a historical commit without risky rebase). The remediation plan must include the exception classification with explicit reasoning why it is non-fixable.

      **Documentation fixes:**
      - **`doc-fix`**: The documentation artifact is the product surface under test. The remediation plan MUST include `path: "docs/file.md"` for the named documentation path, and the round summary must record that same path in `files_modified`.
   - **The plan MUST include at least one `code-fix`, `doc-fix`, or `plan-amendment` task if ANY FAIL check is classifiable as such.** A plan that classifies all FAIL checks as `process-exception` when code-fix, doc-fix, or plan-amendment alternatives exist is itself a defect. Documentation-only changes to SUMMARY.md deviations arrays are NOT a valid resolution for code/architecture deviations.
   - Include `fail_classifications:` YAML array in R{RR}-PLAN.md frontmatter.

     - `code-fix` / `process-exception` entries: `{id: "FAIL-ID", type: "code-fix|process-exception", rationale: "..."}`
     - `doc-fix` entries: `{id: "FAIL-ID", type: "doc-fix", path: "docs/file.md", rationale: "..."}`
     - `plan-amendment` entries MUST also identify the original plan being amended: `{id: "FAIL-ID", type: "plan-amendment", rationale: "...", source_plan: "01-01-PLAN.md"}`. `source_plan` must reference an original plan in the current phase only: never a sibling phase, archived milestone, or remediation plan.

    - Always include `known_issues_input:` and `known_issue_resolutions:` in R{RR}-PLAN.md frontmatter. When `known_issues_count=0` or `input_mode=verification`, set both to empty arrays (`known_issues_input: []` and `known_issue_resolutions: []`) rather than omitting them.
    - When `input_mode=known-issues` or `input_mode=both`, populate `known_issues_input:` with every carried known issue from `known_issues_path` using the canonical `{test,file,error}` JSON object-string shape already used for tracked issues.
    - When `input_mode=known-issues` or `input_mode=both`, populate `known_issue_resolutions:` with a matching entry for every carried known issue using `{test,file,error,disposition,rationale}` JSON object strings. Valid `disposition` values are `resolved`, `accepted-process-exception`, and `unresolved`.

     - `resolved` = this round fixes the issue and QA should no longer return it in `pre_existing_issues`
     - `accepted-process-exception` = QA must verify the issue is real but non-blocking for this phase, omit it from `pre_existing_issues`, and leave it visible via the summary/STATE backlog instead of reopening the round forever
     - `unresolved` = the issue remains blocking and the next round must continue to carry it

    - Do NOT omit the `known_issues_input` or `known_issue_resolutions` keys. Do NOT omit a carried known issue from either array. The deterministic gate treats missing coverage as a failed remediation round even if QA writes `PASS`.
   - Scope the plan to those failures: what to fix, which files, acceptance criteria
  - The orchestrator coordinates the remediation loop and spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md` (QA identified problems, Lead determines fixes).
  - Resolve Lead settings before composing the Lead task:
    ```bash
    if ! AGENT_SETTINGS=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-agent-settings.sh" lead .vbw-planning/config.json "${VBW_PLUGIN_ROOT}/config/model-profiles.json" "{effort}"); then
      echo "$AGENT_SETTINGS" >&2
      exit 1
    fi
    eval "$AGENT_SETTINGS"
    LEAD_MODEL="$RESOLVED_MODEL"
    LEAD_MAX_TURNS="$RESOLVED_MAX_TURNS"
    LEAD_REASONING="$RESOLVED_REASONING"
    ```
  - Spawn Lead as a plain sequential work-unit subagent with `subagent_type: "vbw:vbw-lead"` and `model: "${LEAD_MODEL}"`. If `LEAD_MAX_TURNS` is non-empty, include `maxTurns: ${LEAD_MAX_TURNS}`. If `LEAD_MAX_TURNS` is empty, omit `maxTurns` because the resolved profile is unlimited.

    Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.

    If `LEAD_REASONING` is non-empty, also pass `effort: "${LEAD_REASONING}"`. If `LEAD_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
  - Lead prompt MUST include the authoritative `round_dir`, `source_verification_path`, `known_issues_path`, and output path `{round_dir}/R{RR}-PLAN.md`, the failed-check and known-issue inputs above, the deviation-classification and known-issue-resolution requirements above, and `Read the remediation plan template at /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-PLAN.md and follow its structure exactly.`
  - After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before normalizing plan filenames, validating the generated plan, or advancing state. If it triggers, STOP without advancing `.qa-remediation-stage`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
  - Normalize plan filenames before validation:
    ```bash
    NORM_SCRIPT="${VBW_PLUGIN_ROOT}/scripts/normalize-plan-filenames.sh"
    if [ -f "$NORM_SCRIPT" ]; then
      bash "$NORM_SCRIPT" "{round_dir}"
    fi
    ```
  - Validate the exact QA remediation plan artifact before advancing:
    ```bash
    bash "${VBW_PLUGIN_ROOT}/scripts/validate-uat-remediation-artifact.sh" plan "{round_dir}/R{RR}-PLAN.md"
    ```
    If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`. Do not search for an alternate PLAN.md.
  - After plan validation passes, advance state: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`

   **stage=execute:** Spawn a Dev subagent per `R{RR}-PLAN.md`:
   - **Always subagent: NO team creation for QA remediation (NON-NEGOTIABLE)**
   - Set `subagent_type: "vbw:vbw-dev"` and `model: "${DEV_MODEL}"`
   - Dev fixes code, commits, writes `R{RR}-SUMMARY.md` in `{round_dir}` using `templates/REMEDIATION-SUMMARY.md` (NOT `templates/SUMMARY.md`)
     - The remediation summary frontmatter MUST include aggregated `commit_hashes`, `files_modified`, and `deviations`
     - `files_modified` is required even for documentation-only rounds so `qa-result-gate.sh` can deterministically distinguish metadata-only remediation from real code changes
     - When `input_mode=known-issues` or `input_mode=both`, the remediation summary frontmatter MUST also include `known_issue_outcomes` with one `{test,file,error,disposition,rationale}` JSON object string per carried known issue. Keys and `disposition` values must match `R{RR}-PLAN.md` `known_issue_resolutions`. Do not silently drop accepted non-blocking issues.
    - After Dev returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before checking the summary or advancing state. If it triggers, STOP without advancing `.qa-remediation-stage`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
    - After Dev completes without a no-tool provisioning failure, advance state: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`

   **stage=verify:** Re-run QA:
   - Run `compile-verify-context.sh --remediation-only {phase-dir}` to get compounded verification history plus the current round's plan/summary context only
   - Spawn QA agent as subagent, writes to `{verification_path}` (from `qa-remediation-state.sh` metadata)
     - Output path: `{round_dir}/R{RR}-VERIFICATION.md`, phase-level VERIFICATION.md stays frozen
    - After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before syncing known issues or running the deterministic gate. If it triggers, STOP without advancing `.qa-remediation-stage`.

No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
     - After QA persists `{verification_path}`, immediately sync tracked known issues from that round artifact:
       ```bash
       bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-verification "{phase-dir}" "{verification_path}" 2>/dev/null || true
       ```
     - After sync-verification, auto-promote surviving known issues to `STATE.md ## Todos`:
       ```bash
       bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" promote-todos "{phase-dir}" 2>/dev/null || true
       ```
    - If `compile-verify-context.sh` emits a `KNOWN ISSUES` block, include in QA's task description: "Tracked phase known issues are not informational in remediation rounds. Re-check every carried known issue from `known_issues_input` / `known_issue_resolutions`. Return only still-blocking issues in `pre_existing_issues`. If a carried issue is verified as an `accepted-process-exception`, omit it from `pre_existing_issues`, confirm that the accepted non-blocking disposition is credible for this phase, and rely on the matching `known_issue_outcomes` entry to preserve visibility after the blocking registry clears. A clean remediation QA run must return an empty `pre_existing_issues` array for all resolved or accepted non-blocking carried issues so `{phase-dir}/known-issues.json` can clear."
     - Include the compiled verify context output in QA's task description
      - **Include in QA task description:** "In addition to verifying the remediation plan's own must_haves, you MUST re-verify each original FAIL from the VERIFICATION HISTORY section. For each FAIL_ID: if classified as code-fix, verify the code now matches the plan. if classified as doc-fix, verify the named documentation path now contains the required content. if classified as plan-amendment, verify the original PLAN.md has been updated with the actual approach and rationale. if classified as process-exception, verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL. if code-fix, doc-fix, or plan-amendment still appears viable, keep the FAIL open. Any original FAIL that has not been addressed by one of these four paths is still a FAIL."
      - The deterministic gate validates structural evidence only. QA must decide whether a `process-exception` is *actually* justified during this re-verification step: documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment.
   - After QA returns, run the deterministic gate:
     ```bash
     bash "${VBW_PLUGIN_ROOT}/scripts/qa-result-gate.sh" "{phase-dir}"
     ```
     **Follow `qa_gate_routing` output literally: no exceptions, no judgment, no rationalization. Do NOT evaluate whether failures are justified, acceptable, or minor. The gate script has already made the decision:**
     - **`qa_gate_routing=PROCEED_TO_UAT`:** Advance to done: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" advance "{phase-dir}"`, display `◆ QA remediation: PASS (round {RR})`, break loop, proceed to Step 4.5
    - **`qa_gate_routing=REMEDIATION_REQUIRED`:** Start new round: `bash "${VBW_PLUGIN_ROOT}/scripts/qa-remediation-state.sh" needs-round "{phase-dir}"`, display `◆ QA remediation round {RR}: ${qa_gate_result}`, continue loop. If `qa_gate_known_issues_override=true`, unresolved tracked known issues remain in `{phase-dir}/known-issues.json`.
     - **`qa_gate_routing=QA_RERUN_REQUIRED`:** Re-spawn QA immediately (max 2 retries per round). If `qa_gate_deviation_override=true`, tell QA: "Previous QA run found PASS but SUMMARY.md files contain ${qa_gate_deviation_count} deviations that were not reflected as FAIL checks. Each deviation MUST become a FAIL check: do not rationalize deviations as acceptable." If `qa_gate_plan_coverage` is present, tell QA: "Previous QA run only verified ${qa_gate_plans_verified_count}/${qa_gate_plan_count} plans. Every plan in the phase must be verified: include all plan IDs in plans_verified." If still invalid, treat as REMEDIATION_REQUIRED.
      - **When `qa_gate_metadata_only_override=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round made no implementation changes: only planning/documentation updates. The round still depends on a code-fix path (or omitted fail_classifications), so the original failures cannot be considered resolved without implementation changes. ${qa_gate_phase_deviation_count} phase deviations remain recorded.` This override is the deterministic safety net for rounds that still depend on implementation changes. Pure plan-amendment rounds can pass when the original plan was actually updated, and pure process-exception rounds still need planning/remediation-artifact evidence: delivered docs/README changes alone do not count. The next round's `stage=plan` MUST classify each FAIL as code-fix, doc-fix, plan-amendment, or process-exception per the Deviation Classification rules above.
      - **When `qa_gate_process_exception_evidence_missing=true`** (routing will be `REMEDIATION_REQUIRED`): Display `⚠ QA remediation round has a clean verification result, but the gate cannot find recorded remediation-artifact evidence. Record an existing remediation RNN-PLAN.md/RNN-SUMMARY.md or a valid original phase PLAN.md before treating the process-exception as resolved.` Continue with a new remediation round.
      - **When `qa_gate_round_change_evidence_empty=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Display `⚠ QA remediation round recorded no change evidence: both files_modified and commit_hashes were empty. A PASS without any recorded changed files or commits cannot resolve prior FAILs.` The next round must produce real code/plan changes or capture justified remediation evidence instead of an empty summary.
      - **When `qa_gate_round_change_evidence_unavailable=true`** (routing will be `REMEDIATION_REQUIRED`): This flag only fires when the round includes `code-fix` classifications. Pure `plan-amendment` and `process-exception` rounds are validated by their own evidence paths (source-plan coverage and process-exception artifact evidence respectively) rather than by code change evidence. Display `⚠ QA remediation round recorded change evidence that could not be verified as current-round work. Either the recorded files did not match any committed or current round-local remediation-artifact changes after the source verification commit, or the referenced commit_hashes could not be proven to belong to this round, so the actual changed files could not be trusted.` Restore explicit files_modified entries and/or round-local commit evidence anchored to the remediation round before treating the failures as resolved.
