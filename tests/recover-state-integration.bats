#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config
  cd "$TEST_TEMP_DIR" || return

  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > init.txt && git add init.txt && git commit -q -m "init"

  cat > "$TEST_TEMP_DIR/.vbw-planning/STATE.md" <<'STATE'
State
## Current Phase
## Phase Status
Phase: 1 of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  mkdir -p "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup"
  echo "# Plan" > "$TEST_TEMP_DIR/.vbw-planning/phases/01-setup/01-01-PLAN.md"

  echo "# Test Project" > "$TEST_TEMP_DIR/.vbw-planning/PROJECT.md"
}

teardown() {
  teardown_temp_dir
}


@test "recover-state: outputs empty JSON when event_recovery is false" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = false' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: outputs empty JSON when no arguments" {
  run bash "$SCRIPTS_DIR/recover-state.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: outputs empty JSON when phase dir not found" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json
  run bash "$SCRIPTS_DIR/recover-state.sh" 99 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "recover-state: reconstructs state from SUMMARY.md files" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.phase == 1' >/dev/null
  echo "$output" | jq -e '.status == "running"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: detects pending plans without SUMMARY.md" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "pending"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "pending"' >/dev/null
}

@test "recover-state: qa_required false allows complete existing state" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","qa_required":false,"plans":[{"id":"01-01","status":"pending"}]}
STATE
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "complete"' >/dev/null
  echo "$output" | jq -e '.qa_required == false' >/dev/null
}

@test "recover-state: reports complete when every plan finishes via event log only" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Ship it" > .vbw-planning/phases/01-setup/01-02-PLAN.md

  mkdir -p .vbw-planning/.events
  cat > .vbw-planning/.events/event-log.jsonl <<'EVENTS'
{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}
{"event":"plan_end","phase":1,"plan":2,"data":{"status":"complete"}}
EVENTS

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "running"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
  echo "$output" | jq -e '.plans[1].status == "complete"' >/dev/null
}

@test "recover-state: reports failed when one plan fails via event log with no SUMMARY.md" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Ship it" > .vbw-planning/phases/01-setup/01-02-PLAN.md

  mkdir -p .vbw-planning/.events
  cat > .vbw-planning/.events/event-log.jsonl <<'EVENTS'
{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}
{"event":"plan_end","phase":1,"plan":2,"data":{"status":"failed"}}
EVENTS

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "failed"' >/dev/null
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
  echo "$output" | jq -e '.plans[1].status == "failed"' >/dev/null
}

@test "session-start: calls recover-state.sh when event log is newer than execution state" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","qa_required":true,"effort":"balanced","phase_effort":"balanced","plans":[{"id":"01-01","status":"pending"}]}
STATE

  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl

  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
  [ "$(jq -r '.qa_required' .vbw-planning/.execution-state.json)" = "true" ]
  [ "$(jq -r '.effort' .vbw-planning/.execution-state.json)" = "balanced" ]
  [ "$(jq -r '.phase_effort' .vbw-planning/.execution-state.json)" = "balanced" ]
}

@test "session-start: orphan summary does not finalize a pending plan" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/.execution-state.json <<"STATE"
{"phase":1,"status":"running","qa_required":false,"plans":[{"id":"01-01","status":"pending"}]}
STATE
  cat > .vbw-planning/phases/01-setup/R01-SUMMARY.md <<"SUMMARY"
---
status: failed
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status' .vbw-planning/.execution-state.json)" = "running" ]
  [ "$(jq -r '.plans[0].status' .vbw-planning/.execution-state.json)" = "pending" ]
}

@test "session-start: skips recovery when event_recovery is false" {
  cd "$TEST_TEMP_DIR"
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}]}
STATE

  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
}

@test "session-start: recovers missing execution state when event log exists" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/.execution-state.json ]
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
  [ "$(jq -r '.plans[0].status' .vbw-planning/.execution-state.json)" = "complete" ]
}

@test "session-start: does not recover when event log does not exist" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ ! -f .vbw-planning/.execution-state.json ]
}

@test "session-start: does not recover when execution state is newer than event log" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md

  sleep 1
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}]}
STATE

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
}


