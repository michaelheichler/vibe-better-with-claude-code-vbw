#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_ROOT="$(mktemp -d)"
  SANDBOX="$TEST_ROOT/sandbox"

  mkdir -p "$SANDBOX/scripts" "$SANDBOX/.claude-plugin"
  cp "$REPO_ROOT/scripts/bump-version.sh" "$SANDBOX/scripts/bump-version.sh"
  SCRIPT="$SANDBOX/scripts/bump-version.sh"

  printf '1.0.0\n' > "$SANDBOX/VERSION"
  printf '{"version":"1.0.0"}\n' > "$SANDBOX/.claude-plugin/plugin.json"
  printf '{"plugins":[{"version":"1.0.0"}]}\n' > "$SANDBOX/.claude-plugin/marketplace.json"
  printf '{"plugins":[{"version":"1.0.0"}]}\n' > "$SANDBOX/marketplace.json"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

version_snapshot() {
  printf '%s|%s|%s|%s' \
    "$(tr -d '[:space:]' < "$SANDBOX/VERSION")" \
    "$(jq -r '.version' "$SANDBOX/.claude-plugin/plugin.json")" \
    "$(jq -r '.plugins[0].version' "$SANDBOX/.claude-plugin/marketplace.json")" \
    "$(jq -r '.plugins[0].version' "$SANDBOX/marketplace.json")"
}

@test "bump-version: --help exits 0 and mutates nothing" {
  before="$(version_snapshot)"

  run bash "$SCRIPT" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: bump-version.sh"* ]]
  [[ "$output" == *"--set X.Y.Z"* ]]
  [ "$(version_snapshot)" = "$before" ]
}

@test "bump-version: -h exits 0 and mutates nothing" {
  before="$(version_snapshot)"

  run bash "$SCRIPT" -h

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: bump-version.sh"* ]]
  [ "$(version_snapshot)" = "$before" ]
}

@test "bump-version: unknown flag exits 1 and mutates nothing" {
  before="$(version_snapshot)"

  run bash "$SCRIPT" --bogus

  [ "$status" -eq 1 ]
  [[ "$output" == *"unrecognized argument '--bogus'"* ]]
  [[ "$output" == *"Usage: bump-version.sh"* ]]
  [ "$(version_snapshot)" = "$before" ]
}

@test "bump-version: --set 2.0.0 writes all four files in sync" {
  run bash "$SCRIPT" --set 2.0.0

  [ "$status" -eq 0 ]
  [[ "$output" == *"Version is now 2.0.0"* ]]
  [ "$(version_snapshot)" = "2.0.0|2.0.0|2.0.0|2.0.0" ]
}

@test "bump-version: --set garbage exits 1 and mutates nothing" {
  before="$(version_snapshot)"

  run bash "$SCRIPT" --set garbage

  [ "$status" -eq 1 ]
  [[ "$output" == *"not a valid semver"* ]]
  [ "$(version_snapshot)" = "$before" ]
}

@test "bump-version: --set with no version argument exits 1 and mutates nothing" {
  before="$(version_snapshot)"

  run bash "$SCRIPT" --set

  [ "$status" -eq 1 ]
  [[ "$output" == *"--set requires a version argument"* ]]
  [ "$(version_snapshot)" = "$before" ]
}

@test "bump-version: --verify passes on a synced fixture" {
  run bash "$SCRIPT" --verify

  [ "$status" -eq 0 ]
  [[ "$output" == *"All 4 version files are in sync (1.0.0)."* ]]
}

@test "bump-version: --verify fails on a desynced fixture" {
  printf '{"version":"1.0.1"}\n' > "$SANDBOX/.claude-plugin/plugin.json"

  run bash "$SCRIPT" --verify

  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH DETECTED"* ]]
  [[ "$output" == *".claude-plugin/plugin.json (1.0.1 != 1.0.0)"* ]]
}
