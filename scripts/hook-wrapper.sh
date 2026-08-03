#!/bin/bash

SCRIPT="$1"; shift
[ -z "$SCRIPT" ] && exit 0

cleanup_on_sighup() {
  PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
  if [ ! -d "$PLANNING_DIR" ]; then
    exit 1
  fi

  . "$(dirname "$0")/resolve-claude-dir.sh" 2>/dev/null || true
  CACHE="${CLAUDE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/plugins/cache/vbw-marketplace/vbw"
  TRACKER=$(ls -1 "$CACHE"/*/scripts/agent-pid-tracker.sh 2>/dev/null \
    | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

  if [ -z "$TRACKER" ] || [ ! -f "$TRACKER" ]; then
    _SIB_TRACKER="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/agent-pid-tracker.sh"
    [ -f "$_SIB_TRACKER" ] && TRACKER="$_SIB_TRACKER"
  fi

  if [ -z "$TRACKER" ] || [ ! -f "$TRACKER" ]; then
    exit 1
  fi

  LOG="$PLANNING_DIR/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  echo "[$TS] SIGHUP received, cleaning up agent PIDs" >> "$LOG" 2>/dev/null || true

  PIDS=$(bash "$TRACKER" list 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    for pid in $PIDS; do
      kill -TERM "$pid" 2>/dev/null || true
    done

    sleep 3
    for pid in $PIDS; do
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    done
  fi

  exit 1
}

trap cleanup_on_sighup SIGHUP

. "$(dirname "$0")/lib/vbw-config-root.sh"
find_vbw_root

VBW_DEBUG="${VBW_DEBUG:-0}"

_DBG_ENABLED=0
[ "$VBW_DEBUG" = "1" ] && _DBG_ENABLED=1
if [ "$_DBG_ENABLED" != "1" ] && [ -f "$VBW_PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  _DBG_VAL=$(jq -r '.debug_logging // false' "$VBW_PLANNING_DIR/config.json" 2>/dev/null || echo "false")
  case "$_DBG_VAL" in true|1) _DBG_ENABLED=1 ;; esac
fi

. "$(dirname "$0")/resolve-claude-dir.sh"
CACHE="$CLAUDE_DIR/plugins/cache/vbw-marketplace/vbw"
TARGET=$(ls -1 "$CACHE"/*/scripts/"$SCRIPT" 2>/dev/null \
  | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  TARGET="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/scripts/$SCRIPT}"
fi

if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
  _SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  [ -f "$_SELF_DIR/$SCRIPT" ] && TARGET="$_SELF_DIR/$SCRIPT"
fi
[ -z "$TARGET" ] || [ ! -f "$TARGET" ] && exit 0

[ "$VBW_DEBUG" = "1" ] && echo "[VBW DEBUG] hook-wrapper: $SCRIPT → $TARGET" >&2

if [ "$_DBG_ENABLED" = "1" ] && [ -d "$VBW_PLANNING_DIR" ]; then
  _DBG_LOG="$VBW_PLANNING_DIR/.hook-debug.log"
  _DBG_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  _DBG_TMP=$(mktemp 2>/dev/null || echo "/tmp/.vbw-hook-dbg-$$")
  bash "$TARGET" "$@" | tee "$_DBG_TMP"
  RC=${PIPESTATUS[0]}
  _DBG_OUTPUT=$(cat "$_DBG_TMP" 2>/dev/null)
  rm -f "$_DBG_TMP" 2>/dev/null
  {
    echo "${_DBG_TS} hook=${SCRIPT} exit=${RC}"
    if [ -n "$_DBG_OUTPUT" ]; then
      _DBG_B64=$(echo -n "$_DBG_OUTPUT" | base64 2>/dev/null | tr -d '\n' || echo "encode-failed")
      echo "${_DBG_TS} hook=${SCRIPT} output_base64=${_DBG_B64}"
    fi
  } >> "$_DBG_LOG" 2>/dev/null || true
  if [ -f "$_DBG_LOG" ]; then
    _DBG_LC=$(wc -l < "$_DBG_LOG" 2>/dev/null | tr -d ' ')
    [ "${_DBG_LC:-0}" -gt 200 ] && { tail -100 "$_DBG_LOG" > "${_DBG_LOG}.tmp" && mv "${_DBG_LOG}.tmp" "$_DBG_LOG"; } 2>/dev/null
  fi
else
  bash "$TARGET" "$@"
  RC=$?
fi
[ "$VBW_DEBUG" = "1" ] && [ "$RC" -ne 0 ] && echo "[VBW DEBUG] hook-wrapper: $SCRIPT exit=$RC" >&2
[ "$RC" -eq 0 ] && exit 0

[ "$RC" -eq 2 ] && exit 2

if [ -d "$VBW_PLANNING_DIR" ]; then
  LOG="$VBW_PLANNING_DIR/.hook-errors.log"
  TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '%s %s exit=%d\n' "$TS" "$SCRIPT" "$RC" >> "$LOG" 2>/dev/null
  if [ -f "$LOG" ]; then
    LC=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
    [ "${LC:-0}" -gt 50 ] && { tail -30 "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"; } 2>/dev/null
  fi
fi

exit 0
