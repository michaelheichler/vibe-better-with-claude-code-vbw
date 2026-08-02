**Guard:** Initialized. Requires phase number.
Missing number: STOP "Usage: `/vbw:vibe --remove <phase-number>`"
Not found: STOP "Phase {NN} not found."
Has work (PLAN.md or SUMMARY.md): STOP "Phase {NN} has artifacts. Remove plans first."
Completed ([x] in roadmap): STOP "Cannot remove completed Phase {NN}."

**Steps:**
1. Parse args: extract phase number, validate, look up name/slug.
2. Confirm: display phase details, ask confirmation. Not confirmed -> STOP.
3. Remove dir: `rm -rf .vbw-planning/phases/{NN}-{slug}/`
4. Renumber FORWARD: for each phase > removed: rename dir {NN} -> {NN-1}, rename internal files, update frontmatter, update depends_on.
5. Update ROADMAP.md: remove phase entry + details, renumber subsequent, update deps, update progress table.
6. If `.vbw-planning/CONTEXT.md` exists, rewrite it to reflect the updated milestone decomposition (phase count/grouping, ordering, scope coverage, and requirement mapping). Preserve project-level key decisions and deferred ideas where still valid.
7. Update STATE.md phase total: `bash /tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/update-phase-total.sh .vbw-planning --removed {NN}` (where {NN} is the removed phase number from step 1).
8. **Phase mutation commit boundary (conditional):**
   ```bash
  PG_SCRIPT="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}/scripts/planning-git.sh"
   if [ -f "$PG_SCRIPT" ]; then
     bash "$PG_SCRIPT" commit-boundary "remove phase {NN}" .vbw-planning/config.json
   else
     echo "⚠ VBW: planning-git.sh unavailable. Skipping planning git boundary commit." >&2
   fi
   ```
   Behavior: `planning_tracking=commit` commits `.vbw-planning/` if changed. Other modes no-op.
9. Present: Phase Banner with renumber count, phase changes, file checklist, Next Up.
