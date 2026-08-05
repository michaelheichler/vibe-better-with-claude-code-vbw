#!/bin/bash
set -u

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
fi
if [ -f "$SCRIPT_DIR/lib/agent-manifest.sh" ]; then
  . "$SCRIPT_DIR/lib/agent-manifest.sh"
fi

find_project_root() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.vbw-planning/phases" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

resolve_project_root() {
  if [ -n "${VBW_PLANNING_DIR:-}" ] && [ -d "$VBW_PLANNING_DIR" ]; then
    cd "$VBW_PLANNING_DIR/.." 2>/dev/null && pwd -P 2>/dev/null
    return $?
  fi

  if [ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
    if source "$SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
      if find_vbw_root >/dev/null 2>&1 && [ -n "${VBW_CONFIG_ROOT:-}" ] && [ -n "${VBW_PLANNING_DIR:-}" ] && [ -d "$VBW_PLANNING_DIR" ]; then
        printf '%s\n' "$VBW_CONFIG_ROOT"
        return 0
      fi
    fi
  fi

  find_project_root
}

PROJECT_ROOT=$(resolve_project_root) || exit 0
GUARD_LOG="$PROJECT_ROOT/.vbw-planning/.agent-spawn-guard.log"
guard_breadcrumb() {
  local event="$1" timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
  printf '[%s] agent-spawn-guard %s\n' "$timestamp" "$event" >> "$GUARD_LOG" 2>/dev/null || true
}
guard_breadcrumb start
trap 'guard_breadcrumb complete' EXIT

MARKER_STATUS=$(VBW_PLANNING_DIR="$PROJECT_ROOT/.vbw-planning" bash "$SCRIPT_DIR/delegated-workflow.sh" status-json 2>/dev/null) || exit 0
[ -n "$MARKER_STATUS" ] || exit 0

MARKER_LIVE=$(echo "$MARKER_STATUS" | jq -r '.live // false' 2>/dev/null) || exit 0
MODE=$(echo "$MARKER_STATUS" | jq -r '.mode // ""' 2>/dev/null) || exit 0
DELEGATION_MODE=$(echo "$MARKER_STATUS" | jq -r '.delegation_mode // ""' 2>/dev/null) || exit 0
EXPECTED_TEAM_NAME=$(echo "$MARKER_STATUS" | jq -r '.team_name // ""' 2>/dev/null) || exit 0
MARKER_REASON=$(echo "$MARKER_STATUS" | jq -r '.reason // ""' 2>/dev/null) || exit 0
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // ""' 2>/dev/null) || exit 0
AGENT_NAME=$(echo "$INPUT" | jq -r '.tool_input.name // ""' 2>/dev/null) || exit 0
RUN_IN_BACKGROUND=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null) || exit 0

is_teammate_spawn_tool() {
  [ "$TOOL_NAME" = "Agent" ] || [ "$TOOL_NAME" = "TaskCreate" ]
}

requested_worktree_isolation() {
  local isolation=""
  isolation=$(echo "$INPUT" | jq -r '.tool_input.isolation // ""' 2>/dev/null) || return 1
  [ "$isolation" = "worktree" ]
}

requested_cwd_values() {
  echo "$INPUT" | jq -r '[.tool_input.cwd? // empty, .tool_input.working_dir? // empty, .tool_input.workingDirectory? // empty, .tool_input.workdir? // empty] | map(select(type == "string")) | .[]' 2>/dev/null \
    || return 1
}

requested_sidechain_cwd() {
  requested_cwd_values | grep -Eq '(^|/)\.claude/worktrees/agent-[^/]+(/|$)'
}

requested_vbw_worktree_cwd() {
  requested_cwd_values | grep -Eq '(^|/)\.vbw-worktrees(/|$)'
}

EXEC_STATE_FILE="$PROJECT_ROOT/.vbw-planning/.execution-state.json"
EXEC_ACTIVE=false
if [ -f "$EXEC_STATE_FILE" ] && jq empty "$EXEC_STATE_FILE" >/dev/null 2>&1; then
  EXEC_STATUS=$(jq -r '.status // ""' "$EXEC_STATE_FILE" 2>/dev/null) || EXEC_STATUS=""
  if [ "$EXEC_STATUS" = "running" ]; then
    if [ "$(uname)" = "Darwin" ]; then
      EXEC_MTIME=$(stat -f %m "$EXEC_STATE_FILE" 2>/dev/null || echo 0)
    else
      EXEC_MTIME=$(stat -c %Y "$EXEC_STATE_FILE" 2>/dev/null || echo 0)
    fi
    EXEC_NOW=$(date +%s 2>/dev/null || echo 0)
    EXEC_AGE=$((EXEC_NOW - EXEC_MTIME))
    if [ "$EXEC_AGE" -ge 0 ] && [ "$EXEC_AGE" -lt 14400 ]; then
      EXEC_ACTIVE=true
    fi
  fi
