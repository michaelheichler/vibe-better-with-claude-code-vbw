#!/usr/bin/env bash
# detect-models.sh - Discover model ids from the configured Anthropic-compatible endpoint.
#
# Queries ${ANTHROPIC_BASE_URL}/v1/models with whatever auth env exists and
# prints one model id per line. Works against api.anthropic.com or any
# Anthropic-compatible gateway; no gateway-specific logic.
#
# Usage: detect-models.sh
#
# Returns: stdout = model ids (one per line), always exit 0.
#   Empty output means "no catalog available" (no auth env, endpoint down,
#   or unparseable response) and callers fall back to static tier names.
#
# Env:
#   VBW_MODEL_CATALOG_FILE  test hook: cat this file and exit (no network)
#   ANTHROPIC_BASE_URL      endpoint base (default https://api.anthropic.com)
#   ANTHROPIC_API_KEY       sent as x-api-key
#   ANTHROPIC_AUTH_TOKEN    sent as Authorization: Bearer (when no api key)
#
# Results are cached for 1h per base URL at /tmp/vbw-models-<hash>. Failures
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

if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  AUTH_HEADER="x-api-key: ${ANTHROPIC_API_KEY}"
elif [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  AUTH_HEADER="Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN}"
else
  # Stock OAuth setup: no queryable credential in env. Static tiers apply.
  exit 0
fi

CACHE="/tmp/vbw-models-$(vbw_hash_path "$BASE")"
if [ -f "$CACHE" ] && [ -n "$(find "$CACHE" -mmin -60 2>/dev/null)" ]; then
  cat "$CACHE"
  exit 0
fi

fetch() {
  # Auth header goes through --config on stdin so the key never hits argv/ps.
  curl -fsS --max-time 2 --config - "$1" 2>/dev/null <<EOF
header = "$AUTH_HEADER"
header = "anthropic-version: 2023-06-01"
EOF
}

TMP="$(mktemp "${CACHE}.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
# ponytail: no pagination follow, limit=1000 covers any realistic catalog.
# Retry without the query param for gateways that reject unknown params.
{ fetch "$BASE/v1/models?limit=1000" || fetch "$BASE/v1/models" || true; } \
  | jq -r '.data[]?.id // empty' 2>/dev/null > "$TMP" || true
mv "$TMP" "$CACHE" 2>/dev/null || true
trap - EXIT
cat "$CACHE" 2>/dev/null || true
exit 0
