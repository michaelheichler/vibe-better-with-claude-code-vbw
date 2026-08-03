#!/usr/bin/env bash
set -u

FRONTMATTER_ARRAY_ITEMS_AWK=$(cat <<'AWK'
function trim(v) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
  return v
}
function strip_quotes(v, first, last) {
  first = substr(v, 1, 1)
  last = substr(v, length(v), 1)
  if (first == "\"" && last == "\"") return substr(v, 2, length(v) - 2)
  if (first == squote && last == squote) {
    v = substr(v, 2, length(v) - 2)
    gsub(squote squote, squote, v)
    return v
  }
  return v
}
function emit_value(v) {
  v = trim(v)
  if (v == "") return
  v = strip_quotes(v)
  if (v != "") print v
}
function strip_inline_comment(rest, i, ch, quote) {
  quote = ""
  for (i = 1; i <= length(rest); i++) {
    ch = substr(rest, i, 1)
    if (quote == "") {
      if (ch == "\"" || ch == squote) {
        quote = ch
      } else if (ch == "#" && (i == 1 || substr(rest, i - 1, 1) ~ /[[:space:]]/)) {
        return substr(rest, 1, i - 1)
      }
    } else if (ch == quote) {
      quote = ""
    }
  }
  return rest
}
function parse_flow_array(rest, i, ch, current, quote) {
  rest = trim(strip_inline_comment(rest))
  if (rest !~ /^\[/) return 0
  if (rest ~ /^\[[[:space:]]*\][[:space:]]*$/) return 1
  sub(/^\[/, "", rest)
  sub(/\][[:space:]]*$/, "", rest)
  current = ""
  quote = ""
  for (i = 1; i <= length(rest); i++) {
    ch = substr(rest, i, 1)
    if (quote == "") {
      if (ch == "\"" || ch == squote) {
        quote = ch
        current = current ch
        continue
      }
      if (ch == ",") {
        emit_value(current)
        current = ""
        continue
      }
    } else if (ch == quote) {
      quote = ""
      current = current ch
      continue
    }
    current = current ch
  }
  emit_value(current)
  return 1
}
BEGIN {
  in_fm = 0
  in_arr = 0
  squote = sprintf("%c", 39)
}
NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
in_fm && /^---[[:space:]]*$/ { exit }
in_fm && $0 ~ ("^" key ":[[:space:]]*") {
  rest = $0
  sub("^" key ":[[:space:]]*", "", rest)
  if (parse_flow_array(rest)) exit
  in_arr = 1
  next
}
in_fm && in_arr && /^[[:space:]]+- / {
  line = $0
  sub(/^[[:space:]]+- /, "", line)
  emit_value(line)
  next
}
in_fm && in_arr && /^[^[:space:]]/ { exit }
AWK
)

extract_frontmatter_array_items() {
  local file_path="${1:-}"
  local key_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$key_name" ] || return 0
  awk -v key="$key_name" "$FRONTMATTER_ARRAY_ITEMS_AWK" "$file_path" 2>/dev/null
}