fi
VIBE_ACTIVE="$EXEC_ACTIVE"
if [ "$VIBE_ACTIVE" = true ]; then
  STATE_SESSION=$(jq -r '.session_id // ""' "$EXEC_STATE_FILE" 2>/dev/null) || STATE_SESSION=""
  CURRENT_SESSION=$(vbw_active_agent_session_id "$INPUT" 2>/dev/null || true)
  if [ -n "$STATE_SESSION" ] && [ -n "$CURRENT_SESSION" ] && [ "$STATE_SESSION" != "$CURRENT_SESSION" ]; then
    EXEC_ACTIVE=false
    VIBE_ACTIVE=false
    MARKER_LIVE=false
    MODE=""
    DELEGATION_MODE=""
  fi
fi
MANIFEST_PATH=""
if command -v agent_manifest_path >/dev/null 2>&1; then
  MANIFEST_PATH=$(agent_manifest_path "$PROJECT_ROOT/.vbw-planning" 2>/dev/null || true)
fi
MANIFEST_ACTIVE=false
[ "$VIBE_ACTIVE" = true ] && [ -n "$MANIFEST_PATH" ] && [ -f "$MANIFEST_PATH" ] && MANIFEST_ACTIVE=true
MANIFEST=""
if [ "$MANIFEST_ACTIVE" = true ] && ! MANIFEST=$(agent_manifest_read "$PROJECT_ROOT/.vbw-planning" 2>/dev/null); then
  echo "Blocked: the agent manifest is invalid. Use the agent generator flow to repair it before spawning." >&2
  exit 2
fi

manifest_spawn_fields() {
  local manifest="$1" name="$2"
  jq -c --arg name "$name" '
    ["name", "description", "prompt", "model", "effort", "run_in_background", "isolation", "mode", "max_turns", "maxTurns", "permissionMode", "team_name", "subject", "activeForm", "metadata"] as $fields
    | (.agents[$name].spawn // .agents[$name] // {})
    | with_entries(select(.key as $key | $fields | index($key)))
    | with_entries(select(.value != null))
    | if has("max_turns") then .maxTurns = .max_turns else . end
    | del(.max_turns)
    | if has("maxTurns") then
        .maxTurns = (try (.maxTurns | tonumber) catch null)
        | if (.maxTurns | type) == "number" and .maxTurns > 0 then . else del(.maxTurns) end
      else . end
  ' <<< "$manifest" 2>/dev/null
}

manifest_model_value() {
  local model="$1" alias
  [ -n "$model" ] || return 0
  [ "$model" != inherit ] || return 0
  alias=$(jq -r --arg id "$model" \
    '.aliases // {} | to_entries[] | select(.key | test("^(opus|sonnet|haiku|fable)$")) | select(.value == $id) | .key' \
    "$SCRIPT_DIR/../config/model-pricing.json" 2>/dev/null | head -1)
  printf '%s\n' "${alias:-$model}"
}

_claim_manifest_spawn_locked() {
  local name="$1" entry state now updated spawn current model
  MANIFEST=$(agent_manifest_read "$PROJECT_ROOT/.vbw-planning" 2>/dev/null) || return 1
  entry=$(jq -c --arg name "$name" '.agents[$name] // empty' <<< "$MANIFEST" 2>/dev/null) || return 1
  [ -n "$entry" ] || return 2
  state=$(jq -r '.state // ""' <<< "$entry" 2>/dev/null) || return 1
  [ "$state" = registered ] || return 3
  spawn=$(manifest_spawn_fields "$MANIFEST" "$name") || return 1
  model=$(jq -r '.model // empty' <<< "$spawn" 2>/dev/null) || model=""
  if [ "$model" = inherit ]; then
    spawn=$(jq 'del(.model)' <<< "$spawn") || return 1
  elif [ -n "$model" ]; then
    model=$(manifest_model_value "$model") || return 1
    spawn=$(jq --arg model "$model" '.model = $model' <<< "$spawn") || return 1
  fi
  current="${STRIPPED_INPUT:-}"
  [ -n "$current" ] && [ "$current" != null ] || current=$(echo "$INPUT" | jq '.tool_input' 2>/dev/null) || return 1
  STRIPPED_INPUT=$(jq --argjson spawn "$spawn" 'del(.max_turns, .maxTurns) * $spawn' <<< "$current") || return 1
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || true)
  [ -n "$now" ] || return 1
  updated=$(jq --arg name "$name" --arg now "$now" '.agents[$name].state = "running" | .agents[$name].started_at = $now | .agents[$name].last_activity_at = $now' <<< "$MANIFEST") || return 1
  agent_manifest_write "$PROJECT_ROOT/.vbw-planning" "$updated" >/dev/null 2>&1 || return 1
  MANIFEST="$updated"
  STRIP_REASON="enforced registered agent manifest for $name"
  return 0
}

