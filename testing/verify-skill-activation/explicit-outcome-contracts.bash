echo "=== 3-Layer Skill Activation Pipeline ==="

echo ""
echo "=== Explicit Skill Outcome Contract ==="

SKILL_PAYLOAD_TEMPLATE="$ROOT/references/skill-activation-payload.md"
if [ -f "$SKILL_PAYLOAD_TEMPLATE" ]; then
  pass "skill activation payload template exists"
else
  fail "skill activation payload template missing"
fi

if grep -q '^<skill_activation>$' "$SKILL_PAYLOAD_TEMPLATE" \
  && grep -q '^{skill_calls}$' "$SKILL_PAYLOAD_TEMPLATE" \
  && grep -q '^<skill_no_activation>$' "$SKILL_PAYLOAD_TEMPLATE" \
  && grep -q 'Reason: {no_skill_reason}\.' "$SKILL_PAYLOAD_TEMPLATE" \
  && grep -q '^{follow_up_files_block}$' "$SKILL_PAYLOAD_TEMPLATE"; then
  pass "skill activation payload template defines both render branches"
else
  fail "skill activation payload template missing selected or no-selected branch"
fi

input_count=$(grep -c '^- `' "$SKILL_PAYLOAD_TEMPLATE" || true)
follow_up_sentence_count=$(grep -c -F "$SKILL_FOLLOW_UP_PREFIX" "$SKILL_PAYLOAD_TEMPLATE" || true)
if [ "$input_count" -eq 3 ] && [ "$follow_up_sentence_count" -eq 2 ]; then
  pass "skill activation payload template limits inputs and shares follow-up prose"
else
  fail "skill activation payload template expected 3 inputs and 2 canonical follow-up sentences"
fi

render_site_count=0
for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  site_count=$(grep -c 'Render the prompt prefix from `' "$contract_file" || true)
  render_site_count=$((render_site_count + site_count))
  if grep -Eq '^[[:space:]]*<skill_(no_)?activation>$' "$contract_file"; then
    fail "$contract_name: still contains a duplicated literal payload block"
  else
    pass "$contract_name: literal payload pair removed"
  fi
  verify_skill_contract_sites "$contract_file"
done

if [ "$render_site_count" -eq 20 ]; then
  pass "all 20 child prompt sites render the canonical payload template"
else
  fail "expected 20 payload render sites, found $render_site_count"
fi

if grep -Fq '`${VBW_PLUGIN_ROOT}/references/skill-activation-payload.md`' "$ROOT/references/execute-protocol.md" \
  && grep -Fq 'rendered skill outcome tag is the first child-prompt line' "$ROOT/references/execute-protocol.md" \
  && ! grep -q '^@' "$ROOT/references/execute-protocol.md"; then
  pass "execute-protocol renders and prepends the payload without unresolved includes"
else
  fail "execute-protocol payload rendering can leak an unresolved include or lose first-line ordering"
fi

for agent_file in "${AGENT_SKILL_CONTRACT_FILES[@]}"; do
  agent_name=$(basename "$agent_file")
  if grep -q 'skill_no_activation' "$agent_file"; then
    pass "$agent_name: handles explicit no-activation outcome"
  else
    fail "$agent_name: missing explicit no-activation handling"
  fi
done

for contract_file in "${COMMAND_SKILL_CONTRACT_FILES[@]}"; do
  contract_name=$(basename "$contract_file")
  if grep -q 'omit the skill_activation block entirely\|omit the block entirely' "$contract_file"; then
    fail "$contract_name: still allows silent omission of skill outcome blocks"
  else
    pass "$contract_name: bans silent omission wording"
  fi
done

if ! grep -q 'Same as Add Phase step 5' "$ROOT/references/vibe-mode-insert-phase.md"; then
  pass "vibe-mode-insert-phase.md: Scout contract is local, not shorthand"
else
  fail "vibe-mode-insert-phase.md: Scout contract still relies on Add Phase shorthand"
fi

for agent_file in vbw-lead.md vbw-dev.md vbw-qa.md vbw-scout.md vbw-debugger.md vbw-architect.md vbw-docs.md; do
  AGENT_PATH="$ROOT/agents/$agent_file"
  if grep -q '## Skill Activation' "$AGENT_PATH"; then
    pass "$agent_file: has ## Skill Activation section"
  else
    fail "$agent_file: missing ## Skill Activation section"
  fi
done

echo ""
echo "=== MCP Tool Usage Section (disallowedTools agents) ==="
for agent_file in "$ROOT"/agents/vbw-*.md; do
  agent_name=$(basename "$agent_file")
  if grep -q '^disallowedTools:' "$agent_file"; then
    if grep -q '## MCP Tool Usage' "$agent_file"; then
      pass "$agent_name: has ## MCP Tool Usage section (uses disallowedTools denylist)"
    else
      fail "$agent_name: missing ## MCP Tool Usage section (uses disallowedTools but no MCP guidance)"
    fi
  fi
done

if [ ! -f "$ROOT/scripts/generate-skill-activation.sh" ]; then
  pass "generate-skill-activation.sh: deleted (replaced by intelligent orchestrator selection)"
else
  fail "generate-skill-activation.sh: still exists (should be deleted)"
fi

if ! grep -q 'generate-skill-activation.sh' "$COMPILER"; then
  pass "compile-context.sh: no longer calls generate-skill-activation.sh"
else
  fail "compile-context.sh: still calls generate-skill-activation.sh (should be removed)"
fi

if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section removed"
else
  fail "compile-context.sh: still has emit_skills_section (should be removed)"
fi

if ! grep -q 'Mandatory Skill Activation' "$COMPILER"; then
  pass "compile-context.sh: Mandatory Skill Activation section removed"
else
  fail "compile-context.sh: still has Mandatory Skill Activation (should be removed)"
