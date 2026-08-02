pass() {
  echo "PASS  $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "FAIL  $1"
  FAIL=$((FAIL + 1))
}

RUNTIME_HELPER_TEST_ROOT=$(mktemp -d)
trap 'rm -rf "${RUNTIME_HELPER_TEST_ROOT:-}"' EXIT

write_runtime_skill_fixture() {
  local base_dir="$1" skill_name="$2" rel_name="$3" body_text="$4"
  write_runtime_skill_fixture_with_body "$base_dir" "$skill_name" "$(cat <<EOF
Skill details: [${rel_name%.md}](references/${rel_name})
EOF
)" "references/$rel_name=$body_text"
}

write_runtime_skill_fixture_with_body() {
  local base_dir="$1" skill_name="$2" skill_body="$3"
  shift 3
  mkdir -p "$base_dir/$skill_name/references"
  printf '%s\n' "$skill_body" > "$base_dir/$skill_name/SKILL.md"
  while [ "$#" -gt 0 ]; do
    local fixture_spec="$1" rel_path body_text
    shift
    if [[ "$fixture_spec" == */ ]]; then
      mkdir -p "$base_dir/$skill_name/$fixture_spec"
      continue
    fi
    rel_path="${fixture_spec%%=*}"
    body_text="${fixture_spec#*=}"
    mkdir -p "$(dirname "$base_dir/$skill_name/$rel_path")"
    printf '%s\n' "$body_text" > "$base_dir/$skill_name/$rel_path"
  done
}

assert_empty_output() {
  local output="$1" pass_label="$2" fail_label="$3"
  if [ -z "$output" ]; then pass "$pass_label"; else fail "$fail_label"; fi
}

assert_output_contains() {
  local output="$1" needle="$2" pass_label="$3" fail_label="$4"
  if [[ "$output" == *"$needle"* ]]; then pass "$pass_label"; else fail "$fail_label"; fi
}

assert_output_excludes() {
  local output="$1" pass_label="$2" fail_label="$3"
  shift 3
  local needle
  for needle in "$@"; do
    if [[ "$output" == *"$needle"* ]]; then fail "$fail_label"; return; fi
  done
  pass "$pass_label"
}

setup_runtime_guard_paths() {
  rm -rf "$RUNTIME_HELPER_TEST_ROOT"
  RUNTIME_GUARD_PROJECT_DIR="$RUNTIME_HELPER_TEST_ROOT/project"
  RUNTIME_GUARD_HOME_DIR="$RUNTIME_HELPER_TEST_ROOT/home"
  RUNTIME_GUARD_GLOBAL_PROJECT_DIR="$RUNTIME_HELPER_TEST_ROOT/global-project"
  RUNTIME_GUARD_OUTSIDE_DIR="$RUNTIME_HELPER_TEST_ROOT/outside"
  RUNTIME_GUARD_HELPER="$ROOT/scripts/extract-skill-follow-up-files.sh"
  mkdir -p "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" "$RUNTIME_GUARD_GLOBAL_PROJECT_DIR" \
    "$RUNTIME_GUARD_HOME_DIR/.claude/skills" "$RUNTIME_GUARD_OUTSIDE_DIR"
}

setup_runtime_guard_decoys() {
  write_runtime_skill_fixture "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" swiftdata local-good.md "Local good reference content"
  write_runtime_skill_fixture "$RUNTIME_GUARD_PROJECT_DIR/.agents/skills" swiftdata agents-bad.md "Agents bad reference content"
  write_runtime_skill_fixture "$RUNTIME_GUARD_PROJECT_DIR/.pi/skills" swiftdata pi-bad.md "Pi bad reference content"
  write_runtime_skill_fixture "$RUNTIME_GUARD_HOME_DIR/.agents/skills" swiftdata home-agents-bad.md "Home agents bad reference content"
}

setup_project_confinement_fixtures() {
  write_runtime_skill_fixture_with_body "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" confined-skill "$(cat <<'EOF'
Skill details: [safe](references/local-good.md)
Skill details: [normalized](docs/../references/normalized-good.md)
Skill details: [escape](../other-skill/references/secret.md)
EOF
)" \
    "references/local-good.md=Confined local reference" \
    "references/normalized-good.md=Normalized local reference" \
    "docs/"
  write_runtime_skill_fixture "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" other-skill secret.md "Project secret reference"
  write_runtime_skill_fixture_with_body "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" no-links-skill "This skill has no markdown links."
}