claim_manifest_spawn() {
  agent_manifest_with_lock "$PROJECT_ROOT/.vbw-planning" _claim_manifest_spawn_locked "$1"
}

manifest_guard() {
  local state
  [ "$MANIFEST_ACTIVE" = true ] || return 0
  if claim_manifest_spawn "$SUBAGENT_TYPE"; then
    return 0
  fi
  state=$(jq -r --arg name "$SUBAGENT_TYPE" '.agents[$name].state // "unregistered"' <<< "$MANIFEST" 2>/dev/null || printf 'unregistered')
  if [ "$state" = registered ]; then
    echo "Blocked: registered agent '$SUBAGENT_TYPE' could not be claimed. Use the agent generator flow and retry." >&2
  elif [ "$state" = running ] || [ "$state" = used ] || [ "$state" = expired ]; then
    echo "Blocked: generated agent '$SUBAGENT_TYPE' is already $state and cannot be spawned again. Use the agent generator flow to register a fresh agent." >&2
  else
    echo "Blocked: agent '$SUBAGENT_TYPE' is not registered for this project. Use the agent generator flow to create and register it." >&2
  fi
  exit 2
}

if [ "$EXEC_ACTIVE" = true ] && { [ "$MARKER_LIVE" != "true" ] || [ "$MODE" != "execute" ] || [ -z "$DELEGATION_MODE" ]; }; then
  echo "Blocked: active execute run is missing live runtime delegation state (reason=${MARKER_REASON:-missing_marker}). Initialize execute delegation before spawning teammates." >&2
  exit 2
fi

emit_updated_input() {
  local updated_input="$1" reason="$2"
  local compact_input
  compact_input=$(echo "$updated_input" | jq -c '.' 2>/dev/null) || compact_input="$updated_input"
  jq -n -c --arg reason "$reason" --argjson input "$compact_input" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":$reason,"updatedInput":$input}}'
}

allow_with_strip() {
  if [ -n "${STRIP_REASON:-}" ] && [ -n "${STRIPPED_INPUT:-}" ] && [ "${STRIPPED_INPUT:-}" != "null" ]; then
    echo "${STRIP_WARN:-}" >&2
    emit_updated_input "${STRIPPED_INPUT:-}" "${STRIP_REASON:-}"
  fi
  exit 0
}

