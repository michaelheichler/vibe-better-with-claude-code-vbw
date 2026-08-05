#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_REL="references/subagent-contracts.md"
CANONICAL_FILE="$ROOT/$CANONICAL_REL"
SHARED_INCLUDE='@${CLAUDE_PLUGIN_ROOT}/references/subagent-contracts.md'
EXECUTE_REL="references/execute-protocol.md"
EXECUTE_READ_DIRECTIVE='Before spawning any subagent, read `${VBW_PLUGIN_ROOT}/references/subagent-contracts.md` for the canonical subagent contracts.'

SPAWNING_COMMANDS=(
  commands/vibe.md
  commands/debug.md
  commands/map.md
  commands/qa.md
  commands/fix.md
  commands/research.md
)

CONTRACT_SECTIONS=(
  "## Team-Shutdown Contract"
  "## Non-Team Spawn Shape"
  "## No-Tool Circuit Breaker"
  "## Effort Routing Contract"
)

EFFORT_ROUTING_LINES=(
  'Model routing is enforced by the spawn guard and passed as the documented Task `model` parameter.'
  'Reasoning effort is enforced at the hook/frontmatter layer. It is not a documented Task parameter.'
  'Orchestrators must not claim reasoning effort was or was not applied based on tool schema visibility or agent self-report. Subagents cannot introspect their own reasoning effort.'
  'Evidence for actual routing lives in session and subagent transcripts.'
  'Workflow effort (`thorough`, `balanced`, `fast`, `turbo`) is a matrix key distinct from reasoning effort (`low` through `max`).'
)

INVARIANT_PREFIXES=(
  "Shutdown invariant:"
  "Non-team invariant:"
  "No-tool invariant:"
)

INVARIANT_LABELS=(
  "shutdown"
  "non-team"
  "no-tool"
)

FORBIDDEN_MARKERS=(
  "plain text acknowledgement is not sufficient."
  'non-team spawn shape: omit `team_name`, `run_in_background`, `isolation`'
  "tools, shell/bash, filesystem, edits, or api-session access are unavailable"
)

MARKER_LABELS=(
  "shutdown prose"
  "non-team spawn prose"
  "no-tool prose"
)

PAYLOAD_VERBATIM_ALLOWLIST=(
  'references/vibe-uat-remediation.md:    Spawn one Dev for the current plan task using the non-team spawn shape: omit `team_name`, `run_in_background`, `isolation`, and worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). `name` is optional label-only metadata. Never use it for routing, lifecycle state, or team semantics. Include absolute artifacts exactly as returned by state metadata:'
)

TRACKED_FILES=()
mapfile -t TRACKED_FILES < <(
  git -C "$ROOT" ls-files -- 'commands/*.md' 'references/*.md' 'agents/*.md'
)

PASS=0
FAIL=0

pass() {
  printf 'PASS  %s\n' "$1"
  printf -v PASS '%d' "$((PASS + 1))"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  printf -v FAIL '%d' "$((FAIL + 1))"
}

extract_canonical_invariant() {
  local prefix="$1"

  awk -v prefix="$prefix" '
    $0 == "```text" {
      in_fence = 1
      next
    }
    in_fence && $0 == "```" {
      in_fence = 0
      next
    }
    in_fence && index($0, prefix) == 1 {
      found++
      invariant = $0
    }
    END {
      if (found == 1) {
        print invariant
      } else {
        exit 1
      }
    }
  ' "$CANONICAL_FILE"
}

payload_verbatim_allowed() {
  local rel="$1"
  local line="$2"
  local candidate="$rel:$line"
  local allowed

  for allowed in "${PAYLOAD_VERBATIM_ALLOWLIST[@]}"; do
    if [[ "$candidate" == "$allowed" ]]; then
      return 0
    fi
  done

  return 1
}

echo "=== Shared Contract Verification ==="

canonical_exists=false
if [ -f "$CANONICAL_FILE" ]; then
  canonical_exists=true
  pass "$CANONICAL_REL: canonical reference exists"
else
  fail "$CANONICAL_REL: canonical reference missing"
fi

