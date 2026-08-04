#!/usr/bin/env bash
# detect-models.sh: discover the model ids this Claude Code install accepts.
#
# The Claude Code binary is the SOLE primary source. It embeds the tier alias
# map, the model picker table, and the custom-model catalog string, so
# detection works offline with zero credentials and zero third-party calls.
# Patched binaries advertise injected models in the same structures.
#
# Usage: detect-models.sh [--labeled|--alias-map]
#   default      stdout = model ids, one per line
#   --labeled    stdout = id<TAB>description lines (for matrix proposals)
#   --alias-map  stdout = full-id<TAB>tier-alias lines, built-in tiers only
#                (opus/sonnet/haiku/fable). Spawn tools accept only the tier
#                alias for built-in models, not the full catalog id.
#
# Always exit 0. Empty output means "no catalog available" and callers fall
# back to static tier names.
#
# Env:
#   VBW_MODEL_CATALOG_FILE  test hook: cat this file and exit (no probing)
#   CLAUDE_CODE_EXECPATH    Claude Code binary (default: command -v claude)
#
# Results cached 1h at /tmp/vbw-models-<hash>. Failures are cached too. The
# cache identity carries the binary mtime and size, so a re-patched binary
# advertising a different catalog invalidates the cache on its next run.
# resolve-agent-model.sh mirrors this identity byte for byte.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_KEY_LIB="$SCRIPT_DIR/lib/vbw-cache-key.sh"
hash_path() {
  bash -c '. "$1"; vbw_hash_path "$2"' _ "$CACHE_KEY_LIB" "$1"
}

LABELED=""
[ "${1:-}" = "--labeled" ] && LABELED="1"
ALIAS_MAP=""
[ "${1:-}" = "--alias-map" ] && ALIAS_MAP="1"

if [ -n "${VBW_MODEL_CATALOG_FILE:-}" ]; then
  [ -n "$ALIAS_MAP" ] || cat "$VBW_MODEL_CATALOG_FILE" 2>/dev/null || true
  exit 0
fi

CLAUDE_BIN="${CLAUDE_CODE_EXECPATH:-$(command -v claude || true)}"
[ -f "$CLAUDE_BIN" ] || CLAUDE_BIN=""

BIN_STAMP="0:0"
if [ -n "$CLAUDE_BIN" ]; then
  BIN_STAMP="$(stat -f '%m:%z' "$CLAUDE_BIN" 2>/dev/null || stat -c '%Y:%s' "$CLAUDE_BIN" 2>/dev/null || echo 0:0)"
fi

SRC="bin:${CLAUDE_BIN:-none}:${BIN_STAMP}"
CACHE_SUFFIX="${LABELED:+-labeled}${ALIAS_MAP:+-aliasmap}"
CACHE="/tmp/vbw-models-$(hash_path "$SRC")${CACHE_SUFFIX}"
if [ -f "$CACHE" ] && [ -n "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
  cat "$CACHE"
  exit 0
fi

if [ -z "$CLAUDE_BIN" ]; then
  exit 0
fi

ENTRY='\{value:"[^"]+",label:"[^"]+",description:"[^"]+"\}'

extract_binary() {
  grep -aoE '(opus|sonnet|haiku|fable|default):"claude-[a-z0-9-]+"' "$CLAUDE_BIN" 2>/dev/null \
    | sed 's/^[a-z]*:"//; s/"$//; s/$/\tClaude (built-in)/' || true
  grep -aoE "${ENTRY}(,${ENTRY})*\]\.forEach" "$CLAUDE_BIN" 2>/dev/null \
    | grep -aoE 'value:"[^"]+",label:"[^"]+",description:"[^"]+"' \
    | sed 's/^value:"//; s/",label:"[^"]*",description:"/\t/; s/"$//' || true
  grep -aoE 'Additional custom models: [^`"]+' "$CLAUDE_BIN" 2>/dev/null \
    | sed 's/^Additional custom models: //; s/\.$//' | tr ';' '\n' \
    | sed 's/^ *//; s/ = /\t/' | grep -E '^[A-Za-z0-9._:/[-]+(\[1m\])?\t' || true
}

extract_alias_map() {
  grep -aoE '(opus|sonnet|haiku|fable):"claude-[a-z0-9-]+"' "$CLAUDE_BIN" 2>/dev/null \
    | sed -E 's/^([a-z]+):"(.*)"$/\2\t\1/' || true
}

TMP="$(mktemp "${CACHE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
if [ -n "$CLAUDE_BIN" ]; then
  if [ -n "$ALIAS_MAP" ]; then
    extract_alias_map >> "$TMP"
  else
    extract_binary >> "$TMP"
  fi
fi
if [ -n "$ALIAS_MAP" ]; then
  sort -u "$TMP" -o "$TMP" 2>/dev/null || true
elif [ -z "$LABELED" ]; then
  cut -f1 "$TMP" | sort -u > "${TMP}.ids" && mv "${TMP}.ids" "$TMP"
else
  sort -u "$TMP" -o "$TMP" 2>/dev/null || true
fi
mv "$TMP" "$CACHE" 2>/dev/null || true
trap - EXIT
cat "$CACHE" 2>/dev/null || true
exit 0