@test "session-start: skips recovery when event log is empty (0 bytes)" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  mkdir -p .vbw-planning/.events
  : > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ ! -f .vbw-planning/.execution-state.json ]
}

@test "session-start: recovers when STATE.md has no Phase line (fallback to exec-state phase)" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/STATE.md <<'STATE'
State
## Current Phase
## Phase Status
Status: in-progress
Progress: 50%
STATE

  cat > .vbw-planning/.execution-state.json <<'EXEC'
{"phase":1,"status":"running","qa_required":false,"plans":[{"id":"01-01","status":"pending"}]}
EXEC

  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "complete" ]
}

@test "session-start: recovers when STATE.md has non-numeric Phase (fallback to dir detect)" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/STATE.md <<'STATE'
State
## Current Phase
## Phase Status
Phase: X of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ -f .vbw-planning/.execution-state.json ]
  recovered_phase=$(jq -r '.phase' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_phase" = "1" ]
  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "running" ]
}

@test "session-start: rejects recovery when recovered phase differs from requested phase" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/STATE.md <<'STATE'
State
## Current Phase
## Phase Status
Phase: 2 of 2 (Build)
Status: in-progress
Progress: 60%
STATE

  mkdir -p .vbw-planning/phases/02-build

  cat > .vbw-planning/.execution-state.json <<'EXEC'
{"phase":1,"status":"running","qa_required":false,"plans":[{"id":"01-01","status":"pending"}]}
EXEC

  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_phase=$(jq -r '.phase' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_phase" = "1" ]
}


@test "recover-state: event log matches single-digit plan numbers (leading-zero strip)" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Third Task" > .vbw-planning/phases/01-setup/01-03-PLAN.md

  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":3,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]

  plan_status=$(echo "$output" | jq -r '.plans[] | select(.id == "01-03") | .status')
  [ "$plan_status" = "complete" ]
}

@test "recover-state: exact numeric match prevents plan/phase 1 vs 10 collisions" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: First Task" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Tenth Task" > .vbw-planning/phases/01-setup/01-10-PLAN.md

  mkdir -p .vbw-planning/.events
  cat > .vbw-planning/.events/event-log.jsonl <<'EVENTS'
{"event":"plan_end","phase":10,"plan":1,"data":{"status":"complete"}}
{"event":"plan_end","phase":1,"plan":10,"data":{"status":"complete"}}
EVENTS

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]

  plan_01_status=$(echo "$output" | jq -r '.plans[] | select(.id == "01-01") | .status')
  [ "$plan_01_status" = "pending" ]

  plan_10_status=$(echo "$output" | jq -r '.plans[] | select(.id == "01-10") | .status')
  [ "$plan_10_status" = "complete" ]
}

@test "recover-state: malformed trailing matching line does not mask prior valid event" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  mkdir -p .vbw-planning/.events
  cat > .vbw-planning/.events/event-log.jsonl <<'EVENTS'
{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}
{"event":"plan_end","phase":1,"plan":1,"data":{"status":"failed"
EVENTS

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]

  plan_status=$(echo "$output" | jq -r '.plans[] | select(.id == "01-01") | .status')
  [ "$plan_status" = "complete" ]
}

@test "recover-state: latest valid plan_end status overrides SUMMARY status" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY
  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"failed"}}' > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[] | select(.id == "01-01") | .status == "failed"' >/dev/null
  echo "$output" | jq -e '.status == "failed"' >/dev/null
}

@test "recover-state: non-numeric wave defaults to 1 instead of dropping plan" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/phases/01-setup/01-01-PLAN.md <<'PLAN'
title: Build UI
wave: alpha
PLAN

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]

  plan_count=$(echo "$output" | jq '.plans | length')
  [ "$plan_count" -eq 1 ]
  plan_wave=$(echo "$output" | jq '.plans[0].wave')
  [ "$plan_wave" -eq 1 ]
}

@test "session-start: skips recovery when event log is whitespace-only" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  mkdir -p .vbw-planning/.events
  printf '\n\n\n' > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ ! -f .vbw-planning/.execution-state.json ]
}

@test "session-start: handles missing .events directory gracefully" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  rm -rf .vbw-planning/.events

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  [ ! -f .vbw-planning/.execution-state.json ]
}

