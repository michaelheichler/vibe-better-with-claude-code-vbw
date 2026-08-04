#!/usr/bin/env bash
set -euo pipefail


ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VIBE=$(mktemp)
trap 'rm -f "$VIBE"' EXIT
VIBE_CAT_FILES=(
  "$ROOT/commands/vibe.md"
  "$ROOT/references/vibe-input-parsing.md"
  "$ROOT/references/vibe-uat-remediation.md"
  "$ROOT/references/vibe-mode-bootstrap.md"
  "$ROOT/references/vibe-mode-milestone-uat-recovery.md"
  "$ROOT/references/vibe-mode-plan.md"
  "$ROOT/references/vibe-mode-execute.md"
  "$ROOT/references/vibe-mode-verify.md"
  "$ROOT/references/vibe-mode-add-phase.md"
  "$ROOT/references/vibe-mode-insert-phase.md"
  "$ROOT/references/vibe-mode-remove-phase.md"
  "$ROOT/references/vibe-mode-archive.md"
)
while IFS= read -r vibe_reference; do
  [ -n "$vibe_reference" ] || continue
  if ! printf '%s\n' "${VIBE_CAT_FILES[@]}" | grep -Fq "/$vibe_reference"; then
    echo "verify-vibe: $vibe_reference is imported by commands/vibe.md but omitted from the effective scan" >&2
    exit 1
  fi
done < <(grep -oE 'references/vibe-mode-[[:alnum:]-]+\.md' "$ROOT/commands/vibe.md" | sort -u)
cat "${VIBE_CAT_FILES[@]}" > "$VIBE"
PROTOCOL="$ROOT/references/execute-protocol.md"
README="$ROOT/README.md"
CLAUDE_MD="$ROOT/CLAUDE.md"
HELP="$ROOT/commands/help.md"
SUGGEST="$ROOT/scripts/suggest-next.sh"
MKT_ROOT="$ROOT/marketplace.json"
MKT_PLUGIN="$ROOT/.claude-plugin/marketplace.json"

tracked_repo_file_exists() {
  git -C "$ROOT" ls-files --error-unmatch "$1" >/dev/null 2>&1
}

tracked_markdown_count() {
  git -C "$ROOT" ls-files -- "$@" | wc -l | tr -d ' '
}

TOTAL_PASS=0
TOTAL_FAIL=0
GROUP_PASS=0
GROUP_FAIL=0


group_start() {
  GROUP_PASS=0
  GROUP_FAIL=0
  echo ""
  echo "=== $1 ==="
}

group_end() {
  local label="$1"
  TOTAL_PASS=$((TOTAL_PASS + GROUP_PASS))
  TOTAL_FAIL=$((TOTAL_FAIL + GROUP_FAIL))
  if [ "$GROUP_FAIL" -eq 0 ]; then
    echo "  >> $label: ALL PASS ($GROUP_PASS checks)"
  else
    echo "  >> $label: $GROUP_FAIL FAIL, $GROUP_PASS pass"
  fi
}

check() {
  local req="$1"
  local desc="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  PASS  $req: $desc"
    GROUP_PASS=$((GROUP_PASS + 1))
  else
    echo "  FAIL  $req: $desc"
    GROUP_FAIL=$((GROUP_FAIL + 1))
  fi
}

check_absent() {
  local req="$1"
  local desc="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL  $req: $desc"
    GROUP_FAIL=$((GROUP_FAIL + 1))
  else
    echo "  PASS  $req: $desc"
    GROUP_PASS=$((GROUP_PASS + 1))
  fi
}


group_start "GROUP 1: Core Router (REQ-01 to REQ-05)"

check "REQ-01" "vibe command surface contains planning_dir_exists" grep -q "planning_dir_exists" "$VIBE"
check "REQ-01" "vibe command surface contains phase_count=0" grep -q "phase_count=0" "$VIBE"
check "REQ-01" "vibe command surface contains next_phase_state" grep -q "next_phase_state" "$VIBE"

check "REQ-02" "vibe command surface has Natural language intent section" grep -qi "Natural language intent" "$VIBE"
check "REQ-02" "vibe command surface has interpret user intent" grep -q "interpret user intent" "$VIBE"

check "REQ-03" "vibe command surface maps --plan to Plan mode" grep -q "\-\-plan.*Plan mode" "$VIBE"
check "REQ-03" "vibe command surface maps --execute to Execute mode" grep -q "\-\-execute.*Execute mode" "$VIBE"
check "REQ-03" "vibe command surface maps --discuss to Discuss mode" grep -q "\-\-discuss.*Discuss mode" "$VIBE"

check "REQ-04" "vibe command surface references AskUserQuestion" grep -q "AskUserQuestion" "$VIBE"

check "REQ-05" "vibe command surface describes --yolo flag" grep -q "\-\-yolo" "$VIBE"
check "REQ-05" "vibe command surface describes --yolo skipping confirmations" grep -q "skip.*confirmation" "$VIBE"

group_end "Core Router"


group_start "GROUP 2: Mode Implementation (REQ-06 to REQ-15)"

