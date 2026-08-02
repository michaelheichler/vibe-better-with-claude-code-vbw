#!/usr/bin/env bats

load test_helper

@test "no nested template expressions in command files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/commands/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no nested template expressions in reference files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/references/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no nested template expressions in agent files" {
  run bash -c "grep -rn '!\`bash \`!\`' \"$PROJECT_ROOT/agents/\" 2>/dev/null"
  [ "$status" -eq 1 ]
}

@test "no legacy cat /tmp/.vbw-plugin-root runtime substitution in commands" {
  run bash -c "grep -R -n 'cat /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/commands\" 2>/dev/null | grep -v 'vbw-plugin-root-link-'"
  [ "$status" -eq 1 ]
}

@test "no legacy cat /tmp/.vbw-plugin-root runtime substitution in references" {
  run bash -c "grep -R -n 'cat /tmp/.vbw-plugin-root' \"$PROJECT_ROOT/references\" 2>/dev/null | grep -v 'vbw-plugin-root-link-'"
  [ "$status" -eq 1 ]
}

_guard_pattern() {
  printf 'while [ ! -L "$L" ] && [ $i -lt 20 ]'
}

@test "vibe.md has 1 simple guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/vibe.md")
  [ "$count" -eq 1 ]
}

@test "qa.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/qa.md")
  [ "$count" -eq 1 ]
}

@test "verify.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/verify.md")
  [ "$count" -eq 1 ]
}

@test "discuss.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/discuss.md")
  [ "$count" -eq 1 ]
}

@test "help.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/help.md")
  [ "$count" -eq 1 ]
}

@test "skills.md has 1 guarded symlink template expression" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/skills.md")
  [ "$count" -eq 1 ]
}

@test "resume.md has 0 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/resume.md" || true)
  [ "${count:-0}" -eq 0 ]
}

@test "status.md has 0 guarded symlink template expressions" {
  local count
  count=$(grep -cF "$(_guard_pattern)" "$PROJECT_ROOT/commands/status.md" || true)
  [ "${count:-0}" -eq 0 ]
}

@test "total guarded symlink template expressions across commands is 6" {
  local count
  count=$(grep -rcF "$(_guard_pattern)" "$PROJECT_ROOT/commands/" 2>/dev/null | awk -F: '{s+=$NF} END{print s}')
  [ "$count" -eq 6 ]
}

@test "guarded expressions define and use the L symlink variable" {
  for cmd in vibe qa verify discuss help skills; do
    local count
    count=$(grep -c 'L="/tmp/.vbw-plugin-root-link-' "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing L symlink variable for guarded reads"; return 1; }
  done
}

_atomic_pd_preamble_pattern() {
  printf 'phase-detect.sh" > "/tmp/.vbw-phase-detect-'
}

_atomic_pd_temp_read_pattern() {
  printf '[ -f "$P" ] && PD=$(cat "$P")'
}

_error_cache_bypass_pattern() {
  printf '[ "$PD" = "phase_detect_error=true" ]'
}

_stale_cache_mtime_pattern() {
  printf '[ "$P_M" -lt "$S_M" ]'
}

_stamp_file_pattern() {
  printf '/tmp/.vbw-phase-detect-stamp-'
}

setup() {
  TMP_TEST_DIRS=()
  TMP_TEST_PATHS=()
}

_new_tmp_test_dir() {
  local d
  d=$(mktemp -d)
  TMP_TEST_DIRS+=("$d")
  printf '%s' "$d"
}

_track_tmp_test_path() {
  TMP_TEST_PATHS+=("$1")
}

_install_shared_resolver_fixture() {
  local root="$1"
  cp "$PROJECT_ROOT/scripts/resolve-plugin-root.sh" "$PROJECT_ROOT/scripts/resolve-claude-dir.sh" \
    "$PROJECT_ROOT/scripts/ensure-plugin-root-link.sh" "$root/scripts/"
  chmod +x "$root/scripts/resolve-plugin-root.sh" "$root/scripts/ensure-plugin-root-link.sh"
}

