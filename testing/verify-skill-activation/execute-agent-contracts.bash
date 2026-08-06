
PROTOCOL="$ROOT/references/execute-protocol.md"
DEFAULTS="$ROOT/templates/agent-roles/defaults.json"

if grep -q 'plan-driven' "$PROTOCOL"; then
  pass "execute-protocol.md: documents plan-driven architecture"
else
  fail "execute-protocol.md: missing plan-driven documentation"
fi

if grep -q 'skills_used' "$PROTOCOL"; then
  pass "execute-protocol.md: references skills_used frontmatter"
else
  fail "execute-protocol.md: missing skills_used reference"
fi

if grep -q 'skill-hook-dispatch.sh' "$PROTOCOL"; then
  pass "execute-protocol.md: documents runtime skill hooks (separate concern)"
else
  fail "execute-protocol.md: missing skill-hook-dispatch.sh documentation"
fi

if grep -q 'skill_no_activation' "$PROTOCOL"; then
  pass "execute-protocol.md: documents explicit no-activation outcome"
else
  fail "execute-protocol.md: missing explicit no-activation outcome"
fi

if ! grep -q 'No written YES/NO evaluation required' "$PROTOCOL"; then
  pass "execute-protocol.md: legacy silent-decision wording removed"
else
  fail "execute-protocol.md: still says no written YES/NO evaluation is required"
fi

if ! grep -q 'three-layer' "$PROTOCOL"; then
  pass "execute-protocol.md: old three-layer documentation removed"
else
  fail "execute-protocol.md: still has three-layer documentation"
fi

if grep -q 'states the skill evaluation outcome' "$PROTOCOL"; then
  pass "execute-protocol.md: documents visible skill reporting contract"
else
  fail "execute-protocol.md: missing visible skill reporting documentation"
fi


QA_AGENT="$ROOT/templates/agent-roles/qa.md.tpl"

if grep -q 'skills_used' "$QA_AGENT"; then
  pass "templates/agent-roles/qa.md.tpl: references skills_used for plan-driven activation"
else
  fail "templates/agent-roles/qa.md.tpl: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$QA_AGENT"; then
  pass "templates/agent-roles/qa.md.tpl: references Skill() activation"
else
  fail "templates/agent-roles/qa.md.tpl: missing Skill() reference"
fi

if grep -q 'skill_no_activation' "$QA_AGENT"; then
  pass "templates/agent-roles/qa.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/qa.md.tpl: missing explicit no-activation handling"
fi

if grep -q 'available_skills' "$QA_AGENT"; then
  pass "templates/agent-roles/qa.md.tpl: references available_skills for ad-hoc fallback"
else
  fail "templates/agent-roles/qa.md.tpl: missing available_skills reference for ad-hoc fallback"
fi

SCOUT_AGENT="$ROOT/templates/agent-roles/scout.md.tpl"

if grep -q 'skills_used' "$SCOUT_AGENT"; then
  pass "templates/agent-roles/scout.md.tpl: references skills_used for plan-driven path"
else
  fail "templates/agent-roles/scout.md.tpl: missing skills_used reference"
fi

if grep -q 'available_skills' "$SCOUT_AGENT"; then
  pass "templates/agent-roles/scout.md.tpl: references available_skills for ad-hoc path"
else
  fail "templates/agent-roles/scout.md.tpl: missing available_skills reference for ad-hoc path"
fi

if grep -q 'skill_no_activation' "$SCOUT_AGENT"; then
  pass "templates/agent-roles/scout.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/scout.md.tpl: missing explicit no-activation handling"
fi

if ! grep -q 'may still honor' "$SCOUT_AGENT"; then
  pass "templates/agent-roles/scout.md.tpl: no permissive may-still-honor wording on no-activation path"
else
  fail "templates/agent-roles/scout.md.tpl: still uses permissive may-still-honor wording on no-activation path"
fi

