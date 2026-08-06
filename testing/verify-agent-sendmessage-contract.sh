#!/usr/bin/env bash
set -euo pipefail
# Contract: an agent body referencing SendMessage must have the tool grantable.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULTS="$REPO_ROOT/templates/agent-roles/defaults.json"

fail_agents=()
checked=0

for agent_file in "$REPO_ROOT"/templates/agent-roles/*.md.tpl; do
  [ -f "$agent_file" ] || continue

  body="$(awk '/^---$/{n++; next} n>=2{print}' "$agent_file")"

  printf '%s' "$body" | grep -q 'SendMessage' || continue
  checked=$((checked + 1))

  role="$(basename "$agent_file" .md.tpl)"
  tools_line="$(jq -r --arg role "$role" '.[$role].tools // empty' "$DEFAULTS")"
  disallowed_line="$(jq -r --arg role "$role" '.[$role].disallowedTools // empty' "$DEFAULTS")"

  if [ -n "$tools_line" ]; then
    if ! printf '%s' "$tools_line" | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx 'SendMessage'; then
      fail_agents+=("$(basename "$agent_file"): body references SendMessage but tools: allowlist omits it")
    fi
  elif printf '%s' "$disallowed_line" | tr ',' '\n' \
      | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx 'SendMessage'; then
    fail_agents+=("$(basename "$agent_file"): body references SendMessage but disallowedTools denies it")
  fi
done

if [ "${#fail_agents[@]}" -gt 0 ]; then
  echo "FAIL: agent SendMessage contract violations:" >&2
  printf '  %s\n' "${fail_agents[@]}" >&2
  exit 1
fi

echo "OK: agent SendMessage contract holds (${checked} agents reference SendMessage, all grantable)"
