echo "=== skills.md Step 5 Verification ==="

SKILLS_FILE="$COMMANDS_DIR/skills.md"
SKILLS_INSTALLATION_HEADING='#''#''# Step ''5: Offer installation'
if [ ! -f "$SKILLS_FILE" ]; then
  fail "skills: command file not found"
else
  skills_step_5="$({
    awk -v heading="$SKILLS_INSTALLATION_HEADING" '
      $0 == heading { in_block=1; next }
      in_block && /^### / { exit }
      in_block { print }
    ' "$SKILLS_FILE"
  } || true)"

  if [ -z "$skills_step_5" ]; then
    fail "skills: missing Step 5 block"
  else
    if grep -Fq 'Combine curated + registry, deduplicate, rank (curated first).' <<< "$skills_step_5"; then
      pass "skills: Step 5 preserves curated-first ranking"
    else
      fail "skills: Step 5 missing curated-first ranking guidance"
    fi

    if grep -Fq 'If the combined list is empty: STOP here. Do NOT AskUserQuestion.' <<< "$skills_step_5"; then
      pass "skills: Step 5 stops immediately when no candidates exist"
    else
      fail "skills: Step 5 missing empty-list stop without AskUserQuestion"
    fi

    if grep -Fq 'If the combined list has exactly 1 candidate: keep it structured.' <<< "$skills_step_5" \
      && grep -Fq 'AskUserQuestion with a single bounded question.' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps single-candidate installs structured"
    else
      fail "skills: Step 5 missing structured single-candidate branch"
    fi

    if grep -Eq 'If the combined list has 2-4 candidates: keep it structured' <<< "$skills_step_5" \
      && grep -Eq 'Use AskUserQuestion with 1 question per skill \(2-4 questions total\)' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps bounded multi-candidate installs structured"
    else
      fail "skills: Step 5 missing structured 2-4 candidate branch"
    fi

    if grep -Fq 'For any bounded AskUserQuestion branch below that uses visible options, the built-in `Other` path is still part of that question:' <<< "$skills_step_5" \
      && grep -Fq 'accept unambiguous visible option-by-number replies (for example `#1` / `#2`)' <<< "$skills_step_5" \
      && grep -Fq 'accept hybrid replies anchored to one of those visible option numbers (for example `#2 for now`)' <<< "$skills_step_5" \
      && grep -Fq 're-ask only when the follow-up is ambiguous or invalid for that same question.' <<< "$skills_step_5"; then
      pass "skills: Step 5 bounded Other path accepts numbered and hybrid replies"
    else
      fail "skills: Step 5 missing bounded Other-path numbered/hybrid reply guidance"
    fi

    if grep -Fq 'If none were selected, display `○ No skills selected for installation.` and STOP here. Do not enter Step 6.' <<< "$skills_step_5"; then
      pass "skills: Step 5 stops when bounded structured branches decline everything"
    else
      fail "skills: Step 5 missing no-selection stop before installation"
    fi

    if grep -Fq 'If the combined list has more than 4 candidates: use intentional high-cardinality freeform input.' <<< "$skills_step_5" \
      && grep -Fq 'do NOT use `options` array' <<< "$skills_step_5" \
      && grep -Eq 'larger than the 2-4 structured-choice sweet spot' <<< "$skills_step_5"; then
      pass "skills: Step 5 keeps 5+ candidates on an intentional freeform path"
    else
      fail "skills: Step 5 missing explicit intentional freeform 5+ candidate branch"
    fi
  fi
fi

echo ""
echo "=== Project-Scoped Skill Install Verification ==="

if [ ! -f "$SKILLS_FILE" ]; then
  fail "skills: command file not found"
else
  if grep -Fq '### Step 5b: Choose installation scope' "$SKILLS_FILE" \
    || grep -Fq -- '- **Global**' "$SKILLS_FILE" \
    || grep -Fq 'based on SCOPE' "$SKILLS_FILE"; then
    fail "skills: selectable installation scope remains"
  else
    pass "skills: selectable installation scope removed"
  fi

  if grep -Fq 'Curated suggestions are suppressed only by project-installed skills.' "$SKILLS_FILE"; then
    pass "skills: global installs are informational for curated suggestions"
  else
    fail "skills: missing project-only curated suggestion guidance"
  fi

  if grep -Fq 'Run `npx skills add <skill> -y` for each selected skill.' "$SKILLS_FILE"; then
    pass "skills: install step uses project scope"
  else
    fail "skills: project-scoped install command missing"
  fi
fi

for skill_install_file in "$COMMANDS_DIR/init.md" "$COMMANDS_DIR/skills.md"; do
  skill_install_name="$(basename "$skill_install_file")"
  if grep -Eq 'npx[[:space:]]+skills[[:space:]]+add[^`]*[[:space:]](-g|--global)([[:space:]`]|$)' "$skill_install_file"; then
    fail "$skill_install_name: global skills install flag present"
  else
    pass "$skill_install_name: skills installs remain project-scoped"
  fi
done

echo ""
echo "=== Milestone Context Verification ==="

for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  body="$(awk '/^---$/{d++; next} d>=2' "$file")"
  body_no_context="$(printf '%s\n' "$body" | awk '/^## Context$/{skip=1; next} /^## /{skip=0} !skip')"

  if grep -qi '\.vbw-planning/ACTIVE' <<< "$body_no_context"; then
    fail "$base: references .vbw-planning/ACTIVE. milestone indirection was removed"
  else
    pass "$base: no stale ACTIVE file references"
  fi
done

echo ""
echo "=== Stale ACTIVE Reference Verification (scripts + references) ==="

for scan_file in "${TRACKED_ACTIVE_SCAN_FILES[@]}"; do
  rel_scan_file="${scan_file#$ROOT/}"
  dir_label="${rel_scan_file%%/*}"
  scan_base="$(basename "$scan_file")"

  if [[ "$scan_base" == "session-start.sh" ]]; then
    pass "$dir_label/$scan_base: ACTIVE reference allowed (cleanup migration)"
    continue
  fi

  if grep -qi '\.vbw-planning/ACTIVE' "$scan_file" 2>/dev/null; then
    fail "$dir_label/$scan_base: references .vbw-planning/ACTIVE. milestone indirection was removed"
  else
    pass "$dir_label/$scan_base: no stale ACTIVE file references"
  fi
done

echo ""
echo "=== Phase-Detect Usage Verification ==="

PHASE_DETECT_REQUIRED_COMMANDS="resume vibe discuss qa verify"
for pd_cmd in $PHASE_DETECT_REQUIRED_COMMANDS; do
  pd_file="$COMMANDS_DIR/${pd_cmd}.md"
  if [ ! -f "$pd_file" ]; then
    fail "$pd_cmd: command file not found"
    continue
  fi
  pd_scan_files=("$pd_file")
  if [ "$pd_cmd" = "vibe" ]; then
    pd_scan_files+=("$ROOT"/references/vibe-mode-*.md)
  fi
  if grep -q 'phase-detect\.sh' "${pd_scan_files[@]}"; then
    pass "$pd_cmd: uses phase-detect.sh for state detection"
  else
    fail "$pd_cmd: missing phase-detect.sh. LLM may read archived milestone data"
  fi
done

echo ""
