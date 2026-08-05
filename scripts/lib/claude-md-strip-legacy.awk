function should_remove_section(    remove_section) {
  remove_section = 0

  if (section_header == "## Active Context" ||
      section_header == "## VBW Rules" ||
      section_header == "## Code Intelligence" ||
      section_header == "## Plugin Isolation") {
    remove_section = 1
  } else if (section_header == "## State") {
    if (index(section_body, "Planning directory: `.vbw-planning/`") > 0) {
      remove_section = 1
    }
  } else if (section_header == "## Project Conventions") {
    if (index(section_body, "None yet. Run /vbw:teach to add project conventions.") > 0 ||
        index(section_body, "These conventions are enforced during planning and verified during QA.") > 0) {
      remove_section = 1
    }
  } else if (section_header == "## Commands") {
    if (index(section_body, "Run /vbw:status for current progress.") > 0 &&
        index(section_body, "Run /vbw:help for all available commands.") > 0) {
      remove_section = 1
    }
  }

  return remove_section
}

function flush_section() {
  if (!in_section) {
    return
  }

  if (!should_remove_section()) {
    printf "%s", section_buffer
  }

  in_section = 0
  section_header = ""
  section_buffer = ""
  section_body = ""
}

BEGIN {
  in_fence = 0
  in_section = 0
  section_header = ""
  section_buffer = ""
  section_body = ""
}

/^[[:space:]]*```/ || /^[[:space:]]*~~~/ {
  if (in_section) {
    section_buffer = section_buffer $0 ORS
    section_body = section_body $0 ORS
  } else {
    print
  }
  in_fence = !in_fence
  next
}

{
  if (!in_fence && $0 ~ /^##[[:space:]]+/) {
    flush_section()
    in_section = 1
    section_header = $0
    sub(/[[:space:]]+$/, "", section_header)
    section_buffer = $0 ORS
    section_body = ""
    next
  }

  if (in_section) {
    section_buffer = section_buffer $0 ORS
    section_body = section_body $0 ORS
  } else {
    print
  }
}

END {
  flush_section()
}
