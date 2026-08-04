# AskUserQuestion Contract

Source note: Stable VBW-facing guidance for Claude Code interactive prompts.
Last reviewed: 2026-08-04

Use this contract whenever an agent asks a user to choose a next step.

## Write for quick decisions

### Use clear words

- Use plain words. Explain technical terms before using them.
- State one decision in each question.
- Use a short header with a concrete label. Keep headers short.
- Write a short question. Put only answer-critical context in it. Include minimal answer-critical context in the `question` itself when a modal may hide nearby prose.

### Make options scannable

- Use 2-4 options for a bounded choice.
- Give each option a concrete label of 1 to 5 words.
- Describe what each option means in one short sentence.
- Mark one option as recommended only when there is a real reason.

### Cut unnecessary text

- Do not hedge with words like "maybe", "just", or "probably".
- Do not lecture, justify the workflow, or repeat context the user already gave.
- Do not show a wall of text. Split context across turns when answers depend on earlier choices.

These rules reduce reading load. They also make questions easier to scan and answer for users with different attention, memory, or processing needs.

## Choose the right interaction

Use AskUserQuestion for a real, bounded decision. Use plain text when the user needs to name, search, number, or describe an open-ended answer.

Ask one question at a time when the next question depends on the answer. Batch independent questions in one call. Ask 1-4 questions in a call.

Claude Code provides an `Other` path for structured choices. See **Freeform handoff** for how to process it. Accept hybrid answers such as `#2, without pagination`.

## Intentional freeform

Do not fake a bounded menu when the real choice is high-cardinality or unbounded. Use plain text when the user needs to name, search, number, or describe an answer outside a short fixed list.

### Freeform handoff

When a user selects `Other` and signals freeform intent, stop using AskUserQuestion. Ask the follow-up as plain text, process the response, then resume structured questions only when needed.

## Anti-patterns

- **Fake bounded menus:** Do not present a fixed option list when the real choice space is unbounded or high-cardinality.

## Examples

### Example: structured single-select

Header: Confirm
Question: Continue with phase 03 now?
Options:
- Execute phase 03. The plan is complete. (Recommended)
- Review plans first. Inspect the plan before execution.
- Not now. Keep the current work unchanged.

### Example: intentional freeform

Prompt: Tell me which todo to act on. Use its number or describe the item in your own words.

This stays plain text because the possible answers are not a short fixed list.

### Example: decision gate

Header: Continue
Question: Start implementation now?
Options:
- Start now. Begin the approved work. (Recommended)
- Keep exploring. Resolve more questions first.

## Tool shape

For an interactive AskUserQuestion call, send `questions`. Each question has a short `header`, a complete `question`, 2-4 `options`, and a `multiSelect` setting. Each option has a `label` and `description`. Option-level `preview` is optional.

Do not use `answers`, `annotations`, or `metadata` to compose an interactive question. They are response or host-integration fields, not user-facing question content. Do not assume a `metadata.source` value or per-question `annotations` shape.

Do not set a question-level `preview`. Use previews only when the host supports them, and do not use them for multi-select questions.

Batch independent questions in one call. Sequence dependent questions across separate calls when one answer determines the next question.


## Final check

Keep the interaction short, bounded where possible, and explicit about the freeform boundary.
