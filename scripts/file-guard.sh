#!/bin/bash
set -u
_FG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_FG_SCRIPT_DIR/lib/active-agent-state.sh" ] || { printf 'Blocked: VBW guard library missing (%s)\n' "$_FG_SCRIPT_DIR/lib/active-agent-state.sh" >&2; exit 2; }
[ -f "$_FG_SCRIPT_DIR/lib/orchestrator-identity.sh" ] || { printf 'Blocked: VBW guard library missing (%s)\n' "$_FG_SCRIPT_DIR/lib/orchestrator-identity.sh" >&2; exit 2; }
[ -f "$_FG_SCRIPT_DIR/lib/guard-enforcement.sh" ] || { printf 'Blocked: VBW guard library missing (%s)\n' "$_FG_SCRIPT_DIR/lib/guard-enforcement.sh" >&2; exit 2; }
. "$_FG_SCRIPT_DIR/lib/active-agent-state.sh" || { printf 'Blocked: VBW guard library failed to load (%s)\n' "$_FG_SCRIPT_DIR/lib/active-agent-state.sh" >&2; exit 2; }
. "$_FG_SCRIPT_DIR/lib/orchestrator-identity.sh" || { printf 'Blocked: VBW guard library failed to load (%s)\n' "$_FG_SCRIPT_DIR/lib/orchestrator-identity.sh" >&2; exit 2; }
. "$_FG_SCRIPT_DIR/lib/guard-enforcement.sh" || { printf 'Blocked: VBW guard library failed to load (%s)\n' "$_FG_SCRIPT_DIR/lib/guard-enforcement.sh" >&2; exit 2; }
if [ -f "$_FG_SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
  if source "$_FG_SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
    find_vbw_root >/dev/null 2>&1 || true
  fi
fi
PROJECT_ROOT=$(vbw_guard_project_root "$PWD") || PROJECT_ROOT=""
if [ -n "$PROJECT_ROOT" ]; then
  PHASES_DIR="$PROJECT_ROOT/.vbw-planning/phases"
else
  PHASES_DIR=""
fi
GUARD_LEVEL=$(vbw_guard_enforcement_level "$PROJECT_ROOT" "")
[ "$GUARD_LEVEL" = "off" ] && exit 0

guard_log_event() {
  local message="$1" level="${2:-${GUARD_LEVEL:-enforce}}" agent="${ACTIVE_AGENT_ROLE:-${VBW_ACTIVE_AGENT:-unknown}}"
  [ -d "$PROJECT_ROOT/.vbw-planning" ] || return 0
  if command -v jq >/dev/null 2>&1 && jq -cn --arg message "$message" --arg level "$level" --arg agent "$agent" \
    '{event:"guard_block",level:$level,message:$message,agent:$agent}' \
    >> "$PROJECT_ROOT/.vbw-planning/.event-log.jsonl" 2>/dev/null; then
    return 0
  fi
  message=$(printf '%s' "$message" | tr '\r\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
  agent=$(printf '%s' "$agent" | tr '\r\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
  printf '{"event":"guard_block","level":"%s","message":"%s","agent":"%s"}\n' \
    "$level" "$message" "$agent" >> "$PROJECT_ROOT/.vbw-planning/.event-log.jsonl" 2>/dev/null || true
}

guard_block() {
  local message="$*"
  if [ "$GUARD_LEVEL" = "enforce" ]; then
    guard_log_event "$message"
    printf '%s\n' "$message" >&2
    exit 2
  fi
  guard_log_event "$message"
  exit 0
}

INPUT=$(cat 2>/dev/null) || guard_block "Blocked: unable to read file guard input"
[ -n "$INPUT" ] || guard_block "Blocked: empty file guard input"
GUARD_LEVEL=$(vbw_guard_enforcement_level "$PROJECT_ROOT" "$INPUT")
[ "$GUARD_LEVEL" = "off" ] && exit 0
if ! FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null); then
  guard_block "Blocked: invalid file guard input"
fi
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in
  *$'\n'*) guard_block "Blocked: newline in file path" ;;
esac


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
    "/"*) base="$p" ;;
    *)
      cwd_base=$(pwd -P 2>/dev/null || pwd)
      base="$cwd_base/${p#./}"
      ;;
  esac
  resolve_lexical_path "$base"
}

