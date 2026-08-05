#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULTS_FILE="$ROOT/templates/agent-roles/defaults.json"
README_FILE="$ROOT/README.md"

PASS=0
FAIL=0

pass() {
  local message="$1"
  echo "PASS  $message"
  printf -v PASS '%d' "$((PASS + 1))"
}

fail() {
  local message="$1"
  echo "FAIL  $message"
  printf -v FAIL '%d' "$((FAIL + 1))"
}

check_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$label"
  else
    pass "$label"
  fi
}

markdown_table_cell() {
  local row="$1"
  local cell_index="$2"
  printf '%s\n' "$row" | awk -F'|' -v cell_index="$cell_index" '{ cell=$cell_index; gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell); print cell }'
}

normalize_tool_list() {
  local list="$1"
  printf '%s\n' "$list" \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed 's/^Explicit allowlist:[[:space:]]*//' \
    | sed 's/^Outside explicit allowlist:[[:space:]]*//' \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | awk 'NF { print }' \
    | LC_ALL=C sort
}

print_tool_lines() {
  local list="$1"
  [ -n "$list" ] && printf '%s\n' "$list"
}

compare_tool_lists() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [ "$actual" = "$expected" ]; then
    pass "$label"
  else
    fail "$label"
    printf 'EXPECTED:\n%s\nACTUAL:\n%s\n' "$expected" "$actual"
  fi
}

echo "=== Agent permissionMode Contract Verification ==="

AGENTS="vbw-scout vbw-qa vbw-dev vbw-lead vbw-architect vbw-debugger vbw-docs vbw-qa-author"

get_expected_mode() {
  case "$1" in
    vbw-scout|vbw-qa) echo "plan" ;;
    *) echo "acceptEdits" ;;
  esac
}

for agent in $AGENTS; do
  role="${agent#vbw-}"
  AGENT_FILE="$ROOT/templates/agent-roles/${role}.md.tpl"
  SHORT_NAME="$role"
  EXPECTED="$(get_expected_mode "$agent")"

  if [[ ! -f "$AGENT_FILE" ]] || ! jq -e --arg role "$role" '.[$role].permissionMode // empty' "$DEFAULTS_FILE" >/dev/null; then
    fail "${SHORT_NAME}: role template or permissionMode default missing"
    continue
  fi

  ACTUAL="$(jq -r --arg role "$role" '.[$role].permissionMode' "$DEFAULTS_FILE")"
  if [[ "$ACTUAL" == "$EXPECTED" ]]; then
    pass "${SHORT_NAME}: permissionMode is ${ACTUAL}"
  else
    fail "${SHORT_NAME}: permissionMode is ${ACTUAL} (expected: ${EXPECTED})"
  fi
done

README_DEV_ROW=$(grep -F '| **Dev** |' "$README_FILE" || true)
README_SCOUT_ROW=$(grep -F '| **Scout** |' "$README_FILE" || true)
README_PERMISSION_LEGEND=$(grep -F '**Denied / Omitted**' "$README_FILE" || true)
DEV_DESCRIPTION=$(jq -r '.dev.description' "$DEFAULTS_FILE")
DEV_DISALLOWED_FRONTMATTER=$(jq -r '.dev.disallowedTools // empty' "$DEFAULTS_FILE")
SCOUT_DISALLOWED_FRONTMATTER=$(jq -r '.scout.disallowedTools // empty' "$DEFAULTS_FILE")
README_DEV_DENIED_CELL=$(markdown_table_cell "$README_DEV_ROW" 5)
README_SCOUT_TOOLS_CELL=$(markdown_table_cell "$README_SCOUT_ROW" 4)
README_SCOUT_DENIED_CELL=$(markdown_table_cell "$README_SCOUT_ROW" 5)
DEV_DENIED_NORMALIZED=$(normalize_tool_list "$DEV_DISALLOWED_FRONTMATTER")
README_DENIED_NORMALIZED=$(normalize_tool_list "$README_DEV_DENIED_CELL")
SCOUT_DENIED_NORMALIZED=$(normalize_tool_list "$SCOUT_DISALLOWED_FRONTMATTER")
README_SCOUT_DENIED_NORMALIZED=$(normalize_tool_list "$README_SCOUT_DENIED_CELL")

if [[ -n "$README_DEV_ROW" ]]; then
  pass "README: Dev permission row exists"
else
  fail "README: Dev permission row missing"
fi