check "REQ-06" "vibe command surface has Mode: Init Redirect header" grep -q "### Mode: Init Redirect" "$VIBE"
check "REQ-06" "vibe command surface has Mode: Bootstrap header" grep -q "### Mode: Bootstrap" "$VIBE"
check "REQ-07" "vibe command surface has Mode: Scope header" grep -q "### Mode: Scope" "$VIBE"
check "REQ-10" "vibe command surface has Mode: Discuss header" grep -q "### Mode: Discuss" "$VIBE"
check "REQ-11" "vibe command surface has Mode: Assumptions header" grep -q "### Mode: Assumptions" "$VIBE"
check "REQ-08" "vibe command surface has Mode: Plan header" grep -q "### Mode: Plan" "$VIBE"
check "REQ-09" "vibe command surface has Mode: Execute header" grep -q "### Mode: Execute" "$VIBE"
check "REQ-12" "vibe command surface has Mode: Add Phase header" grep -q "### Mode: Add Phase" "$VIBE"
check "REQ-13" "vibe command surface has Mode: Insert Phase header" grep -q "### Mode: Insert Phase" "$VIBE"
check "REQ-14" "vibe command surface has Mode: Remove Phase header" grep -q "### Mode: Remove Phase" "$VIBE"
check "REQ-15" "vibe command surface has Mode: Archive header" grep -q "### Mode: Archive" "$VIBE"

check "REQ-06" "vibe command surface Bootstrap references PROJECT.md" grep -q "PROJECT.md" "$VIBE"

check "REQ-09" "vibe command surface Execute mode references execute-protocol.md" grep -q "execute-protocol.md" "$VIBE"

check "REQ-15" "vibe command surface Archive mode has audit matrix" grep -q "audit" "$VIBE"

group_end "Mode Implementation"


group_start "GROUP 3: Execution Protocol (REQ-16, REQ-17)"

check "REQ-16" "execute-protocol.md exists in references/" test -f "$PROTOCOL"
check_absent "REQ-16" "execute-protocol.md NOT in commands/" tracked_repo_file_exists "commands/execute-protocol.md"

check_absent "REQ-16" "execute-protocol.md has no name: frontmatter" grep -q "^name:" "$PROTOCOL"

check "REQ-16" "execute-protocol.md contains Step 2" grep -q "Step 2" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 3" grep -q "Step 3" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 4" grep -q "Step 4" "$PROTOCOL"
check "REQ-16" "execute-protocol.md contains Step 5" grep -q "Step 5" "$PROTOCOL"

check "REQ-17" "vibe command surface Execute mode reads execute-protocol.md" grep -q "Read.*execute-protocol" "$VIBE"

group_end "Execution Protocol"


group_start "GROUP 4: Command Surface (REQ-18 to REQ-20)"

ABSORBED=(implement plan execute assumptions add-phase insert-phase remove-phase archive audit)
for cmd in "${ABSORBED[@]}"; do
  check_absent "REQ-18" "commands/${cmd}.md does not exist" tracked_repo_file_exists "commands/${cmd}.md"
done

CMD_COUNT=$(tracked_markdown_count 'commands/*.md')
check "REQ-18" "commands/ has exactly 26 .md files (found $CMD_COUNT)" test "$CMD_COUNT" -eq 26

check_absent "REQ-20" "README.md has no '29 commands'" grep -q "29 commands" "$README"
check_absent "REQ-20" "marketplace.json has no '29 commands'" grep -q "29 commands" "$MKT_ROOT"
check_absent "REQ-20" ".claude-plugin/marketplace.json has no '29 commands'" grep -q "29 commands" "$MKT_PLUGIN"

check_absent "REQ-20" "suggest-next.sh has no /vbw:implement" grep -q "/vbw:implement" "$SUGGEST"
check_absent "REQ-20" "help.md has no /vbw:implement" grep -q "/vbw:implement" "$HELP"
check_absent "REQ-20" "README.md has no /vbw:implement" grep -q "/vbw:implement" "$README"
check_absent "REQ-20" "CLAUDE.md has no /vbw:implement" grep -q "/vbw:implement" "$CLAUDE_MD"

check "REQ-20" "suggest-next.sh references /vbw:vibe" grep -q "/vbw:vibe" "$SUGGEST"

group_end "Command Surface"


group_start "GROUP 5: NL Parsing (REQ-21, REQ-22)"

check_absent "REQ-21" "vibe command surface has no regex patterns" grep -q "regex" "$VIBE"
check_absent "REQ-21" "vibe command surface has no import statements" grep -q "^import " "$VIBE"
check "REQ-21" "vibe command surface has keyword-based intent matching" grep -q "keywords" "$VIBE"

check "REQ-22" "vibe command surface handles ambiguous intents" grep -q "Ambiguous" "$VIBE"
check "REQ-22" "vibe command surface routes ambiguity to contextual AskUserQuestion flow" grep -q "Ambiguous -> AskUserQuestion with contextual options" "$VIBE"

group_end "NL Parsing"


group_start "GROUP 6: Flags (REQ-23 to REQ-25)"

FLAG_COUNT=$(grep -c "^\- \`--" "$VIBE" || true)
check "REQ-23" "vibe command surface has >= 9 mode flags (found $FLAG_COUNT)" test "$FLAG_COUNT" -ge 9

check "REQ-24" "vibe command surface has --effort modifier" grep -q "\-\-effort" "$VIBE"
check "REQ-24" "vibe command surface has --skip-qa modifier" grep -q "\-\-skip-qa" "$VIBE"
check "REQ-24" "vibe command surface has --skip-audit modifier" grep -q "\-\-skip-audit" "$VIBE"
check "REQ-24" "vibe command surface has --plan=NN modifier" grep -q "\-\-plan=NN" "$VIBE"

check "REQ-25" "vibe command surface documents bare integer support" grep -qi "bare integer" "$VIBE"
check "REQ-25" "vibe command surface bare integer targets phase N" grep -q "phase N" "$VIBE"

group_end "Flags"


echo ""
echo "==============================="
echo "  TOTAL: $TOTAL_PASS PASS, $TOTAL_FAIL FAIL"
echo "==============================="

if [ "$TOTAL_FAIL" -eq 0 ]; then
  echo "  All checks passed."
  exit 0
else
  echo "  Some checks failed."
  exit 1
fi
