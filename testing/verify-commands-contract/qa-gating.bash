echo "=== QA Result Gate Contract ==="

QA_FILE="$COMMANDS_DIR/qa.md"

if grep -Eq 'qa-remediation-state\.sh"? get' "$QA_FILE"; then
  pass "qa: resolves remediation state before choosing verification output path"
else
  fail "qa: missing qa-remediation-state.sh get. standalone QA may overwrite phase-level verification"
fi

if grep -q 'first_qa_attention_phase' "$QA_FILE" && grep -q 'qa_attention_status' "$QA_FILE"; then
  pass "qa: auto-detect can target stale or failed QA even with terminal UAT"
else
  fail "qa: missing first_qa_attention-based auto-detect guidance"
fi

if grep -q 'pending`, `failed`, or `verify`' "$QA_FILE"; then
  pass "qa: auto-detect includes verify-stage remediation escape hatch"
else
  fail "qa: auto-detect missing verify-stage remediation escape hatch"
fi

if grep -q 'case "\$QA_STAGE" in' "$QA_FILE" && grep -q 'verify)' "$QA_FILE" && grep -q 'done)' "$QA_FILE" && grep -q 'plan|execute' "$QA_FILE"; then
  pass "qa: uses persisted verification_path only for verify/done and blocks plan/execute"
else
  fail "qa: missing verify/done output guard and plan/execute stop for persisted verification_path"
fi

if grep -Eq 'resolve-verification-path\.sh"? current' "$QA_FILE"; then
  pass "qa: resolves authoritative verification path for done-stage remediation"
else
  fail "qa: missing authoritative done-stage verification path resolution"
fi

if grep -q 'source_verification_path' "$ROOT/references/execute-protocol.md" && grep -q 'verification_path' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: parses full QA remediation metadata contract"
else
  fail "execute-protocol: missing source_verification_path/verification_path in QA remediation metadata parsing"
fi

if grep -Eq 'source_plan`? must reference an original plan in the current phase only' "$ROOT/references/execute-protocol.md" \
  && grep -Eq 'source_plan`? must reference an original plan in the current phase only' "$VIBE_FILE"; then
  pass "execute-protocol/vibe: plan-amendment source_plan is constrained to current-phase original plans"
else
  fail "execute-protocol/vibe: missing current-phase-only constraint for plan-amendment source_plan"
fi

if grep -q 'carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs' "$ROOT/references/execute-protocol.md" \
  && grep -q 'carry forward the nearest earlier verification artifact in the remediation chain that still contains the unresolved FAILs' "$VIBE_FILE"; then
  pass "execute-protocol/vibe: round 02+ planning carries unresolved FAIL source forward across gate-rejected PASS rounds"
else
  fail "execute-protocol/vibe: missing unresolved FAIL carry-forward guidance for round 02+ remediation planning"
fi

if grep -q 'verification_path=' "$QA_FILE" && grep -q 'Output path: {VERIF_PATH}' "$QA_FILE"; then
  pass "qa: uses persisted verification_path contract for standalone QA output"
else
  fail "qa: missing persisted verification_path contract for standalone QA output"
fi

if grep -q 'qa-result-gate\.sh' "$QA_FILE" \
  && grep -Eq 'qa-remediation-state\.sh"? advance' "$QA_FILE" \
  && grep -Eq 'qa-remediation-state\.sh"? needs-round' "$QA_FILE"; then
  pass "qa: standalone remediation QA reruns deterministic gate before trusting round-scoped PASS artifacts"
else
  fail "qa: missing deterministic gate reconciliation for standalone remediation QA"
fi

qa_remediation_block="$({
  awk '
    /^\*\*QA Remediation mode \(needs_qa_remediation\)/ { in_block=1 }
    /^\*\*QA Remediation \+ UAT blocking:/ { in_block=0 }
    in_block { print }
  ' "$VIBE_FILE"
} || true)"

qa_remediation_plan_block="$({
  awk '
    /^#### stage=plan[[:space:]]*$/ { in_block=1 }
    /^#### stage=execute[[:space:]]*$/ { in_block=0 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

