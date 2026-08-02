#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"

tracked_command_markdown_files() {
  local rel
  git -C "$ROOT" ls-files -- 'commands/*.md' 'internal/*.md' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    printf '%s\n' "$ROOT/$rel"
  done
}

tracked_active_scan_files() {
  local rel
  git -C "$ROOT" ls-files -- scripts references agents templates \
    | awk -F/ '($1 == "scripts" || $1 == "references" || $1 == "agents" || $1 == "templates") && NF <= 3 && ($NF ~ /\.sh$/ || $NF ~ /\.md$/) { print }' \
    | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      printf '%s\n' "$ROOT/$rel"
    done
}

TRACKED_COMMAND_MARKDOWN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_COMMAND_MARKDOWN_FILES+=("$file")
done < <(tracked_command_markdown_files)

TRACKED_ACTIVE_SCAN_FILES=()
while IFS= read -r file; do
  [ -n "$file" ] || continue
  TRACKED_ACTIVE_SCAN_FILES+=("$file")
done < <(tracked_active_scan_files)

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

extract_frontmatter() {
  local file="$1"
  awk '
    BEGIN { delim=0; body="" }
    /^---$/ {
      delim++
      if (delim == 2) { closed=1; next }
      next
    }
    delim == 1 { body = body $0 ORS }
    END {
      if (closed) printf "%s", body
    }
  ' "$file"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_block_whitespace() {
  tr '\r\n\t' '   ' | awk '
    {
      gsub(/[[:space:]]+/, " ")
      sub(/^ /, "")
      sub(/ $/, "")
      print
    }
  '
}

contains_literal() {
  local haystack="$1"
  local needle="$2"

  grep -Fq -- "$needle" <<< "$haystack"
}

frontmatter_first_scalar() {
  local frontmatter="$1"
  local field="$2"

  awk -v field="$field" '
    BEGIN {
      pattern = "^" field ":[[:space:]]*"
    }

    $0 ~ pattern && first == "" {
      line = $0
      sub(pattern, "", line)
      first = line
    }

    END {
      if (first != "") print first
    }
  ' <<< "$frontmatter"
}

frontmatter_first_scalar_from_file() {
  local file="$1"
  local field="$2"
  local frontmatter=""

  frontmatter="$(extract_frontmatter "$file")"
  frontmatter_first_scalar "$frontmatter" "$field"
}

frontmatter_continuation_lines() {
  local frontmatter="$1"
  local field="$2"

  awk -v field="$field" '
    BEGIN {
      pattern = "^" field ":"
    }

    $0 ~ pattern {
      collecting = 1
      next
    }

    collecting && /^[[:space:]]/ {
      print
      next
    }

    collecting {
      collecting = 0
    }
  ' <<< "$frontmatter"
}

first_matching_line_number() {
  local text="$1"
  local needle="$2"

  awk -v needle="$needle" '
    index($0, needle) && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

first_matching_regex_line_number() {
  local text="$1"
  local regex="$2"

  awk -v regex="$regex" '
    $0 ~ regex && first == 0 {
      first = NR
    }

    END {
      if (first > 0) print first
    }
  ' <<< "$text"
}

check_literal_before_literal() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_line_number "$text" "$after")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_literal_before_regex() {
  local label="$1"
  local text="$2"
  local before="$3"
  local after_regex="$4"
  local before_line after_line

  before_line=$(first_matching_line_number "$text" "$before")
  after_line=$(first_matching_regex_line_number "$text" "$after_regex")

  if [ -n "$before_line" ] && [ -n "$after_line" ] && [ "$before_line" -lt "$after_line" ]; then
    pass "$label"
  else
    fail "$label"
  fi
}

extract_heading_block() {
  local file="$1"
  local heading="$2"
  local end_regex="$3"

  awk -v h="$heading" -v end_re="$end_regex" '
    function trim_line(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    {
      line=$0
      gsub(/\r/, "", line)
      trimmed=trim_line(line)

      if (trimmed == h) {
        found=1
        print line
        next
      }

      if (found && trimmed ~ end_re) {
        exit
      }

      if (found) {
        print line
      }
    }
  ' "$file"
}

block_contains_normalized() {
  local block="$1"
  local expected="$2"
  local normalized_block=""
  local normalized_expected=""

  normalized_block=$(printf '%s' "$block" | normalize_block_whitespace)
  normalized_expected=$(printf '%s' "$expected" | normalize_block_whitespace)
  [ -n "$normalized_expected" ] || return 1

  contains_literal "$normalized_block" "$normalized_expected"
}

has_allowed_tool() {
  local allowed="$1"
  local target="$2"

  printf '%s' "$allowed" | awk -v RS=',' -v target="$target" '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == target) found=1
    }
    END { exit(found ? 0 : 1) }
  '
}

first_trigger_line() {
  local file="$1"
  local positive_regex="$2"
  local negative_regex="${3:-}"

  awk -v pos="$positive_regex" -v neg="$negative_regex" '
    BEGIN { IGNORECASE=1; delim=0 }
    /^---$/ { delim++; next }
    delim < 2 { next }
    $0 ~ pos && (neg == "" || $0 !~ neg) { print; exit }
  ' "$file"
}

check_allowed_tool_match() {
  local base="$1"
  local allowed="$2"
  local file="$3"
  local tool="$4"
  local positive_regex="$5"
  local negative_regex="${6:-}"
  local trigger=""
  local snippet=""

  trigger=$(first_trigger_line "$file" "$positive_regex" "$negative_regex" || true)
  [ -n "$trigger" ] || return 0

  if has_allowed_tool "$allowed" "$tool"; then
    pass "$base: $tool in body matches allowed-tools"
    return 0
  fi

  snippet=$(trim "$trigger")
  snippet="${snippet//$'\t'/ }"
  snippet="${snippet//$'\r'/ }"
  if [ ${#snippet} -gt 140 ]; then
    snippet="${snippet:0:137}..."
  fi

  fail "$base: body references $tool but allowed-tools does not include it (trigger: $snippet)"
}


VERIFY_COMMANDS_MODULE_DIR="$ROOT/testing/verify-commands-contract"
. "$VERIFY_COMMANDS_MODULE_DIR/base-contracts.bash"
. "$VERIFY_COMMANDS_MODULE_DIR/installation-contracts.bash"
. "$VERIFY_COMMANDS_MODULE_DIR/verification-guardrails.bash"
. "$VERIFY_COMMANDS_MODULE_DIR/vibe-lifecycle.bash"
. "$VERIFY_COMMANDS_MODULE_DIR/qa-gating.bash"
. "$VERIFY_COMMANDS_MODULE_DIR/reference-contracts.bash"
echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All command contract checks passed."
exit 0
