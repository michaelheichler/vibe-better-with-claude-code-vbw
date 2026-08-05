#!/bin/bash
set -u

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
[ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ] || exit 0
[ -f "$SCRIPT_DIR/lib/guard-enforcement.sh" ] || exit 0
. "$SCRIPT_DIR/lib/active-agent-state.sh" || exit 0
. "$SCRIPT_DIR/lib/guard-enforcement.sh" || exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
case "$TOOL_NAME" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

PAYLOAD_AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null) || PAYLOAD_AGENT_TYPE=""
PAYLOAD_AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null) || PAYLOAD_AGENT_ID=""

for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
  [ -n "$candidate" ] || continue
  vbw_active_agent_normalize_role "$candidate" >/dev/null 2>&1 && exit 0
done
for candidate in "$PAYLOAD_AGENT_TYPE" "$PAYLOAD_AGENT_ID"; do
  [ -n "$candidate" ] || continue
  vbw_active_agent_normalize_payload_role "$candidate" >/dev/null 2>&1 && exit 0
done
[ -z "$PAYLOAD_AGENT_TYPE" ] || exit 0
[ -z "$PAYLOAD_AGENT_ID" ] || exit 0


PROJECT_ROOT=$(vbw_guard_project_root "$PWD" 2>/dev/null) || exit 0
STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
[ -f "$STATE_FILE" ] || exit 0

EXEC_STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null) || exit 0
[ "$EXEC_STATUS" = "running" ] || exit 0

CURRENT_SESSION=$(vbw_active_agent_session_id "$INPUT" 2>/dev/null) || CURRENT_SESSION="${CLAUDE_SESSION_ID:-}"
STATE_SESSION=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null) || STATE_SESSION=""
if [ -n "$STATE_SESSION" ] && [ -n "$CURRENT_SESSION" ] && [ "$STATE_SESSION" != "$CURRENT_SESSION" ]; then
  exit 0
fi

NOW=$(date +%s 2>/dev/null || true)
if [ "$(uname)" = "Darwin" ]; then
  MTIME=$(stat -f %m "$STATE_FILE" 2>/dev/null || true)
else
  MTIME=$(stat -c %Y "$STATE_FILE" 2>/dev/null || true)
fi
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac
case "$MTIME" in ''|*[!0-9]*) exit 0 ;; esac
AGE=$((NOW - MTIME))
[ "$AGE" -ge 0 ] && [ "$AGE" -lt 14400 ] || exit 0

TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null) || exit 0
[ -n "$TARGET_PATH" ] || exit 0

deny_product_write() {
  jq -cn --arg reason "VBW vibe execution locks main-session product writes. Delegate this change to a spawned agent." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

case "$TARGET_PATH" in
  ..|../*|*/..|*/../*)
    deny_product_write
    ;;
esac
case "$TARGET_PATH" in
  *.md|.vbw-planning|.vbw-planning/*|*/.vbw-planning|*/.vbw-planning/*|.claude/agents|.claude/agents/*|*/.claude/agents|*/.claude/agents/*)
    exit 0
    ;;
esac

deny_product_write
exit 0