teardown() {
  local p
  for p in "${TMP_TEST_PATHS[@]}"; do
    [ -n "$p" ] && rm -rf "$p"
  done
  local d
  for d in "${TMP_TEST_DIRS[@]}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}

_conditional_wait_pattern() {
  printf 'if [ -z "$PD" ] || [ "$PD" = "phase_detect_error=true" ] || [ -L "$L" ]; then i=0; while [ ! -L "$L" ] && [ $i -lt 20 ]; do'
}

_simulate_phase_detect_reader() {
  local L="$1"
  local P="$2"
  local FALLBACK_ROOT="${3:-}"
  local PD=""

  _refresh_phase_detect() {
    local R="" REAL_R=""
    if [ -n "$FALLBACK_ROOT" ] && [ -f "$FALLBACK_ROOT/scripts/hook-wrapper.sh" ] && [ -f "$FALLBACK_ROOT/scripts/phase-detect.sh" ]; then
      R="$FALLBACK_ROOT"
    fi
    [ -n "$R" ] || return 1

    REAL_R=$(cd "$R" 2>/dev/null && pwd -P) || return 1
    bash "$PROJECT_ROOT/scripts/ensure-plugin-root-link.sh" "$L" "$REAL_R" >/dev/null 2>&1 || true
    PD=$(bash "$REAL_R/scripts/phase-detect.sh" 2>/dev/null) || PD=""

    if [ -z "$(printf '%s' "$PD" | tr -d '[:space:]')" ] || [ "$PD" = "phase_detect_error=true" ]; then
      return 1
    fi

    printf '%s' "$PD" > "$P"
    return 0
  }

  if ! _refresh_phase_detect; then
    PD="phase_detect_error=true"
    printf '%s\n' "$PD" > "$P"
  fi

  [ -f "$P" ] && PD=$(cat "$P")

  if [ -n "$(printf '%s' "$PD" | tr -d '[:space:]')" ] && [ "$PD" != "phase_detect_error=true" ]; then
    printf '%s' "$PD"
  else
    echo "phase_detect_error=true"
  fi
}

_copy_vibe_phase_state_resolver() {
  local out="$1"
  local out_dir

  out_dir=$(dirname "$out")
  cp "$PROJECT_ROOT/scripts/resolve-phase-state.sh" "$out"
  cp "$PROJECT_ROOT/scripts/resolve-plugin-root.sh" "$out_dir/resolve-plugin-root.sh"
  cp "$PROJECT_ROOT/scripts/resolve-claude-dir.sh" "$out_dir/resolve-claude-dir.sh"
}

_extract_vibe_embedded_phase_state_block() {
  local block="$1"
  local out="$2"

  case "$block" in
    milestone)
      awk '
        /MILESTONE_UAT_CONTEXT=\$\(/ { route = 1; next }
        route && /SESSION_KEY="\$\{CLAUDE_SESSION_ID:-default\}"/ { capture = 1 }
        capture {
          line = $0
          sub(/^[[:space:]]+/, "", line)
          print line
          if (index(line, "&& _phase_detect_cache_fresh && PD=$(cat \"$P\")") > 0) exit
        }
      ' "$PROJECT_ROOT/commands/vibe.md" > "$out"
      ;;
    verify)
      awk '
        /^### Mode: Verify$/ { route = 1 }
        route && /SESSION_KEY="\$\{CLAUDE_SESSION_ID:-default\}"/ { capture = 1 }
        capture {
          line = $0
          sub(/^[[:space:]]+/, "", line)
          print line
          if (line == "PD=\"phase_detect_error=true\"") ending = 1
          else if (ending && line == "fi") exit
        }
      ' "$PROJECT_ROOT/commands/vibe.md" > "$out"
      ;;
    *)
      return 1
      ;;
  esac
}

