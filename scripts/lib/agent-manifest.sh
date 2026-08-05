#!/usr/bin/env bash
set -u

agent_manifest_path() {
  printf '%s/.agent-manifest.json\n' "${1:-.vbw-planning}"
}

agent_manifest_lock_path() {
  printf '%s/.agent-manifest.lock\n' "${1:-.vbw-planning}"
}

agent_manifest_acquire_lock() {
  local planning_dir="${1:-.vbw-planning}" lock_dir started now elapsed stale_seconds timeout mtime age
  lock_dir=$(agent_manifest_lock_path "$planning_dir")
  timeout="${VBW_AGENT_MANIFEST_LOCK_TIMEOUT:-10}"
  stale_seconds="${VBW_AGENT_MANIFEST_LOCK_STALE_SECONDS:-30}"
  case "$timeout" in ''|*[!0-9]*) timeout=10 ;; esac
  case "$stale_seconds" in ''|*[!0-9]*) stale_seconds=30 ;; esac
  mkdir -p "$planning_dir" 2>/dev/null || return 1
  started=$(date +%s 2>/dev/null || printf '0')
  while ! mkdir "$lock_dir" 2>/dev/null; do
    now=$(date +%s 2>/dev/null || printf '0')
    elapsed=$((now - started))
    if [ "$elapsed" -ge "$timeout" ]; then
      return 1
    fi
    mtime=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || printf '0')
    case "$mtime" in
      ''|*[!0-9]*|0) ;;
      *)
        age=$((now - mtime))
        if [ "$age" -gt "$stale_seconds" ]; then
          rmdir "$lock_dir" 2>/dev/null || true
        fi
        ;;
    esac
    sleep 0.01
  done
  return 0
}

agent_manifest_release_lock() {
  rmdir "$(agent_manifest_lock_path "${1:-.vbw-planning}")" 2>/dev/null || true
}

agent_manifest_with_lock() {
  local planning_dir="${1:-.vbw-planning}" callback="${2:-}" status
  shift 2 || return 1
  [ -n "$callback" ] || return 1
  agent_manifest_acquire_lock "$planning_dir" || return 1
  if "$callback" "$@"; then
    status=0
  else
    status=$?
  fi
  agent_manifest_release_lock "$planning_dir"
  return "$status"
}

agent_manifest_read() {
  local planning_dir="${1:-.vbw-planning}" path
  path=$(agent_manifest_path "$planning_dir")
  if [ ! -f "$path" ]; then
    printf '%s\n' '{"agents":{}}'
    return 0
  fi
  jq -ce '
    if type != "object" then error("manifest must be an object")
    elif has("agents") and (.agents | type) != "object" then error("manifest agents must be an object")
    elif has("agents") then .
    else {agents: .}
    end
  ' "$path"
}

agent_manifest_write() {
  local planning_dir="$1" manifest="$2" path tmp
  path=$(agent_manifest_path "$planning_dir")
  mkdir -p "$planning_dir" 2>/dev/null || return 1
  tmp="${path}.tmp.${BASHPID:-$$}"
  if ! printf '%s\n' "$manifest" | jq -ce 'select(type == "object" and (.agents | type) == "object")' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
  if mv -f "$tmp" "$path" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
  return 1
}

agent_manifest_safe_name() {
  case "${1:-}" in
    ''|.|..|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;;
  esac
}

agent_manifest_definition_path() {
  local planning_dir="$1" name="$2" project_root
  agent_manifest_safe_name "$name" || return 1
  project_root=$(cd "$planning_dir/.." 2>/dev/null && pwd -P) || return 1
  printf '%s/.claude/agents/%s.md\n' "$project_root" "$name"
}
