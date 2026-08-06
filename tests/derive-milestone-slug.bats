#!/usr/bin/env bats

load test_helper

setup() {
  setup_temp_dir
  cd "$TEST_TEMP_DIR"
  mkdir -p .vbw-planning/phases
}

teardown() {
  cd "$PROJECT_ROOT"
  teardown_temp_dir
}

@test "derives slug from Phase N header format" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: Transfer Matching Bug Fix
Goal: Fix transfer matching

## Phase 2: Test Infrastructure
Goal: Build test suite
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-transfer-matching-bug-fix-test-infrastructure" ]
}

@test "derives slug from numbered bold list format" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

1. **Setup Foundation** - scaffold project
2. **API Layer** - build endpoints
3. **Frontend** - build UI
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-setup-foundation-api-layer-frontend" ]
}

@test "normalizes Unicode dash separators in numbered lists" {
  printf '%s\n' \
    'Roadmap' \
    '' \
    $'1. **Setup Foundation** \xE2\x80\x94 scaffold project' \
    $'2. **API Layer** \xE2\x80\x93 build endpoints' \
    > .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-setup-foundation-api-layer" ]
}

@test "derives slug from bulleted phase list" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

- Phase 1: Core Models
- Phase 2: Service Layer
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-core-models-service-layer" ]
}

@test "uses explicit milestone from STATE.md before ROADMAP phases" {
  cat > .vbw-planning/STATE.md <<'EOF'
State

**Milestone:** Scientific Research Backend v1
EOF
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

- [ ] Phase 1: Wrong Roadmap Name
- [x] Phase 2: Also Wrong
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-scientific-research-backend-v1" ]
}

@test "falls back to ROADMAP when STATE.md has no milestone" {
  cat > .vbw-planning/STATE.md <<'EOF'
State

**Project:** Example
EOF
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: Roadmap Fallback
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-roadmap-fallback" ]
}

@test "derives clean slug from checkbox phase list" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

- [ ] Phase 1: Core Models
- [x] Service Layer
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-core-models-service-layer" ]
}

@test "falls back to phase directory names" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap
No standard phase format here.
EOF
  mkdir -p .vbw-planning/phases/01-setup
  mkdir -p .vbw-planning/phases/02-api

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-setup-api" ]
}

@test "falls back to timestamp when no phases found" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap
Nothing parseable here.
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^01-milestone-[0-9]{8}$ ]]
}

@test "truncates slug to 60 chars" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: This Is A Very Long Phase Name That Should Be Truncated
## Phase 2: Another Extremely Long Phase Name For Testing Purposes
## Phase 3: Yet Another Phase With An Absurdly Long Name Here
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ ${#output} -le 63 ]
}

@test "numbers based on existing milestones" {
  mkdir -p .vbw-planning/milestones/01-first
  mkdir -p .vbw-planning/milestones/02-second
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: Third Feature
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "03-third-feature" ]
}

@test "handles collision with existing milestone" {
  mkdir -p .vbw-planning/milestones/01-setup
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: Setup
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "02-setup" ]
}

@test "handles collision when exact target dir exists" {
  mkdir -p .vbw-planning/milestones/01-setup
  rm -rf .vbw-planning/milestones/01-setup

  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: Setup
EOF

  mkdir -p .vbw-planning/milestones/01-setup

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "02-setup" ]
}

@test "fails when no ROADMAP.md exists" {
  rm -f .vbw-planning/ROADMAP.md

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 1 ]
}

@test "limits to first 3 phase names" {
  cat > .vbw-planning/ROADMAP.md <<'EOF'
Roadmap

## Phase 1: First
## Phase 2: Second
## Phase 3: Third
## Phase 4: Fourth
## Phase 5: Fifth
EOF

  run bash "$SCRIPTS_DIR/derive-milestone-slug.sh" ".vbw-planning"
  [ "$status" -eq 0 ]
  [ "$output" = "01-first-second-third" ]
}
