#!/usr/bin/env bash
set -u

VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID="__vbw_legacy_global"

vbw_active_agent_is_safe_session_id() {
  local sid="${1:-}"
  [ -n "$sid" ] && [ "$sid" != "null" ] && [ "$sid" != "unknown" ] || return 1
  [ "$sid" != "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID" ] || return 1
  case "$sid" in .|..|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-]*) return 1 ;; esac
}

vbw_active_agent_session_id() {
  local input="${1:-}" sid=""
  if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
    sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null) || sid=""
    if vbw_active_agent_is_safe_session_id "$sid"; then printf '%s\n' "$sid"; return 0; fi
  fi
  sid="${CLAUDE_SESSION_ID:-}"
  if vbw_active_agent_is_safe_session_id "$sid"; then printf '%s\n' "$sid"; return 0; fi
  return 1
}

_vbw_active_agent_legacy_source_id() { printf '%s\n' "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID"; }
_vbw_active_agent_is_aggregate_source_id() {
  [ "${1:-}" = "$VBW_ACTIVE_AGENT_LEGACY_SOURCE_ID" ] && return 0
  vbw_active_agent_is_safe_session_id "${1:-}"
}
vbw_active_agent_has_safe_session() { vbw_active_agent_session_id "${1:-}" >/dev/null 2>&1; }

vbw_active_agent_normalize_strict_role() {
  local lower="${1:-}" role suffix
  for role in lead dev qa qa-author scout debugger architect docs; do
    case "$lower" in
      "vbw-$role") printf '%s' "$role"; return 0 ;;
      "vbw-$role-"*)
        suffix="${lower#vbw-$role-}"
        case "$suffix" in ''|*[!0-9]*) continue ;; esac
        printf '%s' "$role"
        return 0
        ;;
    esac
  done
  return 1
}

vbw_active_agent_normalize_role() {
  local lower
  lower=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  lower="${lower#@}"
  lower="${lower#vbw:}"
  if [[ "$lower" == vbw-* ]]; then
    vbw_active_agent_normalize_strict_role "$lower"
    return
  fi
  case "$lower" in
    vbw-lead|vbw-lead-*|lead|lead-*|team-lead|team-lead-*) printf 'lead'; return 0 ;;
    vbw-dev|vbw-dev-*|dev|dev-*|team-dev|team-dev-*) printf 'dev'; return 0 ;;
    vbw-qa-author|vbw-qa-author-*|qa-author|qa-author-*|team-qa-author|team-qa-author-*) printf 'qa-author'; return 0 ;;
    vbw-qa|vbw-qa-*|qa|qa-*|team-qa|team-qa-*) printf 'qa'; return 0 ;;
    vbw-scout|vbw-scout-*|scout|scout-*|team-scout|team-scout-*) printf 'scout'; return 0 ;;
    vbw-debugger|vbw-debugger-*|debugger|debugger-*|team-debugger|team-debugger-*) printf 'debugger'; return 0 ;;
    vbw-architect|vbw-architect-*|architect|architect-*|team-architect|team-architect-*) printf 'architect'; return 0 ;;
    vbw-docs|vbw-docs-*|docs|docs-*|team-docs|team-docs-*) printf 'docs'; return 0 ;;
  esac
  return 1
}

vbw_active_agent_normalize_payload_role() {
  local lower role suffix
  lower=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    @vbw:*) lower="${lower#@vbw:}" ;;
    vbw:*) lower="${lower#vbw:}" ;;
  esac
  if [[ "$lower" == vbw-* ]]; then
    vbw_active_agent_normalize_strict_role "$lower"
    return
  fi
  for role in lead dev qa-author qa scout debugger architect docs; do
    case "$lower" in
      "team-$role") printf '%s' "$role"; return 0 ;;
      "team-$role-"*)
        suffix="${lower#team-$role-}"
        case "$suffix" in ''|*[!0-9]*) continue ;; esac
        printf '%s' "$role"
        return 0
        ;;
    esac
  done
  return 1
}


