#!/usr/bin/env bash
set -euo pipefail


PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
FILTER="${1:-}"
DETAILS_PATH="${PLANNING_DIR}/todo-details.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETAILS_CACHE_JSON=""

. "$SCRIPT_DIR/lib/todo-item-metadata.sh"

resolve_state_path() {
  local state_path="$PLANNING_DIR/STATE.md"

  if [ -f "$state_path" ]; then
    echo "$state_path"
    return 0
  fi

  local latest_milestone=""
  local latest_mtime=0
  for f in "$PLANNING_DIR"/milestones/*/STATE.md; do
    [ -f "$f" ] || continue
    local mtime
    mtime=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0)
    if [[ "$mtime" -gt "$latest_mtime" ]]; then
      latest_mtime="$mtime"
      latest_milestone="$f"
    fi
  done
  if [ -n "$latest_milestone" ]; then
    echo "$latest_milestone"
    return 0
  fi

  echo '{"status":"error","message":"STATE.md not found at '"$state_path"'. Run /vbw:init to set up your project."}'
  return 1
}

emit_error_json() {
  local state_path="$1"
  local section_name="$2"
  local filter_lower="$3"
  local message="$4"
  jq -n --arg sp "$state_path" --arg sec "$section_name" --arg f "${filter_lower:-null}" --arg msg "$message" '
    {status:"error", state_path:$sp, section:$sec, count:0,
      filter:(if $f == "null" then null else $f end),
      display:$msg, message:$msg, items:[]}
  '
}

. "$SCRIPT_DIR/lib/list-todos-functions.inc"

main

: "${DETAILS_PATH-}" "${DETAILS_CACHE_JSON-}" "${section_index-}" "${normalized_text-}" "${command_text-}"
