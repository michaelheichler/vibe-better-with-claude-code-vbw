echo "=== Allowed-Tools Consistency Verification ==="

for file in "${TRACKED_COMMAND_MARKDOWN_FILES[@]}"; do
  base="$(basename "$file" .md)"

  FRONTMATTER="$(extract_frontmatter "$file")"
  if [ -z "$FRONTMATTER" ]; then
    continue
  fi

  ALLOWED="$(frontmatter_first_scalar "$FRONTMATTER" "allowed-tools")"
  if [ -z "$ALLOWED" ]; then
    continue
  fi

  check_allowed_tool_match "$base" "$ALLOWED" "$file" "AskUserQuestion" '(^|[^[:alnum:]_])AskUserQuestion([^[:alnum:]_]|$)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Skill" 'Call[[:space:]]+Skill[(]|(^|[^[:alnum:]_])Skill[(]'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "WebSearch" '(^|[^[:alnum:]_])WebSearch([^[:alnum:]_]|$)' 'do[[:space:]]+not.*WebSearch'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "Agent" '(via[[:space:]]+Task[[:space:]]+tool|Task[[:space:]]+tool[[:space:]]+invocation|subagent_type:)'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TaskCreate" '(^|[^[:alnum:]_])TaskCreate([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TaskCreate'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "TodoWrite" '(^|[^[:alnum:]_])TodoWrite([^[:alnum:]_]|$)' 'do[[:space:]]+not.*TodoWrite|disallow.*TodoWrite|forbid.*TodoWrite'
  check_allowed_tool_match "$base" "$ALLOWED" "$file" "SendMessage" '(^|[^[:alnum:]_])SendMessage([^[:alnum:]_]|$)' 'do[[:space:]]+not.*SendMessage'
done

for skill_cmd in debug fix map qa research vibe; do
  skill_file="$COMMANDS_DIR/${skill_cmd}.md"
  [ -f "$skill_file" ] || continue

  if grep -Fq 'Call Skill(' "$skill_file"; then
    skill_allowed="$(frontmatter_first_scalar_from_file "$skill_file" "allowed-tools")"
    if has_allowed_tool "$skill_allowed" "Skill"; then
      pass "$skill_cmd: regression guard confirms Skill allowlist"
    else
      fail "$skill_cmd: regression guard found Call Skill(...) but allowed-tools is missing Skill"
    fi
  fi
done

INIT_FILE="$COMMANDS_DIR/init.md"
if [ -f "$INIT_FILE" ] && grep -Fq 'WebSearch' "$INIT_FILE"; then
  init_allowed="$(frontmatter_first_scalar_from_file "$INIT_FILE" "allowed-tools")"
  if has_allowed_tool "$init_allowed" "WebSearch"; then
    pass "init: regression guard confirms WebSearch allowlist"
  else
    fail "init: regression guard found WebSearch in body but allowed-tools is missing WebSearch"
  fi
fi

echo ""
echo "=== Command Reference Verification ==="

while IFS= read -r ref; do
  rel="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"

  if [[ "$rel" == *"{"* || "$rel" == *"}"* ]]; then
    pass "reference uses template placeholder (skipped): $ref"
    continue
  fi

  if [[ "$rel" == *"*"* ]]; then
    if compgen -G "$ROOT/$rel" >/dev/null; then
      pass "wildcard reference resolves: $ref"
    else
      fail "wildcard reference has no matches: $ref"
    fi
    continue
  fi

  if [ -e "$ROOT/$rel" ]; then
    pass "reference resolves: $ref"
  else
    fail "reference missing target: $ref -> $rel"
  fi
done < <(grep -RhoE '\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9._/*{}-]+' "${TRACKED_COMMAND_MARKDOWN_FILES[@]}" 2>/dev/null | sort -u)

echo ""
echo "--- UAT Remediation TodoWrite disambiguation ---"
uat_section="$(
  awk '
    /^### Mode: UAT Remediation$/ { in_section=1; next }
    in_section && /^### Mode:/ { exit }
    in_section { print }
  ' "$VIBE_FILE"
)"
if grep -q '\*\*TodoWrite progress list (NON-NEGOTIABLE' <<< "$uat_section"; then
  pass "UAT Remediation step 4 explicitly references TodoWrite"
else
  fail "UAT Remediation step 4 missing 'TodoWrite progress list' heading. risk of TaskCreate conflation (see issue #367)"
fi

if contains_literal "$uat_section" 'TodoWrite is the only progress tracker for these stages'; then
  pass "UAT Remediation declares TodoWrite as the sole stage progress tracker"
else
  fail "UAT Remediation missing explicit TodoWrite-only stage progress tracker contract"
fi

if contains_literal "$uat_section" 'Do not represent Research, Plan, Execute, or Fix as TaskCreate/TaskUpdate items'; then
  pass "UAT Remediation forbids TaskCreate/TaskUpdate stage trackers"
else
  fail "UAT Remediation missing TaskCreate/TaskUpdate stage-tracker prohibition"
fi

if contains_literal "$uat_section" 'TaskCreate/Agent is allowed only for real Scout/Lead/Dev work-unit delegation inside the current stage'; then
  pass "UAT Remediation distinguishes progress tracking from Scout/Lead/Dev delegation"
else
  fail "UAT Remediation missing delegation/progress-tracking distinction"
fi
