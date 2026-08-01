#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir

  RESOLVER="$SCRIPTS_DIR/resolve-plugin-root.sh"
  ENSURE_LINK="$SCRIPTS_DIR/ensure-plugin-root-link.sh"
  export CLAUDE_CONFIG_DIR="$TEST_TEMP_DIR/claude"
  export VBW_CACHE_ROOT="$TEST_TEMP_DIR/cache"
  export VBW_TMP_ROOT="$TEST_TEMP_DIR/tmp"
  export CLAUDE_SESSION_ID="resolver-${BATS_TEST_NUMBER}-$$"
  export MOCK_PS_OUTPUT=""
  SESSION_LINK="$VBW_TMP_ROOT/.vbw-plugin-root-link-${CLAUDE_SESSION_ID}"

  mkdir -p "$CLAUDE_CONFIG_DIR" "$VBW_CACHE_ROOT" "$VBW_TMP_ROOT" "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/ps" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_PS_OUTPUT:-}"
MOCK
  chmod +x "$TEST_TEMP_DIR/bin/ps"
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  unset CLAUDE_PLUGIN_ROOT
}

teardown() {
  teardown_temp_dir
}

make_root() {
  local name="$1"
  local root="$TEST_TEMP_DIR/roots/$name"

  mkdir -p "$root/scripts" "$root/commands"
  : > "$root/scripts/hook-wrapper.sh"
  : > "$root/commands/vibe.md"
  cp "$ENSURE_LINK" "$root/scripts/ensure-plugin-root-link.sh"
  (cd "$root" && pwd -P)
}

assert_resolved() {
  local expected="$1"

  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  [ -L "$SESSION_LINK" ]
  [ "$(readlink "$SESSION_LINK")" = "$expected" ]
}

@test "explicit CLAUDE_PLUGIN_ROOT wins and is canonicalized" {
  local root alias
  root=$(make_root explicit)
  alias="$TEST_TEMP_DIR/explicit-alias"
  ln -s "$root" "$alias"
  export CLAUDE_PLUGIN_ROOT="$alias"

  run bash "$RESOLVER"

  assert_resolved "$root"
}

@test "cache local resolves when explicit root is unavailable" {
  local root
  root=$(make_root local)
  ln -s "$root" "$VBW_CACHE_ROOT/local"

  run bash "$RESOLVER"

  assert_resolved "$root"
}

@test "highest numeric cache version wins before generic cache entries" {
  local older newer generic
  older=$(make_root numeric-older)
  newer=$(make_root numeric-newer)
  generic=$(make_root generic-shadow)
  ln -s "$older" "$VBW_CACHE_ROOT/1.9.0"
  ln -s "$newer" "$VBW_CACHE_ROOT/1.10.0"
  ln -s "$generic" "$VBW_CACHE_ROOT/zulu"

  run bash "$RESOLVER"

  assert_resolved "$newer"
}

@test "lexically last generic cache entry resolves without numeric entries" {
  local alpha zulu
  alpha=$(make_root generic-alpha)
  zulu=$(make_root generic-zulu)
  ln -s "$alpha" "$VBW_CACHE_ROOT/alpha"
  ln -s "$zulu" "$VBW_CACHE_ROOT/zulu"

  run bash "$RESOLVER"

  assert_resolved "$zulu"
}

@test "marketplace root resolves without a cache entry" {
  local root marketplaces_root
  root=$(make_root marketplace)
  marketplaces_root="$CLAUDE_CONFIG_DIR/plugins/marketplaces"
  mkdir -p "$marketplaces_root"
  ln -s "$root" "$marketplaces_root/vbw-marketplace"

  run bash "$RESOLVER"

  assert_resolved "$root"
}

@test "exact session link resolves before generic links" {
  local exact generic
  exact=$(make_root exact-link)
  generic=$(make_root generic-link-shadow)
  ln -s "$exact" "$SESSION_LINK"
  ln -s "$generic" "$VBW_TMP_ROOT/.vbw-plugin-root-link-z-generic"

  run bash "$RESOLVER"

  assert_resolved "$exact"
}

