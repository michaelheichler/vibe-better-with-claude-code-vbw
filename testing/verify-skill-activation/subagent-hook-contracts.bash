
echo ""
echo "=== Subagent Type Verification ==="

_SAT_TOTAL=$(grep -h 'subagent_type.*vbw:' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" 2>/dev/null | wc -l | tr -d ' ')

if [ "$_SAT_TOTAL" -ge 16 ]; then
  pass "subagent_type: ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
else
  fail "subagent_type: only ${_SAT_TOTAL} spawn points specify subagent_type (>= 16 expected)"
fi

for _role_check in "vbw-scout:references/vibe-mode-bootstrap.md" "vbw-scout:commands/research.md" "vbw-scout:commands/map.md" "vbw-dev:commands/fix.md" "vbw-dev:references/execute-protocol.md" "vbw-debugger:commands/debug.md" "vbw-qa:commands/qa.md" "vbw-qa:references/execute-post-build-qa.md" "vbw-lead:references/vibe-mode-plan.md"; do
  _sat_role="${_role_check%%:*}"
  _sat_file="${_role_check#*:}"
  if grep -q "subagent_type.*${_sat_role}" "$ROOT/$_sat_file"; then
    pass "$_sat_file: specifies subagent_type for $_sat_role"
  else
    fail "$_sat_file: missing subagent_type for $_sat_role"
  fi
done

echo ""
echo "=== Skill Decision Logging Hook ==="

HOOKS_JSON="$ROOT/hooks/hooks.json"

if jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Agent|TaskCreate")
  | .hooks[]
  | select(.command | contains("skill-decision-logger.sh"))
  | select(.timeout == 3)
' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json: skill-decision-logger.sh wired under PreToolUse Agent|TaskCreate (timeout=3)"
else
  fail "hooks.json: skill-decision-logger.sh not correctly wired (expected PreToolUse → Agent|TaskCreate → timeout=3)"
fi

if jq -e '
  .hooks.PreToolUse[]
  | select(.matcher == "Skill")
  | .hooks[]
  | select(.command | contains("skill-decision-logger.sh"))
  | select(.timeout == 3)
' "$HOOKS_JSON" >/dev/null 2>&1; then
  pass "hooks.json: skill-decision-logger.sh wired under PreToolUse Skill (timeout=3)"
else
  fail "hooks.json: skill-decision-logger.sh missing runtime Skill hook wiring"
fi

if [ -f "$ROOT/scripts/skill-decision-logger.sh" ]; then
  pass "scripts/skill-decision-logger.sh: exists"
else
  fail "scripts/skill-decision-logger.sh: missing"
fi

if [ -f "$ROOT/scripts/extract-skill-follow-up-files.sh" ]; then
  pass "scripts/extract-skill-follow-up-files.sh: exists"
else
  fail "scripts/extract-skill-follow-up-files.sh: missing"
fi

if grep -q '\.claude/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh" \
  && grep -q 'CLAUDE_DIR/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh"; then
  pass "scripts/extract-skill-follow-up-files.sh: covers project-local and global Claude skill roots"
else
  fail "scripts/extract-skill-follow-up-files.sh: missing project-local or global Claude skill roots"
fi

if grep -q '\.agents/skills\|\.pi/skills\|\$HOME/.agents/skills' "$ROOT/scripts/extract-skill-follow-up-files.sh"; then
  fail "scripts/extract-skill-follow-up-files.sh: still references non-Claude lookalike skill roots"
else
  pass "scripts/extract-skill-follow-up-files.sh: rejects non-Claude lookalike skill roots"
fi

verify_runtime_skill_root_guard

if [ -x "$ROOT/scripts/skill-decision-logger.sh" ]; then
  pass "scripts/skill-decision-logger.sh: is executable"
else
  fail "scripts/skill-decision-logger.sh: not executable"
fi

if grep -q 'exit 0' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: exits 0 (fail-open)"
else
  fail "scripts/skill-decision-logger.sh: missing exit 0 (must be fail-open)"
fi

if grep -q '\.tool_name // ""' "$ROOT/scripts/skill-decision-logger.sh" \
  && grep -q '\.tool_input.skill' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: parses runtime Skill tool payloads"
else
  fail "scripts/skill-decision-logger.sh: missing runtime Skill payload parsing"
fi

if grep -q 'runtime_skill' "$ROOT/scripts/skill-decision-logger.sh" \
  && grep -q 'orchestrator_preselection' "$ROOT/scripts/skill-decision-logger.sh"; then
  pass "scripts/skill-decision-logger.sh: distinguishes orchestrator vs runtime entries"
else
  fail "scripts/skill-decision-logger.sh: missing orchestrator/runtime discriminator"
fi

if grep -q 'malformed skill_activation block exits 0 and writes no log' "$ROOT/tests/skill-decision-logger.bats" \
  && grep -q 'malformed skill_no_activation block exits 0 and writes no log' "$ROOT/tests/skill-decision-logger.bats"; then
  pass "tests/skill-decision-logger.bats: covers malformed prompt-block fail-open behavior"
else
  fail "tests/skill-decision-logger.bats: missing malformed prompt-block fail-open coverage"
fi

DEBUG_CMD="$ROOT/commands/debug.md"

if grep -Eq 'Pass 1:|\*\*Pass 1:\*\*' "$DEBUG_CMD" \
  && grep -Eq 'Pass 2:|\*\*Pass 2:\*\*' "$DEBUG_CMD"; then
  pass "debug.md: defines explicit two-pass skill-selection rubric"
else
  fail "debug.md: missing explicit two-pass skill-selection rubric"
fi

if grep -q 'bounded sparse-context enrichment' "$DEBUG_CMD" \
  && grep -Eq '1-3 likely files' "$DEBUG_CMD"; then
  pass "debug.md: documents bounded sparse-context enrichment"
else
  fail "debug.md: missing bounded sparse-context enrichment contract"
fi

if grep -q 'Treat `DETAIL_STATUS=ok` as “lookup succeeded,” not automatically as “detail is useful.”' "$DEBUG_CMD" \
  && grep -q 'non-empty `detail.context` or at least one related file' "$DEBUG_CMD"; then
  pass "debug.md: empty detail does not suppress enrichment"
else
  fail "debug.md: missing empty-detail enrichment guard"
fi

if grep -q 'ModelContext' "$DEBUG_CMD" \
  && grep -q 'VersionedSchema' "$DEBUG_CMD" \
  && grep -q 'core-data' "$DEBUG_CMD"; then
  pass "debug.md: includes explicit SwiftData positive cues and Core Data negative cue"
else
  fail "debug.md: missing SwiftData positive cues or Core Data negative cue"
fi

if grep -q 'concrete working files or framework markers' "$DEBUGGER_AGENT" \
  && grep -q 'activate `swiftdata` right away' "$DEBUGGER_AGENT"; then
  pass "vbw-debugger.md: adds immediate early-evidence fallback rule"
else
  fail "vbw-debugger.md: missing immediate early-evidence fallback rule"
fi

if grep -q 'bounded sparse-input enrichment' "$PROTOCOL" \
  && grep -q 'core-data' "$PROTOCOL"; then
  pass "execute-protocol.md: mirrors sparse-input enrichment and persistence-skill guardrails"
else
  fail "execute-protocol.md: missing mirrored sparse-input enrichment guardrails"
fi

echo ""
echo "=== Skill Follow-Up Read Nudge ==="

if grep -qi 'do not scan entire skill folders or read unrelated references' "$PROTOCOL"; then
  pass "execute-protocol.md: has skill follow-up read nudge"
else
  fail "execute-protocol.md: missing skill follow-up read nudge"
fi

_EP_NUDGE_COUNT=$(grep -c 'scan entire skill folders or read unrelated references\|not entire skill folders or unrelated references' "$PROTOCOL")
if [ "$_EP_NUDGE_COUNT" -ge 2 ]; then
  pass "execute-protocol.md: follow-up read nudge in both loci ($_EP_NUDGE_COUNT sites)"
else
  fail "execute-protocol.md: follow-up read nudge in only $_EP_NUDGE_COUNT locus (expected 2)"
fi

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -qi 'do not scan entire skill folders or read unrelated references' "$contract_file"; then
    pass "$contract_name: has skill follow-up read nudge"
  else
    fail "$contract_name: missing skill follow-up read nudge"
  fi
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -qi 'do not scan entire skill folders or read unrelated references' "$agent_file"; then
    pass "$agent_name: has skill follow-up read nudge (top-level)"
  else
    fail "$agent_name: missing skill follow-up read nudge (top-level)"
  fi
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q '<skill_follow_up_files>' "$agent_file"; then
    pass "$agent_name: understands payload-local resolved follow-up file block"
  else
    fail "$agent_name: missing payload-local resolved follow-up file block guidance"
  fi
done

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  required_count=2
  [ "$agent_name" = "vbw-architect.md" ] && required_count=1
  if [ "$(grep -F "$SKILL_FOLLOW_UP_PREFIX" "$agent_file" | grep -Fi "$SKILL_FOLLOW_UP_SUFFIX" | grep -Ec "$SKILL_FOLLOW_UP_SEPARATOR_RE")" -ge "$required_count" ]; then
    pass "$agent_name: has runtime-local follow-up read nudge"
  else
    fail "$agent_name: missing runtime-local follow-up read nudge"
  fi
done

_DEBUG_NUDGE_COUNT=$(grep -ci 'do not scan entire skill folders or read unrelated references' "$DEBUG_CMD")
if [ "$_DEBUG_NUDGE_COUNT" -ge 3 ]; then
  pass "debug.md: follow-up read nudge present across the 3 debug skill sites (raw occurrences: $_DEBUG_NUDGE_COUNT)"
else
  fail "debug.md: follow-up read nudge appears in only $_DEBUG_NUDGE_COUNT raw loci (expected at least 3)"
fi

if awk '/^## File Writing/{found=1; next} found && /^## /{exit} found' "$SCOUT_AGENT" \
  | grep -F "$SKILL_FOLLOW_UP_PREFIX" \
  | grep -Fi "$SKILL_FOLLOW_UP_SUFFIX" \
  | grep -Eq "$SKILL_FOLLOW_UP_SEPARATOR_RE"; then
  pass "vbw-scout.md: has runtime-local follow-up read nudge near File Writing"
else
  fail "vbw-scout.md: missing runtime-local follow-up read nudge near File Writing"
fi

echo ""
