**Guard:** Initialized, roadmap exists.
No roadmap: STOP "No milestones configured. Run `/vbw:vibe` to bootstrap."
No work (no SUMMARY.md files): STOP "Nothing to ship."

**Hard UAT gate (always, non-bypassable):**
Before any audit/bypass handling, run:
```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/archive-uat-guard.sh
```
If exit code is 2: STOP. Unresolved UAT (active or milestone) blocks archive regardless of `--skip-audit` or `--force`.

**Hard state-consistency gate (always, non-bypassable):**
After the UAT gate passes, run:
```bash
bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/verify-state-consistency.sh .vbw-planning --mode archive
```
If exit code is non-zero: STOP. If exit code is 2, state misalignment at archive means the archived milestone record may be unreliable. Phase counts, completion markers, or project metadata could be inconsistent. Surface the JSON output's `failed_checks` array so the user can fix the drift before retrying. For any other non-zero exit, treat the verifier as failed unexpectedly and do not proceed with archive.

**Pre-gate audit (unless --skip-audit or --force):**
Run 7-point audit matrix:
1. Roadmap completeness: every phase has real goal (not TBD/empty)
2. Phase planning: every phase has >= 1 PLAN.md
3. Plan execution: every PLAN.md has SUMMARY.md
4. Execution status: every SUMMARY.md has `status: complete`
5. Verification: authoritative QA verification exists and is fresh PASS. Missing=WARN, failed=FAIL. After QA remediation reaches `done`, the authoritative artifact is the round-scoped `R{RR}-VERIFICATION.md`. The frozen phase-level VERIFICATION.md must not be reused.
6. UAT status: any `*-UAT.md` with `status: issues_found` = FAIL. Unresolved UAT issues must be remediated before archiving.
7. Requirements coverage: req IDs in roadmap exist in REQUIREMENTS.md
FAIL -> STOP with remediation suggestions. WARN -> proceed with warnings.

**Steps:**
1. **Derive milestone slug deterministically (do NOT invent a slug):**
   ```bash
   MILESTONE_SLUG=$(bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/derive-milestone-slug.sh .vbw-planning)
   ```
  This reads ROADMAP.md phase names and outputs a numbered kebab-case slug (e.g., `01-setup-api-layer`). Keep this milestone slug separate from any custom git tag passed via `--tag`. **Never use a hardcoded slug like "default". Always use the script output.**
2. Parse args: --tag=vN.N.N (custom tag), --no-tag (skip), --force (skip non-UAT audit).
3. Compute summary: from ROADMAP (phases), SUMMARY.md files (tasks/commits/deviations), REQUIREMENTS.md (satisfied count).
4. **Rolling summary (conditional):** If `rolling_summary=true` in config:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/compile-rolling-summary.sh \
     .vbw-planning/phases .vbw-planning/ROLLING-CONTEXT.md 2>/dev/null || true
   ```
   Compiles final rolling context before artifacts move to milestones/. Fail-open.
   When `rolling_summary=false`: skip.
5. Archive: `mkdir -p .vbw-planning/milestones/{SLUG}`. Move ROADMAP.md, STATE.md, and phases/ to milestones/{SLUG}/. If `.vbw-planning/CONTEXT.md` exists, move it to milestones/{SLUG}/CONTEXT.md. Use the **Write** tool (not Bash) to create `.vbw-planning/milestones/{SLUG}/SHIPPED.md`. This ensures PostToolUse hooks fire for artifact tracking. Delete stale RESUME.md.
5b. **Persist project-level state:** After archiving, run:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/persist-state-after-ship.sh \
     .vbw-planning/milestones/{SLUG}/STATE.md .vbw-planning/STATE.md "{PROJECT_NAME}"
   ```
   This extracts project-level sections (Todos, Decisions, Blockers, Codebase Profile) from the archived STATE.md and writes a fresh root STATE.md. Milestone-specific sections (Current Phase, Activity Log, Phase Status) stay in the archive only. Fail-open: if the script fails, warn but continue.
6. Planning commit boundary (conditional):
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "archive milestone {SLUG}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Run this BEFORE branch merge/tag so shipped planning state is committed.
7. Git branch merge: if `milestone/{SLUG}` branch exists, merge --no-ff. Conflict -> abort, warn. No branch -> skip.
8. Git tag: unless --no-tag, `git tag -a {tag} -m "Shipped milestone: {name}"`. Default: `milestone/{SLUG}`.
9. Regenerate CLAUDE.md: update Active Context, remove shipped refs. Preserve non-VBW content. Only replace VBW-managed sections, and keep the user's own sections intact.
9b. Post-archive hook (non-blocking): after successful archive completion, run:
   ```bash
   bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/post-archive-hook.sh "{SLUG}" ".vbw-planning/milestones/{SLUG}" "{tag}" .vbw-planning/config.json
   ```
   Use the tag selected in step 8, or an empty third argument when `--no-tag` was used. Repos without `hooks.post_archive` configured no-op through the dispatcher. Any warnings are non-blocking.
10. Present: Phase Banner with metrics (phases, tasks, commits, requirements, deviations), archive path, tag, branch status, memory status. Run `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/suggest-next.sh vibe`.
