#!/usr/bin/env bash

extract_fail_classification_field() {
  local file_path="${1:-}"
  local field_name="${2:-}"
  [ -f "$file_path" ] || return 0
  [ -n "$field_name" ] || return 0
  awk -v field="$field_name" '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    function emit(v) {
      gsub(/[",}\]]/, "", v)
      v = trim(v)
      if (v != "") print v
    }
    BEGIN {
      in_fm = 0
      in_fc = 0
    }
    NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
    in_fm && /^---[[:space:]]*$/ { exit }
    in_fm && /^fail_classifications:/ {
      rest = $0
      sub(/^fail_classifications:[[:space:]]*/, "", rest)
      if (rest ~ /^\[/) {
        while (match(rest, field ":[[:space:]]*[^,}]+")) {
          value = substr(rest, RSTART, RLENGTH)
          sub("^" field ":[[:space:]]*", "", value)
          emit(value)
          rest = substr(rest, RSTART + RLENGTH)
        }
        exit
      }
      in_fc = 1
      next
    }
    in_fm && in_fc && /^[[:space:]]+- / {
      line = $0
      if (match(line, field ":[[:space:]]*[^,}]+")) {
        value = substr(line, RSTART, RLENGTH)
        sub("^" field ":[[:space:]]*", "", value)
        emit(value)
      }
      next
    }
    in_fm && in_fc && $0 ~ ("^[[:space:]]+" field ":") {
      line = $0
      sub("^[[:space:]]*" field ":[[:space:]]*", "", line)
      emit(line)
      next
    }
    in_fm && in_fc && /^[^[:space:]]/ { exit }
  ' "$file_path" 2>/dev/null
}

extract_fail_classification_types() { extract_fail_classification_field "${1:-}" type; }
extract_fail_classification_ids() { extract_fail_classification_field "${1:-}" id; }
extract_fail_classification_paths() { extract_fail_classification_field "${1:-}" path; }
extract_fail_classification_source_plans() { extract_fail_classification_field "${1:-}" source_plan; }

collect_fail_classification_types_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_types "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

collect_fail_classification_ids_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_ids "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

collect_fail_classification_paths_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_paths "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}


collect_fail_classification_source_plans_in_dir() {
  local scan_dir="${1:-}"
  [ -d "$scan_dir" ] || return 0
  while IFS= read -r _cfc_plan; do
    [ -f "$_cfc_plan" ] || continue
    extract_fail_classification_source_plans "$_cfc_plan"
  done < <(find "$scan_dir" -maxdepth 1 ! -name '.*' \( -name '*-PLAN.md' -o -name 'PLAN.md' \) 2>/dev/null | (sort -V 2>/dev/null || sort))
}

plan_amendment_source_plans_are_valid() {
  local phase_dir="${1:-}"
  local source_plan canonical_plan
  while IFS= read -r source_plan; do
    source_plan=$(normalize_recorded_path "$source_plan")
    [ -n "$source_plan" ] || return 1
    canonical_plan=$(canonicalize_phase_path "$source_plan" "$phase_dir")
    if ! path_is_original_plan_artifact "$canonical_plan" "$phase_dir"; then
      return 1
    fi
  done
  return 0
}

paths_cover_required_original_plan_artifacts() {
  local phase_dir="${1:-}"
  local required_paths="${2:-}"
  local recorded_paths required_path required_canonical recorded_path recorded_canonical found

  recorded_paths=$(cat)
  while IFS= read -r required_path; do
    required_path=$(normalize_recorded_path "$required_path")
    [ -n "$required_path" ] || return 1
    required_canonical=$(canonicalize_phase_path "$required_path" "$phase_dir")
    [ -n "$required_canonical" ] || return 1

    found=false
    while IFS= read -r recorded_path; do
      recorded_path=$(normalize_recorded_path "$recorded_path")
      [ -n "$recorded_path" ] || continue
      recorded_canonical=$(canonicalize_phase_path "$recorded_path" "$phase_dir")
      if [ "$recorded_canonical" = "$required_canonical" ]; then
        found=true
        break
      fi
    done <<< "$recorded_paths"

    [ "$found" = true ] || return 1
  done <<< "$required_paths"

  return 0
}

fail_classification_types_are_valid() {
  local saw_type=false
  while IFS= read -r classification_type; do
    [ -n "$classification_type" ] || continue
    saw_type=true
    case "$classification_type" in
      code-fix|doc-fix|plan-amendment|process-exception) ;;
      *) return 1 ;;
    esac
  done
  [ "$saw_type" = true ]
}

extract_fail_ids_from_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || return 0
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        id_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
          if (cell == "ID") id_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") {
          fail_index++
          fail_id = (id_col > 0) ? trim($(id_col)) : ""
          if (fail_id == "") fail_id = sprintf("FAIL-ROW-%02d", fail_index)
          print fail_id
        }
      }
    }
  ' "$file_path" 2>/dev/null
}

count_fail_rows_in_verification() {
  local file_path="${1:-}"
  [ -f "$file_path" ] || { echo 0; return; }
  awk -F'|' '
    function trim(v) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      return v
    }
    !/^\|/ { header_found = 0; next }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]-]+(\|[[:space:]-]+)+\|?[[:space:]]*$/) next
      if (!header_found) {
        status_col = 0
        for (i = 2; i < NF; i++) {
          cell = trim($i)
          if (cell == "Status") status_col = i
        }
        if (status_col > 0) header_found = 1
        next
      }
      if (status_col > 0) {
        status = trim($(status_col))
        gsub(/\*+/, "", status)
        status = trim(status)
        if (status == "FAIL") count++
      }
    }
    END { print count + 0 }
  ' "$file_path" 2>/dev/null
}

classification_ids_cover_source_fail_ids() {
  local source_fail_ids="${1:-}"
  local classified_ids="${2:-}"
  while IFS= read -r source_fail_id; do
    [ -n "$source_fail_id" ] || continue
    if ! printf '%s\n' "$classified_ids" | grep -Fx -- "$source_fail_id" >/dev/null 2>&1; then
      return 1
    fi
  done <<< "$source_fail_ids"
  return 0
}