_assert_vibe_embedded_phase_state_blocks() {
  local td="$1"
  local root="$2"
  local expected="$3"
  local rejected="${4:-}"
  local block session link cache script

  for block in milestone verify; do
    session="vibe-embedded-${block}-$$-$RANDOM"
    link="/tmp/.vbw-plugin-root-link-${session}"
    cache="/tmp/.vbw-phase-detect-${session}.txt"
    script="$td/vibe-${block}-phase-state.sh"

    _track_tmp_test_path "$link"
    _track_tmp_test_path "$cache"
    ln -s "$root" "$link"
    printf '%s\n' 'phase_detect_error=true' > "$cache"
    touch -t 209912312359 "$cache"
    _extract_vibe_embedded_phase_state_block "$block" "$script"
    [ -s "$script" ]

    run env CLAUDE_SESSION_ID="$session" bash -c 'source "$1"; printf '\''%s\n'\'' "$PD"' _ "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$expected"* ]]
    if [ -n "$rejected" ]; then
      [[ "$output" != *"$rejected"* ]]
    fi
  done
}

@test "commands with phase-detect run it atomically in preamble" {
  for cmd in resume status discuss qa verify; do
    local count
    count=$(grep -cF "$(_atomic_pd_preamble_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing atomic phase-detect in preamble"; return 1; }
  done

  local phase_state="$PROJECT_ROOT/scripts/resolve-phase-state.sh"
  grep -q 'PTMP="${P}.tmp\.\$\$"' "$phase_state" || { echo "FAIL: resolve-phase-state.sh missing temp output path"; return 1; }
  grep -q 'bash "\$L/scripts/phase-detect.sh" > "\$PTMP"' "$phase_state" || { echo "FAIL: resolve-phase-state.sh missing temp-file phase-detect write"; return 1; }
  grep -q 'mv "\$PTMP" "\$P"' "$phase_state" || { echo "FAIL: resolve-phase-state.sh missing atomic phase-detect rename"; return 1; }
}

@test "commands with phase-detect preamble no longer use stamp file" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stamp_file_pattern)" "$PROJECT_ROOT/commands/${cmd}.md") || true
    [ "$count" -eq 0 ] || { echo "FAIL: ${cmd}.md still references phase-detect stamp file"; return 1; }
  done
}

@test "commands with phase-detect use guarded temp-file read fallback" {
  for cmd in resume status discuss qa verify; do
    local count
    count=$(grep -cF "$(_atomic_pd_temp_read_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing guarded phase-detect temp-file read"; return 1; }
  done

  local vibe_count
  vibe_count=$(grep -cF 'PD=$(cat "$P")' "$PROJECT_ROOT/commands/vibe.md" || true)
  [ "${vibe_count:-0}" -ge 1 ] || { echo 'FAIL: vibe.md missing guarded phase-detect temp-file read'; return 1; }
}

@test "commands with phase-detect treat error cache as cache miss" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_error_cache_bypass_pattern)" "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing error-cache bypass"; return 1; }
  done
}

@test "commands with phase-detect always re-run when plugin link exists" {
  for cmd in resume status vibe discuss qa verify; do
    local count
    count=$(grep -cF "$(_stale_cache_mtime_pattern)" "$PROJECT_ROOT/commands/${cmd}.md") || true
    [ "$count" -eq 0 ] || { echo "FAIL: ${cmd}.md still uses stale-cache mtime guard"; return 1; }
  done
}

@test "vibe phase-state readers require fresh cache before fallback" {
  local vibe="$PROJECT_ROOT/commands/vibe.md"
  local phase_state="$PROJECT_ROOT/scripts/resolve-phase-state.sh"
  local start_count fresh_count stat_count
  start_count=$(grep -h 'START_TS=$(date +%s\|start_ts=$(date +%s' "$vibe" "$phase_state" | wc -l | tr -d ' ')
  fresh_count=$(grep -h 'phase_detect_cache_fresh()' "$vibe" "$phase_state" | wc -l | tr -d ' ')
  stat_count=$(grep -h 'stat -c %Y "\$P"\|stat -f %m "\$P"' "$vibe" "$phase_state" | wc -l | tr -d ' ')
  [ "${start_count:-0}" -ge 3 ] || { echo 'FAIL: vibe phase-state readers missing invocation-start freshness guard'; return 1; }
  [ "${fresh_count:-0}" -ge 3 ] || { echo 'FAIL: vibe phase-state readers missing fresh-cache helper'; return 1; }
  [ "${stat_count:-0}" -ge 3 ] || { echo 'FAIL: vibe phase-state readers missing cache mtime freshness check'; return 1; }
}

