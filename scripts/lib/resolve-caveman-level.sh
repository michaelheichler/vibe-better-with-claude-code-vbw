#!/usr/bin/env bash

resolve_caveman_level() {
  local style="${1:-none}"
  local planning_dir="${2:-.vbw-planning}"

  if [[ "$style" != "auto" ]]; then
    RESOLVED_CAVEMAN_LEVEL="$style"
    return 0
  fi

  local usage_file="${planning_dir}/.context-usage"

  if [[ ! -f "$usage_file" ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  local used_pct field_count
  field_count=$(awk -F'|' '{print NF}' "$usage_file" 2>/dev/null)

  if [[ "$field_count" == "3" ]]; then
    used_pct=$(awk -F'|' '{print $2}' "$usage_file" 2>/dev/null)
  elif [[ "$field_count" == "2" ]]; then
    used_pct=$(awk -F'|' '{print $1}' "$usage_file" 2>/dev/null)
  else
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  if [[ -z "$used_pct" ]] || ! [[ "$used_pct" =~ ^[0-9]+$ ]]; then
    RESOLVED_CAVEMAN_LEVEL="none"
    return 0
  fi

  if (( used_pct >= 85 )); then
    RESOLVED_CAVEMAN_LEVEL="ultra"
  elif (( used_pct >= 70 )); then
    RESOLVED_CAVEMAN_LEVEL="full"
  elif (( used_pct >= 50 )); then
    RESOLVED_CAVEMAN_LEVEL="lite"
  else
    RESOLVED_CAVEMAN_LEVEL="none"
  fi

  return 0
}

: "${RESOLVED_CAVEMAN_LEVEL-}"
