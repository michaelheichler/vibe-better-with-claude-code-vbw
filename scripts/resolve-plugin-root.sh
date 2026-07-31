#!/usr/bin/env bash
set -euo pipefail

# R: success prints the canonical first valid root and repairs its exact session link. Failure follows the selected fatal or nonfatal contract.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/resolve-claude-dir.sh"

required_script="hook-wrapper.sh"
nonfatal=false

# Invariant: parsed options are valid and remaining arguments are untouched. Variant: $# decreases.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --require-script)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        echo "Usage: resolve-plugin-root.sh [--require-script <name>] [--nonfatal]" >&2
        exit 2
      fi
      required_script="$2"
      shift 2
      ;;
    --nonfatal)
      nonfatal=true
      shift
      ;;
    *)
      echo "Usage: resolve-plugin-root.sh [--require-script <name>] [--nonfatal]" >&2
      exit 2
      ;;
  esac
done

case "$required_script" in
  */* | . | ..)
    echo "resolve-plugin-root.sh: --require-script expects a script name" >&2
    exit 2
    ;;
esac

fail_resolution() {
  if [ "$nonfatal" = true ]; then
    exit 0
  fi
  echo "VBW: plugin root resolution failed" >&2
  exit 1
}

fail_link() {
  if [ "$nonfatal" = true ]; then
    exit 0
  fi
  echo "VBW: plugin root link failed" >&2
  exit 1
}

valid_root() {
  local candidate="${1:-}"
  [ -n "$candidate" ] &&
    [ -d "$candidate" ] &&
    [ -f "$candidate/scripts/$required_script" ]
}

export LC_ALL=C
cache_root="${VBW_CACHE_ROOT:-$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw}"
marketplaces_root="$CLAUDE_DIR/plugins/marketplaces"
tmp_root="${VBW_TMP_ROOT:-/tmp}"
session_key="${CLAUDE_SESSION_ID:-default}"
session_link="$tmp_root/.vbw-plugin-root-link-${session_key}"
resolved_root=""

if valid_root "${CLAUDE_PLUGIN_ROOT:-}"; then
  resolved_root="$CLAUDE_PLUGIN_ROOT"
fi

if [ -z "$resolved_root" ] && valid_root "$cache_root/local"; then
  resolved_root="$cache_root/local"
fi

if [ -z "$resolved_root" ]; then
  numeric_names=()
  # Invariant: numeric_names equals the numeric entries examined. Variant: unexamined cache entries decrease.
  for candidate in "$cache_root"/*; do
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      continue
    fi
    name="${candidate##*/}"
    if [[ "$name" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
      numeric_names+=("$name")
    fi
  done
  if [ "${#numeric_names[@]}" -gt 0 ]; then
    numeric_name=$(printf '%s\n' "${numeric_names[@]}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
    if valid_root "$cache_root/$numeric_name"; then
      resolved_root="$cache_root/$numeric_name"
    fi
  fi
fi

if [ -z "$resolved_root" ]; then
  generic_names=()
  # Invariant: generic_names equals the cache entries examined. Variant: unexamined cache entries decrease.
  for candidate in "$cache_root"/*; do
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
      generic_names+=("${candidate##*/}")
    fi
  done
  if [ "${#generic_names[@]}" -gt 0 ]; then
    generic_name=$(printf '%s\n' "${generic_names[@]}" | sort | tail -1)
    if valid_root "$cache_root/$generic_name"; then
      resolved_root="$cache_root/$generic_name"
    fi
  fi
fi

if [ -z "$resolved_root" ]; then
  # Invariant: no examined marketplace entry is valid. Variant: unexamined marketplace entries decrease.
  for candidate in "$marketplaces_root"/* "$marketplaces_root"/*/*; do
    if valid_root "$candidate" && [ -f "$candidate/commands/vibe.md" ]; then
      resolved_root="$candidate"
      break
    fi
  done
fi

if [ -z "$resolved_root" ] && valid_root "$session_link"; then
  resolved_root="$session_link"
fi

if [ -z "$resolved_root" ]; then
  # Invariant: no examined generic session link is valid. Variant: unexamined temp entries decrease.
  for candidate in "$tmp_root"/.vbw-plugin-root-link-*; do
    if valid_root "$candidate"; then
      resolved_root="$candidate"
      break
    fi
  done
fi

if [ -z "$resolved_root" ]; then
  process_plugin_dir=$(ps axww -o args= 2>/dev/null | grep -v grep | grep -oE -- "--plugin-dir [^ ]+" | head -1 || true)
  process_plugin_dir="${process_plugin_dir#--plugin-dir }"
  if valid_root "$process_plugin_dir"; then
    resolved_root="$process_plugin_dir"
  fi
fi

[ -n "$resolved_root" ] || fail_resolution
canonical_root=$(cd "$resolved_root" 2>/dev/null && pwd -P) || fail_resolution

if ! bash "$canonical_root/scripts/ensure-plugin-root-link.sh" \
  "$session_link" "$canonical_root" >/dev/null 2>&1; then
  fail_link
fi

printf '%s\n' "$canonical_root"