if is_teammate_spawn_tool; then
  if requested_vbw_worktree_cwd; then
    echo "Blocked: teammate spawn requested a VBW worktree path as a spawn working directory. Omit cwd/working_dir/workingDirectory/workdir fields; VBW worktree targeting is task prompt/state metadata, not a spawn cwd." >&2
    exit 2
  fi
  STRIP_REASON=""
  STRIP_WARN=""
  if requested_sidechain_cwd; then
    STRIPPED_INPUT=$(echo "$INPUT" | jq '.tool_input | del(.cwd, .working_dir, .workingDirectory, .workdir, .isolation)' 2>/dev/null)
    STRIP_REASON="VBW stripped sidechain cwd fields, worktree targeting is task metadata, not spawn cwd"
    STRIP_WARN="VBW guard: stripped sidechain cwd fields (and isolation if present) from $TOOL_NAME spawn (models add these spontaneously; blocking causes infinite retry loops)"
  elif requested_worktree_isolation; then
    STRIPPED_INPUT=$(echo "$INPUT" | jq '.tool_input | del(.isolation)' 2>/dev/null)
    STRIP_REASON="VBW stripped isolation:worktree, worktree isolation is not managed via spawn params"
    STRIP_WARN="VBW guard: stripped isolation:worktree from $TOOL_NAME spawn (models add this spontaneously; blocking causes infinite retry loops)"
  fi

  SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // ""' 2>/dev/null) || exit 0
  manifest_guard
  MODEL_ROLE=""
  case "$SUBAGENT_TYPE" in
    vbw:vbw-dev|vbw-dev) MODEL_ROLE="dev" ;;
    vbw:vbw-qa|vbw-qa|vbw:vbw-qa-author|vbw-qa-author) MODEL_ROLE="qa" ;;
    vbw:vbw-scout|vbw-scout) MODEL_ROLE="scout" ;;
    vbw:vbw-lead|vbw-lead) MODEL_ROLE="lead" ;;
    vbw:vbw-architect|vbw-architect) MODEL_ROLE="architect" ;;
    vbw:vbw-debugger|vbw-debugger) MODEL_ROLE="debugger" ;;
    vbw:vbw-docs|vbw-docs) MODEL_ROLE="docs" ;;
  esac

  if [ -n "$MODEL_ROLE" ]; then
    if RESOLVED_MODEL=$(bash "$SCRIPT_DIR/resolve-agent-model.sh" "$MODEL_ROLE" "$PROJECT_ROOT/.vbw-planning/config.json" "$SCRIPT_DIR/../config/model-profiles.json" 2>/dev/null) && [ -n "$RESOLVED_MODEL" ]; then
      SPAWN_ALIAS=$(jq -r --arg id "$RESOLVED_MODEL" \
        '.aliases // {} | to_entries[] | select(.key | test("^(opus|sonnet|haiku|fable)$")) | select(.value == $id) | .key' \
        "$SCRIPT_DIR/../config/model-pricing.json" 2>/dev/null | head -1)
      if [ -n "$SPAWN_ALIAS" ]; then
        RESOLVED_MODEL="$SPAWN_ALIAS"
      elif [[ "$RESOLVED_MODEL" == claude-* ]]; then
        printf 'VBW guard: pricing alias missing for built-in model %s\n' "$RESOLVED_MODEL" >&2
      fi
      MODEL_CHANGED=true
      if echo "$INPUT" | jq -e --arg model "$RESOLVED_MODEL" '(.tool_input.model? // null) == $model' >/dev/null 2>&1; then
        MODEL_CHANGED=false
      fi
      if [ "$MODEL_CHANGED" = true ]; then
        if [ -n "${STRIPPED_INPUT:-}" ] && [ "${STRIPPED_INPUT:-}" != "null" ]; then
          STRIPPED_INPUT=$(echo "$STRIPPED_INPUT" | jq --arg model "$RESOLVED_MODEL" '.model = $model' 2>/dev/null) || exit 0
          STRIP_REASON="${STRIP_REASON:+$STRIP_REASON; }enforced resolved model for $SUBAGENT_TYPE"
        else
          STRIPPED_INPUT=$(echo "$INPUT" | jq --arg model "$RESOLVED_MODEL" '.tool_input | .model = $model' 2>/dev/null) || exit 0
          STRIP_REASON="enforced resolved model for $SUBAGENT_TYPE"
        fi
      fi

      REASONING_PROFILES_PATH="$SCRIPT_DIR/../config/reasoning-profiles.json"
      if [ -f "$REASONING_PROFILES_PATH" ]; then
        if RESOLVED_REASONING=$(bash "$SCRIPT_DIR/resolve-agent-reasoning.sh" "$MODEL_ROLE" "$PROJECT_ROOT/.vbw-planning/config.json" "$REASONING_PROFILES_PATH" "$RESOLVED_MODEL" "$SCRIPT_DIR/../config/model-pricing.json" 2>/dev/null); then
          CURRENT_INPUT="${STRIPPED_INPUT:-}"
          if [ -z "$CURRENT_INPUT" ] || [ "$CURRENT_INPUT" = "null" ]; then
            CURRENT_INPUT=$(echo "$INPUT" | jq '.tool_input' 2>/dev/null) || exit 0
          fi
          CURRENT_EFFORT=$(echo "$CURRENT_INPUT" | jq -r '.effort // empty' 2>/dev/null) || CURRENT_EFFORT=""
          CURRENT_EFFORT_PRESENT=false
          if echo "$CURRENT_INPUT" | jq -e 'has("effort")' >/dev/null 2>&1; then
            CURRENT_EFFORT_PRESENT=true
          fi

          if [ -n "$RESOLVED_REASONING" ]; then
            if [ "$CURRENT_EFFORT" != "$RESOLVED_REASONING" ]; then
              if [ -n "${STRIPPED_INPUT:-}" ] && [ "${STRIPPED_INPUT:-}" != "null" ]; then
                STRIPPED_INPUT=$(echo "$STRIPPED_INPUT" | jq --arg effort "$RESOLVED_REASONING" '.effort = $effort' 2>/dev/null) || exit 0
              else
                STRIPPED_INPUT=$(echo "$INPUT" | jq --arg effort "$RESOLVED_REASONING" '.tool_input | .effort = $effort' 2>/dev/null) || exit 0
              fi
              STRIP_REASON="${STRIP_REASON:+$STRIP_REASON; }enforced resolved reasoning for $SUBAGENT_TYPE"
            fi
          elif [ "$CURRENT_EFFORT_PRESENT" = true ]; then
            if [ -n "${STRIPPED_INPUT:-}" ] && [ "${STRIPPED_INPUT:-}" != "null" ]; then
              STRIPPED_INPUT=$(echo "$STRIPPED_INPUT" | jq 'del(.effort)' 2>/dev/null) || exit 0
            else
              STRIPPED_INPUT=$(echo "$INPUT" | jq '.tool_input | del(.effort)' 2>/dev/null) || exit 0
            fi
            STRIP_REASON="${STRIP_REASON:+$STRIP_REASON; }removed unsupported reasoning for $SUBAGENT_TYPE"
          fi
        fi
      fi
    else
      echo "VBW guard: could not resolve model for $SUBAGENT_TYPE, passing spawn through unchanged" >&2
      STRIPPED_INPUT=""
      STRIP_REASON=""
      STRIP_WARN=""
    fi
  fi