guard_block_always() {
  local message="$*"
  guard_log_event "$message" enforce
  printf '%s\n' "$message" >&2
  exit 2
}

normalize_agent_role() {
  command -v vbw_active_agent_normalize_role >/dev/null 2>&1 || return 1
  vbw_active_agent_normalize_role "$1"
}

normalize_payload_agent_role() {
  command -v vbw_active_agent_normalize_payload_role >/dev/null 2>&1 || return 1
  vbw_active_agent_normalize_payload_role "$1"
}

_FG_PAYLOAD_AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null) || _FG_PAYLOAD_AGENT_TYPE=""
_FG_PAYLOAD_AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // .agent_name // .agentName // ""' 2>/dev/null) || _FG_PAYLOAD_AGENT_ID=""
_FG_PAYLOAD_HAS_AGENT=false
if [ -n "$_FG_PAYLOAD_AGENT_TYPE" ] || [ -n "$_FG_PAYLOAD_AGENT_ID" ]; then
  _FG_PAYLOAD_HAS_AGENT=true
fi
_FG_CALLER_IS_DELEGATED="$_FG_PAYLOAD_HAS_AGENT"

# Caller hints are advisory because they are not a security boundary.
if [ "${CLAUDE_CODE_CHILD_SESSION:-}" = "1" ]; then
  _FG_CALLER_IS_DELEGATED=true
fi

# Environment roles take precedence because VBW exports them for spawned agents.
detect_agent_role() {
  local candidate role
  for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
    [ -z "$candidate" ] && continue
    role=$(normalize_agent_role "$candidate") || continue
    printf '%s' "$role"
    return 0
  done
  for candidate in "$_FG_PAYLOAD_AGENT_TYPE" "$_FG_PAYLOAD_AGENT_ID"; do
    [ -z "$candidate" ] && continue
    role=$(normalize_payload_agent_role "$candidate") || continue
    printf '%s' "$role"
    return 0
  done
  if [ "$_FG_PAYLOAD_HAS_AGENT" != true ]; then
    _FG_SESSION_ID=$(vbw_active_agent_session_id "$INPUT" 2>/dev/null) || _FG_SESSION_ID="${CLAUDE_SESSION_ID:-}"
    if vbw_orchestrator_instance_id "$_FG_SESSION_ID" >/dev/null 2>&1; then
      printf 'orchestrator'
      return 0
    fi
    return 1
  fi
  guard_block "Blocked: unrecognized agent evidence (agent_type=$_FG_PAYLOAD_AGENT_TYPE, agent_id=$_FG_PAYLOAD_AGENT_ID); role cannot be confirmed."
  return 2
}

ACTIVE_AGENT_ROLE=""
if ACTIVE_AGENT_ROLE=$(detect_agent_role); then
  :
else
  _FG_ROLE_STATUS=$?
  ACTIVE_AGENT_ROLE=""
  [ "$_FG_ROLE_STATUS" -eq 2 ] && exit "$_FG_ROLE_STATUS"
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
      guard_block_always "Blocked: wrong naming convention for $_FG_TYPE artifact. Use {NN}-${_FG_TYPE}.md (e.g., 01-${_FG_TYPE}.md), not ${_FG_TYPE}-{NN}.md ($_BASENAME_CHECK)"
    fi
    ;;
esac

# Reject sidechain targets before planning exemptions because VBW never merges writes from Claude internal worktrees.
if [ -n "${VBW_CLAUDE_SIDECHAIN_ROOT:-}" ] && [ -n "${VBW_CLAUDE_SIDECHAIN_HOST_ROOT:-}" ]; then
  _FG_SIDECHAIN_BLOCK=false
  _FG_BLOCKED_TARGET="$FILE_PATH"

  case "$FILE_PATH" in
    "/"*)
      _FG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
      case "$_FG_TARGET_ABS" in
        "$VBW_CLAUDE_SIDECHAIN_ROOT"|"$VBW_CLAUDE_SIDECHAIN_ROOT""/"*)
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
    guard_block_always "Blocked: Claude sidechain write target
