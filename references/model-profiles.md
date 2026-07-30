# Model Profiles

**Purpose:** Control AI model selection for VBW agents to optimize cost vs quality tradeoff.

## Overview
VBW spawns 7 specialized agents (Lead, Dev, QA, Scout, Debugger, Architect, Docs) via the Task tool. Model profiles determine which Claude model each agent uses. Three preset profiles cover common use cases, with per-agent overrides for advanced customization.

## Preset Profiles

### Quality (default)
**Use when:** Architecture decisions, production-critical work, anything embarrassing to get wrong.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | opus | Maximum planning depth and research quality |
| Dev | opus | Complex implementation, deep reasoning |
| QA | sonnet | Solid verification without Opus cost |
| Scout | sonnet | Research quality with MCP tool access |
| Debugger | opus | Root cause analysis needs deep reasoning |
| Architect | opus | Roadmap and phase structure requires strategic thinking |
| Docs | sonnet | Documentation tasks benefit from clear prose without Opus cost |

**Est. cost per phase:** ~$3.00 (baseline)

### Balanced
**Use when:** Standard development work, most phases.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | sonnet | Good planning quality, 5x cheaper than Opus |
| Dev | sonnet | Solid implementation for most tasks |
| QA | sonnet | Standard verification depth |
| Scout | sonnet | Research quality, MCP tool access |
| Debugger | sonnet | Good debugging for common issues |
| Architect | sonnet | Clear roadmaps without Opus overhead |
| Docs | sonnet | Standard documentation quality |

**Est. cost per phase:** ~$1.50 (50% of Quality)

### Budget
**Use when:** Prototyping, exploratory work, tight budget constraints.

| Agent | Model | Rationale |
|-------|-------|-----------|
| Lead | sonnet | Minimum viable planning (Haiku too weak) |
| Dev | sonnet | Maintains code quality baseline |
| QA | haiku | Quick verification, 25x cheaper |
| Scout | haiku | Fast research, minimal cost |
| Debugger | sonnet | Root cause needs Sonnet minimum |
| Architect | sonnet | Roadmap clarity worth Sonnet cost |
| Docs | sonnet | Maintains documentation quality baseline |

**Est. cost per phase:** ~$0.70 (25% of Quality, 50% of Balanced)

## Per-Agent Overrides
Override individual agents without switching profiles.

**Syntax (via /vbw:config):**
```
/vbw:config model_override <agent> <model>
```

**Example:**
```
/vbw:config model_override dev opus
```
Sets Dev to Opus while keeping other agents at profile defaults.

**When to override:**
- Dev to Opus on budget profile for complex implementation tasks
- QA to Sonnet on budget profile for critical verification
- Lead to Opus on balanced profile for strategic planning phases

**Clearing overrides:**
Switch to a different profile and back, or manually edit .vbw-planning/config.json.

## Cost Comparison

| Profile | Lead | Dev | QA | Scout | Docs | Est. Cost/Phase | vs Quality |
|---------|------|-----|----|----|------|-----------------|------------|
| Quality | opus | opus | sonnet | sonnet | sonnet | $3.00 | 100% |
| Balanced | sonnet | sonnet | sonnet | sonnet | sonnet | $1.50 | 50% |
| Budget | sonnet | sonnet | haiku | haiku | sonnet | $0.70 | 25% |

*Estimates based on typical 3-plan phase with 2 Dev teammates, 1 QA run, Lead planning. Assumes ~15K input + ~5K output tokens per agent turn. Opus ~$15/$75 per MTok, Sonnet ~$3/$15, Haiku ~$0.25/$1.25 (input/output). Actual costs vary by phase complexity and plan count.*

## Configuration

**View current profile:**
```
/vbw:config
```
Shows active profile and per-agent model assignments in settings table.

**Switch profile:**
```
/vbw:config model_profile <quality|balanced|budget>
```
Displays before/after cost impact estimate.

**Config file location:**
`.vbw-planning/config.json` -- fields: `model_profile` (string), `model_overrides` (object)

## Detected Catalog and Model Matrix

When Claude Code runs against an Anthropic-compatible endpoint that exposes more than the Claude tiers (any gateway/proxy), VBW can route agents to those models natively:

- `scripts/detect-models.sh` queries `${ANTHROPIC_BASE_URL}/v1/models` with the auth env available (`ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN`) and prints the available model ids. Results are cached for 1h per base URL. With no auth env (stock OAuth setups) it prints nothing and static tiers apply.
- `/vbw:init` (Step 1.8) runs detection, proposes an agent x effort matrix from the detected ids, and writes the confirmed result to `.vbw-planning/config.json` as `model_matrix`, alongside `model_catalog` and `model_catalog_detected_at`. `/vbw:config` -> Model profile -> Model matrix re-runs the same flow.

**Matrix shape:**

```json
"model_matrix": {
  "dev":  { "thorough": "sol", "balanced": ["sol", "claude-sonnet-5"], "fast": "glm52", "turbo": "glm52" },
  "docs": { "balanced": ["glm52", "haiku"] }
}
```

Values are a single model id or a preference array. Arrays resolve to the first entry present in the detected catalog; when no catalog is readable, the first entry is trusted as written. The matrix is sparse: any missing agent/effort cell falls through to the profile preset.

**Resolution precedence** (`scripts/resolve-agent-model.sh`):

1. `model_overrides.<agent>` (string or preference array)
2. `model_matrix.<agent>.<effort>` (string or preference array; `<effort>` is the config `effort` value)
3. `model_profile` preset (tier table above)

## Implementation Notes
- Model resolution: `scripts/resolve-agent-model.sh` reads config, applies profile preset, merges overrides
- Turn-budget resolution: `scripts/resolve-agent-max-turns.sh` reads config `agent_max_turns` and scales by effort. Set a value to `false` or `0` to give that agent unlimited turns — the resolver emits an empty string, and the orchestrator omits the `maxTurns` parameter from the Task tool call
- Task tool integration: All agent-spawning commands pass explicit `model` and `maxTurns` parameters. When the resolver emits a non-empty value (positive integer), `maxTurns` is included; when the resolver emits an empty value (unlimited), `maxTurns` is omitted entirely
- Turbo effort bypasses model logic (no agents spawned, direct execution)
- Model names: `opus`/`sonnet`/`haiku` are Claude Code tier aliases resolved to the latest model of each tier; full model ids (e.g. `claude-opus-5`) and gateway catalog ids are also valid

## Related Documentation
- Effort vs Model: @references/effort-profile-balanced.md (effort controls workflow depth, model profile controls cost)
- Command reference: @commands/help.md
- User guide: @README.md Cost Optimization section