@test "first valid generic session link resolves when exact link is absent" {
  local first second
  first=$(make_root generic-link-first)
  second=$(make_root generic-link-second)
  ln -s "$first" "$VBW_TMP_ROOT/.vbw-plugin-root-link-a-first"
  ln -s "$second" "$VBW_TMP_ROOT/.vbw-plugin-root-link-z-second"

  run bash "$RESOLVER"

  assert_resolved "$first"
}

@test "process tree plugin-dir recovery resolves the candidate" {
  local root
  root=$(make_root process)
  export MOCK_PS_OUTPUT="claude --plugin-dir $root"

  run bash "$RESOLVER"

  assert_resolved "$root"
}

@test "total failure exits one with an actionable diagnostic" {
  run bash "$RESOLVER"

  [ "$status" -eq 1 ]
  [ "$output" = "VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics." ]
  [ ! -e "$SESSION_LINK" ]
}

@test "link repair failure exits one with an actionable diagnostic" {
  local root
  root=$(make_root link-failure)
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$root/scripts/ensure-plugin-root-link.sh"
  chmod +x "$root/scripts/ensure-plugin-root-link.sh"
  export CLAUDE_PLUGIN_ROOT="$root"

  run bash "$RESOLVER"

  [ "$status" -eq 1 ]
  [ "$output" = "VBW: plugin root link failed. Run /vbw:doctor for diagnostics." ]
  [ ! -e "$SESSION_LINK" ]
}

@test "wrong-target exact link is repaired after higher-priority resolution" {
  local expected wrong
  expected=$(make_root expected)
  wrong=$(make_root wrong)
  ln -s "$wrong" "$SESSION_LINK"
  export CLAUDE_PLUGIN_ROOT="$expected"

  run bash "$RESOLVER"

  assert_resolved "$expected"
}

@test "require-script resolves a root containing the requested script" {
  local root
  root=$(make_root required-present)
  : > "$root/scripts/phase-detect.sh"
  export CLAUDE_PLUGIN_ROOT="$root"

  run bash "$RESOLVER" --require-script phase-detect.sh

  assert_resolved "$root"
}

@test "require-script rejects roots missing the requested script" {
  local root
  root=$(make_root required-absent)
  export CLAUDE_PLUGIN_ROOT="$root"

  run bash "$RESOLVER" --require-script phase-detect.sh

  [ "$status" -eq 1 ]
  [ "$output" = "VBW: plugin root resolution failed. Run /vbw:doctor for diagnostics." ]
  [ ! -e "$SESSION_LINK" ]
}

@test "nonfatal failure emits no output and exits zero" {
  run bash "$RESOLVER" --nonfatal

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$SESSION_LINK" ]
}

@test "explicit root wins when every lower-priority source exists" {
  local explicit local numeric generic marketplace exact generic_link process marketplace_dir
  explicit=$(make_root precedence-explicit)
  local=$(make_root precedence-local)
  numeric=$(make_root precedence-numeric)
  generic=$(make_root precedence-generic)
  marketplace=$(make_root precedence-marketplace)
  exact=$(make_root precedence-exact)
  generic_link=$(make_root precedence-generic-link)
  process=$(make_root precedence-process)

  export CLAUDE_PLUGIN_ROOT="$explicit"
  ln -s "$local" "$VBW_CACHE_ROOT/local"
  ln -s "$numeric" "$VBW_CACHE_ROOT/9.0.0"
  ln -s "$generic" "$VBW_CACHE_ROOT/zulu"
  marketplace_dir="$CLAUDE_CONFIG_DIR/plugins/marketplaces"
  mkdir -p "$marketplace_dir"
  ln -s "$marketplace" "$marketplace_dir/vbw"
  ln -s "$exact" "$SESSION_LINK"
  ln -s "$generic_link" "$VBW_TMP_ROOT/.vbw-plugin-root-link-z-generic"
  export MOCK_PS_OUTPUT="claude --plugin-dir $process"

  run bash "$RESOLVER"

  assert_resolved "$explicit"
}

@test "cache local wins over numeric cache when both exist" {
  local local_root numeric
  local_root=$(make_root precedence-local-second)
  numeric=$(make_root precedence-numeric-second)
  ln -s "$local_root" "$VBW_CACHE_ROOT/local"
  ln -s "$numeric" "$VBW_CACHE_ROOT/99.0.0"

  run bash "$RESOLVER"

  assert_resolved "$local_root"
}
