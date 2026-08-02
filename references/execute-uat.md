**Autonomy gate:**

| Autonomy | UAT active |
| -------- | ---------- |
| cautious | YES |
| standard | YES |
| confident | OFF |
| pure-vibe | OFF |

**Override:** If `auto_uat` is `true` in config, UAT is always active regardless of autonomy level.

Read autonomy and auto_uat from config:
```bash
AUTONOMY=$(jq -r '.autonomy // "standard"' .vbw-planning/config.json)
AUTO_UAT=$(jq -r '.auto_uat // false' .vbw-planning/config.json)
```

If `AUTO_UAT` is not `true` and autonomy is confident or pure-vibe: display "○ UAT verification skipped (autonomy: {level})" and proceed to Step 5.

**UAT execution:**

Resolve the UAT filename before proceeding:
```bash
UAT_NAME=$(bash "${VBW_PLUGIN_ROOT}/scripts/resolve-artifact-path.sh" uat "{phase-dir}")
```

1. Check if `{phase-dir}/${UAT_NAME}` already exists with `status: complete`. If so: "○ UAT already complete" and proceed to Step 5.
2. Generate test scenarios from the compiled UAT verification context:
  ```bash
  UAT_VERIFY_CONTEXT=$(bash "${VBW_PLUGIN_ROOT}/scripts/compile-verify-context-for-uat.sh" "{phase-dir}" 2>/dev/null || true)
  ```
  Treat this compact context as the authoritative UAT input. It includes merged PLAN/SUMMARY details, remediation scope, the correct `uat_path`, and any unsuppressed `SUMMARY_DEVIATION:` records. Do not independently re-read individual SUMMARY.md files to build UAT scope.
  - Parse `verify_scope=full` vs `verify_scope=remediation round=RR` from the compiled context.
  - Parse `uat_path=` and write the UAT file there. For full scope this is usually `${UAT_NAME}`. for remediation it is the round-scoped UAT path.
  - Parse each `SUMMARY_DEVIATION:` record (`signature`, `source_plan`, `source_path`, `text`). These records are already filtered against `{phase-dir}/remediation/uat/accepted-deviations.json`. do not re-prefill accepted records.

  **Summary deviation review prefill (NON-NEGOTIABLE):** Before generated plan checkpoints, create one `D{NN}` review checkpoint for each `SUMMARY_DEVIATION:` record, in the same stable order.
  - These are review checkpoints, not blocking issues. Start `**Result:**` empty and leave `issues: 0` in the initial frontmatter unless the human later rejects a deviation.
  - Write them before any generated `P...` or `PR...` checkpoints.
  - Include identity metadata exactly in the entry: `**Source:** Summary deviation review`, `**Deviation Signature:** {signature}`, `**Source Plan:** {source_plan}`, `**Source Summary:** {source_path}`, and `**Deviation:** {text}`.
  - Use `**Expected:** Human confirms whether this documented deviation is acceptable for this phase.`
  - Include the `D{NN}` entries in `total_tests`. they remain incomplete until the human answers.

  Generate plan/remediation scenarios from the compiled context:
  - Use each context record's built work, files modified, and must_haves
   - Generate 1-3 test scenarios per plan requiring HUMAN judgment: things only a person can verify
   - Minimum 1 test per plan. Test IDs: `P{plan}-T{NN}`
  - In remediation re-verification mode, use remediation checkpoint IDs `PR{RR}-T{NN}` (for example, `PR03-T01`) and focus on whether the original UAT issue was fixed.

   **UAT tests must require human judgment.** Good examples:
   - Open the app and navigate to screen X: does it display Y correctly?
   - Perform user workflow A → B → C: does the result look right?
   - Check that the UI reflects the change: is the label/value/layout correct?

   **NEVER generate tests that can be performed programmatically.** These belong in QA (Step 4), not UAT:
   - ✗ Grep/search files for expected content or missing imports
   - ✗ Verify file existence, deletion, or structure
   - ✗ Run a test suite or individual test (xcodebuild test, pytest, bats, jest, etc.)
   - ✗ Run a CLI command and check its exit code or output
   - ✗ Execute a script and verify it passes
   - ✗ Run a linter, type-checker, or build command

   **What belongs in UAT (ask the user):**
   - Visual/UI correctness
   - Domain-specific data validation
   - UX flows and usability
   - Behavior that requires the running app or hardware
   - Subjective quality

   **What does NOT belong in UAT (the agent or QA already handles these):**
   - Running test suites: QA runs these during execution. Do NOT ask the user to run tests.
   - Checking command output, exit codes, or build success
   - Grepping files for expected content
   - Verifying file existence or structure
   - Any check that can be performed programmatically via Bash, Grep, or Glob

   **Skill-aware exclusion:** If any active skill, tool, or MCP server gives the model UI automation capabilities (e.g., describe-UI, tap/click simulation, accessibility inspection, screenshot capture, DOM querying), then UI interactions that can be verified programmatically via those capabilities also belong in QA, not UAT. Only include scenarios that require true human judgment: subjective quality, visual design assessment, domain-specific data correctness, or hardware-dependent behavior that available tooling cannot automate.

   If a plan's work is purely internal (refactor, test infrastructure, script changes) with no user-facing behavior, generate a single lightweight checkpoint asking the user to confirm the app still works as expected from their perspective, rather than asking them to run automated checks.

  - Write initial UAT file at `{phase-dir}/{uat_path}` with all tests (prefilled `D{NN}` review checkpoints first, then generated `P...` or `PR...` checkpoints. all Result fields empty)
