echo "=== Skill Activation Pipeline Verification (plan-driven model) ==="


DEV_AGENT="$ROOT/templates/agent-roles/dev.md.tpl"
DEFAULTS="$ROOT/templates/agent-roles/defaults.json"
FIX_COMMAND="$ROOT/commands/fix.md"
VIBE_COMMAND="$RUNTIME_HELPER_TEST_ROOT/vibe-skill-effective.md"
EXECUTE_PROTOCOL="$ROOT/references/execute-protocol.md"
cat \
  "$ROOT/commands/vibe.md" \
  "$ROOT/references/ask-user-question.md" \
  "$ROOT/references/subagent-contracts.md" \
  "$ROOT/references/vibe-input-parsing.md" \
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
  "$ROOT/references/vbw-brand-essentials.md" > "$VIBE_COMMAND"
DEV_TOOLS=$(jq -r '.dev.tools // empty' "$DEFAULTS")
DEV_DISALLOWED=$(jq -r '.dev.disallowedTools // empty' "$DEFAULTS")
DEV_MEMORY=$(jq -r '.dev.memory // empty' "$DEFAULTS")
DEV_MEMORY="memory: $DEV_MEMORY"
DEV_DISALLOWED="disallowedTools: $DEV_DISALLOWED"
DEV_BODY=$(awk '
  NR == 1 && /^---$/ { in_frontmatter = 1; next }
  in_frontmatter && /^---$/ { in_frontmatter = 0; next }
  !in_frontmatter { print }
' "$DEV_AGENT")

markdown_section() {
  local heading="$1"
  awk -v heading="$heading" '
    $0 == "## " heading { in_section = 1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' <<< "$DEV_BODY"
}

DEV_COMMUNICATION_SECTION=$(markdown_section Communication)
DEV_BLOCKED_TASK_SECTION=$(markdown_section "Blocked Task Self-Start")
DEV_CONSTRAINTS_SECTION=$(markdown_section Constraints)

dev_disallowed_has() {
  local target="$1"
  printf '%s' "$DEV_DISALLOWED" | sed 's/^disallowedTools:[[:space:]]*//' | awk -v RS=',' -v target="$target" '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == target) found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

if [ -z "$DEV_TOOLS" ]; then
  pass "templates/agent-roles/dev.md.tpl: does not pin a tools allowlist (forward-compatible)"
else
  fail "templates/agent-roles/dev.md.tpl: must not pin a tools allowlist (use disallowedTools denylist for forward compatibility)"
fi

if [ -n "$DEV_DISALLOWED" ]; then
  pass "templates/agent-roles/dev.md.tpl: declares disallowedTools denylist"
else
  fail "templates/agent-roles/dev.md.tpl: missing disallowedTools denylist"
fi

if [ "$DEV_MEMORY" = "memory: project" ]; then
  pass "templates/agent-roles/dev.md.tpl: preserves project memory"
else
  fail "templates/agent-roles/dev.md.tpl: memory must remain project (found: ${DEV_MEMORY:-missing})"
fi

for required_denied in Task TaskCreate Agent AskUserQuestion; do
  if dev_disallowed_has "$required_denied"; then
    pass "templates/agent-roles/dev.md.tpl: disallowedTools bans $required_denied"
  else
    fail "templates/agent-roles/dev.md.tpl: disallowedTools must ban $required_denied"
  fi
done

for must_remain_available in Bash Read Edit Write Glob Grep LSP Skill WebFetch WebSearch SendMessage TaskGet; do
  if dev_disallowed_has "$must_remain_available"; then
    fail "templates/agent-roles/dev.md.tpl: disallowedTools must not ban $must_remain_available (Dev relies on it)"
  else
    pass "templates/agent-roles/dev.md.tpl: disallowedTools does not ban $must_remain_available"
  fi
done

if grep -q 'Your frontmatter denylist explicitly bans recursive delegation' <<< "$DEV_CONSTRAINTS_SECTION" \
  && grep -q 'Use the listed implementation tools directly' <<< "$DEV_CONSTRAINTS_SECTION" \
  && grep -q 'Task`, `TaskCreate`, `Agent`, and `AskUserQuestion`' <<< "$DEV_CONSTRAINTS_SECTION" \
  && grep -q 'Do not form an agent team' <<< "$DEV_CONSTRAINTS_SECTION"; then
  pass "templates/agent-roles/dev.md.tpl: prompt explains denylist no-subagent tool boundary"
else
  fail "templates/agent-roles/dev.md.tpl: missing denylist no-subagent tool-boundary guidance"
fi

if grep -q 'SendMessage' <<< "$DEV_COMMUNICATION_SECTION" \
  && grep -q 'execution_update' <<< "$DEV_COMMUNICATION_SECTION" \
  && grep -q 'blocker_report' <<< "$DEV_COMMUNICATION_SECTION" \
  && ! dev_disallowed_has SendMessage; then
  pass "templates/agent-roles/dev.md.tpl: SendMessage guidance available (not in denylist)"
else
  fail "templates/agent-roles/dev.md.tpl: SendMessage guidance/availability mismatch"
fi

if grep -q 'TaskGet' <<< "$DEV_BLOCKED_TASK_SECTION" \
  && grep -q 'blockedBy' <<< "$DEV_BLOCKED_TASK_SECTION" \
  && grep -q 'completed' <<< "$DEV_BLOCKED_TASK_SECTION" \
  && grep -q 'self-start' <<< "$DEV_BLOCKED_TASK_SECTION" \
  && ! dev_disallowed_has TaskGet; then
  pass "templates/agent-roles/dev.md.tpl: TaskGet guidance available (not in denylist)"
else
  fail "templates/agent-roles/dev.md.tpl: TaskGet guidance/availability mismatch"
fi

if grep -q '^## MCP-Derived Context' "$DEV_AGENT"; then
  fail "templates/agent-roles/dev.md.tpl: stale '## MCP-Derived Context' section must be removed (subagents may call MCP directly)"
else
  pass "templates/agent-roles/dev.md.tpl: no stale '## MCP-Derived Context' section"
fi

if grep -q 'explicit `tools:` allowlist' "$DEV_AGENT" \
  || grep -q 'Assume dynamic MCP server tools are unavailable' "$DEV_AGENT" \
  || grep -q 'Do not ask the orchestrator to add MCP' "$DEV_AGENT"; then
  fail "templates/agent-roles/dev.md.tpl: stale anti-MCP allowlist guidance must be removed"
else
  pass "templates/agent-roles/dev.md.tpl: no stale anti-MCP allowlist guidance"
fi

if grep -q 'Dev uses an explicit allowlist' "$ROOT/README.md" \
  || grep -q 'Explicit implementation allowlist' "$ROOT/README.md"; then
  fail "README.md: stale Dev allowlist wording must be removed"
else
  pass "README.md: no stale Dev allowlist wording"
fi

if grep -q 'Dev uses a `disallowedTools` denylist' "$ROOT/README.md" \
  && grep -q 'Denylist (no Task/Agent/Team/AskUserQuestion)' "$ROOT/README.md"; then
  pass "README.md: Dev described as denylist in overview and diagram"
else
  fail "README.md: Dev overview/diagram missing denylist language"
fi

if grep -q '## Available Tools' "$DEV_AGENT" \
  && grep -q 'denylist' "$DEV_AGENT" \
  && grep -q '## MCP Tool Usage' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: documents denylist tool boundary and MCP availability"
else
  fail "templates/agent-roles/dev.md.tpl: missing denylist + MCP availability documentation"
fi

for anti_mcp_target in "$FIX_COMMAND" "$VIBE_COMMAND" "$EXECUTE_PROTOCOL"; do
  target_label=$(basename "$anti_mcp_target")
  if grep -q 'do not instruct `vbw-dev` to call MCP servers directly' "$anti_mcp_target" \
    || grep -q 'pre-extract concise.*for Dev' "$anti_mcp_target" \
    || grep -q 'Do not plan for Dev agents to call MCP servers directly' "$anti_mcp_target"; then
    fail "$target_label: stale anti-MCP gating prose must be removed (subagents may call MCP directly)"
  else
    pass "$target_label: no stale anti-MCP gating prose"
  fi
done

if grep -q 'note them in the Dev task description' "$FIX_COMMAND" \
  || grep -q "note them in the Dev's task context" "$VIBE_COMMAND" \
  || grep -q 'so the Dev agent knows which MCP tools to use' "$EXECUTE_PROTOCOL"; then
  fail "Dev spawn docs: stale inherited MCP instruction remains"
else
  pass "Dev spawn docs: no stale inherited MCP instruction remains"
fi

if grep -q 'skills_used' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: references skills_used frontmatter"
else
  fail "templates/agent-roles/dev.md.tpl: missing skills_used reference"
fi

if grep -q 'Skill(skill-name)' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: references Skill() activation"
else
  fail "templates/agent-roles/dev.md.tpl: missing Skill() reference"
fi

if ! grep -q 'protocol violation' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: no enforcement language"
else
  fail "templates/agent-roles/dev.md.tpl: still has 'protocol violation' enforcement language"
fi

if grep -q 'skill_activation' "$DEV_AGENT" && grep -q 'skill_no_activation' "$DEV_AGENT"; then
  pass "templates/agent-roles/dev.md.tpl: has orchestrator-aware conditional in deeper protocol"
else
  fail "templates/agent-roles/dev.md.tpl: missing orchestrator-aware conditional (must reference both skill_activation and skill_no_activation)"
fi


LEAD_AGENT="$ROOT/templates/agent-roles/lead.md.tpl"
LEAD_TOOLS="tools: $(jq -r '.lead.tools // empty' "$DEFAULTS")"

if grep -q 'Skill' <<< "$LEAD_TOOLS"; then
  pass "templates/agent-roles/lead.md.tpl: Skill in tools allowlist"
else
  fail "templates/agent-roles/lead.md.tpl: Skill NOT in tools allowlist"
fi

if grep -q 'Wire relevant skills into plans' "$LEAD_AGENT"; then
  pass "templates/agent-roles/lead.md.tpl: emphasizes wiring skills into plans"
else
  fail "templates/agent-roles/lead.md.tpl: missing plan wiring language"
fi

if grep -q 'Skill completeness check' "$LEAD_AGENT"; then
  pass "templates/agent-roles/lead.md.tpl: has skill completeness gate in self-review"
else
  fail "templates/agent-roles/lead.md.tpl: missing skill completeness gate in self-review"
fi

if grep -q 'skill_no_activation' "$LEAD_AGENT"; then
  pass "templates/agent-roles/lead.md.tpl: recognizes explicit no-activation block"
else
  fail "templates/agent-roles/lead.md.tpl: missing explicit no-activation handling"
fi

if ! grep -q 'write YES or NO' "$LEAD_AGENT"; then
  pass "templates/agent-roles/lead.md.tpl: no written YES/NO evaluation"
else
  fail "templates/agent-roles/lead.md.tpl: still has written YES/NO evaluation"
fi


HOOKS_FILE="$ROOT/hooks/hooks.json"

if jq -e '[.. | objects | .command? // empty | select(contains("skill-evaluation-gate.sh"))] | length == 0' "$HOOKS_FILE" >/dev/null 2>&1; then
  pass "hooks.json: skill-evaluation-gate.sh removed"
else
  fail "hooks.json: skill-evaluation-gate.sh still present"
fi

if jq -e '[.. | objects | .command? // empty | select(contains("skill-eval-prompt-gate.sh"))] | length == 0' "$HOOKS_FILE" >/dev/null 2>&1; then
  pass "hooks.json: skill-eval-prompt-gate.sh removed"
else
  fail "hooks.json: skill-eval-prompt-gate.sh still present"
fi


if jq -e '[.. | objects | .command? // empty | select(contains("skill-hook-dispatch.sh"))] | length > 0' "$HOOKS_FILE" >/dev/null 2>&1; then
  pass "hooks.json: skill-hook-dispatch.sh preserved (runtime skill hooks)"
else
  fail "hooks.json: skill-hook-dispatch.sh missing (should be preserved)"
fi


for agent_file in qa scout debugger architect docs qa-author; do
  AGENT_PATH="$ROOT/templates/agent-roles/${agent_file}.md.tpl"
  AGENT_TOOLS="$(jq -r --arg role "$agent_file" '.[$role].tools // empty' "$DEFAULTS")"
  AGENT_DISALLOWED="$(jq -r --arg role "$agent_file" '.[$role].disallowedTools // empty' "$DEFAULTS")"
  if [ -n "$AGENT_TOOLS" ]; then
    if grep -q 'Skill' <<< "$AGENT_TOOLS"; then
      pass "$agent_file: Skill in tools allowlist"
    else
      fail "$agent_file: Skill NOT in tools allowlist"
    fi
  elif [ -n "$AGENT_DISALLOWED" ]; then
    if grep -q 'Skill' <<< "$AGENT_DISALLOWED"; then
      fail "$agent_file: Skill is in disallowedTools (should be inherited)"
    else
      pass "$agent_file: Skill inherited via disallowedTools pattern (not denied)"
    fi
  else
    fail "$agent_file: Neither tools: nor disallowedTools: found in frontmatter"
  fi
done


COMPILER="$ROOT/scripts/compile-context.sh"

if grep -q 'emit_skill_directive' "$COMPILER"; then
  fail "compile-context.sh: still has emit_skill_directive (should be removed)"
else
  pass "compile-context.sh: emit_skill_directive removed"
fi