@test "session-start: auto-recovery skips reconcile block" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","qa_required":false,"plans":[{"id":"01-01","status":"pending"}]}
STATE

  mkdir -p .vbw-planning/.events
  sleep 1
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "complete" ]
}

@test "recover-state: treats SUMMARY status 'completed' as complete" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: completed
---
SUMMARY

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
  echo "$output" | jq -e '.status == "running"' >/dev/null
}

@test "recover-state: treats quoted SUMMARY status 'completed' as complete" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  cat > .vbw-planning/phases/01-setup/01-01-SUMMARY.md <<'SUMMARY'
---
status: "completed"
---
SUMMARY

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
  echo "$output" | jq -e '.status == "running"' >/dev/null
}

@test "session-start: reconcile resolves phase 3 to 03-* dir via find_phase_dir_by_num" {
  cd "$TEST_TEMP_DIR"

  mkdir -p .vbw-planning/phases/03-core
  echo "title: Core" > .vbw-planning/phases/03-core/03-01-PLAN.md
  cat > .vbw-planning/phases/03-core/03-01-SUMMARY.md <<'SUMMARY'
---
status: complete
---
SUMMARY

  cat > .vbw-planning/STATE.md <<'STATE'
State
## Current Phase
## Phase Status
Phase: 3 of 3 (Core)
Status: in-progress
Progress: 80%
STATE

  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":3,"status":"running","plans":[{"id":"03-01","status":"pending"}]}
STATE

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_status=$(jq -r '.status' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_status" = "complete" ]
}

@test "session-start: non-numeric STATE phase prefers event-backed phase over highest numeric phase" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  cat > .vbw-planning/STATE.md <<'STATE'
State
## Current Phase
## Phase Status
Phase: X of 2 (Setup)
Status: in-progress
Progress: 50%
STATE

  mkdir -p .vbw-planning/phases/02-build
  echo "# Plan" > .vbw-planning/phases/02-build/02-01-PLAN.md

  mkdir -p .vbw-planning/.events
  echo '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}' > .vbw-planning/.events/event-log.jsonl

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]

  recovered_phase=$(jq -r '.phase' .vbw-planning/.execution-state.json 2>/dev/null)
  [ "$recovered_phase" = "1" ]
}


@test "recover-state: parses SUMMARY with CRLF line endings" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf -- '---\r\nstatus: complete\r\n---\r\n# Summary\r\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: parses SUMMARY with quoted status value" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf -- '---\nstatus: "complete"\n---\n# Summary\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: parses SUMMARY with whitespace-padded status" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf -- '---\nstatus:   complete   \n---\n# Summary\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: parses SUMMARY with leading blank line and BOM" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: Build UI" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  printf '\xef\xbb\xbf\n---\nstatus: complete\n---\n# Summary\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.plans[0].status == "complete"' >/dev/null
}

@test "recover-state: marks a phase partial, not complete, when a summary is only partial" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: First" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  printf -- '---\nstatus: complete\n---\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf -- '---\nstatus: partial\n---\n' > .vbw-planning/phases/01-setup/01-02-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "partial"' >/dev/null
  echo "$output" | jq -e '.plans[] | select(.id == "01-02") | .status == "partial"' >/dev/null
}

@test "recover-state: reports partial, not running, when every summary is terminal" {
  cd "$TEST_TEMP_DIR"
  local tmp
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: First" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  printf -- '---\nstatus: partial\n---\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf -- '---\nstatus: partial\n---\n' > .vbw-planning/phases/01-setup/01-02-SUMMARY.md

  run bash "$SCRIPTS_DIR/recover-state.sh" 1 ".vbw-planning/phases"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.status == "partial"' >/dev/null
}


