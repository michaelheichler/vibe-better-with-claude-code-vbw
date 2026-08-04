#!/usr/bin/env bash
set -u

vbw_guard_execution_is_live() {
  local project_root="${1:-}" planning_dir state_file status now mtime age marker_status marker_live
  planning_dir="$project_root/.vbw-planning"
  state_file="$planning_dir/.execution-state.json"
  if [ -f "$state_file" ]; then
    status=$(jq -r '.status // ""' "$state_file" 2>/dev/null) || status=""
    if [ "$status" = "running" ]; then
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

vbw_guard_enforcement_level() {
  local project_root="${1:-}" hook_input="${2:-}" session_id=""
  local planning_dir="${project_root}/.vbw-planning"
  [ -n "$project_root" ] || { printf 'off\n'; return 0; }
  [ -f "$planning_dir/config.json" ] || [ -d "$planning_dir/phases" ] || {
    printf 'off\n'
    return 0
  }
  if [ -n "${VBW_AGENT_ROLE:-}" ] || [ -n "${VBW_ACTIVE_AGENT:-}" ]; then
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
