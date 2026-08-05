#!/usr/bin/env bash

set -euo pipefail

. "$(dirname "$0")/resolve-claude-dir.sh"

TEAMS_DIR="$CLAUDE_DIR/teams"
TASKS_DIR="$CLAUDE_DIR/tasks"
STALE_THRESHOLD_SECONDS=7200  # 2 hours
PLANNING_DIR="${VBW_PLANNING_DIR:-$(pwd)/.vbw-planning}"
LOG_FILE="$PLANNING_DIR/.hook-errors.log"

if [ ! -d "$TEAMS_DIR" ]; then
  exit 0
fi

TEMP_DIR="/tmp/vbw-stale-teams-$$"
mkdir -p "$TEMP_DIR"

log_cleanup() {
  local msg="$1"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $msg" >> "$LOG_FILE" 2>/dev/null || true
}

teams_cleaned=0
tasks_cleaned=0

get_mtime() {
  local file="$1"
  if [[ "$OSTYPE" == "darwin"* ]]; then
    stat -f %m "$file" 2>/dev/null || echo "0"
  else
    stat -c %Y "$file" 2>/dev/null || echo "0"
  fi
}

NOW=$(date +%s)

# Pass 1: remove configless VBW teams.
for team_dir in "$TEAMS_DIR"/*; do
  [ ! -d "$team_dir" ] && continue

  team_name=$(basename "$team_dir")

  case "$team_name" in vbw-*) ;; *) continue ;; esac

  [ -f "$team_dir/config.json" ] && continue

  if mv "$team_dir" "$TEMP_DIR/$team_name" 2>/dev/null; then
    teams_cleaned=$((teams_cleaned + 1))
    log_cleanup "Orphaned team cleanup (no config.json): $team_name"
  fi

  if [ -d "$TASKS_DIR/$team_name" ]; then
    if mv "$TASKS_DIR/$team_name" "$TEMP_DIR/${team_name}-tasks" 2>/dev/null; then
      tasks_cleaned=$((tasks_cleaned + 1))
      log_cleanup "Orphaned tasks cleanup: $team_name (paired with configless team)"
    fi
  fi
done

# Pass 2: remove stale VBW teams with inboxes.
for team_dir in "$TEAMS_DIR"/*; do
  [ ! -d "$team_dir" ] && continue

  team_name=$(basename "$team_dir")

  case "$team_name" in vbw-*) ;; *) continue ;; esac

  inbox_dir="$team_dir/inboxes"

  [ ! -d "$inbox_dir" ] && continue

  inbox_mtime=0
  for inbox_file in "$inbox_dir"/*; do
    [ ! -e "$inbox_file" ] && continue
    file_mtime=$(get_mtime "$inbox_file")
    [ "$file_mtime" -gt "$inbox_mtime" ] && inbox_mtime=$file_mtime
  done

  age=$((NOW - inbox_mtime))
  [ "$age" -lt "$STALE_THRESHOLD_SECONDS" ] && continue

  stale_hours=$((age / 3600))

  if mv "$team_dir" "$TEMP_DIR/$team_name" 2>/dev/null; then
    teams_cleaned=$((teams_cleaned + 1))
    log_cleanup "Stale team cleanup: $team_name (stale for ${stale_hours}h)"
  fi

  tasks_dir="$TASKS_DIR/$team_name"
  if [ -d "$tasks_dir" ]; then
    if mv "$tasks_dir" "$TEMP_DIR/${team_name}-tasks" 2>/dev/null; then
      tasks_cleaned=$((tasks_cleaned + 1))
      log_cleanup "Stale tasks cleanup: $team_name (paired with team)"
    fi
  fi
done

rm -rf "$TEMP_DIR" 2>/dev/null || true

if [ "$teams_cleaned" -gt 0 ] || [ "$tasks_cleaned" -gt 0 ]; then
  log_cleanup "Summary: $teams_cleaned teams cleaned, $tasks_cleaned tasks removed"
fi

exit 0
