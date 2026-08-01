#!/usr/bin/env bash
set -euo pipefail
# Contract: an agent body referencing SendMessage must have the tool grantable.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail_agents=()
checked=0

for agent_file in "$REPO_ROOT"/agents/vbw-*.md; do
  [ -f "$agent_file" ] || continue

  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$agent_file")"
  body="$(awk '/^---$/{n++; next} n>=2{print}' "$agent_file")"

  printf '%s' "$body" | grep -q 'SendMessage' || continue
  checked=$((checked + 1))

  tools_line="$(printf '%s\n' "$frontmatter" | grep -E '^tools:' || true)"
  disallowed_line="$(printf '%s\n' "$frontmatter" | grep -E '^disallowedTools:' || true)"

  if [ -n "$tools_line" ]; then
    if ! printf '%s' "$tools_line" | sed 's/^tools:[[:space:]]*//' | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx 'SendMessage'; then
      fail_agents+=("$(basename "$agent_file"): body references SendMessage but tools: allowlist omits it")
    fi
  else
    if [ -n "$disallowed_line" ] && printf '%s' "$disallowed_line" \
        | sed 's/^disallowedTools:[[:space:]]*//' | tr ',' '\n' \
        | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -qx 'SendMessage'; then
      fail_agents+=("$(basename "$agent_file"): body references SendMessage but disallowedTools denies it")
    fi
  fi
done

if [ "${#fail_agents[@]}" -gt 0 ]; then
  echo "FAIL: agent SendMessage contract violations:" >&2
  printf '  %s\n' "${fail_agents[@]}" >&2
  exit 1
fi

echo "OK: agent SendMessage contract holds (${checked} agents reference SendMessage, all grantable)"
