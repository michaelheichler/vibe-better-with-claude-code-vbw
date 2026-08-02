#!/usr/bin/env bash

now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown"
}

bool_to_json() {
  if [ "${1:-false}" = "true" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}

normalize_version() {
  local value="$1"
  value="${value#v}"
  awk -v s="$value" 'BEGIN { if (match(s, /[0-9]+([.][0-9]+)+/)) print substr(s, RSTART, RLENGTH); }'
}

version_gt() {
  local left right
  left="$(normalize_version "$1")"
  right="$(normalize_version "$2")"
  [ -n "$left" ] && [ -n "$right" ] || return 1
  awk -v a="$left" -v b="$right" '
    BEGIN {
      split(a, av, "."); split(b, bv, ".");
      for (i = 1; i <= 4; i++) {
        ai = (av[i] == "" ? 0 : av[i] + 0);
        bi = (bv[i] == "" ? 0 : bv[i] + 0);
        if (ai > bi) exit 0;
        if (ai < bi) exit 1;
      }
      exit 1;
    }
  '
}

path_contains_dir() {
  local dir="$1"
  case ":${PATH:-}:" in
    *":$dir:"*) return 0 ;;
    *) return 1 ;;
  esac
}

canonical_executable_path() {
  local path="$1" dir base dir_real
  [ -n "$path" ] || return 0
  dir="$(dirname "$path")"
  base="$(basename "$path")"
  if dir_real="$(cd "$dir" 2>/dev/null && pwd -P)"; then
    printf '%s/%s\n' "$dir_real" "$base"
  else
    printf '%s\n' "$path"
  fi
}

same_executable_path() {
  local left="$1" right="$2" left_real right_real
  [ -n "$left" ] && [ -n "$right" ] || return 1
  left_real="$(canonical_executable_path "$left")"
  right_real="$(canonical_executable_path "$right")"
  [ "$left_real" = "$right_real" ]
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

platform_os() {
  uname -s 2>/dev/null || echo unknown
}

preferred_install_method_detect() {
  if [ "$(platform_os)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    echo "homebrew"
  else
    echo "github-release"
  fi
}

rtk_config_path() {
  case "$(platform_os)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Application Support/rtk/config.toml"
      ;;
    *)
      if [ -n "${XDG_CONFIG_HOME:-}" ]; then
        printf '%s\n' "$XDG_CONFIG_HOME/rtk/config.toml"
      else
        printf '%s\n' "$HOME/.config/rtk/config.toml"
      fi
      ;;
  esac
}

rtk_config_state() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "missing"
  elif [ ! -s "$path" ]; then
    echo "config_error"
  else
    echo "present"
  fi
}

rtk_path_from_receipt() {
  if [ -f "$RTK_RECEIPT_FILE" ] && jq empty "$RTK_RECEIPT_FILE" >/dev/null 2>&1; then
    jq -r '.binary_path // empty' "$RTK_RECEIPT_FILE" 2>/dev/null || true
  fi
}

rtk_path_detect() {
  local path
  path="$(command_path rtk)"
  if [ -n "$path" ]; then
    printf '%s\n' "$path"
  fi
}

shell_first_word_unquote() {
  local input="$1" len i ch next quote="" started=false word=""
  len=${#input}
  i=0
  while [ "$i" -lt "$len" ]; do
    ch="${input:i:1}"
    if [ -z "$quote" ]; then
      case "$ch" in
        [[:space:]])
          if [ "$started" = "true" ]; then
            break
          fi
          ;;
        "'")
          started=true
          quote="single"
          ;;
        '"')
          started=true
          quote="double"
          ;;
        "\\")
          started=true
          if [ $((i + 1)) -lt "$len" ]; then
            next="${input:i+1:1}"
            word+="$next"
            i=$((i + 1))
          else
            word+="$ch"
          fi
          ;;
        *)
          started=true
          word+="$ch"
          ;;
      esac
    elif [ "$quote" = "single" ]; then
      if [ "$ch" = "'" ]; then
        quote=""
      else
        word+="$ch"
      fi
    else
      if [ "$ch" = '"' ]; then
        quote=""
      elif [ "$ch" = "\\" ] && [ $((i + 1)) -lt "$len" ]; then
        next="${input:i+1:1}"
        case "$next" in
          '$'|'`'|'"'|'\\')
            word+="$next"
            i=$((i + 1))
            ;;
          *)
            word+="$ch"
            ;;
        esac
      else
        word+="$ch"
      fi
    fi
    i=$((i + 1))
  done
  [ -z "$quote" ] || return 1
  [ "$started" = "true" ] || return 1
  printf '%s\n' "$word"
}

rtk_version_detect() {
  local path="$1" out
  [ -n "$path" ] || return 0
  out="$("$path" --version 2>/dev/null || true)"
  normalize_version "$out"
}

