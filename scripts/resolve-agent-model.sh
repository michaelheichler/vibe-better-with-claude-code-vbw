#!/usr/bin/env bash
# resolve-agent-model.sh - Model resolution for VBW agents
#
# Resolution precedence:
#   1. model_overrides.<agent> in config.json (string or preference array)
#   2. model_matrix.<agent>.<effort> in config.json (string or preference array)
#   3. model_profile preset from model-profiles.json (legacy tier table)
#
# Preference arrays resolve to the first entry present in the detected model
# catalog (scripts/detect-models.sh, 1h cache); when no catalog is available
# the first entry is trusted as-is. Single strings are emitted without an
# availability check: the matrix is written from a detected catalog at init
# time, so configured models are available by construction.
#
# Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>
#   agent-name: lead|dev|qa|scout|debugger|architect|docs
#   config-path: path to .vbw-planning/config.json
#   profiles-path: path to config/model-profiles.json
#
# Returns: stdout = model string (tier alias or full model id), exit 0
# Errors: stderr = error message, exit 1
#
# Integration pattern (from command files):
#   MODEL=$(bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-agent-model.sh lead .vbw-planning/config.json ${CLAUDE_PLUGIN_ROOT}/config/model-profiles.json)
#   if [ $? -ne 0 ]; then echo "Model resolution failed"; exit 1; fi
#   # Pass to Task tool: model: "${MODEL}"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/vbw-cache-key.sh
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

# Model ids must be a single clean token because they land in a `model:` Task
# param: letters, digits, dot, underscore, colon, slash, hyphen, brackets
# (gateway ids like `provider:model-x[1m]` are valid).
MODEL_SHAPE='^[][A-Za-z0-9._:/-]+$'

# Argument parsing
if [ $# -ne 3 ]; then
  echo "Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"

# Validate agent name
case "$AGENT" in
  lead|dev|qa|scout|debugger|architect|docs)
    # Valid agent
    ;;
  *)
    echo "Invalid agent name '$AGENT'. Valid: lead, dev, qa, scout, debugger, architect, docs" >&2
    exit 1
    ;;
esac

# Validate config file exists
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Config not found at $CONFIG_PATH. Run /vbw:init first." >&2
  exit 1
fi

# Validate profiles file exists
if [ ! -f "$PROFILES_PATH" ]; then
  echo "Model profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

# Locate the detected-catalog cache so its fingerprint can scope the
# resolution cache: a catalog refresh must invalidate cached resolutions.
# Source identity mirrors detect-models.sh; no probing happens here.
_MODELS_BASE="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
_MODELS_BASE="${_MODELS_BASE%/}"
_MODELS_AUTH=""
if [ -n "${ANTHROPIC_API_KEY:-}" ] || [ -n "${ANTHROPIC_AUTH_TOKEN:-}" ]; then
  _MODELS_AUTH="1"
fi
_MODELS_BIN="${CLAUDE_CODE_EXECPATH:-$(command -v claude || true)}"
[ -f "$_MODELS_BIN" ] || _MODELS_BIN=""
_MODELS_STAMP="0:0"
if [ -n "$_MODELS_BIN" ]; then
  _MODELS_STAMP="$(stat -f '%m:%z' "$_MODELS_BIN" 2>/dev/null || stat -c '%Y:%s' "$_MODELS_BIN" 2>/dev/null || echo 0:0)"
fi
_MODELS_CACHE="/tmp/vbw-models-$(vbw_hash_path "bin:${_MODELS_BIN:-none}:${_MODELS_STAMP}|${_MODELS_AUTH:+$_MODELS_BASE}")"
if [ -n "${VBW_MODEL_CATALOG_FILE:-}" ]; then
  # Test hook set: it fully overrides the live cache (detect-models.sh serves
  # it unconditionally), so fingerprint it, or "none" when it does not exist.
  if [ -f "$VBW_MODEL_CATALOG_FILE" ]; then
    MODELS_HASH=$(file_content_fingerprint "$VBW_MODEL_CATALOG_FILE")
  else
    MODELS_HASH="none"
  fi