@test "vibe phase-state readers use a shared live phase-detect lock" {
  local lock_count
  lock_count=$(grep -hF '/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock' \
    "$PROJECT_ROOT/commands/vibe.md" \
    "$PROJECT_ROOT/scripts/resolve-phase-state.sh" | wc -l | tr -d ' ')
  [ "${lock_count:-0}" -ge 3 ] || { echo 'FAIL: vibe phase-state readers missing shared live lock'; return 1; }
}

@test "vibe phase-state resolver uses the shared live lock" {
  grep -qF 'LOCK="/tmp/.vbw-phase-detect-live-${SESSION_KEY}.lock"' "$PROJECT_ROOT/scripts/resolve-phase-state.sh" || {
    echo 'FAIL: resolve-phase-state.sh missing shared phase-detect live lock';
    return 1;
  }
}

@test "commands with phase-detect define self-healing refresh helpers or guarded live reads" {
  for cmd in resume status discuss qa verify; do
    local count
    count=$(grep -cF '_refresh_phase_detect()' "$PROJECT_ROOT/commands/${cmd}.md")
    [ "$count" -ge 1 ] || { echo "FAIL: ${cmd}.md missing self-healing refresh helper"; return 1; }
  done

  local vibe_live_count
  vibe_live_count=$(grep -hF 'bash "$L/scripts/phase-detect.sh"' \
    "$PROJECT_ROOT/commands/vibe.md" \
    "$PROJECT_ROOT/scripts/resolve-phase-state.sh" | wc -l | tr -d ' ')
  [ "$vibe_live_count" -ge 3 ] || { echo "FAIL: vibe phase-state flow missing guarded live reads"; return 1; }
}

@test "vibe/verify secondary readers no longer use legacy empty-only fallback" {
  run bash -c "grep -nF '[ -z \"\$PD\" ] && [ -L \"\$L\" ] && [ -f \"\$L/scripts/phase-detect.sh\" ]' \"$PROJECT_ROOT/commands/vibe.md\" \"$PROJECT_ROOT/commands/verify.md\""
  [ "$status" -eq 1 ]
}

@test "reader bypasses error cache when live script is available" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/.vbw-plugin-root-link-test-live"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  : > "$root/scripts/hook-wrapper.sh"
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  echo "phase_detect_error=true" > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$root")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
  [[ "$out" != *"phase_detect_error=true"* ]]
}

@test "shared vibe phase-state resolver repairs sentinel cache without pre-existing link" {
  local td root script session link cache
  td=$(_new_tmp_test_dir)

  root="$td/root"
  script="$td/vibe-phase-state.sh"
  session="vibe-phase-live-$$-$RANDOM"
  link="/tmp/.vbw-plugin-root-link-${session}"
  cache="/tmp/.vbw-phase-detect-${session}.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'next_phase_state=fresh_live' 'phase_detect_complete=true'
EOF
  : > "$root/scripts/hook-wrapper.sh"
  _install_shared_resolver_fixture "$root"
  chmod +x "$root/scripts/phase-detect.sh" "$root/scripts/ensure-plugin-root-link.sh"

  printf '%s\n' 'phase_detect_error=true' > "$cache"
  touch -t 209912312359 "$cache"

  _track_tmp_test_path "$link"
  _track_tmp_test_path "$cache"
  _copy_vibe_phase_state_resolver "$script"
  [ -s "$script" ]

  run env CLAUDE_SESSION_ID="$session" CLAUDE_PLUGIN_ROOT="$root" bash "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"next_phase_state=fresh_live"* ]]
  [[ "$output" != *"phase_detect_error=true"* ]]
  [ -L "$link" ]
}