fi

if ! grep -q 'skill-activation-block.txt' "$PROTOCOL"; then
  pass "execute-protocol.md: .skill-activation-block.txt references removed"
else
  fail "execute-protocol.md: still references .skill-activation-block.txt"
fi

if [ ! -f "$ROOT/scripts/emit-skill-prompt-line.sh" ]; then
  pass "emit-skill-prompt-line.sh: deleted (replaced by generate-skill-activation.sh)"
else
  fail "emit-skill-prompt-line.sh: still exists (should be deleted)"
fi

VIBE_CMD="$VIBE_COMMAND"
RESEARCH_CMD="$ROOT/commands/research.md"
if ! grep -q 'SKILL_PROMPT_LINE' "$PROTOCOL"; then
  pass "execute-protocol.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "execute-protocol.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$VIBE_CMD"; then
  pass "vibe.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "vibe.md: still references SKILL_PROMPT_LINE"
fi

if ! grep -q 'SKILL_PROMPT_LINE' "$RESEARCH_CMD"; then
  pass "research.md: no SKILL_PROMPT_LINE references (removed)"
else
  fail "research.md: still references SKILL_PROMPT_LINE"
fi

if grep -q 'evaluate installed skills' "$PROTOCOL"; then
  pass "execute-protocol.md: intelligent skill selection documented"
else
  fail "execute-protocol.md: missing intelligent skill selection documentation"
fi

if ! grep -q 'select skills from installed skills visible in your system context' "$PROTOCOL"; then
  pass "execute-protocol.md: old LLM-composed skill selection removed"
else
  fail "execute-protocol.md: still has old LLM-composed skill selection instruction"
fi

if ! grep -q 'SKILL_BLOCK' "$PROTOCOL"; then
  pass "execute-protocol.md: SKILL_BLOCK variable removed"
else
  fail "execute-protocol.md: SKILL_BLOCK still referenced (should be removed)"
fi

if ! grep -q 'generate-skill-activation.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: generate-skill-activation.sh references removed"
else
  fail "execute-protocol.md: still references generate-skill-activation.sh"
fi

if grep -q 'skill_activation' "$VIBE_CMD" && grep -q 'skill_no_activation' "$VIBE_CMD" && grep -q 'skill_activation' "$RESEARCH_CMD" && grep -q 'skill_no_activation' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: orchestrator-composed explicit positive and negative skill outcomes"
else
  fail "vibe.md or research.md: missing explicit positive or negative skill outcomes"
fi

if grep -q 'evaluate installed skills' "$VIBE_CMD"; then
  pass "vibe.md: uses intelligent skill evaluation language"
else
  fail "vibe.md: missing intelligent skill evaluation language"
fi

if ! grep -q 'Do not skip any listed skill' "$VIBE_CMD" && ! grep -q 'Do not skip any listed skill' "$RESEARCH_CMD"; then
  pass "vibe.md + research.md: 'Do not skip any listed skill' removed"
else
  fail "vibe.md or research.md: still has 'Do not skip any listed skill'"
fi

if ! grep -q 'Do NOT attempt to compose skill activation yourself' "$PROTOCOL"; then
  pass "execute-protocol.md: anti-LLM-composition directive removed (intelligent selection now)"
else
  fail "execute-protocol.md: anti-LLM-composition directive still present"
fi

if ! (grep -Ei 'skill_activation|Skill\(' "$PROTOCOL" "$VIBE_CMD" "$RESEARCH_CMD" | grep -qiE 'if you need|if relevant|clearly relevant'); then
  pass "skill activation prompts: no weak conditional phrasing in skill-instruction lines"
else
  fail "skill activation prompts: weak conditional phrasing present in skill-instruction lines"
fi

if ! grep -rq 'clearly relevant' "$ROOT/agents/"; then
  pass "agent prompts: no 'clearly relevant' conditional phrasing"
else
  fail "agent prompts: 'clearly relevant' still present,use direct imperative language"
fi

if ! grep -rq 'STATE.md.*Installed\|Installed.*STATE.md' "$ROOT/agents/"; then
  pass "agent prompts: no STATE.md Installed fallback (removed,skills surfaced via available_skills)"
else
  fail "agent prompts: STATE.md Installed fallback still present in agents"
fi

if ! grep -q '\.skill-names' "$ROOT/scripts/planning-git.sh"; then
  pass "planning-git.sh: no .skill-names in transient gitignore (removed)"
else
  fail "planning-git.sh: still has .skill-names in transient gitignore"
fi

if grep -q 'rm.*\.skill-names' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has brownfield .skill-names cleanup"
else
  fail "session-start.sh: missing brownfield .skill-names cleanup"
fi

if ! grep -q 'inject-subagent-skills.sh' "$HOOKS_FILE"; then
  pass "hooks.json: inject-subagent-skills.sh removed (Layer 3,native CC skill visibility)"
else
  fail "hooks.json: inject-subagent-skills.sh still present (should be removed)"
fi

COMPILER="$ROOT/scripts/compile-context.sh"
if ! grep -q 'emit_skills_section' "$COMPILER"; then
  pass "compile-context.sh: emit_skills_section fully removed (all roles)"
else
  fail "compile-context.sh: emit_skills_section still present"
fi

for _cmd_file in $_MAX_TURNS_COMMANDS; do
  _cmd_name=$(basename "$_cmd_file")
  if grep -q 'MAX_TURNS.*is 0' "$_cmd_file" || grep -q 'MAX_TURNS.*is a positive integer' "$_cmd_file"; then
    fail "$_cmd_name: uses old 'is 0'/'is a positive integer' phrasing (should use non-empty/empty)"
  else
    pass "$_cmd_name: uses non-empty/empty phrasing for maxTurns"
  fi
done
