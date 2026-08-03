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

extract_todos() {
  local file="$1"
  local section_name=""
  local lines=""

  lines=$(awk '
    /^## Todos$/ { found=1; next }
    found && /^##/ { exit }
    found && /^### / { sub_found=1; next }
    found && sub_found && /^##/ { exit }
    found && !sub_found && /^- / { print }
  ' "$file")

  if [ -n "$lines" ]; then
    section_name="## Todos"
  else
    lines=$(awk '
      /^### Pending Todos$/ { found=1; next }
      found && /^### Completed Todos$/ { exit }
      found && /^##/ { exit }
      found && /^- / { print }
    ' "$file")
    if [ -n "$lines" ]; then
      section_name="### Pending Todos"
    fi
  fi

  if [ -z "$lines" ]; then
    echo ""
    return
  fi

  echo "$section_name"
  echo "$lines"
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

main() {
  local filter_lower=""
  if [ -n "$FILTER" ]; then
    filter_lower=$(echo "$FILTER" | tr '[:upper:]' '[:lower:]')
  fi

  local state_path
  state_path=$(resolve_state_path) || { echo "$state_path"; exit 0; }

  local raw_output section_name
  raw_output=$(extract_todos "$state_path")

  if [ -z "$raw_output" ]; then
    jq -n --arg sp "$state_path" --arg f "${filter_lower:-null}" \
      '{status:"empty", state_path:$sp, section:null, count:0,
        filter:(if $f == "null" then null else $f end),
        display:"No pending todos.", items:[]}'
    exit 0
  fi

  section_name=$(echo "$raw_output" | head -1)
  local todo_lines
  todo_lines=$(echo "$raw_output" | tail -n +2)

  local all_items_json items_json
  local section_index=0
  local all_items_ndjson
  all_items_ndjson=$(mktemp 2>/dev/null) || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not prepare todo listing output. Rerun /vbw:list-todos."
    exit 0
  }
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local stripped="${line#- }"
    stripped="${stripped#"${stripped%%[![:space:]]*}"}"
    [ -z "$stripped" ] && continue
    section_index=$((section_index + 1))

    local parsed
    if ! parsed=$(todo_item_parse_line_json "$line" "$section_index" "$state_path" "$section_name"); then
      rm -f "$all_items_ndjson"
      emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not parse one of the current todos. Rerun /vbw:list-todos."
      exit 0
    fi
    if ! printf '%s\n' "$parsed" >> "$all_items_ndjson"; then
      rm -f "$all_items_ndjson"
      emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not stage todo listing output. Rerun /vbw:list-todos."
      exit 0
    fi
  done <<< "$todo_lines"

  all_items_json=$(jq -sc '.' "$all_items_ndjson" 2>/dev/null) || {
    rm -f "$all_items_ndjson"
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not build the todo listing. Rerun /vbw:list-todos."
    exit 0
  }
  rm -f "$all_items_ndjson"
  all_items_json=$(todo_item_annotate_identity_occurrence "$all_items_json") || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not annotate todo identity metadata. Rerun /vbw:list-todos."
    exit 0
  }
  items_json=$(printf '%s' "$all_items_json" | jq -c --arg filter "$filter_lower" '
    [ .[]
      | if $filter == "" then . else select(.priority == $filter) end
    ]
    | to_entries
    | map(.value + {num:(.key + 1)})
  ' 2>/dev/null) || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not filter todo items. Rerun /vbw:list-todos."
    exit 0
  }

  local filtered_count
  filtered_count=$(echo "$items_json" | jq 'length' 2>/dev/null) || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not count todo items. Rerun /vbw:list-todos."
    exit 0
  }

  if [ "$filtered_count" -eq 0 ]; then
    local msg
    if [ -n "$filter_lower" ]; then
      msg="No ${filter_lower}-priority todos found."
    else
      msg="No pending todos."
    fi
    jq -n --arg st "$([ -n "$filter_lower" ] && echo "no-match" || echo "empty")" \
      --arg sp "$state_path" --arg sec "$section_name" \
      --arg f "${filter_lower:-null}" --arg msg "$msg" \
      '{status:$st, state_path:$sp, section:$sec, count:0,
        filter:(if $f == "null" then null else $f end),
        display:$msg, items:[]}'
    exit 0
  fi

  local display
  display=$(printf '%s' "$items_json" | jq -r '
    .[] |
      (
        (if .priority == "high" then "[HIGH] " elif .priority == "low" then "[low] " elif .priority == "known-issue" then "[KNOWN-ISSUE] " else "" end)
        + .normalized_text
        + (if .age then " (" + .age + ")" else "" end)
        + (if .ref then " [detail]" else "" end)
      ) as $body
      | "\(.num). \($body)"
  ' 2>/dev/null) || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not render the todo listing. Rerun /vbw:list-todos."
    exit 0
  }
  [ -n "$display" ] && display="${display}"$'\n'

  echo "$items_json" | jq --arg st "ok" --arg sp "$state_path" \
    --arg sec "$section_name" --argjson c "$filtered_count" \
    --arg f "${filter_lower:-null}" --arg d "$display" \
    '{status:$st, state_path:$sp, section:$sec, count:$c,
      filter:(if $f == "null" then null else $f end),
      display:$d, items:.}' 2>/dev/null || {
    emit_error_json "$state_path" "$section_name" "$filter_lower" "Could not finalize the todo listing. Rerun /vbw:list-todos."
    exit 0
  }
}

main

: "${DETAILS_PATH-}" "${DETAILS_CACHE_JSON-}"
