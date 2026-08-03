#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

require_file_literal() {
  local desc="$1"
  local needle="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Fq -- "$needle" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_file_regex() {
  local desc="$1"
  local pattern="$2"
  local file="$3"

  if [ -f "$file" ] && grep -Eq -- "$pattern" "$file"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_text_literal() {
  local desc="$1"
  local needle="$2"
  local text="$3"

  if grep -Fq -- "$needle" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

require_text_regex() {
  local desc="$1"
  local pattern="$2"
  local text="$3"

  if grep -Eq -- "$pattern" <<< "$text"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

extract_heading_block() {
  local file="$1"
  local heading="$2"
  local end_regex="$3"

  awk -v h="$heading" -v end_re="$end_regex" '
    function trim_line(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }

    {
      line=$0
      gsub(/\r/, "", line)
      trimmed=trim_line(line)

      if (trimmed == h) {
        found=1
        print line
        next
      }

      if (found && trimmed ~ end_re) {
        exit
      }

      if (found) {
        print line
      }
    }
  ' "$file"
}

extract_bullet_block() {
  local text="$1"
  local anchor="$2"

  awk -v anchor="$anchor" '
    {
      line=$0

      if (index(line, anchor) > 0) {
        found=1
        print line
        next
      }

      if (found && line ~ /^- \*\*/) {
        exit
      }

      if (found) {
        print line
      }
    }
  ' <<< "$text"
}

echo "=== Discussion Engine Contract Verification ==="

ENGINE="$ROOT/references/discussion-engine.md"



for indicator in "✓ confirmed" "⚡ validated" "? resolved" "✗ corrected" "○ expanded"; do
  if grep -q "$indicator" "$ENGINE"; then
    pass "engine: contains confidence indicator '$indicator'"
  else
    fail "engine: missing confidence indicator '$indicator'"
  fi
done



if grep -q "present a summary" "$ENGINE"; then
  pass "engine: A5 has user-facing presentation instruction"
else
  fail "engine: A5 missing user-facing presentation instruction"
fi



if grep -q "Step 1.7" "$ENGINE"; then
  pass "engine: Step 1.7 (Assumptions Path) exists"
else
  fail "engine: Step 1.7 (Assumptions Path) missing"
fi



if grep -q "META.md" "$ENGINE"; then
  pass "engine: codebase map guard references META.md"
else
  fail "engine: codebase map guard missing META.md reference"
fi



SHARED_BLOCK="$(extract_heading_block "$ENGINE" "## Shared interaction contract" '^## ' || true)"
INTERACTION_BLOCK="$(extract_heading_block "$ENGINE" "## Interaction Boundary" '^## ' || true)"
DISCUSSION_SELECTION_TEXT="$(extract_heading_block "$ENGINE" "## Step ""2: Orient" '^## ' || true)"
DISCUSSION_EXPLORATION_TEXT="$(extract_heading_block "$ENGINE" "## Step ""3: Explore" '^## ' || true)"
FRESH_STRUCTURED_BLOCK="$(extract_bullet_block "$DISCUSSION_SELECTION_TEXT" "Fresh 1 to 4 gray areas" || true)"
FRESH_FREEFORM_BLOCK="$(extract_bullet_block "$DISCUSSION_SELECTION_TEXT" "Fresh 5 to 6 gray areas" || true)"
CONTINUATION_STRUCTURED_BLOCK="$(extract_bullet_block "$DISCUSSION_SELECTION_TEXT" "Continuation 1 to 3 uncovered gray areas" || true)"
CONTINUATION_FREEFORM_BLOCK="$(extract_bullet_block "$DISCUSSION_SELECTION_TEXT" "Continuation 4 to 6 uncovered gray areas" || true)"

if [ -n "$SHARED_BLOCK" ]; then
  pass "engine: shared interaction contract block extracted"
else
  fail "engine: shared interaction contract block extracted"
fi

if [ -n "$INTERACTION_BLOCK" ]; then
  pass "engine: interaction boundary block extracted"
else
  fail "engine: interaction boundary block extracted"
fi

if [ -n "$DISCUSSION_SELECTION_TEXT" ]; then
  pass "engine: Step 2 block extracted"
else
  fail "engine: Step 2 block extracted"
fi

if [ -n "$DISCUSSION_EXPLORATION_TEXT" ]; then
  pass "engine: Step 3 block extracted"
else
  fail "engine: Step 3 block extracted"
fi

if [ -n "$FRESH_STRUCTURED_BLOCK" ]; then
  pass "engine: fresh structured gray-area branch extracted"
else
  fail "engine: fresh structured gray-area branch extracted"
fi

if [ -n "$FRESH_FREEFORM_BLOCK" ]; then
  pass "engine: fresh freeform gray-area branch extracted"
else
  fail "engine: fresh freeform gray-area branch extracted"
fi

if [ -n "$CONTINUATION_STRUCTURED_BLOCK" ]; then
  pass "engine: continuation structured gray-area branch extracted"
else
  fail "engine: continuation structured gray-area branch extracted"
fi

if [ -n "$CONTINUATION_FREEFORM_BLOCK" ]; then
  pass "engine: continuation freeform gray-area branch extracted"
else
  fail "engine: continuation freeform gray-area branch extracted"
fi

require_text_literal "engine: shared block points to ask-user-question reference" "references/ask-user-question.md" "$SHARED_BLOCK"
require_text_literal "engine: boundary documents structured 1 to 4 visible choices" "Use structured AskUserQuestion for bounded discussion decisions with 1 to 4 visible choices" "$INTERACTION_BLOCK"
require_text_literal "engine: boundary documents larger selections as freeform/no-options" "Use intentional freeform/no-options input" "$INTERACTION_BLOCK"
require_text_literal "engine: boundary forbids options array for high-cardinality paths" 'do NOT use `options` array' "$INTERACTION_BLOCK"
require_text_literal "engine: continuation selection keeps explicit no-op path" 'Continuation discussions must always offer an explicit `None: discussion is complete` no-op path' "$DISCUSSION_SELECTION_TEXT"

require_text_literal "engine: fresh 1 to 4 branch uses structured multi-select" "Use structured AskUserQuestion multi-select" "$FRESH_STRUCTURED_BLOCK"
require_text_literal "engine: fresh 1 to 4 branch requires selected area" "require at least one selected area" "$FRESH_STRUCTURED_BLOCK"

require_text_literal "engine: fresh 5 to 6 branch uses freeform/no-options" "intentional freeform/no-options selection" "$FRESH_FREEFORM_BLOCK"
require_text_literal "engine: fresh 5 to 6 branch requires selected area" "Require at least one selected area" "$FRESH_FREEFORM_BLOCK"
require_text_literal "engine: fresh 5 to 6 branch forbids options array" 'do NOT use `options` array' "$FRESH_FREEFORM_BLOCK"

require_text_literal "engine: continuation 1 to 3 branch uses structured multi-select" "Use structured AskUserQuestion multi-select" "$CONTINUATION_STRUCTURED_BLOCK"
require_text_literal "engine: continuation 1 to 3 branch includes None option" 'None: discussion is complete' "$CONTINUATION_STRUCTURED_BLOCK"
require_text_literal "engine: continuation 1 to 3 branch accounts for four visible choices" "four visible choices" "$CONTINUATION_STRUCTURED_BLOCK"

require_text_literal "engine: continuation 4 to 6 branch uses freeform/no-options" "intentional freeform/no-options selection" "$CONTINUATION_FREEFORM_BLOCK"
require_text_literal "engine: continuation 4 to 6 branch accepts both no-op spellings" 'Accept `none` / `None: discussion is complete`' "$CONTINUATION_FREEFORM_BLOCK"
require_text_literal "engine: continuation 4 to 6 branch forbids options array" 'do NOT use `options` array' "$CONTINUATION_FREEFORM_BLOCK"

require_text_literal "engine: Step 3 early exit requires no selected areas" "Step 2 produced no selected areas" "$DISCUSSION_EXPLORATION_TEXT"
require_text_literal "engine: Step 3 early exit covers structured None" 'structured `None: discussion is complete`' "$DISCUSSION_EXPLORATION_TEXT"
require_text_literal "engine: Step 3 early exit covers freeform none" 'freeform `none`' "$DISCUSSION_EXPLORATION_TEXT"
require_text_literal "engine: Step 3 early exit covers freeform None phrase" 'freeform `none` / `None: discussion is complete`' "$DISCUSSION_EXPLORATION_TEXT"
require_text_literal "engine: Step 3 early exit skips to Step 4" "skip directly to Step 4" "$DISCUSSION_EXPLORATION_TEXT"
require_file_literal "engine: Let me explain stops AskUserQuestion" 'stop using AskUserQuestion' "$ENGINE"
require_file_regex "engine: Let me explain asks plain-text follow-up and waits" 'plain-text follow-up, wait for the response' "$ENGINE"
require_file_literal "engine: Builder sample is clearly marked as an example" '<example label="Builder mode gray-area prompt">' "$ENGINE"
require_file_literal "engine: Architect sample is clearly marked as an example" '<example label="Architect mode gray-area prompt">' "$ENGINE"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
