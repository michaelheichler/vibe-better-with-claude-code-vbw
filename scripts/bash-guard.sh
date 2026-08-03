#!/bin/bash
set -u
# Parse failures block because unvalidated commands cannot be trusted.

if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked: jq not available, cannot validate bash command" >&2
  exit 2
fi

INPUT=$(cat 2>/dev/null) || exit 2
[ -z "$INPUT" ] && exit 2

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 2
[ -z "$COMMAND" ] && exit 0  # No command = nothing to check

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -z "${VBW_PLANNING_DIR:-}" ] && [ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ]; then
  if source "$SCRIPT_DIR/lib/vbw-config-root.sh" 2>/dev/null; then
    find_vbw_root "$SCRIPT_DIR" >/dev/null 2>&1 || true
  fi
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
DEFAULT_PATTERNS="$PLUGIN_ROOT/config/destructive-commands.txt"
LOCAL_PATTERNS="$PLANNING_DIR/destructive-commands.local.txt"
if [ -f "$SCRIPT_DIR/lib/active-agent-state.sh" ]; then
  . "$SCRIPT_DIR/lib/active-agent-state.sh"
fi

_BG_PAYLOAD_AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null) || _BG_PAYLOAD_AGENT_TYPE=""
_BG_PAYLOAD_AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null) || _BG_PAYLOAD_AGENT_ID=""
_BG_PAYLOAD_HAS_AGENT=false
if [ -n "$_BG_PAYLOAD_AGENT_TYPE" ] || [ -n "$_BG_PAYLOAD_AGENT_ID" ]; then
  _BG_PAYLOAD_HAS_AGENT=true
fi

detect_agent_role() {
  local candidate role
  for candidate in "${VBW_AGENT_ROLE:-}" "${VBW_ACTIVE_AGENT:-}"; do
    [ -z "$candidate" ] && continue
    role=$(vbw_active_agent_normalize_role "$candidate") || continue
    printf '%s' "$role"
    return 0
  done
  for candidate in "$_BG_PAYLOAD_AGENT_TYPE" "$_BG_PAYLOAD_AGENT_ID"; do
    [ -z "$candidate" ] && continue
    role=$(vbw_active_agent_normalize_role "$candidate") || continue
    printf '%s' "$role"
    return 0
  done
  [ "$_BG_PAYLOAD_HAS_AGENT" = true ] || return 1
  command -v vbw_active_agent_current_scout >/dev/null 2>&1 \
    && vbw_active_agent_current_scout "$PLANNING_DIR" "$INPUT" \
    && { printf 'scout'; return 0; }
  command -v vbw_active_agent_current_qa >/dev/null 2>&1 \
    && vbw_active_agent_current_qa "$PLANNING_DIR" "$INPUT" \
    && { printf 'qa'; return 0; }
  return 1
}

ACTIVE_AGENT_ROLE=""
if ACTIVE_AGENT_ROLE=$(detect_agent_role); then
  :
else
  ACTIVE_AGENT_ROLE=""
fi

PATTERNS=""
for PFILE in "$DEFAULT_PATTERNS" "$LOCAL_PATTERNS"; do
  [ -f "$PFILE" ] || continue
  FILE_PATTERNS=$(grep -v '^\s*#' "$PFILE" | grep -v '^\s*$' | tr '\n' '|' | sed 's/|$//')
  [ -n "$FILE_PATTERNS" ] && {
    [ -n "$PATTERNS" ] && PATTERNS="$PATTERNS|$FILE_PATTERNS" || PATTERNS="$FILE_PATTERNS"
  }
done

log_block_event() {
  local matched="$1"
  local preview matched_esc agent timestamp

  if [ -d "$PLANNING_DIR" ]; then
    preview=$(echo "$COMMAND" | head -c 40)
    agent="${ACTIVE_AGENT_ROLE:-${VBW_ACTIVE_AGENT:-unknown}}"
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s")
    preview=$(echo "$preview" | sed 's/"/\\"/g')
    matched_esc=$(echo "$matched" | sed 's/"/\\"/g')
    printf '{"event":"bash_guard_block","command_preview":"%s","pattern_matched":"%s","agent":"%s","timestamp":"%s"}\n' \
      "$preview" "$matched_esc" "$agent" "$timestamp" >> "$PLANNING_DIR/.event-log.jsonl" 2>/dev/null
  fi
}

