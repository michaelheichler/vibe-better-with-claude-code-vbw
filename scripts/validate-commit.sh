#!/bin/bash
set -u

if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

if ! echo "$COMMAND" | grep -q "git commit"; then
  exit 0
fi

MSG=""
if echo "$COMMAND" | grep -q 'cat <<'; then
  MSG=$(printf '%s\n' "$COMMAND" | sed -n '/cat <</,$ p' | sed '1d' | sed '/^[[:space:]]*$/d' | head -1 | sed 's/^[[:space:]]*//')
  if [ -z "$MSG" ]; then
    exit 0  # Can't parse heredoc, fail-open
  fi
fi
if [ -z "$MSG" ]; then
  MSG=$(echo "$COMMAND" | sed -n 's/.*-m[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$MSG" ] && MSG=$(echo "$COMMAND" | sed -n "s/.*-m[[:space:]]*'\\([^']*\\)'.*/\\1/p")
  [ -z "$MSG" ] && MSG=$(echo "$COMMAND" | sed -n 's/.*-m[[:space:]]*\([^[:space:]]*\).*/\1/p')
fi

if [ -z "$MSG" ]; then
  exit 0
fi

VALID_TYPES="feat|fix|test|refactor|perf|docs|style|chore"
if ! echo "$MSG" | grep -qE "^($VALID_TYPES)\(.+\): .+"; then
  jq -n --arg msg "$MSG" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": ("Commit message does not match format {type}({scope}): {desc}. Got: " + $msg)
    }
  }'
fi

if [ -f ".claude-plugin/plugin.json" ] && [ -f "./scripts/bump-version.sh" ]; then
  PLUGIN_NAME=$(jq -r '.name // ""' .claude-plugin/plugin.json 2>/dev/null)
  if [ "$PLUGIN_NAME" = "vbw" ]; then
    VERIFY_OUTPUT=$(bash ./scripts/bump-version.sh --verify 2>&1) || {
      DETAILS=$(echo "$VERIFY_OUTPUT" | grep -A 10 "MISMATCH")
      jq -n --arg details "$DETAILS" '{
        "hookSpecificOutput": {
          "hookEventName": "PostToolUse",
          "additionalContext": ("Version files are out of sync. Run: bash scripts/bump-version.sh\n" + $details)
        }
      }'
    }
  fi
fi

exit 0
