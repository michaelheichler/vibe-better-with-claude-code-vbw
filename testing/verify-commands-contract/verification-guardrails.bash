echo "=== Phase-Detect Refresh Safety Verification ==="

EXECUTE_POST_BUILD_QA_REF="$ROOT/references/execute-post-build-qa.md"
EXECUTE_QA_GATE_REF="$ROOT/references/execute-qa-result-gating.md"
EXECUTE_UAT_REF="$ROOT/references/execute-uat.md"

for pd_safe_cmd in vibe verify resume status discuss qa; do
  pd_safe_file="$COMMANDS_DIR/${pd_safe_cmd}.md"
  if [ ! -f "$pd_safe_file" ]; then
    fail "$pd_safe_cmd: command file not found"
    continue
  fi

  if grep -Fq '_PD_CACHE="$PD"' "$pd_safe_file"; then
    fail "$pd_safe_cmd: stale phase-detect cache fallback still present"
  else
    pass "$pd_safe_cmd: no stale phase-detect cache fallback"
  fi

  if grep -Fq 'if [ -L "$L" ] && [ -f "$L/scripts/hook-wrapper.sh" ]; then R="$L"; fi' "$pd_safe_file"; then
    fail "$pd_safe_cmd: reuses session symlink as plugin-root candidate"
  else
    pass "$pd_safe_cmd: does not trust session symlink as plugin root"
  fi
done

echo ""
echo "=== Verify Guardrail Verification ==="

VIBE_SOURCE="$COMMANDS_DIR/vibe.md"
VIBE_FILE=$(mktemp)
trap 'rm -f "$VIBE_FILE"' EXIT
append_vibe_reference() {
  local reference="$1"
  if [ -f "$reference" ]; then
    cat "$reference"
  else
    fail "vibe: missing referenced file ${reference#"$ROOT/"}"
  fi
}
while IFS= read -r vibe_line || [ -n "$vibe_line" ]; do
  printf '%s\n' "$vibe_line"
  case "$vibe_line" in
    '@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md')
      append_vibe_reference "$ROOT/references/ask-user-question.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/subagent-contracts.md')
      append_vibe_reference "$ROOT/references/subagent-contracts.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-input-parsing.md')
      append_vibe_reference "$ROOT/references/vibe-input-parsing.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-uat-remediation.md')
      append_vibe_reference "$ROOT/references/vibe-uat-remediation.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-bootstrap.md')
      append_vibe_reference "$ROOT/references/vibe-mode-bootstrap.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-milestone-uat-recovery.md')
      append_vibe_reference "$ROOT/references/vibe-mode-milestone-uat-recovery.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-plan.md')
      append_vibe_reference "$ROOT/references/vibe-mode-plan.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-execute.md')
      append_vibe_reference "$ROOT/references/vibe-mode-execute.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-verify.md')
      append_vibe_reference "$ROOT/references/vibe-mode-verify.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-add-phase.md')
      append_vibe_reference "$ROOT/references/vibe-mode-add-phase.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-insert-phase.md')
      append_vibe_reference "$ROOT/references/vibe-mode-insert-phase.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-remove-phase.md')
      append_vibe_reference "$ROOT/references/vibe-mode-remove-phase.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vibe-mode-archive.md')
      append_vibe_reference "$ROOT/references/vibe-mode-archive.md"
      ;;
    '@${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md')
      append_vibe_reference "$ROOT/references/vbw-brand-essentials.md"
      ;;
  esac
done < "$VIBE_SOURCE" > "$VIBE_FILE"
for lazy_vibe_pointer in \
  'Read `{LINK}/references/vibe-uat-remediation.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-bootstrap.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-milestone-uat-recovery.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-plan.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-execute.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-verify.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-add-phase.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-insert-phase.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-remove-phase.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Read `{LINK}/references/vibe-mode-archive.md` and follow it. `{LINK}` is the first line of the Context block output.' \
  'Before handling a team shutdown, Read `{LINK}/references/subagent-contracts.md` and follow its contract. `{LINK}` is the first line of the Context block output.' \
  'Before rendering output, read `{LINK}/references/vbw-brand-essentials.md` and follow it. `{LINK}` is the first line of the Context block output. Skip this read for Verify mode because UAT files use plain markdown.'; do
  if grep -Fqx "$lazy_vibe_pointer" "$VIBE_SOURCE"; then
    pass "vibe: routes lazy reference ${lazy_vibe_pointer#*references/}"
  else
    fail "vibe: missing lazy reference route ${lazy_vibe_pointer#*references/}"
  fi
