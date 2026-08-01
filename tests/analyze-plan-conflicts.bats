#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  PHASE_DIR="$TEST_TEMP_DIR/01-test"
  mkdir -p "$PHASE_DIR"
}

teardown() {
  teardown_temp_dir
}

@test "reports shared files and deterministic disjoint groups" {
  cat > "$PHASE_DIR/01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
files_touched: [scripts/a.sh, scripts/shared.sh]
---
PLAN
  cat > "$PHASE_DIR/01-02-PLAN.md" <<'PLAN'
---
phase: 1
plan: 2
files_touched:
  - scripts/shared.sh
  - scripts/b.sh
---
PLAN
  cat > "$PHASE_DIR/01-03-PLAN.md" <<'PLAN'
---
phase: 1
plan: 3
files_touched: [scripts/c.sh]
---
PLAN

  run bash "$SCRIPTS_DIR/analyze-plan-conflicts.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "conflict_pairs=01-01:01-02" ]
  [ "${lines[1]}" = "disjoint_groups=01-01|01-03;01-02" ]
  [ "${lines[2]}" = "plans_missing_files_touched=" ]
}

@test "treats a missing files_touched field as conflicting with every plan" {
  cat > "$PHASE_DIR/01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
files_touched: [scripts/a.sh]
---
PLAN
  cat > "$PHASE_DIR/01-02-PLAN.md" <<'PLAN'
---
phase: 1
plan: 2
---
PLAN
  cat > "$PHASE_DIR/01-03-PLAN.md" <<'PLAN'
---
phase: 1
plan: 3
files_touched: [scripts/c.sh]
---
PLAN

  run bash "$SCRIPTS_DIR/analyze-plan-conflicts.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "conflict_pairs=01-01:01-02,01-02:01-03" ]
  [ "${lines[1]}" = "disjoint_groups=01-01|01-03;01-02" ]
  [ "${lines[2]}" = "plans_missing_files_touched=01-02" ]
}

@test "accepts an empty files_touched array as declared and disjoint" {
  cat > "$PHASE_DIR/01-01-PLAN.md" <<'PLAN'
---
phase: 1
plan: 1
files_touched: []
---
PLAN
  cat > "$PHASE_DIR/01-02-PLAN.md" <<'PLAN'
---
phase: 1
plan: 2
files_touched: [scripts/a.sh]
---
PLAN

  run bash "$SCRIPTS_DIR/analyze-plan-conflicts.sh" "$PHASE_DIR"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "conflict_pairs=" ]
  [ "${lines[1]}" = "disjoint_groups=01-01|01-02" ]
  [ "${lines[2]}" = "plans_missing_files_touched=" ]
}

@test "fails for an unreadable phase directory" {
  run bash "$SCRIPTS_DIR/analyze-plan-conflicts.sh" "$TEST_TEMP_DIR/missing"

  [ "$status" -eq 1 ]
  [[ "$output" == error=unreadable_phase_dir:* ]]
}
