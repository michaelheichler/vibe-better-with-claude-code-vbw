#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRICING_PATH="$SCRIPT_DIR/../config/model-pricing.json"
CACHE_KEY_LIB="$SCRIPT_DIR/lib/vbw-cache-key.sh"
hash_path() {
  bash -c '. "$1"; vbw_hash_path "$2"' _ "$CACHE_KEY_LIB" "$1"
}

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

MODEL_SHAPE='^[][A-Za-z0-9._:/-]+$'

if [ $# -ne 3 ]; then
  echo "Usage: resolve-agent-model.sh <agent-name> <config-path> <profiles-path>" >&2
  exit 1
fi

AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"

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
  echo "Model profiles not found at $PROFILES_PATH. Plugin installation issue." >&2
  exit 1
fi

_MODELS_BIN="${CLAUDE_CODE_EXECPATH:-$(command -v claude || true)}"
[ -f "$_MODELS_BIN" ] || _MODELS_BIN=""
_MODELS_SOURCE="$(bash -c '. "$1"; vbw_model_cache_source "$2" "$3"' _ "$CACHE_KEY_LIB" "$_MODELS_BIN" "$PRICING_PATH")"
_MODELS_CACHE="/tmp/vbw-models-$(hash_path "$_MODELS_SOURCE")"
if [ -n "${VBW_MODEL_CATALOG_FILE:-}" ]; then
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

CONFIG_HASH=$(file_content_fingerprint "$CONFIG_PATH")
PROFILES_HASH=$(file_content_fingerprint "$PROFILES_PATH")
if [ -f "$PRICING_PATH" ]; then
  PRICING_HASH=$(file_content_fingerprint "$PRICING_PATH")
else
  PRICING_HASH="none"
fi
PATH_HASH=$(hash_path "${CONFIG_PATH}|${PROFILES_PATH}")
CACHE_FILE="/tmp/vbw-model-${AGENT}-${PATH_HASH}-${CONFIG_HASH}-${PROFILES_HASH}-${MODELS_HASH}-${PRICING_HASH}"
if [ -f "$CACHE_FILE" ]; then
  _cached=$(cat "$CACHE_FILE")
  if [[ "$_cached" =~ $MODEL_SHAPE ]]; then
    echo "$_cached"
    exit 0
  fi
fi

CATALOG=""
CATALOG_EXTRA=""
CATALOG_LOADED=false
load_catalog() {
  if [ "$CATALOG_LOADED" = false ]; then
    printf -v CATALOG '%s' "$(bash "$SCRIPT_DIR/detect-models.sh" 2>/dev/null || true)"
    printf -v CATALOG_EXTRA '%s' "$(jq -r '(.model_catalog_extra // [])[]' "$CONFIG_PATH" 2>/dev/null || true)"
    printf -v CATALOG_LOADED '%s' true
  fi
}

candidates_from() {
  jq -r "($1) // empty | if type == \"array\" then .[] else . end" "$CONFIG_PATH" 2>/dev/null || true
}

resolve_alias() {
  local model="$1"
  case "$model" in
    opus|sonnet|haiku|fable|default)
      printf '%s\n' "$model"
      return 0
      ;;
  esac
  if [ -f "$PRICING_PATH" ]; then
    jq -r --arg m "$model" '.aliases[$m] // $m' "$PRICING_PATH" 2>/dev/null || printf '%s\n' "$model"
  else
    printf '%s\n' "$model"
  fi
}

resolve_catalog_alias() {
  local model="$1"
  if [ -f "$PRICING_PATH" ]; then
    jq -r --arg m "$model" '.aliases[$m] // $m' "$PRICING_PATH" 2>/dev/null || printf '%s\n' "$model"
  else
    printf '%s\n' "$model"
  fi
}

emit_catalog_choice() {
  local model="$1" canonical="$2"
  case "$model" in
    opus|sonnet|haiku|fable|default) printf '%s\n' "$model" ;;
    *) printf '%s\n' "$canonical" ;;
  esac
}

pick_catalog_model() {
  local candidates="$1" haystack="$2" c catalog_model
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    catalog_model=$(resolve_catalog_alias "$c")
    if grep -Fxq -- "$catalog_model" <<< "$haystack" || { case "$c" in opus|sonnet|haiku|fable|default) false ;; *) [ "$catalog_model" != "$c" ] ;; esac; }; then
      emit_catalog_choice "$c" "$catalog_model"
      return 0
    fi
  done <<< "$candidates"
}

pick_model() {
  local first="" count=0 c chosen=""
  local all=""
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    [ -z "$first" ] && first="$c"
    count=$((count + 1))
    all="${all}${c}"$'\n'
  done
  [ "$count" -eq 0 ] && return 0
  first=$(resolve_alias "$first")
  if [ "$count" -eq 1 ]; then
    echo "$first"
    return 0
  fi
  load_catalog
  if [ -n "$CATALOG" ]; then
    local haystack="${CATALOG}"$'\n'"${CATALOG_EXTRA}"
    chosen=$(pick_catalog_model "$all" "$haystack")

  fi
  echo "${chosen:-$first}"
}

EFFORT=$(jq -r '.effort // "balanced"' "$CONFIG_PATH")

MODEL=$(candidates_from ".model_overrides[\"$AGENT\"]" | pick_model)

if [ -z "$MODEL" ]; then
  MODEL=$(candidates_from ".model_matrix[\"$AGENT\"][\"$EFFORT\"]" | pick_model)
fi

if [ -z "$MODEL" ]; then
  PROFILE=$(jq -r '.model_profile // "quality"' "$CONFIG_PATH")
  if ! jq -e ".$PROFILE" "$PROFILES_PATH" >/dev/null 2>&1; then
    echo "Invalid model_profile '$PROFILE'. Valid: quality, balanced, budget" >&2
    exit 1
  fi
  MODEL=$(resolve_alias "$(jq -r ".$PROFILE.$AGENT" "$PROFILES_PATH")")
fi

if [[ "$MODEL" =~ $MODEL_SHAPE ]]; then
  echo "$MODEL"
  echo "$MODEL" > "$CACHE_FILE" 2>/dev/null || true
else
  echo "Invalid model '$MODEL' for $AGENT. Must be a single model id token." >&2
  exit 1
fi