done
for lazy_vibe_reference in \
  "$ROOT/references/vibe-uat-remediation.md" \
  "$ROOT/references/vibe-mode-bootstrap.md" \
  "$ROOT/references/vibe-mode-milestone-uat-recovery.md" \
  "$ROOT/references/vibe-mode-plan.md" \
  "$ROOT/references/vibe-mode-execute.md" \
  "$ROOT/references/vibe-mode-verify.md" \
  "$ROOT/references/vibe-mode-add-phase.md" \
  "$ROOT/references/vibe-mode-insert-phase.md" \
  "$ROOT/references/vibe-mode-remove-phase.md" \
  "$ROOT/references/vibe-mode-archive.md" \
  "$ROOT/references/subagent-contracts.md" \
  "$ROOT/references/vbw-brand-essentials.md"; do
  append_vibe_reference "$lazy_vibe_reference" >> "$VIBE_FILE"
done
QA_FILE="$COMMANDS_DIR/qa.md"
VERIFY_FILE="$COMMANDS_DIR/verify.md"

if grep -q 'Verify-context error guard (NON-NEGOTIABLE)' "$VERIFY_FILE"; then
  pass "verify: has fail-closed verify-context error guard"
else
  fail "verify: missing fail-closed verify-context error guard"
fi

if grep -q 'If the user specified an explicit phase number that differs from the auto-detected target, ignore the pre-computed `qa_status`' "$VERIFY_FILE"; then
  pass "verify: explicit target phases ignore auto-detected qa_status"
else
  fail "verify: missing explicit-phase qa_status override guidance"
fi

if grep -q 'Only proceed to UAT when the PASS is both gate-authoritative and fresh for the target phase' "$VERIFY_FILE"; then
  pass "verify: explicit QA gate requires gate-authoritative fresh PASS for target phase"
else
  fail "verify: missing gate-authoritative fresh-PASS requirement in explicit QA gate"
fi

if grep -q 'qa-result-gate\.sh' "$VERIFY_FILE" \
  && grep -q 'QA_GATE_ROUTING=' "$VERIFY_FILE" \
  && grep -q 'PROCEED_TO_UAT' "$VERIFY_FILE" \
  && grep -q 'QA_RERUN_REQUIRED' "$VERIFY_FILE" \
  && grep -q 'REMEDIATION_REQUIRED' "$VERIFY_FILE"; then
  pass "verify: standalone UAT honors deterministic QA gate before UAT"
else
  fail "verify: missing deterministic qa-result-gate enforcement before UAT"
fi

if grep -q 'KNOWN_ISSUES_STATUS=' "$VERIFY_FILE" \
  && grep -q 'KNOWN_ISSUES_STATUS=malformed' "$VERIFY_FILE" \
  && grep -q 'unreadable tracked known issues' "$VERIFY_FILE" \
  && grep -q 'unresolved tracked known issues' "$VERIFY_FILE"; then
  pass "verify: skip-qa guard blocks malformed known-issues registries"
else
  fail "verify: missing malformed known-issues fail-closed guard in skip-qa path"
fi

if grep -q 'sync-verification "\$PDIR" "\$VERIF_FILE"' "$VERIFY_FILE"; then
  pass "verify: restores known-issues registry from existing verification artifacts before gating"
else
  fail "verify: missing known-issues restore from existing verification artifact"
fi

if grep -q 'sync-verification "\$PDIR" "\$VERIF_FILE"' "$VERIFY_FILE" \
  && grep -q 'promote-todos "\$PDIR"' "$VERIFY_FILE"; then
  pass "verify: restore path re-promotes known issues into STATE.md todos after sync-verification"
else
  fail "verify: missing promote-todos after known-issues restore in verify recovery path"
fi

if grep -Fq 'Track Todo' "$VERIFY_FILE" \
  && grep -Fq 'track-uat-deviations.sh" todo-from-uat' "$VERIFY_FILE" \
  && grep -Fq 'accepted deviation added to todos (ref:{TODO_REF})' "$VERIFY_FILE" \
  && grep -Fq 'Never invent a todo ref' "$VERIFY_FILE"; then
  pass "verify: summary-deviation Track Todo path uses deterministic helper output"