fi

[ "$MARKER_LIVE" = "true" ] || {
  allow_with_strip
}
[ "$MODE" = "execute" ] || {
  allow_with_strip
}
[ -n "$DELEGATION_MODE" ] || {
  allow_with_strip
}

case "$DELEGATION_MODE" in
  team)
    if [ -z "$TEAM_NAME" ]; then
      echo "Blocked: execute team mode requires team-scoped agent spawns. Missing team_name on Agent spawn${AGENT_NAME:+ ($AGENT_NAME)}." >&2
      exit 2
    fi
    if [ -z "$AGENT_NAME" ]; then
      echo "Blocked: execute team mode requires teammate name metadata on team-scoped spawns." >&2
      exit 2
    fi
    if [ -n "$EXPECTED_TEAM_NAME" ] && [ "$TEAM_NAME" != "$EXPECTED_TEAM_NAME" ]; then
      echo "Blocked: execute team mode requires team_name '$EXPECTED_TEAM_NAME', got '$TEAM_NAME'." >&2
      exit 2
    fi
    ;;
  subagent|direct)
    if [ -n "$TEAM_NAME" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot attach team_name '$TEAM_NAME'. Use true team mode or explicit non-team execution." >&2
      exit 2
    fi
    if [ "$TOOL_NAME" = "TaskCreate" ]; then
      if ! SPAWN_SESSION_ID=$(vbw_active_agent_session_id "$INPUT" 2>/dev/null); then
        echo "Blocked: execute delegation mode '$DELEGATION_MODE' must serialize non-team TaskCreate spawns. Wait for the current teammate to finish before starting another." >&2
        exit 2
      fi
      ACTIVE_COUNT=0
      if command -v vbw_active_agent_current_count >/dev/null 2>&1; then
        ACTIVE_COUNT=$(vbw_active_agent_current_count "$PROJECT_ROOT/.vbw-planning" "$INPUT")
      elif [ -f "$PROJECT_ROOT/.vbw-planning/.active-agents/$SPAWN_SESSION_ID/active-agent-count" ]; then
        ACTIVE_COUNT=$(cat "$PROJECT_ROOT/.vbw-planning/.active-agents/$SPAWN_SESSION_ID/active-agent-count" 2>/dev/null | tr -d '[:space:]')
      fi
      if ! printf '%s' "$ACTIVE_COUNT" | grep -Eq '^[0-9]+$'; then
        ACTIVE_COUNT=0
      fi
      if [ "$ACTIVE_COUNT" -gt 0 ]; then
        echo "Blocked: execute delegation mode '$DELEGATION_MODE' must serialize non-team TaskCreate spawns. Wait for the current teammate to finish before starting another." >&2
        exit 2
      fi
    fi
    if [ "$RUN_IN_BACKGROUND" = "true" ]; then
      echo "Blocked: execute delegation mode '$DELEGATION_MODE' cannot simulate team mode with background Agent spawns. Use explicit non-team execution (wait for each agent) or switch to true team mode." >&2
      exit 2
    fi
    ;;
esac

allow_with_strip

exit 0
