#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULTS="$ROOT/templates/agent-roles/defaults.json"

PASS=0
FAIL=0

pass() {
  local message="$1"
  echo "PASS  $message"
  printf -v PASS '%d' "$((PASS + 1))"
}

fail() {
  local message="$1"
  echo "FAIL  $message"
  printf -v FAIL '%d' "$((FAIL + 1))"
}

echo "=== Repo-Wide LSP-First Policy Verification ==="


POLICY="$ROOT/references/lsp-first-policy.md"

if [[ -f "$POLICY" ]]; then
  pass "references/lsp-first-policy.md exists"
else
  fail "references/lsp-first-policy.md missing"
fi

if grep -Eiq 'LSP.*first|prefer LSP|Prefer.*LSP' "$POLICY" 2>/dev/null; then
  pass "policy doc states LSP-first rule"
else
  fail "policy doc missing LSP-first rule"
fi

if grep -q "Search/Grep/Glob" "$POLICY" 2>/dev/null; then
  pass "policy doc covers Search/Grep/Glob fallback scope"
else
  fail "policy doc missing Search/Grep/Glob fallback scope"
fi

if grep -Eiq 'LSP is unavailable|LSP.*error' "$POLICY" 2>/dev/null; then
  pass "policy doc covers LSP unavailable fallback"
else
  fail "policy doc missing LSP unavailable fallback"
fi


echo ""
echo "--- Agent LSP-first guidance checks ---"

LSP_AGENTS=("vbw-scout" "vbw-architect" "vbw-lead" "vbw-dev" "vbw-qa" "vbw-debugger" "vbw-docs")

for agent in "${LSP_AGENTS[@]}"; do
  role="${agent#vbw-}"
  AGENT_FILE="$ROOT/templates/agent-roles/${role}.md.tpl"
  SHORT_NAME="$role"

  if [[ ! -f "$AGENT_FILE" ]]; then
    fail "${SHORT_NAME}: agent file missing"
    continue
  fi

  if jq -e --arg role "$role" '((.[$role].tools // "") | contains("LSP"))' "$DEFAULTS" >/dev/null; then
    pass "${SHORT_NAME}: LSP in tools list"
  elif jq -e --arg role "$role" '((.[$role].disallowedTools // "") | contains("LSP") | not)' "$DEFAULTS" >/dev/null; then
    pass "${SHORT_NAME}: LSP inherited via disallowedTools pattern (not denied)"
  elif [[ "$agent" == "vbw-dev" ]] && grep -Eiq 'Prefer.*LSP|prefer.*LSP' "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP inherited (tools via context), LSP guidance present"
  else
    fail "${SHORT_NAME}: LSP missing from tools list"
  fi

  if grep -Eiq 'Prefer.*LSP.*\(go-to-definition, find-references' "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP-first preference instruction present"
  else
    fail "${SHORT_NAME}: missing LSP-first preference instruction"
  fi

  if grep -q "LSP is unavailable or errors.*fall back immediately" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: LSP unavailable fallback guard present"
  else
    fail "${SHORT_NAME}: missing LSP unavailable fallback guard"
  fi

  if grep -q "Search/Grep/Glob" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: explicit Search/Grep/Glob fallback boundaries"
  else
    fail "${SHORT_NAME}: missing explicit Search/Grep/Glob fallback boundaries"
  fi

  if grep -q "lsp-first-policy.md" "$AGENT_FILE"; then
    pass "${SHORT_NAME}: references lsp-first-policy.md"
  else
    fail "${SHORT_NAME}: missing reference to lsp-first-policy.md"
  fi
done


echo ""
echo "--- Lead research-present path LSP checks ---"

LEAD="$ROOT/templates/agent-roles/lead.md.tpl"

if grep -q "If RESEARCH.md exists" "$LEAD"; then
  pass "lead: research-available fast path present"
else
  fail "lead: missing research-available fast path"
fi

if grep -A5 "If RESEARCH.md exists" "$LEAD" | grep -Eiq 'prefer.*LSP|LSP.*\(go-to-definition'; then
  pass "lead: research-present path allows targeted LSP validation"
else
  fail "lead: research-present path missing targeted LSP validation"
fi

if grep -q "Do NOT do broad exploratory scanning" "$LEAD"; then
  pass "lead: broad-scan prohibition when research exists"
else
  fail "lead: missing broad-scan prohibition when research exists"
fi

if grep -q "If no RESEARCH.md exists" "$LEAD"; then
  pass "lead: no-research scanning path present"
else
  fail "lead: missing no-research scanning path"
fi


echo ""
echo "--- Bootstrap & init LSP guidance checks ---"

BOOTSTRAP="$ROOT/scripts/bootstrap/bootstrap-claude.sh"
CLAUDE_TEXT="$ROOT/scripts/lib/claude-md-code-intelligence.txt"
INIT="$ROOT/commands/init.md"

if grep -q "Search/Grep/Glob" "$CLAUDE_TEXT"; then
  pass "bootstrap: Code Intelligence uses Search/Grep/Glob fallback language"
else
  fail "bootstrap: Code Intelligence missing Search/Grep/Glob fallback language"
fi

if grep -q "Prefer LSP over Search/Grep/Glob" "$CLAUDE_TEXT"; then
  pass "bootstrap: Code Intelligence has LSP-first-over-Search language"
else
  fail "bootstrap: Code Intelligence missing LSP-first-over-Search language"
fi

if grep -q "bootstrap-claude.sh" "$INIT"; then
  pass "init: delegates CLAUDE generation to bootstrap-claude.sh"
else
  fail "init: missing bootstrap-claude.sh delegation for CLAUDE generation"
fi

if grep -q "Code Intelligence heading/guidance already exists" "$INIT"; then
  pass "init: documents no-duplicate Code Intelligence rule"
else
  fail "init: missing no-duplicate Code Intelligence rule"
fi


echo ""
echo "--- Contributor docs LSP-first convention checks ---"

AGENTS_MD="$ROOT/AGENTS.md"
CONTRIB="$ROOT/CONTRIBUTING.md"

if [ ! -f "$AGENTS_MD" ]; then
  echo "SKIP  AGENTS.md: not present (gitignored)"
elif grep -Eiq 'LSP-first.*code navigation|lsp-first-policy\.md' "$AGENTS_MD"; then
  pass "AGENTS.md: LSP-first convention documented"
else
  fail "AGENTS.md: missing LSP-first convention"
fi

if grep -Eiq 'LSP-first.*policy|lsp-first-policy\.md' "$CONTRIB"; then
  pass "CONTRIBUTING.md: LSP-first policy referenced"
else
  fail "CONTRIBUTING.md: missing LSP-first policy reference"
fi


echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1
