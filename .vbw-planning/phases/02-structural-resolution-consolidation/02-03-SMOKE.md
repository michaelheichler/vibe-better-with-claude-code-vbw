# Plan 02-03 Fresh-Session Smoke

Date: 2026-07-31
Verdict: pass

Smoke-tested from an isolated sandbox while loading the candidate plugin checkout via `--plugin-dir` or a marketplace-root `"source":"./"` install. No configured consumer debug target was available, so `/tmp/vbw-02-03-smoke/sandbox` was used. Each command below was the first command in an independent fresh session.

## `--plugin-dir` install

| Command | Session | Result | Session link |
|---|---|---|---|
| `/vbw:help` | `b9b6cf7f-14b6-4e4a-a1fb-e45c34122353` | Exit 0. Full VBW help rendered with no resolver diagnostic. | `/Users/michael/dev/skills/vibe-better-with-claude-code-vbw` |
| `/vbw:status` | `eab4672c-1c09-4bb6-9bca-4bff022f866b` | Exit 0. Reached the expected missing-`.vbw-planning/` guard with no resolver or phase-detect diagnostic. | `/Users/michael/dev/skills/vibe-better-with-claude-code-vbw` |

Evidence:

- `/tmp/vbw-02-03-smoke/config-plugin/projects/-private-tmp-vbw-02-03-smoke-sandbox/b9b6cf7f-14b6-4e4a-a1fb-e45c34122353.jsonl`
- `/tmp/vbw-02-03-smoke/config-plugin/projects/-private-tmp-vbw-02-03-smoke-sandbox/eab4672c-1c09-4bb6-9bca-4bff022f866b.jsonl`
- `/tmp/vbw-02-03-smoke/plugin-help.debug`
- `/tmp/vbw-02-03-smoke/plugin-status.debug`

## Marketplace-root `"source":"./"` install

The isolated install record pointed `vbw@vbw-marketplace` directly at `/tmp/vbw-02-03-smoke/market-source`, whose marketplace entry used `"source":"./"`. The versioned cache copy was removed before each fresh session. SessionStart created the deterministic session link to the marketplace root.

| Command | Session | Result | Session link |
|---|---|---|---|
| `/vbw:help` | `1f5652a2-83ee-453e-9498-d3684f65a493` | Exit 0. Full VBW help rendered with no resolver diagnostic. | `/private/tmp/vbw-02-03-smoke/market-source` |
| `/vbw:status` | `4c639954-8c62-4f70-bf3f-72ddd63d4410` | Exit 0. Reached the expected missing-`.vbw-planning/` guard with no resolver or phase-detect diagnostic. | `/private/tmp/vbw-02-03-smoke/market-source` |

Evidence:

- `/tmp/vbw-02-03-smoke/config-market/projects/-private-tmp-vbw-02-03-smoke-sandbox/1f5652a2-83ee-453e-9498-d3684f65a493.jsonl`
- `/tmp/vbw-02-03-smoke/config-market/projects/-private-tmp-vbw-02-03-smoke-sandbox/4c639954-8c62-4f70-bf3f-72ddd63d4410.jsonl`
- `/tmp/vbw-02-03-smoke/market-help.debug`
- `/tmp/vbw-02-03-smoke/market-status.debug`

The encoded project path is the sandbox path in all four transcripts, not the plugin checkout. Temporary copied credentials were removed after the runs.