qa_remediation_execute_block="$({
  awk '
    /^#### stage=execute[[:space:]]*$/ { in_block=1 }
    /^#### stage=verify[[:space:]]*$/ { in_block=0 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

execute_protocol_qa_remediation_block="$({
  awk '
    /^\*\*QA Remediation Loop \(inline, same session\):/ { in_block=1 }
    /^### Step 4\.5: Human acceptance testing \(UAT\)/ { in_block=0 }
    in_block { print }
  ' "$ROOT/references/execute-protocol.md"
} || true)"

qa_remediation_verify_block="$({
  awk '
    /^#### stage=verify[[:space:]]*$/ { in_block=1 }
    in_block { print }
  ' <<< "$qa_remediation_block"
} || true)"

if grep -Fq '<qa_remediation_artifact_contract>' <<< "$qa_remediation_block" \
  && grep -Fq '`round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` are authoritative host-repository paths from `qa-remediation-state.sh` metadata' <<< "$qa_remediation_block" \
  && grep -Fq 'Pass these exact paths to Lead, Dev, and QA prompts' <<< "$qa_remediation_block" \
  && grep -Fq '.claude/worktrees/agent-*' <<< "$qa_remediation_block" \
  && grep -Fq 'never rewrite them relative to the current CWD' <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has host artifact path contract"
else
  fail "vibe: QA remediation missing host artifact path contract"
fi

if grep -Fq '<qa_remediation_artifact_contract>' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq '`round_dir`, `source_verification_path`, `known_issues_path`, and `verification_path` from `qa-remediation-state.sh` metadata are authoritative host-repository paths' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'pass these exact paths to Lead, Dev, and QA prompts' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'never rewrite them relative to the current CWD' <<< "$execute_protocol_qa_remediation_block"; then
  pass "execute-protocol: QA remediation host paths cover Lead, Dev, and QA"
else
  fail "execute-protocol: QA remediation host path contract missing Lead/Dev/QA coverage"
fi

if grep -Fq '<qa_remediation_spawn_contract>' <<< "$qa_remediation_block" \
  && grep -Fq 'QA remediation spawns are plain sequential subagent calls' <<< "$qa_remediation_block" \
  && grep -Fq "$NON_TEAM_INVARIANT_TEXT" <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has canonical non-team spawn invariant"
else
  fail "vibe: QA remediation missing canonical non-team spawn invariant"
fi

if grep -Fq 'future section explicitly prepares VBW worktree targeting' <<< "$qa_remediation_block" \
  || grep -Fq 'unless a future section' <<< "$qa_remediation_block" \
  || grep -Fq 'prepared VBW worktree target' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation must not preserve worktree-targeting spawn exceptions"
else
  pass "vibe: QA remediation rejects worktree-targeting spawn exceptions"
fi

if grep -Fq '<qa_remediation_no_tool_circuit_breaker>' <<< "$qa_remediation_block" \
  && grep -Fq 'After any QA remediation Lead, Dev, or QA subagent returns' <<< "$qa_remediation_block" \
  && grep -Fq 'follow the no-tool circuit breaker in `references/subagent-contracts.md`' <<< "$qa_remediation_block" \
  && grep -Fq 'STOP without advancing `.qa-remediation-stage`' <<< "$qa_remediation_block" \
  && grep -Fq "$NO_TOOL_INVARIANT_TEXT" <<< "$qa_remediation_block"; then
  pass "vibe: QA remediation has canonical no-tool circuit breaker"
else
  fail "vibe: QA remediation missing canonical no-tool circuit breaker"
fi

if grep -Fq 'tools, Bash, filesystem, edits, or API-session access are unavailable' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation no-tool breaker still uses Bash-only wording"
else
  pass "vibe: QA remediation no-tool breaker includes generic shell signal"
fi

if grep -Fq 'unavailable tools, Bash, filesystem, edits, or API-session access' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation return sites still use Bash-only wording"
else
  pass "vibe: QA remediation return sites include generic shell signal"
fi

if grep -Fq 'After any QA remediation Dev or QA subagent returns' <<< "$qa_remediation_block"; then
  fail "vibe: QA remediation shared no-tool breaker still excludes Lead"