rtk_path_from_hook_command() {
  local command="$1" executable=""
  [ -n "$command" ] || return 0
  executable="$(shell_first_word_unquote "$command" 2>/dev/null || true)"
  case "$executable" in
    rtk) command_path rtk ;;
    */rtk) if [ -x "$executable" ]; then printf '%s\n' "$executable"; fi ;;
    *) return 0 ;;
  esac
}

receipt_managed() {
  [ -f "$RTK_RECEIPT_FILE" ] || return 1
  jq -e '.manager == "vbw"' "$RTK_RECEIPT_FILE" >/dev/null 2>&1
}

receipt_field() {
  local field="$1"
  [ -f "$RTK_RECEIPT_FILE" ] || return 0
  jq -r --arg field "$field" '.[$field] // empty' "$RTK_RECEIPT_FILE" 2>/dev/null || true
}

settings_valid() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq empty "$RTK_SETTINGS_JSON" >/dev/null 2>&1
}

settings_hook_command() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq -r '
    [
      .hooks.PreToolUse[]? as $group
      | ($group.matcher // "") as $matcher
      | $group.hooks[]?
      | (.command // "") as $command
      | ($command | gsub("[\"'\'' ]"; "")) as $match_command
      | select($match_command | test("(^|/)rtkhookclaude($|[;])|rtk-rewrite[.]sh"))
      | {matcher: $matcher, command: (.command // "")}
    ][0].command // ""
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || true
}

settings_hook_matcher() {
  [ -f "$RTK_SETTINGS_JSON" ] || return 0
  jq -r '
    [
      .hooks.PreToolUse[]? as $group
      | ($group.matcher // "") as $matcher
      | $group.hooks[]?
      | (.command // "") as $command
      | ($command | gsub("[\"'\'' ]"; "")) as $match_command
      | select($match_command | test("(^|/)rtkhookclaude($|[;])|rtk-rewrite[.]sh"))
      | {matcher: $matcher, command: (.command // "")}
    ][0].matcher // ""
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || true
}

settings_bash_hook_count() {
  [ -f "$RTK_SETTINGS_JSON" ] || { echo 0; return 0; }
  jq -r '
    [
      .hooks.PreToolUse[]?
      | select((.matcher // "") == "Bash" or (.matcher // "") == "")
      | .hooks[]?
      | select((.type // "command") == "command" and (.command // "") != "")
    ] | length
  ' "$RTK_SETTINGS_JSON" 2>/dev/null || echo 0
}

legacy_hook_present() {
  [ -f "$CLAUDE_DIR/hooks/rtk-rewrite.sh" ] || [ -f "$RTK_LEGACY_CLAUDE_DIR/hooks/rtk-rewrite.sh" ]
}

global_claude_ref_present() {
  [ -f "$RTK_CLAUDE_MD" ] || return 1
  grep -Fq '@RTK.md' "$RTK_CLAUDE_MD" 2>/dev/null
}

project_local_present() {
  [ -d ".rtk" ] || [ -f ".rtk/filters.toml" ]
}

vbw_bash_hook_present() {
  local hooks_json="$SCRIPT_DIR/../hooks/hooks.json"
  [ -f "$hooks_json" ] || return 1
  jq -e '
    .. | objects
    | select((.matcher? // "") == "Bash" or ((.command? // "") | contains("bash-guard.sh")))
  ' "$hooks_json" >/dev/null 2>&1
}

checksum_tool() {
  if command -v shasum >/dev/null 2>&1; then
    echo "shasum"
  elif command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  fi
}

sha256_file() {
  local file="$1" tool
  tool="$(checksum_tool)"
  [ -n "$tool" ] || die 1 "no SHA-256 tool found (need shasum or sha256sum)"
  case "$tool" in
    shasum) shasum -a 256 "$file" | awk '{print $1}' ;;
    sha256sum) sha256sum "$file" | awk '{print $1}' ;;
  esac
}

sha256_text() {
  local tool
  tool="$(checksum_tool)"
  [ -n "$tool" ] || return 0
  case "$tool" in
    shasum) shasum -a 256 | awk '{print $1}' ;;
    sha256sum) sha256sum | awk '{print $1}' ;;
  esac
}

os_arch_target() {
  local os arch
  os="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$arch" in
    arm64|aarch64) arch="aarch64" ;;
    x86_64|amd64) arch="x86_64" ;;
  esac
  case "$os:$arch" in
    Darwin:aarch64) echo "aarch64-apple-darwin" ;;
    Darwin:x86_64) echo "x86_64-apple-darwin" ;;
    Linux:aarch64) echo "aarch64-unknown-linux-gnu" ;;
    Linux:x86_64) echo "x86_64-unknown-linux-musl" ;;
    *) echo "" ;;
  esac
}