if grep -Eq 'still honor( its| any)? `skills_used` frontmatter' "$SCOUT_AGENT"; then
  pass "templates/agent-roles/scout.md.tpl: preserves plan-driven skills_used behavior on no-activation path"
else
  fail "templates/agent-roles/scout.md.tpl: missing mandatory skills_used preservation on no-activation path"
fi

DEBUGGER_AGENT="$ROOT/templates/agent-roles/debugger.md.tpl"

if grep -q 'available_skills' "$DEBUGGER_AGENT"; then
  pass "templates/agent-roles/debugger.md.tpl: references available_skills for ad-hoc activation"
else
  fail "templates/agent-roles/debugger.md.tpl: missing available_skills reference"
fi

if grep -q 'bounded completeness pass' "$DEBUGGER_AGENT"; then
  pass "templates/agent-roles/debugger.md.tpl: includes bounded additive completeness pass"
else
  fail "templates/agent-roles/debugger.md.tpl: missing bounded additive completeness pass"
fi

if grep -q 'skill_no_activation' "$DEBUGGER_AGENT"; then
  pass "templates/agent-roles/debugger.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/debugger.md.tpl: missing explicit no-activation handling"
fi

if grep -q 'starting set, not a ceiling' "$DEBUGGER_AGENT"; then
  pass "templates/agent-roles/debugger.md.tpl: treats orchestrator selection as a starting set"
else
  fail "templates/agent-roles/debugger.md.tpl: missing starting-set additive wording"
fi

ARCHITECT_AGENT="$ROOT/templates/agent-roles/architect.md.tpl"

if grep -q 'available_skills' "$ARCHITECT_AGENT"; then
  pass "templates/agent-roles/architect.md.tpl: references available_skills for ad-hoc activation"
else
  fail "templates/agent-roles/architect.md.tpl: missing available_skills reference"
fi

if grep -q 'bounded completeness pass' "$ARCHITECT_AGENT"; then
  pass "templates/agent-roles/architect.md.tpl: includes bounded additive completeness pass"
else
  fail "templates/agent-roles/architect.md.tpl: missing bounded additive completeness pass"
fi

if grep -q 'skill_no_activation' "$ARCHITECT_AGENT"; then
  pass "templates/agent-roles/architect.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/architect.md.tpl: missing explicit no-activation handling"
fi

if grep -q 'starting set, not a ceiling' "$ARCHITECT_AGENT"; then
  pass "templates/agent-roles/architect.md.tpl: treats orchestrator selection as a starting set"
else
  fail "templates/agent-roles/architect.md.tpl: missing starting-set additive wording"
fi

DOCS_AGENT="$ROOT/templates/agent-roles/docs.md.tpl"

if grep -q 'skills_used' "$DOCS_AGENT"; then
  pass "templates/agent-roles/docs.md.tpl: references skills_used for plan-driven activation"
else
  fail "templates/agent-roles/docs.md.tpl: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DOCS_AGENT"; then
  pass "templates/agent-roles/docs.md.tpl: references Skill() activation"
else
  fail "templates/agent-roles/docs.md.tpl: missing Skill() reference"
fi

if grep -q 'skill_no_activation' "$DOCS_AGENT"; then
  pass "templates/agent-roles/docs.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/docs.md.tpl: missing explicit no-activation handling"
fi

if grep -q 'available_skills' "$DOCS_AGENT"; then
  pass "templates/agent-roles/docs.md.tpl: references available_skills for ad-hoc fallback"
else
  fail "templates/agent-roles/docs.md.tpl: missing available_skills reference for ad-hoc fallback"
fi

if grep -q 'available_skills' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: references available_skills for ad-hoc fallback"
else
  fail "templates/agent-roles/dev.md.tpl: missing available_skills reference for ad-hoc fallback"
fi

if grep -q 'Dev/QA/Scout/Docs' "$PROTOCOL"; then
  pass "execute-protocol.md: documents all execution-time agents (Dev/QA/Scout/Docs)"
else
  fail "execute-protocol.md: missing updated agent coverage"
fi

