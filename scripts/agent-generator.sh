#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/lib/agent-manifest.sh"
. "$SCRIPT_DIR/lib/guard-enforcement.sh"

fail() {
  printf 'agent-generator: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: agent-generator.sh <role> --job <text> [overrides]\n' >&2
  exit 1
}

ROLE="${1:-}"
[ -n "$ROLE" ] || usage
ROLE="${ROLE#vbw-}"
shift
case "$ROLE" in
  architect|debugger|dev|docs|lead|qa-author|qa|scout) ;;
  *) fail "invalid role '$ROLE'" ;;
esac

declare -A OVERRIDES=()
JOB=""

option_token() {
  case "$1" in
    --description) printf 'DESCRIPTION' ;;
    --tools) printf 'TOOLS' ;;
    --disallowed-tools) printf 'DISALLOWED_TOOLS' ;;
    --permission-mode) printf 'PERMISSION_MODE' ;;
    --max-turns) printf 'MAX_TURNS' ;;
    --skills) printf 'SKILLS' ;;
    --mcp-servers) printf 'MCP_SERVERS' ;;
    --memory) printf 'MEMORY' ;;
    --background) printf 'BACKGROUND' ;;
    --isolation) printf 'ISOLATION' ;;
    --color) printf 'COLOR' ;;
    --initial-prompt) printf 'INITIAL_PROMPT' ;;
    --model) printf 'MODEL' ;;
    --effort) printf 'EFFORT' ;;
    --reasoning) printf 'REASONING' ;;
    *) return 1 ;;
  esac
}

parse_options() {
  local argument key value token
  while [ "$#" -gt 0 ]; do
    argument="$1"
    shift
    if [[ "$argument" == --*=* ]]; then
      key="${argument%%=*}"
      value="${argument#*=}"
    else
      key="$argument"
      [ "$#" -gt 0 ] || fail "missing value for $key"
      value="$1"
      shift
    fi
    if [ "$key" = "--job" ]; then
      JOB="$value"
      continue
    fi
    token=$(option_token "$key") || fail "unknown option '$key'"
    OVERRIDES["$token"]="$value"
  done
}

find_project_root() {
  local root
  root=$(vbw_guard_project_root "$PWD" 2>/dev/null) || root=""
  [ -n "$root" ] || fail "cannot find initialized project (.vbw-planning)"
  printf '%s\n' "$root"
}

load_words() {
  local file="$1" target="$2"
  local -n words="$target"
  [ -f "$file" ] || fail "wordlist not found: $file"
  mapfile -t words < <(grep -E '^[a-z0-9]+$' "$file" || true)
  [ "${#words[@]}" -gt 0 ] || fail "wordlist is empty: $file"
}

pick_word() {
  local array_name="$1"
  local -n word_array="$array_name"
  printf '%s\n' "${word_array[RANDOM % ${#word_array[@]}]}"
}

name_is_available() {
  local name="$1" manifest="$2" agents_dir="$3"
  [ ! -e "$agents_dir/$name.md" ] || return 1
  ! jq -e --arg name "$name" '.agents | has($name)' <<< "$manifest" >/dev/null 2>&1
}

choose_name() {
  local manifest="$1" agents_dir="$2" left right noun attempt name
  for ((attempt = 0; attempt < 100; attempt++)); do
    left=$(pick_word WORDS_A)
    right=$(pick_word WORDS_A)
    noun=$(pick_word WORDS_B)
    name="vbw-$ROLE-$left-$right-$noun"
    if name_is_available "$name" "$manifest" "$agents_dir"; then
      printf '%s\n' "$name"
      return 0
    fi
  done
  fail "could not find a collision-free generated name"
}

