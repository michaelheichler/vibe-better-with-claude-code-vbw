#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  export PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning"
}

teardown() {
  teardown_temp_dir
}

@test "manifest read rejects a present non-object agents field" {
  printf '%s\n' '{"agents":[]}' > "$PLANNING_DIR/.agent-manifest.json"

  run bash -c 'source "$1"; agent_manifest_read "$2"' _ \
    "$SCRIPTS_DIR/lib/agent-manifest.sh" "$PLANNING_DIR"

  [ "$status" -ne 0 ]
}

@test "manifest read converts a legacy flat manifest only when agents is absent" {
  printf '%s\n' '{"legacy":{"state":"used"}}' > "$PLANNING_DIR/.agent-manifest.json"

  run bash -c 'source "$1"; agent_manifest_read "$2"' _ \
    "$SCRIPTS_DIR/lib/agent-manifest.sh" "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.agents.legacy.state')" = "used" ]
}

@test "manifest lock recovers a stale lock" {
  mkdir "$PLANNING_DIR/.agent-manifest.lock"
  touch -t 200001010000 "$PLANNING_DIR/.agent-manifest.lock"

  run bash -c 'source "$1"; VBW_AGENT_MANIFEST_LOCK_TIMEOUT=1 VBW_AGENT_MANIFEST_LOCK_STALE_SECONDS=1; noop() { :; }; agent_manifest_with_lock "$2" noop' _ \
    "$SCRIPTS_DIR/lib/agent-manifest.sh" "$PLANNING_DIR"

  [ "$status" -eq 0 ]
  [ ! -d "$PLANNING_DIR/.agent-manifest.lock" ]
}

@test "manifest lock times out when held" {
  mkdir "$PLANNING_DIR/.agent-manifest.lock"

  run bash -c 'source "$1"; VBW_AGENT_MANIFEST_LOCK_TIMEOUT=1; noop() { :; }; agent_manifest_with_lock "$2" noop' _ \
    "$SCRIPTS_DIR/lib/agent-manifest.sh" "$PLANNING_DIR"

  [ "$status" -eq 1 ]
}

@test "manifest lock preserves concurrent read-modify-write updates" {
  local writer="$TEST_TEMP_DIR/writer.sh" pids=() pid i failures=0
  cat > "$writer" <<'EOF'
#!/usr/bin/env bash
set -u
. "$1"
planning_dir="$2"
name="$3"
update_manifest() {
  local manifest updated
  manifest=$(agent_manifest_read "$planning_dir") || return 1
  sleep 0.02
  updated=$(jq --arg name "$name" '.agents[$name] = {state:"registered"}' <<< "$manifest") || return 1
  agent_manifest_write "$planning_dir" "$updated"
}
agent_manifest_with_lock "$planning_dir" update_manifest
EOF
  chmod +x "$writer"
  for i in $(seq 1 12); do
    bash "$writer" "$SCRIPTS_DIR/lib/agent-manifest.sh" "$PLANNING_DIR" "agent-$i" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failures=$((failures + 1))
    fi
  done

  [ "$failures" -eq 0 ]
  [ "$(jq '.agents | length' "$PLANNING_DIR/.agent-manifest.json")" -eq 12 ]
}
