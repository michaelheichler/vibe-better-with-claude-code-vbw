#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE_DIR="$SCRIPT_DIR/../templates/agent-roles"
ROLE="${1:-}"
shift || true

fail() {
  printf 'render-agent-template: %s\n' "$1" >&2
  exit 1
}

token_for_key() {
  case "$1" in
    name|NAME) printf 'NAME' ;;
    description|DESCRIPTION) printf 'DESCRIPTION' ;;
    tools|TOOLS) printf 'TOOLS' ;;
    disallowedTools|DISALLOWED_TOOLS) printf 'DISALLOWED_TOOLS' ;;
    model|MODEL) printf 'MODEL' ;;
    permissionMode|PERMISSION_MODE) printf 'PERMISSION_MODE' ;;
    maxTurns|MAX_TURNS) printf 'MAX_TURNS' ;;
    skills|SKILLS) printf 'SKILLS' ;;
    mcpServers|MCP_SERVERS) printf 'MCP_SERVERS' ;;
    memory|MEMORY) printf 'MEMORY' ;;
    background|BACKGROUND) printf 'BACKGROUND' ;;
    effort|EFFORT) printf 'EFFORT' ;;
    isolation|ISOLATION) printf 'ISOLATION' ;;
    color|COLOR) printf 'COLOR' ;;
    initialPrompt|INITIAL_PROMPT) printf 'INITIAL_PROMPT' ;;
    JOB|job) printf 'JOB' ;;
    *) return 1 ;;
  esac
}

case "$ROLE" in
  architect|debugger|dev|docs|lead|qa-author|qa|scout) ;;
  *) fail "invalid role '$ROLE'" ;;
esac

TEMPLATE="$TEMPLATE_DIR/$ROLE.md.tpl"
DEFAULTS="$TEMPLATE_DIR/defaults.json"
[ -f "$TEMPLATE" ] || fail "template not found for role '$ROLE'"
[ -f "$DEFAULTS" ] || fail "defaults not found"

declare -A VALUES=()
for field in name description tools disallowedTools model permissionMode maxTurns skills mcpServers memory background effort isolation color initialPrompt; do
  token=$(token_for_key "$field")
  value=$(jq -r --arg role "$ROLE" --arg field "$field" '.[$role][$field] // empty' "$DEFAULTS")
  [ -n "$value" ] && VALUES["$token"]="$value"
done

for assignment in "$@"; do
  key=${assignment%%=*}
  [ "$key" != "$assignment" ] || fail "expected KEY=VALUE, got '$assignment'"
  value=${assignment#*=}
  token=$(token_for_key "$key") || fail "unknown field '$key'"
  VALUES["$token"]="$value"
done

for required in NAME MODEL DESCRIPTION JOB; do
  [ "${VALUES[$required]+set}" = set ] && [ -n "${VALUES[$required]}" ] || fail "missing required field $required"
done

rendered=$(cat "$TEMPLATE")
for token in "${!VALUES[@]}"; do
  value=${VALUES[$token]}
  [ -n "$value" ] || continue
  if [ "$token" = "JOB" ]; then
    escaped="$value"
  else
    escaped=$(jq -Rn --arg value "$value" '$value')
    escaped=${escaped:1:${#escaped}-2}
  fi
  marker="{{$token}}"
  rendered=${rendered//"$marker"/"$escaped"}
done

filtered=""
in_front=0
first_line=1
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$first_line" -eq 1 ] && [ "$line" = "---" ]; then
    in_front=1
    first_line=0
    filtered+="$line"$'\n'
    continue
  fi
  first_line=0
  if [ "$in_front" -eq 1 ] && [ "$line" = "---" ]; then
    in_front=0
    filtered+="$line"$'\n'
    continue
  fi
  if [ "$in_front" -eq 1 ] && [[ "$line" == *"{{"* ]]; then
    continue
  fi
  filtered+="$line"$'\n'
done <<< "$rendered"

if grep -qE '\{\{[A-Z_][A-Z0-9_]*\}\}' <<< "$filtered"; then
  fail "unresolved template token"
fi
printf '%s' "$filtered"
