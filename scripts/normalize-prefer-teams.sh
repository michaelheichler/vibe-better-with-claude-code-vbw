#!/usr/bin/env bash
set -u


read_raw_value() {
  local config_path="$1"

  if [ ! -f "$config_path" ] || ! command -v jq >/dev/null 2>&1; then
    echo "auto"
    return 0
  fi

  jq -r '.prefer_teams // "auto"' "$config_path" 2>/dev/null || echo "auto"
}

normalize_prefer_teams() {
  case "${1:-auto}" in
    ""|null|false|when_parallel)
      echo "auto"
      ;;
    true)
      echo "always"
      ;;
    always|auto|never)
      echo "$1"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

if [ "${1:-}" = "--value" ]; then
  shift
  normalize_prefer_teams "${1:-auto}"
  exit 0
fi

normalize_prefer_teams "$(read_raw_value "${1:-.vbw-planning/config.json}")"