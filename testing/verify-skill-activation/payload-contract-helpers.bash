expected_skill_contract_sites() {
  case "$(basename "$1")" in
    debug.md|vibe-uat-remediation.md) echo 3 ;;
    map.md|qa.md|vibe-input-parsing.md|vibe-mode-plan.md) echo 2 ;;
    research.md|fix.md|execute-protocol.md|vibe-mode-bootstrap.md|vibe-mode-add-phase.md|vibe-mode-insert-phase.md) echo 1 ;;
    *) echo 0 ;;
  esac
}

collect_skill_contract_site_lines() {
  local file="$1"
  grep -nE 'evaluate installed skills visible in your system context|Skill activation for Dev/QA tasks' "$file" 2>/dev/null | cut -d: -f1 || true
}

is_uat_remediation_skill_site() {
  [ "$(basename "$1")" = "vibe-uat-remediation.md" ]
}

verify_render_directive() {
  local file_name="$1" site_number="$2" segment="$3" render_count
  render_count=$(grep -c 'Render the prompt prefix from `' <<< "$segment" || true)
  if [ "$render_count" -eq 1 ]; then
    pass "$file_name: site $site_number renders the canonical payload template once"
  else
    fail "$file_name: site $site_number expected one payload render directive, found $render_count"
  fi
}

verify_local_outcomes() {
  local file_name="$1" site_number="$2" segment="$3"
  if grep -q '<skill_activation>' <<< "$segment" \
    && grep -q '<skill_no_activation>' <<< "$segment" \
    && grep -qi 'reason' <<< "$segment"; then
    pass "$file_name: site $site_number keeps local selected and no-selected policy"
  else
    fail "$file_name: site $site_number lost local selected or no-selected policy"
  fi
  if grep -q 'exactly one explicit' <<< "$segment"; then
    pass "$file_name: site $site_number states the one-of-two outcome contract"
  else
    fail "$file_name: site $site_number missing one-of-two outcome wording"
  fi
  if grep -qi 'state the skill outcome in your response\|states the skill evaluation outcome' <<< "$segment"; then
    pass "$file_name: site $site_number keeps visible-reporting guidance"
  else
    fail "$file_name: site $site_number missing visible-reporting guidance"
  fi
}

verify_selection_scope() {
  local file="$1"
  local file_name="$2"
  local site_number="$3"
  local segment="$4"
  if is_uat_remediation_skill_site "$file"; then
    if grep -q 'select only skills directly needed\|select the task-specific skills listed in the remediation plan' <<< "$segment"; then
      pass "$file_name: site $site_number keeps UAT-scoped selection"
    else
      fail "$file_name: site $site_number lost UAT-scoped selection"
    fi
    pass "$file_name: site $site_number keeps its narrow role scope"
  elif grep -q 'materially helpful' <<< "$segment" \
    && grep -q 'single most direct skill' <<< "$segment" \
    && grep -qi 'swiftdata' <<< "$segment"; then
    pass "$file_name: site $site_number keeps additive selection and adjacent-skill example"
  else
    fail "$file_name: site $site_number lost additive selection or adjacent-skill example"
  fi
  if grep -qi 'do not scan entire skill folders or read unrelated references\|not entire skill folders or unrelated references' <<< "$segment"; then
    pass "$file_name: site $site_number keeps the follow-up read nudge"
  else
    fail "$file_name: site $site_number lost the follow-up read nudge"
  fi
}

verify_skill_contract_sites() {
  local file="$1" file_name expected_count total_lines start_line end_line site_number segment
  local site_lines=()
  file_name=$(basename "$file")
  expected_count=$(expected_skill_contract_sites "$file")
  total_lines=$(wc -l < "$file" | tr -d ' ')
  while IFS= read -r line; do
    [ -n "$line" ] && site_lines+=("$line")
  done < <(collect_skill_contract_site_lines "$file")
  if [ "${#site_lines[@]}" -eq "$expected_count" ]; then
    pass "$file_name: found $expected_count explicit skill-evaluation site(s)"
  else
    fail "$file_name: expected $expected_count explicit skill-evaluation site(s), found ${#site_lines[@]}"
  fi
  site_number=1
  while [ "$site_number" -le "${#site_lines[@]}" ]; do
    start_line="${site_lines[$((site_number - 1))]}"
    end_line="$total_lines"
    [ "$site_number" -ge "${#site_lines[@]}" ] || end_line=$(( ${site_lines[$site_number]} - 1 ))
    segment=$(sed -n "${start_line},${end_line}p" "$file")
    verify_render_directive "$file_name" "$site_number" "$segment"
    verify_local_outcomes "$file_name" "$site_number" "$segment"
    verify_selection_scope "$file" "$file_name" "$site_number" "$segment"
    site_number=$((site_number + 1))
  done
}
