#!/usr/bin/env bash
set -u


if [ $# -lt 1 ]; then
  echo "[]"
  exit 0
fi

PHASE_DIR="$1"

command -v jq &>/dev/null || { echo "[]"; exit 0; }
[ ! -d "$PHASE_DIR" ] && { echo "[]"; exit 0; }

CONFIG_PATH=".vbw-planning/config.json"
if [ -f "$CONFIG_PATH" ]; then
  MONOREPO_ROUTING=$(jq -r 'if .monorepo_routing != null then .monorepo_routing elif .v3_monorepo_routing != null then .v3_monorepo_routing else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$MONOREPO_ROUTING" != "true" ]; then
    echo "[]"
    exit 0
  fi
fi

PACKAGE_MARKERS="package.json Cargo.toml go.mod pyproject.toml"
PACKAGE_ROOTS=()

for marker in $PACKAGE_MARKERS; do
  while IFS= read -r marker_path; do
    [ -z "$marker_path" ] && continue
    root=$(dirname "$marker_path")
    [ "$root" = "." ] && continue
    PACKAGE_ROOTS+=("$root")
  done < <(find . -maxdepth 4 -name "$marker" -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.vbw-planning/*' 2>/dev/null)
done

if [ ${#PACKAGE_ROOTS[@]} -eq 0 ]; then
  echo "[]"
  exit 0
fi

PLAN_FILES=()
for plan_file in "$PHASE_DIR"/*-PLAN.md; do
  [ ! -f "$plan_file" ] && continue
  while IFS= read -r line; do
    cleaned=$(echo "$line" | sed 's/.*\*\*Files:\*\* *//' | sed 's/`//g' | sed 's/ *(new)//g')
    IFS=',' read -ra parts <<< "$cleaned"
    for part in "${parts[@]}"; do
      trimmed=$(echo "$part" | sed 's/^ *//;s/ *$//')
      [ -n "$trimmed" ] && PLAN_FILES+=("$trimmed")
    done
  done < <(grep -i '^\- \*\*Files:\*\*' "$plan_file" 2>/dev/null)
done

RELEVANT_ROOTS=()
for plan_file in "${PLAN_FILES[@]}"; do
  [ -z "$plan_file" ] && continue
  for root in "${PACKAGE_ROOTS[@]}"; do
    clean_root="${root#./}"
    case "$plan_file" in
      "$clean_root"/*)
        FOUND=false
        for existing in "${RELEVANT_ROOTS[@]+"${RELEVANT_ROOTS[@]}"}"; do
          [ "$existing" = "$clean_root" ] && FOUND=true && break
        done
        [ "$FOUND" = false ] && RELEVANT_ROOTS+=("$clean_root")
        ;;
    esac
  done
done

if [ ${#RELEVANT_ROOTS[@]} -eq 0 ]; then
  echo "[]"
else
  printf '%s\n' "${RELEVANT_ROOTS[@]}" | jq -R '.' | jq -s '.' 2>/dev/null || echo "[]"
fi

exit 0
