#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_URL="https://raw.githubusercontent.com/michaelheichler/vibe-better-with-claude-code-vbw/main/VERSION"

FILES=(
  "$ROOT/VERSION"
  "$ROOT/.claude-plugin/plugin.json"
  "$ROOT/.claude-plugin/marketplace.json"
  "$ROOT/marketplace.json"
)

usage() {
  cat <<'EOF'
Usage: bump-version.sh [MODE]

Modes:
  (none)          Auto-increment the patch version (default). Fetches the
                   authoritative version from GitHub, falls back to the
                   local VERSION file on failure, then writes NEW to all
                   4 version files.
  --offline       Same as the default, but skips the GitHub fetch entirely.
  --set X.Y.Z     Write an explicit semver (e.g. 2.1.0) to all 4 version
                   files. No fetch, no auto-increment.
  --verify        Check that all 4 version files agree without writing
                   anything. Exits 1 on mismatch.
  --help, -h      Print this usage summary and exit 0.

Examples:
  bump-version.sh
  bump-version.sh --offline
  bump-version.sh --set 2.0.0
  bump-version.sh --verify
EOF
}

# write_version NEW: write the given version string to all 4 version files
write_version() {
  local new="$1"

  printf '%s\n' "$new" > "$ROOT/VERSION"

  jq --arg v "$new" '.version = $v' "$ROOT/.claude-plugin/plugin.json" > "$ROOT/.claude-plugin/plugin.json.tmp" \
    && mv "$ROOT/.claude-plugin/plugin.json.tmp" "$ROOT/.claude-plugin/plugin.json"

  jq --arg v "$new" '.plugins[0].version = $v' "$ROOT/.claude-plugin/marketplace.json" > "$ROOT/.claude-plugin/marketplace.json.tmp" \
    && mv "$ROOT/.claude-plugin/marketplace.json.tmp" "$ROOT/.claude-plugin/marketplace.json"

  jq --arg v "$new" '.plugins[0].version = $v' "$ROOT/marketplace.json" > "$ROOT/marketplace.json.tmp" \
    && mv "$ROOT/marketplace.json.tmp" "$ROOT/marketplace.json"

  echo "Updated 4 files:"
  for f in "${FILES[@]}"; do
    echo "  ${f#$ROOT/}"
  done
  echo ""
  echo "Version is now $new"
}

MODE="${1:-}"

case "$MODE" in
  ""|--verify|--offline)
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  --set)
    SET_VERSION="${2:-}"
    if [[ -z "$SET_VERSION" ]]; then
      echo "Error: --set requires a version argument (e.g. --set 2.0.0)" >&2
      echo "" >&2
      usage >&2
      exit 1
    fi
    if [[ ! "$SET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Error: --set version '$SET_VERSION' is not a valid semver (expected X.Y.Z)" >&2
      echo "" >&2
      usage >&2
      exit 1
    fi
    echo "Setting version to: $SET_VERSION"
    echo ""
    write_version "$SET_VERSION"
    exit 0
    ;;
  *)
    echo "Error: unrecognized argument '$MODE'" >&2
    echo "" >&2
    usage >&2
    exit 1
    ;;
esac

# --verify: check all 4 version files are in sync without bumping
if [[ "$MODE" == "--verify" ]]; then
  V_FILE=$(tr -d '[:space:]' < "$ROOT/VERSION")
  V_PLUGIN=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")
  V_MKT_PLUGIN=$(jq -r '.plugins[0].version' "$ROOT/.claude-plugin/marketplace.json")
  V_MKT_ROOT=$(jq -r '.plugins[0].version' "$ROOT/marketplace.json")

  echo "Version sync check:"
  echo "  VERSION                         $V_FILE"
  echo "  .claude-plugin/plugin.json      $V_PLUGIN"
  echo "  .claude-plugin/marketplace.json $V_MKT_PLUGIN"
  echo "  marketplace.json                $V_MKT_ROOT"

  # intentional: detect if ANY file differs from VERSION
  # shellcheck disable=SC2055
  if [[ "$V_FILE" != "$V_PLUGIN" || "$V_FILE" != "$V_MKT_PLUGIN" || "$V_FILE" != "$V_MKT_ROOT" ]]; then
    echo ""
    echo "MISMATCH DETECTED — the following files differ:" >&2
    [[ "$V_FILE" != "$V_PLUGIN" ]]     && echo "  .claude-plugin/plugin.json ($V_PLUGIN != $V_FILE)" >&2
    [[ "$V_FILE" != "$V_MKT_PLUGIN" ]] && echo "  .claude-plugin/marketplace.json ($V_MKT_PLUGIN != $V_FILE)" >&2
    [[ "$V_FILE" != "$V_MKT_ROOT" ]]   && echo "  marketplace.json ($V_MKT_ROOT != $V_FILE)" >&2
    exit 1
  fi

  echo ""
  echo "All 4 version files are in sync ($V_FILE)."
  exit 0
fi

LOCAL=$(tr -d '[:space:]' < "$ROOT/VERSION")

# --offline: skip remote fetch entirely (useful in CI or air-gapped environments)
if [[ "$MODE" == "--offline" ]]; then
  REMOTE="$LOCAL"
  echo "Offline mode: skipping GitHub fetch."
else
  # Fetch the authoritative version from GitHub (graceful fallback on failure)
  REMOTE=$(curl -sf --max-time 5 "$REPO_URL" 2>/dev/null | tr -d '[:space:]' || true)
  if [[ -z "$REMOTE" ]]; then
    echo "Warning: Could not fetch version from GitHub. Using local VERSION as baseline." >&2
    REMOTE="$LOCAL"
  fi
fi

# Use whichever is higher as the base (protects against local being behind)
BASE="$REMOTE"
if [[ "$(printf '%s\n%s' "$LOCAL" "$REMOTE" | sort -V | tail -1)" == "$LOCAL" ]]; then
  BASE="$LOCAL"
fi

# Auto-increment patch version
MAJOR="${BASE%%.*}"
REST="${BASE#*.}"
MINOR="${REST%%.*}"
PATCH="${REST#*.}"
NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"

echo "GitHub version:  $REMOTE"
echo "Local version:   $LOCAL"
echo "Bumping to:      $NEW"
echo ""

write_version "$NEW"
