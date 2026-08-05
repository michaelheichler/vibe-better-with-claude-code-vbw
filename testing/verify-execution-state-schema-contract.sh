#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFERENCE="$ROOT/references/execute-protocol.md"
SCRIPT="$ROOT/scripts/state-updater.sh"
KEY='"qa_required"'
FAIL=0

for file in "$REFERENCE" "$SCRIPT"; do
  if grep -qF "$KEY" "$file"; then
    printf 'PASS  %s contains %s\n' "$file" "$KEY"
  else
    printf 'FAIL  %s is missing %s\n' "$file" "$KEY"
    FAIL=$((FAIL + 1))
  fi
done

exit "$FAIL"