if [ -n "$DEV_DISALLOWED_FRONTMATTER" ]; then
  pass "templates/agent-roles/dev.md.tpl: frontmatter declares disallowedTools denylist"
else
  fail "templates/agent-roles/dev.md.tpl: frontmatter must declare disallowedTools denylist"
fi

if [[ -n "$README_SCOUT_ROW" ]]; then
  pass "README: Scout permission row exists"
else
  fail "README: Scout permission row missing"
fi

if [ -n "$SCOUT_DISALLOWED_FRONTMATTER" ]; then
  pass "templates/agent-roles/scout.md.tpl: frontmatter declares disallowedTools denylist"
else
  fail "templates/agent-roles/scout.md.tpl: frontmatter must declare disallowedTools denylist"
fi

check_not_contains "templates/agent-roles/dev.md.tpl: description no longer says explicit allowlist" "$DEV_DESCRIPTION" "explicit implementation tool allowlist"
check_contains "templates/agent-roles/dev.md.tpl: description mentions denylist-controlled tool access" "$DEV_DESCRIPTION" "denylist-controlled"

if jq -e '.dev | has("tools")' "$DEFAULTS_FILE" >/dev/null; then
  fail "templates/agent-roles/dev.md.tpl: frontmatter must not use a tools allowlist (use disallowedTools denylist for forward compatibility)"
else
  pass "templates/agent-roles/dev.md.tpl: frontmatter does not use a tools allowlist"
fi

for required_denied in Task TaskCreate Agent AskUserQuestion; do
  if grep -Fxq "$required_denied" <<<"$DEV_DENIED_NORMALIZED"; then
    pass "templates/agent-roles/dev.md.tpl: disallowedTools bans $required_denied"
  else
    fail "templates/agent-roles/dev.md.tpl: disallowedTools must ban $required_denied"
  fi
done

for must_not_deny in Bash Read Edit Write Glob Grep LSP Skill WebFetch WebSearch SendMessage TaskGet; do
  if grep -Fxq "$must_not_deny" <<<"$DEV_DENIED_NORMALIZED"; then
    fail "templates/agent-roles/dev.md.tpl: disallowedTools must not ban $must_not_deny (Dev relies on it)"
  else
    pass "templates/agent-roles/dev.md.tpl: disallowedTools does not ban $must_not_deny"
  fi
done

check_not_contains "README: Dev row no longer pins an explicit allowlist" "$README_DEV_ROW" "Explicit allowlist:"
check_not_contains "README: Dev row no longer says Outside explicit allowlist" "$README_DEV_ROW" "Outside explicit allowlist"
check_contains "README: Dev row uses inherited tools language" "$README_DEV_ROW" "Inherited (all except denied)"
compare_tool_lists "README: Dev denied tokens exactly match disallowedTools frontmatter" "$README_DENIED_NORMALIZED" "$DEV_DENIED_NORMALIZED"

for required_denied in Edit NotebookEdit Task TaskCreate Agent; do
  if grep -Fxq "$required_denied" <<<"$SCOUT_DENIED_NORMALIZED"; then
    pass "templates/agent-roles/scout.md.tpl: disallowedTools bans $required_denied"
  else
    fail "templates/agent-roles/scout.md.tpl: disallowedTools must ban $required_denied"
  fi
done

for must_not_deny in Bash Read Write Glob Grep LSP Skill WebFetch WebSearch; do
  if grep -Fxq "$must_not_deny" <<<"$SCOUT_DENIED_NORMALIZED"; then
    fail "templates/agent-roles/scout.md.tpl: disallowedTools must not ban $must_not_deny (Scout relies on it)"
  else
    pass "templates/agent-roles/scout.md.tpl: disallowedTools does not ban $must_not_deny"
  fi
done

check_contains "README: Scout row documents read-only Bash" "$README_SCOUT_TOOLS_CELL" "Bash is read-only live-validation only"
compare_tool_lists "README: Scout denied tokens exactly match disallowedTools frontmatter" "$README_SCOUT_DENIED_NORMALIZED" "$SCOUT_DENIED_NORMALIZED"

check_contains "README: permission legend mentions disallowedTools" "$README_PERMISSION_LEGEND" 'disallowedTools'

if grep -Fq 'Dev, Debugger' "$README_FILE" && grep -Fq 'Full access. The ones you actually worry about.' "$README_FILE"; then
  fail "README: permission model no longer groups Dev with full-access agents"
else
  pass "README: permission model no longer groups Dev with full-access agents"
fi

echo ""
echo "TOTAL  ${PASS} PASS, ${FAIL} FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
