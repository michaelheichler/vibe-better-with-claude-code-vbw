# Shared Subagent Contracts

This document is the canonical source for the team-shutdown contract, the non-team spawn shape, and the no-tool circuit breaker. `references/handoff-schemas.md` remains the authority for V2 message schemas. Do not duplicate those schemas here.

Keep this material local at call sites:

- Role-specific stop tails
- Debugger checkpointing
- The Architect shutdown exclusion
- Actual-team-mode gating and teardown sequencing
- Residual-cleanup ordering
- UAT artifact-path guidance
- Text pasted verbatim into child prompt payloads

## Team-Shutdown Contract

When a message contains `"type":"shutdown_request"` or `shutdown_request` in its text:

1. Finish any in-progress tool call.
2. Call the SendMessage tool with this JSON body. Fill in the current status and echo the request ID.

   ```json
   {"type": "shutdown_response", "approved": true, "request_id": "<id from shutdown_request>", "final_status": "complete"}
   ```

   Use `final_status` value `"complete"`, `"idle"`, or `"in_progress"` as appropriate.
3. Then stop. Do not start new work or take any further action.

**CRITICAL: Plain text acknowledgement is NOT sufficient.** You MUST call the SendMessage tool. The orchestrator cannot proceed with team shutdown until it receives a tool-call `shutdown_response` from every teammate.

The orchestrator must wait for each `shutdown_response` with `approved: true`, delivered through a teammate SendMessage tool call. Send at most three `shutdown_request` attempts per teammate, counting the initial request. If a teammate responds in plain text instead of calling SendMessage or rejects the request, re-send it immediately while attempts remain. If the teammate has not approved after the third attempt, log a warning and proceed to residual cleanup.

Call sites must copy this invariant byte-for-byte:

```text
Shutdown invariant: acknowledge every `shutdown_request` by calling SendMessage with `shutdown_response`, then stop.
```

## Non-Team Spawn Shape

Non-team spawn shape: omit `team_name`, `run_in_background`, `isolation`, and worktree cwd fields (`cwd`, `working_dir`, `workingDirectory`, `workdir`). The `name` field is optional label-only metadata. Never use it for routing, lifecycle state, or team semantics.

Call sites must copy this invariant byte-for-byte:

```text
Non-team invariant: omit `team_name`, `run_in_background`, `isolation`, and all worktree cwd fields.
```

For VBW agents, set `subagent_type` to `<plugin>:<agent-name>`. For example, `vbw:vbw-dev` is correct. Bare `vbw-dev` is wrong.

## No-Tool Circuit Breaker

At every non-team subagent return site, inspect returned text before artifact validation, summary finalization, deterministic gates, or state advancement. If it says tools, shell/Bash, filesystem, edits, or API-session access are unavailable, treat that as a platform/tool provisioning failure. Stop without advancing state, report the failed role and stage or task, and do not retry the same prompt. Do not consume the normal retry budget. Repeating a no-tool spawn cannot fix tool provisioning and wastes tokens.

Call sites must copy this invariant byte-for-byte:

```text
No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
```

## Effort Routing Contract

- Model routing is enforced by the spawn guard and passed as the documented Task `model` parameter.
- Reasoning effort is enforced at the hook/frontmatter layer. It is not a documented Task parameter.
- Orchestrators must not claim reasoning effort was or was not applied based on tool schema visibility or agent self-report. Subagents cannot introspect their own reasoning effort.
- Evidence for actual routing lives in session and subagent transcripts.
- Workflow effort (`thorough`, `balanced`, `fast`, `turbo`) is a matrix key distinct from reasoning effort (`low` through `max`).
