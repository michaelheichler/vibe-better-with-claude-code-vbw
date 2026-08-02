#!/usr/bin/env bash
set -u

_RS_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_RS_SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$_RS_SCRIPT_DIR/summary-utils.sh"
  is_plan_finalized() { is_summary_terminal "$1"; }
else
  # Safe default: treat plans as not finalized when helpers unavailable
  is_plan_finalized() { return 1; }
  extract_summary_status() { echo ""; return 1; }
fi

if [ $# -lt 1 ]; then
  echo "{}"
  exit 0
fi

PHASE="$1"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${PLANNING_DIR}/config.json"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"

# Legacy fallback: honor v3_event_recovery if unprefixed key missing (pre-migration brownfield)
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  EVENT_RECOVERY=$(jq -r 'if .event_recovery != null then .event_recovery elif .v3_event_recovery != null then .v3_event_recovery else false end' "$CONFIG_PATH" 2>/dev/null || echo "false")
  if [ "$EVENT_RECOVERY" != "true" ]; then
    echo "{}"
    exit 0
  fi
fi

command -v jq &>/dev/null || { echo "{}"; exit 0; }

# Uses jq fromjson? so malformed trailing lines do not mask earlier valid events.
latest_plan_event_status() {
  local _events_file="$1"
  local _phase="$2"
  local _plan="$3"
  jq -Rr \
    --argjson phase "$_phase" \
    --argjson plan "$_plan" \
    '
      fromjson?
      | select(.event == "plan_end")
      | select((((.phase | tostring | tonumber?) // -1) == $phase))
      | select((((.plan  | tostring | tonumber?) // -1) == $plan))
      | (.data.status // empty)
    ' "$_events_file" 2>/dev/null | tail -n 1
}

PHASES_DIR="${2:-${PLANNING_DIR}/phases}"
PHASE_DIR=""
for d in "$PHASES_DIR"/"$(printf '%02d' "$PHASE")"-*/; do
  [ -d "$d" ] && PHASE_DIR="$d" && break
done

[ -z "$PHASE_DIR" ] && { echo "{}"; exit 0; }

PHASE_SLUG=$(basename "$PHASE_DIR" | sed "s/^$(printf '%02d' "$PHASE")-//")

PLANS_JSON="[]"
for plan_file in "$PHASE_DIR"/*-PLAN.md; do
  [ ! -f "$plan_file" ] && continue
  PLAN_ID=$(basename "$plan_file" | sed 's/-PLAN\.md$//')
  PLAN_TITLE=$(awk '/^title:/ {gsub(/^title: *"?|"?$/, ""); print}' "$plan_file" 2>/dev/null) || PLAN_TITLE="unknown"
  PLAN_WAVE=$(awk '/^wave:/ {gsub(/^wave: */, ""); print}' "$plan_file" 2>/dev/null) || PLAN_WAVE="1"

  SUMMARY_FILE="$PHASE_DIR/${PLAN_ID}-SUMMARY.md"
  if is_plan_finalized "$SUMMARY_FILE"; then
    PLAN_STATUS=$(extract_summary_status "$SUMMARY_FILE")
    case "$PLAN_STATUS" in
      complete|completed) PLAN_STATUS="complete" ;;
      partial) PLAN_STATUS="partial" ;;
      failed) PLAN_STATUS="failed" ;;
      *) PLAN_STATUS="pending" ;;
    esac
  else
    PLAN_STATUS="pending"
  fi

  # Policy: latest valid event is authoritative over SUMMARY.md, which may be stale.
  if [ -f "$EVENTS_FILE" ]; then
    # log-event.sh writes bare integers ("plan":1, not "plan":01), so strip leading zeros to match
    PLAN_NUM=$(echo "$PLAN_ID" | sed 's/^[0-9]*-//' | sed 's/^0*//')
    [ -z "$PLAN_NUM" ] && PLAN_NUM="0"
    EVENT_STATUS=$(latest_plan_event_status "$EVENTS_FILE" "$PHASE" "$PLAN_NUM") || EVENT_STATUS=""
    [ "$EVENT_STATUS" = "complete" ] && PLAN_STATUS="complete"
    [ "$EVENT_STATUS" = "failed" ] && PLAN_STATUS="failed"
  fi

  case "${PLAN_WAVE:-1}" in
    ''|*[!0-9]*) PLAN_WAVE=1 ;;
  esac

  PLANS_JSON=$(echo "$PLANS_JSON" | jq \
    --arg id "$PLAN_ID" \
    --arg title "$PLAN_TITLE" \
    --argjson wave "${PLAN_WAVE:-1}" \
    --arg status "$PLAN_STATUS" \
    '. + [{"id": $id, "title": $title, "wave": $wave, "status": $status}]' 2>/dev/null) || continue
done

TOTAL=$(echo "$PLANS_JSON" | jq 'length' 2>/dev/null) || TOTAL=0
COMPLETE=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "complete")] | length' 2>/dev/null) || COMPLETE=0
FAILED=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null) || FAILED=0
TERMINAL=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "complete" or .status == "failed" or .status == "partial")] | length' 2>/dev/null) || TERMINAL=0


if [ "$FAILED" -gt 0 ]; then
  STATUS="failed"
elif [ "$COMPLETE" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
  STATUS="complete"
elif [ "$COMPLETE" -gt 0 ] || [ "$TERMINAL" -gt 0 ]; then
  STATUS="running"
else
  STATUS="pending"
fi

MAX_WAVE=$(echo "$PLANS_JSON" | jq '[.[].wave] | max // 1' 2>/dev/null) || MAX_WAVE=1
CURRENT_WAVE=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "pending" or .status == "running") | .wave] | min // 1' 2>/dev/null) || CURRENT_WAVE=1

jq -n \
  --argjson phase "$PHASE" \
  --arg phase_name "$PHASE_SLUG" \
  --arg status "$STATUS" \
  --argjson wave "$CURRENT_WAVE" \
  --argjson total_waves "$MAX_WAVE" \
  --argjson plans "$PLANS_JSON" \
  '{phase: $phase, phase_name: $phase_name, status: $status, wave: $wave, total_waves: $total_waves, plans: $plans}' \
  2>/dev/null || echo "{}"

exit 0