vbw_active_agent_session_dir() { printf '%s/.active-agents/%s\n' "$1" "$2"; }
_vbw_active_agent_state_dir() {
  if [ -n "${2:-}" ]; then vbw_active_agent_session_dir "$1" "$2"; else printf '%s\n' "$1"; fi
}
_vbw_active_agent_count_file() {
  printf '%s/active-agent-count\n' "$(_vbw_active_agent_state_dir "$1" "${2:-}")"
}
_vbw_active_agent_roles_file() {
  printf '%s/active-agent-roles\n' "$(_vbw_active_agent_state_dir "$1" "${2:-}")"
}
_vbw_active_agent_role_pids_file() {
  printf '%s/active-agent-role-pids\n' "$(_vbw_active_agent_state_dir "$1" "${2:-}")"
}
_vbw_active_agent_marker_file() {
  printf '%s/active-agent\n' "$(_vbw_active_agent_state_dir "$1" "${2:-}")"
}
_vbw_active_agent_agents_dir() {
  printf '%s/agents\n' "$(_vbw_active_agent_state_dir "$1" "${2:-}")"
}
_vbw_active_agent_agent_file() {
  printf '%s/%s.json\n' "$(_vbw_active_agent_agents_dir "$1" "$2")" "$3"
}
_vbw_active_agent_lock_dir() { printf '%s/.active-agent-count.lock\n' "$1"; }

vbw_active_agent_acquire_lock() {
  local planning_dir="$1" lock_dir attempts=0 mtime now age
  lock_dir=$(_vbw_active_agent_lock_dir "$planning_dir")
  while [ "$attempts" -lt 100 ]; do
    mkdir "$lock_dir" 2>/dev/null && return 0
    attempts=$((attempts + 1))
    if [ "$attempts" -eq 50 ] && [ -d "$lock_dir" ]; then
      now=$(date +%s 2>/dev/null || echo 0)
      mtime=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo 0)
      age=$((now - mtime))
      [ "$age" -gt 5 ] && rmdir "$lock_dir" 2>/dev/null || true
    fi
    sleep 0.01
  done
  return 1
}
vbw_active_agent_release_lock() { rmdir "$(_vbw_active_agent_lock_dir "$1")" 2>/dev/null || true; }

