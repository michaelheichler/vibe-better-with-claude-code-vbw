echo "=== Command Contract Verification ==="

for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  if [ "$(head -1 "$file" 2>/dev/null || true)" != "---" ]; then
    fail "$base: missing YAML frontmatter opener"
    continue
  fi

  FRONTMATTER="$(extract_frontmatter "$file")"
  if [ -z "$FRONTMATTER" ]; then
    fail "$base: empty or malformed frontmatter"
    continue
  fi

  NAME_VALUE="$(frontmatter_first_scalar "$FRONTMATTER" "name")"
  NAME_STEM="${NAME_VALUE#vbw:}"

  if [ -z "$NAME_VALUE" ]; then
    fail "$base: missing name field"
  elif [ "$NAME_STEM" != "$base" ]; then
    fail "$base: name mismatch (expected '$base', got '$NAME_VALUE')"
  else
    pass "$base: name matches filename"
  fi

  if ! grep -q '^allowed-tools:' <<< "$FRONTMATTER"; then
    fail "$base: missing allowed-tools field"
  else
    pass "$base: allowed-tools present"
  fi

  DESC_COUNT="$(grep -c '^description:' <<<"$FRONTMATTER")"
  if [ "$DESC_COUNT" -ne 1 ]; then
    fail "$base: description field missing or duplicated"
    continue
  fi

  DESC_VALUE="$(frontmatter_first_scalar "$FRONTMATTER" "description")"
  if [ -z "$DESC_VALUE" ]; then
    fail "$base: description is empty"
  elif [[ "$DESC_VALUE" == \|* || "$DESC_VALUE" == \>* ]]; then
    fail "$base: description must be single-line (block scalar found)"
  else
    AFTER_DESC="$(frontmatter_continuation_lines "$FRONTMATTER" "description")"
    if [ -n "$AFTER_DESC" ]; then
      fail "$base: description has continuation lines"
    else
      pass "$base: description is single-line"
    fi
  fi
done

echo ""
echo "=== Non-Team Name Contract Verification ==="

STALE_NON_TEAM_NAME_PATTERNS=(
  'no `team_name`, `name`'
  'omit `team_name`, `name`'
  'Do not pass `team_name`, per-agent `name`'
  'do not pass `team_name`, per-agent `name`'
  'Do not pass team metadata (`team_name`), per-agent names (`name`)'
  'do not pass team metadata (`team_name`), per-agent names (`name`)'
)
NON_TEAM_NAME_SCAN_FILES=("${TRACKED_COMMAND_MARKDOWN_FILES[@]}" "$ROOT/references/execute-protocol.md")
stale_non_team_name_found=false
for file in "${NON_TEAM_NAME_SCAN_FILES[@]}"; do
  [ -f "$file" ] || continue
  for pattern in "${STALE_NON_TEAM_NAME_PATTERNS[@]}"; do
    if grep -Fq -- "$pattern" "$file"; then
      fail "non-team name contract: stale name-ban phrase in ${file#"$ROOT/"}: $pattern"
      stale_non_team_name_found=true
    fi
  done
done
if [ "$stale_non_team_name_found" = false ]; then
  pass "non-team name contract: command/reference prose has no stale name-ban phrases"
fi

DEBUG_COMMAND_FILE="$COMMANDS_DIR/debug.md"
NON_TEAM_INVARIANT_TEXT='Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.'
NO_TOOL_INVARIANT_TEXT='No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.'

debug_path_a_block="$(awk '
  /\*\*Path A: Competing Hypotheses\*\*/ { in_block = 1 }
  in_block && /\*\*Path B: Standard\*\*/ { exit }
  in_block { print }
' "$DEBUG_COMMAND_FILE")"

debug_path_a_investigator_block="$(awk '
  /Spawn 3 vbw-debugger teammates/ { in_block = 1 }
  in_block && /\*\*Investigation phase:\*\*/ { exit }
  in_block { print }
' "$DEBUG_COMMAND_FILE")"

debug_path_a_implementation_block="$(awk '
  /\*\*Implementation phase:\*\*/ { in_block = 1 }
  in_block && /\*\*Path B: Standard\*\*/ { exit }
  in_block { print }
' "$DEBUG_COMMAND_FILE")"

debug_path_b_block="$(awk '
  /\*\*Path B: Standard\*\*/ { in_block = 1 }
  in_block && /^5\. \*\*Persist to debug session \+ Clear delegation marker \+ Present:/ { exit }
  in_block { print }
' "$DEBUG_COMMAND_FILE")"

debug_inline_qa_spawn_block="$(awk '
  /Spawn vbw-qa as subagent via Agent tool for debug-session verification/ { in_block = 1 }
  in_block && /Use this payload prefix as the FIRST lines of the debug-session QA prompt/ { exit }
  in_block { print }
' "$DEBUG_COMMAND_FILE")"

if contains_literal "$debug_path_a_block" 'there is no TeamCreate setup step' \
  && contains_literal "$debug_path_a_investigator_block" 'True-team spawn shape' \
  && contains_literal "$debug_path_a_investigator_block" 'accepted but ignored' \
  && contains_literal "$debug_path_a_investigator_block" 'unique per-teammate `name`' \
  && contains_literal "$debug_path_a_investigator_block" 'debug-hypothesis-1' \
  && contains_literal "$debug_path_a_investigator_block" 'Do not pass `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir`'; then
  pass "debug: Path A hypothesis investigators use true-team spawn metadata"
else
  fail "debug: Path A hypothesis investigators must document implicit team formation and per-teammate names"
fi

