#!/bin/bash

export PROJECT_ROOT="${BATS_TEST_DIRNAME}/.."
export SCRIPTS_DIR="${PROJECT_ROOT}/scripts"
export CONFIG_DIR="${PROJECT_ROOT}/config"

CACHE_KEY_LIB="${SCRIPTS_DIR}/lib/vbw-cache-key.sh"
vbw_hash_path() {
  bash -c '
. "$1"
vbw_hash_path "$2"
' _ "$CACHE_KEY_LIB" "$1"
}

vbw_cache_prefix() {
  bash -c '
. "$1"
vbw_cache_prefix "$2" "$3" "$4"
' _ "$CACHE_KEY_LIB" "$1" "$2" "$3"
}

save_optional_env() {
  local name="$1" was_set="_ORIG_${1}_WAS_SET" saved="_ORIG_${1}"
  if [[ -v "$name" ]]; then
    printf -v "$was_set" '%s' 1
    printf -v "$saved" '%s' "${!name}"
    export "${was_set?}" "${saved?}"
  else
    printf -v "$was_set" '%s' 0
    export "${was_set?}"
    unset "$saved" 2>/dev/null || true
  fi
}

restore_optional_env() {
  local name="$1" was_set="_ORIG_${1}_WAS_SET" saved="_ORIG_${1}"
  if [ "${!was_set:-0}" = "1" ]; then
    printf -v "$name" '%s' "${!saved}"
    export "${name?}"
  else
    unset "$name" 2>/dev/null || true
  fi
  unset "$was_set" "$saved" 2>/dev/null || true
}

setup_temp_dir() {
  TEST_TEMP_DIR=$(mktemp -d)
  export TEST_TEMP_DIR
  export VBW_AGENT_PID_LOCK_DIR="$TEST_TEMP_DIR/.vbw-agent-pid-lock"
  export _ORIG_HOME="${HOME:-}"
  export _ORIG_GIT_CONFIG_NOSYSTEM="${GIT_CONFIG_NOSYSTEM:-}"
  export _ORIG_GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-}"
  local name
  for name in VBW_PLANNING_DIR CONFIG_PATH VBW_TARGET_ROOT VBW_TARGET_GIT_ROOT VBW_WORKSPACE_SUBPATH CLAUDE_CONFIG_DIR CLAUDE_SESSION_ID; do
    save_optional_env "$name"
  done
  export HOME="$TEST_TEMP_DIR"
  unset CLAUDE_CONFIG_DIR CLAUDE_SESSION_ID VBW_PLANNING_DIR CONFIG_PATH VBW_TARGET_ROOT VBW_TARGET_GIT_ROOT VBW_WORKSPACE_SUBPATH 2>/dev/null || true
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_TEMP_DIR/.gitconfig"
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
}

assert_no_blank_lines_in_state_section() {
  local start_re="$1"
  local stop_re="$2"
  local state_path="$TEST_TEMP_DIR/.vbw-planning/STATE.md"

  awk -v start_re="$start_re" -v stop_re="$stop_re" '
    $0 ~ start_re { seen_start=1; in_section=1; next }
    in_section && $0 ~ stop_re { seen_stop=1; in_section=0; exit }
    in_section && /^[[:space:]]*$/ { failed=1; exit }
    END {
      if (failed || !seen_start || !seen_stop) exit 1
    }
  ' "$state_path"
}

teardown_temp_dir() {
  [ -n "${TEST_TEMP_DIR:-}" ] && rm -rf "$TEST_TEMP_DIR"
  HOME="$_ORIG_HOME"
  local name
  for name in VBW_PLANNING_DIR CONFIG_PATH VBW_TARGET_ROOT VBW_TARGET_GIT_ROOT VBW_WORKSPACE_SUBPATH CLAUDE_CONFIG_DIR CLAUDE_SESSION_ID; do
    restore_optional_env "$name"
  done
  if [ -n "$_ORIG_GIT_CONFIG_NOSYSTEM" ]; then
    GIT_CONFIG_NOSYSTEM="$_ORIG_GIT_CONFIG_NOSYSTEM"
  else
    unset GIT_CONFIG_NOSYSTEM
  fi
  if [ -n "$_ORIG_GIT_CONFIG_GLOBAL" ]; then
    GIT_CONFIG_GLOBAL="$_ORIG_GIT_CONFIG_GLOBAL"
  else
    unset GIT_CONFIG_GLOBAL
  fi
  unset VBW_AGENT_PID_LOCK_DIR _ORIG_HOME _ORIG_GIT_CONFIG_NOSYSTEM _ORIG_GIT_CONFIG_GLOBAL
}

