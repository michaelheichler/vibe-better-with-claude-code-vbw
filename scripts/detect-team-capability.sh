#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

emit_result() {
  printf 'team_capability=%s\nteam_capability_reason=%s\n' "$1" "$2"
}

if [ -n "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  if [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" ]; then
    emit_result available env_enabled
  else
    emit_result unavailable env_disabled
  fi
  exit 0
fi

. "$SCRIPT_DIR/resolve-claude-dir.sh"
settings_path="$CLAUDE_DIR/settings.json"

if [ ! -f "$settings_path" ]; then
  emit_result unavailable not_configured
elif ! jq empty "$settings_path" >/dev/null 2>&1; then
  emit_result unavailable settings_unreadable
elif jq -e '.env? | objects | has("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS")' "$settings_path" >/dev/null 2>&1; then
  if jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"' "$settings_path" >/dev/null 2>&1; then
    emit_result available settings_enabled
  else
    emit_result unavailable settings_disabled
  fi
else
  emit_result unavailable not_configured
fi

exit 0