if contains_literal "$debug_path_a_investigator_block" 'Non-team spawn shape' \
  || contains_literal "$debug_path_a_investigator_block" "$NON_TEAM_INVARIANT_TEXT"; then
  fail "debug: Path A hypothesis investigators must not use non-team label wording"
else
  pass "debug: Path A hypothesis investigators avoid non-team label wording"
fi

if contains_literal "$debug_path_a_implementation_block" "$NON_TEAM_INVARIANT_TEXT"; then
  pass "debug: Path A post-shutdown implementation owner remains non-team"
else
  fail "debug: Path A post-shutdown implementation owner must remain non-team"
fi

if contains_literal "$debug_path_b_block" "$NON_TEAM_INVARIANT_TEXT"; then
  pass "debug: Path B debugger remains non-team"
else
  fail "debug: Path B debugger must retain the canonical non-team invariant"
fi

if contains_literal "$debug_inline_qa_spawn_block" "$NON_TEAM_INVARIANT_TEXT"; then
  pass "debug: inline QA spawn remains non-team"
else
  fail "debug: inline QA spawn must retain the canonical non-team invariant"
fi

echo ""
echo "=== AskUserQuestion Contract Verification ==="

ASK_USER_QUESTION_REF="$ROOT/references/ask-user-question.md"
VIBE_COMMAND_FILE="$COMMANDS_DIR/vibe.md"
VIBE_CONFIRMATION_BLOCK="$(extract_heading_block "$VIBE_COMMAND_FILE" "### Confirmation Gate" '^## ' || true)"

if [ -f "$ASK_USER_QUESTION_REF" ]; then
  pass "ask-user-question: shared reference exists"
else
  fail "ask-user-question: shared reference missing"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Source note:' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: source note present"
else
  fail "ask-user-question: missing source note"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Last reviewed:' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: last reviewed metadata present"
else
  fail "ask-user-question: missing last reviewed metadata"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'Keep headers short' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents short-header rule"
else
  fail "ask-user-question: missing short-header rule"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '2-4 options' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents 2-4 option sweet spot"
else
  fail "ask-user-question: missing 2-4 option guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '1-4 questions' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents 1-4 question guidance"
else
  fail "ask-user-question: missing 1-4 question guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '`Other` path' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents built-in Other path"
else
  fail "ask-user-question: missing built-in Other path guidance"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq 'high-cardinality or unbounded' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents intentional freeform boundary"
else
  fail "ask-user-question: missing intentional freeform boundary"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '### Example[^[:alnum:]]+structured single-select' "$ASK_USER_QUESTION_REF" \
  && grep -Eq '### Example[^[:alnum:]]+intentional freeform' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes structured and freeform examples"
else
  fail "ask-user-question: missing structured/freeform example coverage"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '### Freeform handoff' "$ASK_USER_QUESTION_REF" \
  && grep -Fq 'stop using AskUserQuestion' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: documents freeform handoff rule"
else
  fail "ask-user-question: missing freeform handoff rule"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Fq '## Anti-patterns' "$ASK_USER_QUESTION_REF" \
  && grep -Fq 'Fake bounded menus' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes anti-patterns section"
else
  fail "ask-user-question: missing anti-patterns section"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && grep -Eq '### Example[^[:alnum:]]+decision gate' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: includes decision gate example"
else
  fail "ask-user-question: missing decision gate example"
fi

if [ -f "$ASK_USER_QUESTION_REF" ] && ! grep -Eiq 'github\.com/.*issues|fixes #[0-9]+|see #[0-9]+|issue #[0-9]+|parent.*#[0-9]+' "$ASK_USER_QUESTION_REF"; then
  pass "ask-user-question: no volatile upstream issue links"
else
  fail "ask-user-question: contains volatile upstream issue links"
fi

if grep -Fq '@${CLAUDE_PLUGIN_ROOT}/references/ask-user-question.md' "$VIBE_COMMAND_FILE"; then
  pass "vibe: loads shared AskUserQuestion reference"
else
  fail "vibe: missing shared AskUserQuestion reference include"
fi

if [ -n "$VIBE_CONFIRMATION_BLOCK" ]; then
  pass "vibe: confirmation gate block extracted for boundary checks"
else
  fail "vibe: could not extract confirmation gate block"
fi

if grep -Fq 'references/ask-user-question.md' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  pass "vibe: confirmation gate points to shared AskUserQuestion reference"
else
  fail "vibe: confirmation gate missing shared AskUserQuestion reference"
fi

if grep -Fq '**Exception:** `--yolo` skips all confirmation gates.' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Exception:** Flags skip confirmation (explicit intent).' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '| Routing state | Recommended | Alternatives |' <<< "$VIBE_CONFIRMATION_BLOCK" \
  && grep -Fq '**Discussion-aware alternatives:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  pass "vibe: confirmation gate keeps vibe-local routing behavior"
else
  fail "vibe: confirmation gate lost vibe-local routing constructs"
fi

if grep -Eq '2-4 options|1-4 questions|freeform|high-cardinality' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '`Other` path' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'Keep headers short' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'dialog obscures' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq 'For simple yes/no confirmations without a table entry' <<< "$VIBE_CONFIRMATION_BLOCK" \
  || grep -Fq '**AskUserQuestion parameters:**' <<< "$VIBE_CONFIRMATION_BLOCK"; then
  fail "vibe: confirmation gate still carries generic AskUserQuestion contract guidance"
else
  pass "vibe: confirmation gate keeps generic AskUserQuestion contract guidance out of vibe-local prose"
fi

echo ""
