#!/usr/bin/env bash
set -u


if [ $# -lt 2 ]; then
  exit 0
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${PLANNING_DIR}/config.json"

EVENT_TYPE="$1"
PHASE="$2"
shift 2

case "$EVENT_TYPE" in
  phase_start|phase_end|plan_start|plan_end|agent_spawn|agent_shutdown|error|checkpoint)
    ;;
  phase_planned|task_created|task_claimed|task_started|artifact_written|gate_passed|gate_failed|task_completed_candidate|task_completed_confirmed|task_blocked|task_reassigned|shutdown_sent|shutdown_received)
    ;;
  token_overage|token_cap_escalated|file_conflict|smart_route|contract_revision|cache_hit|task_completion_rejected|snapshot_restored|state_recovered|message_rejected|milestone_shipped)
    ;;
  *)
    echo "[log-event] WARNING: unknown event type '${EVENT_TYPE}' rejected" >&2
    exit 0
    ;;
esac

CORRELATION_ID="${VBW_CORRELATION_ID:-}"

EXEC_STATE="${PLANNING_DIR}/.execution-state.json"
if [ -z "$CORRELATION_ID" ] && [ -f "$EXEC_STATE" ] && command -v jq &>/dev/null; then
  CORRELATION_ID=$(jq -r '.correlation_id // ""' "$EXEC_STATE" 2>/dev/null || echo "")
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

EVENTS_DIR="${PLANNING_DIR}/.events"
EVENTS_FILE="${EVENTS_DIR}/event-log.jsonl"

mkdir -p "$EVENTS_DIR" 2>/dev/null || exit 0

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

if command -v uuidgen &>/dev/null; then
  EVENT_ID=$(uuidgen 2>/dev/null) || EVENT_ID=""
  if [ -n "$EVENT_ID" ]; then
    EVENT_ID=$(echo "$EVENT_ID" | tr '[:upper:]' '[:lower:]')
  else
    EVENT_ID="${TS}-${RANDOM}${RANDOM}"
  fi
else
  EVENT_ID="${TS}-${RANDOM}${RANDOM}"
fi

_JQ_ARGS=(
  --arg ts "$TS"
  --arg event_id "$EVENT_ID"
  --arg correlation_id "$CORRELATION_ID"
  --arg event "$EVENT_TYPE"
)
case "$PHASE" in
  *[!0-9]*) _JQ_ARGS+=(--arg phase "$PHASE") ;;
  *)        _JQ_ARGS+=(--argjson phase "$PHASE") ;;
esac
_JQ_EXPR='{ts: $ts, event_id: $event_id, correlation_id: $correlation_id, event: $event, phase: $phase}'

if [ -n "$PLAN" ]; then
  case "$PLAN" in
    *[!0-9]*) _JQ_ARGS+=(--arg plan "$PLAN"); _JQ_EXPR="${_JQ_EXPR} + {plan: \$plan}" ;;
    *)        _JQ_ARGS+=(--argjson plan "$PLAN"); _JQ_EXPR="${_JQ_EXPR} + {plan: \$plan}" ;;
  esac
fi

if [ -n "$DATA_PAIRS" ]; then
  _JQ_ARGS+=(--argjson data "{${DATA_PAIRS}}"); _JQ_EXPR="${_JQ_EXPR} + {data: \$data}"
fi

if command -v jq &>/dev/null; then
  jq -nc "${_JQ_ARGS[@]}" "$_JQ_EXPR" >> "$EVENTS_FILE" 2>/dev/null || true
else
  PLAN_FIELD=""
  if [ -n "$PLAN" ]; then
    PLAN_FIELD=",\"plan\":\"${PLAN}\""
  fi
  DATA_FIELD=""
  if [ -n "$DATA_PAIRS" ]; then
    DATA_FIELD=",\"data\":{${DATA_PAIRS}}"
  fi
  case "$PHASE" in
    *[!0-9]*) _PHASE_JSON="\"${PHASE}\"" ;;
    *)        _PHASE_JSON="${PHASE}" ;;
  esac
  echo "{\"ts\":\"${TS}\",\"event_id\":\"${EVENT_ID}\",\"correlation_id\":\"${CORRELATION_ID}\",\"event\":\"${EVENT_TYPE}\",\"phase\":${_PHASE_JSON}${PLAN_FIELD}${DATA_FIELD}}" >> "$EVENTS_FILE" 2>/dev/null || true
fi

: "${CONFIG_PATH-}"
