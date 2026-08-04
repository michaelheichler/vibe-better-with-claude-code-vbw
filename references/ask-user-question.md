# AskUserQuestion Contract

Use this contract whenever an agent asks a user to choose a next step.

## Write for quick decisions

### Use clear words

- Use plain words. Explain technical terms before using them.
- State one decision in each question.
- Use a short header with a concrete label.
- Write a short question. Put only answer-critical context in it.

### Make options scannable

- Use 2 to 4 options for a bounded choice.
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

Ask one question at a time when the next question depends on the answer. Batch independent questions in one call. Ask no more than 4 questions in a call.

Claude Code provides an Other path for structured choices. Treat it as a valid freeform answer. If the user chooses Other to explain, ask for and process the explanation in plain text before presenting another menu. Accept hybrid answers such as `#2, without pagination`.

## Tool shape

For an interactive AskUserQuestion call, send `questions`. Each question has:

- `header`: a short label, up to 12 characters.
- `question`: the complete user-visible decision.
- `options`: 2 to 4 choices. Each choice has `label` and `description`. `preview` is optional and belongs on an option when the host supports previews.
- `multiSelect`: set this to `true` only when several options can all be correct.

Do not use `answers`, `annotations`, or `metadata` to compose an interactive question. They are response or host-integration fields, not user-facing question content. Do not assume a `metadata.source` value or per-question `annotations` shape.

Do not set a question-level `preview`. A preview is optional content on an option. Do not use previews for multi-select questions.

## Examples

### Structured choice

Header: Next step

Question: What should happen next?

Options:
- Plan phase 03. The scope is ready to turn into a plan. (Recommended)
- Discuss phase 03. Explore open questions before planning.
- Stop here. Keep the current work unchanged.

### Open answer

Prompt: Which todo should I act on? Give its number or describe it in your own words.

This stays plain text because the possible answers are not a short fixed list.

### Decision gate

Header: Continue

Question: Start implementation now?

Options:
- Start now. Begin the approved work. (Recommended)
- Keep exploring. Resolve more questions first.