3. **CHECKPOINT loop: present ONE test at a time, wait for user response:**

   **This is a conversational loop. Do NOT present all tests at once. Do NOT end the session after presenting a test. Do NOT proceed to Step 5 until all tests are complete.**

   For the FIRST test without a result, display a CHECKPOINT followed by AskUserQuestion:

    ```text
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    CHECKPOINT {NN}/{total}: {plan-id}: {plan-title}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    {scenario description}
    ```

    Then use AskUserQuestion. Keep the modal question self-contained because it may cover the surrounding checkpoint prose:

    ```yaml
    question: "Scenario: {scenario description}\n\nExpected: {expected result}\n\nDoes the behavior match this checkpoint?"
    header: "UAT"
    multiSelect: false
    options:
      - label: "Pass"
        description: "Behavior matches expected result"
      - label: "Skip"
        description: "Cannot test right now: skip this checkpoint"
    ```

   The tool automatically provides a freeform "Other" option for the user to describe issues.

  **Summary-deviation checkpoint prompt:** If the current checkpoint is a prefilled `D{NN}` summary-deviation review, show the deviation text and source metadata instead of a product scenario.
  - The CHECKPOINT display must be self-contained: include a compact `Deviation: {text}` line from the entry's `**Deviation:**` field and `Source: {source_path} ({source_plan})` from `**Source Summary:**` and `**Source Plan:**`. Include `Deviation Signature: {signature}` only when it helps distinguish similar deviations.
  - The AskUserQuestion `question` value MUST also be self-contained. Include the same compact `Deviation: {text}` and `Source: {source_path} ({source_plan})` lines in the tool question, then ask: `Accept this documented deviation as non-blocking for this phase?`
  - The generic artifact expectation, `Expected: Human confirms whether this documented deviation is acceptable for this phase.`, is not enough by itself. It must not be the only visible AskUserQuestion question for a prefilled `D{NN}` summary-deviation checkpoint.
  - Use three visible option labels for this checkpoint type only:
    - `Pass` → `Accept this deviation as non-blocking for this phase`
    - `Track Todo` → `Accept this deviation and add a VBW todo`
    - `Skip` → `Leave this deviation unaccepted for now`
  - This stays within the AskUserQuestion four-option limit. Normal product checkpoints keep only `Pass` and `Skip`.
  - Freeform/Other → record the response as a UAT issue if it explains why the deviation is unacceptable or reveals a product defect, except for high-confidence todo intent handled below.

   **STOP HERE.** Wait for the AskUserQuestion response. Do NOT continue to the next test or to Step 5.

   **After the user responds:**

   Map the AskUserQuestion response:

  - **"Pass" selected:** record pass. For a prefilled summary-deviation `D{NN}` checkpoint, also write `**Disposition:** accepted-process-exception` and preserve its deviation metadata. Plain `Pass` accepts the deviation without adding a todo.
  - **"Track Todo" selected:** for a prefilled summary-deviation `D{NN}` checkpoint only, record `**Result:** pass`, write `**Disposition:** accepted-process-exception`, preserve deviation metadata, and mark the checkpoint as accepted-and-tracked for the persistence step. Do not introduce a new `Result` value.
  - **"Skip" selected:** record skip. For a prefilled summary-deviation `D{NN}` checkpoint, also write `**Disposition:** skipped-by-user` and do not record acceptance.
  - **Freeform text (via "Other"):** Apply case-insensitive, trimmed string matching:
    - For a prefilled summary-deviation `D{NN}` checkpoint, normalize before intent matching: trim, lowercase, treat curly apostrophes as straight apostrophes (`can’t` == `can't`), treat em/en dashes as separators, and canonicalize contractions (`can't`/`cant` → `cannot`, `don't`/`dont` → `do not`, `won't`/`wont` → `will not`). Then apply marker-first ordering: explicit rejection/blocking/acceptance-refusal markers (`unacceptable`, `reject`, `blocking`, `blocker`, `do not continue`, `cannot continue`, `will not continue`, `do not proceed`, `cannot proceed`, `not ok`, `not okay`, `cannot accept`, `do not accept`, `will not accept`, `unable to accept`, `refuse to accept`, `not acceptable`) record `Result: issue` and `Disposition: rejected-by-user` even when todo words are also present. `not ok` and `not okay` are equivalent because `ok` and `okay` are equivalent pass-intent words elsewhere. Examples: `can't continue, track this` and `can’t continue, track this` both canonicalize to `cannot continue, track this`. `not ok, track this` remains rejected. `can't accept this, track this` and `can’t accept this, track this` both canonicalize to `cannot accept this, track this`. and `not acceptable, add to todo` remains a rejected UAT issue. Only otherwise should high-confidence todo intent (`/vbw:todo`, `todo`, `to-do`, `add to todo`, `add to to-do`, `track this`, `track it`, `backlog`, or `follow up later`) map to the accepted-and-tracked path.
     - **Skip words** (skip, skipped, next, n/a, na, later, defer): record skip
     - **Anything else**: classify the response as an issue, synthesize the persisted `Description` using the issue capture rules below, and infer severity from keywords (crash/broken/error=critical, wrong/missing/bug=major, minor/cosmetic/nitpick=minor, default=major). For a prefilled summary-deviation `D{NN}` checkpoint, also write `**Disposition:** rejected-by-user`.
   - **Issue description capture:** Whenever a response is recorded as an issue, synthesize an actionable persisted `Description` from the checkpoint expectation, the current user response, and any visible attachment/image content available in the current conversation turn.
     - Correct typos, remove filler/hedging, preserve user intent, identify the violated expectation, and state the observed actual behavior.
     - If the user includes or references an image/attachment and the content is visible and interpretable, inspect it immediately and fold relevant facts into durable text in `Description`.
     - If an image/attachment is not visible or not interpretable, do not persist `image attached`, `(Image attached)`, `screenshot attached`, `attachment attached`, or similar placeholders as evidence. Record the limitation only if it matters to remediation.
     - Never persist raw screenshots, raw attachment blobs, or base64 data in the UAT artifact.
     - Do not add a required raw-response field. keep the existing `Description` and `Severity` issue shape for downstream extraction.
     - Do not invent facts that are not present in the checkpoint, user response, or visible attachment/image evidence.
     - Preserve the human-only UAT boundary: synthesize issue text only from current UAT evidence. do not debug, inspect project files, run commands, or implement fixes during UAT capture.
   - If a pass/skip response includes a separate defect observation unrelated to the current checkpoint, append it as a discovered UAT issue. Before choosing the ID, scan the current UAT file at `{phase-dir}/{uat_path}` in both initial and resumed sessions for existing `D[0-9]+` headings, including prefilled summary-deviation review entries and issues appended earlier in the same session. allocate highest existing + 1 (`D03` after prefilled `D01`/`D02`) and never renumber existing entries.
   - Update `{phase-dir}/{uat_path}` immediately (persist to disk)
  - If the response accepts and tracks a prefilled summary-deviation checkpoint (`Track Todo` or high-confidence todo-intent freeform), run `bash "${VBW_PLUGIN_ROOT}/scripts/track-uat-deviations.sh" todo-from-uat "{phase-dir}" "{phase-dir}/{uat_path}" "{test-id}"` after writing the UAT file. Use only the helper-emitted `todo_ref` to write or update `**Tracking:** accepted deviation added to todos (ref:{todo_ref})` or `**Tracking:** accepted deviation already tracked in todos (ref:{todo_ref})`. If the helper reports `no_state_file`, `missing_metadata`, `not_accepted`, empty output, or any other failure status, keep the UAT `Result: pass` and write `**Tracking:** accepted deviation todo tracking unavailable ({status})` rather than claiming a todo was added.
  - If the response accepts a prefilled summary-deviation checkpoint, run `bash "${VBW_PLUGIN_ROOT}/scripts/track-uat-deviations.sh" record-from-uat "{phase-dir}" "{phase-dir}/{uat_path}"` after any todo tracking update. The helper is idempotent. never hand-edit `accepted-deviations.json`.
   - Display progress: `✓ {completed}/{total} tests`
   - If more tests remain: present the NEXT test using the same CHECKPOINT format with AskUserQuestion, then **STOP and wait again**
   - If all tests done: go to step 4

4. After all tests complete:
   - Update UAT.md frontmatter (status, completed date, final counts)
  - Run `bash "${VBW_PLUGIN_ROOT}/scripts/track-uat-deviations.sh" record-from-uat "{phase-dir}" "{phase-dir}/{uat_path}"` after finalization so accepted summary-deviation signatures are available to suppress future duplicate prefill.
   - If no issues: proceed to Step 5
   - If issues found: display issue summary, suggest `/vbw:fix`, STOP (do not proceed to Step 5)

**Inline execution (NON-NEGOTIABLE):** The orchestrator runs the CHECKPOINT loop directly in the main conversation: this is NOT a subagent operation. Do NOT spawn a QA agent, Dev agent, or any subagent for UAT. Do NOT use TaskCreate to delegate UAT. The AskUserQuestion tool is only available to the orchestrator: subagents cannot interact with the user, so delegating UAT to a subagent bypasses user input entirely. The orchestrator must wait for user input at each checkpoint.
