#!/usr/bin/env bash

collect_debug_log_diagnostics() {
  local claude_dir="${CLAUDE_CONFIG_DIR:-${HOME:-/tmp}/.claude}"
  local debug_log="${claude_dir}/debug/latest"

  echo "--- Debug Log Summary ---"

  if [ ! -f "$debug_log" ]; then
    echo "debug_log: not found (${debug_log})"
    echo ""
    return 0
  fi

  local real_path link_target debug_dir resolved_debug_dir debug_log_lines
  real_path="$debug_log"
  link_target=$(readlink "$debug_log" 2>/dev/null || true)
  if [ -n "$link_target" ]; then
    if [[ "$link_target" = /* ]]; then
      real_path="$link_target"
    else
      debug_dir=$(dirname "$debug_log")
      resolved_debug_dir=$(cd -P "$debug_dir" 2>/dev/null && pwd -P)
      if [ -n "$resolved_debug_dir" ]; then
        real_path="${resolved_debug_dir}/${link_target}"
      else
        real_path="${debug_dir}/${link_target}"
      fi
    fi
  fi
  echo "debug_log: $real_path"
  debug_log_lines=$(wc -l < "$debug_log" 2>/dev/null | tr -d ' ')
  : "${debug_log_lines:=0}"
  echo "debug_log_lines: $debug_log_lines"

  local plugin_lines
  plugin_lines=$(grep -cE 'Loading hooks from plugin:|Registered .* hooks from|Loaded plugin|Loading plugin' "$debug_log" 2>/dev/null || true)
  : "${plugin_lines:=0}"
  echo "plugin_loading_lines: $plugin_lines"
  if [ "$plugin_lines" -gt 0 ]; then
    grep -E 'Loading hooks from plugin:|Registered .* hooks from|Loaded plugin|Loading plugin' "$debug_log" 2>/dev/null | head -5 | while IFS= read -r line; do
      echo "  $line"
    done
  fi

  local hook_lookups hook_successes hook_errors
  hook_lookups=$(grep -c 'Getting matching hook commands' "$debug_log" 2>/dev/null || true)
  : "${hook_lookups:=0}"
  hook_successes=$(grep -c 'Hook .* success:' "$debug_log" 2>/dev/null || true)
  : "${hook_successes:=0}"
  hook_errors=$(grep -ciE 'hook.*(error|fail|timeout|reject|denied|block|stderr)' "$debug_log" 2>/dev/null || true)
  : "${hook_errors:=0}"
  echo "hook_lookups: $hook_lookups"
  echo "hook_successes: $hook_successes"
  echo "hook_error_lines: $hook_errors"

  if [ "$hook_errors" -gt 0 ]; then
    grep -iE 'hook.*(error|fail|timeout|reject|denied|block|stderr)' "$debug_log" 2>/dev/null | head -10 | while IFS= read -r line; do
      echo "  [ERROR] $line"
    done
  fi

  echo ""
}
