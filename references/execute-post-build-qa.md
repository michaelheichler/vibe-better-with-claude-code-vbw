If `--skip-qa` or turbo: "○ QA verification skipped ({reason})"

**Auto-skip for certain agents:** Check if the current agent type is in `qa_skip_agents` config array (default: `["docs"]`):
```bash
AGENT_TYPE=$(jq -r '.current_agent_type // "dev"' .vbw-planning/config.json 2>/dev/null)
QA_SKIP_AGENTS=$(jq -r '.qa_skip_agents // []' .vbw-planning/config.json 2>/dev/null)
if echo "$QA_SKIP_AGENTS" | jq -e --arg agent "$AGENT_TYPE" 'contains([$agent])' >/dev/null 2>&1; then
  echo "○ QA verification skipped (agent: $AGENT_TYPE)"
  # Skip to Step 4.5 (UAT)
fi
```
When the agent type is in the skip list, QA is skipped automatically without needing `--skip-qa` flag. Docs-only changes don't need formal QA.

**After QA persists VERIFICATION.md (and only after that), run the verification threshold gate:**
```bash
bash "${VBW_PLUGIN_ROOT}/scripts/hard-gate.sh" verification_threshold {phase} {plan} {task} {contract_path}
```
If this gate fails, treat it as a QA/verification failure and stop before UAT.

**Dev-surfaced issues collection (before spawning QA):**
After all plans are complete (Step 3c verified), collect deviations and pre-existing issues from all SUMMARY.md files. This data is passed to QA in the task description so QA can treat deviations as FAIL checks and persist pre-existing issues in VERIFICATION.md.

```bash
# Collect deviations and pre-existing issues from all SUMMARY.md files
DEV_ISSUES=""
for summary_file in {phase-dir}/*-SUMMARY.md
do
  [ -f "$summary_file" ] || continue
  plan_id=$(basename "$summary_file" | sed 's/-SUMMARY\.md$//')

  # Extract deviations from YAML frontmatter AND the body ## Deviations section.
  # The shared helper merges both sources in stable order, drops placeholder
  # "none" values, and de-duplicates exact duplicates. Frontmatter must not
  # mask body-only deviation detail.
  devs=""
  if [ -f "${VBW_PLUGIN_ROOT}/scripts/summary-utils.sh" ]; then
    # shellcheck source=/dev/null
    . "${VBW_PLUGIN_ROOT}/scripts/summary-utils.sh"
  fi
  if type extract_summary_deviations >/dev/null 2>&1; then
    devs=$(extract_summary_deviations "$summary_file" 2>/dev/null | awk '
      NF { items = items (items ? "; " : "") $0 }
      END { print items }
    ')
  fi

  # Extract pre-existing issues from canonical SUMMARY.md frontmatter first.
  preex_key_present=false
  awk '
    BEGIN { in_fm=0; found=0 }
    NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
    in_fm && /^---[[:space:]]*$/ { exit(found ? 0 : 1) }
    in_fm && /^pre_existing_issues:[[:space:]]*/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$summary_file" >/dev/null 2>&1 && preex_key_present=true

  preex=$(summary_extract_frontmatter_array_items "$summary_file" pre_existing_issues | while IFS= read -r issue_json
  do
    [ -n "$issue_json" ] || continue
    printf '%s' "$issue_json" | jq -er '
      select(type == "object")
      | if .file == .test then
          (.test + ": " + .error)
        else
          (.test + " (" + .file + "): " + .error)
        end
    ' 2>/dev/null || true
  done | awk '
    {
      items = items (items ? "; " : "") $0
    }
    END { print items }
  ' 2>/dev/null)

  # Brownfield fallback: extract pre-existing issues from the legacy body section.
  # Only use this when the canonical frontmatter key is absent. If the key is
  # present as `pre_existing_issues: []`, that explicit empty array is the
  # authoritative "no known issues" signal and must suppress stale body text.
  if [ -z "$preex" ] && [ "$preex_key_present" != true ]; then
    preex=$(awk '
      /^## Pre-existing Issues/ { found=1; next }
      found && /^## / { exit }
      found && /^[[:space:]]*$/ { next }
      found && /^- / { line=$0; sub(/^- /, "", line); items = items (items ? "; " : "") line }
      END { print items }
    ' "$summary_file" 2>/dev/null)
  fi

  if [ -n "$devs" ]; then
    printf -v _dev_line 'DEVIATIONS (Plan %s): %s\n' "$plan_id" "$devs"
    DEV_ISSUES="${DEV_ISSUES}${_dev_line}"
  fi
  if [ -n "$preex" ]; then
    printf -v _preex_line 'PREEXISTING (Plan %s): %s\n' "$plan_id" "$preex"
    DEV_ISSUES="${DEV_ISSUES}${_preex_line}"
  fi
done
```

