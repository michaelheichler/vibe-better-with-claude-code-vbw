#!/usr/bin/env bash
set -euo pipefail

PHASE_DIR="${1:-}"

if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ] || [ ! -r "$PHASE_DIR" ]; then
  printf 'error=unreadable_phase_dir:%s\n' "$PHASE_DIR" >&2
  exit 1
fi

phase_prefix=$(basename "${PHASE_DIR%/}" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
if [ -z "$phase_prefix" ]; then
  printf 'error=invalid_phase_dir:%s\n' "$PHASE_DIR" >&2
  exit 1
fi
phase_id=$(printf '%02d' "$((10#$phase_prefix))")

normalize_analyzer_plan_id() {
  local raw="$1"
  local raw_phase raw_plan
  case "$raw" in
    *-*)
      raw_phase="${raw%%-*}"
      raw_plan="${raw#*-}"
      if [[ "$raw_phase" =~ ^[0-9]+$ ]] && [[ "$raw_plan" =~ ^[0-9]+$ ]]; then
        printf '%02d-%02d\n' "$((10#$raw_phase))" "$((10#$raw_plan))"
      else
        printf '%s\n' "$raw"
      fi
      ;;
    *[!0-9]*) printf '%s\n' "$raw" ;;
    *) printf '%s-%02d\n' "$phase_id" "$((10#$raw))" ;;
  esac
}

FILES_TOUCHED_AWK=$(cat <<'AWK'
function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}
function emit(value, count, item_index, parts) {
  sub(/[[:space:]]+#.*$/, "", value)
  value = trim(value)
  if (value == "" || value == "[]") return
  if (value ~ /^\[/) {
    sub(/^\[/, "", value)
    sub(/\][[:space:]]*$/, "", value)
    count = split(value, parts, ",")
    for (item_index = 1; item_index <= count; item_index++) emit(parts[item_index])
    return
  }
  gsub(/^["']|["']$/, "", value)
  if (value != "") print value
}
BEGIN { in_frontmatter = 0; in_files = 0 }
/^---[[:space:]]*$/ {
  if (in_frontmatter == 0) {
    in_frontmatter = 1
    next
  }
  exit
}
in_frontmatter && /^[[:space:]]*files_touched:[[:space:]]*/ {
  print "__declared__"
  line = $0
  sub(/^[[:space:]]*files_touched:[[:space:]]*/, "", line)
  if (trim(line) != "") emit(line)
  in_files = 1
  next
}
in_frontmatter && in_files && /^[[:space:]]*-[[:space:]]*/ {
  line = $0
  sub(/^[[:space:]]*-[[:space:]]*/, "", line)
  emit(line)
  next
}
in_frontmatter && in_files && /^[^[:space:]]/ { exit }
AWK
)

join_by() {
  local delimiter="$1"
  shift
  local joined=""
  local value
  for value in "$@"; do
    if [ -n "$joined" ]; then
      joined+="$delimiter"
    fi
    joined+="$value"
  done
  printf '%s' "$joined"
}

declare -a plan_ids=()
declare -a conflict_pairs=()
declare -a missing_ids=()
declare -a groups=()
declare -A plan_files=()
declare -A missing=()
declare -A conflicts=()

while IFS= read -r plan_file; do
  plan_id=$(normalize_analyzer_plan_id "$(basename "$plan_file" -PLAN.md)")
  plan_ids+=("$plan_id")
  mapfile -t parsed < <(awk "$FILES_TOUCHED_AWK" "$plan_file")
  if [ "${parsed[0]:-}" != "__declared__" ]; then
    missing["$plan_id"]=1
    missing_ids+=("$plan_id")
    plan_files["$plan_id"]=""
    continue
  fi
  if [ "${#parsed[@]}" -gt 1 ]; then
    plan_files["$plan_id"]=$(printf '%s\n' "${parsed[@]:1}")
  else
    plan_files["$plan_id"]=""
  fi
done < <(find "$PHASE_DIR" -maxdepth 1 -type f -name '*-PLAN.md' -print | LC_ALL=C sort)

plans_conflict() {
  local left="$1"
  local right="$2"
  local left_file right_file
  if [ -n "${missing[$left]:-}" ] || [ -n "${missing[$right]:-}" ]; then
    return 0
  fi
  while IFS= read -r left_file; do
    [ -n "$left_file" ] || continue
    while IFS= read -r right_file; do
      [ -n "$right_file" ] || continue
      [ "$left_file" = "$right_file" ] && return 0
    done <<< "${plan_files[$right]}"
  done <<< "${plan_files[$left]}"
  return 1
}

for ((i = 0; i < ${#plan_ids[@]}; i++)); do
  for ((j = i + 1; j < ${#plan_ids[@]}; j++)); do
    left="${plan_ids[$i]}"
    right="${plan_ids[$j]}"
    if plans_conflict "$left" "$right"; then
      pair="$left:$right"
      conflict_pairs+=("$pair")
      conflicts["$pair"]=1
    fi
  done
done

pair_conflicts() {
  local left="$1"
  local right="$2"
  local key
  if [[ "$left" < "$right" ]]; then
    key="$left:$right"
  else
    key="$right:$left"
  fi
  [ -n "${conflicts[$key]:-}" ]
}

for plan_id in "${plan_ids[@]}"; do
  placed=false
  for ((group_index = 0; group_index < ${#groups[@]}; group_index++)); do
    compatible=true
    IFS='|' read -r -a members <<< "${groups[$group_index]}"
    for member in "${members[@]}"; do
      if pair_conflicts "$plan_id" "$member"; then
        compatible=false
        break
      fi
    done
    if [ "$compatible" = true ]; then
      groups[$group_index]+="|$plan_id"
      placed=true
      break
    fi
  done
  if [ "$placed" = false ]; then
    groups+=("$plan_id")
  fi
done

printf 'conflict_pairs=%s\n' "$(join_by , "${conflict_pairs[@]}")"
printf 'disjoint_groups=%s\n' "$(join_by ';' "${groups[@]}")"
printf 'plans_missing_files_touched=%s\n' "$(join_by , "${missing_ids[@]}")"
printf 'analyzed_plan_ids=%s\n' "$(join_by , "${plan_ids[@]}")"
