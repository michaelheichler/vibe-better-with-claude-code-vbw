#!/usr/bin/env bash
set -u


PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MSG=""
if [ $# -ge 1 ] && [ -n "$1" ]; then
  MSG="$1"
else
  MSG=$(cat 2>/dev/null) || MSG=""
fi

[ -z "$MSG" ] && { echo '{"valid":false,"errors":["empty message"]}'; exit 2; }

if ! echo "$MSG" | jq '.' >/dev/null 2>&1; then
  echo '{"valid":false,"errors":["not valid JSON"]}'
  exit 2
fi

SCHEMAS_PATH="${SCRIPT_DIR}/../config/schemas/message-schemas.json"
if [ ! -f "$SCHEMAS_PATH" ]; then
  echo '{"valid":true,"errors":[],"reason":"schemas file not found, fail-open"}'
  exit 0
fi

ERRORS="[]"

add_error() {
  ERRORS=$(echo "$ERRORS" | jq --arg e "$1" '. + [$e]' 2>/dev/null || echo "[$1]")
}

MSG_TYPE_PRENORM=$(echo "$MSG" | jq -r '.type // ""' 2>/dev/null) || MSG_TYPE_PRENORM=""
if [ "$MSG_TYPE_PRENORM" = "shutdown_request" ] || [ "$MSG_TYPE_PRENORM" = "shutdown_response" ]; then
  HAS_PAYLOAD=$(echo "$MSG" | jq 'has("payload")' 2>/dev/null || echo "false")
  if [ "$HAS_PAYLOAD" != "true" ]; then
    FLAT_ID=$(echo "$MSG" | jq -r '.requestId // .id // ""' 2>/dev/null) || FLAT_ID=""
    FLAT_AUTHOR=$(echo "$MSG" | jq -r '.from // .author_role // "unknown"' 2>/dev/null) || FLAT_AUTHOR=""
    MSG=$(echo "$MSG" | jq --arg fid "$FLAT_ID" --arg fauthor "$FLAT_AUTHOR" '
      {
        id: ($fid | if . == "" then "normalized-\(now | floor | tostring)" else . end),
        type: .type,
        phase: (.phase // 0),
        task: (.task // "0-0"),
        author_role: $fauthor,
        target_role: (.target_role // null),
        timestamp: (.timestamp // (now | tostring)),
        schema_version: (.schema_version // "2.0"),
        payload: (del(.type, .id, .requestId, .from, .phase, .task,
                      .author_role, .target_role, .timestamp, .schema_version, .confidence)),
        confidence: (.confidence // 1.0)
      }
    ' 2>/dev/null) || true
  fi
fi

ENVELOPE_FIELDS=$(jq -r '.envelope_fields[]' "$SCHEMAS_PATH" 2>/dev/null) || ENVELOPE_FIELDS=""
while IFS= read -r field; do
  [ -z "$field" ] && continue
  HAS_FIELD=$(echo "$MSG" | jq --arg f "$field" 'has($f)' 2>/dev/null || echo "false")
  if [ "$HAS_FIELD" != "true" ]; then
    add_error "missing envelope field: ${field}"
  fi
done <<< "$ENVELOPE_FIELDS"

MSG_TYPE=$(echo "$MSG" | jq -r '.type // ""' 2>/dev/null) || MSG_TYPE=""
if [ -z "$MSG_TYPE" ]; then
  add_error "missing type field"
else
  TYPE_EXISTS=$(jq --arg t "$MSG_TYPE" '.schemas | has($t)' "$SCHEMAS_PATH" 2>/dev/null || echo "false")
  if [ "$TYPE_EXISTS" != "true" ]; then
    add_error "unknown message type: ${MSG_TYPE}"
  fi
fi

if [ -n "$MSG_TYPE" ] && [ "$TYPE_EXISTS" = "true" ]; then
  PAYLOAD_REQUIRED=$(jq -r --arg t "$MSG_TYPE" '.schemas[$t].payload_required[]' "$SCHEMAS_PATH" 2>/dev/null) || PAYLOAD_REQUIRED=""
  while IFS= read -r field; do
    [ -z "$field" ] && continue
    HAS_FIELD=$(echo "$MSG" | jq --arg f "$field" '.payload | has($f)' 2>/dev/null || echo "false")
    if [ "$HAS_FIELD" != "true" ]; then
      add_error "missing payload field: ${field}"
    fi
  done <<< "$PAYLOAD_REQUIRED"
fi

AUTHOR_ROLE=$(echo "$MSG" | jq -r '.author_role // ""' 2>/dev/null) || AUTHOR_ROLE=""
if [ -n "$AUTHOR_ROLE" ] && [ -n "$MSG_TYPE" ] && [ "$TYPE_EXISTS" = "true" ]; then
  ROLE_ALLOWED=$(jq -r --arg t "$MSG_TYPE" --arg r "$AUTHOR_ROLE" \
    '.schemas[$t].allowed_roles | index($r) != null' "$SCHEMAS_PATH" 2>/dev/null || echo "false")
  if [ "$ROLE_ALLOWED" != "true" ]; then
    add_error "role ${AUTHOR_ROLE} not authorized for ${MSG_TYPE}"
  fi
fi

TARGET_ROLE=$(echo "$MSG" | jq -r '.target_role // ""' 2>/dev/null) || TARGET_ROLE=""
if [ -n "$TARGET_ROLE" ] && [ -n "$MSG_TYPE" ]; then
  CAN_RECEIVE=$(jq -r --arg r "$TARGET_ROLE" --arg t "$MSG_TYPE" \
    '.role_hierarchy[$r].can_receive // [] | index($t) != null' "$SCHEMAS_PATH" 2>/dev/null || echo "false")
  if [ "$CAN_RECEIVE" != "true" ]; then
    add_error "target role ${TARGET_ROLE} cannot receive ${MSG_TYPE}"
  fi
fi

if [ -n "$MSG_TYPE" ]; then
  REFS_MODIFIED=$(echo "$MSG" | jq -r '.payload.files_modified // [] | .[]' 2>/dev/null) || REFS_MODIFIED=""
  REFS_PATHS=$(echo "$MSG" | jq -r '.payload.allowed_paths // [] | .[]' 2>/dev/null) || REFS_PATHS=""
  FILE_REFS=""
  [ -n "$REFS_MODIFIED" ] && FILE_REFS="$REFS_MODIFIED"
  if [ -n "$REFS_PATHS" ]; then
    [ -n "$FILE_REFS" ] && FILE_REFS="${FILE_REFS}"$'\n'"${REFS_PATHS}" || FILE_REFS="$REFS_PATHS"
  fi

  if [ -n "$FILE_REFS" ]; then
    PHASE=$(echo "$MSG" | jq -r '.phase // 0' 2>/dev/null) || PHASE=0
    CONTRACT_DIR="${PLANNING_DIR}/.contracts"
    if [ -d "$CONTRACT_DIR" ] && [ "$PHASE" -gt 0 ] 2>/dev/null; then
      CONTRACT_FILE=$(ls "${CONTRACT_DIR}/${PHASE}-"*.json 2>/dev/null | head -1)
      if [ -n "$CONTRACT_FILE" ] && [ -f "$CONTRACT_FILE" ]; then
        ALLOWED=$(jq -r '.allowed_paths[]' "$CONTRACT_FILE" 2>/dev/null) || ALLOWED=""
        if [ -n "$ALLOWED" ]; then
          while IFS= read -r ref; do
            [ -z "$ref" ] && continue
            NORM_REF="${ref#./}"
            FOUND=false
            while IFS= read -r allowed; do
              [ -z "$allowed" ] && continue
              if [ "$NORM_REF" = "${allowed#./}" ]; then
                FOUND=true
                break
              fi
            done <<< "$ALLOWED"
            if [ "$FOUND" = "false" ]; then
              add_error "file reference ${NORM_REF} outside contract scope"
            fi
          done <<< "$FILE_REFS"
        fi
      fi
    fi
  fi
fi

if [ "$MSG_TYPE" = "qa_verdict" ]; then
  HAS_CHECKS_DETAIL=$(echo "$MSG" | jq -r '.payload | has("checks_detail")' 2>/dev/null || echo "false")
  if [ "$HAS_CHECKS_DETAIL" = "true" ]; then
    DETAIL_TYPE=$(echo "$MSG" | jq -r '.payload.checks_detail | type // "null"' 2>/dev/null || echo "null")
    if [ "$DETAIL_TYPE" != "array" ] && [ "$DETAIL_TYPE" != "null" ]; then
      add_error "qa_verdict checks_detail must be an array or null"
    elif [ "$DETAIL_TYPE" = "array" ]; then
      DETAIL_COUNT=$(echo "$MSG" | jq -r '.payload.checks_detail | length' 2>/dev/null || echo "0")
      INVALID_DETAIL_COUNT=$(echo "$MSG" | jq '[.payload.checks_detail[] | select(
        (.id | type != "string") or
        (.status | type != "string") or
        ((.id | gsub("^\\s+|\\s+$"; "")) == "") or
        ((.status | gsub("^\\s+|\\s+$"; "")) as $s | ($s == "" or (["PASS","FAIL","WARN"] | index($s) == null)))
      )] | length' 2>/dev/null || echo "1")
      if [ "${INVALID_DETAIL_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        add_error "qa_verdict checks_detail entries require non-empty string id and status in PASS|FAIL|WARN"
      elif [ "${DETAIL_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        COUNTER_MISMATCHES=$(echo "$MSG" | jq -r '
          .payload as $p
          | ($p.checks_detail // []) as $d
          | [
              if (($p.checks.failed // null) != ($d | map(select(.status == "FAIL")) | length))
              then "qa_verdict checks.failed does not match checks_detail FAIL count"
              else empty end,
              if (($p.checks.passed // null) != ($d | map(select(.status == "PASS")) | length))
              then "qa_verdict checks.passed does not match checks_detail PASS count"
              else empty end,
              if (($p.checks.total // null) != ($d | length))
              then "qa_verdict checks.total does not match checks_detail entry count"
              else empty end
            ]
          | .[]
        ' 2>/dev/null)
        if [ -n "$COUNTER_MISMATCHES" ]; then
          while IFS= read -r mismatch; do
            [ -z "$mismatch" ] && continue
            add_error "$mismatch"
          done <<< "$COUNTER_MISMATCHES"
        fi
      fi
    fi
  fi
fi

ERROR_COUNT=$(echo "$ERRORS" | jq 'length' 2>/dev/null || echo "0")
if [ "$ERROR_COUNT" -eq 0 ] || [ "$ERROR_COUNT" = "0" ]; then
  echo '{"valid":true,"errors":[]}'
  exit 0
else
  RESULT=$(jq -n --argjson errors "$ERRORS" '{valid: false, errors: $errors}')
  echo "$RESULT"

  if [ -f "${SCRIPT_DIR}/log-event.sh" ]; then
    bash "${SCRIPT_DIR}/log-event.sh" "message_rejected" "${PHASE:-0}" \
      "type=${MSG_TYPE}" "role=${AUTHOR_ROLE}" "error_count=${ERROR_COUNT}" 2>/dev/null || true
  fi

  exit 2
fi