@test "shared vibe phase-state resolver fails closed when live refresh returns error sentinel" {
  local td root script session link cache
  td=$(_new_tmp_test_dir)

  root="$td/root"
  script="$td/vibe-phase-state.sh"
  session="vibe-phase-fail-$$-$RANDOM"
  link="/tmp/.vbw-plugin-root-link-${session}"
  cache="/tmp/.vbw-phase-detect-${session}.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "phase_detect_error=true"
EOF
  : > "$root/scripts/hook-wrapper.sh"
  _install_shared_resolver_fixture "$root"
  chmod +x "$root/scripts/phase-detect.sh" "$root/scripts/ensure-plugin-root-link.sh"

  printf '%s\n' 'phase_detect_error=true' > "$cache"
  touch -t 209912312359 "$cache"

  _track_tmp_test_path "$link"
  _track_tmp_test_path "$cache"
  _copy_vibe_phase_state_resolver "$script"
  [ -s "$script" ]

  run env CLAUDE_SESSION_ID="$session" CLAUDE_PLUGIN_ROOT="$root" bash "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"phase_detect_error=true"* ]]
  [[ "$output" != *"next_phase_state=fresh_live"* ]]
  [ -L "$link" ]
}

@test "vibe.md embedded phase-state blocks repair sentinel cache with live refresh" {
  local td root
  td=$(_new_tmp_test_dir)

  root="$td/root"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'next_phase_state=fresh_live' 'phase_detect_complete=true'
EOF
  : > "$root/scripts/hook-wrapper.sh"
  _install_shared_resolver_fixture "$root"
  chmod +x "$root/scripts/phase-detect.sh" "$root/scripts/ensure-plugin-root-link.sh"

  _assert_vibe_embedded_phase_state_blocks \
    "$td" "$root" "next_phase_state=fresh_live" "phase_detect_error=true"
}

@test "vibe.md embedded phase-state blocks fail closed on live error sentinel" {
  local td root
  td=$(_new_tmp_test_dir)

  root="$td/root"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "phase_detect_error=true"
EOF
  : > "$root/scripts/hook-wrapper.sh"
  _install_shared_resolver_fixture "$root"
  chmod +x "$root/scripts/phase-detect.sh" "$root/scripts/ensure-plugin-root-link.sh"

  _assert_vibe_embedded_phase_state_blocks \
    "$td" "$root" "phase_detect_error=true" "next_phase_state=fresh_live"
}

@test "reader refreshes without pre-existing link when fallback root is available" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/.vbw-plugin-root-link-test-refresh"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_without_link"
EOF
  : > "$root/scripts/hook-wrapper.sh"
  chmod +x "$root/scripts/phase-detect.sh"

  echo "phase_detect_error=true" > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$root")
  [[ "$out" == *"next_phase_state=fresh_without_link"* ]]
  [ -L "$link" ]
}

@test "reader refreshes stale valid cache when live script is available" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/.vbw-plugin-root-link-test-stale"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
echo "next_phase_state=fresh_live"
EOF
  : > "$root/scripts/hook-wrapper.sh"
  chmod +x "$root/scripts/phase-detect.sh"

  echo "next_phase_state=stale_cache" > "$cache"
  ln -s "$root" "$link"

  out=$(_simulate_phase_detect_reader "$link" "$cache" "$root")
  [[ "$out" == *"next_phase_state=fresh_live"* ]]
}

@test "reader fails closed when cache is valid but no live resolver is available" {
  local td cache out
  td=$(_new_tmp_test_dir)

  cache="$td/pd.txt"
  echo "next_phase_state=cached_ok" > "$cache"

  _simulate_phase_detect_reader "$td/.vbw-plugin-root-link-test-missing" "$cache" > "$td/out.txt"
  out=$(cat "$td/out.txt")

  [[ "$out" == "phase_detect_error=true" ]]
}

@test "reader treats whitespace-only output as error" {
  local td root link cache out
  td=$(_new_tmp_test_dir)

  root="$td/root"
  link="$td/.vbw-plugin-root-link-test-whitespace"
  cache="$td/pd.txt"
  mkdir -p "$root/scripts"

  cat > "$root/scripts/phase-detect.sh" <<'EOF'
#!/usr/bin/env bash
printf '   \n\n'
EOF
  : > "$root/scripts/hook-wrapper.sh"
  chmod +x "$root/scripts/phase-detect.sh"

  ln -s "$root" "$link"
  : > "$cache"

  out=$(_simulate_phase_detect_reader "$link" "$cache")
  [[ "$out" == "phase_detect_error=true" ]]
}