block_readonly_agent_command() {
  local reason="$1"
  local role_label

  case "$ACTIVE_AGENT_ROLE" in
    scout) role_label="Scout" ;;
    qa) role_label="QA" ;;
    *) role_label="Agent" ;;
  esac

  echo "Blocked: $role_label Bash is read-only ($reason)" >&2
  log_block_event "${ACTIVE_AGENT_ROLE:-unknown}:$reason"
  exit 2
}

has_shell_file_write_redirection() {
  local command="$1"
  local index=0 length character next_character target_start target_end redirect_target target_quote
  local in_single=0 in_double=0 escaped=0

  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"

    if [ "$escaped" -eq 1 ]; then
      escaped=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$character" = "'" ] && in_single=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then
        escaped=1
      elif [ "$character" = '"' ]; then
        in_double=0
      fi
      index=$((index + 1))
      continue
    fi

    case "$character" in
      "'")
        in_single=1
        ;;
      '"')
        in_double=1
        ;;
      "\\")
        escaped=1
        ;;
      ">")
        target_start=$((index + 1))
        [ "${command:$target_start:1}" = ">" ] && target_start=$((target_start + 1))
        while [ "$target_start" -lt "$length" ] && [[ "${command:$target_start:1}" = [[:space:]] ]]; do
          target_start=$((target_start + 1))
        done

        target_quote="${command:$target_start:1}"
        case "$target_quote" in
          "'"|'"')
            target_end=$((target_start + 1))
            while [ "$target_end" -lt "$length" ] && [ "${command:$target_end:1}" != "$target_quote" ]; do
              target_end=$((target_end + 1))
            done
            redirect_target="${command:$((target_start + 1)):$((target_end - target_start - 1))}"
            [ "$redirect_target" = "/dev/null" ] || return 0
            index=$((target_end + 1))
            continue
            ;;
        esac

        if [ "$target_quote" = "&" ]; then
          target_end=$((target_start + 1))
          if [ "${command:$target_end:1}" = "-" ]; then
            target_end=$((target_end + 1))
          else
            while [ "$target_end" -lt "$length" ] && [[ "${command:$target_end:1}" = [0-9] ]]; do
              target_end=$((target_end + 1))
            done
          fi
          redirect_target="${command:$target_start:$((target_end - target_start))}"
          case "$redirect_target" in
            '&'-|'&'[0-9]*)
              ;;
            *)
              return 0
              ;;
          esac
        else
          target_end=$target_start
          while [ "$target_end" -lt "$length" ]; do
            next_character="${command:$target_end:1}"
            case "$next_character" in
              [[:space:]]|";"|"|"|"&"|"<"|">")
                break
                ;;
            esac
            target_end=$((target_end + 1))
          done
          redirect_target="${command:$target_start:$((target_end - target_start))}"
          [ "$redirect_target" = "/dev/null" ] || return 0
        fi
        index=$target_end
        continue
        ;;
      "<")
        next_character="${command:$((index + 1)):1}"
        [ "$next_character" = "<" ] && return 0
        ;;
    esac

    index=$((index + 1))
  done

  return 1
}

command_has_command_substitution() {
  local command="$1"
  local index=0 length character next_character in_single=0 in_double=0 escaped=0

  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"

    if [ "$escaped" -eq 1 ]; then
      escaped=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$character" = "'" ] && in_single=0
      index=$((index + 1))
      continue
    fi

    case "$character" in
      "'")
        [ "$in_double" -eq 0 ] && in_single=1
        ;;
      '"')
        if [ "$in_double" -eq 1 ]; then
          in_double=0
        else
          in_double=1
        fi
        ;;
      "\\")
        escaped=1
        ;;
      '$')
        next_character="${command:$((index + 1)):1}"
        [ "$next_character" = "(" ] && return 0
        ;;
      '`')
        return 0
        ;;
    esac

    index=$((index + 1))
  done

  return 1
}