setup_global_confinement_fixtures() {
  write_runtime_skill_fixture_with_body "$RUNTIME_GUARD_HOME_DIR/.claude/skills" global-skill "$(cat <<'EOF'
Skill details: [safe](references/global-good.md)
Skill details: [normalized](docs/../references/global-normalized.md)
Skill details: [escape](../other-skill/references/global-secret.md)
EOF
)" \
    "references/global-good.md=Global safe reference" \
    "references/global-normalized.md=Global normalized reference" \
    "docs/"
  write_runtime_skill_fixture "$RUNTIME_GUARD_HOME_DIR/.claude/skills" other-skill global-secret.md "Global secret reference"
}

setup_project_symlink_fixture() {
  write_runtime_skill_fixture_with_body "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills" symlink-skill "$(cat <<'EOF'
Skill details: [safe](references/local-good.md)
Skill details: [symlink](references/linked-outside.md)
EOF
)" "references/local-good.md=Project symlink safe reference"
  printf '%s\n' 'Project symlink outside content' > "$RUNTIME_GUARD_OUTSIDE_DIR/project-secret.md"
  ln -s "$RUNTIME_GUARD_OUTSIDE_DIR/project-secret.md" \
    "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills/symlink-skill/references/linked-outside.md"
}

setup_global_symlink_fixture() {
  write_runtime_skill_fixture_with_body "$RUNTIME_GUARD_HOME_DIR/.claude/skills" global-symlink-skill "$(cat <<'EOF'
Skill details: [safe](references/global-good.md)
Skill details: [symlink](references/linked-outside.md)
EOF
)" "references/global-good.md=Global symlink safe reference"
  printf '%s\n' 'Global symlink outside content' > "$RUNTIME_GUARD_OUTSIDE_DIR/global-secret.md"
  ln -s "$RUNTIME_GUARD_OUTSIDE_DIR/global-secret.md" \
    "$RUNTIME_GUARD_HOME_DIR/.claude/skills/global-symlink-skill/references/linked-outside.md"
}

run_runtime_guard_helper() {
  local project_dir="$1"
  shift
  HOME="$RUNTIME_GUARD_HOME_DIR" CLAUDE_CONFIG_DIR="$RUNTIME_GUARD_HOME_DIR/.claude" \
    bash "$RUNTIME_GUARD_HELPER" --project-dir "$project_dir" "$@" 2>/dev/null
}

capture_runtime_guard_output() {
  local output_name="$1"
  local context="$2"
  shift 2
  local captured_output
  if ! captured_output=$(run_runtime_guard_helper "$@"); then
    fail "$context: helper exited nonzero"
    return 1
  fi
  printf -v "$output_name" '%s' "$captured_output"
}

verify_runtime_traversal_guards() {
  local project_output global_output mixed_output
  capture_runtime_guard_output project_output \
    "scripts/extract-skill-follow-up-files.sh: project traversal guard helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" ../../.agents/skills/swiftdata ../../.pi/skills/swiftdata || return 1

  assert_empty_output "$project_output" \
    "scripts/extract-skill-follow-up-files.sh: rejects traversal into project lookalike roots at runtime" \
    "scripts/extract-skill-follow-up-files.sh: traversal into project lookalike roots still produces runtime output"
  capture_runtime_guard_output global_output \
    "scripts/extract-skill-follow-up-files.sh: global traversal guard helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" ../../.agents/skills/swiftdata || return 1
  assert_empty_output "$global_output" \
    "scripts/extract-skill-follow-up-files.sh: rejects traversal into HOME/.agents at runtime" \
    "scripts/extract-skill-follow-up-files.sh: traversal into HOME/.agents still produces runtime output"
  capture_runtime_guard_output mixed_output \
    "scripts/extract-skill-follow-up-files.sh: mixed traversal guard helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" "swiftdata ../../.agents/skills/swiftdata" || return 1
  assert_output_contains "$mixed_output" "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills/swiftdata/references/local-good.md" \
    "scripts/extract-skill-follow-up-files.sh: preserves valid skills alongside invalid traversal tokens" \
    "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input lost the valid skill"
  assert_output_excludes "$mixed_output" \
    "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input does not leak decoy roots" \
    "scripts/extract-skill-follow-up-files.sh: mixed valid+invalid runtime input still leaked a decoy root" \
    agents-bad.md pi-bad.md home-agents-bad.md
}

