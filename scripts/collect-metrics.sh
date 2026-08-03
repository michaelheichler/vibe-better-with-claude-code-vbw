#!/usr/bin/env bash
set -u


if [ $# -lt 2 ]; then
  echo "Usage: collect-metrics.sh <event> <phase> [plan] [key=value ...]" >&2
  exit 0
fi

EVENT="$1"
PHASE="$2"
shift 2

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

CONFIG_PATH="$PLANNING_DIR/config.json"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  METRICS_ENABLED=$(jq -r 'if .metrics != null then .metrics elif .v3_metrics != null then .v3_metrics else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$METRICS_ENABLED" != "true" ]; then
    exit 0
  fi
fi

PLAN=""
DATA_PAIRS=""

for arg in "$@"; do
  case "$arg" in
    *=*)
      KEY=$(echo "$arg" | cut -d'=' -f1)
      VALUE=$(echo "$arg" | cut -d'=' -f2-)
      if [ -n "$DATA_PAIRS" ]; then
        DATA_PAIRS="${DATA_PAIRS},\"${KEY}\":\"${VALUE}\""
      else
        DATA_PAIRS="\"${KEY}\":\"${VALUE}\""
      fi
      ;;
    *)
      if [ -z "$PLAN" ]; then
        PLAN="$arg"
      fi
      ;;
  esac
done

METRICS_DIR="$PLANNING_DIR/.metrics"
METRICS_FILE="${METRICS_DIR}/run-metrics.jsonl"

mkdir -p "$METRICS_DIR" 2>/dev/null || { exit 0; }

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

PLAN_FIELD=""
if [ -n "$PLAN" ]; then
  PLAN_FIELD=",\"plan\":${PLAN}"
fi

DATA_FIELD=""
if [ -n "$DATA_PAIRS" ]; then
  DATA_FIELD=",\"data\":{${DATA_PAIRS}}"
fi

echo "{\"ts\":\"${TS}\",\"event\":\"${EVENT}\",\"phase\":${PHASE}${PLAN_FIELD}${DATA_FIELD}}" >> "$METRICS_FILE" 2>/dev/null || true