else
  pass "vibe: QA remediation shared no-tool breaker includes Lead"
fi

if grep -Fq 'After any QA remediation Lead, Dev, or QA subagent returns' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'follow the no-tool circuit breaker in `references/subagent-contracts.md`' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'STOP without advancing `.qa-remediation-stage`' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq "$NO_TOOL_INVARIANT_TEXT" <<< "$execute_protocol_qa_remediation_block"; then
  pass "execute-protocol: QA remediation shared no-tool breaker includes Lead"
else
  fail "execute-protocol: QA remediation shared no-tool breaker missing Lead or canonical invariant"
fi

check_literal_before_regex "vibe: QA no-tool breaker appears before remediation state advance" "$qa_remediation_block" '<qa_remediation_no_tool_circuit_breaker>' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA no-tool breaker appears before deterministic gate" "$qa_remediation_block" '<qa_remediation_no_tool_circuit_breaker>' 'qa-result-gate.sh'

if grep -Fq 'The orchestrator/Lead writes the plan' <<< "$qa_remediation_plan_block" \
  || grep -Fq 'The orchestrator writes the plan' <<< "$qa_remediation_plan_block"; then
  fail "vibe: QA remediation plan stage still has ambiguous orchestrator-authored planning wording"
else
  pass "vibe: QA remediation plan stage removes ambiguous orchestrator-authored wording"
fi

if grep -Fq 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'subagent_type: "vbw:vbw-lead"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'resolve-agent-settings.sh lead' <<< "$qa_remediation_plan_block" \
  && grep -Fq '.vbw-planning/config.json' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'config/model-profiles.json' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'LEAD_MODEL="$RESOLVED_MODEL"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'LEAD_MAX_TURNS="$RESOLVED_MAX_TURNS"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'model: "${LEAD_MODEL}"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'maxTurns: ${LEAD_MAX_TURNS}' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'omit `maxTurns` because the resolved profile is unlimited' <<< "$qa_remediation_plan_block" \
  && grep -Fq "$NON_TEAM_INVARIANT_TEXT" <<< "$qa_remediation_plan_block" \
  && grep -Fq 'Read the remediation plan template at /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/templates/REMEDIATION-PLAN.md' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation plan stage resolves Lead settings and spawns with safe shape"
else
  fail "vibe: QA remediation plan stage missing Lead settings resolution or safe spawn contract"
fi

check_literal_before_literal "vibe: QA plan resolves Lead settings before using Lead model" "$qa_remediation_plan_block" 'resolve-agent-settings.sh lead' 'model: "${LEAD_MODEL}"'
if grep -Fq 'Plan recovery and Lead spawn' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If the canonical `{round_dir}/R{RR}-PLAN.md` exists after normalization' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If validation passes, do not spawn Lead again. Reuse the persisted plan' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation reuses existing validated plan on resume"
else
  fail "vibe: QA remediation missing existing-plan recovery before Lead respawn"
fi
check_literal_before_literal "vibe: QA existing-plan recovery normalizes before canonical probe" "$qa_remediation_plan_block" 'normalize-plan-filenames.sh' 'If the canonical `{round_dir}/R{RR}-PLAN.md` exists after normalization'
check_literal_before_literal "vibe: QA existing-plan recovery appears before Lead spawn" "$qa_remediation_plan_block" 'Plan recovery and Lead spawn' 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`'
check_literal_before_literal "vibe: QA plan Lead spawn appears before Lead return breaker" "$qa_remediation_plan_block" 'spawns exactly one Lead subagent to write `{round_dir}/R{RR}-PLAN.md`' 'After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`'

if grep -Fq 'Normalize plan filenames before validation' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'normalize-plan-filenames.sh' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'validate-uat-remediation-artifact.sh plan "{round_dir}/R{RR}-PLAN.md"' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'If validation fails, display the validator error and STOP without advancing `.qa-remediation-stage`' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'Do not search for an alternate PLAN.md' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation plan stage validates canonical plan before advance"
else
  fail "vibe: QA remediation plan stage missing normalization/validation gate before advance"
fi