else
  fail "verify: summary-deviation Track Todo path missing deterministic helper/ref contract"
fi

if grep -Fq 'Track Todo' "$EXECUTE_UAT_REF" \
  && grep -Fq 'track-uat-deviations.sh" todo-from-uat' "$EXECUTE_UAT_REF" \
  && grep -Fq 'accepted deviation added to todos (ref:{todo_ref})' "$EXECUTE_UAT_REF"; then
  pass "execute-protocol: summary-deviation Track Todo path mirrors helper output contract"
else
  fail "execute-protocol: summary-deviation Track Todo path missing helper output contract"
fi

if grep -Fq "can't\`/\`cant\` → \`cannot" "$VERIFY_FILE" \
  && grep -Fq 'curly apostrophes as straight apostrophes' "$VERIFY_FILE" \
  && grep -Fq "can’t" "$VERIFY_FILE" \
  && grep -Fq 'marker-first ordering' "$VERIFY_FILE" \
  && grep -Fq 'not ok' "$VERIFY_FILE" \
  && grep -Fq 'cannot accept' "$VERIFY_FILE" \
  && grep -Fq 'do not accept' "$VERIFY_FILE" \
  && grep -Fq 'will not accept' "$VERIFY_FILE" \
  && grep -Fq 'unable to accept' "$VERIFY_FILE" \
  && grep -Fq 'refuse to accept' "$VERIFY_FILE" \
  && grep -Fq 'not acceptable' "$VERIFY_FILE" \
  && grep -Fq "can't continue, track this" "$VERIFY_FILE" \
  && grep -Fq 'not ok, track this' "$VERIFY_FILE" \
  && grep -Fq "can't accept this, track this" "$VERIFY_FILE" \
  && grep -Fq 'not acceptable, add to todo' "$VERIFY_FILE" \
  && grep -Fq 'rejected-by-user' "$VERIFY_FILE"; then
  pass "verify: summary-deviation todo intent handles contraction blockers before tracking"
else
  fail "verify: summary-deviation todo intent missing contraction blocker guard"
fi

if grep -Fq "can't\`/\`cant\` → \`cannot" "$EXECUTE_UAT_REF" \
  && grep -Fq 'curly apostrophes as straight apostrophes' "$EXECUTE_UAT_REF" \
  && grep -Fq "can’t continue, track this" "$EXECUTE_UAT_REF" \
  && grep -Fq 'marker-first ordering' "$EXECUTE_UAT_REF" \
  && grep -Fq 'not ok' "$EXECUTE_UAT_REF" \
  && grep -Fq 'cannot accept' "$EXECUTE_UAT_REF" \
  && grep -Fq 'do not accept' "$EXECUTE_UAT_REF" \
  && grep -Fq 'will not accept' "$EXECUTE_UAT_REF" \
  && grep -Fq 'unable to accept' "$EXECUTE_UAT_REF" \
  && grep -Fq 'refuse to accept' "$EXECUTE_UAT_REF" \
  && grep -Fq 'not acceptable' "$EXECUTE_UAT_REF" \
  && grep -Fq "can't continue, track this" "$EXECUTE_UAT_REF" \
  && grep -Fq 'not ok, track this' "$EXECUTE_UAT_REF" \
  && grep -Fq "can't accept this, track this" "$EXECUTE_UAT_REF" \
  && grep -Fq 'not acceptable, add to todo' "$EXECUTE_UAT_REF" \
  && grep -Fq 'rejected-by-user' "$EXECUTE_UAT_REF"; then
  pass "execute-protocol: summary-deviation todo intent handles contraction blockers before tracking"
else
  fail "execute-protocol: summary-deviation todo intent missing contraction blocker guard"
fi

if grep -Eq 'qa-remediation-state\.sh"? advance' "$QA_FILE"; then
  pass "qa: round-scoped PROCEED_TO_UAT persists remediation advance"
else
  fail "qa: missing round-scoped qa-remediation-state advance before standalone QA success presentation"
fi

if grep -Eq 'qa-remediation-state\.sh"? needs-round' "$QA_FILE"; then
  pass "qa: round-scoped REMEDIATION_REQUIRED persists next-round state"
else
  fail "qa: missing round-scoped qa-remediation-state needs-round before standalone remediation handoff"
fi

if grep -q 'echo "verify_context=unavailable"' "$VIBE_FILE"; then
  pass "vibe: routed verify precompute emits fail-closed verify_context sentinel"
