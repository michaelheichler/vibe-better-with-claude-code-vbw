# Model Profiles

**Purpose:** choose a model and a reasoning effort for each of VBW's 8 agents (Lead, Dev, QA, QA Author, Scout, Debugger, Architect, Docs). QA Author follows the QA route.

Two independent axes. **Model** decides which engine runs the role. **Reasoning effort** decides how hard that engine thinks. A strong model at `medium` often beats a weaker model at its default, so reach for the effort dial before downgrading the model.

Machine-readable prices, context sizes, and accepted effort values live in `config/model-pricing.json`. That file is the source of truth. The tables here are a summary for reasoning about tradeoffs.

## Routing principle

Route by **measured performance at the role's actual task**, not by a generic capability ladder. Cost is the tiebreaker between models that are all adequate for the role, never the primary selector. A cheap model that fails the task costs more than an expensive one that succeeds, because the work gets redone.

## Task performance (July 2026)

Numbers are the most recent public measurements. Sources are named because several vendor claims could not be independently confirmed.

### Agentic coding (Dev)

| Model | SWE-bench Verified | Terminal-Bench 2.1 | Source |
|---|---|---|---|
| claude-opus-5 | 97.0 | 84.6 | Vals AI 2026-07-22 |
| gpt-5.6-sol | 96.2 | 85.8 | Vals AI |
| claude-fable-5 | 95.0 | 83.8 | Vals AI, tbench.ai (Claude Code harness) |
| kimi-k3 | 93.4 | 80.9 | Vals AI |
| gpt-5.6-luna | 93.0 | 79.0 | Vals AI |
| claude-opus-4-8 | 88.6 | 78.9 | Vals AI, tbench.ai |
| grok-4.5 | 86.6 | 79.3 | Vals AI, tbench.ai (Cursor CLI) |
| glm-5.2 | 80.0 | 81.0 | steel.dev, vendor card |
| claude-sonnet-5 | not listed | 74.6 | tbench.ai |
| claude-haiku-4-5 | 73.3 | 35.5 (TB 2.0) | anthropic.com, tbench.ai |

Caveat: Vals reports claude-opus-5 at 84.6 on Terminal-Bench, dropping to 81.3 when refusal-fallback passes count as failures.

### Planning and long-horizon reasoning (Lead, Architect)

| Model | ARC-AGI-2 | $/task | HLE | GPQA Diamond |
|---|---|---|---|---|
| gpt-5.6-sol (max) | 92.5 | 1.44 | not listed | 94.6 |
| claude-opus-5 (max) | 90.4 | 2.06 | 64.7 | not listed |
| claude-opus-5 (high) | 88.3 | 1.45 | 64.7 | not listed |
| gpt-5.5 (xhigh) | 85.0 | 1.87 | not listed | 93.6 |
| gemini-3.1-pro | 77.1 | 0.96 | 51.4 | 94.3 |
| claude-opus-4-8 (high) | 72.1 | not listed | 57.9 | 93.6 |
| grok-4.5 (high) | 52.6 | 0.78 | not listed | 93.0 |
| glm-5.2 | 22.8 | not listed | 54.7 | 91.2 |
| **claude-haiku-4-5** | **1.3 to 4.0** | not listed | not listed | not listed |

Sources: arcprize.org verified leaderboard, llm-stats.com. claude-fable-5, claude-sonnet-5, and kimi-k3 are absent from ARC-AGI-2. Fable 5 scores 64.5 on HLE and Sonnet 5 scores 57.4.

**Haiku 4.5 must never be routed to Lead, Architect, or Debugger.** A 1.3 to 4.0 percent score against 88 to 92 for the frontier tier is not a cost tradeoff, it is a different capability class.

### Code review and bug finding (QA)

**No vendor publishes a general code-review eval, and none publishes false-positive versus recall data.** The only measured proxies are security-focused: gpt-5.6-sol scores 73.5 on ExploitBench, 71.2 on SEC-Bench Pro, and 84.5 on CyberGym. Anthropic names CyberGym and OSS-Fuzz for its models but publishes no scores.

Rank QA by agentic-coding performance, then prefer a **different family from Dev** when the catalog has one. Cross-family review catches what self-similar review misses. This is a structural argument, not a benchmarked one.

### Research and long context (Scout)