@test "vibe phase-state flow uses self-healing live read with temp-file fallback" {
  local vibe="$PROJECT_ROOT/commands/vibe.md"
  local phase_state="$PROJECT_ROOT/scripts/resolve-phase-state.sh"
  local cat_count
  cat_count=$(grep -hF 'cat "$P"' "$vibe" "$phase_state" | wc -l | tr -d ' ')
  [ "${cat_count:-0}" -ge 1 ] || { echo "FAIL: vibe phase-state flow missing temp-file fallback"; return 1; }

  local live_count
  live_count=$(grep -hF 'bash "$L/scripts/phase-detect.sh"' "$vibe" "$phase_state" | wc -l | tr -d ' ')
  [ "$live_count" -ge 3 ] || { echo "FAIL: vibe phase-state flow missing live reads"; return 1; }
}

@test "verify.md bans automated test commands in UAT scenarios" {
  grep -q 'NEVER generate tests that ask the user to run automated checks' "$PROJECT_ROOT/commands/verify.md"
}

@test "verify.md lists automated test tools as excluded from UAT" {
  grep -q 'xcodebuild test, pytest, bats, jest' "$PROJECT_ROOT/commands/verify.md"
}

@test "shared resolver validates candidates by required script" {
  grep -Fq '[ -f "$candidate/scripts/$required_script" ]' "$PROJECT_ROOT/scripts/resolve-plugin-root.sh"
  for cmd in verify discuss help qa skills; do
    grep -Fq 'resolve-plugin-root.sh' "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md missing shared resolver delegation"; return 1; }
  done
  grep -Fq 'resolve-phase-state.sh' "$PROJECT_ROOT/commands/vibe.md"
  grep -Fq 'resolve-plugin-root.sh' "$PROJECT_ROOT/scripts/resolve-phase-state.sh"
}

@test "command trampolines do NOT use bare [ -d ] for local/ acceptance" {
  for cmd in vibe verify discuss help qa skills; do
    run bash -c "grep 'elif \\[ -d.*VBW_CACHE_ROOT.*local' \"$PROJECT_ROOT/commands/${cmd}.md\" 2>/dev/null"
    [ "$status" -eq 1 ] || { echo "FAIL: ${cmd}.md still has bare [ -d ] local/ check"; return 1; }
  done
}

@test "shared resolver owns process-tree fallback" {
  grep -Fq 'ps axww -o args=' "$PROJECT_ROOT/scripts/resolve-plugin-root.sh"
  run bash -c "grep -nF 'ps axww -o args=' \"$PROJECT_ROOT\"/commands/{vibe,verify,discuss,help,qa,skills}.md"
  [ "$status" -eq 1 ]
}

@test "shared resolver owns canonical pwd -P resolution" {
  grep -Fq 'canonical_root=$(cd "$resolved_root" 2>/dev/null && pwd -P)' \
    "$PROJECT_ROOT/scripts/resolve-plugin-root.sh"
  for cmd in config debug discuss doctor fix help init map qa report research resume rtk skills status update verify whats-new; do
    grep -Fq 'resolve-plugin-root.sh' "$PROJECT_ROOT/commands/${cmd}.md" || \
      { echo "FAIL: ${cmd}.md missing shared resolver delegation"; return 1; }
  done
  grep -Fq 'resolve-phase-state.sh' "$PROJECT_ROOT/commands/vibe.md"
  grep -Fq 'resolve-plugin-root.sh' "$PROJECT_ROOT/scripts/resolve-phase-state.sh"
}

@test "shared resolver repairs links with canonical_root" {
  grep -Fq 'bash "$canonical_root/scripts/ensure-plugin-root-link.sh"' \
    "$PROJECT_ROOT/scripts/resolve-plugin-root.sh"
  grep -Fq '"$session_link" "$canonical_root"' "$PROJECT_ROOT/scripts/resolve-plugin-root.sh"
}
