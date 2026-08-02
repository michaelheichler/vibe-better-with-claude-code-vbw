#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  create_test_config

  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  unset CLAUDE_PLUGIN_ROOT CLAUDE_ENV_FILE
  CACHE_DIR="$CLAUDE_CONFIG_DIR/plugins/cache/vbw-marketplace/vbw"
  SESSION_ID="cache-sort-${BATS_TEST_NUMBER}-$$"

  export REAL_SORT REAL_MKDIR REAL_RMDIR
  REAL_SORT=$(command -v sort)
  REAL_MKDIR=$(command -v mkdir)
  REAL_RMDIR=$(command -v rmdir)
  mkdir -p "$TEST_TEMP_DIR/bin"

  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "${1:-}" = "-V" ]; then exit 2; fi' \
    'exec "$REAL_SORT" "$@"' > "$TEST_TEMP_DIR/bin/sort"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$#" -eq 1 ] && [ "$1" = "/tmp/vbw-cache-cleanup-lock" ]; then exit 0; fi' \
    'exec "$REAL_MKDIR" "$@"' > "$TEST_TEMP_DIR/bin/mkdir"
  printf '%s\n' '#!/usr/bin/env bash' \
    'if [ "$#" -eq 1 ] && [ "$1" = "/tmp/vbw-cache-cleanup-lock" ]; then exit 0; fi' \
    'exec "$REAL_RMDIR" "$@"' > "$TEST_TEMP_DIR/bin/rmdir"
  chmod +x "$TEST_TEMP_DIR/bin/sort" "$TEST_TEMP_DIR/bin/mkdir" "$TEST_TEMP_DIR/bin/rmdir"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

teardown() {
  rm -f "/tmp/.vbw-plugin-root-link-${SESSION_ID}"
  teardown_temp_dir
}

make_cache_version() {
  local version="$1"
  local root="$CACHE_DIR/$version"

  mkdir -p "$root/commands" "$root/.claude-plugin" "$root/config"
  printf '# init\n' > "$root/commands/init.md"
  printf '{"name":"vbw","version":"%s"}\n' "$version" > "$root/.claude-plugin/plugin.json"
  printf '%s\n' "$version" > "$root/VERSION"
  printf '{}\n' > "$root/config/defaults.json"
}

@test "session-start cache cleanup falls back when sort lacks -V" {
  make_cache_version "1.9.0"
  make_cache_version "1.10.0"

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s\\n' '{\"session_id\":\"$SESSION_ID\"}' | bash '$SCRIPTS_DIR/session-start.sh'"

  [ "$status" -eq 0 ]
  [ ! -e "$CACHE_DIR/1.9.0" ]
  [ -d "$CACHE_DIR/1.10.0" ]
}

@test "session-start cache integrity check falls back when sort lacks -V" {
  make_cache_version "1.10.0"
  rm "$CACHE_DIR/1.10.0/config/defaults.json"

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s\\n' '{\"session_id\":\"$SESSION_ID\"}' | bash '$SCRIPTS_DIR/session-start.sh'"

  [ "$status" -eq 0 ]
  [ ! -d "$CACHE_DIR" ]
  [[ "$output" == *"VBW cache integrity check failed"* ]]
}

@test "session-start marketplace auto-sync falls back when sort lacks -V" {
  local marketplace_dir="$CLAUDE_CONFIG_DIR/plugins/marketplaces/vbw-marketplace"
  make_cache_version "1.10.0"
  mkdir -p "$marketplace_dir/.git" "$marketplace_dir/.claude-plugin" "$marketplace_dir/commands"
  printf '%s\n' '{"name":"vbw","version":"1.10.0"}' > "$marketplace_dir/.claude-plugin/plugin.json"
  printf '# init\n' > "$marketplace_dir/commands/init.md"
  printf '# vibe\n' > "$marketplace_dir/commands/vibe.md"

  run bash -c "cd '$TEST_TEMP_DIR' && printf '%s\\n' '{\"session_id\":\"$SESSION_ID\"}' | bash '$SCRIPTS_DIR/session-start.sh'"

  [ "$status" -eq 0 ]
  [ ! -d "$CACHE_DIR" ]
  [[ "$output" == *"VBW cache stale"* ]]
}
