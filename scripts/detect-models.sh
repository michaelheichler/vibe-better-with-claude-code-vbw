#!/usr/bin/env bash
# detect-models.sh - Discover the model ids available to this Claude Code install.
#
# Primary source: the Claude Code binary's embedded model alias table. It is
# authoritative for what the installed client accepts (patched binaries
# advertise injected gateway models there too) and needs no credentials.
# Supplement: when endpoint auth env exists, ${ANTHROPIC_BASE_URL}/v1/models
# is fetched and merged, because endpoint-mode gateways expose models the
# (unpatched) binary does not know about.
#
# Usage: detect-models.sh
#
# Returns: stdout = model ids (one per line), always exit 0.
#   Empty output means "no catalog available" and callers fall back to
#   static tier names.
#
# Env:
#   VBW_MODEL_CATALOG_FILE  test hook: cat this file and exit (no probing)
#   CLAUDE_CODE_EXECPATH    Claude Code binary (default: command -v claude)
#   ANTHROPIC_BASE_URL      endpoint base (default https://api.anthropic.com)
#   ANTHROPIC_API_KEY       sent as x-api-key
#   ANTHROPIC_AUTH_TOKEN    sent as Authorization: Bearer (when no api key)
#
# Results are cached for 1h per source at /tmp/vbw-models-<hash>. Failures
# are cached too (empty file) so a down endpoint costs one timeout per hour.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/vbw-cache-key.sh
. "$SCRIPT_DIR/lib/vbw-cache-key.sh"

if [ -n "${VBW_MODEL_CATALOG_FILE:-}" ]; then
  cat "$VBW_MODEL_CATALOG_FILE" 2>/dev/null || true
  exit 0
fi

BASE="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
BASE="${BASE%/}"

AUTH_HEADER=""
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  AUTH_HEADER="x-api-key: ${ANTHROPIC_API_KEY}"
elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN}"
fi

CLAUDE_BIN="${CLAUDE_CODE_EXECPATH:-$(command -v claude || true)}"
[ -f "$CLAUDE_BIN" ] || CLAUDE_BIN=""

if [ -z "$CLAUDE_BIN" ] && [ -z "$AUTH_HEADER" ]; then
  exit 0
fi

# Source identity mirrored in resolve-agent-model.sh (cache fingerprint).
SRC="bin:${CLAUDE_BIN:-none}|${AUTH_HEADER:+$BASE}"
CACHE="/tmp/vbw-models-$(vbw_hash_path "$SRC")"
if [ -f "$CACHE" ] && [ -n "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
  cat "$CACHE"
  exit 0
fi

fetch() {
  # Auth header via --config on stdin: the key must never hit argv/ps.
  curl -fsS --max-time 2 --config - "$1" 2>/dev/null <<EOF
header = "$AUTH_HEADER"
header = "anthropic-version: 2023-06-01"
EOF
}

TMP="$(mktemp "${CACHE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
if [ -n "$CLAUDE_BIN" ]; then
  # Reserved-alias entries pin the CURRENT model set; historic ids carry no
  # alias entry, which keeps this precise across binary versions.
  grep -aoE '(opus|sonnet|haiku|fable|default):"claude-[a-z0-9-]+"' "$CLAUDE_BIN" 2>/dev/null \
    | sed 's/^[a-z]*:"//; s/"$//' >> "$TMP" || true
  # Patched binaries inject gateway models as alias:"leverframe:provider:model".
  # Both sides route, so emit alias and canonical id.
  LF_ENTRIES=$(grep -aoE '[a-z0-9_.-]+:"leverframe:[^"]+"' "$CLAUDE_BIN" 2>/dev/null || true)
  if [ -n "$LF_ENTRIES" ]; then
    printf '%s\n' "$LF_ENTRIES" | sed 's/:".*//' >> "$TMP"
    printf '%s\n' "$LF_ENTRIES" | sed 's/^[^"]*"//; s/"$//' >> "$TMP"
  fi
fi
if [ -n "$AUTH_HEADER" ]; then
  # ponytail: no pagination follow, limit=1000 covers any realistic catalog
  { fetch "$BASE/v1/models?limit=1000" || fetch "$BASE/v1/models" || true; } \
    | jq -r '.data[]?.id // empty' 2>/dev/null >> "$TMP" || true
fi
sort -u "$TMP" -o "$TMP" 2>/dev/null || true
mv "$TMP" "$CACHE" 2>/dev/null || true
trap - EXIT
cat "$CACHE" 2>/dev/null || true
exit 0
