#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$SCRIPT_DIR/lib/track-known-issues-frontmatter.sh"

parse_frontmatter_issue_json() {
  local item="$1"
  local source_path="$2"
  local round="$3"
  local test file error
  item=$(trim "$item")
  [ -n "$item" ] || return 1
  if ! printf '%s' "$item" | jq -e '
    type == "object"
    and (.test | type == "string")
    and (.file | type == "string")
    and (.error | type == "string")
  ' >/dev/null 2>&1; then
    return 1
  fi
  test=$(printf '%s' "$item" | jq -r '.test')
  file=$(printf '%s' "$item" | jq -r '.file')
  error=$(printf '%s' "$item" | jq -r '.error')
  new_issue_object "$(strip_code_ticks "$test")" "$(strip_code_ticks "$file")" "$(strip_code_ticks "$error")" "$source_path" "$round"
}
parse_freeform_issue_line() {
  local line="$1"
  local source_path="$2"
  local round="$3"
  local test=""
  local file=""
  local error=""
  line=$(trim "$line")
  [ -n "$line" ] || return 1
  if [[ "$line" =~ ^(.+)[[:space:]]+\(([^()]+)\):[[:space:]]*(.+)$ ]]; then
    test=$(strip_code_ticks "${BASH_REMATCH[1]}")
    file=$(strip_code_ticks "${BASH_REMATCH[2]}")
    error=$(strip_code_ticks "${BASH_REMATCH[3]}")
  elif [[ "$line" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
    test=$(strip_code_ticks "${BASH_REMATCH[1]}")
    file="$test"
    error=$(strip_code_ticks "${BASH_REMATCH[2]}")
  else
    return 1
  fi
  [ -n "$test" ] || return 1
  [ -n "$file" ] || file="$test"
  [ -n "$error" ] || return 1
  new_issue_object "$test" "$file" "$error" "$source_path" "$round"
}
extract_legacy_summary_issue_lines() {
  local summary_file="$1" source_rel="$2"
  awk -v source_rel="$source_rel" '
    /^## Pre-existing Issues/ { found=1; next }
    found && /^## / { exit }
    found && /^[[:space:]]*$/ { next }
    found && /^- / {
      line = $0
      sub(/^- /, "", line)
      print source_rel "\t" line
    }
  ' "$summary_file" 2>/dev/null || true
}

extract_summary_issues_json_file() {
  local summary_file="$1"
  local source_rel frontmatter_items
  [ -f "$summary_file" ] || return 0
  source_rel=$(relative_to_phase "$summary_file")
  frontmatter_items=$(extract_frontmatter_array_items "$summary_file" pre_existing_issues)
  if frontmatter_key_present "$summary_file" pre_existing_issues; then
    while IFS= read -r item; do
      [ -n "$item" ] || continue
      parse_frontmatter_issue_json "$item" "$source_rel" 0 || true
    done <<< "$frontmatter_items"
  else
    extract_legacy_summary_issue_lines "$summary_file" "$source_rel" |
      while IFS=$'\t' read -r summary_rel line; do
        [ -n "$summary_rel" ] || continue
        parse_freeform_issue_line "$line" "$summary_rel" 0 || true
      done
  fi
}

extract_summary_issues_json() {
  local tmp_json
  tmp_json=$(mktemp)
  local summary_file
  while IFS= read -r summary_file; do
    extract_summary_issues_json_file "$summary_file"
  done < <(find "$PHASE_DIR" -maxdepth 1 ! -name '.*' \( -name '*-SUMMARY.md' -o -name 'SUMMARY.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort)) > "$tmp_json"
  jq -s 'map(select(type == "object")) | unique_by(.test, .file, .error) | sort_by(.test, .file, .error)' "$tmp_json"
  rm -f "$tmp_json"
}