| Model | BrowseComp | Context | Note |
|---|---|---|---|
| kimi-k3 | 91.2 | 1,048,576 | Highest single-agent score |
| gpt-5.6-sol | 90.4 | 1,050,000 | 92.2 with 4 parallel agents |
| gpt-5.5-pro | 90.1 | 1,050,000 | |
| claude-fable-5 | 88.0 | 1,000,000 | |
| gemini-3.1-pro | 85.9 | 1,000,000 | MRCR v2 84.9 at 128K, 26.3 at 1M |
| claude-sonnet-5 | 84.7 | 1,000,000 | 86.6 multi-agent |
| claude-opus-4-8 | 84.3 | 1,000,000 | 88.5 multi-agent |
| grok-4.5 | not listed | 500,000 | |
| claude-haiku-4-5 | not listed | 200,000 | Smallest context in the set |

Source: leaderboard.steel.dev 2026-07-27, llm-stats.com. Anthropic retracted its own Sonnet 5 BrowseComp chart for methodology reasons, so the figure above is the aggregator's.

Scout reads a lot of source material. Context size is a hard constraint before quality matters.

### Debugging (Debugger)

**No vendor publishes a debugging or root-cause eval for any model in this set.** Confirmed independently across Anthropic, OpenAI, Moonshot, z.ai, Google, xAI, MiniMax, and DeepSeek documentation. Treat absence as missing data, not as low capability.

Use agentic coding as the proxy and weight planning performance heavily, since root-cause analysis is a reasoning task. That combination puts opus-5, gpt-5.6-sol, and fable-5 at the top and rules out haiku.

### Documentation and prose (Docs)
On4iUUes1@
| Model | LMArena text Elo | Rank |
|---|---|---|
| claude-fable-5 | 1508 | 1 |
| claude-opus-5 (max) | 1495 | 5 |
| gemini-3.1-pro | 1486 | 10 |
| kimi-k3 (max) | 1486 | 11 |
| gpt-5.6-sol (xhigh) | 1485 | 13 |
| claude-opus-4-8 | 1484 | 14 |
| glm-5.2 (max) | 1469 | 31 |
| grok-4.5 | 1468 | 35 |
| claude-sonnet-5 (high) | 1460 | 44 |
| gpt-5.6-luna (xhigh) | 1452 | 56 |
| claude-haiku-4-5 | 1412 | 120 |

Source: lmarena.ai 2026-07-27, 7.5M votes. The spread across the top 30 is inside roughly 3 percent, so Docs is the role where a cheap model costs least.

## Price and quality per dollar

USD per million tokens. Full data including long-context tiers is in `config/model-pricing.json`.

| Model | Input | Output | Context | Effort ladder |
|---|---|---|---|---|
| claude-fable-5 | 10.00 | 50.00 | 1M | low to max |
| claude-opus-5 | 5.00 | 25.00 | 1M | low to max |
| claude-opus-4-8 | 5.00 | 25.00 | 1M | low to max |
| claude-sonnet-5 | 2.00 | 10.00 | 1M | low to max |
| claude-haiku-4-5 | 1.00 | 5.00 | 200K | **none** |
| gpt-5.6-sol | 5.00 | 30.00 | 1.05M | low to xhigh |
| gpt-5.6-terra | 2.00 | 12.00 | 1.05M | low to xhigh |
| gpt-5.6-luna | 0.20 | 1.20 | 1.05M | low to xhigh |
| gpt-5.5 | 5.00 | 30.00 | 1.05M | none to xhigh |
| gpt-5.5-pro | 30.00 | 180.00 | 1.05M | medium to xhigh |
| kimi-k3 | 3.00 | 15.00 | 1M | low, high, max |
| kimi-k2.7-code | 0.95 | 4.00 | 262K | always on |
| glm-5.2 | 1.40 | 4.40 | 1M | unpublished |
| gemini-3.1-pro | 2.00 | 12.00 | 1M | low, medium, high |
| grok-4.5 | 2.00 | 6.00 | 500K | low, medium, high |
| minimax-m3 | 0.30 | 1.20 | 1M | none |
| deepseek-v4-flash | 0.14 | 0.28 | 1M | low, high, max |

Two pricing traps:

- **Long-context surcharges.** gpt-5.6 and gpt-5.5 roughly double above 272K tokens. gemini-3.1-pro and grok-4.5 do the same above 200K. minimax-m3 doubles above 512K. A Scout run on a large repo can silently cost twice the headline rate.
- **claude-sonnet-5 at 2.00/10.00 is an introductory rate expiring 2026-08-31**, reverting to 3.00/15.00.

Best measured quality per dollar, by role:

| Role | Pick | Why |
|---|---|---|
| Dev | claude-opus-5 | Top SWE-bench Verified at half of fable-5's rate |
| Lead, Architect | gpt-5.6-sol or claude-opus-5 | Highest ARC-AGI-2 per dollar per task (1.44 and 1.45) |
| QA | a strong model from a different family than Dev | No eval exists, so structure substitutes for data |
| Scout | gemini-3.1-pro or kimi-k3 | 0.96 per ARC task and the top BrowseComp score, both at 1M context |
| Debugger | claude-opus-5 | Best combined coding and planning, and no debugging eval exists |
| Docs | gpt-5.6-luna or claude-haiku-4-5 | Elo gap to the frontier is small, price gap is 25x to 40x |

## Subscriptions

This is usually the decisive factor and it inverts the per-token advice above.

| Plan | USD per month | Includes |
|---|---|---|
| Claude Pro | 20 (17 annual) | Claude Code |
| Claude Max 5x | 100 | Claude Code |
| Claude Max 20x | 200 | Claude Code |
| Claude Team | 25 per seat | Claude Code |
| Claude Team Premium | 125 per seat | Claude Code, 5x usage |
| ChatGPT Go / Plus | 8 / 20 | Codex |
| ChatGPT Pro | 100 (5x) / 200 (20x) | Codex |
| z.ai GLM Coding Lite | 18 | GLM-5.2, GLM-5-Turbo, GLM-4.7 |
| OpenCode Zen | none | Pay as you go, no subscription tier |

**On a Pro, Max, or Team plan the marginal token cost is zero until quota exhausts.** The correct default is then the strongest model the plan allows, and the per-token tables above are irrelevant. They govern API-key and gateway setups only.

Unresolved: z.ai Pro and Max prices, and the Kimi Code plan price. Both vendor pages render client-side and published no figures.

OpenCode Zen exposes an Anthropic-compatible endpoint at `https://opencode.ai/zen/v1/messages`, so it is reachable directly from Claude Code through `ANTHROPIC_BASE_URL` without a router.

## Choosing models per role

Apply the task tables above. Where the detected catalog lacks a listed model, rank by family and price.

- **Lead, Architect, Debugger:** highest planning score available. Never haiku-class.
- **Dev:** highest agentic-coding score available.
- **QA:** strong model from a different family than Dev when the catalog has one. Fall back to a strong same-family model otherwise.
- **Scout:** largest context first, then research score. Watch the long-context surcharge.
- **Docs, and every fast or turbo cell:** cheapest capable model. This is where the quality gap is genuinely small.

Families and strengths of non-Claude ids come from the labeled descriptions emitted by `detect-models.sh --labeled` at detection time. **Never invent a model id.** The tables in this file are for ranking an id that detection already returned. Preference arrays should end in a Claude tier id as a stable final fallback.

`/vbw:init` Step 1.8 and `/vbw:config` Model matrix both apply this guidance.

## Reasoning effort

The second axis. Values, per family, verified against vendor documentation:

| Family | Parameter | Accepted values | Default |
|---|---|---|---|
| Claude 5 (fable, opus, sonnet) | `output_config.effort` | low, medium, high, xhigh, max | high |
| **claude-haiku-4-5** | none | **rejects the parameter** | n/a |
| OpenAI gpt-5.5 | `reasoning.effort` | none, low, medium, high, xhigh | medium |
| OpenAI gpt-5.5-pro | `reasoning.effort` | medium, high, xhigh | high |
| OpenAI gpt-5.6 | `reasoning.effort` | xhigh confirmed, full set unpublished | medium |
| kimi-k3 | `reasoning_effort` | low, high, max | max |
| gemini-3.1-pro | `thinking_level` | low, medium, high | high |
| grok-4.5 | `reasoning_effort` | low, medium, high (cannot disable) | high |
| deepseek-v4-flash | `reasoning_effort` | low, high, max | n/a |
| glm-5.2, minimax-m3, kimi-k2.7-code | varies | no usable ladder published | n/a |

Sending an unsupported value is a hard API error, not a no-op. `scripts/resolve-agent-reasoning.sh` reconciles the configured value against `config/model-pricing.json` and emits an empty string when the model rejects the parameter, so the orchestrator omits it.

Per-profile defaults live in `config/reasoning-profiles.json`:

| Agent | quality | balanced | budget |
|---|---|---|---|
| lead | xhigh | high | medium |
| dev | xhigh | high | medium |
| architect | xhigh | high | medium |
| debugger | xhigh | high | medium |
| qa | high | medium | low |
| scout | high | medium | low |
| docs | medium | low | low |

**Effort is the cheaper dial.** Before moving Dev from opus-5 down to sonnet-5, try opus-5 at `medium`. Effort scales token spend on the same engine, whereas a model swap changes capability class.

## Preset profiles

Fallback when no matrix is configured.

