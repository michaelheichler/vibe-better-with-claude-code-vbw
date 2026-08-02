#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_KEY="${CLAUDE_SESSION_ID:-default}"
L="/tmp/.vbw-plugin-root-link-${SESSION_KEY}"
P="/tmp/.vbw-phase-detect-${SESSION_KEY}.txt"
PTMP="${P}.tmp.$$"
LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"

refresh_phase_detect_link() {
  bash "$SCRIPT_DIR/resolve-plugin-root.sh" --require-script phase-detect.sh >/dev/null 2>&1 || return 1
  [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]
}

refresh_phase_detect_link || true

LOCKED=false
lock_retry_count=0
while [ $lock_retry_count -lt 100 ]; do
  if mkdir "$LOCK" 2>/dev/null; then
    LOCKED=true
    break
  fi
  sleep 0.1
  lock_retry_count=$((lock_retry_count + 1))
done

if [ "$LOCKED" = true ]; then
  bash "$L/scripts/phase-detect.sh" > "$PTMP" 2>/dev/null || printf '%s\n' 'phase_detect_error=true' > "$PTMP"
  mv "$PTMP" "$P"
  rmdir "$LOCK" 2>/dev/null || true
else
  cache_retry_count=0
  while [ $cache_retry_count -lt 100 ]; do
    [ -f "$P" ] && break
    sleep 0.1
    cache_retry_count=$((cache_retry_count + 1))
  done
  if [ ! -f "$P" ]; then
    printf '%s\n' 'phase_detect_error=true' > "$PTMP"
    mv "$PTMP" "$P"
  fi
fi

PD=""
phase_detect_start_ts=$(date +%s 2>/dev/null || echo 0)

phase_detect_cache_fresh() {
  local modified_at=""
  [ -f "$P" ] || return 1
  modified_at=$(stat -c %Y "$P" 2>/dev/null || stat -f %m "$P" 2>/dev/null || echo "")
  [ -n "$modified_at" ] || return 1
  [ "$modified_at" -ge "$phase_detect_start_ts" ] 2>/dev/null
}

phase_detect_cache_retryable() {
  [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]
}

freshness_retry_count=0
while [ $freshness_retry_count -lt 100 ]; do
  if phase_detect_cache_fresh; then
    PD=$(cat "$P")
    break
  fi
  sleep 0.1
  freshness_retry_count=$((freshness_retry_count + 1))
done

if phase_detect_cache_retryable; then
  refresh_phase_detect_link || true
fi

if phase_detect_cache_retryable && [ -L "$L" ] && [ -f "$L/scripts/phase-detect.sh" ]; then
  refresh_retry_count=0
  while [ $refresh_retry_count -lt 100 ]; do
    if phase_detect_cache_fresh; then
      PD=$(cat "$P")
      if ! phase_detect_cache_retryable; then
        break
      fi
    fi
    if mkdir "$LOCK" 2>/dev/null; then
      PTMP="${P}.reader.$$.$RANDOM"
      PD=$(bash "$L/scripts/phase-detect.sh" 2>/dev/null) || PD=""
      if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
        printf '%s\n' "$PD" > "$PTMP" 2>/dev/null && mv "$PTMP" "$P" 2>/dev/null || true
      fi
      rmdir "$LOCK" 2>/dev/null || true
      break
    fi
    sleep 0.1
    refresh_retry_count=$((refresh_retry_count + 1))
  done
fi

if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && phase_detect_cache_fresh; then
  PD=$(cat "$P")
fi

printf '%s\n' "$L"
if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
  printf '%s' "$PD"
else
  printf '%s\n' 'phase_detect_error=true'
fi