if grep -Fq 'Always include `known_issues_input:` and `known_issue_resolutions:` in R{RR}-PLAN.md frontmatter' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'known_issues_count=0' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'input_mode=verification' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'known_issues_input: []' <<< "$qa_remediation_plan_block" \
  && grep -Fq 'known_issue_resolutions: []' <<< "$qa_remediation_plan_block"; then
  pass "vibe: QA remediation plan always includes known-issue arrays"
else
  fail "vibe: QA remediation plan may omit validator-required known-issue arrays"
fi

if grep -Fq 'Always include `known_issues_input:` and `known_issue_resolutions:` in R{RR}-PLAN.md frontmatter' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'known_issues_count=0' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'input_mode=verification' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'known_issues_input: []' <<< "$execute_protocol_qa_remediation_block" \
  && grep -Fq 'known_issue_resolutions: []' <<< "$execute_protocol_qa_remediation_block"; then
  pass "execute-protocol: QA remediation plan always includes known-issue arrays"
else
  fail "execute-protocol: QA remediation plan may omit validator-required known-issue arrays"
fi

if block_contains_normalized "$qa_remediation_plan_block" \
  'After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before normalization, plan validation, or state advancement. If it triggers, STOP without advancing `.qa-remediation-stage`. '"$NO_TOOL_INVARIANT_TEXT" \
  && block_contains_normalized "$qa_remediation_execute_block" \
    'After Dev returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before checking the summary or advancing state. If it triggers, STOP without advancing `.qa-remediation-stage`. '"$NO_TOOL_INVARIANT_TEXT" \
  && block_contains_normalized "$qa_remediation_verify_block" \
    'After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md` before syncing known issues or running the deterministic gate. If it triggers, STOP without advancing `.qa-remediation-stage`. '"$NO_TOOL_INVARIANT_TEXT"; then
  pass "vibe: QA remediation applies no-tool breaker at Lead, Dev, and QA return sites"
else
  fail "vibe: QA remediation missing no-tool breaker at Lead, Dev, or QA return site"
fi

check_literal_before_regex "vibe: QA plan Lead breaker appears before plan-stage state advance" "$qa_remediation_plan_block" 'After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA plan Lead breaker appears before plan normalization" "$qa_remediation_plan_block" 'After Lead returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'Normalize plan filenames before validation'
check_literal_before_literal "vibe: QA plan normalization appears before plan validation" "$qa_remediation_plan_block" 'Normalize plan filenames before validation' 'Validate the exact QA remediation plan artifact before advancing'
check_literal_before_regex "vibe: QA plan validation appears before plan-stage state advance" "$qa_remediation_plan_block" 'validate-uat-remediation-artifact.sh plan "{round_dir}/R{RR}-PLAN.md"' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA plan validation passes before state advance wording" "$qa_remediation_plan_block" 'Validate the exact QA remediation plan artifact before advancing' 'After plan validation passes, advance state'
check_literal_before_regex "vibe: QA execute Dev breaker appears before execute-stage state advance" "$qa_remediation_execute_block" 'After Dev returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'qa-remediation-state\.sh.*advance'
check_literal_before_literal "vibe: QA verify breaker appears before known-issue sync" "$qa_remediation_verify_block" 'After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'track-known-issues.sh" sync-verification'
check_literal_before_literal "vibe: QA verify breaker appears before known-issue promotion" "$qa_remediation_verify_block" 'After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'track-known-issues.sh" promote-todos'
check_literal_before_literal "vibe: QA verify breaker appears before deterministic gate" "$qa_remediation_verify_block" 'After QA returns, apply the no-tool circuit breaker in `references/subagent-contracts.md`' 'qa-result-gate.sh'

if grep -q 'Determine verification scope from `VERIF_PATH`' "$QA_FILE"; then
  pass "qa: standalone QA scope is tied to resolved VERIF_PATH"
else
  fail "qa: standalone QA scope still appears disconnected from resolved VERIF_PATH"
fi

if grep -q 'Determine verification scope from `VERIF_PATH`' "$QA_FILE"; then
  pass "qa: standalone QA scope is tied to resolved VERIF_PATH"
else
  fail "qa: standalone QA scope still appears disconnected from resolved VERIF_PATH"
fi

