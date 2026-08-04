---
name: vbw:map
category: advanced
disable-model-invocation: true
description: Analyze existing codebase with adaptive Scout teammates to produce structured mapping documents.
argument-hint: [--incremental] [--package=name] [--tier=solo|duo|quad]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, WebFetch, Agent, TaskCreate, SendMessage, Skill, LSP
---

# VBW Map: $ARGUMENTS

## Context

Working directory:
```
!`pwd`
```
Plugin root:
```
!`L="/tmp/.vbw-plugin-root-link-${CLAUDE_SESSION_ID:-default}"; R="$L/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || R="${CLAUDE_PLUGIN_ROOT:-}/scripts/resolve-plugin-root.sh"; [ -f "$R" ] || { echo "VBW: plugin root unavailable. Restart this session to recreate $L." >&2; exit 1; }; bash "$R" >/dev/null || exit 1; echo "$L"`
```

Store the plugin root path output above as `{plugin-root}` for use in script invocations below. Replace `{plugin-root}` with the literal `Plugin root` value from Context whenever a step below references a script or reference file.

@${CLAUDE_PLUGIN_ROOT}/references/subagent-contracts.md

Existing mapping:
```text
!`ls .vbw-planning/codebase/ 2>/dev/null || echo "No codebase mapping found"`
```
META.md:
```
!`cat .vbw-planning/codebase/META.md 2>/dev/null || echo "No META.md found"`
```
Project files:
```text
!`ls package.json pyproject.toml Cargo.toml go.mod Gemfile build.gradle pom.xml 2>/dev/null || echo "No standard project files found"`
```
Git HEAD:
```text
!`git rev-parse HEAD 2>/dev/null || echo "no-git"`
```
Agent Teams:
```text
!`echo "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-0}"`
```

## Guard

1. **Not initialized** (no .vbw-planning/ dir): STOP "Run /vbw:init first."
2. **No git:** WARN "Not a git repo, incremental mapping disabled." Continue in full mode.
3. **Empty project:** No source files → STOP: "No source code found to map."

## Steps

### Step 1: Parse arguments and detect mode

- **--incremental**: force incremental refresh
- **--package=name**: scope to single monorepo package
- **--tier=solo|duo|quad**: force specific tier (overrides auto-detection)

**Mode detection:** If META.md exists + git repo: compare `git_hash` to HEAD. <20% files changed = incremental, else full. No META.md or no git = full. Store MAPPING_MODE and CHANGED_FILES.

### Step 1.5: Size codebase and select tier

Count source files (Glob), excluding: .vbw-planning/, node_modules/, .git/, vendor/, dist/, build/, target/, .next/, __pycache__/, .venv/, coverage/. If --package, scope to that dir. Store SOURCE_FILE_COUNT.

| Tier | Files | Strategy | Scouts |
|------|-------|----------|--------|
| solo | <200 | Orchestrator maps inline | 0 |
| duo | 200-1000 | 2 scouts, combined domains | 2 |
| quad | 1000+ | Full 4-scout team | 4 |

Overrides: --tier flag forces tier. Agent Teams not enabled → force solo (`⚠ Agent Teams not enabled , using solo mode`). `prefer_teams='never'` in config → force solo (`⚠ prefer_teams=never , using solo mode`).
Display: `◆ Sizing: {SOURCE_FILE_COUNT} source files → {tier} mode`

Read `prefer_teams` before applying tier:
```bash
PREFER_TEAMS=$(bash "{plugin-root}/scripts/normalize-prefer-teams.sh" .vbw-planning/config.json 2>/dev/null || echo "auto")
```
If `PREFER_TEAMS` is `never`, force solo regardless of file count or --tier flag.

### Step 2: Detect monorepo

**JS/Node patterns:** Check lerna.json, pnpm-workspace.yaml, packages/ or apps/ with sub-package.json, root workspaces field.

**Multi-component detection:** Count distinct build system roots at different paths. Build system markers: package.json, Cargo.toml, go.mod, pyproject.toml, build.gradle, pom.xml, *.xcodeproj, Podfile, pubspec.yaml. If 2+ markers found at different directory levels (not just root), treat as monorepo.

If monorepo + --package: scope to that package.

### Map Document Format

Every map writer MUST use the exact level-two headings and entry shapes below for the documents it owns. Additional sections are allowed. Do not rename the required headings.

**STACK.md:**
```markdown
# Stack

## Purpose

{First non-empty paragraph describing the product purpose.}

## Languages

| Language | Evidence |
| --- | --- |
| {Language} | {Files or tooling that establish its use} |

## Key Technologies

- **{Technology}**: {Role and evidence}
```

**ARCHITECTURE.md:**
```markdown
# Architecture

## Overview

{First non-empty paragraph summarizing the architecture.}
```

**INDEX.md:**
```markdown
# Codebase Map Index

## Cross-Cutting Themes

- **{Theme}**: {Description}
```

**META.md:**
```yaml
# Codebase Map META