command_has_process_substitution() {
  local command="$1"
  local index=0 length character next_character in_single=0 in_double=0 escaped=0

  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"

    if [ "$escaped" -eq 1 ]; then
      escaped=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$character" = "'" ] && in_single=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then
        escaped=1
      elif [ "$character" = '"' ]; then
        in_double=0
      fi
      index=$((index + 1))
      continue
    fi

    case "$character" in
      "'")
        in_single=1
        ;;
      '"')
        in_double=1
        ;;
      "\\")
        escaped=1
        ;;
      "<"|">")
        next_character="${command:$((index + 1)):1}"
        [ "$next_character" = "(" ] && return 0
        ;;
    esac

    index=$((index + 1))
  done

  return 1
}

command_without_quoted_text() {
  local command="$1"
  local index=0 length character output="" in_single=0 in_double=0 escaped=0

  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"

    if [ "$escaped" -eq 1 ]; then
      output="${output} "
      escaped=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      [ "$character" = "'" ] && in_single=0
      output="${output} "
      index=$((index + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then
        escaped=1
      elif [ "$character" = '"' ]; then
        in_double=0
      fi
      output="${output} "
      index=$((index + 1))
      continue
    fi

    case "$character" in
      "'")
        in_single=1
        output="${output} "
        ;;
      '"')
        in_double=1
        output="${output} "
        ;;
      "\\")
        escaped=1
        output="${output} "
        ;;
      *)
        output="${output}${character}"
        ;;
    esac

    index=$((index + 1))
  done

  printf '%s' "$output"
}

command_has_unquoted_eval() {
  local command="$1"
  local masked

  masked=$(command_without_quoted_text "$command")
  echo "$masked" | grep -qE '(^|[[:space:];|&(){}])eval([[:space:];|&(){}]|$)'
}

is_shell_interpreter_token() {
  local token="$1"

  token="${token##*/}"
  case "$token" in
    bash|sh|zsh|dash|ksh|fish)
      return 0
      ;;
  esac

  return 1
}

shell_visible_tokens() {
  local command="$1"
  local index=0 length character token="" in_single=0 in_double=0 escaped=0

  length=${#command}
  while [ "$index" -lt "$length" ]; do
    character="${command:$index:1}"

    if [ "$escaped" -eq 1 ]; then
      token="${token}${character}"
      escaped=0
      index=$((index + 1))
      continue
    fi

    if [ "$in_single" -eq 1 ]; then
      if [ "$character" = "'" ]; then
        in_single=0
      else
        token="${token}${character}"
      fi
      index=$((index + 1))
      continue
    fi

    if [ "$in_double" -eq 1 ]; then
      if [ "$character" = "\\" ]; then
        escaped=1
      elif [ "$character" = '"' ]; then
        in_double=0
      else
        token="${token}${character}"
      fi
      index=$((index + 1))
      continue
    fi

    case "$character" in
      "'")
        in_single=1
        ;;
      '"')
        in_double=1
        ;;
      "\\")
        escaped=1
        ;;
      [[:space:]]|";"|"|"|"&"|"("|")"|"{"|"}"|"!")
        if [ -n "$token" ]; then
          printf '%s\n' "$token"
          token=""
        fi
        ;;
      *)
        token="${token}${character}"
        ;;
    esac

    index=$((index + 1))
  done

  if [ -n "$token" ]; then
    printf '%s\n' "$token"
  fi
}

command_segments_without_quoted_text() {
  local command="$1"
  local masked

  masked=$(command_without_quoted_text "$command")
  printf '%s' "$masked" | tr ';|&' '\n'
}