else
  fail "vibe: routed verify precompute missing fail-closed verify_context sentinel"
fi

if grep -q 'qa-remediation-state\.sh get-or-init {phase-dir}' "$VIBE_FILE" \
  && grep -q 'deterministic stage-less resume path' "$VIBE_FILE"; then
  pass "vibe: QA remediation resume self-initializes absent state"
else
  fail "vibe: missing qa-remediation-state get-or-init for stage-less QA remediation resume"
fi

if grep -q 'qa_reason' "$VIBE_FILE" \
  && grep -q 'qa_attention_reason' "$VIBE_FILE" \
  && grep -q 'missing_verification_artifact' "$VIBE_FILE" \
  && grep -q 'verified_at_commit_mismatch' "$VIBE_FILE" \
  && grep -q 'qa_gate_rerun_required' "$VIBE_FILE"; then
  pass "vibe: QA pending gate surfaces machine-readable phase-detect reasons"
else
  fail "vibe: QA pending gate missing machine-readable reason guidance"
fi

if grep -Fq 'QA is pending ({qa_reason})' "$VIBE_FILE"; then
  fail "vibe: QA pending table still displays raw qa_reason token"
else
  pass "vibe: QA pending table avoids raw qa_reason display token"
fi

if grep -Fq 'QA is pending ({reason label})' "$VIBE_FILE" \
  && grep -Fq 'Resolve `{reason label}` from `qa_reason`' "$VIBE_FILE"; then
  pass "vibe: QA pending table points to resolved reason-label mapping"
else
  fail "vibe: QA pending table missing resolved reason-label guidance"
fi

if grep -Fq -- 'qa_reason=none|<reason>' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'qa_attention_reason=none|<reason>' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'result:` is authoritative when present' "$ROOT/references/phase-detection.md" \
  && grep -Fq -- 'Legacy `status:` is accepted only when `result:` is absent' "$ROOT/references/phase-detection.md"; then
  pass "phase-detection: documents QA reason fields and legacy result precedence"
else
  fail "phase-detection: missing QA reason or legacy result documentation"
fi

if grep -q 'Read the active UAT artifact exactly once' "$VIBE_FILE" \
  && grep -q 'Do NOT shell out to `extract-uat-issues.sh` for active-phase routing' "$VIBE_FILE" \
  && grep -q 'Use `uat_file` from the pre-computed state when available' "$VIBE_FILE"; then
  pass "vibe: active UAT remediation reads the active UAT artifact directly from routing metadata"
else
  fail "vibe: active UAT remediation missing direct-read routing guidance"
fi

if grep -q 'UAT issues (remediation only):' "$VIBE_FILE" || grep -q '^---UAT_EXTRACT_START---$' "$VIBE_FILE"; then
  fail "vibe: active UAT remediation still includes the precomputed extraction block"
else
  pass "vibe: active UAT remediation no longer embeds an active extraction marker block"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VERIFY_FILE"; then
  pass "verify: precomputed UAT context uses shared scope resolver"
else
  fail "verify: precomputed UAT context missing shared scope resolver"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VIBE_FILE"; then
  pass "vibe: precomputed UAT context uses shared scope resolver"
else
  fail "vibe: precomputed UAT context missing shared scope resolver"
fi

if grep -q 'extract-uat-resume\.sh "{phase-dir}"' "$VIBE_FILE" \
  && grep -q 'remediation/uat/round-{RR}/R{RR}-UAT.md' "$VIBE_FILE" \
  && grep -q 'remediation/round-{RR}/R{RR}-UAT.md' "$VIBE_FILE"; then
  pass "vibe: needs_reverification refreshes and validates round-scoped uat_path for round-dir and legacy layouts"
else
  fail "vibe: needs_reverification missing refreshed round-scoped uat_path validation"
fi

if grep -q 'uat_resume_scenario' "$VIBE_FILE" \
  && grep -q 'uat_resume_expected' "$VIBE_FILE" \
  && grep -q 'bash "$L/scripts/extract-uat-resume.sh" "$PDIR" 2>/dev/null || echo "uat_resume=error"' "$VIBE_FILE" \
  && grep -q 'echo "uat_resume=unavailable"' "$VIBE_FILE"; then
  pass "vibe: Verify mode passes deterministic UAT resume fields and preserves wrapper sentinels"
