#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"

tracked_command_reference_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'references/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

TRACKED_COMMAND_REFERENCE_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_REFERENCE_FILES+=("$file")
done < <(tracked_command_reference_files)

COMMAND_SKILL_CONTRACT_FILES=(
  "$ROOT/commands/research.md"
  "$ROOT/commands/fix.md"
  "$ROOT/commands/map.md"
  "$ROOT/commands/qa.md"
  "$ROOT/commands/debug.md"
  "$ROOT/references/vibe-mode-bootstrap.md"
  "$ROOT/references/vibe-mode-plan.md"
  "$ROOT/references/vibe-mode-add-phase.md"
  "$ROOT/references/vibe-mode-insert-phase.md"
  "$ROOT/references/vibe-uat-remediation.md"
  "$ROOT/references/vibe-input-parsing.md"
  "$ROOT/references/execute-protocol.md"
)

AGENT_SKILL_CONTRACT_FILES=(
  "$ROOT/agents/vbw-lead.md"
  "$ROOT/agents/vbw-dev.md"
  "$ROOT/agents/vbw-qa.md"
  "$ROOT/agents/vbw-scout.md"
  "$ROOT/agents/vbw-debugger.md"
  "$ROOT/agents/vbw-architect.md"
  "$ROOT/agents/vbw-docs.md"
)

SKILL_FOLLOW_UP_PREFIX="After calling \`Skill(...)\`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting"
SKILL_FOLLOW_UP_SUFFIX="do not scan entire skill folders or read unrelated references."
SKILL_FOLLOW_UP_SEPARATOR_RE='acting.{1,3}[Dd]o not scan'

export COMMAND_SKILL_CONTRACT_FILES AGENT_SKILL_CONTRACT_FILES SKILL_FOLLOW_UP_PREFIX SKILL_FOLLOW_UP_SUFFIX SKILL_FOLLOW_UP_SEPARATOR_RE

PASS=0
FAIL=0


VERIFY_SKILL_MODULE_DIR="$ROOT/testing/verify-skill-activation"
. "$VERIFY_SKILL_MODULE_DIR/runtime-fixtures.bash"
. "$VERIFY_SKILL_MODULE_DIR/payload-contract-helpers.bash"
. "$VERIFY_SKILL_MODULE_DIR/agent-contracts.bash"
. "$VERIFY_SKILL_MODULE_DIR/execute-agent-contracts.bash"
. "$VERIFY_SKILL_MODULE_DIR/additive-contracts.bash"
. "$VERIFY_SKILL_MODULE_DIR/explicit-outcome-contracts.bash"
. "$VERIFY_SKILL_MODULE_DIR/subagent-hook-contracts.bash"
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All skill activation pipeline checks passed."
exit 0
