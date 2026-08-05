#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  setup_temp_dir
  mkdir -p "$TEST_TEMP_DIR/.vbw-planning"
  export VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
  export EVIDENCE_SCRIPT="$SCRIPTS_DIR/agent-routing-evidence.sh"
  cd "$TEST_TEMP_DIR"
}

teardown() {
  teardown_temp_dir
}

write_manifest() {
  printf '%s\n' "$1" > "$VBW_PLANNING_DIR/.agent-manifest.json"
  printf '%s\n' '{}' > "$VBW_PLANNING_DIR/config.json"
}

run_evidence() {
  local mode="$1" input="$2"
  run bash -c 'printf "%s\n" "$1" | env -u CLAUDE_CODE_SUBAGENT_MODEL -u CLAUDE_CODE_EFFORT_LEVEL VBW_PLANNING_DIR="$2" bash "$3" "$4"' _ "$input" "$VBW_PLANNING_DIR" "$EVIDENCE_SCRIPT" "$mode"
}

run_evidence_with_overrides() {
  local mode="$1" input="$2"
  run bash -c 'printf "%s\n" "$1" | CLAUDE_CODE_SUBAGENT_MODEL=override-model CLAUDE_CODE_EFFORT_LEVEL=override-effort VBW_PLANNING_DIR="$2" bash "$3" "$4"' _ "$input" "$VBW_PLANNING_DIR" "$EVIDENCE_SCRIPT" "$mode"
}

start_input() {
  jq -n '{agent_type:"generated",agent_id:"agent-1",model:"claude-sonnet-5",effort:"high",max_turns:12}'
}

stop_input() {
  local path="$1"
  jq -n --arg path "$path" '{agent_type:"generated",agent_id:"agent-1",agent_transcript_path:$path}'
}

@test "evidence records model pass and effort unknown from transcript" {
  local transcript input record
  write_manifest '{"agents":{"generated":{"state":"running","model":"claude-sonnet-5","effort":"high"}}}'
  transcript="$TEST_TEMP_DIR/subagent.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-5","content":[]}}' > "$transcript"

  run_evidence start "$(start_input)"
  [ "$status" -eq 0 ]
  run_evidence stop "$(stop_input "$transcript")"
  [ "$status" -eq 0 ]

  record=$(jq -s '.[0]' "$VBW_PLANNING_DIR/.agent-routing-evidence.jsonl")
  [ "$(jq -r '.verdict.model' <<< "$record")" = "pass" ]
  [ "$(jq -r '.verdict.effort' <<< "$record")" = "unknown" ]
  [ "$(jq -r '.transcript_path_field' <<< "$record")" = "agent_transcript_path" ]
  [ "$(jq -r '.requested.requested_max_turns' <<< "$record")" = "12" ]
  [ -n "$(jq -r '.requested.config_hash' <<< "$record")" ]
}

@test "evidence records model mismatch and emits stop warning" {
  local transcript record
  write_manifest '{"agents":{"generated":{"state":"running","model":"claude-sonnet-5"}}}'
  transcript="$TEST_TEMP_DIR/subagent.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-5","content":[]}}' > "$transcript"

  run_evidence start "$(start_input)"
  run_evidence stop "$(stop_input "$transcript")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent routing evidence mismatch"* ]]
  record=$(jq -s '.[0]' "$VBW_PLANNING_DIR/.agent-routing-evidence.jsonl")
  [ "$(jq -r '.verdict.model' <<< "$record")" = "mismatch" ]
}

@test "evidence classifies environment overrides at start" {
  local transcript record
  write_manifest '{"agents":{"generated":{"state":"running","model":"claude-sonnet-5","effort":"high"}}}'
  transcript="$TEST_TEMP_DIR/subagent.jsonl"
  printf '%s\n' '{"type":"assistant","message":{"model":"claude-sonnet-5","content":[]}}' > "$transcript"

  run_evidence_with_overrides start "$(start_input)"
  run_evidence_with_overrides stop "$(stop_input "$transcript")"
  [ "$status" -eq 0 ]
  record=$(jq -s '.[0]' "$VBW_PLANNING_DIR/.agent-routing-evidence.jsonl")
  [ "$(jq -r '.verdict.model' <<< "$record")" = "env_override" ]
  [ "$(jq -r '.verdict.effort' <<< "$record")" = "env_override" ]
  [ "$(jq -r '.requested.env_override_model' <<< "$record")" = "true" ]
}

@test "evidence tolerates a missing transcript" {
  local record
  write_manifest '{"agents":{"generated":{"state":"running","model":"claude-sonnet-5","effort":"high"}}}'

  run_evidence start "$(start_input)"
  run_evidence stop "$(stop_input "$TEST_TEMP_DIR/missing.jsonl")"
  [ "$status" -eq 0 ]
  record=$(jq -s '.[0]' "$VBW_PLANNING_DIR/.agent-routing-evidence.jsonl")
  [ "$(jq -r '.verdict.model' <<< "$record")" = "unknown" ]
  [ "$(jq -r '.verdict.effort' <<< "$record")" = "unknown" ]
}

@test "evidence check summarizes counts and stale running entries" {
  write_manifest '{"agents":{"generated":{"state":"running","last_activity_at":"1970-01-01T00:00:00Z"}}}'
  printf '%s\n' \
    '{"timestamp":"2026-08-05T00:00:00Z","name":"a","verdict":{"model":"pass","effort":"unknown"}}' \
    '{"timestamp":"2026-08-05T00:01:00Z","name":"b","verdict":{"model":"mismatch","effort":"env_override"}}' \
    > "$VBW_PLANNING_DIR/.agent-routing-evidence.jsonl"

  run bash "$EVIDENCE_SCRIPT" check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent routing evidence: 2 records"* ]]
  [[ "$output" == *"mismatch     model=1 effort=0"* ]]
  [[ "$output" == *"env_override model=0 effort=1"* ]]
  [[ "$output" == *"unknown      model=0 effort=1"* ]]
  [[ "$output" == *"stale running entries=1"* ]]
}