| Agent | quality | balanced | budget |
|---|---|---|---|
| lead | opus | sonnet | sonnet |
| dev | opus | sonnet | sonnet |
| qa | sonnet | sonnet | sonnet |
| scout | sonnet | sonnet | sonnet |
| debugger | opus | sonnet | sonnet |
| architect | opus | sonnet | sonnet |
| docs | sonnet | sonnet | haiku |

Budget places haiku on Docs only. Earlier revisions routed Scout and QA to haiku, which the measured data does not support: Scout needs the 1M context haiku lacks, and QA needs the reasoning haiku scores 1.3 to 4.0 percent on.

**Per-agent overrides:** `/vbw:config model_override <agent> <model>`. Clear them by switching profile and back, or by editing `.vbw-planning/config.json`.

## Detected catalog and model matrix

When Claude Code runs against an Anthropic-compatible endpoint exposing more than the Claude tiers, VBW routes agents to those models natively.

`scripts/detect-models.sh` treats the model table embedded in the Claude Code binary as the sole primary source. It works offline, needs zero credentials on subscription or OAuth setups, and a patched binary advertises injected models in the same structures. `${ANTHROPIC_BASE_URL}/v1/models` is queried only as a last resort, when the binary yields nothing and `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` exists. Results cache for 1h, keyed on the binary's path, mtime, and size, so a re-patched binary invalidates immediately. `--labeled` emits `id` TAB `description` for the proposal flows. Empty output means static tiers apply.

**Matrix shape:**

```json
"model_matrix": {
  "dev":  { "thorough": "sol", "balanced": ["sol", "claude-sonnet-5"], "fast": "glm52", "turbo": "glm52" },
  "docs": { "balanced": ["glm52", "haiku"] }
},
"reasoning_matrix": {
  "dev":  { "thorough": "xhigh", "balanced": "medium" },
  "docs": { "balanced": "low" }
}
```

Model values are a single id or a preference array. Arrays resolve to the first entry present in the detected catalog. With no readable catalog the first entry is trusted as written. Both matrices are sparse, so any missing agent or effort cell falls through to the profile preset.

Reasoning values are a single effort string. Preference arrays are not supported there, because the resolver already reconciles against the model's accepted set.

**Resolution precedence:**

Model (`scripts/resolve-agent-model.sh`):

1. `model_overrides.<agent>`
2. `model_matrix.<agent>.<effort>`
3. `model_profile` preset

Reasoning (`scripts/resolve-agent-reasoning.sh`):

1. `reasoning_overrides.<agent>`
2. `reasoning_matrix.<agent>.<effort>`
3. `model_profile` preset from `reasoning-profiles.json`
4. Reconciliation against the resolved model's accepted set

`model_catalog_extra` (array, default `[]`) lists trusted model ids the user knows are good even though detection did not advertise them, such as an unlisted model behind a gateway. Preference-array resolution treats these as available alongside the detected catalog. They are consulted only when a detected catalog exists. An empty or unreadable catalog still trusts the first array entry as written.

## Implementation notes

- Model resolution: `scripts/resolve-agent-model.sh`
- Reasoning resolution: `scripts/resolve-agent-reasoning.sh`
- Combined: `scripts/resolve-agent-settings.sh` emits `RESOLVED_MODEL`, `RESOLVED_MAX_TURNS`, `RESOLVED_EFFORT`, and `RESOLVED_REASONING`
- Turn budgets: `scripts/resolve-agent-max-turns.sh` reads `agent_max_turns` and scales by effort. Set a value to `false` or `0` for unlimited turns, which emits an empty string and makes the orchestrator omit `maxTurns`
- Task tool integration: agent-spawning commands pass explicit `model`, `maxTurns`, and `effort` parameters. Empty resolver output means the parameter is omitted entirely
- Turbo effort bypasses model logic, since no agents are spawned
- Model names: `opus`, `sonnet`, `haiku`, and `fable` are Claude Code tier aliases resolved to the latest model of each tier. Full ids and gateway catalog ids are also valid

## Data freshness

Benchmark numbers and prices were collected 2026-07-31. Re-verify after roughly six months.

Current boards: Vals AI, tbench.ai Terminal-Bench 2.1, arcprize.org, LMArena, leaderboard.steel.dev, llm-stats.com. Aider polyglot (last updated 2025-11), the official LiveCodeBench board (window ends 2025-05), and swebench.com (2026-02) are stale and contain none of these models.

Anthropic publishes its headline benchmarks only as chart images, so Claude SWE-bench figures here come from Vals AI rather than from Anthropic directly.

## Related documentation

- Effort vs model: @references/effort-profile-balanced.md (workflow effort controls depth, this file controls engine and thinking)
- Command reference: @commands/help.md
- User guide: @README.md Cost Optimization section
