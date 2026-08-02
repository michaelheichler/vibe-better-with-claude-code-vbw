echo "=== Additive Agent Skill Model ==="

for agent_file in vbw-dev.md vbw-qa.md vbw-docs.md vbw-lead.md vbw-scout.md vbw-architect.md vbw-debugger.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"

  if grep -q 'starting set, not a ceiling' "$AGENT_PATH"; then
    pass "$agent_file: treats orchestrator selection as a starting set"
  else
    fail "$agent_file: missing starting-set additive wording"
  fi

  if grep -q 'bounded completeness pass' "$AGENT_PATH"; then
    pass "$agent_file: includes bounded completeness pass"
  else
    fail "$agent_file: missing bounded completeness pass"
  fi

  if grep -q 'no skills were preselected for this spawned task' "$AGENT_PATH"; then
    pass "$agent_file: no-activation block is treated as no initial preselection"
  else
    fail "$agent_file: no-activation path still reads like a hard ban"
  fi

  if grep -Eq 'Do not additionally scan `<available_skills>`|Do not scan `<available_skills>`|do not rescan `<available_skills>`' "$AGENT_PATH"; then
    fail "$agent_file: still contains old no-rescan ceiling wording"
  else
    pass "$agent_file: old no-rescan ceiling wording removed"
  fi
done

echo ""
echo "=== Adjacent Skill Example Coverage ==="

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -qi 'swiftdata' "$contract_file"; then
    pass "$contract_name: includes adjacent-skill example"
  else
    fail "$contract_name: missing adjacent-skill example"
  fi
done

README_FILE="$ROOT/README.md"
if grep -q 'Additive runtime activation' "$README_FILE" \
  && grep -q 'visible `Skills:` line' "$README_FILE"; then
  pass "README.md: documents additive spawned-agent skill activation"
else
  fail "README.md: missing additive spawned-agent skill activation note"
fi


if ! grep -q 'emit-skill-xml.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: emit-skill-xml.sh references removed"
else
  fail "execute-protocol.md: still references emit-skill-xml.sh (should be removed)"
fi

if grep -q 'available_skills' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills awareness"
else
  fail "execute-protocol.md: missing skills awareness reference"
fi




_AGENT_START="$ROOT/scripts/agent-start.sh"

_ROLES_AGENT_START=$(sed -n '/normalize_agent_role/,/^}/p' "$_AGENT_START" | grep "printf '" | sed "s/.*printf '\\([^']*\\)'.*/\\1/" | sort)

for _role in architect debugger dev docs lead qa scout; do
  if grep -q "^${_role}$" <<< "$_ROLES_AGENT_START"; then
    pass "agent-start.sh: normalize handles '$_role' role"
  else
    fail "agent-start.sh: normalize missing '$_role' role"
  fi
done


_MAX_TURNS_COMMANDS=$(grep -l 'maxTurns.*\${' "${TRACKED_COMMAND_REFERENCE_FILES[@]}" 2>/dev/null || true)
_MT_FAIL=0
for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'omit\|do NOT include maxTurns' "$_cmd_file"; then
    pass "$_cmd_name: maxTurns has conditional omission logic"
  else
    fail "$_cmd_name: maxTurns passed unconditionally (missing zero check)"
    _MT_FAIL=1
  fi
done
if [ -z "$_MAX_TURNS_COMMANDS" ]; then
  pass "maxTurns: no commands reference maxTurns (nothing to check)"
fi


echo ""