elif [ -f "$_MODELS_CACHE" ]; then
  MODELS_HASH=$(file_content_fingerprint "$_MODELS_CACHE")
else
  MODELS_HASH="none"
fi

# Session-level cache: avoid repeated jq calls for the same agent + config pair.
# Scope by content fingerprints and path hash so parallel BATS workers
# using different temp repos cannot collide.
CONFIG_HASH=$(file_content_fingerprint "$CONFIG_PATH")
PROFILES_HASH=$(file_content_fingerprint "$PROFILES_PATH")
PATH_HASH=$(vbw_hash_path "${CONFIG_PATH}|${PROFILES_PATH}")
CACHE_FILE="/tmp/vbw-model-${AGENT}-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}-${MODELS_HASH}"
if [ -f "$CACHE_FILE" ]; then
  _cached=$(cat "$CACHE_FILE")
  if [[ "$_cached" =~ $MODEL_SHAPE ]]; then
    echo "$_cached"
    exit 0
  fi
  # Cache is corrupt or empty — fall through to recompute
fi

CATALOG=""
CATALOG_EXTRA=""
CATALOG_LOADED=false
load_catalog() {
  if [ "$CATALOG_LOADED" = false ]; then
    CATALOG=$(bash "$SCRIPT_DIR/detect-models.sh" 2>/dev/null) || CATALOG=""
    # model_catalog_extra: trusted ids treated as available even if undetected.
    CATALOG_EXTRA=$(jq -r '(.model_catalog_extra // [])[]' "$CONFIG_PATH" 2>/dev/null || true)
    CATALOG_LOADED=true
  fi
}

candidates_from() {
  # $1 = jq filter over config.json; prints one candidate per line
  jq -r "($1) // empty | if type == \"array\" then .[] else . end" "$CONFIG_PATH" 2>/dev/null || true
}

pick_model() {
  # stdin = candidate lines. Echoes the chosen model, or nothing.
  # Arrays prefer the first entry present in the detected catalog; a single
  # candidate (or an empty/unavailable catalog) is trusted as-is.
  local first="" count=0 c chosen=""
  local all=""
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    [ -z "$first" ] && first="$c"
    count=$((count + 1))
    all="${all}${c}"$'\n'
  done
  [ "$count" -eq 0 ] && return 0
  if [ "$count" -eq 1 ]; then
    echo "$first"
    return 0
  fi
  load_catalog
  if [ -n "$CATALOG" ]; then
    local haystack="${CATALOG}"$'\n'"${CATALOG_EXTRA}"
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      if grep -Fxq -- "$c" <<< "$haystack"; then
        chosen="$c"
        break
      fi
    done <<< "$all"
  fi
  echo "${chosen:-$first}"
}

EFFORT=$(jq -r '.effort // "balanced"' "$CONFIG_PATH")

# 1. Per-agent override
MODEL=$(candidates_from ".model_overrides[\"$AGENT\"]" | pick_model)

# 2. Agent x effort matrix (written at init from the detected catalog)
if [ -z "$MODEL" ]; then
  MODEL=$(candidates_from ".model_matrix[\"$AGENT\"][\"$EFFORT\"]" | pick_model)
fi

# 3. Legacy profile preset
if [ -z "$MODEL" ]; then
  PROFILE=$(jq -r '.model_profile // "quality"' "$CONFIG_PATH")
  if ! jq -e ".$PROFILE" "$PROFILES_PATH" >/dev/null 2>&1; then
    echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
    exit 1
  fi
  MODEL=$(jq -r ".$PROFILE.$AGENT" "$PROFILES_PATH")
fi

# Validate final model shape
if [[ "$MODEL" =~ $MODEL_SHAPE ]]; then
  echo "$MODEL"
  # Cache result for session reuse
  echo "$MODEL" > "$CACHE_FILE" 2>/dev/null || true
else
  echo "Invalid model '$MODEL' for $AGENT. Must be a single model id token." >&2
  exit 1
fi