mapped_at: {UTC ISO 8601 timestamp}
git_hash: {Full git HEAD hash or no-git}
file_count: {Positive SOURCE_FILE_COUNT integer}
mode: {full or incremental}
monorepo: {true or false}
mapping_tier: {solo, duo, or quad}
mcp_tools_used: {Comma-separated tool names or none}
documents:
  - STACK.md
  - DEPENDENCIES.md
  - ARCHITECTURE.md
  - STRUCTURE.md
  - CONVENTIONS.md
  - TESTING.md
  - CONCERNS.md
  - INDEX.md
  - PATTERNS.md
```

The top-level META keys MUST begin at column one. Do not prefix them with list markers. `## Purpose` is the canonical purpose heading for new maps. The other map documents may use headings suited to their domains.

### Step 3: Execute mapping (tier-branched)

**Step 3-solo:** Orchestrator analyzes each domain sequentially and writes to `.vbw-planning/codebase/`. Follow the Map Document Format contract above for every document.

- Domain 1 (Tech Stack): STACK.md + DEPENDENCIES.md
- Domain 2 (Architecture): ARCHITECTURE.md + STRUCTURE.md
- Domain 3 (Quality): CONVENTIONS.md + TESTING.md
- Domain 4 (Concerns): CONCERNS.md

Display ✓ per domain. After all 7 docs written, skip Step 3.5, go to Step 4.

---

**Step 3-duo:** **Pre-spawn stale-team cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Agent teams are experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1). The team forms when the first teammate is spawned via the Agent tool. There is no TeamCreate setup step. Spawn the team (`description="Codebase Map (duo)"`) with 2 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.** Do not pass `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir` on any TaskCreate.

