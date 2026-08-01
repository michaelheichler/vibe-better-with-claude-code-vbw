#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMANDS_DIR="$ROOT/commands"
RESOLVER="$ROOT/scripts/resolve-plugin-root.sh"
ENSURE_LINK="$ROOT/scripts/ensure-plugin-root-link.sh"
EXECUTE_PROTOCOL="$ROOT/references/execute-protocol.md"

PASS=0
FAIL=0

pass() {
  printf 'PASS  %s\n' "$1"
  declare -g PASS=$((PASS + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1"
  declare -g FAIL=$((FAIL + 1))
}

in_list() {
  local needle="$1"
  shift
  local item
  # Invariant: every visited item differs from needle. Variant: unvisited arguments.
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

TARGET_COMMANDS=(
  config.md debug.md discuss.md doctor.md fix.md help.md init.md map.md qa.md
  report.md research.md resume.md rtk.md skills.md status.md update.md verify.md vibe.md whats-new.md
)
EXEMPT_COMMANDS=(
  compress.md list-todos.md pause.md profile.md teach.md todo.md uninstall.md
)
PHASE_DETECT_COMMANDS=(discuss.md qa.md resume.md status.md verify.md vibe.md)
TARGET_FILES=()

printf '%s\n' '=== Plugin Root Shared Resolver Contract ==='

if [ -x "$RESOLVER" ]; then
  pass "shared resolver is executable"
else
  fail "shared resolver is missing or not executable"
fi

# Invariant: TARGET_FILES contains exactly the visited target commands. Variant: unvisited targets.
for rel in "${TARGET_COMMANDS[@]}"; do
  file="$COMMANDS_DIR/$rel"
  if [ -f "$file" ]; then
    TARGET_FILES+=("$file")
  else
    fail "$rel: target command is missing"
  fi
done

# Invariant: every visited tracked command is classified once. Variant: unvisited tracked commands.
while IFS= read -r rel; do
  base="${rel#commands/}"
  if in_list "$base" "${TARGET_COMMANDS[@]}"; then
    :
  elif in_list "$base" "${EXEMPT_COMMANDS[@]}"; then
    :
  else
    fail "$base: command is neither a resolver target nor an explicit exemption"
  fi
done < <(git -C "$ROOT" ls-files 'commands/*.md')

tracked_count=$(git -C "$ROOT" ls-files 'commands/*.md' | wc -l | tr -d '[:space:]')
classified_count=$((${#TARGET_COMMANDS[@]} + ${#EXEMPT_COMMANDS[@]}))
if [ "$tracked_count" -eq "$classified_count" ]; then
  pass "all $tracked_count tracked commands are classified (19 targets, 7 exemptions)"
else
  fail "command classification count mismatch: $tracked_count tracked, $classified_count classified"
fi

session_link_path='/tmp/.vbw-plugin-root-link-'
session_id_fallback='${CLAUDE_SESSION_ID:-default}'
root_fallback='${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh'
resolver_path='scripts/resolve-plugin-root.sh'
helper_execution='bash "$R"'
unreachable_helper_message='VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics.'

has_semantic_trampoline() {
  local preamble="$1"
  grep -Fq "$session_link_path" <<< "$preamble" &&
    grep -Fq "$session_id_fallback" <<< "$preamble" &&
    grep -Fq "$root_fallback" <<< "$preamble" &&
    grep -Fq "$resolver_path" <<< "$preamble" &&
    grep -Fq "$helper_execution" <<< "$preamble" &&
    grep -Fq "$unreachable_helper_message" <<< "$preamble"
}

# Invariant: every processed target has one semantic-contract result. Variant: unvisited target files.
for file in "${TARGET_FILES[@]}"; do
  base=$(basename "$file")
  preamble=$(grep -A2 -m1 '^Plugin root:$' "$file" || true)
  if has_semantic_trampoline "$preamble"; then
    pass "$base: delegates its preamble to resolve-plugin-root.sh"
  else
    fail "$base: missing the shared resolver trampoline contract"
  fi
done

bare_error_preamble='!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; bash "$R"; echo "VBW: plugin root resolution failed"`'
missing_fallback_preamble='!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; bash "$R"; echo "VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics."`'
if has_semantic_trampoline "$bare_error_preamble"; then
  fail "semantic contract accepts the legacy bare error"
else
  pass "semantic contract rejects the legacy bare error"
fi
if has_semantic_trampoline "$missing_fallback_preamble"; then
  fail "semantic contract accepts a missing CLAUDE_PLUGIN_ROOT fallback"
else
  pass "semantic contract rejects a missing CLAUDE_PLUGIN_ROOT fallback"
fi

legacy_matches=$(grep -nE 'plugins/marketplaces|ps axww|VBW_CACHE_ROOT=|sort -t\.|grep -oE -- "--plugin-dir' \
  "${TARGET_FILES[@]}" "$EXECUTE_PROTOCOL" 2>/dev/null || true)
if [ -z "$legacy_matches" ]; then
  pass "target commands and execute protocol contain no legacy cascade fragments"
else
  fail "legacy inline cascade fragments remain"
  printf '%s\n' "$legacy_matches"
fi

if grep -Fq 'VBW_PLUGIN_ROOT=$(bash "$RESOLVER") || exit 1' "$EXECUTE_PROTOCOL" &&
  grep -Fq 'scripts/resolve-plugin-root.sh' "$EXECUTE_PROTOCOL"; then
  pass "execute-protocol delegates runtime resolution to the shared helper"
else
  fail "execute-protocol is missing the shared-helper invocation"
fi

declare -A expected_refresh_counts=(
  [discuss.md]=1
  [qa.md]=1
  [resume.md]=1
  [status.md]=1
  [verify.md]=2
  [vibe.md]=1
)
# Invariant: every visited phase command has its expected delegated refreshes. Variant: unvisited phase commands.
for rel in "${PHASE_DETECT_COMMANDS[@]}"; do
  count=$(grep -c -- '--require-script phase-detect.sh' "$COMMANDS_DIR/$rel" || true)
  if [ "$count" -eq "${expected_refresh_counts[$rel]}" ]; then
    pass "$rel: $count phase-detect refresh site(s) delegate with --require-script"
  else
    fail "$rel: expected ${expected_refresh_counts[$rel]} delegated refresh site(s), found $count"
  fi
done

for needle in \
  'LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"' \
  'while [ $i -lt 100 ]' \
  'mkdir "$LOCK"' \
  'mv "$PTMP" "$P"'
do
  if grep -Fq "$needle" "$COMMANDS_DIR/vibe.md"; then
    pass "vibe.md preserves phase-detect locking contract: $needle"
  else
    fail "vibe.md lost phase-detect locking contract: $needle"
  fi
done

if grep -Fq -- '--nonfatal' "$COMMANDS_DIR/rtk.md" &&
  grep -Fq '"status_unavailable":true' "$COMMANDS_DIR/rtk.md"; then
  pass "rtk.md preserves nonfatal status_unavailable behavior"
else
  fail "rtk.md is missing --nonfatal or status_unavailable"
fi

legacy_temp_matches=$(grep -nE 'cat /tmp/\.vbw-plugin-root([^-/]|$)|printf.*> /tmp/\.vbw-plugin-root([^-/]|$)' \
  "${TARGET_FILES[@]}" "$EXECUTE_PROTOCOL" 2>/dev/null || true)
if [ -z "$legacy_temp_matches" ]; then
  pass "no target uses the legacy shared plugin-root temp file"
else
  fail "legacy shared plugin-root temp-file usage remains"
  printf '%s\n' "$legacy_temp_matches"
fi

printf '\n%s\n' '=== Shared Resolver Behavioral Smoke ==='
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vbw-root-contract.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TEST_DIR/bin/ps"
chmod +x "$TEST_DIR/bin/ps"

make_root() {
  local name="$1"
  local root="$TEST_DIR/roots/$name"
  mkdir -p "$root/scripts" "$root/commands"
  : > "$root/scripts/hook-wrapper.sh"
  : > "$root/commands/vibe.md"
  cp "$ENSURE_LINK" "$root/scripts/ensure-plugin-root-link.sh"
  (cd "$root" && pwd -P)
}

explicit_root=$(make_root explicit)
local_root=$(make_root local)
wrong_root=$(make_root wrong)
explicit_alias="$TEST_DIR/explicit-alias"
cache_root="$TEST_DIR/cache-precedence"
tmp_root="$TEST_DIR/tmp-precedence"
config_root="$TEST_DIR/config-precedence"
session_id="contract-precedence-$$"
session_link="$tmp_root/.vbw-plugin-root-link-$session_id"
mkdir -p "$cache_root" "$tmp_root" "$config_root"
ln -s "$explicit_root" "$explicit_alias"
ln -s "$local_root" "$cache_root/local"
ln -s "$wrong_root" "$session_link"

if output=$(CLAUDE_PLUGIN_ROOT="$explicit_alias" CLAUDE_CONFIG_DIR="$config_root" \
  VBW_CACHE_ROOT="$cache_root" VBW_TMP_ROOT="$tmp_root" CLAUDE_SESSION_ID="$session_id" \
  PATH="$TEST_DIR/bin:$PATH" bash "$RESOLVER" 2>&1); then
  if [ "$output" = "$explicit_root" ] && [ -L "$session_link" ] &&
    [ "$(readlink "$session_link")" = "$explicit_root" ]; then
    pass "explicit root wins, canonicalizes, and repairs the session link"
  else
    fail "precedence/canonicalization/link repair returned unexpected state: $output"
  fi
else
  fail "explicit-root behavioral smoke failed: $output"
fi

marketplace_root=$(make_root marketplace)
market_config="$TEST_DIR/config-marketplace"
market_cache="$TEST_DIR/cache-marketplace"
market_tmp="$TEST_DIR/tmp-marketplace"
market_session="contract-marketplace-$$"
market_link="$market_tmp/.vbw-plugin-root-link-$market_session"
mkdir -p "$market_config/plugins/marketplaces" "$market_cache" "$market_tmp"
ln -s "$marketplace_root" "$market_config/plugins/marketplaces/vbw-marketplace"

if output=$(CLAUDE_PLUGIN_ROOT="" CLAUDE_CONFIG_DIR="$market_config" \
  VBW_CACHE_ROOT="$market_cache" VBW_TMP_ROOT="$market_tmp" CLAUDE_SESSION_ID="$market_session" \
  PATH="$TEST_DIR/bin:$PATH" bash "$RESOLVER" 2>&1); then
  if [ "$output" = "$marketplace_root" ] && [ -L "$market_link" ]; then
    pass "marketplace-root fallback resolves and creates the session link"
  else
    fail "marketplace-root fallback returned unexpected state: $output"
  fi
else
  fail "marketplace-root behavioral smoke failed: $output"
fi

empty_config="$TEST_DIR/config-empty"
empty_cache="$TEST_DIR/cache-empty"
empty_tmp="$TEST_DIR/tmp-empty"
mkdir -p "$empty_config" "$empty_cache" "$empty_tmp"
if output=$(CLAUDE_PLUGIN_ROOT="" CLAUDE_CONFIG_DIR="$empty_config" \
  VBW_CACHE_ROOT="$empty_cache" VBW_TMP_ROOT="$empty_tmp" CLAUDE_SESSION_ID="contract-failure-$$" \
  PATH="$TEST_DIR/bin:$PATH" bash "$RESOLVER" 2>&1); then
  fail "fatal resolver unexpectedly succeeded: $output"
else
  status=$?
  if [ "$status" -eq 1 ] && [ "$output" = "VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics." ]; then
    pass "fatal resolution failure preserves exit 1 and diagnostic"
  else
    fail "fatal resolution failure returned status $status and output: $output"
  fi
fi

if output=$(CLAUDE_PLUGIN_ROOT="" CLAUDE_CONFIG_DIR="$empty_config" \
  VBW_CACHE_ROOT="$empty_cache" VBW_TMP_ROOT="$empty_tmp" CLAUDE_SESSION_ID="contract-nonfatal-$$" \
  PATH="$TEST_DIR/bin:$PATH" bash "$RESOLVER" --nonfatal 2>&1); then
  if [ -z "$output" ]; then
    pass "nonfatal resolution failure exits zero with empty output"
  else
    fail "nonfatal resolution failure emitted output: $output"
  fi
else
  status=$?
  fail "nonfatal resolution failure returned status $status"
fi

printf '\n===============================\n'
printf 'TOTAL: %s PASS, %s FAIL\n' "$PASS" "$FAIL"
printf '===============================\n'

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

printf '%s\n' 'All plugin root shared resolver checks passed.'
