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

## No-Tool Circuit Breaker

At every non-team subagent return site, inspect returned text before artifact validation, summary finalization, deterministic gates, or state advancement. If it says tools, shell/Bash, filesystem, edits, or API-session access are unavailable, treat that as a platform/tool provisioning failure. Stop without advancing state, report the failed role and stage or task, and do not retry the same prompt. Do not consume the normal retry budget. Repeating a no-tool spawn cannot fix tool provisioning and wastes tokens.

Call sites must copy this invariant byte-for-byte:

```text
No-tool invariant: treat unavailable tools as a provisioning failure, do not advance state, and do not retry the same prompt.
```