blocked target: $_FG_BLOCKED_TARGET
host repo: $VBW_CLAUDE_SIDECHAIN_HOST_ROOT
retry: retry the same Write/Edit with an absolute path under the host repo, not the Claude sidechain path.
reason: VBW will not merge or use writes made inside Claude's internal sidechain."
  fi
fi

if [ "$ACTIVE_AGENT_ROLE" = "scout" ] && [ -n "$PROJECT_ROOT" ]; then
  _FG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
  _FG_PLANNING_ABS=$(to_abs_path "$PROJECT_ROOT/.vbw-planning")
  case "$_FG_TARGET_ABS" in
    "$_FG_PLANNING_ABS"|"$_FG_PLANNING_ABS""/"*)
      :
      ;;
    *)
      guard_block "Blocked: Scout-safe active-agent context is read-only outside .vbw-planning/"
      ;;
  esac
fi

case "$FILE_PATH" in
  *.vbw-planning/milestones/*/phases"/"*)
    # Other milestone root files must fall through because archival writes SHIPPED.md and moves STATE.md and ROADMAP.md.
    guard_block_always "Blocked: writes to archived milestone phases are not allowed ($FILE_PATH)"
    ;;
  *.vbw-planning/*/remediation/uat/round-*/R[0-9]*-SUMMARY.md|\
  *.vbw-planning/*/remediation/qa/round-*/R[0-9]*-SUMMARY.md)
    exit 0
    ;;
  *.vbw-planning/*-SUMMARY.md)
    _FG_SUM_STATUS=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null | sed -n '
      /^---$/,/^---$/ {
        /^status:/ {
          s/^status:[[:space:]]*//
          s/["'"'"']//g
          p
        }
      }
    ' | head -1 | tr -d '[:space:]')
    if [ -n "$_FG_SUM_STATUS" ]; then
      case "$_FG_SUM_STATUS" in
        complete|completed|partial|failed) ;;
        *)
          guard_block_always "Blocked: SUMMARY.md status '${_FG_SUM_STATUS}' is not terminal (must be complete|partial|failed)"
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
  is_plan_finalized() {
    bash -c '. "$1"; is_summary_terminal "$2"' _ "$_FG_STATUS_LIB" "$1"
  }
else
  is_plan_finalized() { return 1; }
fi

normalize_path() {
  local input_path="$1"
  local absolute_path absolute_root
  if [ -n "$PROJECT_ROOT" ]; then
    case "$input_path" in
      "$PROJECT_ROOT""/"*)
        input_path="${input_path#"$PROJECT_ROOT"/}"
        ;;
      "/"*)
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

declare -A _FG_PATTERN_MATCH_CACHE=()

path_pattern_components_match_at() {
  local target_index="$1" pattern_index="$2" cache_key result
  local target_segment pattern_segment
  local target_count="${#_FG_TARGET_COMPONENTS[@]}" pattern_count="${#_FG_PATTERN_COMPONENTS[@]}"
  cache_key="$target_index:$pattern_index"
  if [ -n "${_FG_PATTERN_MATCH_CACHE["$cache_key"]+set}" ]; then
    return "${_FG_PATTERN_MATCH_CACHE["$cache_key"]}"
  fi
  if [ "$pattern_index" -eq "$pattern_count" ]; then
    result=1
    [ "$target_index" -eq "$target_count" ] && result=0
  else
    pattern_segment="${_FG_PATTERN_COMPONENTS[$pattern_index]}"
    if [ "$target_index" -ge "$target_count" ] && [ "$pattern_segment" != "**" ]; then
      result=1
    elif [ "$pattern_segment" = "**" ]; then
      result=1
      path_pattern_components_match_at "$target_index" "$((pattern_index + 1))" && result=0
      if [ "$result" -ne 0 ] && [ "$target_index" -lt "$target_count" ] && path_pattern_components_match_at "$((target_index + 1))" "$pattern_index"; then
        result=0
      fi
    else
      result=1
      target_segment="${_FG_TARGET_COMPONENTS[$target_index]}"
      # shellcheck disable=SC2254 # Because quoting would disable lexical glob matching.
      case "$target_segment" in
        $pattern_segment) path_pattern_components_match_at "$((target_index + 1))" "$((pattern_index + 1))" && result=0 ;;
      esac
    fi
  fi
  _FG_PATTERN_MATCH_CACHE["$cache_key"]="$result"
  return "$result"
}

