# Configuration Reference

Reference for the config files under `config/` that drive VBW's per-project settings, model routing, stack detection, token budgets, rollout gating, LSP mapping, and the destructive-command guard.

## config/defaults.json

Seed values for `.vbw-planning/config.json`, created by `/vbw:init` and backfilled by `/vbw:config`'s migration step (`scripts/migrate-config.sh`) whenever new keys are added. It currently has 44 top-level keys. The full settings table (type, allowed values, and default) lives in `commands/config.md` under "Settings Reference" (44 rows, one per key) and is not duplicated here to avoid drift. View it live with `/vbw:config`.

Notable groups:
- **Core workflow**: `effort` (thorough/balanced/fast/turbo), `autonomy` (cautious/standard/confident/pure-vibe), `planning_tracking` (manual/ignore/commit), `auto_push` (never/after_phase/always), `verification_tier` (quick/standard/deep).
- **Model routing**: `model_profile` (quality/balanced/budget, default `quality`), `model_overrides` (per-agent map, default `{}`), `active_profile` / `custom_profiles` for saved setting bundles.
- **Agent turn budgets**: `agent_max_turns`, an object keyed by 6 agent roles (`scout`, `qa`, `architect`, `debugger`, `lead`, `dev`), with defaults `scout=15, qa=25, architect=30, debugger=80, lead=50, dev=75`. The `docs` agent has no entry here. It is excluded from QA verification by default via `qa_skip_agents: ["docs"]`. Values scale by effort level (thorough 1.5x, balanced 1x, fast 0.8x, turbo 0.6x), and a value of `false` or `0` means unlimited turns (see `scripts/resolve-agent-max-turns.sh`).
- **Rollout-managed flags**: `metrics`, `token_budgets`, `two_phase_completion`, `rolling_summary`, `validation_gates`, `smart_routing`, `snapshot_resume`, `event_recovery`, `monorepo_routing`, `lease_locks`. See [Rollout Stages](#rollout-stages-configrollout-stagesjson) below.
- **Statusline**: four `statusline_*` booleans, all default `false`, documented in `commands/config.md`.
- **Caveman mode**: `caveman_style` (none/lite/full/ultra/auto, default `none`), `caveman_commit`, `caveman_review` (both boolean, default `false`).

Legacy `v2_*`/`v3_*` prefixed keys from older configs are auto-migrated away by `migrate-config.sh`. That infrastructure has graduated to always-on behavior and no longer appears as a toggle.

## Model Profiles (config/model-profiles.json)

Three presets, each mapping the 7 agent roles (`lead`, `dev`, `qa`, `scout`, `debugger`, `architect`, `docs`) to a Claude model tier:

| Agent | Quality | Balanced | Budget |
| ----- | ------- | -------- | ------ |
| lead | opus | sonnet | sonnet |
| dev | opus | sonnet | sonnet |
| qa | sonnet | sonnet | haiku |
| scout | sonnet | sonnet | haiku |
| debugger | opus | sonnet | sonnet |
| architect | opus | sonnet | sonnet |
| docs | sonnet | sonnet | sonnet |

`quality` is the `defaults.json` default. Per `references/model-profiles.md`, `model` names resolve to `opus` = Claude Opus 4.6, `sonnet` = Claude Sonnet 4.5, `haiku` = Claude Haiku 3.5. That doc also gives illustrative relative-cost estimates per phase (Quality about $3.00, Balanced about $1.50 or 50%, Budget about $0.70 or 25%), based on an assumed 3-plan phase with 2 Dev teammates. These are estimates from the doc, not measured figures.

Resolution and overrides:
- `scripts/resolve-agent-model.sh <agent> <config.json> <model-profiles.json>` resolves the effective model for one agent, applying `model_overrides` on top of the active `model_profile`.
- Switch the whole profile: `/vbw:config model_profile <quality|balanced|budget>`.
- Override a single agent: `/vbw:config model_override <agent> <model>`, where `<agent>` is one of `lead|dev|qa|scout|debugger|architect` and `<model>` is one of `opus|sonnet|haiku` (`config.md` does not expose an override path for `docs`).
- `/vbw:config` with no arguments shows a before/after cost estimate using integer cost weights `opus=100, sonnet=20, haiku=2` when switching profiles or setting per-agent overrides.
- Resolved models are passed as an explicit `model:` parameter on every Task tool call. The session's `/model` setting does not propagate to subagents.

## Stack Mappings (config/stack-mappings.json)

Used by `/vbw:init` and `/vbw:vibe` to detect a project's stack from marker files and suggest Claude Code skills. Structured as 7 categories:

| Category | Entries |
| -------- | ------- |
| languages | 11 (python, rust, go, elixir, java, dotnet, deno, bun, ruby, php, kotlin) |
| frameworks | 21 (next, react, vue, svelte, express, fastapi, django, prisma, tailwind, typescript, astro, remix, nuxt, rails, laravel, spring, angular, nestjs, flask, solidjs, phoenix) |
| testing | 3 (vitest, jest, playwright) |
| services | 5 (stripe, supabase, firebase, clerk, auth0) |
| quality | 3 (eslint, prettier, storybook) |
| mobile | 2 (ios-swift, swiftui) |
| devops | 3 (docker, vercel, github-actions) |

Each entry has `detect` (marker files/globs, some scoped to a `package.json:<dep>` pattern), `skills` (suggested skill IDs), and `description`.

Note: the file's JSON source defines a top-level `mobile` object twice. The first block bundles `ios-swift` and `swiftui` alongside `android-kotlin`, `flutter`, and `react-native`. The second, later block redefines `mobile` with only `ios-swift` and `swiftui`. Per JSON object semantics, the second `"mobile"` key wins when parsed, so only 2 mobile entries (`ios-swift`, `swiftui`) are actually visible to tooling that reads this file with `jq` or a standard JSON parser. The `android-kotlin`, `flutter`, and `react-native` entries in the first `mobile` block are shadowed and never detected.

Skill suggestions from this file only take effect when `skill_suggestions` is `true` (the default) in project config. `auto_install_skills` (default `false`) controls whether suggested skills are installed automatically versus just surfaced.

## Token Budgets (config/token-budgets.json)

Per-agent character budgets for context compilation, active when `token_budgets: true` (the default). Budgets are sized at 1-4% of an assumed ~800K-character context window. Claude 4.x models have ~200K token windows, and characters are used instead of tokens for cross-model consistency:

| Agent | max_chars | Description |
| ----- | --------- | ------------ |
| scout | 8000 | Low fixed budget per query batch |
| lead | 20000 | Medium budget, only on plan/replan events |
| dev | 32000 | Per-task budget tied to contract complexity |
| qa | 24000 | Tiered budget by risk class |
| debugger | 32000 | Same as dev, for investigation |
| architect | 20000 | Same as lead, for planning |
| docs | 16000 | Medium budget for documentation artifacts |

Also defines `task_complexity` scoring for per-task Dev budgets: weights `must_haves_weight=1`, `files_weight=2`, `dependency_weight=3`, combined into a score mapped through 4 tiers (`simple` 0-5 at 0.6x, `standard` 6-12 at 1.0x, `complex` 13-20 at 1.3x, `heavy` 21+ at 1.6x). `truncation_strategy` is `head`, and `overage_action` is `truncate_and_log` when a budget is exceeded.

## Rollout Stages (config/rollout-stages.json)

Gates which optional flags are considered safe to enable, keyed to how many clean phases a project has completed. There are 3 stages:

| Stage | Label | Phases required | Flags |
| ----- | ----- | ---------------- | ----- |
| 1 | observability | 0 | metrics, token_budgets, two_phase_completion, rolling_summary |
| 2 | optimization | 2 | (none, all former stage-2 flags have graduated) |
| 3 | full | 5 | validation_gates, smart_routing, snapshot_resume, event_recovery, monorepo_routing, lease_locks |

`advancement.auto_advance` is `false` and `advancement.require_clean_phases` is `true`. Stage progression is not automatic, it requires clean phases to be counted (`count_event: "phase_end"`) rather than being force-advanced by the tooling. All flags named across the 3 stages already default to `true` in `config/defaults.json`, so this file currently documents the staged-rollout rationale for flags that have already graduated to on-by-default, rather than gating anything actively withheld.

## Destructive Commands Guard (config/destructive-commands.txt)

One case-insensitive regex per line, matched with `grep -iE` against the full Bash command string, used by the bash guard to block risky database/filesystem commands before execution. Comment lines (`#`) and blanks are ignored. The file currently has 33 active patterns grouped by ecosystem:

PHP/Laravel, Ruby/Rails, Python/Django, Node.js (Prisma, Knex, Sequelize, TypeORM, Drizzle), Go, Rust (Diesel, SQLx), Elixir/Phoenix/Ecto, raw SQL clients (mysql/psql/sqlite3 `DROP`/`TRUNCATE`), MongoDB shell (`dropDatabase`, `.drop(`), Redis (`FLUSHALL`/`FLUSHDB`), Docker (volume-destroying `down -v`, `volume rm/prune`, `system prune --volumes`), and filesystem removal of `.sqlite`/`.db` files or `/var/lib/{mysql,postgresql,mongodb}`.

Two ways to bypass or extend the guard:
- Override: set `VBW_ALLOW_DESTRUCTIVE=1` in the environment, or set `bash_guard=false` in project config.
- Extend: add project-specific patterns in `.vbw-planning/destructive-commands.local.txt`.

## LSP Mappings (config/lsp-mappings.json)

Maps detected stack items to LSP language servers and Claude Code plugins, using a three-tier priority scheme, per the file's own `_description`. Tier 1 is official Anthropic plugins. Tier 2 is servers from the LSP spec page, via the Piebald-AI plugin where available, otherwise a `null` plugin with a manual `install_cmd`/`install_url`. Tier 3 is Piebald-AI-only languages not otherwise covered, and has no dedicated entries in this file since all Piebald languages already appear under Tier 2.

Counts as of this file: 33 language server entries (11 Tier 1, 22 Tier 2), and 35 alias entries mapping framework/tool names to their underlying language server. For example `react`, `next`, and `svelte` map to `typescript`, `fastapi`, `django`, and `flask` map to `python`, `rails` maps to `ruby`, and `laravel` maps to `php`.

Each server entry carries `tier`, `plugin` (or `null`), `plugin_org`, `binary_check` (a shell probe command), `install_cmd` (or `null` with a companion `install_url`), and `description`. Tier 1 entries (`swift`, `typescript`, `python`, `go`, `rust`, `java`, `kotlin`, `c`, `dotnet`, `lua`, `php`) are all attributed to `plugin_org: "anthropic-official"`. Tier 2 entries are either `Piebald-AI/claude-code-lsps` (most) or have `plugin: null` with a direct `install_cmd` (`bash`, `haskell`, `clojure`, `elm`, `erlang`, `fsharp`, `r`, `zig`, `nix`, `terraform`).

This is what backs the LSP-first code navigation policy referenced by agent tool lists. See `references/lsp-first-policy.md`.

## Message Schemas (config/schemas/message-schemas.json)

Not a config file consumers edit, but the contract for inter-agent messages VBW agents exchange during a run (`schema_version: "2.0"`). Every message carries the envelope fields `id`, `type`, `phase`, `task`, `author_role`, `timestamp`, `schema_version`, `payload`, `confidence`. There are 10 message types: `scout_findings`, `plan_contract`, `execution_update`, `blocker_report`, `debugger_report`, `qa_verdict`, `approval_request`, `approval_response`, `shutdown_request`, `shutdown_response`. Each has an `allowed_roles` list, required/optional payload fields, and a `role_hierarchy` block declaring which roles can send and receive which message types. `qa_verdict` additionally constrains `checks_detail` entries to a `PASS`/`FAIL`/`WARN` status enum and a fixed set of known categories (`must_have`, `artifact`, `key_link`, `anti_pattern`, `convention`, `requirement`, `skill_augmented`).

## Where This Is Wired Up

`commands/config.md` (`/vbw:config`) is the interactive and scriptable entry point for all of the above except the guard and schema files:
- No-args mode walks Core settings or Model profile via `AskUserQuestion`, then applies the change through a shared apply step.
- `<setting> <value>` mode validates and writes directly. It has dedicated validation for `max_uat_remediation_rounds` (via `scripts/resolve-uat-remediation-round-limit.sh`, accepting `false`, `0`, or a positive integer), and a `.gitignore` sync step when `planning_tracking` changes (via `scripts/planning-git.sh sync-ignore`).
- `model_profile <profile>` and `model_override <agent> <model>` subcommands apply the model-profile changes described above, each printing a before/after cost estimate.
- `skill_hook <skill> <event> <tools>` / `skill_hook remove <skill>` manage per-skill hook wiring stored under `config.json`'s `skill_hooks` key. That key lives entirely in project config, not in any of the files above.

Every write goes through Step 0 first, which runs `scripts/migrate-config.sh --print-added` to backfill any settings keys added to `config/defaults.json` since the project's `.vbw-planning/config.json` was created, before any read or write in the rest of the command proceeds.
