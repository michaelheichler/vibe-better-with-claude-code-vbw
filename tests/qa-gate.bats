#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  git init --quiet
  git config user.email test@test.com
  git config user.name test
  touch tracked
  git add tracked
  git commit --quiet -m 'test(00-00): fixture'
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

make_phase() {
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/$1"
  mkdir -p "$phase_dir"
  touch "$phase_dir/$2-PLAN.md"
  printf '%s\n' '---' "status: $3" '---' > "$phase_dir/$2-SUMMARY.md"
  if [ "$3" = partial ] && [ "${4:-}" = extra-plan ]; then
    touch "$phase_dir/01-02-PLAN.md"
  fi
}

make_support_copy() {
  local source_dir="$PROJECT_ROOT/scripts"
  local target_dir="$TEST_TEMP_DIR/gate-scripts"
  mkdir -p "$target_dir/lib"
  cp "$source_dir/qa-gate.sh" "$target_dir/"
  cp "$source_dir/summary-utils.sh" "$target_dir/"
  cp "$source_dir/verification-freshness.sh" "$target_dir/"
  cp "$source_dir/lib/phase-detect-support.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-path-evidence.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-fail-classifications.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-known-issues.sh" "$target_dir/lib/"
  cp "$source_dir/lib/qa-result-gate-summary-deviations.sh" "$target_dir/lib/"
  cp "$source_dir/lib/track-known-issues-parsers.sh" "$target_dir/lib/"
  cat > "$target_dir/resolve-verification-path.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s/remediation/qa/round-01/R01-VERIFICATION.md\n' "$2"
EOF
  cat > "$target_dir/qa-result-gate.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'qa_gate_routing=PROCEED_TO_UAT'
EOF
  cat > "$target_dir/track-known-issues.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$target_dir"/*.sh
}

@test "fully complete phase counts as satisfied" {
  make_phase 01-complete 01-01 complete

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$PROJECT_ROOT/scripts/qa-gate.sh"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "remediation-resolved partial phase counts as satisfied" {
  make_phase 01-remediated 01-01 partial
  local phase_dir="$TEST_TEMP_DIR/.vbw-planning/phases/01-remediated"
  mkdir -p "$phase_dir/remediation/qa/round-01"
  printf '%s\n' stage=done round=01 > "$phase_dir/remediation/qa/.qa-remediation-stage"
  local commit
  commit=$(git rev-parse HEAD)
  cat > "$phase_dir/remediation/qa/round-01/R01-VERIFICATION.md" <<EOF
---
result: PASS
verified_at_commit: $commit
writer: write-verification.sh
---
EOF
  make_support_copy

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "unresolved partial phase does not count" {
  make_phase 01-partial 01-01 partial extra-plan

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$PROJECT_ROOT/scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"0 summaries for 2 plans"* ]]
}

@test "missing phase support degrades to the flat count path" {
  mkdir -p "$TEST_TEMP_DIR/gate-scripts"
  cp "$PROJECT_ROOT/scripts/qa-gate.sh" "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"
  make_phase 01-partial 01-01 partial extra-plan

  run env VBW_PLANNING_DIR="$TEST_TEMP_DIR/.vbw-planning" bash "$TEST_TEMP_DIR/gate-scripts/qa-gate.sh"

  [ "$status" -eq 2 ]
  [[ "$output" == *"0 summaries for 2 plans"* ]]
}