segment_command_token() {
  local segment="$1"
  local token wrapper="" skip_next=0

  while IFS= read -r token; do
    [ -n "$token" ] || continue
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$token" in
      [0-9]*'>'*|[0-9]*'<'*|[[:alnum:]_]*=*)
        continue
        ;;
    esac
    case "$wrapper" in
      sudo)
        case "$token" in
          -u|-g|-h|-p|-C) skip_next=1; continue ;;
          -*) continue ;;
          *) wrapper="" ;;
        esac
        ;;
      env)
        case "$token" in
          -*) continue ;;
          *=*) continue ;;
          *) wrapper="" ;;
        esac
        ;;
      command|exec)
        case "$token" in
          -*) continue ;;
          *) wrapper="" ;;
        esac
        ;;
      nice)
        case "$token" in
          -n) skip_next=1; continue ;;
          -*) continue ;;
          *) wrapper="" ;;
        esac
        ;;
    esac
    if [ -z "$wrapper" ]; then
      case "$token" in
        sudo|env|command|exec|nice) wrapper="$token"; continue ;;
      esac
      printf '%s' "${token##*/}"
      return 0
    fi
  done <<< "$(shell_visible_tokens "$segment")"

  return 1
}

command_has_filesystem_mutation() {
  local command="$1"
  local segment command_token

  while IFS= read -r segment; do
    command_token=$(segment_command_token "$segment") || continue
    case "$command_token" in
      rm|mv|cp|mkdir|rmdir|touch|chmod|chown|ln|install|truncate)
        return 0
        ;;
    esac
  done <<< "$(command_segments_without_quoted_text "$command")"

  return 1
}

command_matches_patterns() {
  local command="$1"
  local segment COMMAND

  while IFS= read -r segment; do
    COMMAND="$segment"
    if echo "$COMMAND" | grep -iqE "$PATTERNS"; then
      return 0
    fi
  done <<< "$(command_segments_without_quoted_text "$command")"

  return 1
}

command_pattern_match() {
  local command="$1"
  local segment

  while IFS= read -r segment; do
    if printf '%s\n' "$segment" | grep -iqE "$PATTERNS"; then
      printf '%s\n' "$segment" | grep -ioE "$PATTERNS" | head -1
      return 0
    fi
  done <<< "$(command_segments_without_quoted_text "$command")"

  return 1
}


token_has_shell_c_option() {
  case "$1" in
    -c|--command|--command=*)
      return 0
      ;;
    --*)
      return 1
      ;;
    -*)
      echo "${1#-}" | grep -q 'c'
      return $?
      ;;
  esac

  return 1
}

segment_has_shell_c_invocation() {
  local segment="$1"
  local token saw_shell=0 skip_next_shell_option_arg=0

  while IFS= read -r token; do
    [ -z "$token" ] && continue

    if [ "$saw_shell" -eq 1 ]; then
      if [ "$skip_next_shell_option_arg" -eq 1 ]; then
        skip_next_shell_option_arg=0
        continue
      fi

      if token_has_shell_c_option "$token"; then
        return 0
      fi

      case "$token" in
        -o|-O|--init-file|--rcfile)
          skip_next_shell_option_arg=1
          continue
          ;;
        --init-file=*|--rcfile=*)
          continue
          ;;
        -*)
          continue
          ;;
        *)
          saw_shell=0
          ;;
      esac
    fi

    if is_shell_interpreter_token "$token"; then
      saw_shell=1
      skip_next_shell_option_arg=0
      continue
    fi
  done <<< "$(shell_visible_tokens "$segment")"

  return 1
}

command_has_nested_shell_execution() {
  local command="$1"

  if segment_has_shell_c_invocation "$command"; then
    return 0
  fi

  return 1
}

curl_uses_get_query_mode() {
  local command="$1"
  echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)(--get([[:space:]]|$)|-[[:alnum:]]*G[[:alnum:]]*([[:space:]]|$))'
}

gh_api_uses_explicit_get() {
  local command="$1"
  echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--method(=|[[:space:]]+)[Gg][Ee][Tt]|-X[[:space:]]*[Gg][Ee][Tt]|-X[Gg][Ee][Tt])'
}