if grep -q 'Debugger/Dev/Scout' "$PROTOCOL"; then
  pass "execute-protocol.md: names Debugger explicitly in ad-hoc paths"
else
  fail "execute-protocol.md: ad-hoc paths missing Debugger"
fi

if grep -q 'vbw:debug' "$PROTOCOL"; then
  pass "execute-protocol.md: documents /vbw:debug ad-hoc path"
else
  fail "execute-protocol.md: missing /vbw:debug documentation"
fi


DISPATCHER="$ROOT/scripts/skill-hook-dispatch.sh"

if grep -q '\.tools // \..*\.matcher' "$DISPATCHER"; then
  pass "skill-hook-dispatch.sh: reads both tools and matcher (backward compat)"
else
  fail "skill-hook-dispatch.sh: missing backward compat for matcher field"
fi

CONFIG_CMD="$ROOT/commands/config.md"

if grep -q 'skill_hook <skill> <event> <tools>' "$CONFIG_CMD"; then
  pass "config.md: skill_hook signature uses tools (not matcher)"
else
  fail "config.md: skill_hook signature still uses matcher"
fi

if grep -q '"tools": "Write|Edit"' "$CONFIG_CMD"; then
  pass "config.md: example JSON uses tools field"
else
  fail "config.md: example JSON still uses matcher field"
fi


if [ ! -f "$ROOT/scripts/skill-eval-prompt-gate.sh" ]; then
  pass "skill-eval-prompt-gate.sh: deleted"
else
  fail "skill-eval-prompt-gate.sh: still exists"
fi

if [ ! -f "$ROOT/scripts/skill-evaluation-gate.sh" ]; then
  pass "skill-evaluation-gate.sh: deleted"
else
  fail "skill-evaluation-gate.sh: still exists"
fi


if [ ! -f "$ROOT/scripts/emit-skill-xml.sh" ]; then
  pass "emit-skill-xml.sh: deleted (native CC skill visibility)"
else
  fail "emit-skill-xml.sh: still exists (should be deleted)"
fi


if [ ! -f "$ROOT/scripts/inject-subagent-skills.sh" ]; then
  pass "inject-subagent-skills.sh: deleted (additionalContext injection removed)"
else
  fail "inject-subagent-skills.sh: still exists (should be deleted)"
fi

if ! grep -q 'Installed skills:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: no longer injects skill names into additionalContext"
else
  fail "session-start.sh: still injects skill names into additionalContext"
fi


if grep -q 'GSD_WARNING' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: has GSD co-installation warning"
else
  fail "session-start.sh: missing GSD co-installation warning"
fi

if grep -q 'gsd:\*' "$ROOT/scripts/session-start.sh" || grep -q '/gsd:' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: GSD warning references /gsd:* commands"
else
  fail "session-start.sh: GSD warning missing /gsd:* reference"
fi


for role in dev qa docs lead scout architect debugger qa-author; do
  if ! jq -e --arg role "$role" \
      'has($role) and (.[$role] | type == "object" and (has("maxTurns") | not))' \
      "$DEFAULTS" >/dev/null; then
    fail "$role: missing role or maxTurns still in role defaults"
  else
    pass "$role: no maxTurns in role defaults"
  fi
done


if ! grep -q 'emit-skill-xml.sh' "$ROOT/scripts/session-start.sh"; then
  pass "session-start.sh: emit-skill-xml.sh call removed"
else
  fail "session-start.sh: still calls emit-skill-xml.sh (should be removed)"
fi


for agent_file in dev.md.tpl qa.md.tpl docs.md.tpl lead.md.tpl scout.md.tpl architect.md.tpl debugger.md.tpl qa-author.md.tpl; do
  AGENT_PATH="$ROOT/templates/agent-roles/$agent_file"
  if grep -q 'available_skills' "$AGENT_PATH"; then
    pass "$agent_file: references <available_skills>"
  else
    fail "$agent_file: missing <available_skills> reference"
  fi
done

echo ""