Scout A (Tech + Architecture): analyze tech stack, deps, architecture, structure. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/STACK.md
.vbw-planning/codebase/DEPENDENCIES.md
.vbw-planning/codebase/ARCHITECTURE.md
.vbw-planning/codebase/STRUCTURE.md
</output_paths>
Read `{plugin-root}/commands/map.md` and follow its Map Document Format contract for every output file.
```
Mode: {MAPPING_MODE}. After writing all 4 files, send a `scout_findings` message (domain: "tech-and-architecture") with `cross_cutting` findings only (file contents already written). Schema ref: `{plugin-root}/references/handoff-schemas.md`

Scout B (Quality + Concerns): analyze quality, conventions, testing, debt, risks. Write findings directly to the output paths. Include in prompt:
```
<output_paths>
.vbw-planning/codebase/CONVENTIONS.md
.vbw-planning/codebase/TESTING.md
.vbw-planning/codebase/CONCERNS.md
</output_paths>
Read `{plugin-root}/commands/map.md` and follow its Map Document Format contract for every output file.
```
Mode: {MAPPING_MODE}. After writing all 3 files, send a `scout_findings` message (domain: "quality-and-concerns") with `cross_cutting` findings only. Schema ref: `{plugin-root}/references/handoff-schemas.md`

**Scout model (effort-gated):** Fast/Turbo: `Model: haiku`. Thorough/Balanced: inherit session model.
**Scout turn budget (effort-gated):** Resolve with `bash "{plugin-root}/scripts/resolve-agent-max-turns.sh" scout .vbw-planning/config.json "{effort}"`. If `SCOUT_MAX_TURNS` is non-empty, pass `maxTurns: ${SCOUT_MAX_TURNS}` to each Scout TaskCreate. If `SCOUT_MAX_TURNS` is empty, do NOT include maxTurns (omitting it = unlimited).
**Skill pre-evaluation:** Before composing Scout task descriptions, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for codebase mapping, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context. Do not select only the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected, {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references.

If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning each duo-mode Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block.

Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.

**MCP tools:** If code-analysis MCP tools are available (architecture extraction, dependency graphs, call hierarchy, symbol search), note the specific tools in each Scout's task prompt so Scouts can use them with Glob/Read/Grep.

Wait for all findings. Proceed to Step 3.5.

---

**Step 3-quad:** **Pre-spawn stale-team cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Agent teams are experimental (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1). The team forms when the first teammate is spawned via the Agent tool. There is no TeamCreate setup step. Spawn the team (`description="Codebase Map (quad)"`) with 4 Scouts via TaskCreate. **Set `subagent_type: "vbw:vbw-scout"` on each Scout TaskCreate.** Do not pass `isolation`, `cwd`, `working_dir`, `workingDirectory`, or `workdir` on any TaskCreate. Each Scout writes its domain files directly via `<output_paths>`, then sends a `scout_findings` message with `cross_cutting` findings only (file contents already written). Schema ref: `{plugin-root}/references/handoff-schemas.md`
- Scout 1 (Tech Stack): `<output_paths>` = `.vbw-planning/codebase/STACK.md`, `.vbw-planning/codebase/DEPENDENCIES.md`. Include this sentence in the payload: "Read {plugin-root}/commands/map.md and follow its Map Document Format contract for every output file."
- Scout 2 (Architecture): `<output_paths>` = `.vbw-planning/codebase/ARCHITECTURE.md`, `.vbw-planning/codebase/STRUCTURE.md`. Include this sentence in the payload: "Read {plugin-root}/commands/map.md and follow its Map Document Format contract for every output file."
- Scout 3 (Quality): `<output_paths>` = `.vbw-planning/codebase/CONVENTIONS.md`, `.vbw-planning/codebase/TESTING.md`. Include this sentence in the payload: "Read {plugin-root}/commands/map.md and follow its Map Document Format contract for every output file."
- Scout 4 (Concerns): `<output_paths>` = `.vbw-planning/codebase/CONCERNS.md`. Include this sentence in the payload: "Read {plugin-root}/commands/map.md and follow its Map Document Format contract for every output file."

Security: PreToolUse hook handles enforcement. **Scout model:** same as duo. **Scout turn budget:** same as duo (pass `maxTurns: ${SCOUT_MAX_TURNS}` when non-empty, omit when empty). **Skill pre-evaluation:** Before composing Scout task descriptions, evaluate installed skills visible in your system context. Read each skill's description and select all materially helpful installed skills for codebase mapping, including adjacent/supporting domain skills surfaced by the prompt, logs, error text, related files, or stack context. Do not select only the single most direct skill. The spawned prompt MUST begin with exactly one explicit skill outcome block: use `<skill_activation>{For each selected skill: "Call Skill({skill-name})"}</skill_activation>` when one or more installed skills are preselected at orchestration time, or `<skill_no_activation>Evaluated installed skills for this task. No skills were preselected at orchestration time. Reason: {brief task-specific reason}.</skill_no_activation>` when none are preselected. Silent omission of both blocks is invalid. After evaluating, state the skill outcome in your response (e.g., "Skills: activating {skill-name}" or "Skills: none preselected, {reason}") so the user has visibility before the agent is spawned. Example: if the prompt or error mentions SwiftData, include `swiftdata` alongside relevant test/build/debug skills. After calling `Skill(...)`, if the loaded skill's instructions reference additional files, sibling docs, or follow-up read steps relevant to the active task, read those specific files before reasoning or acting. Do not scan entire skill folders or read unrelated references. If one or more skills were preselected, run `bash "{plugin-root}/scripts/extract-skill-follow-up-files.sh" "{all preselected skill names from the activation block}" 2>/dev/null || true` before spawning each quad-mode Scout. If the helper prints a `<skill_follow_up_files>` block, paste it immediately after the follow-up-read sentence in the spawned payload. Otherwise omit that block. **MCP tools:** If code-analysis MCP tools are available (architecture extraction, dependency graphs, call hierarchy, symbol search), note the specific tools in each Scout's task prompt so Scouts can use them with Glob/Read/Grep.

Render the prompt prefix from `{plugin-root}/references/skill-activation-payload.md` with the local `skill_calls`, task-specific `no_skill_reason`, and optional helper-emitted `follow_up_files_block`. Prepend the rendered bytes to the child prompt so the rendered skill outcome tag is its first line. Do not paste the template path, variables, or an unresolved `@` include into the child prompt.

**Scout communication (effort-gated):**

| Effort | Messages |
|--------|----------|
| Thorough | Cross-cutting findings + contradiction flags for INDEX.md Validation Notes |
| Balanced | Cross-cutting findings only |
| Fast | Blockers only |

Use targeted `message` not `broadcast`. Wait for all findings. Display ✓ per scout.

### Step 3.5: Verify mapping documents written by Scouts

**Skip if solo** (docs already written). Scouts wrote files directly via `<output_paths>`. Verify all 7 docs exist in `.vbw-planning/codebase/`: STACK.md, DEPENDENCIES.md, ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, CONCERNS.md. If any are missing, log `⚠ Missing: {filename}` and write a placeholder from the `scout_findings` message content (fall back to cross_cutting text). Use `cross_cutting` findings from scout_findings messages for INDEX.md Validation Notes in Step 4.

### Step 4: Synthesize INDEX.md and PATTERNS.md

Read all 7 docs. Follow the Map Document Format contract above when writing INDEX.md. Produce:
- **INDEX.md:** Cross-referenced index with key findings + "Validation Notes" for contradictions
- **PATTERNS.md:** Recurring patterns: architectural, naming, quality, concern, dependency

### Step 5: Create META.md and present summary

**HARD GATE. Shutdown before presenting results:** Solo mode has no team and skips shutdown. Duo and Quad modes follow the team-shutdown contract in `references/subagent-contracts.md`, including its orchestrator retry procedure for plain-text replies and rejected responses.

Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.

Run **Post-shutdown residual cleanup:** `bash "{plugin-root}/scripts/clean-stale-teams.sh" 2>/dev/null || true`. Verify that shutdown leaves ZERO active teammates. If teardown stalls, advise the user to run `/vbw:doctor --cleanup`. Only then proceed to META.md and user output. Failure to shut down leaves agents running and consuming API credits.

Write META.md from the exact META.md template in the Map Document Format contract. Keep every top-level key unbulleted and at column one.

Display per @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md: Phase Banner (Codebase Mapped, Mode, Tier), ✓ per document, Key Findings (◆), Next Up block.

## Output Format

Follow @${CLAUDE_PLUGIN_ROOT}/references/vbw-brand-essentials.md
Use a Phase Banner (double-line box), File Checklist (✓), ◆ for findings, ⚠ for warnings, Next Up Block, and no ANSI.