scout_git_segments_are_readonly() {
  local command="$1"
  local segment segments

  segments=$(printf '%s' "$command" | tr ';|&' '\n')
  while IFS= read -r segment; do
    if echo "$segment" | grep -qE '^[[:space:]]*git[[:space:]]+'; then
      if ! echo "$segment" | grep -qE '^[[:space:]]*git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:]]+|[[:space:]]+(--no-pager|--bare|--literal-pathspecs|--[[:alnum:]-]+(=[^[:space:]]+)?))*[[:space:]]+(status|log|show|diff|ls-files|grep|rev-parse|cat-file|ls-tree|blame|describe)([[:space:]]|$)'; then
        return 1
      fi
    fi
  done <<< "$segments"

  return 0
}

scout_gh_segments_are_readonly() {
  local command="$1"
  local segment segments

  segments=$(printf '%s' "$command" | tr ';|&' '\n')
  while IFS= read -r segment; do
    if echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+'; then
      if echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+api([[:space:]]|$)'; then
        continue
      fi
      if ! echo "$segment" | grep -qE '^[[:space:]]*gh[[:space:]]+((auth[[:space:]]+status|status)([[:space:]]|$)|issue[[:space:]]+(view|list|status)([[:space:]]|$)|pr[[:space:]]+(view|list|status|checks|diff)([[:space:]]|$)|repo[[:space:]]+(view|list)([[:space:]]|$)|release[[:space:]]+(view|list)([[:space:]]|$)|run[[:space:]]+(view|list)([[:space:]]|$)|workflow[[:space:]]+(view|list)([[:space:]]|$)|search[[:space:]]+(issues|prs|repos|code)([[:space:]]|$))'; then
        return 1
      fi
    fi
  done <<< "$segments"

  return 0
}

is_sensitive_path_token() {
  local token="$1"
  local base

  base="${token##*/}"

  case "$token" in
    .env|.env.*|*/.env|*/.env.*)
      return 0
      ;;
    .git|.git/*|*/.git|*/.git/*)
      return 0
      ;;
    .netrc|*/.netrc|.npmrc|*/.npmrc|.pypirc|*/.pypirc|.pgpass|*/.pgpass|.my.cnf|*/.my.cnf|.vault-token|*/.vault-token)
      return 0
      ;;
    .docker/config.json|*/.docker/config.json)
      return 0
      ;;
    .config/gh/hosts.yml|*/.config/gh/hosts.yml|.config/gh/hosts.yaml|*/.config/gh/hosts.yaml)
      return 0
      ;;
    .kube/config|*/.kube/config)
      return 0
      ;;
    .cargo/credentials|*/.cargo/credentials|.cargo/credentials.toml|*/.cargo/credentials.toml)
      return 0
      ;;
    .gem/credentials|*/.gem/credentials)
      return 0
      ;;
  esac

  case "$base" in
    id_rsa|id_dsa|id_ed25519|*.pem|*.p12|*.pfx|credentials|credentials.json|secret|secrets|secret.json|secrets.json|secret.yaml|secrets.yaml|secret.yml|secrets.yml|secret.txt|secrets.txt)
      return 0
      ;;
  esac

  case "$token" in
    *private-key*|*private_key*)
      return 0
      ;;
  esac

  return 1
}

command_has_sensitive_file_reference() {
  local command="$1"
  local token

  while IFS= read -r token; do
    [ -z "$token" ] && continue
    if is_sensitive_path_token "$token"; then
      return 0
    fi
  done <<< "$(shell_visible_tokens "$command")"

  if echo "$command" | grep -iqE '(^|[[:space:]/])\.env($|[[:space:]/.;|&])|\.env\.[^[:space:];|&]*|id_(rsa|dsa|ed25519)|\.(pem|p12|pfx)($|[[:space:];|&])|private[-_]?key|credentials(\.json)?|secrets?(\.(json|ya?ml|txt))?|(^|[[:space:]/])\.git($|/|[[:space:];|&])'; then
    return 0
  fi

  return 1
}

