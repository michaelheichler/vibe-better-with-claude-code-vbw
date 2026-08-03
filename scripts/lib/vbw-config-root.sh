#!/usr/bin/env bash

_walk_up_for_vbw_root() {
  local _cwd="$1" _prev
  while [ "$_cwd" != "/" ]; do
    if [ -f "$_cwd/.vbw-planning/config.json" ]; then
      export VBW_CONFIG_ROOT="$_cwd"
      export VBW_PLANNING_DIR="$_cwd/.vbw-planning"
      return 0
    fi
    _prev="$_cwd"
    _cwd=$(dirname "$_cwd")
    [ "$_cwd" = "$_prev" ] && break
  done
  return 1
}

_prefer_claude_sidechain_host_root() {
  local _cwd="$1" _probe _parent _grandparent _host

  _probe="$_cwd"
  while [ "$_probe" != "/" ]; do
    case "$(basename "$_probe")" in
      agent-*)
        _parent=$(dirname "$_probe")
        _grandparent=$(dirname "$_parent")
        if [ "$(basename "$_parent")" = "worktrees" ] && [ "$(basename "$_grandparent")" = ".claude" ]; then
          _host=$(dirname "$_grandparent")
          if [ -f "$_host/.vbw-planning/config.json" ]; then
            export VBW_CONFIG_ROOT="$_host"
            export VBW_PLANNING_DIR="$_host/.vbw-planning"
            export VBW_CLAUDE_SIDECHAIN_ROOT="$_probe"
            export VBW_CLAUDE_SIDECHAIN_HOST_ROOT="$_host"
            return 0
          fi
        fi
        ;;
    esac

    _parent=$(dirname "$_probe")
    [ "$_parent" = "$_probe" ] && break
    _probe="$_parent"
  done

  return 1
}

find_vbw_root() {
  if [ -n "${VBW_CONFIG_ROOT:-}" ]; then
    export VBW_CONFIG_ROOT
    export VBW_PLANNING_DIR="${VBW_CONFIG_ROOT}/.vbw-planning"
    return 0
  fi

  local _start_dir _cwd_dir
  _cwd_dir=$(pwd -P 2>/dev/null || pwd)

  if [ -n "${1:-}" ]; then
    _prefer_claude_sidechain_host_root "$_cwd_dir" && return 0
    _walk_up_for_vbw_root "$_cwd_dir" && return 0
    if _start_dir=$(cd "$1" 2>/dev/null && pwd -P 2>/dev/null); then
      _walk_up_for_vbw_root "$_start_dir" && return 0
    else
      _walk_up_for_vbw_root "$_cwd_dir" && return 0
    fi
  else
    _prefer_claude_sidechain_host_root "$_cwd_dir" && return 0
    _walk_up_for_vbw_root "$_cwd_dir" && return 0
  fi

  export VBW_CONFIG_ROOT="$_cwd_dir"
  export VBW_PLANNING_DIR="$_cwd_dir/.vbw-planning"
}