If `DEV_ISSUES` is non-empty, include it in the QA task description:
```
Dev-surfaced issues (include in VERIFICATION.md):
${DEV_ISSUES}
DEVIATIONS are plan violations: treat each as a FAIL check.
PREEXISTING items go in the "Pre-existing Issues" section of VERIFICATION.md.
```

**Phase known-issues persistence (before QA):**
After collecting Dev-surfaced pre-existing issues from SUMMARY.md files, persist them to phase state so a later QA session does not forget them:

```bash
bash "${VBW_PLUGIN_ROOT}/scripts/track-known-issues.sh" sync-summaries "{phase-dir}" 2>/dev/null || true
```

This writes `{phase-dir}/known-issues.json`. The human-readable `Discovered Issues` block later in the execute summary is supplemental: the JSON registry is the authoritative phase backlog. Unresolved issues that survive QA and remediation are auto-promoted to `STATE.md ## Todos` via `promote-todos`, making them visible in `/vbw:list-todos` and `/vbw:resume`.

If execution completed but the session ended before QA actually started, standalone/resumed phase-level QA entrypoints must rerun this `sync-summaries` backfill before the first `VERIFICATION.md` is written.

**Tier resolution:** When `validation_gates=true`: use `qa_tier` from gate policy resolved in Step 3.
When `validation_gates=false` (default): map effort to tier: turbo=skip (already handled), fast=quick, balanced=standard, thorough=deep. Override: if >15 requirements or last phase before ship, force Deep.

**Control Plane QA context:** If `${VBW_PLUGIN_ROOT}/scripts/control-plane.sh` exists:
  `bash "${VBW_PLUGIN_ROOT}/scripts/control-plane.sh" compile {phase} 0 0 --role=qa --phase-dir={phase-dir} 2>/dev/null || true`
Otherwise, fall through to direct compile-context.sh call below.

**Context compilation:** If `config_context_compiler=true`, before spawning QA run:
`bash "${VBW_PLUGIN_ROOT}/scripts/compile-context.sh" {phase} qa {phases_dir}`
This produces `{phase-dir}/.context-qa.md` with phase goal, success criteria, requirements to verify, and conventions.
If compilation fails, proceed without it.

Display: `◆ Spawning QA agent (${QA_MODEL})...`

Resolve the VERIFICATION filename before spawning QA:
```bash
VERIF_NAME=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" verification "{phase-dir}")
VERIF_BASE="${VERIF_NAME%.md}"
```

**Per-wave QA (Thorough/Balanced, QA_TIMING=per-wave):** After each wave completes, spawn QA concurrently with next wave's Dev work. QA receives only completed wave's PLAN.md + SUMMARY.md + "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol." Include the output path in the task description so QA persists directly: "Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {phase-dir}/${VERIF_BASE}-wave{W}.md. Plugin root: ${VBW_PLUGIN_ROOT}." After final wave, spawn integration QA covering all plans + cross-plan integration with output path `{phase-dir}/${VERIF_NAME}`. QA calls `write-verification.sh` directly: the orchestrator does NOT persist. If QA reports a `write-verification.sh` failure, surface the error to the user: do NOT fall back to manual VERIFICATION.md writes.

**Post-build QA (Fast, QA_TIMING=post-build):** Spawn QA after ALL plans complete. Include in task description: "Phase context: {phase-dir}/.context-qa.md (if compiled). Model: ${QA_MODEL}. Your verification tier is {tier}. If `.vbw-planning/codebase/META.md` exists, read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from `.vbw-planning/codebase/` to bootstrap codebase understanding before verifying. Run {5-10|15-25|30+} checks per the tier definitions in your agent protocol. Persist your VERIFICATION.md by piping qa_verdict JSON through write-verification.sh. Output path: {phase-dir}/${VERIF_NAME}. Plugin root: ${VBW_PLUGIN_ROOT}." QA calls `write-verification.sh` directly: the orchestrator does NOT persist. If QA reports a `write-verification.sh` failure, surface the error to the user: do NOT fall back to manual VERIFICATION.md writes.

**CRITICAL:** Set `subagent_type: "vbw:vbw-qa"` and `model: "${QA_MODEL}"` in the Agent tool invocation when spawning QA agents. If `QA_MAX_TURNS` is non-empty, also pass `maxTurns: ${QA_MAX_TURNS}`. If `QA_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited). If `QA_REASONING` is non-empty, also pass `effort: "${QA_REASONING}"`. If `QA_REASONING` is empty, do NOT include effort (the resolved model rejects the parameter).
**CRITICAL:** When true team mode is active, pass `team_name: "vbw-phase-{NN}"` and `name: "qa"` (or `name: "qa-wave{W}"` for per-wave QA) parameters to each QA Agent tool invocation.