command_has_db_cli_mutation_keyword() {
  local command="$1"
  local masked

  echo "$command" | grep -qE '(^|[[:space:];|&])([^[:space:];|&]*/)?(mysql|psql|sqlite3|mongo|mongosh)([[:space:]]|$)' || return 1

  masked=$(command_without_quoted_text "$command")

  # Fails closed: redirected SQL content cannot be statically inspected for mutation intent.
  if echo "$masked" | grep -qE '(^|[[:space:];|&])([^[:space:];|&]*/)?(mysql|psql|sqlite3|mongo|mongosh)[^;|&]*<'; then
    return 0
  fi

  if echo "$command" | grep -iqE '\b(INSERT|UPDATE|DELETE|ALTER|DROP|TRUNCATE|CREATE|REPLACE|GRANT|REVOKE|MERGE|VACUUM|CALL|EXEC|EXECUTE|PERFORM|DO)\b'; then
    return 0
  fi

  echo "$command" | grep -qE '\.(insertOne|insertMany|updateOne|updateMany|deleteOne|deleteMany|dropDatabase|dropCollection|findOneAndUpdate|findOneAndDelete|findOneAndReplace|bulkWrite|replaceOne|createIndex|dropIndex|renameCollection|remove|save)[[:space:]]*\('
}

