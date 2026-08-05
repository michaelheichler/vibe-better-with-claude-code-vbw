#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  local message="$1"
  printf 'PASS  %s\n' "$message"
  declare -g PASS=$((PASS + 1))
}

fail() {
  local message="$1"
  printf 'FAIL  %s\n' "$message"
  declare -g FAIL=$((FAIL + 1))
}

contains() {
  local file="$1"
  local pattern="$2"
  grep -Fq "$pattern" "$file"
}

omits() {
  local file="$1"
  local pattern="$2"
  ! grep -Fq "$pattern" "$file"
}

HELPER="$ROOT/scripts/resolve-agent-settings.sh"
FIX_FILE="$ROOT/commands/fix.md"
RESEARCH_FILE="$ROOT/commands/research.md"
QA_FILE="$ROOT/commands/qa.md"
DEBUG_FILE="$ROOT/commands/debug.md"
VIBE_FILE="$ROOT/commands/vibe.md"

if [ -f "$HELPER" ] \
  && contains "$HELPER" "RESOLVED_MODEL" \
  && contains "$HELPER" "RESOLVED_MAX_TURNS" \
  && contains "$HELPER" "resolve-agent-model.sh" \
  && contains "$HELPER" "resolve-agent-max-turns.sh"; then
  pass "helper: resolve-agent-settings.sh emits consolidated agent settings"
else
  fail "helper: resolve-agent-settings.sh missing consolidated output contract"
fi

if contains "$FIX_FILE" 'bash "{plugin-root}/scripts/resolve-agent-settings.sh" dev .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" turbo' \
  && omits "$FIX_FILE" 'resolve-agent-model.sh" dev' \
  && omits "$FIX_FILE" 'resolve-agent-max-turns.sh" dev'; then
  pass "fix: uses consolidated dev agent settings helper"
else
  fail "fix: missing consolidated dev agent settings helper"
fi

if contains "$RESEARCH_FILE" 'bash "{plugin-root}/scripts/resolve-agent-settings.sh" scout .vbw-planning/config.json "{plugin-root}/config/model-profiles.json"' \
  && omits "$RESEARCH_FILE" 'resolve-agent-model.sh" scout' \
  && omits "$RESEARCH_FILE" 'resolve-agent-max-turns.sh" scout'; then
  pass "research: uses consolidated scout agent settings helper"
else
  fail "research: missing consolidated scout agent settings helper"
fi

if contains "$QA_FILE" 'bash "{plugin-root}/scripts/resolve-agent-settings.sh" qa .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$QA_EFFORT_PROFILE"' \
  && omits "$QA_FILE" 'resolve-agent-model.sh" qa' \
  && omits "$QA_FILE" 'resolve-agent-max-turns.sh" qa'; then
  pass "qa: uses consolidated qa agent settings helper"
else
  fail "qa: missing consolidated qa agent settings helper"
fi

if contains "$DEBUG_FILE" 'bash "{plugin-root}/scripts/resolve-agent-settings.sh" debugger .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$EFFORT_PROFILE"' \
  && contains "$DEBUG_FILE" 'bash "{plugin-root}/scripts/resolve-agent-settings.sh" qa .vbw-planning/config.json "{plugin-root}/config/model-profiles.json" "$EFFORT_PROFILE"' \
  && omits "$DEBUG_FILE" 'resolve-agent-model.sh" debugger' \
  && omits "$DEBUG_FILE" 'resolve-agent-max-turns.sh" debugger' \
  && omits "$DEBUG_FILE" 'resolve-agent-model.sh" qa' \
  && omits "$DEBUG_FILE" 'resolve-agent-max-turns.sh" qa'; then
  pass "debug: uses consolidated debugger and qa agent settings helper"
else
  fail "debug: missing consolidated debugger/qa agent settings helper"
fi

if contains "$VIBE_FILE" 'Read `{LINK}/references/vibe-mode-execute.md` and follow it.' \
  && omits "$VIBE_FILE" 'resolve-agent-model.sh' \
  && omits "$VIBE_FILE" 'resolve-agent-max-turns.sh'; then
  pass "vibe: delegates execution settings to the mode reference"
else
  fail "vibe: missing mode-reference execution delegation"
fi

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[ "$FAIL" -eq 0 ] || exit 1