get_dead_pid() {
  local process_id attempt
  sleep 999 &
  process_id=$!
  [[ -n "$process_id" ]] || return 1
  kill -9 "$process_id" 2>/dev/null || true
  for ((attempt = 0; attempt < 50; attempt++)); do
    if ! kill -0 "$process_id" 2>/dev/null; then
      echo "$process_id"
      return 0
    fi
    kill -9 "$process_id" 2>/dev/null || true
    sleep 0.02
  done
  if kill -0 "$process_id" 2>/dev/null; then
    return 1
  fi
  echo "$process_id"
}

assign_live_pid() {
  local var_name="${1:-}"
  [ -n "$var_name" ] || return 1
  kill -0 "$$" 2>/dev/null || return 1
  printf -v "$var_name" '%s' "$$"
}

run_phase_detect() {
  local _pd_script_dir="${1:-$SCRIPTS_DIR}"
  local _pd_sleeps=(0.1 0.2 0.4 0.8)
  local _pd_attempt=0
  while [ $_pd_attempt -lt 5 ]; do
    run bash "$_pd_script_dir/phase-detect.sh"
    if [ -n "$output" ] && [[ "$output" == *"phase_detect_complete=true"* ]]; then
      return 0
    fi
    if [ $_pd_attempt -lt 4 ]; then
      sleep "${_pd_sleeps[$_pd_attempt]}"
    fi
    _pd_attempt=$((_pd_attempt + 1))
  done
  output="run_phase_detect: all 5 retries returned empty or incomplete output"
  export status=1
  echo "$output" >&2
  return 1
}

vbw_cache_prefix_for_root() {
  local root="$1" uid="${2:-$(id -u)}" version root_real
  version=$(tr -d '[:space:]' < "${PROJECT_ROOT}/VERSION" 2>/dev/null || echo 0)
  if root_real=$(cd "$root" 2>/dev/null && pwd -P 2>/dev/null); then
    :
  else
    root_real="$root"
  fi
  vbw_cache_prefix "$version" "$uid" "$root_real"
}

cleanup_vbw_cache_for_root() {
  local prefix
  prefix=$(vbw_cache_prefix_for_root "$1" "${2:-$(id -u)}")
  rm -f "${prefix}-fast" "${prefix}-slow" "${prefix}-cost" "${prefix}-ok" 2>/dev/null || true
}

cleanup_vbw_caches_under_temp_dir() {
  local uid="${1:-$(id -u)}" path root
  [ -n "${TEST_TEMP_DIR:-}" ] || return 0
  [ -d "$TEST_TEMP_DIR" ] || return 0

  while IFS= read -r path; do
    root=$(dirname "$path")
    cleanup_vbw_cache_for_root "$root" "$uid"
  done < <(find "$TEST_TEMP_DIR" \( -type d -o -type f \) \( -name .git -o -name .vbw-planning \) -print 2>/dev/null)
}

create_test_vbw_workspace() {
  local dir="$1"
  mkdir -p "$dir/.vbw-planning"
  echo '{}' > "$dir/.vbw-planning/config.json"
}

create_test_config() {
  local dir="${1:-.vbw-planning}"
  jq '.worktree_isolation = "on" | .lease_locks = false | .event_recovery = false' "$CONFIG_DIR/defaults.json" > "$TEST_TEMP_DIR/$dir/config.json"
}

setup_unrelated_git_repo() {
  local repo_dir="$1"

  mkdir -p "$repo_dir"
  (
    cd "$repo_dir" || exit 1
    git init -q
    git config user.name "VBW Test"
    git config user.email "vbw-tests@example.com"
    echo "initial" > unrelated.txt
    git add unrelated.txt
    git commit -qm "init"
  )
}
