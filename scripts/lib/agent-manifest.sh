#!/usr/bin/env bash
set -u

agent_manifest_path() {
  printf '%s/.agent-manifest.json\n' "${1:-.vbw-planning}"
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
    elif (.agents? | type) == "object" then .
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
