#!/bin/bash
set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate file path" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // .tool_input.pattern // ""' 2>/dev/null) || exit 2

if [ -z "$FILE_PATH" ]; then
  exit 2
fi

if echo "$FILE_PATH" | grep -qE '\.env$|\.env\.|\.pem$|\.key$|\.cert$|\.p12$|\.pfx$|credentials\.json$|secrets\.json$|service-account.*\.json$|(^|/)node_modules/|(^|/)\.git/|(^|/)dist/|(^|/)build/'; then
  echo "Blocked: sensitive file ($FILE_PATH)" >&2
  exit 2
fi

is_marker_fresh() {
  local marker="$1"
  [ ! -f "$marker" ] && return 1
  local now marker_mtime age
  now=$(date +%s)
  if [ "$(uname)" = "Darwin" ]; then
    marker_mtime=$(stat -f %m "$marker" 2>/dev/null || echo 0)
  else
    marker_mtime=$(stat -c %Y "$marker" 2>/dev/null || echo 0)
  fi
  age=$((now - marker_mtime))
  [ "$age" -lt 86400 ]
}

derive_project_root() {
  local path="$1"
  local marker_dir="$2"
  local root

  root="${path%%/$marker_dir/*}"
  if [ -z "$root" ] || [ "$root" = "$path" ]; then
    root="."
  fi

  printf '%s' "$root"
}

if echo "$FILE_PATH" | grep -qF '.planning/' && ! echo "$FILE_PATH" | grep -qF '.vbw-planning/'; then
  GSD_ROOT=$(derive_project_root "$FILE_PATH" ".planning")
  _SF_ACTIVE_AGENT_FRESH=false
  if command -v vbw_active_agent_current_marker_fresh >/dev/null 2>&1 && vbw_active_agent_current_marker_fresh "$GSD_ROOT/.vbw-planning" "$INPUT" 86400; then
    _SF_ACTIVE_AGENT_FRESH=true
  elif ! command -v vbw_active_agent_current_marker_fresh >/dev/null 2>&1 && is_marker_fresh "$GSD_ROOT/.vbw-planning/.active-agent"; then
    _SF_ACTIVE_AGENT_FRESH=true
  fi
  if [ "$_SF_ACTIVE_AGENT_FRESH" = true ] || is_marker_fresh "$GSD_ROOT/.vbw-planning/.vbw-session"; then
    echo "Blocked: .planning/ is managed by GSD, not VBW ($FILE_PATH)" >&2
    exit 2
  fi
fi


exit 0
