#!/usr/bin/env bash
# resolve-agent-reasoning.sh: reasoning-effort resolution for VBW agents.
#
# Precedence (mirrors resolve-agent-model.sh):
#   1. reasoning_overrides.<agent>
#   2. reasoning_matrix.<agent>.<effort>
#   3. model_profile preset from reasoning-profiles.json
#
# The result is reconciled against the agent's resolved model, because sending
# an unsupported effort is a hard API error rather than a no-op.
#
# Usage: resolve-agent-reasoning.sh <agent> <config-path> <profiles-path> [model] [pricing-path]
# Returns: stdout = effort value, or empty when the parameter must be omitted.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/vbw-cache-key.sh"

file_content_fingerprint() {
  local file_path="$1"

  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file_path" | awk '{print $1}' | cut -c1-8
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file_path" | cut -c1-8
  else
    cksum "$file_path" | awk '{print $1}'
  fi
}

REASONING_SHAPE='^(none|minimal|low|medium|high|xhigh|max)$'

if [ $# -lt 3 ] || [ $# -gt 5 ]; then
  echo "Usage: resolve-agent-reasoning.sh <agent> <config-path> <profiles-path> [model] [pricing-path]" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"
MODEL="${4:-}"
PRICING_PATH="${5:-$(dirname "$PROFILES_PATH")/model-pricing.json}"

case "$AGENT" in
  lead|dev|qa|scout|debugger|architect|docs)
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect, docs" >&2
    exit 1
    ;;
esac

if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /vbw:init first." >&2
  exit 1
fi

if [ ! -f "$PROFILES_PATH" ]; then
  echo "Reasoning profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

CONFIG_HASH=$(file_content_fingerprint "$CONFIG_PATH")
PROFILES_HASH=$(file_content_fingerprint "$PROFILES_PATH")
PRICING_HASH="none"
if [ -f "$PRICING_PATH" ]; then
  PRICING_HASH=$(file_content_fingerprint "$PRICING_PATH")
fi
PATH_HASH=$(vbw_hash_path "${CONFIG_PATH}|${PROFILES_PATH}|${PRICING_PATH}|${MODEL}")
CACHE_FILE="/tmp/vbw-reasoning-${AGENT}-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}-${PRICING_HASH}"
if [ -f "$CACHE_FILE" ]; then
  _cached=$(cat "$CACHE_FILE")
  if [ -z "$_cached" ] || [[ "$_cached" =~ $REASONING_SHAPE ]]; then
    echo "$_cached"
    exit 0
  fi
fi

EFFORT=$(jq -r '.effort // "balanced"' "$CONFIG_PATH")

REASONING=$(jq -r ".reasoning_overrides[\"$AGENT\"] // empty" "$CONFIG_PATH" 2>/dev/null || true)

if [ -z "$REASONING" ]; then
  REASONING=$(jq -r ".reasoning_matrix[\"$AGENT\"][\"$EFFORT\"] // empty" "$CONFIG_PATH" 2>/dev/null || true)
fi

if [ -z "$REASONING" ]; then
  PROFILE=$(jq -r '.model_profile // "quality"' "$CONFIG_PATH")
  if ! jq -e --arg p "$PROFILE" 'has($p)' "$PROFILES_PATH" >/dev/null 2>&1; then
    echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
    exit 1
  fi
  REASONING=$(jq -r --arg p "$PROFILE" --arg a "$AGENT" '.[$p][$a] // empty' "$PROFILES_PATH")
fi

if [ -z "$REASONING" ]; then
  echo ""
  echo "" > "$CACHE_FILE" 2>/dev/null || true
  exit 0
fi

if ! [[ "$REASONING" =~ $REASONING_SHAPE ]]; then
  echo "Invalid reasoning effort '$REASONING' for $AGENT. Valid: none, minimal, low, medium, high, xhigh, max" >&2
  exit 1
fi

if [ -n "$MODEL" ] && [ -f "$PRICING_PATH" ]; then
  CANONICAL=$(jq -r --arg m "$MODEL" '.aliases[$m] // $m' "$PRICING_PATH" 2>/dev/null || echo "$MODEL")
  if jq -e --arg m "$CANONICAL" '.models | has($m)' "$PRICING_PATH" >/dev/null 2>&1; then
    SUPPORTED=$(jq -r --arg m "$CANONICAL" '(.models[$m].reasoning_efforts // []) | join(" ")' "$PRICING_PATH")
    if [ -z "$SUPPORTED" ]; then
      REASONING=""
    elif ! grep -qw -- "$REASONING" <<< "$SUPPORTED"; then
      REASONING=$(jq -r --arg m "$CANONICAL" '.models[$m].reasoning_default // ""' "$PRICING_PATH")
      [ "$REASONING" = "null" ] && REASONING=""
    fi
  fi
fi

echo "$REASONING"
echo "$REASONING" > "$CACHE_FILE" 2>/dev/null || true
