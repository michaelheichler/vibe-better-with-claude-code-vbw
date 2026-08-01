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

echo "=== Dijkstra Correctness Discipline Verification ==="


ROUTER="$ROOT/references/dijkstra/DISCIPLINE.md"

if [[ -f "$ROUTER" ]]; then
  pass "references/dijkstra/DISCIPLINE.md exists"
else
  fail "references/dijkstra/DISCIPLINE.md missing"
fi

for term in postcondition invariant variant; do
  if grep -qi "$term" "$ROUTER" 2>/dev/null; then
    pass "router doc mentions '$term'"
  else
    fail "router doc missing '$term'"
  fi
done

if grep -q '^## Routing table' "$ROUTER" 2>/dev/null
then
  pass "router doc has Routing table section"
else
  fail "router doc missing Routing table section"
fi

if grep -q '^## Source boundary' "$ROUTER" 2>/dev/null
then
  pass "router doc has Source boundary section"
else
  fail "router doc missing Source boundary section"
fi

if grep -Eq 'one to three|1-3' "$ROUTER" 2>/dev/null; then
  pass "router doc states the 1-3 brief loading budget"
else
  fail "router doc missing the 1-3 brief loading budget"
fi


echo ""
echo "--- Routing table path checks ---"

BRIEF_COUNT=0
MISSING=0
while IFS= read -r rel; do
  BRIEF_COUNT=$((BRIEF_COUNT + 1))
  if [[ ! -f "$ROOT/$rel" ]]; then
    fail "routing table references missing file: $rel"
    MISSING=$((MISSING + 1))
  fi
done < <(grep -oE '`references/dijkstra/[a-z0-9-]+\.md`' "$ROUTER" 2>/dev/null | tr -d '`' | sort -u)

if [[ "$BRIEF_COUNT" -ge 17 ]]; then
  pass "routing table references $BRIEF_COUNT distinct brief files (>= 17)"
else
  fail "routing table references only $BRIEF_COUNT distinct brief files (expected >= 17)"
fi

if [[ "$MISSING" -eq 0 && "$BRIEF_COUNT" -gt 0 ]]; then
  pass "all routing table paths resolve to files on disk"
fi

while IFS= read -r brief; do
  name="$(basename "$brief")"
  if ! grep -q "$name" "$ROUTER" 2>/dev/null; then
    fail "brief on disk not referenced by routing table: $name"
  fi
done < <(find "$ROOT/references/dijkstra" -name '[ds][0-9][0-9]-*.md' 2>/dev/null)
pass "brief-to-routing-table reachability scan completed"


echo ""
echo "--- Dev agent checks ---"

DEV="$ROOT/agents/vbw-dev.md"

if grep -q '^## Correctness Discipline (Dijkstra)' "$DEV"
then
  pass "dev: Correctness Discipline (Dijkstra) section present"
else
  fail "dev: missing Correctness Discipline (Dijkstra) section"
fi

if grep -q "references/dijkstra/DISCIPLINE.md" "$DEV"; then
  pass "dev: references the discipline router doc"
else
  fail "dev: missing reference to references/dijkstra/DISCIPLINE.md"
fi

if grep -q "correctness: dijkstra" "$DEV"; then
  pass "dev: honors the correctness: dijkstra plan flag"
else
  fail "dev: missing the correctness: dijkstra plan flag trigger"
fi

if grep -q "Grounding:" "$DEV"; then
  pass "dev: Grounding line convention present"
else
  fail "dev: missing Grounding line convention"
fi

if head -10 "$DEV" | grep -q "Dijkstra correctness discipline"; then
  pass "dev: description advertises the Dijkstra correctness discipline"
else
  fail "dev: description missing the Dijkstra correctness discipline clause"
fi


echo ""
echo "--- QA agent checks ---"

QA="$ROOT/agents/vbw-qa.md"

if grep -q '^## Correctness Verification (Dijkstra)' "$QA"
then
  pass "qa: Correctness Verification (Dijkstra) section present"
else
  fail "qa: missing Correctness Verification (Dijkstra) section"
fi

if grep -q "references/dijkstra/DISCIPLINE.md" "$QA"; then
  pass "qa: references the discipline router doc"
else
  fail "qa: missing reference to references/dijkstra/DISCIPLINE.md"
fi

if grep -qi 'invariant' "$QA" && grep -Eqi '[^n]variant|^variant' "$QA"; then
  pass "qa: verifies invariant/variant reasoning"
else
  fail "qa: missing invariant/variant verification guidance"
fi

if grep -q "Grounding:" "$QA"; then
  pass "qa: checks the Grounding line as correctness evidence"
else
  fail "qa: missing Grounding line check"
fi


echo ""
echo "--- Lead and execute-protocol checks ---"

LEAD="$ROOT/agents/vbw-lead.md"
PROTO="$ROOT/references/execute-protocol.md"

if grep -q "correctness: dijkstra" "$LEAD"; then
  pass "lead: sets the correctness: dijkstra flag at planning time"
else
  fail "lead: missing the correctness: dijkstra plan-time flag guidance"
fi

if grep -q "correctness: dijkstra" "$PROTO"; then
  pass "execute-protocol: documents the correctness: dijkstra flag"
else
  fail "execute-protocol: missing the correctness: dijkstra flag paragraph"
fi

SYNC_SENTENCE='Dev engages `references/dijkstra/DISCIPLINE.md` and QA verifies the invariant/variant reasoning'
if grep -qF "$SYNC_SENTENCE" "$LEAD" && grep -qF "$SYNC_SENTENCE" "$PROTO"; then
  pass "lead/execute-protocol: mirrored flag sentence in sync"
else
  fail "lead/execute-protocol: mirrored flag sentence out of sync"
fi


echo ""
echo "==============================="
echo "TOTAL: $PASS PASS, $FAIL FAIL"
echo "==============================="

[[ "$FAIL" -eq 0 ]] || exit 1