_vbw_active_agent_read_count_file() {
  local raw=""
  [ -f "$1" ] && raw=$(tr -d '[:space:]' < "$1" 2>/dev/null || true)
  case "$raw" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$raw" ;; esac
}
_vbw_active_agent_valid_pid() { printf '%s' "${1:-}" | grep -Eq '^[0-9]+$'; }
vbw_active_agent_pid_is_live() {
  _vbw_active_agent_valid_pid "${1:-}" && kill -0 "$1" 2>/dev/null
}
_vbw_active_agent_file_is_live() {
  local file pid
  file="$1"
  pid=$(basename "$file" .json)
  vbw_active_agent_pid_is_live "$pid"
}
_vbw_active_agent_file_role() {
  local role
  role=$(jq -r '.role // empty' "$1" 2>/dev/null) || return 1
  vbw_active_agent_normalize_role "$role"
}
_vbw_active_agent_live_files() {
  local dir="$1" file
  [ -d "$dir" ] || return 0
  for file in "$dir"/*.json; do
    [ -f "$file" ] && _vbw_active_agent_file_is_live "$file" && printf '%s\n' "$file"
  done
}
_vbw_active_agent_count_from_files() { _vbw_active_agent_live_files "$1" | wc -l | tr -d ' '; }

_vbw_active_agent_role_stats_from_files() {
  local dir="$1" file role
  declare -A sums=()
  while IFS= read -r file; do
    role=$(_vbw_active_agent_file_role "$file" 2>/dev/null) || continue
    sums["$role"]=$(( ${sums[$role]:-0} + 1 ))
  done < <(_vbw_active_agent_live_files "$dir")
  for role in "${!sums[@]}"; do printf '%s %s\n' "$role" "${sums[$role]}"; done | sort
}

_vbw_active_agent_read_count() {
  local dir
  dir=$(_vbw_active_agent_agents_dir "$1" "${2:-}")
  if [ -d "$dir" ]; then _vbw_active_agent_count_from_files "$dir"; else _vbw_active_agent_read_count_file "$(_vbw_active_agent_count_file "$1" "${2:-}")"; fi
}

_vbw_active_agent_role_stats() {
  local dir roles
  dir=$(_vbw_active_agent_agents_dir "$1" "${2:-}")
  if [ -d "$dir" ]; then
    roles=$(_vbw_active_agent_role_stats_from_files "$dir")
  else
    roles=$(cat "$(_vbw_active_agent_roles_file "$1" "${2:-}")" 2>/dev/null || true)
  fi
  awk '($2 ~ /^[0-9]+$/) && $2 > 0 { sum += $2; count += 1; role = $1 } END { printf "%d %d %s\n", sum + 0, count + 0, role }' <<< "$roles"
}

_vbw_active_agent_sync_session_aggregate() {
  local planning_dir="$1" session_id="$2" state_dir agents count sum roles marker file role tmp writer_id
  writer_id="${BASHPID:-$$}"
  state_dir=$(_vbw_active_agent_state_dir "$planning_dir" "$session_id")
  agents=$(_vbw_active_agent_agents_dir "$planning_dir" "$session_id")
  count=$(_vbw_active_agent_count_from_files "$agents")
  if [ "$count" -le 0 ]; then
    rm -f "$state_dir/active-agent-count" "$state_dir/active-agent-roles" "$state_dir/active-agent-role-pids" "$state_dir/active-agent"
    return 0
  fi
  mkdir -p "$state_dir" || return 0
  printf '%s\n' "$count" > "$state_dir/active-agent-count.tmp.$writer_id" && mv "$state_dir/active-agent-count.tmp.$writer_id" "$state_dir/active-agent-count"
  : > "$state_dir/active-agent-roles.tmp.$writer_id"; : > "$state_dir/active-agent-role-pids.tmp.$writer_id"
  while IFS= read -r file; do
    role=$(_vbw_active_agent_file_role "$file" 2>/dev/null) || continue
    printf '%s %s\n' "$(basename "$file" .json)" "$role" >> "$state_dir/active-agent-role-pids.tmp.$writer_id"
  done < <(_vbw_active_agent_live_files "$agents")
  awk '{ counts[$2] += 1 } END { for (role in counts) print role, counts[role] }' "$state_dir/active-agent-role-pids.tmp.$writer_id" | sort > "$state_dir/active-agent-roles.tmp2.$writer_id"
  mv "$state_dir/active-agent-roles.tmp2.$writer_id" "$state_dir/active-agent-roles"; mv "$state_dir/active-agent-role-pids.tmp.$writer_id" "$state_dir/active-agent-role-pids"
  IFS=' ' read -r sum _count role <<< "$(_vbw_active_agent_role_stats "$planning_dir" "$session_id")"
  marker="$state_dir/active-agent"
  if [ "${sum:-0}" -eq "$count" ] && [ "${_count:-0}" -eq 1 ] && [ -n "${role:-}" ]; then printf '%s\n' "$role" > "$marker"; else rm -f "$marker"; fi
}

_vbw_active_agent_extract_key() {
  local input="$1" role="$2" pid="$3" key
  key=$(printf '%s' "$input" | jq -r '(.agent_id // .teammate_name // .name // .task_id // .agent_name // .agentName // .agent_type // empty)' 2>/dev/null) || key=""
  [ -n "$key" ] || key="${role}-${pid}"
  printf '%s' "$key" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]_.-' '_'
}

_vbw_active_agent_write_registration() {
  local planning_dir="$1" session_id="$2" role="$3" pid="$4" key="$5" dir file tmp
  _vbw_active_agent_valid_pid "$pid" || return 1
  dir=$(_vbw_active_agent_agents_dir "$planning_dir" "$session_id"); mkdir -p "$dir" || return 1
  file=$(_vbw_active_agent_agent_file "$planning_dir" "$session_id" "$pid"); tmp="${file}.tmp.$$"
  jq -n --arg role "$role" --arg key "$key" --arg pid "$pid" '{role:$role,key:$key,pid:$pid}' > "$tmp" || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$file"
}

_vbw_active_agent_has_positive_source_dirs_unlocked() {
  local dir source count
  for dir in "$1/.active-agents"/*; do
    [ -d "$dir" ] || continue
    source=$(basename "$dir"); _vbw_active_agent_is_aggregate_source_id "$source" || continue
    count=$(_vbw_active_agent_read_count "$1" "$source")
    [ "$count" -gt 0 ] && return 0
  done
  return 1
}

_vbw_active_agent_migrate_legacy_root_to_source_unlocked() {
  local planning_dir="$1" source dir pid role key migrated
  source=$(_vbw_active_agent_legacy_source_id); dir=$(_vbw_active_agent_agents_dir "$planning_dir" "$source")
  migrated="$dir/.migrated"
  [ -f "$migrated" ] && return 0
  [ -f "$planning_dir/.active-agent-role-pids" ] || return 0
  _vbw_active_agent_has_positive_source_dirs_unlocked "$planning_dir" && return 0
  while read -r pid role; do
    _vbw_active_agent_valid_pid "$pid" || continue
    role=$(vbw_active_agent_normalize_role "$role" 2>/dev/null) || continue
    key="legacy-${pid}"
    _vbw_active_agent_write_registration "$planning_dir" "$source" "$role" "$pid" "$key" || true
  done < "$planning_dir/.active-agent-role-pids"
  [ -d "$dir" ] && : > "$migrated"
  [ -d "$dir" ] && _vbw_active_agent_sync_session_aggregate "$planning_dir" "$source"
}

_vbw_active_agent_rebuild_aggregate_unlocked() {
  local planning_dir="$1" total=0 dir source file role tmp_roles tmp_pids writer_id
  local -A sums=()
  writer_id="${BASHPID:-$$}"
  tmp_roles="$planning_dir/.active-agent-roles.tmp.$writer_id"; tmp_pids="$planning_dir/.active-agent-role-pids.tmp.$writer_id"
  : > "$tmp_roles"; : > "$tmp_pids"
  for dir in "$planning_dir/.active-agents"/*; do
    [ -d "$dir" ] || continue
    source=$(basename "$dir"); _vbw_active_agent_is_aggregate_source_id "$source" || continue
    _vbw_active_agent_sync_session_aggregate "$planning_dir" "$source"
    while IFS= read -r file; do
      role=$(_vbw_active_agent_file_role "$file" 2>/dev/null) || continue
      total=$((total + 1)); sums["$role"]=$(( ${sums[$role]:-0} + 1 ))
      printf '%s %s\n' "$(basename "$file" .json)" "$role" >> "$tmp_pids"
    done < <(_vbw_active_agent_live_files "$(_vbw_active_agent_agents_dir "$planning_dir" "$source")")
  done
  if [ "$total" -le 0 ]; then _vbw_active_agent_root_files_remove "$planning_dir"; rm -f "$tmp_roles" "$tmp_pids"; return 0; fi
  printf '%s\n' "$total" > "$planning_dir/.active-agent-count.tmp.$writer_id"; mv "$planning_dir/.active-agent-count.tmp.$writer_id" "$planning_dir/.active-agent-count"
  for role in "${!sums[@]}"; do printf '%s %s\n' "$role" "${sums[$role]}"; done | sort > "$tmp_roles"
  mv "$tmp_roles" "$planning_dir/.active-agent-roles"; mv "$tmp_pids" "$planning_dir/.active-agent-role-pids"
  if [ "${#sums[@]}" -eq 1 ]; then printf '%s\n' "${!sums[@]}" > "$planning_dir/.active-agent"; else rm -f "$planning_dir/.active-agent"; fi
}

_vbw_active_agent_root_files_remove() {
  rm -f "$1/.active-agent" "$1/.active-agent-count" "$1/.active-agent-roles" "$1/.active-agent-role-pids"
}

vbw_active_agent_rebuild_aggregate() {
  local planning_dir="$1"
  vbw_active_agent_acquire_lock "$planning_dir" || return 0
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}

vbw_active_agent_start() {
  local planning_dir="$1" input="${2:-}" role="$3" pid="${4:-}" sid key
  [ -n "$role" ] || return 0
  vbw_active_agent_acquire_lock "$planning_dir" || return 0
  sid=$(vbw_active_agent_session_id "$input" 2>/dev/null) || sid=$(_vbw_active_agent_legacy_source_id)
  key=$(_vbw_active_agent_extract_key "$input" "$role" "$pid")
  _vbw_active_agent_migrate_legacy_root_to_source_unlocked "$planning_dir"
  _vbw_active_agent_write_registration "$planning_dir" "$sid" "$role" "$pid" "$key" || {
    vbw_active_agent_release_lock "$planning_dir"
    return 0
  }
  _vbw_active_agent_sync_session_aggregate "$planning_dir" "$sid"
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}

vbw_active_agent_find_session_by_pid() {
  local planning_dir="$1" pid="${2:-}" dir source file match="" matches=0
  _vbw_active_agent_valid_pid "$pid" || return 1
  for dir in "$planning_dir/.active-agents"/*; do
    [ -d "$dir" ] || continue
    source=$(basename "$dir"); _vbw_active_agent_is_aggregate_source_id "$source" || continue
    file=$(_vbw_active_agent_agent_file "$planning_dir" "$source" "$pid")
    if [ -f "$file" ]; then
      match="$source"
      matches=$((matches + 1))
    fi
  done
  [ "$matches" -eq 1 ] || return 1
  printf '%s\n' "$match"
}

_vbw_active_agent_remove_registration() {
  local planning_dir="$1" sid="$2" pid="$3" file
  _vbw_active_agent_valid_pid "$pid" || return 1
  file=$(_vbw_active_agent_agent_file "$planning_dir" "$sid" "$pid")
  [ -f "$file" ] || return 1
  rm -f "$file"; return 0
}

vbw_active_agent_stop() {
  local planning_dir="$1" input="${2:-}" role="${3:-}" pid="${4:-}" sid
  vbw_active_agent_acquire_lock "$planning_dir" || return 0
  if sid=$(vbw_active_agent_session_id "$input" 2>/dev/null); then
    :
  elif sid=$(vbw_active_agent_find_session_by_pid "$planning_dir" "$pid" 2>/dev/null); then
    :
  else
    _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
    vbw_active_agent_release_lock "$planning_dir"
    return 0
  fi
  _vbw_active_agent_remove_registration "$planning_dir" "$sid" "$pid" || true
  _vbw_active_agent_sync_session_aggregate "$planning_dir" "$sid"
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}

vbw_active_agent_remove_current_session() {
  local planning_dir="$1" input="${2:-}" sid
  vbw_active_agent_acquire_lock "$planning_dir" || return 0
  sid=$(vbw_active_agent_session_id "$input" 2>/dev/null) || sid=$(_vbw_active_agent_legacy_source_id)
  rm -rf "$(vbw_active_agent_session_dir "$planning_dir" "$sid")"
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}

vbw_active_agent_clear_all() {
  local planning_dir="$1"
  if ! vbw_active_agent_acquire_lock "$planning_dir"; then
    return 0
  fi
  rm -rf "$planning_dir/.active-agents"
  _vbw_active_agent_root_files_remove "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}

_vbw_active_agent_marker_role_matches() {
  local marker="$1" target="$2" candidate role
  [ -f "$marker" ] || return 1
  candidate=$(head -n 1 "$marker" 2>/dev/null | tr -d '[:space:]')
  role=$(vbw_active_agent_normalize_role "$candidate" 2>/dev/null) || return 1
  [ "$role" = "$target" ]
}

_vbw_active_agent_live_role_in_files() {
  local dir="$1" target="$2" file role
  while IFS= read -r file; do
    role=$(_vbw_active_agent_file_role "$file" 2>/dev/null) || continue
    [ "$role" = "$target" ] && return 0
  done < <(_vbw_active_agent_live_files "$dir")
  return 1
}

vbw_active_agent_current_role_is() {
  local planning_dir="$1" input="${2:-}" target_role="$3" sid roles count marker agents
  [ -n "$target_role" ] || return 1
  if ! sid=$(vbw_active_agent_session_id "$input"); then
    printf '%s\n' 'session_id unresolvable, role detection skipped (fail-closed)' >&2
    return 1
  fi
  agents=$(_vbw_active_agent_agents_dir "$planning_dir" "$sid")
  roles=$(_vbw_active_agent_roles_file "$planning_dir" "$sid")
  count=$(_vbw_active_agent_count_file "$planning_dir" "$sid")
  marker=$(_vbw_active_agent_marker_file "$planning_dir" "$sid")
  if [ -d "$agents" ]; then _vbw_active_agent_live_role_in_files "$agents" "$target_role"; return $?; fi
  if [ -f "$roles" ]; then awk -v r="$target_role" '$1 == r && $2 ~ /^[0-9]+$/ && $2 > 0 { found=1 } END { exit found ? 0 : 1 }' "$roles"; return $?; fi
  [ -f "$count" ] && return 1
  _vbw_active_agent_marker_role_matches "$marker" "$target_role"
}

vbw_active_agent_current_scout() { vbw_active_agent_current_role_is "$1" "${2:-}" scout; }
vbw_active_agent_current_qa() { vbw_active_agent_current_role_is "$1" "${2:-}" qa; }

_vbw_active_agent_marker_is_fresh() {
  local marker="$1" max_age="${2:-86400}" now mtime age
  [ -f "$marker" ] || return 1
  now=$(date +%s 2>/dev/null || echo 0)
  mtime=$(stat -f %m "$marker" 2>/dev/null || stat -c %Y "$marker" 2>/dev/null || echo 0)
  age=$((now - mtime)); [ "$age" -ge 0 ] && [ "$age" -lt "$max_age" ]
}

vbw_active_agent_current_marker_fresh() {
  local planning_dir="$1" input="${2:-}" max_age="${3:-86400}" sid marker
  if sid=$(vbw_active_agent_session_id "$input"); then
    for marker in "$(_vbw_active_agent_count_file "$planning_dir" "$sid")" "$(_vbw_active_agent_marker_file "$planning_dir" "$sid")" "$(_vbw_active_agent_roles_file "$planning_dir" "$sid")"; do
      _vbw_active_agent_marker_is_fresh "$marker" "$max_age" && return 0
    done
    return 1
  fi
  _vbw_active_agent_marker_is_fresh "$planning_dir/.active-agent" "$max_age"
}

vbw_active_agent_current_count() {
  local planning_dir="$1" input="${2:-}" sid
  sid=$(vbw_active_agent_session_id "$input" 2>/dev/null) || sid=""
  _vbw_active_agent_read_count "$planning_dir" "$sid"
}

_vbw_active_agent_session_has_live_pid() {
  local dir="$1" agents
  agents="$dir/agents"
  if [ -d "$agents" ]; then [ -n "$(_vbw_active_agent_live_files "$agents")" ]; return; fi
  [ -f "$dir/active-agent-role-pids" ] || return 1
  while read -r pid _role; do vbw_active_agent_pid_is_live "$pid" && return 0; done < "$dir/active-agent-role-pids"
  return 1
}

vbw_active_agent_scan_stale_sessions() {
  local planning_dir="$1" dir source
  for dir in "$planning_dir/.active-agents"/*; do
    [ -d "$dir" ] || continue
    source=$(basename "$dir"); _vbw_active_agent_is_aggregate_source_id "$source" || continue
    if [ -d "$dir/agents" ]; then
      _vbw_active_agent_session_has_live_pid "$dir" || printf 'stale_marker|.active-agents/%s|dead session-local PIDs\n' "$source"
    elif [ "$(_vbw_active_agent_read_count "$planning_dir" "$source")" -gt 0 ]; then
      _vbw_active_agent_session_has_live_pid "$dir" || printf 'stale_marker|.active-agents/%s|dead session-local PIDs\n' "$source"
    fi
  done
}

vbw_active_agent_cleanup_stale_sessions() {
  local planning_dir="$1" stale ref source
  vbw_active_agent_acquire_lock "$planning_dir" || return 0
  stale=$(vbw_active_agent_scan_stale_sessions "$planning_dir" || true)
  while IFS='|' read -r _category ref _detail; do
    [ -n "$ref" ] || continue
    source="${ref#.active-agents/}"
    _vbw_active_agent_is_aggregate_source_id "$source" || continue
    rm -rf "$(vbw_active_agent_session_dir "$planning_dir" "$source")"
  done <<< "$stale"
  _vbw_active_agent_rebuild_aggregate_unlocked "$planning_dir"
  vbw_active_agent_release_lock "$planning_dir"
}