@test "session-start: preserves recovered state age across sessions" {
  cd "$TEST_TEMP_DIR"
  local tmp initial_epoch initial_stamp state_mtime_before state_mtime_after recovery_now
  tmp=$(mktemp)
  jq '.event_recovery = true' .vbw-planning/config.json > "$tmp" && mv "$tmp" .vbw-planning/config.json

  echo "title: First" > .vbw-planning/phases/01-setup/01-01-PLAN.md
  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  printf -- '---\nstatus: complete\n---\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf '%s\n' '{"phase":1,"status":"running","correlation_id":"dead-run","plans":[{"id":"01-01","status":"pending"},{"id":"01-02","status":"pending"}]}' > .vbw-planning/.execution-state.json

  REAL_DATE=$(command -v date)
  export REAL_DATE
  recovery_now=$("$REAL_DATE" +%s)
  initial_epoch=$((recovery_now - 14300))
  if [ "$(uname)" = "Darwin" ]; then
    initial_stamp=$("$REAL_DATE" -r "$initial_epoch" '+%Y%m%d%H%M.%S')
  else
    initial_stamp=$("$REAL_DATE" -d "@$initial_epoch" '+%Y%m%d%H%M.%S')
  fi
  touch -t "$initial_stamp" .vbw-planning/.execution-state.json
  state_mtime_before=$(stat -f %m .vbw-planning/.execution-state.json 2>/dev/null || stat -c %Y .vbw-planning/.execution-state.json)

  printf '%s\n' '{"mode":"execute","active":true,"delegation_mode":"subagent","correlation_id":"dead-run"}' > .vbw-planning/.delegated-workflow.json
  mkdir -p .vbw-planning/.events "$TEST_TEMP_DIR/bin"
  printf '{"event":"plan_end","phase":1,"plan":1,"data":{"status":"complete"}}\n' > .vbw-planning/.events/event-log.jsonl
  printf '%s\n' '#!/bin/bash' 'if [ "${1:-}" = "+%s" ]; then' '  printf "%s\n" "$VBW_TEST_NOW"' 'else' '  exec "$REAL_DATE" "$@"' 'fi' > "$TEST_TEMP_DIR/bin/date"
  chmod +x "$TEST_TEMP_DIR/bin/date"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  export VBW_TEST_NOW="$recovery_now"

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  [ -f .vbw-planning/.delegated-workflow.json ]
  [ "$(jq -r '.status' .vbw-planning/.execution-state.json)" = "running" ]
  state_mtime_after=$(stat -f %m .vbw-planning/.execution-state.json 2>/dev/null || stat -c %Y .vbw-planning/.execution-state.json)
  [ "$state_mtime_after" = "$state_mtime_before" ]

  export VBW_TEST_NOW=$((recovery_now + 101))
  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  [ ! -f .vbw-planning/.delegated-workflow.json ]
}

@test "session-start: reconcile flips running state to partial when every plan summary is terminal" {
  cd "$TEST_TEMP_DIR"
  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"complete"},{"id":"01-02","status":"running"}]}
STATE
  printf -- '---\nstatus: complete\n---\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  printf -- '---\nstatus: partial\n---\n' > .vbw-planning/phases/01-setup/01-02-SUMMARY.md

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  reconciled_status=$(jq -r '.status' .vbw-planning/.execution-state.json)
  [ "$reconciled_status" = "partial" ]
}

@test "session-start: reconcile preserves execution-state mtime for interrupted runs" {
  cd "$TEST_TEMP_DIR"
  echo "title: Second" > .vbw-planning/phases/01-setup/01-02-PLAN.md
  cat > .vbw-planning/.execution-state.json <<'STATE'
{"phase":1,"status":"running","plans":[{"id":"01-01","status":"complete"},{"id":"01-02","status":"pending"}]}
STATE
  printf -- '---\nstatus: complete\n---\n' > .vbw-planning/phases/01-setup/01-01-SUMMARY.md
  touch -t 202001010000 .vbw-planning/.execution-state.json
  old_mtime=$(stat -f %m .vbw-planning/.execution-state.json 2>/dev/null || stat -c %Y .vbw-planning/.execution-state.json)

  run bash "$SCRIPTS_DIR/session-start.sh"
  [ "$status" -eq 0 ]
  reconciled_status=$(jq -r '.status' .vbw-planning/.execution-state.json)
  [ "$reconciled_status" = "running" ]
  new_mtime=$(stat -f %m .vbw-planning/.execution-state.json 2>/dev/null || stat -c %Y .vbw-planning/.execution-state.json)
  [ "$new_mtime" = "$old_mtime" ]
}
