#!/bin/bash

[ -n "${_VBW_SUMMARY_STATUS_LOADED:-}" ] && return 0
_VBW_SUMMARY_STATUS_LOADED=1

is_valid_summary_status() {
  local status="$1"
  case "$status" in
    complete|partial|failed) return 0 ;;
    *) return 1 ;;
  esac
}

is_completion_status() {
  local status="$1"
  case "$status" in
    complete|partial) return 0 ;;
    *) return 1 ;;
  esac
}

extract_summary_status() {
  local file="$1"
  [ ! -f "$file" ] && echo "" && return 1
  local status=""
  local in_fm=0
  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ "$in_fm" -eq 0 ]; then in_fm=1; continue; else break; fi
    fi
    if [ "$in_fm" -eq 1 ]; then
      case "$line" in
        status:*)
          status=$(echo "$line" | cut -d: -f2- | sed 's/^ *//' | tr '[:upper:]' '[:lower:]')
          ;;
      esac
    fi
  done < "$file"
  echo "$status"
  is_valid_summary_status "$status"
}

is_plan_completed() {
  local summary_file="$1"
  [ ! -f "$summary_file" ] && return 1
  local status
  status=$(extract_summary_status "$summary_file")
  is_completion_status "$status"
}

is_plan_finalized() {
  local summary_file="$1"
  [ ! -f "$summary_file" ] && return 1
  local status
  status=$(extract_summary_status "$summary_file")
  is_valid_summary_status "$status"
}

count_completed_summaries() {
  local phase_dir="$1"
  local count=0
  local sf
  for sf in "$phase_dir"/*-SUMMARY.md; do
    [ ! -f "$sf" ] && continue
    if is_plan_completed "$sf"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}

count_finalized_summaries() {
  local phase_dir="$1"
  local count=0
  local sf
  for sf in "$phase_dir"/*-SUMMARY.md; do
    [ ! -f "$sf" ] && continue
    if is_plan_finalized "$sf"; then
      count=$((count + 1))
    fi
  done
  echo "$count"
}