else
  fail "vibe: Verify mode missing deterministic UAT resume fields or wrapper sentinels"
fi

if grep -q 'compile-verify-context.sh --remediation-only {phase-dir}' "$EXECUTE_QA_GATE_REF"; then
  pass "execute-protocol: QA remediation verify uses remediation-only verify context"
else
  fail "execute-protocol: QA remediation verify missing remediation-only verify context"
fi

if grep -q 'verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL' "$EXECUTE_QA_GATE_REF" \
  && grep -q 'documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment' "$EXECUTE_QA_GATE_REF"; then
  pass "execute-protocol: remediation QA rejects unjustified process-exception labels"
else
  fail "execute-protocol: remediation QA guidance still allows documentation-only process-exception loophole"
fi

if grep -q 'After QA persists VERIFICATION.md (and only after that), run the verification threshold gate' "$EXECUTE_POST_BUILD_QA_REF"; then
  pass "execute-protocol: verification_threshold runs after QA persists VERIFICATION"
else
  fail "execute-protocol: verification_threshold ordering still appears before QA"
fi

if grep -q 'compile-verify-context.sh --remediation-only {phase-dir}' "$VIBE_FILE"; then
  pass "vibe: QA remediation verify uses remediation-only verify context"
else
  fail "vibe: QA remediation verify missing remediation-only verify context"
fi

if grep -q 'verify the exception is documented with non-fixable justification and that the justification is credible for this FAIL' "$VIBE_FILE" \
  && grep -q 'documentation alone is insufficient when the original FAIL still appears fixable via code or plan amendment' "$VIBE_FILE"; then
  pass "vibe: remediation QA rejects unjustified process-exception labels"
else
  fail "vibe: remediation QA guidance still allows documentation-only process-exception loophole"
fi

if grep -q 'compile-verify-context-for-uat\.sh' "$VERIFY_FILE"; then
  pass "verify: misnamed-plan refresh recomputes UAT scope through shared resolver"
else
  fail "verify: misnamed-plan refresh missing shared UAT scope resolver"
fi

if grep -Eq 'uat-remediation-state\.sh"? get-or-init "{phase-dir}" major' "$VERIFY_FILE" \
  && grep -q 'remediation/uat/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -q 'remediation/round-{RR}/R{RR}-UAT.md' "$VERIFY_FILE" \
  && grep -Eq 'extract-uat-resume\.sh"? "{phase-dir}"' "$VERIFY_FILE"; then
  pass "verify: remediation re-verification refreshes and validates round-scoped uat_path for round-dir and legacy layouts"
else
  fail "verify: remediation re-verification missing refreshed round-scoped uat_path validation"
fi

if grep -q 'uat_resume_scenario' "$VERIFY_FILE" \
  && grep -q 'uat_resume_expected' "$VERIFY_FILE" \
  && grep -q 'summary-deviation checkpoints use `uat_resume_deviation`' "$VERIFY_FILE" \
  && grep -q 're-run `bash "{plugin-root}/scripts/extract-uat-resume.sh" "{phase-dir}"`' "$VERIFY_FILE"; then
  pass "verify: resumed UAT uses deterministic checkpoint fields and refreshes after each answer"
else
  fail "verify: resumed UAT missing deterministic checkpoint field usage or refresh loop"
fi

if grep -q 'ignore the pre-computed verify context, `next_phase_state`, `qa_status`, and UAT resume metadata' "$VERIFY_FILE" \
  && grep -q 'Do NOT force full scope' "$VERIFY_FILE" \
  && grep -q 'Use UAT resume metadata for the active target phase' "$VERIFY_FILE" \
  && grep -q 'uat-remediation-state\.sh" get "{phase-dir}"' "$VERIFY_FILE"; then
  pass "verify: explicit target phase uses target-specific verify state and blocks mid-remediation UAT"
else
  fail "verify: explicit target phase still depends on auto-detected state or allows mid-remediation UAT"
fi

if grep -q '_uat_state_file=.*remediation/uat/\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_legacy_remed_file=.*remediation/\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_legacy_file=.*\.uat-remediation-stage' "$VERIFY_FILE" \
  && grep -q '_uat_state_exists' "$VERIFY_FILE"; then
  pass "verify: remediation lifecycle advance has state-existence guard for new-format and both legacy locations"
else
  fail "verify: remediation lifecycle advance missing state-existence guard before needs-round"
fi

echo ""