if grep -q 'first_qa_attention_phase' "$QA_FILE" && grep -q 'qa_attention_status' "$QA_FILE"; then
  pass "qa: auto-detect retargets stale or failed authoritative QA artifacts"
else
  fail "qa: auto-detect missing stale/failed authoritative QA retargeting guidance"
fi

if grep -q 'compile-verify-context.sh --remediation-only' "$VIBE_FILE"; then
  pass "vibe: refreshes verify context before QA remediation handoff to Verify"
else
  fail "vibe: missing verify-context refresh for QA remediation handoff"
fi

echo ""
echo "=== Execute Team Routing Verification ==="

if grep -q 'True team mode' "$ROOT/references/execute-protocol.md" \
  && grep -q 'Explicit non-team mode' "$ROOT/references/execute-protocol.md" \
  && grep -q 'Team-tooling-unavailable fallback' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: defines true team, explicit non-team, and fallback branches"
else
  fail "execute-protocol: missing one or more execute team-routing branches"
fi

if grep -q 'Plain background `Agent` spawns without team semantics are NOT an agent team' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: forbids faux-team background Agent substitution"
else
  fail "execute-protocol: missing faux-team Agent prohibition"
fi

if grep -Eq 'Agent Teams not enabled.{1,3}using non-team mode' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: pins explicit non-team fallback warning text"
else
  fail "execute-protocol: missing explicit non-team fallback warning text"
fi

if grep -Fq 'resolve-execute-delegation-mode.sh' "$ROOT/references/execute-protocol.md" \
  && grep -Fq "prefer_teams='auto'" "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'max_parallel_width > 1' "$ROOT/references/execute-protocol.md" \
  && ! grep -Fq "prefer_teams='auto': request team mode only when 2+ uncompleted plans remain" "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "dev-{MM}"`' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol: dependency-aware routing uses consistent true-team metadata wording"
else
  fail "execute-protocol: dependency-aware routing wording is inconsistent or still references stale 2+ plan team creation"
fi

if grep -q 'scripts/delegated-workflow.sh" set execute' "$ROOT/references/execute-protocol.md" \
  && grep -q 'delegation_mode' "$ROOT/scripts/delegated-workflow.sh"; then
  pass "execute-protocol + delegated-workflow: runtime execute delegation mode is persisted"
else
  fail "execute-protocol + delegated-workflow: missing persisted execute delegation mode contract"
fi

if grep -q 'background `Agent` spawns that lack `team_name`' "$VIBE_FILE" \
  && grep -q 'fall back to explicit non-team execution' "$VIBE_FILE"; then
  pass "vibe: execute invariant forbids faux-team background Agent execution"
else
  fail "vibe: missing execute invariant for real-team vs explicit fallback"
fi

_vibe_gate_count=$(grep -c 'qa-result-gate\.sh' "$VIBE_FILE" 2>/dev/null || echo 0)
if [ "$_vibe_gate_count" -ge 2 ]; then
  pass "vibe: references qa-result-gate.sh at $_vibe_gate_count call sites"
else
  fail "vibe: expected >=2 qa-result-gate.sh references, found $_vibe_gate_count"
fi

_ep_gate_count=$(grep -c 'qa-result-gate\.sh' "$ROOT/references/execute-protocol.md" 2>/dev/null || echo 0)
if [ "$_ep_gate_count" -ge 2 ]; then
  pass "execute-protocol: references qa-result-gate.sh at $_ep_gate_count call sites"
else
  fail "execute-protocol: expected >=2 qa-result-gate.sh references, found $_ep_gate_count"
fi

for f in "$VIBE_FILE" "$ROOT/references/execute-protocol.md"; do
  if [ "$f" = "$VIBE_FILE" ]; then
    base="vibe.md"
  else
    base=$(basename "$f")
  fi
  _ar_count=$(grep -c 'no exceptions, no judgment, no rationalization' "$f" 2>/dev/null || echo 0)
  if [ "$_ar_count" -ge 2 ]; then
    pass "$base: has anti-rationalization instruction at $_ar_count call sites"
  else
    fail "$base: expected >=2 anti-rationalization instructions, found $_ar_count"
  fi
done

echo ""