parse_resolved_settings() {
  local settings="$1" line key raw
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key=${line%%=*}
    case "$key" in
      RESOLVED_AGENT|RESOLVED_MODEL|RESOLVED_MAX_TURNS|RESOLVED_EFFORT|RESOLVED_REASONING) ;;
      *) fail "invalid resolver assignment '$key'" ;;
    esac
    raw=${line#*=}
    [[ "$raw" == \'*\' ]] || fail "invalid resolver value for $key"
    raw=${raw:1:${#raw}-2}
    raw=${raw//"'\\''"/"'"}
    printf -v "$key" '%s' "$raw"
  done <<< "$settings"
}

resolve_settings() {
  local effort_input="${OVERRIDES[EFFORT]-}" settings_script settings
  settings_script="${VBW_AGENT_SETTINGS_SCRIPT:-$SCRIPT_DIR/resolve-agent-settings.sh}"
  [ -f "$settings_script" ] || fail "agent settings resolver not found"
  if ! settings=$(bash "$settings_script" "$ROLE" "$CONFIG_PATH" "$PROFILES_PATH" "$effort_input" 2>&1); then
    fail "$settings"
  fi
  parse_resolved_settings "$settings"
}

validate_reasoning_override() {
  local value="$1" canonical
  [ -n "$value" ] || return 0
  canonical=$(jq -r --arg model "$MODEL" '.aliases[$model] // $model' "$SCRIPT_DIR/../config/model-pricing.json" 2>/dev/null) || fail "could not inspect model reasoning support"
  jq -e --arg model "$canonical" --arg value "$value" \
    '.models[$model].reasoning_efforts // [] | index($value) != null' \
    "$SCRIPT_DIR/../config/model-pricing.json" >/dev/null 2>&1 \
    || fail "reasoning override '$value' is unsupported by model '$MODEL'"
}

build_overrides_json() {
  local json='{}' token
  for token in "${!OVERRIDES[@]}"; do
    json=$(jq -c --arg key "$token" --arg value "${OVERRIDES[$token]}" '.[$key] = $value' <<< "$json")
  done
  printf '%s\n' "$json"
}

renderer_args() {
  local token
  RENDER_ARGS=("NAME=$NAME" "JOB=$JOB" "MODEL=$MODEL" "MAX_TURNS=$MAX_TURNS" "EFFORT=$FRONTMATTER_EFFORT")
  for token in DESCRIPTION TOOLS DISALLOWED_TOOLS PERMISSION_MODE SKILLS MCP_SERVERS MEMORY BACKGROUND ISOLATION COLOR INITIAL_PROMPT; do
    if [ "${OVERRIDES[$token]+set}" = set ]; then
      RENDER_ARGS+=("$token=${OVERRIDES[$token]}")
    fi
  done
}

register_manifest_entry_locked() {
  local overrides="$1" manifest entry updated created
  manifest=$(agent_manifest_read "$PLANNING_DIR") || return 1
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  entry=$(jq -cn \
    --arg name "$NAME" \
    --arg role "$ROLE" \
    --arg project_root "$PROJECT_ROOT" \
    --arg definition_path "$TARGET" \
    --arg created_at "$created" \
    --arg model "$MODEL" \
    --arg effort "$FRONTMATTER_EFFORT" \
    --arg max_turns "$MAX_TURNS" \
    --argjson overrides "$overrides" \
    '{name:$name,role:$role,project_root:$project_root,definition_path:$definition_path,state:"registered",created_at:$created_at,model:$model,effort:$effort,max_turns:$max_turns,overrides:$overrides}')
  updated=$(jq -c --arg name "$NAME" --argjson entry "$entry" '.agents[$name] = $entry' <<< "$manifest") || return 1
  agent_manifest_write "$PLANNING_DIR" "$updated" || return 1
  MANIFEST="$updated"
}

generate_agent_locked() {
  local live_count tmp_target overrides_json
  MANIFEST=$(agent_manifest_read "$PLANNING_DIR") || { GENERATOR_ERROR="invalid agent manifest"; return 1; }
  live_count=$(jq '[.agents[] | select(.state == "registered" or .state == "running")] | length' <<< "$MANIFEST")
  if [ "$live_count" -ge 4 ]; then
    GENERATOR_ERROR="agent cap reached: 4 registered or running agents"
    return 1
  fi
  NAME=$(choose_name "$MANIFEST" "$AGENTS_DIR") || { GENERATOR_ERROR="could not find a collision-free generated name"; return 1; }
  TARGET="$AGENTS_DIR/$NAME.md"
  renderer_args
  tmp_target="${TARGET}.tmp.${BASHPID:-$$}"
  if ! bash "$SCRIPT_DIR/render-agent-template.sh" "$ROLE" "${RENDER_ARGS[@]}" > "$tmp_target"; then
    rm -f "$tmp_target"
    GENERATOR_ERROR="could not render generated agent"
    return 1
  fi
  if ! mv -f "$tmp_target" "$TARGET"; then
    rm -f "$tmp_target"
    GENERATOR_ERROR="could not install generated agent"
    return 1
  fi
  overrides_json=$(build_overrides_json)
  if ! register_manifest_entry_locked "$overrides_json"; then
    rm -f "$TARGET"
    GENERATOR_ERROR="could not register generated agent in manifest"
    return 1
  fi
}

parse_options "$@"
[ -n "$JOB" ] || fail "--job is required"
PROJECT_ROOT=$(find_project_root)
PLANNING_DIR="$PROJECT_ROOT/.vbw-planning"
CONFIG_PATH="$PLANNING_DIR/config.json"
PROFILES_PATH="$PLUGIN_ROOT/config/model-profiles.json"
[ -f "$CONFIG_PATH" ] || fail "config not found: $CONFIG_PATH"
[ -f "$PROFILES_PATH" ] || fail "model profiles not found: $PROFILES_PATH"
AGENTS_DIR="$PROJECT_ROOT/.claude/agents"
mkdir -p "$AGENTS_DIR"
PLANNING_GIT="$PLUGIN_ROOT/scripts/planning-git.sh"
[ -f "$PLANNING_GIT" ] || fail "planning git helper not found"
bash "$PLANNING_GIT" ensure-generated-agent-ignore || fail "could not install generated-agent gitignore rule"
WORDLIST_A="${VBW_AGENT_WORDLIST_A:-$PLUGIN_ROOT/config/agent-generator-adjectives.txt}"
WORDLIST_B="${VBW_AGENT_WORDLIST_B:-$PLUGIN_ROOT/config/agent-generator-nouns.txt}"
load_words "$WORDLIST_A" WORDS_A
load_words "$WORDLIST_B" WORDS_B
if [ "$ROLE" = qa ]; then
  filtered_words=()
  for word in "${WORDS_A[@]}"; do
    [ "$word" = author ] || filtered_words+=("$word")
  done
  WORDS_A=("${filtered_words[@]}")
  [ "${#WORDS_A[@]}" -gt 0 ] || fail "wordlist has no usable adjectives for qa"
fi
if [ -n "${VBW_AGENT_RANDOM_SEED:-}" ]; then
  RANDOM="$VBW_AGENT_RANDOM_SEED"
fi
resolve_settings
MODEL="${OVERRIDES[MODEL]:-$RESOLVED_MODEL}"
MAX_TURNS="${OVERRIDES[MAX_TURNS]:-$RESOLVED_MAX_TURNS}"
if [ "${OVERRIDES[REASONING]+set}" = set ]; then
  FRONTMATTER_EFFORT="${OVERRIDES[REASONING]}"
else
  FRONTMATTER_EFFORT="$RESOLVED_REASONING"
fi
[ -n "$MODEL" ] || fail "resolved model is empty"
validate_reasoning_override "$FRONTMATTER_EFFORT"
TARGET=""
GENERATOR_ERROR=""
if ! agent_manifest_with_lock "$PLANNING_DIR" generate_agent_locked; then
  [ -n "$TARGET" ] && rm -f "$TARGET"
  fail "${GENERATOR_ERROR:-could not generate agent}"
fi
printf 'Agent-call parameters:\n'
printf '  subagent_type: %s\n' "$NAME"
printf '  name: %s\n' "$NAME"
printf '  model: %s\n' "$MODEL"
[ -n "$MAX_TURNS" ] && printf '  maxTurns: %s\n' "$MAX_TURNS"
[ -n "$FRONTMATTER_EFFORT" ] && printf '  effort: %s\n' "$FRONTMATTER_EFFORT"
printf 'SPAWN_READY %s\n' "$NAME"