verify_project_confinement() {
  local output
  capture_runtime_guard_output output \
    "scripts/extract-skill-follow-up-files.sh: project confinement helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" confined-skill || return 1
  assert_output_contains "$output" "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills/confined-skill/references/local-good.md" \
    "scripts/extract-skill-follow-up-files.sh: keeps in-tree project follow-up links" \
    "scripts/extract-skill-follow-up-files.sh: lost an in-tree project follow-up link"
  assert_output_contains "$output" "$RUNTIME_GUARD_PROJECT_DIR/.claude/skills/confined-skill/references/normalized-good.md" \
    "scripts/extract-skill-follow-up-files.sh: keeps normalized project follow-up links" \
    "scripts/extract-skill-follow-up-files.sh: lost a normalized project follow-up link"
  assert_output_excludes "$output" \
    "scripts/extract-skill-follow-up-files.sh: project SKILL.md traversal cannot escape into a sibling skill" \
    "scripts/extract-skill-follow-up-files.sh: project SKILL.md traversal escaped into a sibling skill" \
    other-skill/references/secret.md
}

verify_global_confinement() {
  local output
  capture_runtime_guard_output output \
    "scripts/extract-skill-follow-up-files.sh: global confinement helper failed" \
    "$RUNTIME_GUARD_GLOBAL_PROJECT_DIR" global-skill || return 1
  assert_output_contains "$output" "$RUNTIME_GUARD_HOME_DIR/.claude/skills/global-skill/references/global-good.md" \
    "scripts/extract-skill-follow-up-files.sh: keeps in-tree global follow-up links" \
    "scripts/extract-skill-follow-up-files.sh: lost an in-tree global follow-up link"
  assert_output_contains "$output" "$RUNTIME_GUARD_HOME_DIR/.claude/skills/global-skill/references/global-normalized.md" \
    "scripts/extract-skill-follow-up-files.sh: keeps normalized global follow-up links" \
    "scripts/extract-skill-follow-up-files.sh: lost a normalized global follow-up link"
  assert_output_excludes "$output" \
    "scripts/extract-skill-follow-up-files.sh: global SKILL.md traversal cannot escape into a sibling skill" \
    "scripts/extract-skill-follow-up-files.sh: global SKILL.md traversal escaped into a sibling skill" \
    other-skill/references/global-secret.md
}

verify_runtime_no_links() {
  local output
  capture_runtime_guard_output output \
    "scripts/extract-skill-follow-up-files.sh: no-links helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" no-links-skill || return 1
  assert_empty_output "$output" \
    "scripts/extract-skill-follow-up-files.sh: skills with no markdown links exit cleanly with no output" \
    "scripts/extract-skill-follow-up-files.sh: no-link skills should emit no output"
}

verify_project_symlink_guard() {
  local output
  capture_runtime_guard_output output \
    "scripts/extract-skill-follow-up-files.sh: project symlink helper failed" \
    "$RUNTIME_GUARD_PROJECT_DIR" symlink-skill || return 1
  assert_output_contains "$output" symlink-skill/references/local-good.md \
    "scripts/extract-skill-follow-up-files.sh: project symlink fixture still emits safe in-tree files" \
    "scripts/extract-skill-follow-up-files.sh: project symlink fixture lost the safe in-tree file"
  assert_output_excludes "$output" \
    "scripts/extract-skill-follow-up-files.sh: project symlinked follow-up path is rejected" \
    "scripts/extract-skill-follow-up-files.sh: project symlinked follow-up path escaped the active skill directory" \
    linked-outside.md
}

verify_global_symlink_guard() {
  local output
  capture_runtime_guard_output output \
    "scripts/extract-skill-follow-up-files.sh: global symlink helper failed" \
    "$RUNTIME_GUARD_GLOBAL_PROJECT_DIR" global-symlink-skill || return 1
  assert_output_contains "$output" global-symlink-skill/references/global-good.md \
    "scripts/extract-skill-follow-up-files.sh: global symlink fixture still emits safe in-tree files" \
    "scripts/extract-skill-follow-up-files.sh: global symlink fixture lost the safe in-tree file"
  assert_output_excludes "$output" \
    "scripts/extract-skill-follow-up-files.sh: global symlinked follow-up path is rejected" \
    "scripts/extract-skill-follow-up-files.sh: global symlinked follow-up path escaped the active skill directory" \
    linked-outside.md
}

verify_runtime_skill_root_guard() {
  setup_runtime_guard_paths
  setup_runtime_guard_decoys
  setup_project_confinement_fixtures
  setup_global_confinement_fixtures
  setup_project_symlink_fixture
  setup_global_symlink_fixture
  verify_runtime_traversal_guards
  verify_project_confinement
  verify_global_confinement
  verify_runtime_no_links
  verify_project_symlink_guard
  verify_global_symlink_guard
}
