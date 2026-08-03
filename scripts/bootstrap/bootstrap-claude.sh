#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../lib/claude-md-vbw-sections.sh"

if [[ ! -f "$LIB" ]]; then
  echo "Error: helper library not found at $LIB" >&2
  exit 1
fi

source "$LIB"


VBW_SECTIONS=("${VBW_CANONICAL_HEADERS[@]}")

VBW_DEPRECATED_SECTIONS=(
  "## Key Decisions"  # Removed: tracked in .vbw-planning/PROJECT.md and STATE.md
  "## Installed Skills"  # Removed: skills surfaced through runtime activation pipeline
)

GSD_STRONG_SECTIONS=(
  "## Codebase Intelligence"
  "## Project Reference"
  "## GSD Rules"
  "## GSD Context"
)

GSD_SOFT_SECTIONS=(
  "## What This Is"
  "## Core Value"
  "## Context"
  "## Constraints"
)

if [[ $# -lt 3 ]]; then
  echo "Usage: bootstrap-claude.sh OUTPUT_PATH PROJECT_NAME CORE_VALUE [EXISTING_PATH]" >&2
  exit 1
fi

OUTPUT_PATH="$1"
PROJECT_NAME="$2"
CORE_VALUE="$3"
EXISTING_PATH="${4:-}"

if [[ -z "$PROJECT_NAME" || -z "$CORE_VALUE" ]]; then
  echo "Error: PROJECT_NAME and CORE_VALUE must not be empty" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

INCLUDE_ACTIVE_CONTEXT=true
INCLUDE_VBW_RULES=true
INCLUDE_CODE_INTELLIGENCE=true
INCLUDE_PLUGIN_ISOLATION=true

generate_vbw_sections() {
  local emitted=false

  if [[ "$INCLUDE_ACTIVE_CONTEXT" == true ]]; then
    vbw_generate_active_context_section
    emitted=true
  fi

  if [[ "$INCLUDE_VBW_RULES" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_vbw_rules_section
    emitted=true
  fi

  if [[ "$INCLUDE_CODE_INTELLIGENCE" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_code_intelligence_section
    emitted=true
  fi

  if [[ "$INCLUDE_PLUGIN_ISOLATION" == true ]]; then
    if [[ "$emitted" == true ]]; then echo ""; fi
    vbw_generate_plugin_isolation_section
  fi
}

is_vbw_section() {
  local line="$1"
  for header in "${VBW_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

is_gsd_section() {
  local line="$1"
  for header in "${GSD_STRONG_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done

  if [[ "${ALLOW_SOFT_GSD_STRIP:-false}" == "true" ]]; then
    for header in "${GSD_SOFT_SECTIONS[@]}"; do
      if [[ "$line" == "$header" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

is_deprecated_vbw_section() {
  local line="$1"
  for header in "${VBW_DEPRECATED_SECTIONS[@]}"; do
    if [[ "$line" == "$header" ]]; then
      return 0
    fi
  done
  return 1
}

is_managed_section() {
  is_vbw_section "$1" || is_deprecated_vbw_section "$1" || is_gsd_section "$1"
}

if [[ -n "$EXISTING_PATH" && -f "$EXISTING_PATH" ]]; then
  ALLOW_SOFT_GSD_STRIP=false
  if grep -Eq '^## (Codebase Intelligence|Project Reference|GSD Rules|GSD Context)$' "$EXISTING_PATH"; then
    ALLOW_SOFT_GSD_STRIP=true
  fi

  NON_VBW_CONTENT=""
  IN_MANAGED_SECTION=false
  FOUND_NON_VBW=false
  IN_DEPRECATED_SECTION=false
  DEPRECATED_SECTION_BUFFER=""
  DEPRECATED_HAS_USER_CONTENT=false

  migrate_key_decisions_to_state() {
    local buffer="$1"
    local state_path
    state_path="$(dirname "$OUTPUT_PATH")/.vbw-planning/STATE.md"

    local data_rows=""
    local row_count=0
    while IFS= read -r row; do
      [[ "$row" =~ ^\|\ *Decision ]] && continue
      [[ "$row" =~ ^\|[-[:space:]|]+\|$ ]] && continue
      [[ "$row" =~ _\(No\ decisions\ yet\)_ ]] && continue
      [[ "$row" =~ ^\| ]] || continue
      data_rows+="${row}"$'\n'
      row_count=$((row_count + 1))
    done <<< "$buffer"

    if [[ $row_count -eq 0 ]]; then
      return 0
    fi

    if [[ ! -f "$state_path" ]]; then
      echo "Warning: Cannot migrate $row_count Key Decisions row(s), STATE.md not found at $state_path" >&2
      return 1
    fi

    if ! grep -q '^## Key Decisions' "$state_path"; then
      echo "Warning: Cannot migrate $row_count Key Decisions row(s), no ## Key Decisions section in STATE.md" >&2
      return 1
    fi

    local unique_rows=""
    local unique_count=0
    while IFS= read -r drow; do
      [[ -z "$drow" ]] && continue
      if ! tr -s ' ' < "$state_path" | grep -qF "$(printf '%s' "$drow" | tr -s ' ')"; then
        unique_rows+="${drow}"$'\n'
        unique_count=$((unique_count + 1))
      fi
    done <<< "$data_rows"

    if [[ $unique_count -eq 0 ]]; then
      echo "Skipped migration, all $row_count Key Decisions row(s) already in STATE.md" >&2
      return 0
    fi

    local tmp_state
    tmp_state="$(mktemp)"
    trap 'rm -f "${tmp_state:-}"' RETURN
    local in_kd_section=false
    local past_separator=false
    local rows_inserted=false

    while IFS= read -r sline || [[ -n "$sline" ]]; do
      if [[ "$sline" == "## Key Decisions" ]]; then
        in_kd_section=true
        past_separator=false
        rows_inserted=false
        echo "$sline" >> "$tmp_state"
        continue
      fi
      if [[ "$in_kd_section" == true && "$sline" =~ ^##\  ]]; then
        if [[ "$past_separator" == true && "$rows_inserted" == false ]]; then
          printf '%s' "$unique_rows" >> "$tmp_state"
          rows_inserted=true
        fi
        echo "" >> "$tmp_state"
        in_kd_section=false
        echo "$sline" >> "$tmp_state"
        continue
      fi
      if [[ "$in_kd_section" == true ]]; then
        if [[ "$sline" =~ ^\|[-[:space:]|]+\|$ && ! "$sline" =~ ^\|\ *Decision ]]; then
          past_separator=true
          echo "$sline" >> "$tmp_state"
          continue
        fi
        if [[ "$sline" =~ _\(No\ decisions\ yet\)_ ]]; then
          continue
        fi
        if [[ "$past_separator" == true && -z "$sline" ]]; then
          continue
        fi
        echo "$sline" >> "$tmp_state"
      else
        echo "$sline" >> "$tmp_state"
      fi
    done < "$state_path"

    if [[ "$in_kd_section" == true && "$past_separator" == true && "$rows_inserted" == false ]]; then
      printf '%s' "$unique_rows" >> "$tmp_state"
      rows_inserted=true
    fi

    if [[ "$past_separator" == false ]]; then
      rm -f "$tmp_state"
      echo "Warning: Cannot migrate $unique_count Key Decisions row(s), STATE.md Key Decisions section has no table" >&2
      return 1
    fi

    mv "$tmp_state" "$state_path"
    echo "Migrated $unique_count Key Decisions row(s) from CLAUDE.md to STATE.md" >&2
  }

  flush_deprecated_buffer() {
    if [[ "$IN_DEPRECATED_SECTION" == true ]]; then
      if [[ "$DEPRECATED_HAS_USER_CONTENT" == true ]]; then
        if ! migrate_key_decisions_to_state "$DEPRECATED_SECTION_BUFFER"; then
          NON_VBW_CONTENT+="${DEPRECATED_SECTION_BUFFER}"
          FOUND_NON_VBW=true
          IN_DEPRECATED_SECTION=false
          DEPRECATED_SECTION_BUFFER=""
          DEPRECATED_HAS_USER_CONTENT=false
          return
        fi
      fi

      local preserved=""
      local section_label=""
      local first_line=true
      while IFS= read -r bline; do
        if [[ "$first_line" == true ]]; then
          first_line=false
          section_label="${bline#\#\# }"
          continue
        fi
        [[ "$bline" =~ ^\|\ *Decision ]] && continue
        [[ "$bline" =~ ^\|[-[:space:]|]+\|$ ]] && continue
        [[ "$bline" =~ ^\| ]] && continue
        preserved+="${bline}"$'\n'
      done <<< "$DEPRECATED_SECTION_BUFFER"

      if [[ -n "${preserved//[[:space:]]/}" ]]; then
        preserved="$(echo "$preserved" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
        NON_VBW_CONTENT+="## ${section_label} (Archived Notes)"$'\n'$'\n'"${preserved}"$'\n'$'\n'
        FOUND_NON_VBW=true
      fi

      IN_DEPRECATED_SECTION=false
      DEPRECATED_SECTION_BUFFER=""
      DEPRECATED_HAS_USER_CONTENT=false
    fi
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%"${line##*[![:space:]]}"}"

    if is_managed_section "$line"; then
      flush_deprecated_buffer
      if is_deprecated_vbw_section "$line"; then
        IN_DEPRECATED_SECTION=true
        DEPRECATED_SECTION_BUFFER="${line}"$'\n'
        DEPRECATED_HAS_USER_CONTENT=false
      fi
      IN_MANAGED_SECTION=true
      continue
    fi

    if [[ "$line" =~ ^##\  ]] && ! is_managed_section "$line"; then
      flush_deprecated_buffer
      IN_MANAGED_SECTION=false
    fi

    if [[ "$IN_DEPRECATED_SECTION" == true ]]; then
      DEPRECATED_SECTION_BUFFER+="${line}"$'\n'
      if [[ -n "$line" && ! "$line" =~ ^\|[-[:space:]|]+\|$ && ! "$line" =~ ^\|\ *Decision ]]; then
        DEPRECATED_HAS_USER_CONTENT=true
      fi
      continue
    fi

    if [[ "$IN_MANAGED_SECTION" == false ]]; then
      NON_VBW_CONTENT+="${line}"$'\n'
      FOUND_NON_VBW=true
    fi
  done < "$EXISTING_PATH"

  flush_deprecated_buffer

  if vbw_should_emit_managed_section "$EXISTING_PATH" "Active Context" "## Active Context"; then
    INCLUDE_ACTIVE_CONTEXT=true
  else
    INCLUDE_ACTIVE_CONTEXT=false
  fi

  if vbw_should_emit_managed_section "$EXISTING_PATH" "VBW Rules" "## VBW Rules"; then
    INCLUDE_VBW_RULES=true
  else
    INCLUDE_VBW_RULES=false
  fi

  if vbw_should_emit_code_intelligence_section "$EXISTING_PATH"; then
    INCLUDE_CODE_INTELLIGENCE=true
  else
    INCLUDE_CODE_INTELLIGENCE=false
  fi

  if vbw_should_emit_managed_section "$EXISTING_PATH" "Plugin Isolation" "## Plugin Isolation"; then
    INCLUDE_PLUGIN_ISOLATION=true
  else
    INCLUDE_PLUGIN_ISOLATION=false
  fi

  {
    if [[ "$FOUND_NON_VBW" == true ]]; then
      echo "$NON_VBW_CONTENT" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
      if [[ "$INCLUDE_ACTIVE_CONTEXT" == true || "$INCLUDE_VBW_RULES" == true || "$INCLUDE_CODE_INTELLIGENCE" == true || "$INCLUDE_PLUGIN_ISOLATION" == true ]]; then
        echo ""
      fi
    fi
    generate_vbw_sections
  } > "$OUTPUT_PATH"
else
  {
    echo "# ${PROJECT_NAME}"
    echo ""
    echo "**Core value:** ${CORE_VALUE}"
    echo ""
    generate_vbw_sections
  } > "$OUTPUT_PATH"
fi

exit 0
