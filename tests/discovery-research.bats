#!/usr/bin/env bats

setup() {
  export TEST_DIR=$(mktemp -d)
  mkdir -p "$TEST_DIR/.vbw-planning"
  export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "domain-research.md has 4 required sections" {
  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Feature 1
- Feature 2

## Common Pitfalls
- Pitfall 1

## Architecture Patterns
- Pattern 1

## Competitor Landscape
- Competitor 1: feature
EOF

  run grep -c "^## Table Stakes" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  run grep -c "^## Common Pitfalls" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Architecture Patterns" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]

  run grep -c "^## Competitor Landscape" "$TEST_DIR/.vbw-planning/domain-research.md"
  [ "$output" -eq 1 ]
}

@test "bootstrap-requirements.sh renders object-shaped answered requirement with research" {
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":[{"question":"Test","answer":"Answer","category":"scope","phase":"bootstrap","date":"2026-02-13"}],"inferred":[]}
EOF

  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Authentication

## Common Pitfalls
- Poor error handling

## Architecture Patterns
- REST API

## Competitor Landscape
- Competitor A: feature X
EOF

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json" \
    "$TEST_DIR/.vbw-planning/domain-research.md"

  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" ]
  run grep -F "### REQ-01: Answer" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]
}

@test "bootstrap-requirements.sh renders answered string without inferred requirements" {
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":["Export CSV reports"],"inferred":[]}
EOF

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json"

  [ "$status" -eq 0 ]
  run grep -F "### REQ-01: Export CSV reports" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]
  run grep -F "_(No requirements defined yet)_" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 1 ]
}

@test "bootstrap-requirements.sh renders mixed requirements with contiguous ids" {
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":["Export CSV reports","Schedule weekly reports"],"inferred":[{"text":"Filter reports by date","priority":"Should-have"}]}
EOF

  run bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json"

  [ "$status" -eq 0 ]
  run grep -F "### REQ-01: Export CSV reports" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]
  run grep -F "### REQ-02: Schedule weekly reports" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]
  run grep -F "### REQ-03: Filter reports by date" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$status" -eq 0 ]
  run grep -c "^### REQ-" "$TEST_DIR/.vbw-planning/REQUIREMENTS.md"
  [ "$output" -eq 3 ]
}

@test "discovery.json includes research_summary field" {
  cat > "$TEST_DIR/.vbw-planning/discovery.json" <<EOF
{"answered":[],"inferred":[]}
EOF

  cat > "$TEST_DIR/.vbw-planning/domain-research.md" <<EOF
## Table Stakes
- Feature

## Common Pitfalls
- Pitfall

## Architecture Patterns
- Pattern

## Competitor Landscape
- Competitor
EOF

  bash "$CLAUDE_PLUGIN_ROOT/scripts/bootstrap/bootstrap-requirements.sh" \
    "$TEST_DIR/.vbw-planning/REQUIREMENTS.md" \
    "$TEST_DIR/.vbw-planning/discovery.json" \
    "$TEST_DIR/.vbw-planning/domain-research.md"

  run jq -e '.research_summary.available' "$TEST_DIR/.vbw-planning/discovery.json"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
