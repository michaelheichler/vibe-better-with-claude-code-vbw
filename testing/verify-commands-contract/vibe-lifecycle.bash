echo "=== Milestone Context Refresh Verification ==="
mode_block() {
  case "$1" in
    "### Mode: Add Phase") cat "$ROOT/references/vibe-mode-add-phase.md" ;;
    "### Mode: Insert Phase") cat "$ROOT/references/vibe-mode-insert-phase.md" ;;
    "### Mode: Remove Phase") cat "$ROOT/references/vibe-mode-remove-phase.md" ;;
    "### Mode: Archive") cat "$ROOT/references/vibe-mode-archive.md" ;;
    *) extract_heading_block "$VIBE_FILE" "$1" '^### Mode: ' ;;
  esac
}

echo ""
echo "=== Mode Block Helper Regression Verification ==="

_mode_helper_tmp_dir="$(mktemp -d)"
_mode_helper_fixture="$_mode_helper_tmp_dir/mode-block-fixture.md"
printf '%s' $'### Mode: Archive   \r\n9b. Post-archive hook (non-blocking): after successful archive completion, run:\r\n  MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh\r\n    .vbw-planning)\r\n### Mode: Next\r\nignored\r\n' > "$_mode_helper_fixture"
_mode_helper_block="$(extract_heading_block "$_mode_helper_fixture" "### Mode: Archive" '^### Mode: ' || true)"

if [ -n "$_mode_helper_block" ]; then
  pass "mode-block helper extracts mode blocks with trailing-space/CRLF headings"
else
  fail "mode-block helper failed to extract mode block with trailing-space/CRLF heading"
fi

if block_contains_normalized "$_mode_helper_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)'; then
  pass "mode-block helper matches wrapped milestone slug command after whitespace normalization"
else
  fail "mode-block helper missed wrapped milestone slug command after whitespace normalization"
fi

if contains_literal "$_mode_helper_block" 'ignored'; then
  fail "mode-block helper did not stop at the next mode heading"
else
  pass "mode-block helper stops at the next mode heading"
fi

if block_contains_normalized "$_mode_helper_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/not-the-helper.sh .vbw-planning)'; then
  fail "mode-block helper normalization produced a false positive for the wrong helper path"
else
  pass "mode-block helper normalization rejects wrong helper paths"
fi

rm -rf "$_mode_helper_tmp_dir"

for mode in "### Mode: Add Phase" "### Mode: Insert Phase" "### Mode: Remove Phase"; do
  block=$(mode_block "$mode")
  label=${mode#"### Mode: "}

  if grep -q 'If `\.vbw-planning/CONTEXT\.md` exists, rewrite it to reflect the updated milestone decomposition' <<< "$block"; then
    pass "vibe: $label refreshes milestone CONTEXT.md"
  else
    fail "vibe: $label missing milestone CONTEXT refresh instruction"
  fi

  if grep -q 'Preserve project-level key decisions and deferred ideas where still valid\.' <<< "$block"; then
    pass "vibe: $label preserves milestone decisions and deferred ideas"
  else
    fail "vibe: $label missing preservation instruction for milestone CONTEXT refresh"
  fi
done

echo ""
echo "=== Add Phase Numbering Verification ==="

add_phase_block=$(mode_block "### Mode: Add Phase")
if contains_literal "$add_phase_block" '6. Update ROADMAP.md:' \
  && contains_literal "$add_phase_block" '7. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition' \
  && contains_literal "$add_phase_block" '8. Update STATE.md phase total:' \
  && contains_literal "$add_phase_block" '9. **Phase mutation commit boundary (conditional):**' \
  && contains_literal "$add_phase_block" '10. Present:' \
  && ! contains_literal "$add_phase_block" '1. Update ROADMAP.md:'; then
  pass "vibe: Add Phase keeps one ordered parent step list"
else
  fail "vibe: Add Phase restarts ordered steps instead of continuing 6-10"
fi

echo ""
echo "=== Archive Hook Wiring Verification ==="

archive_block=$(mode_block "### Mode: Archive")

if contains_literal "$archive_block" '9b. Post-archive hook (non-blocking): after successful archive completion, run:'; then
  pass "vibe: Archive mode includes explicit post-archive hook step"
else
  fail "vibe: Archive mode missing explicit post-archive hook step"
fi

if block_contains_normalized "$archive_block" 'MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)'; then
  pass "vibe: Archive mode derives milestone slug via derive-milestone-slug.sh"
else
  fail "vibe: Archive mode missing deterministic milestone slug derivation"
fi

if contains_literal "$archive_block" 'Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).'; then
  pass "vibe: Archive mode still defines --tag as a custom git tag"
else
  fail "vibe: Archive mode no longer defines --tag as a custom git tag"
fi

if contains_literal "$archive_block" 'Override with `--tag` if provided.'; then
  fail "vibe: Archive mode still lets --tag override milestone slug"
else
  pass "vibe: Archive mode keeps milestone slug separate from custom --tag"
fi

if block_contains_normalized "$archive_block" 'bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/post-archive-hook.sh "{SLUG}" ".vbw-planning/milestones/{SLUG}" "{tag}" .vbw-planning/config.json'; then
  pass "vibe: Archive mode wires post-archive hook with slug/archive/tag/config arguments"
else
  fail "vibe: Archive mode missing post-archive hook argument contract"
fi

archive_regen_line=$(first_matching_line_number "$archive_block" '9. Regenerate CLAUDE.md:')
archive_hook_line=$(first_matching_line_number "$archive_block" '9b. Post-archive hook (non-blocking):')
archive_present_line=$(first_matching_line_number "$archive_block" '10. Present:')

if [ -n "$archive_regen_line" ] && [ -n "$archive_hook_line" ] && [ -n "$archive_present_line" ] \
  && [ "$archive_regen_line" -lt "$archive_hook_line" ] \
  && [ "$archive_hook_line" -lt "$archive_present_line" ]; then
  pass "vibe: Archive post-archive hook remains between CLAUDE regeneration and final presentation"
else
  fail "vibe: Archive post-archive hook ordering drifted outside the successful archive sequence"
fi

echo ""
