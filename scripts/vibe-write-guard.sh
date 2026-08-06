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
PHASES_DIR="$PROJECT_ROOT/.vbw-planning/phases"

_ACTIVE_PLAN=false
if phase_has_active_plan "$PHASES_DIR"; then
  _ACTIVE_PLAN=true
fi
_STATE_ACTIVE=false
STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
if [ -f "$STATE_FILE" ]; then
  EXEC_STATUS=$(jq -r '.status // ""' "$STATE_FILE" 2>/dev/null) || EXEC_STATUS=""
  if [ "$EXEC_STATUS" = "running" ]; then
    CURRENT_SESSION=$(vbw_active_agent_session_id "$INPUT" 2>/dev/null) || CURRENT_SESSION="${CLAUDE_SESSION_ID:-}"
    STATE_SESSION=$(jq -r '.session_id // ""' "$STATE_FILE" 2>/dev/null) || STATE_SESSION=""
    if [ -z "$STATE_SESSION" ] || [ -z "$CURRENT_SESSION" ] || [ "$STATE_SESSION" = "$CURRENT_SESSION" ]; then
      NOW=$(date +%s 2>/dev/null || true)
      if [ "$(uname)" = "Darwin" ]; then
        MTIME=$(stat -f %m "$STATE_FILE" 2>/dev/null || true)
      else
        MTIME=$(stat -c %Y "$STATE_FILE" 2>/dev/null || true)
      fi
      case "$NOW" in ''|*[!0-9]*) NOW="" ;; esac
      case "$MTIME" in ''|*[!0-9]*) MTIME="" ;; esac
      if [ -n "$NOW" ] && [ -n "$MTIME" ]; then
        AGE=$((NOW - MTIME))
        if [ "$AGE" -ge 0 ] && [ "$AGE" -lt 14400 ]; then
          _STATE_ACTIVE=true
        fi
      fi
    fi
  fi
fi

[ "$_ACTIVE_PLAN" = true ] || [ "$_STATE_ACTIVE" = true ] || exit 0

TARGET_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null) || exit 0
[ -n "$TARGET_PATH" ] || exit 0

deny_product_write() {
  jq -cn --arg reason "VBW vibe execution locks main-session product writes. Delegate this change to a spawned agent." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

canonicalize_target_input() {
  local target="$1" parent base
  CANONICAL_SUFFIX=()
  if [[ "$target" = /* ]]; then
    CANONICAL_PATH="$target"
  else
    CANONICAL_PATH="$PWD/$target"
  fi
  while [ ! -e "$CANONICAL_PATH" ] && [ ! -L "$CANONICAL_PATH" ]; do
    parent="${CANONICAL_PATH%/*}"
    base="${CANONICAL_PATH##*/}"
    CANONICAL_SUFFIX=("$base" "${CANONICAL_SUFFIX[@]}")
    [ "$parent" = "$CANONICAL_PATH" ] && parent="/"
    CANONICAL_PATH="$parent"
  done
}

resolve_target_symlinks() {
  local link parent base hops=0
  while [ -L "$CANONICAL_PATH" ]; do
    hops=$((hops + 1))
    [ "$hops" -gt 40 ] && return 1
    link=$(readlink "$CANONICAL_PATH" 2>/dev/null) || return 1
    if [[ "$link" = /* ]]; then
      CANONICAL_PATH="$link"
    else
      CANONICAL_PATH="$(dirname "$CANONICAL_PATH")/$link"
    fi
    while [ ! -e "$CANONICAL_PATH" ] && [ ! -L "$CANONICAL_PATH" ]; do
      parent="${CANONICAL_PATH%/*}"
      base="${CANONICAL_PATH##*/}"
      CANONICAL_SUFFIX=("$base" "${CANONICAL_SUFFIX[@]}")
      [ "$parent" = "$CANONICAL_PATH" ] && parent="/"
      CANONICAL_PATH="$parent"
    done
  done
}

canonicalize_target_base() {
  local parent
  if [ -d "$CANONICAL_PATH" ]; then
    CANONICAL_PATH=$(cd "$CANONICAL_PATH" 2>/dev/null && pwd -P) || return 1
  else
    parent=$(cd "$(dirname "$CANONICAL_PATH")" 2>/dev/null && pwd -P) || return 1
    CANONICAL_PATH="$parent/$(basename "$CANONICAL_PATH")"
  fi
}

canonicalize_target_path() {
  local base
  canonicalize_target_input "$1" || return 1
  resolve_target_symlinks || return 1
  canonicalize_target_base || return 1
  for base in "${CANONICAL_SUFFIX[@]}"; do
    CANONICAL_PATH="$CANONICAL_PATH/$base"
  done
  printf '%s\n' "$CANONICAL_PATH"
}

CANONICAL_PATH=""
CANONICAL_SUFFIX=()

case "$TARGET_PATH" in
  ..|../*|*/..|*/../*)
    deny_product_write
    ;;
esac
CANONICAL_TARGET_PATH=$(canonicalize_target_path "$TARGET_PATH" 2>/dev/null) || deny_product_write
is_template_exempt_path "$PROJECT_ROOT" "$CANONICAL_TARGET_PATH" && exit 0
case "$CANONICAL_TARGET_PATH" in
  *.md|.vbw-planning|.vbw-planning/*|*/.vbw-planning|*/.vbw-planning/*|.claude/agents|.claude/agents/*|*/.claude/agents|*/.claude/agents/*)
    exit 0
    ;;
esac

deny_product_write
exit 0