path_pattern_split_components() {
  local value="$1" target_array="$2" part
  if [ "$target_array" = target ]; then _FG_TARGET_COMPONENTS=(); else _FG_PATTERN_COMPONENTS=(); fi
  while [[ "$value" == */* ]]; do
    part="${value%%/*}"
    if [ "$target_array" = target ]; then _FG_TARGET_COMPONENTS+=("$part"); else _FG_PATTERN_COMPONENTS+=("$part"); fi
    value="${value#*/}"
  done
  if [ "$target_array" = target ]; then _FG_TARGET_COMPONENTS+=("$value"); else _FG_PATTERN_COMPONENTS+=("$value"); fi
}

path_pattern_components_match() {
  local target="$1" pattern="$2"
  path_pattern_split_components "$target" target
  path_pattern_split_components "$pattern" pattern
  _FG_PATTERN_MATCH_CACHE=()
  path_pattern_components_match_at 0 0
}

# shellcheck disable=SC2254 # Because quoting would disable lexical glob matching.
path_matches_pattern() {
  local target="$1" pattern="$2"
  local prefix alternatives suffix alternative expanded_pattern
  local -a brace_alternatives

  [ "$target" = "$pattern" ] && return 0

  case "$pattern" in
    *"{"*"}"*)
      prefix="${pattern%%\{*}"
      alternatives="${pattern#*\{}"
      alternatives="${alternatives%%\}*}"
      suffix="${pattern#*\{*\}}"
      IFS=',' read -r -a brace_alternatives <<< "$alternatives"
      for alternative in "${brace_alternatives[@]}"; do
        expanded_pattern="${prefix}${alternative}${suffix}"
        path_pattern_components_match "$target" "$expanded_pattern" && return 0
      done
      ;;
    *"*"*|*"?"*|*"["*)
      path_pattern_components_match "$target" "$pattern" && return 0
      ;;
  esac
  return 1
}

path_matches_declared_scope() {
  local target="$1" declared="$2" declared_dir
  path_matches_pattern "$target" "$declared" && return 0
  case "$declared" in
    */|*'*'*|*'?'*|*'['*) ;;
    *) return 1 ;;
  esac
  declared_dir=$(dirname "$declared")
  if [ "$declared_dir" = "." ] || [ -z "$declared_dir" ]; then
    return 1
  fi
  path_matches_pattern "$target" "${declared_dir%/}/**"
}

path_matches_files_modified_scope() {
  local target="$1" declared="$2" declared_dir
  path_matches_pattern "$target" "$declared" && return 0
  declared_dir=$(dirname "$declared")
  [ "$declared_dir" != "." ] || return 1
  path_matches_pattern "$target" "${declared_dir%/}/**"
}

NORM_TARGET=$(normalize_path "$FILE_PATH")

CONFIG_PATH="$PROJECT_ROOT/.vbw-planning/config.json"
WORKTREE_ISOLATION="off"
if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_PATH" ]; then
  WORKTREE_ISOLATION=$(jq -r '.worktree_isolation // "off"' "$CONFIG_PATH" 2>/dev/null) || WORKTREE_ISOLATION="off"