check_readonly_agent_command() {
  local command="$1"
  local matched=""

  if [ -n "$PATTERNS" ] && command_matches_patterns "$command"; then
    matched=$(command_pattern_match "$command")
    block_readonly_agent_command "destructive command detected: $matched"
  fi

  if command_has_command_substitution "$command"; then
    block_readonly_agent_command "command substitution"
  fi

  if command_has_process_substitution "$command"; then
    block_readonly_agent_command "process substitution"
  fi

  if command_has_unquoted_eval "$command"; then
    block_readonly_agent_command "eval command"
  fi

  if command_has_nested_shell_execution "$command"; then
    block_readonly_agent_command "nested shell execution"
  fi

  if has_shell_file_write_redirection "$command"; then
    block_readonly_agent_command "shell file write/redirection"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])tee([[:space:]]|$)'; then
    block_readonly_agent_command "tee can write files"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])((npm|pnpm|yarn|bun)([[:space:]]+(--prefix|--dir|--cwd|-C)(=|[[:space:]]+)[^[:space:];|&]+|[[:space:]]+--[[:alnum:]-]+(=[^[:space:];|&]+)?)*[[:space:]]+(install|i|ci|add|update|upgrade|remove|uninstall)|pip3?[[:space:]]+install|bundle[[:space:]]+install|gem[[:space:]]+install|cargo[[:space:]]+(install|update|add)|go[[:space:]]+get|brew[[:space:]]+(install|upgrade|uninstall)|apt(-get)?[[:space:]]+(install|upgrade|remove)|composer[[:space:]]+(install|update|require|remove))([[:space:]]|$)'; then
    block_readonly_agent_command "package or dependency mutation command"
  fi

  if command_has_filesystem_mutation "$command"; then
    block_readonly_agent_command "filesystem mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])sed[[:space:]][^;|&]*(--in-place(=|[[:space:]]|$)|-[^[:space:];|&]*i([^[:alnum:]]|$))|(^|[[:space:];|&])perl[[:space:]][^;|&]*-[^[:space:];|&]*p?i([^[:alnum:]]|$)'; then
    block_readonly_agent_command "in-place edit command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])git([^;|&]*)[[:space:]]+diff([^;|&]*)(--output(=|[[:space:]]|$))'; then
    block_readonly_agent_command "git output file command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])git[[:space:]]+' && ! scout_git_segments_are_readonly "$command"; then
    block_readonly_agent_command "git state mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])git([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)(=|[[:space:]]+)[^[:space:];|&]+|[[:space:]]+(--no-pager|--bare|--literal-pathspecs|--[[:alnum:]-]+(=[^[:space:];|&]+)?))*[[:space:]]+(add|commit|push|reset|checkout|switch|merge|rebase|cherry-pick|tag|branch|clean|stash|restore|rm|mv|pull|fetch)([[:space:]]|$)'; then
    block_readonly_agent_command "git state mutation command"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])((systemctl|service|launchctl)[[:space:]]+(start|stop|restart|reload)|brew[[:space:]]+services[[:space:]]+(start|stop|restart)|docker([[:space:]]+compose)?[[:space:]]+(up|down|rm|rmi|volume|system|network))([[:space:]]|$)'; then
    block_readonly_agent_command "service/container mutation command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)([[:space:]]-X[[:space:]]*([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|[[:space:]]-X([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|--request(=|[[:space:]]+)([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|--data($|[=[:space:]])|--data-(ascii|raw|binary)(=|[[:space:]]|$)|--json(=|[[:space:]]|$)|[[:space:]]-[[:alnum:]]*d($|[[:space:]]|[^[:space:];|&])|--form(=|[[:space:]]|$)|[[:space:]]-[[:alnum:]]*F($|[[:space:]]|[^[:space:];|&])|[[:space:]]-[[:alnum:]]*T($|[[:space:]]|[^[:space:];|&])|--upload-file(=|[[:space:]]|$))'; then
    block_readonly_agent_command "mutating curl request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])curl([^;|&]*)--data-urlencode(=|[[:space:]]|$)' && ! curl_uses_get_query_mode "$command"; then
    block_readonly_agent_command "mutating curl request"
  fi

  if echo "$command" | grep -iqE '(^|[[:space:];|&])curl([^;|&]*)([[:space:]]-[[:alnum:]]*o[[:alnum:]]*($|[[:space:]]|[^[:space:];|&])|--output(=|[[:space:]]|$)|--output-dir(=|[[:space:]]|$)|--remote-name([[:space:]]|$))|(^|[[:space:];|&])wget([[:space:]]|$)'; then
    block_readonly_agent_command "local output file command"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--method(=|[[:space:]]+)([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|-X[[:space:]]*([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee])|-X([Pp][Oo][Ss][Tt]|[Pp][Uu][Tt]|[Pp][Aa][Tt][Cc][Hh]|[Dd][Ee][Ll][Ee][Tt][Ee]))'; then
    block_readonly_agent_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--input(=|[[:space:]]|$))'; then
    block_readonly_agent_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+api([^;|&]*)(--field(=|[[:space:]]|$)|--raw-field(=|[[:space:]]|$)|-f($|[[:space:]]|[^[:space:];|&])|-F($|[[:space:]]|[^[:space:];|&]))' && ! gh_api_uses_explicit_get "$command"; then
    block_readonly_agent_command "mutating gh api request"
  fi

  if echo "$command" | grep -qE '(^|[[:space:];|&])gh[[:space:]]+' && ! scout_gh_segments_are_readonly "$command"; then
    block_readonly_agent_command "mutating gh command"
  fi

  if command_has_sensitive_file_reference "$command"; then
    block_readonly_agent_command "sensitive file read"
  fi

  if command_has_db_cli_mutation_keyword "$command"; then
    block_readonly_agent_command "raw database mutation via CLI"
  fi
}

case "$ACTIVE_AGENT_ROLE" in
  scout|qa)
    check_readonly_agent_command "$COMMAND"
    ;;
esac

[ "${VBW_ALLOW_DESTRUCTIVE:-0}" = "1" ] && exit 0

if [ -f "$PLANNING_DIR/config.json" ]; then
  GUARD=$(jq -r '.bash_guard // true' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "$GUARD" = "false" ] && exit 0
fi

[ -z "$PATTERNS" ] && exit 0

if command_matches_patterns "$COMMAND"; then
  MATCHED=$(command_pattern_match "$COMMAND")
  echo "Blocked: destructive command detected ($MATCHED)" >&2
  echo "Hint: Use VBW_ALLOW_DESTRUCTIVE=1 to override, or run outside VBW." >&2
  echo "See: config/destructive-commands.txt for the full blocklist." >&2
  log_block_event "$MATCHED"

  exit 2
fi

exit 0
