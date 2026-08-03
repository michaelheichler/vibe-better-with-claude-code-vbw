#!/bin/bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || ROOT=""

if [ -z "$ROOT" ] || [ ! -d "$ROOT/.git" ]; then
  exit 0
fi

mkdir -p "$ROOT/.git/hooks"

HOOK_PATH="$ROOT/.git/hooks/pre-push"

HOOK_CONTENT='#!/usr/bin/env bash
set -euo pipefail
_vbw_find_script() {
  local dirs=(
    "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    "$HOME/.config/claude-code"
  )
  for d in "${dirs[@]}"; do
    [ -z "$d" ] && continue
    local s
    s=$(ls -1 "$d"/plugins/cache/vbw-marketplace/vbw/*/scripts/pre-push-hook.sh 2>/dev/null | sort -V | tail -1 || true)
    [ -n "$s" ] && [ -f "$s" ] && echo "$s" && return 0
  done
  return 1
}
SCRIPT=$(_vbw_find_script || true)
if [ -n "$SCRIPT" ] && [ -f "$SCRIPT" ]; then
  exec bash "$SCRIPT" "$@"
fi
exit 0'

if [ -f "$HOOK_PATH" ]; then
  if [ -L "$HOOK_PATH" ]; then
    CURRENT_TARGET=$(readlink "$HOOK_PATH")
    if echo "$CURRENT_TARGET" | grep -q "pre-push-hook.sh"; then
      echo "$HOOK_CONTENT" > "$HOOK_PATH"
      chmod +x "$HOOK_PATH"
      echo "Upgraded pre-push hook to standalone script" >&2
    else
      echo "pre-push hook exists but is not managed by VBW -- skipping" >&2
    fi
  elif grep -q "VBW pre-push hook" "$HOOK_PATH" 2>/dev/null; then
    if ! grep -q "_vbw_find_script" "$HOOK_PATH" 2>/dev/null; then
      echo "$HOOK_CONTENT" > "$HOOK_PATH"
      chmod +x "$HOOK_PATH"
      echo "Upgraded pre-push hook to multi-location resolver" >&2
    else
      echo "pre-push hook already installed" >&2
    fi
  else
    echo "pre-push hook exists but is not managed by VBW -- skipping" >&2
  fi
else
  echo "$HOOK_CONTENT" > "$HOOK_PATH"
  chmod +x "$HOOK_PATH"
  echo "Installed pre-push hook" >&2
fi
