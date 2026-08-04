#!/usr/bin/env bash
set -u

vbw_orchestrator_marker_path() {
  local session_id="${1:-}"
  case "$session_id" in
    ''|*[!a-zA-Z0-9._-]*) return 1 ;;
  esac
  printf '/tmp/.vbw-orchestrator-instance-%s\n' "$session_id"
}

vbw_orchestrator_instance_id() {
  local session_id="${1:-}" marker instance_id owner mode current_uid
  marker=$(vbw_orchestrator_marker_path "$session_id") || return 1
  [ -f "$marker" ] || return 1
  [ ! -L "$marker" ] || return 1
  current_uid=$(id -u 2>/dev/null) || return 1
  owner=$(stat -c %u "$marker" 2>/dev/null || stat -f %u "$marker" 2>/dev/null || true)
  mode=$(stat -c %a "$marker" 2>/dev/null || stat -f %Lp "$marker" 2>/dev/null || true)
  [ "$owner" = "$current_uid" ] || return 1
  [ "$mode" = "600" ] || return 1
  instance_id=$(head -n 1 "$marker" | tr -d '[:space:]')
  [[ "$instance_id" =~ ^[0-9]+-[0-9]+-[0-9]+-[a-zA-Z0-9]+$ ]] || return 1
  printf '%s\n' "$instance_id"
}

vbw_orchestrator_write_marker() {
  local session_id="$1" marker instance_id tmp_dir tmp entropy
  marker=$(vbw_orchestrator_marker_path "$session_id") || return 1
  entropy=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')
  instance_id=$(printf '%s-%s-%s-%s' "$(date +%s 2>/dev/null || echo 0)" "${BASHPID:-$$}" "$RANDOM" "${entropy:-fallback}")
  tmp_dir=$(mktemp -d "${marker}.tmp.XXXXXX" 2>/dev/null) || return 1
  tmp="$tmp_dir/marker"
  if printf '%s\n' "$instance_id" > "$tmp" 2>/dev/null && chmod 600 "$tmp" 2>/dev/null && mv "$tmp" "$marker" 2>/dev/null; then
    rmdir "$tmp_dir" 2>/dev/null || true
    return 0
  fi
  rm -rf "$tmp_dir" 2>/dev/null || true
  return 1
}