fi
if [ "$WORKTREE_ISOLATION" != "off" ] && [ -n "$ACTIVE_AGENT_ROLE" ]; then
  case "$ACTIVE_AGENT_ROLE" in
    dev|debugger)
      AGENT_NAME_SHORT="${VBW_AGENT_NAME:-${_FG_PAYLOAD_AGENT_ID:-}}"
      case "$AGENT_NAME_SHORT" in
        @vbw:*) AGENT_NAME_SHORT="${AGENT_NAME_SHORT#@vbw:}" ;;
        vbw:*) AGENT_NAME_SHORT="${AGENT_NAME_SHORT#vbw:}" ;;
      esac
      case "$AGENT_NAME_SHORT" in
        *vbw-*) AGENT_NAME_SHORT="${AGENT_NAME_SHORT##*vbw-}" ;;
      esac
      if [ -z "$AGENT_NAME_SHORT" ]; then
        guard_block "Blocked: worktree mapping cannot be resolved for role '$ACTIVE_AGENT_ROLE'"
      fi
      WORKTREE_MAP_FILE="$PROJECT_ROOT/.vbw-planning/.agent-worktrees/${AGENT_NAME_SHORT}.json"
      if [ ! -f "$WORKTREE_MAP_FILE" ]; then
        guard_block "Blocked: worktree mapping missing for agent '$AGENT_NAME_SHORT'"
      fi
      WORKTREE_PATH=$(jq -r '.worktree_path // ""' "$WORKTREE_MAP_FILE" 2>/dev/null) || WORKTREE_PATH=""
      if [ -z "$WORKTREE_PATH" ]; then
        guard_block "Blocked: worktree mapping has no path for agent '$AGENT_NAME_SHORT'"
      fi
      WORKTREE_ABS=$(to_abs_path "$WORKTREE_PATH")
      TARGET_ABS=$(to_abs_path "$FILE_PATH")
      case "$TARGET_ABS" in
        "$WORKTREE_ABS"/*|"$WORKTREE_ABS")
          :
          ;;
        *)
          guard_block "Blocked: write outside worktree boundary (expected prefix: $WORKTREE_ABS, got: $TARGET_ABS)"
          ;;
      esac
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
              guard_block_always "Blocked: $NORM_TARGET is a forbidden path in contract (${CONTRACT_FILE})"
            fi
          done <<< "$FORBIDDEN"
        fi
        ALLOWED=$(jq -r '.allowed_paths[]' "$CONTRACT_FILE" 2>/dev/null) || ALLOWED=""
        if [ -n "$ALLOWED" ]; then
          IN_SCOPE=false
          while IFS= read -r allowed; do
            [ -z "$allowed" ] && continue
            NORM_ALLOWED="${allowed#./}"
            if path_matches_declared_scope "$NORM_TARGET" "$NORM_ALLOWED" || {
              vbw_guard_execution_is_live "$PROJECT_ROOT" &&
              path_matches_files_modified_scope "$NORM_TARGET" "$NORM_ALLOWED"
            }; then
              IN_SCOPE=true
              break
            fi
          done <<< "$ALLOWED"
          if [ "$IN_SCOPE" = "false" ]; then
            guard_block_always "Blocked: $NORM_TARGET not in contract allowed_paths (${CONTRACT_FILE})"
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
    "$_FG_PLANNING_ABS"|"$_FG_PLANNING_ABS""/"*)
      :
      ;;
    *)
      guard_block "Blocked: role 'qa' cannot write outside .vbw-planning/"
      ;;
  esac
fi

_DG_PROJECT_ABS=$(to_abs_path "$PROJECT_ROOT")
_DG_TARGET_ABS=$(to_abs_path "$FILE_PATH")
_DG_TARGET_IN_PROJECT=false
case "$_DG_TARGET_ABS" in
  "$_DG_PROJECT_ABS"|"$_DG_PROJECT_ABS""/"*) _DG_TARGET_IN_PROJECT=true ;;
esac

if [ "$_DG_TARGET_IN_PROJECT" = true ] && [ -z "${VBW_AGENT_ROLE:-}" ] && [ -z "${VBW_ACTIVE_AGENT:-}" ] && [ "$_FG_CALLER_IS_DELEGATED" = false ]; then
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
        guard_block "Blocked: orchestrator cannot write product files during delegated workflow (effort=$_DG_EFFORT). Delegate via Task tool to Dev/Debugger subagent."
        ;;
    esac
  fi
fi

AGENT_ROLE="$ACTIVE_AGENT_ROLE"
if [ -n "$AGENT_ROLE" ]; then
  case "$AGENT_ROLE" in
    lead|architect|qa)
      guard_block "Blocked: role '${AGENT_ROLE}' cannot write outside .vbw-planning/"
      ;;
    scout)
      guard_block "Blocked: role 'scout' is read-only"
      ;;
    dev|debugger)
      ;;
    *)
      ;;
  esac
fi

vbw_guard_execution_is_live "$PROJECT_ROOT" || exit 0

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
  if path_matches_files_modified_scope "$NORM_TARGET" "$NORM_DECLARED"; then
    exit 0
  fi
done <<< "$DECLARED_FILES"

guard_block "Blocked: $NORM_TARGET is not in active plan's files_modified ($ACTIVE_PLAN)"