for section in "${CONTRACT_SECTIONS[@]}"; do
  if [ "$canonical_exists" = true ] && grep -Fxq -- "$section" "$CANONICAL_FILE"; then
    pass "$CANONICAL_REL: contains $section"
  else
    fail "$CANONICAL_REL: missing $section"
  fi
done

for line in "${EFFORT_ROUTING_LINES[@]}"; do
  if [ "$canonical_exists" = true ] && grep -Fxq -- "- $line" "$CANONICAL_FILE"; then
    pass "$CANONICAL_REL: contains effort-routing contract line"
  else
    fail "$CANONICAL_REL: missing effort-routing contract line: $line"
  fi
done

for rel in "${SPAWNING_COMMANDS[@]}"; do
  if grep -Fxq -- "$SHARED_INCLUDE" "$ROOT/$rel" \
    || { [ "$rel" = "${SPAWNING_COMMANDS[0]}" ] && grep -Fq 'Read `{LINK}/references/subagent-contracts.md`' "$ROOT/$rel"; }; then
    pass "${rel##*/}: includes shared contracts"
  else
    fail "${rel##*/}: missing shared-contract include"
  fi
done

if grep -Fq -- "$EXECUTE_READ_DIRECTIVE" "$ROOT/$EXECUTE_REL"; then
  pass "${EXECUTE_REL##*/}: reads shared contracts before spawning"
else
  fail "${EXECUTE_REL##*/}: missing shared-contract read directive"
fi

if grep -Fxq -- "$SHARED_INCLUDE" "$ROOT/$EXECUTE_REL"; then
  fail "${EXECUTE_REL##*/}: must use a read directive, not a standalone include"
else
  pass "${EXECUTE_REL##*/}: has no standalone shared-contract include"
fi

CANONICAL_INVARIANTS=()
for prefix in "${INVARIANT_PREFIXES[@]}"; do
  invariant=""
  if [ "$canonical_exists" = true ] && invariant="$(extract_canonical_invariant "$prefix")"; then
    CANONICAL_INVARIANTS+=("$invariant")
    pass "$CANONICAL_REL: extracts $prefix"
  else
    CANONICAL_INVARIANTS+=("")
    fail "$CANONICAL_REL: cannot extract one fenced $prefix sentence"
  fi
done

for rel in "${TRACKED_FILES[@]}"; do
  line_number=0
  while IFS= read -r line || [ -n "$line" ]; do
    line_number=$((line_number + 1))
    for index in "${!INVARIANT_PREFIXES[@]}"; do
      prefix="${INVARIANT_PREFIXES[$index]}"
      if [[ "$line" != *"$prefix"* ]]; then
        continue
      fi

      actual="${prefix}${line#*"$prefix"}"
      expected="${CANONICAL_INVARIANTS[$index]}"
      label="${INVARIANT_LABELS[$index]}"
      if [ -n "$expected" ] && [ "$actual" = "$expected" ]; then
        pass "${rel##*/}:$line_number $label invariant matches canonical"
      else
        fail "${rel##*/}:$line_number $label invariant differs from canonical"
      fi
    done
  done < "$ROOT/$rel"
done

for marker_index in "${!FORBIDDEN_MARKERS[@]}"; do
  marker="${FORBIDDEN_MARKERS[$marker_index]}"
  marker_label="${MARKER_LABELS[$marker_index]}"
  violations=0

  for rel in "${TRACKED_FILES[@]}"; do
    [ "$rel" = "$CANONICAL_REL" ] && continue

    line_number=0
    while IFS= read -r line || [ -n "$line" ]; do
      line_number=$((line_number + 1))
      lower_line="${line,,}"
      if [[ "$lower_line" != *"$marker"* ]]; then
        continue
      fi

      if [ "$marker_index" -eq 1 ] && payload_verbatim_allowed "$rel" "$line"; then
        pass "${rel##*/}:$line_number retained payload-verbatim non-team spawn prose is allowlisted"
        continue
      fi

      fail "${rel##*/}:$line_number contains centralized $marker_label"
      violations=$((violations + 1))
    done < "$ROOT/$rel"
  done

  if [ "$violations" -eq 0 ]; then
    pass "$marker_label is confined to the canonical reference and explicit payload allowlist"
  fi
done

echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

echo "All shared contract checks passed."
exit 0
