#!/usr/bin/env bash
set -u

vbw_guard_execution_is_live() {
  local project_root="${1:-}" planning_dir state_file exec_status now mtime age marker_status marker_live
  planning_dir="$project_root/.vbw-planning"
  state_file="$planning_dir/.execution-state.json"
  if [ -f "$state_file" ]; then
    exec_status=$(jq -r '.status // ""' "$state_file" 2>/dev/null) || exec_status=""
    if [ "$exec_status" = "running" ]; then
      now=$(date +%s 2>/dev/null || echo 0)
      if [ "$(uname)" = "Darwin" ]; then
        mtime=$(stat -f %m "$state_file" 2>/dev/null || echo 0)
      else
        mtime=$(stat -c %Y "$state_file" 2>/dev/null || echo 0)
      fi
      age=$((now - mtime))
      if [ "$age" -ge 0 ] && [ "$age" -lt 14400 ]; then
        return 0
      fi
    fi
  fi
  if [ -f "$planning_dir/.delegated-workflow.json" ]; then
    marker_status=$(VBW_PLANNING_DIR="$planning_dir" bash "$(dirname "${BASH_SOURCE[0]}")/../delegated-workflow.sh" status-json 2>/dev/null) || marker_status=""
    marker_live=$(printf '%s' "$marker_status" | jq -r '.live // false' 2>/dev/null) || marker_live="false"
    [ "$marker_live" = "true" ] && return 0
  fi
  return 1
}

vbw_guard_project_root() {
  local start_dir="${1:-$PWD}" dir
  if [ -n "${VBW_CONFIG_ROOT:-}" ] && {
    [ -f "$VBW_CONFIG_ROOT/.vbw-planning/config.json" ] ||
    [ -d "$VBW_CONFIG_ROOT/.vbw-planning/phases" ];
  }; then
    printf '%s\n' "$VBW_CONFIG_ROOT"
    return 0
  fi
  dir=$(cd "$start_dir" 2>/dev/null && pwd -P) || return 1
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.vbw-planning/config.json" ] || [ -d "$dir/.vbw-planning/phases" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

vbw_guard_agent_role_present() {
  local hook_input="${1:-}" candidate payload_type payload_id
  for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
    [ -n "$candidate" ] || continue
    vbw_active_agent_normalize_role "$candidate" >/dev/null 2>&1 && return 0
  done
  payload_type=$(printf '%s' "$hook_input" | jq -r '.agent_type // ""' 2>/dev/null) || payload_type=""
  payload_id=$(printf '%s' "$hook_input" | jq -r '.agent_id // .agent_name // .agentName // ""' 2>/dev/null) || payload_id=""
  for candidate in "$payload_type" "$payload_id"; do
    [ -n "$candidate" ] || continue
    vbw_active_agent_normalize_payload_role "$candidate" >/dev/null 2>&1 && return 0
  done
  return 1
}

vbw_guard_enforcement_level() {
  local project_root="${1:-}" hook_input="${2:-}" session_id=""
  local planning_dir="${project_root}/.vbw-planning"
  [ -n "$project_root" ] || { printf 'off\n'; return 0; }
  [ -f "$planning_dir/config.json" ] || [ -d "$planning_dir/phases" ] || {
    printf 'off\n'
    return 0
  }
  if vbw_guard_agent_role_present "$hook_input"; then
    printf 'enforce\n'
    return 0
  fi
  if vbw_guard_execution_is_live "$project_root"; then
    printf 'enforce\n'
    return 0
  fi
  if command -v vbw_active_agent_session_id >/dev/null 2>&1; then
    session_id=$(vbw_active_agent_session_id "$hook_input" 2>/dev/null) || session_id="${CLAUDE_SESSION_ID:-}"
  else
    session_id="${CLAUDE_SESSION_ID:-}"
  fi
  if [ -n "$session_id" ] && command -v vbw_orchestrator_instance_id >/dev/null 2>&1 && \
     vbw_orchestrator_instance_id "$session_id" >/dev/null 2>&1; then
    printf 'enforce\n'
    return 0
  fi
  printf 'advisory\n'
}

