#!/usr/bin/env bash
set -u


if [ $# -lt 5 ]; then
  echo '{"repaired":false,"attempts":0,"gate":"unknown","reason":"insufficient arguments"}'
  exit 0
fi

GATE_TYPE="$1"
PHASE="$2"
PLAN="$3"
TASK="$4"
CONTRACT_PATH="$5"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_RETRIES=2

REPAIRABLE=false
case "$GATE_TYPE" in
  contract_compliance) REPAIRABLE=true ;;
  required_checks)     REPAIRABLE=true ;;
  protected_file|commit_hygiene|artifact_persistence|verification_threshold)
    REPAIRABLE=false ;;
esac

if [ "$REPAIRABLE" = "false" ]; then
  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "task_blocked" "$PHASE" "$PLAN" \
      "task=${TASK}" "gate=${GATE_TYPE}" "owner=lead" \
      "next_action=manual_intervention" 2>/dev/null || true
  fi
  echo "{\"repaired\":false,\"attempts\":0,\"gate\":\"${GATE_TYPE}\",\"reason\":\"not repairable, escalated to lead\"}"
  exit 0
fi

ATTEMPT=0
REPAIRED=false

while [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; do
  ATTEMPT=$((ATTEMPT + 1))

  case "$GATE_TYPE" in
    contract_compliance)
      PHASES_DIR="${PLANNING_DIR}/phases"
      PHASE_DIR=$(ls -d "${PHASES_DIR}/${PHASE}-"* 2>/dev/null | head -1)
      if [ -n "$PHASE_DIR" ]; then
        PLAN_FILE=$(ls "${PHASE_DIR}/"*"-${PLAN}-"*PLAN.md 2>/dev/null | head -1)
        [ -z "$PLAN_FILE" ] && PLAN_FILE=$(ls "${PHASE_DIR}/${PHASE}-${PLAN}-"*PLAN.md 2>/dev/null | head -1)
        PADDED_PHASE=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
        PADDED_PLAN=$(printf "%02d" "$PLAN" 2>/dev/null || echo "$PLAN")
        [ -z "$PLAN_FILE" ] && PLAN_FILE=$(ls "${PHASE_DIR}/${PADDED_PHASE}-${PADDED_PLAN}-PLAN.md" 2>/dev/null | head -1)
        if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
          bash "${SCRIPT_DIR}/generate-contract.sh" "$PLAN_FILE" >/dev/null 2>&1
        fi
      fi
      ;;

    required_checks)
      ;;
  esac

  GATE_RESULT=$(bash "${SCRIPT_DIR}/hard-gate.sh" "$GATE_TYPE" "$PHASE" "$PLAN" "$TASK" "$CONTRACT_PATH" 2>/dev/null) || true
  GATE_STATUS=$(echo "$GATE_RESULT" | jq -r '.result // "fail"' 2>/dev/null || echo "fail")

  if [ "$GATE_STATUS" = "pass" ]; then
    REPAIRED=true
    break
  fi
done

if [ "$REPAIRED" = "true" ]; then
  echo "{\"repaired\":true,\"attempts\":${ATTEMPT},\"gate\":\"${GATE_TYPE}\"}"
else
  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "task_blocked" "$PHASE" "$PLAN" \
      "task=${TASK}" "gate=${GATE_TYPE}" "owner=lead" \
      "next_action=investigate_and_fix" "attempts=${ATTEMPT}" 2>/dev/null || true
  fi
  echo "{\"repaired\":false,\"attempts\":${ATTEMPT},\"gate\":\"${GATE_TYPE}\",\"reason\":\"max retries exhausted, escalated to lead\"}"
fi
