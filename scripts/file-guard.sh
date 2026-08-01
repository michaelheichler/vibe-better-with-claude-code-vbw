#!/bin/bash
set -u
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -z "$FILE_PATH" ] && exit 0

_FG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$_FG_SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  # shellcheck source=lib/active-agent-state.sh
  . "$_FG_SCRIPT_DIR/lib/active-agent-state.sh"
fi
_FG_SHARED_ROOT_RESOLVED=false
if [ -f "$_FG_SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
  # shellcheck source=lib/vbw-config-root.sh
  if source "$_FG_SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
    if find_vbw_root "$_FG_SCRIPT_DIR" >/dev/null 2>&1; then
      _FG_SHARED_ROOT_RESOLVED=true
    fi
  fi
fi

resolve_lexical_path() {
  local base="$1" probe suffix resolved_probe
  probe=$(dirname "$base")
  suffix="/$(basename "$base")"
  while [ ! -d "$probe" ] && [ "$probe" != "/" ]; do
    suffix="/$(basename "$probe")$suffix"
    probe=$(dirname "$probe")
  done
  [ -d "$probe" ] || {
    printf '%s\n' "$base"
    return 0
  }
  resolved_probe=$(cd "$probe" 2>/dev/null && pwd -P 2>/dev/null) || resolved_probe="$probe"
  printf '%s\n' "${resolved_probe%/}$suffix"
}

to_abs_path() {
  local p="$1" base cwd_base
  [ -z "$p" ] && {
    printf '\n'
    return 0
  }
  case "$p" in
    /*) base="$p" ;;
    *)
      cwd_base=$(pwd -P 2>/dev/null || pwd)
      base="$cwd_base/${p#./}"
      ;;
  esac
  resolve_lexical_path "$base"
}

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.vbw-planning/config.json" ] || [ -d "$dir/.vbw-planning/phases" ]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

if [ "$_FG_SHARED_ROOT_RESOLVED" = "true" ] && [ -n "${VBW_CONFIG_ROOT:-}" ] && [ -n "${VBW_PLANNING_DIR:-}" ] && [ -f "$VBW_PLANNING_DIR/config.json" ]; then
  PROJECT_ROOT="$VBW_CONFIG_ROOT"
  PHASES_DIR="$VBW_PLANNING_DIR/phases"
else
  PROJECT_ROOT=$(find_project_root) || PROJECT_ROOT=""
  if [ -n "$PROJECT_ROOT" ]; then
    PHASES_DIR="$PROJECT_ROOT/.vbw-planning/phases"
  else
    PHASES_DIR=""
  fi
fi

normalize_agent_role() {
  command -v vbw_active_agent_normalize_role >/dev/null 2>&1 || return 1
  vbw_active_agent_normalize_role "$1"
}

_FG_PAYLOAD_AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null) || _FG_PAYLOAD_AGENT_TYPE=""
_FG_PAYLOAD_AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null) || _FG_PAYLOAD_AGENT_ID=""
_FG_PAYLOAD_HAS_AGENT=false
if [ -n "$_FG_PAYLOAD_AGENT_TYPE" ] || [ -n "$_FG_PAYLOAD_AGENT_ID" ]; then
  _FG_PAYLOAD_HAS_AGENT=true
fi
_FG_CALLER_IS_DELEGATED="$_FG_PAYLOAD_HAS_AGENT"

detect_payload_agent_role() {
  local candidate role
  for candidate in "$_FG_PAYLOAD_AGENT_TYPE" "$_FG_PAYLOAD_AGENT_ID"; do
    [ -z "$candidate" ] && continue
    if role=$(normalize_agent_role "$candidate"); then
      printf '%s' "$role"
      return 0
    fi
  done
  return 1
}
# Advisory only: env hints and the undocumented child flag are caller-controlled, so this is not a security boundary.
if [ "${CLAUDE_CODE_CHILD_SESSION:-}" = "1" ]; then
  _FG_CALLER_IS_DELEGATED=true
fi

# Keep env role precedence over payload role because VBW spawns rely on exported role hints, then classify child callers before orchestrators.
detect_agent_role() {
  local candidate role planning_dir

  for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
    [ -z "$candidate" ] && continue
    if role=$(normalize_agent_role "$candidate"); then
      printf '%s' "$role"
      return 0
    fi
  done

  if role=$(detect_payload_agent_role); then
    printf '%s' "$role"
    return 0
  fi

  [ "$_FG_PAYLOAD_HAS_AGENT" = true ] || return 1

  if [ -n "$PROJECT_ROOT" ]; then
    planning_dir="$PROJECT_ROOT/.vbw-planning"
    if command -v vbw_active_agent_current_scout >/dev/null 2>&1 && vbw_active_agent_current_scout "$planning_dir" "$INPUT"; then
      printf 'scout'
      return 0
    fi
    if command -v vbw_active_agent_current_qa >/dev/null 2>&1 && vbw_active_agent_current_qa "$planning_dir" "$INPUT"; then
      printf 'qa'
      return 0
    fi
  fi

  return 1
}

ACTIVE_AGENT_ROLE=""
if ACTIVE_AGENT_ROLE=$(detect_agent_role); then
  :
else
  ACTIVE_AGENT_ROLE=""
fi

_FG_NORMALIZED=$(echo "$FILE_PATH" | sed 's#/[^/]*/\.\./#/#g')
FILE_PATH_LC=$(echo "$_FG_NORMALIZED" | tr '[:upper:]' '[:lower:]')
case "$FILE_PATH_LC" in
  *.vbw-planning/phases/*/plan-[0-9]*.md|*.vbw-planning/phases/*/summary-[0-9]*.md|*.vbw-planning/phases/*/context-[0-9]*.md)
    _BASENAME_CHECK=$(basename "$FILE_PATH" 2>/dev/null) || _BASENAME_CHECK="$FILE_PATH"
    _BASENAME_LC=$(echo "$_BASENAME_CHECK" | tr '[:upper:]' '[:lower:]')
    if echo "$_BASENAME_LC" | grep -qE '^(plan|summary|context)-[0-9]+\.md$' || \
       echo "$_BASENAME_LC" | grep -qE '^plan-[0-9]+-(summary|context)\.md$'; then
      _FG_TYPE="PLAN"
      case "$_BASENAME_LC" in
        summary-*|*-summary.*) _FG_TYPE="SUMMARY" ;;
        context-*|*-context.*) _FG_TYPE="CONTEXT" ;;
      esac
      echo "Blocked: wrong naming convention for $_FG_TYPE artifact. Use {NN}-${_FG_TYPE}.md (e.g., 01-${_FG_TYPE}.md), not ${_FG_TYPE}-{NN}.md ($_BASENAME_CHECK)" >&2
      exit 2
    fi
    ;;
esac

# Reject sidechain targets before planning exemptions because VBW never merges writes from Claude internal worktrees.
if [ -n "${VBW_CLAUDE_SIDECHAIN_ROOT:-}" ] && [ -n "${VBW_CLAUDE_SIDECHAIN_HOST_ROOT:-}" ]; then
  _FG_SIDECHAIN_BLOCK=false
  _FG_BLOCKED_TARGET="$FILE_PATH"

  case "$FILE_PATH" in
    /*)
      _FG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
      case "$_FG_TARGET_ABS" in
        "$VBW_CLAUDE_SIDECHAIN_ROOT"|"$VBW_CLAUDE_SIDECHAIN_ROOT"/*)
          _FG_SIDECHAIN_BLOCK=true
          _FG_BLOCKED_TARGET="$_FG_TARGET_ABS"
          ;;
      esac
      ;;
    *)
      _FG_SIDECHAIN_BLOCK=true
      ;;
  esac

  if [ "$_FG_SIDECHAIN_BLOCK" = "true" ]; then
    {
      echo "Blocked: Claude sidechain write target"
      echo "blocked target: $_FG_BLOCKED_TARGET"
      echo "host repo: $VBW_CLAUDE_SIDECHAIN_HOST_ROOT"
      echo "retry: retry the same Write/Edit with an absolute path under the host repo, not the Claude sidechain path."
      echo "reason: VBW will not merge or use writes made inside Claude's internal sidechain."
    } >&2
    exit 2
  fi
fi

if [ "$ACTIVE_AGENT_ROLE" = "scout" ] && [ -n "$PROJECT_ROOT" ]; then
  _FG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
  _FG_PLANNING_ABS=$(to_abs_path "$PROJECT_ROOT/.vbw-planning")
  case "$_FG_TARGET_ABS" in
    "$_FG_PLANNING_ABS"|"$_FG_PLANNING_ABS"/*)
      :
      ;;
    *)
      echo "Blocked: Scout-safe active-agent context is read-only outside .vbw-planning/" >&2
      exit 2
      ;;
  esac
fi

case "$FILE_PATH" in
  *.vbw-planning/milestones/*/phases/*)
    # Other milestone root files must fall through because archival writes SHIPPED.md and moves STATE.md and ROADMAP.md.
    echo "Blocked: writes to archived milestone phases are not allowed ($FILE_PATH)" >&2
    exit 2
    ;;
  *.vbw-planning/*/remediation/uat/round-*/R[0-9]*-SUMMARY.md|\
  *.vbw-planning/*/remediation/qa/round-*/R[0-9]*-SUMMARY.md)
    exit 0
    ;;
  *.vbw-planning/*-SUMMARY.md)
    _FG_SUM_STATUS=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null | sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' | head -1 | tr -d '[:space:]')
    if [ -n "$_FG_SUM_STATUS" ]; then
      case "$_FG_SUM_STATUS" in
        complete|completed|partial|failed) ;;
        *)
          echo "Blocked: SUMMARY.md status '${_FG_SUM_STATUS}' is not terminal (must be complete|partial|failed)" >&2
          exit 2
          ;;
      esac
    fi
    # Unparseable summary status must fail open because Edit payloads may omit full content.
    exit 0
    ;;
  *.vbw-planning/*|*SUMMARY.md|*VERIFICATION.md|*STATE.md|*CLAUDE.md|*.execution-state.json)
    exit 0
    ;;
esac

[ -z "$PROJECT_ROOT" ] && exit 0
[ ! -d "$PHASES_DIR" ] && exit 0

_FG_STATUS_LIB="${_FG_SCRIPT_DIR}/summary-utils.sh"
if [ -f "$_FG_STATUS_LIB" ]; then
  # shellcheck source=summary-utils.sh
  source "$_FG_STATUS_LIB"
  is_plan_finalized() { is_summary_terminal "$1"; }
else
  is_plan_finalized() { return 1; }
fi

normalize_path() {
  local input_path="$1"
  local absolute_path absolute_root
  if [ -n "$PROJECT_ROOT" ]; then
    case "$input_path" in
      "$PROJECT_ROOT"/*)
        input_path="${input_path#"$PROJECT_ROOT"/}"
        ;;
      /*)
        absolute_path=$(to_abs_path "$input_path")
        absolute_root=$(to_abs_path "$PROJECT_ROOT")
        if [ "$absolute_path" = "$absolute_root" ]; then
          input_path=""
        elif [[ "$absolute_path" == "$absolute_root"/* ]]; then
          input_path="${absolute_path#"$absolute_root"/}"
        fi
        ;;
    esac
  fi
  input_path="${input_path#./}"
  echo "$input_path"
}

NORM_TARGET=$(normalize_path "$FILE_PATH")

CONFIG_PATH="$PROJECT_ROOT/.vbw-planning/config.json"
WORKTREE_ISOLATION="off"
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_PATH" ]; then
  WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' "$CONFIG_PATH" 2>/dev/null) || WORKTREE_ISOLATION="off"
fi
if [ "$WORKTREE_ISOLATION" != "off" ] && [ -n "${VBW_AGENT_ROLE:-}" ]; then
  case "${VBW_AGENT_ROLE:-}" in
    dev|debugger)
      AGENT_NAME_SHORT=$(echo "${VBW_AGENT_NAME:-}" | sed 's/.*vbw-//')
      WORKTREE_MAP_FILE="$PROJECT_ROOT/.vbw-planning/.agent-worktrees/${AGENT_NAME_SHORT}.json"
      if [ -f "$WORKTREE_MAP_FILE" ]; then
        WORKTREE_PATH=$(jq -r '.worktree_path // ""' "$WORKTREE_MAP_FILE" 2>/dev/null) || WORKTREE_PATH=""
        if [ -n "$WORKTREE_PATH" ]; then
          WORKTREE_ABS=$(to_abs_path "$WORKTREE_PATH")
          TARGET_ABS=$(to_abs_path "$FILE_PATH")
          case "$TARGET_ABS" in
            "$WORKTREE_ABS"/*|"$WORKTREE_ABS")
              :
              ;;
            *)
              echo "Blocked: write outside worktree boundary (expected prefix: $WORKTREE_ABS, got: $TARGET_ABS)" >&2
              exit 2
              ;;
          esac
        fi
      fi
      ;;
  esac
fi

CONTRACT_DIR="$PROJECT_ROOT/.vbw-planning/.contracts"
if [ -d "$CONTRACT_DIR" ]; then
  for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
    [ ! -f "$PLAN_FILE" ] && continue
    SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
    if ! is_plan_finalized "$SUMMARY_FILE"; then
      BASENAME=$(basename "$PLAN_FILE")
      PHASE_NUM=$(echo "$BASENAME" | sed 's/^\([0-9]*\)-.*/\1/')
      PLAN_NUM=$(echo "$BASENAME" | sed 's/^[0-9]*-\([0-9]*\)-.*/\1/')
      CONTRACT_FILE="${CONTRACT_DIR}/${PHASE_NUM}-${PLAN_NUM}.json"
      if [ -f "$CONTRACT_FILE" ]; then
        FORBIDDEN=$(jq -r '.forbidden_paths[]' "$CONTRACT_FILE" 2>/dev/null) || FORBIDDEN=""
        if [ -n "$FORBIDDEN" ]; then
          while IFS= read -r forbidden; do
            [ -z "$forbidden" ] && continue
            NORM_FORBIDDEN="${forbidden#./}"
            NORM_FORBIDDEN="${NORM_FORBIDDEN%/}"
            if [ "$NORM_TARGET" = "$NORM_FORBIDDEN" ] || [[ "$NORM_TARGET" == "$NORM_FORBIDDEN"/* ]]; then
              echo "Blocked: $NORM_TARGET is a forbidden path in contract (${CONTRACT_FILE})" >&2
              exit 2
            fi
          done <<< "$FORBIDDEN"
        fi
        ALLOWED=$(jq -r '.allowed_paths[]' "$CONTRACT_FILE" 2>/dev/null) || ALLOWED=""
        if [ -n "$ALLOWED" ]; then
          IN_SCOPE=false
          while IFS= read -r allowed; do
            [ -z "$allowed" ] && continue
            NORM_ALLOWED="${allowed#./}"
            if [ "$NORM_TARGET" = "$NORM_ALLOWED" ]; then
              IN_SCOPE=true
              break
            fi
          done <<< "$ALLOWED"
          if [ "$IN_SCOPE" = "false" ]; then
            echo "Blocked: $NORM_TARGET not in contract allowed_paths (${CONTRACT_FILE})" >&2
            exit 2
          fi
        fi
      fi
      break
    fi
  done
fi

if [ "$ACTIVE_AGENT_ROLE" = "qa" ] && [ -n "$PROJECT_ROOT" ]; then
  _FG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
  _FG_PLANNING_ABS=$(to_abs_path "$PROJECT_ROOT/.vbw-planning")
  case "$_FG_TARGET_ABS" in
    "$_FG_PLANNING_ABS"|"$_FG_PLANNING_ABS"/*)
      :
      ;;
    *)
      echo "Blocked: role 'qa' cannot write outside .vbw-planning/" >&2
      exit 2
      ;;
  esac
fi

_DG_PROJECT_ABS=$(to_abs_path "$PROJECT_ROOT")
_DG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
_DG_TARGET_IN_PROJECT=false
case "$_DG_TARGET_ABS" in
  "$_DG_PROJECT_ABS"|"$_DG_PROJECT_ABS"/*) _DG_TARGET_IN_PROJECT=true ;;
esac

if [ "$_DG_TARGET_IN_PROJECT" = true ] && [ -z "$ACTIVE_AGENT_ROLE" ] && [ -z "${VBW_AGENT_ROLE:-}" ] && [ -z "${VBW_ACTIVE_AGENT:-}" ] && [ "$_FG_CALLER_IS_DELEGATED" = false ]; then
  _DELEG_FILE="$PROJECT_ROOT/.vbw-planning/.delegated-workflow.json"
  _DG_MARKER_STATUS=""
  _DG_MARKER_LIVE="false"
  _DG_MARKER_MODE=""
  _DG_MARKER_EXEC_MODE=""
  if [ -f "$_DELEG_FILE" ]; then
    _DG_MARKER_STATUS=$(VBW_PLANNING_DIR="$PROJECT_ROOT/.vbw-planning" bash "${_FG_SCRIPT_DIR}/delegated-workflow.sh" status-json 2>/dev/null) || _DG_MARKER_STATUS=""
    if [ -n "$_DG_MARKER_STATUS" ]; then
      _DG_MARKER_LIVE=$(echo "$_DG_MARKER_STATUS" | jq -r '.live // false' 2>/dev/null) || _DG_MARKER_LIVE="false"
      _DG_MARKER_MODE=$(echo "$_DG_MARKER_STATUS" | jq -r '.mode // ""' 2>/dev/null) || _DG_MARKER_MODE=""
      _DG_MARKER_EXEC_MODE=$(echo "$_DG_MARKER_STATUS" | jq -r '.delegation_mode // ""' 2>/dev/null) || _DG_MARKER_EXEC_MODE=""
    fi

    if [ "$_DG_MARKER_LIVE" = "true" ] && [ "$_DG_MARKER_MODE" = "execute" ] && [ "$_DG_MARKER_EXEC_MODE" = "team" ]; then
      exit 0
    fi
  fi

  _DG_BLOCK=false
  _DG_EFFORT=""

  _EXEC_STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
  _EXEC_APPLICABLE=true
  if [ -f "$_EXEC_STATE_FILE" ] && [ -n "${CLAUDE_SESSION_ID:-}" ]; then
    _EXEC_SESSION_ID=$(jq -r '.session_id // ""' "$_EXEC_STATE_FILE" 2>/dev/null) || _EXEC_SESSION_ID=""
    if [ -n "$_EXEC_SESSION_ID" ] && [ "$_EXEC_SESSION_ID" != "${CLAUDE_SESSION_ID:-}" ]; then
      _EXEC_APPLICABLE=false
    fi
  fi
  if [ -f "$_EXEC_STATE_FILE" ] && [ "$_EXEC_APPLICABLE" = true ]; then
    _EXEC_STATUS=$(jq -r '.status // ""' "$_EXEC_STATE_FILE" 2>/dev/null) || _EXEC_STATUS=""
    if [ "$_EXEC_STATUS" = "running" ]; then
      _DG_NOW=$(date +%s 2>/dev/null || echo 0)
      if [ "$(uname)" = "Darwin" ]; then
        _DG_MTIME=$(stat -f %m "$_EXEC_STATE_FILE" 2>/dev/null || echo 0)
      else
        _DG_MTIME=$(stat -c %Y "$_EXEC_STATE_FILE" 2>/dev/null || echo 0)
      fi
      _DG_AGE=$((_DG_NOW - _DG_MTIME))
      if [ "$_DG_AGE" -ge 0 ] && [ "$_DG_AGE" -lt 14400 ]; then
        _DG_BLOCK=true
        _DG_EFFORT=$(jq -r '.effort // ""' "$_EXEC_STATE_FILE" 2>/dev/null) || _DG_EFFORT=""
      fi
    fi
  fi

  if [ "$_DG_BLOCK" = false ]; then
    if [ "$_DG_MARKER_LIVE" = "true" ]; then
      _DG_BLOCK=true
      _DG_EFFORT=$(echo "$_DG_MARKER_STATUS" | jq -r '.effort // ""' 2>/dev/null) || _DG_EFFORT=""
    fi
  fi

  if [ "$_DG_BLOCK" = true ]; then
    if [ -z "$_DG_EFFORT" ] || [ "$_DG_EFFORT" = "null" ]; then
      _DG_EFFORT=$(jq -r '.effort // "balanced"' "$PROJECT_ROOT/.vbw-planning/config.json" 2>/dev/null) || _DG_EFFORT="balanced"
    fi
    case "$_DG_EFFORT" in
      turbo|direct)
        :
        ;;
      *)
        echo "Blocked: orchestrator cannot write product files during delegated workflow (effort=$_DG_EFFORT). Delegate via Task tool to Dev/Debugger subagent." >&2
        exit 2
        ;;
    esac
  fi
fi

AGENT_ROLE="$ACTIVE_AGENT_ROLE"
if [ -n "$AGENT_ROLE" ]; then
  case "$AGENT_ROLE" in
    lead|architect|qa)
      echo "Blocked: role '${AGENT_ROLE}' cannot write outside .vbw-planning/" >&2
      exit 2
      ;;
    scout)
      echo "Blocked: role 'scout' is read-only" >&2
      exit 2
      ;;
    dev|debugger)
      ;;
    *)
      ;;
  esac
fi

execution_is_live() {
  local exec_state="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
  local exec_status now mtime age marker_status marker_live
  if [ -f "$exec_state" ]; then
    exec_status=$(jq -r '.status // ""' "$exec_state" 2>/dev/null) || exec_status=""
    if [ "$exec_status" = "running" ]; then
      now=$(date +%s 2>/dev/null || echo 0)
      if [ "$(uname)" = "Darwin" ]; then
        mtime=$(stat -f %m "$exec_state" 2>/dev/null || echo 0)
      else
        mtime=$(stat -c %Y "$exec_state" 2>/dev/null || echo 0)
      fi
      age=$((now - mtime))
      if [ "$age" -ge 0 ] && [ "$age" -lt 14400 ]; then
        return 0
      fi
    fi
  fi
  if [ -f "$PROJECT_ROOT/.vbw-planning/.delegated-workflow.json" ]; then
    marker_status=$(VBW_PLANNING_DIR="$PROJECT_ROOT/.vbw-planning" bash "${_FG_SCRIPT_DIR}/delegated-workflow.sh" status-json 2>/dev/null) || marker_status=""
    if [ -n "$marker_status" ]; then
      marker_live=$(echo "$marker_status" | jq -r '.live // false' 2>/dev/null) || marker_live="false"
      [ "$marker_live" = "true" ] && return 0
    fi
  fi
  return 1
}

# A planned-but-not-executing phase must not block unrelated work: only
# enforce files_modified while an execution is actually live.
execution_is_live || exit 0

ACTIVE_PLAN=""
for PLAN_FILE in "$PHASES_DIR"/*/*-PLAN.md; do
  [ ! -f "$PLAN_FILE" ] && continue
  SUMMARY_FILE="${PLAN_FILE%-PLAN.md}-SUMMARY.md"
  if ! is_plan_finalized "$SUMMARY_FILE"; then
    ACTIVE_PLAN="$PLAN_FILE"
    break
  fi
done

[ -z "$ACTIVE_PLAN" ] && exit 0

DECLARED_FILES=$(awk '
  BEGIN { in_front=0; in_files=0 }
  /^---$/ {
    if (in_front == 0) { in_front=1; next }
    else { exit }
  }
  in_front && /^files_modified:/ { in_files=1; next }
  in_front && in_files && /^[[:space:]]+- / {
    sub(/^[[:space:]]+- /, "")
    gsub(/["'"'"']/, "")
    print
    next
  }
  in_front && in_files && /^[^[:space:]]/ { in_files=0 }
' "$ACTIVE_PLAN" 2>/dev/null) || exit 0

[ -z "$DECLARED_FILES" ] && exit 0

while IFS= read -r declared; do
  [ -z "$declared" ] && continue
  NORM_DECLARED=$(normalize_path "$declared")
  if [ "$NORM_TARGET" = "$NORM_DECLARED" ]; then
    exit 0
  fi
done <<< "$DECLARED_FILES"

echo "Blocked: $NORM_TARGET is not in active plan's files_modified ($ACTIVE_PLAN)" >&2
exit 2
