#!/bin/bash

input=""
while IFS= read -t 1 -r _line; do
  input="${input}${_line}"
done 2>/dev/null
[ -n "${_line:-}" ] && input="${input}${_line}"
exec 0</dev/null

C='\033[36m' G='\033[32m' Y='\033[33m' R='\033[31m'
D='\033[2m' B='\033[1m' X='\033[0m'

_UID=$(id -u)
_OS=$(uname)
_SL_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
_VER=$(cat "$_SL_SCRIPT_DIR/../VERSION" 2>/dev/null | tr -d '[:space:]')
. "$_SL_SCRIPT_DIR/lib/vbw-config-root.sh"
. "$_SL_SCRIPT_DIR/lib/vbw-cache-key.sh"
find_vbw_root "$_SL_SCRIPT_DIR"

_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
_CACHE_ROOT="${VBW_CONFIG_ROOT:-$_REPO_ROOT}"
_CACHE=$(vbw_cache_prefix "${_VER:-0}" "$_UID" "$_CACHE_ROOT")

if ! [ -f "${_CACHE}-ok" ] || ! [ -O "${_CACHE}-ok" ]; then
  rm -f /tmp/vbw-sl-cache-"${_UID}" /tmp/vbw-usage-cache-"${_UID}" /tmp/vbw-gh-cache-"${_UID}" /tmp/vbw-team-cache-"${_UID}" /tmp/vbw-*-"${_UID}" 2>/dev/null
  for f in /tmp/vbw-*-"${_UID}"-fast /tmp/vbw-*-"${_UID}"-slow /tmp/vbw-*-"${_UID}"-cost /tmp/vbw-*-"${_UID}"-ok; do
    _stale_bn="${f##*/}"
    _stale_dc=$(echo "$_stale_bn" | tr -cd '-' | wc -c | tr -d ' ')
    [ "$_stale_dc" -le 3 ] && rm -f "$f" 2>/dev/null
  done
  unset _stale_bn _stale_dc f
  touch "${_CACHE}-ok"
fi


if [ -f "$_SL_SCRIPT_DIR/summary-utils.sh" ]; then
  . "$_SL_SCRIPT_DIR/summary-utils.sh"
else
  count_complete_summaries() { echo "0"; }
  count_done_summaries() { echo "0"; }
fi
if [ -f "$_SL_SCRIPT_DIR/uat-utils.sh" ]; then
  . "$_SL_SCRIPT_DIR/uat-utils.sh"
else
  normalize_uat_status() { echo "$1"; }
fi
if [ -f "$_SL_SCRIPT_DIR/phase-state-utils.sh" ]; then
  . "$_SL_SCRIPT_DIR/phase-state-utils.sh"
else
  count_phase_plans() {
    local dir="$1"
    local count=0
    local f
    for f in "$dir"/[0-9]*-PLAN.md "$dir"/PLAN.md; do
      [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
  }
  list_canonical_phase_dirs() {
    local parent="$1"
    [ -d "$parent" ] || return 0
    local dirs=() d base
    for d in "$parent"/*/; do
      [ -d "$d" ] || continue
      base="${d%/}"; base="${base##*/}"
      case "$base" in [0-9]*-*) dirs+=("${d%/}") ;; esac
    done
    [ ${#dirs[@]} -gt 0 ] || return 0
    printf '%s\n' "${dirs[@]}" | sort -V 2>/dev/null || \
      printf '%s\n' "${dirs[@]}" | awk -F/ '{n=$NF; gsub(/[^0-9].*/,"",n); if (n == "") n=0; print (n+0)"\t"$0}' | sort -n -k1,1 -k2,2 | cut -f2-
  }
  find_phase_dir_by_ref() {
    local planning_dir="$1" phase_ref="$2"
    local prefix_match
    [ -d "$planning_dir/phases" ] || return 0
    [ -n "$phase_ref" ] || return 0
    echo "$phase_ref" | grep -qE '^[0-9]+$' || return 0
    prefix_match=$(ls -d "$planning_dir/phases/$(printf '%02d' "$phase_ref")"-*/ 2>/dev/null | head -1)
    [ -n "$prefix_match" ] && { echo "$prefix_match"; return 0; }
    list_canonical_phase_dirs "$planning_dir/phases" | sed -n "${phase_ref}p"
  }
fi

if [ -f "$_SL_SCRIPT_DIR/verification-freshness.sh" ]; then
  . "$_SL_SCRIPT_DIR/verification-freshness.sh"
else
  verification_is_stale() { return 0; }
fi

qa_verification_stale() {
  verification_is_stale "$1"
}

cache_fresh() {
  local cf="$1" ttl="$2"
  [ ! -f "$cf" ] && return 1
  [ ! -O "$cf" ] && rm -f "$cf" 2>/dev/null && return 1
  local mt
  if [ "$_OS" = "Darwin" ]; then
    mt=$(stat -f %m "$cf" 2>/dev/null || echo 0)
  else
    mt=$(stat -c %Y "$cf" 2>/dev/null || echo 0)
  fi
  [ $((NOW - mt)) -le "$ttl" ]
}

file_mtime_epoch() {
  local path="$1"
  if [ "$_OS" = "Darwin" ]; then
    stat -f %m "$path" 2>/dev/null || echo 0
  else
    stat -c %Y "$path" 2>/dev/null || echo 0
  fi
}

lifecycle_artifacts_newer_than_cache() {
  local cf="$1" planning_dir="$2"
  local cache_mt artifact artifact_mt
  [ -f "$cf" ] || return 1
  [ -d "$planning_dir/phases" ] || return 1

  cache_mt=$(file_mtime_epoch "$cf")
  while IFS= read -r artifact; do
    [ -f "$artifact" ] || continue
    artifact_mt=$(file_mtime_epoch "$artifact")
    if [ "$artifact_mt" -ge "$cache_mt" ] 2>/dev/null; then
      return 0
    fi
  done < <(find "$planning_dir/phases" -type f \( \( -name '*-UAT.md' ! -name '*-SOURCE-UAT.md' \) -o -name '*VERIFICATION.md' -o -name '.qa-remediation-stage' -o -name '.uat-remediation-stage' \) 2>/dev/null)

  return 1
}

atomic_write_string() {
  local target="$1" content="$2" tmp
  tmp="${target}.tmp.$$.$RANDOM"
  if printf '%s\n' "$content" > "$tmp" 2>/dev/null && mv "$tmp" "$target" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null || true
  return 1
}

acquire_lock_dir() {
  local lock_dir="$1" attempts=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    attempts=$((attempts + 1))
    [ "$attempts" -ge 100 ] && return 1
    if [ -f "$lock_dir/pid" ]; then
      local lock_pid
      lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -f "$lock_dir/pid" 2>/dev/null || true
        rmdir "$lock_dir" 2>/dev/null || true
        continue
      fi
    else
      local pw=0
      while [ "$pw" -lt 5 ] && [ ! -f "$lock_dir/pid" ]; do
        sleep 0.02
        pw=$((pw + 1))
      done
      if [ -f "$lock_dir/pid" ]; then
        continue
      fi
      rmdir "$lock_dir" 2>/dev/null || true
      continue
    fi
    sleep 0.02
  done
  printf '%s\n' "$$" > "$lock_dir/pid" 2>/dev/null || true
  return 0
}

release_lock_dir() {
  local lock_dir="$1"
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || rm -rf "$lock_dir" 2>/dev/null || true
}

_resolve_notraffic() {
  _NOTRAFFIC_ACTIVE=""
  local _val="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
  if [ -z "$_val" ]; then
    local _sdir
    for _sdir in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
      [ -z "$_sdir" ] && continue
      [ -f "$_sdir/settings.json" ] || continue
      _val=$(jq -r '.env.CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC // ""' "$_sdir/settings.json" 2>/dev/null)
      [ -n "$_val" ] && break
    done
  fi
  case "$_val" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) _NOTRAFFIC_ACTIVE=1 ;;
  esac
}

progress_bar() {
  local pct="$1" width="$2"
  local filled=$((pct * width / 100))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$pct" -gt 0 ] && [ "$filled" -eq 0 ] && filled=1
  local empty=$((width - filled))
  local color
  if [ "$pct" -ge 80 ]; then color="$R"
  elif [ "$pct" -ge 50 ]; then color="$Y"
  else color="$G"
  fi
  local bar=""
  [ "$filled" -gt 0 ] && bar=$(printf "%${filled}s" | sed 's/ /█/g')
  [ "$empty" -gt 0 ] && bar="${bar}$(printf "%${empty}s" | sed 's/ /░/g')"
  printf '%b%s%b' "$color" "$bar" "$X"
}

fmt_tok() {
  local v=$1
  if [ "$v" -ge 1000000 ]; then
    local d=$((v / 1000000)) r=$(( (v % 1000000 + 50000) / 100000 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dM" "$d" "$r"
  elif [ "$v" -ge 1000 ]; then
    local d=$((v / 1000)) r=$(( (v % 1000 + 50) / 100 ))
    [ "$r" -ge 10 ] && d=$((d + 1)) && r=0
    printf "%d.%dK" "$d" "$r"
  else
    printf "%d" "$v"
  fi
}

fmt_cost() {
  local whole="${1%%.*}" frac="${1#*.}"
  local cents="${frac:0:2}"
  cents=$((10#${cents:-0}))
  whole=$((10#${whole:-0}))
  local total_cents=$(( whole * 100 + cents ))
  if [ "$total_cents" -ge 10000 ]; then printf "\$%d" "$whole"
  elif [ "$total_cents" -ge 1000 ]; then printf "\$%d.%d" "$whole" $((cents / 10))
  else printf "\$%d.%02d" "$whole" "$cents"
  fi
}

fmt_dur() {
  local s=$(($1 / 1000))
  if [ "$s" -ge 3600 ]; then
    printf "%dh %dm" $((s / 3600)) $(( (s % 3600) / 60 ))
  elif [ "$s" -ge 60 ]; then
    printf "%dm %ds" $((s / 60)) $((s % 60))
  else
    printf "%ds" "$s"
  fi
}

IFS='|' read -r PCT REM IN_TOK OUT_TOK CACHE_W CACHE_R CTX_SIZE \
               COST DUR_MS API_MS ADDED REMOVED MODEL VER <<< \
  "$(echo "$input" | jq -r '[
    (.context_window.used_percentage // 0 | floor),
    (.context_window.remaining_percentage // 100 | floor),
    (.context_window.current_usage.input_tokens // 0),
    (.context_window.current_usage.output_tokens // 0),
    (.context_window.current_usage.cache_creation_input_tokens // 0),
    (.context_window.current_usage.cache_read_input_tokens // 0),
    (.context_window.context_window_size // 200000),
    (.cost.total_cost_usd // 0),
    (.cost.total_duration_ms // 0),
    (.cost.total_api_duration_ms // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.model.display_name // "Claude"),
    (.version // "?")
  ] | join("|")' 2>/dev/null)"

PCT=${PCT:-0}; REM=${REM:-100}; IN_TOK=${IN_TOK:-0}; OUT_TOK=${OUT_TOK:-0}
CACHE_W=${CACHE_W:-0}; CACHE_R=${CACHE_R:-0}; COST=${COST:-0}
DUR_MS=${DUR_MS:-0}; API_MS=${API_MS:-0}; ADDED=${ADDED:-0}; REMOVED=${REMOVED:-0}
MODEL=${MODEL:-Claude}; VER=${VER:-?}


_AC_DISABLED=""
_AC_OVERRIDE=""
_AC_WINDOW_CAP=""
_AC_MAX_OUTPUT=""

_AC_SETTINGS_ENV=""
for _sdir in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude"; do
  [ -z "$_sdir" ] && continue
  [ -f "$_sdir/settings.json" ] || continue
  _AC_SETTINGS_ENV=$(jq -r '[
    .env.DISABLE_AUTO_COMPACT // "",
    .env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // "",
    .env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // "",
    .env.CLAUDE_CODE_MAX_OUTPUT_TOKENS // ""
  ] | join("|")' "$_sdir/settings.json" 2>/dev/null)
  [ -n "$_AC_SETTINGS_ENV" ] && [ "$_AC_SETTINGS_ENV" != "|||" ] && break
done
IFS='|' read -r _S_DISABLED _S_OVERRIDE _S_WINDOW _S_OUTPUT <<< "$_AC_SETTINGS_ENV"

_AC_DISABLED="${DISABLE_AUTO_COMPACT:-$_S_DISABLED}"
_AC_OVERRIDE="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-$_S_OVERRIDE}"
_AC_WINDOW_CAP="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-$_S_WINDOW}"
_AC_MAX_OUTPUT="${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-$_S_OUTPUT}"

_AC_SKIP=false
case "$_AC_DISABLED" in
  1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) _AC_SKIP=true ;;
esac

_ac_dec() { local v="${1#"${1%%[!0]*}"}"; echo "${v:-0}"; }

if [ "$_AC_SKIP" = "false" ] && [ "${CTX_SIZE:-0}" -gt 0 ] 2>/dev/null; then
  _AC_CTX="$CTX_SIZE"
  if [ -n "$_AC_WINDOW_CAP" ]; then
    _WC="$(_ac_dec "${_AC_WINDOW_CAP%%.*}")"
    if [ "$_WC" -gt 0 ] 2>/dev/null && [ "$_WC" -lt "$_AC_CTX" ] 2>/dev/null; then
      _AC_CTX="$_WC"
    fi
  fi

  _OUT_CAP=20000
  if [ -n "$_AC_MAX_OUTPUT" ]; then
    _MO="$(_ac_dec "${_AC_MAX_OUTPUT%%.*}")"
    if [ "$_MO" -gt 0 ] 2>/dev/null && [ "$_MO" -lt 20000 ] 2>/dev/null; then
      _OUT_CAP="$_MO"
    fi
  fi

  _EFF=$((_AC_CTX - _OUT_CAP))
  [ "$_EFF" -lt 0 ] && _EFF=0

  _DEF_TRIGGER=$((_EFF - 13000))
  [ "$_DEF_TRIGGER" -lt 0 ] && _DEF_TRIGGER=0

  _TRIGGER="$_DEF_TRIGGER"

  if [ -n "$_AC_OVERRIDE" ]; then
    _OV_WHOLE="$(_ac_dec "${_AC_OVERRIDE%%.*}")"
    _OV_FRAC="0"
    case "$_AC_OVERRIDE" in
      *.*) _OV_FRAC="${_AC_OVERRIDE#*.}"; _OV_FRAC="$(_ac_dec "${_OV_FRAC:0:1}")"; _OV_FRAC="${_OV_FRAC:-0}" ;;
    esac
    if [ "$_OV_WHOLE" -ge 0 ] 2>/dev/null && [ "$_OV_FRAC" -ge 0 ] 2>/dev/null; then
      _OV_PCT_X10=$((_OV_WHOLE * 10 + _OV_FRAC))
      if [ "$_OV_PCT_X10" -gt 0 ] && [ "$_OV_PCT_X10" -le 1000 ]; then
        _OV_TRIGGER=$((_EFF * _OV_PCT_X10 / 1000))
        [ "$_OV_TRIGGER" -lt "$_DEF_TRIGGER" ] && _TRIGGER="$_OV_TRIGGER"
      fi
    fi
  fi

  if [ "$_TRIGGER" -gt 0 ]; then
    _BUFFER=$((CTX_SIZE - _TRIGGER))
    _BUF_PCT_X10=$((_BUFFER * 1000 / CTX_SIZE))

    _REM_X10=$((REM * 10))
    [ "$_BUF_PCT_X10" -ge 1000 ] && _BUF_PCT_X10=999  # defensive: prevent division by zero
    _USABLE_REM=$(( (_REM_X10 - _BUF_PCT_X10) * 1000 / (1000 - _BUF_PCT_X10) ))
    [ "$_USABLE_REM" -lt 0 ] && _USABLE_REM=0
    [ "$_USABLE_REM" -gt 1000 ] && _USABLE_REM=1000

    PCT=$(( 100 - (_USABLE_REM + 5) / 10 ))
    [ "$PCT" -lt 0 ] && PCT=0
    [ "$PCT" -gt 100 ] && PCT=100
    REM=$((100 - PCT))
    CTX_SIZE="$_TRIGGER"
  fi
fi

NOW=$(date +%s)

CTX_USED=$((IN_TOK + CACHE_W + CACHE_R))
CTX_USED_FMT=$(fmt_tok "$CTX_USED")
CTX_SIZE_FMT=$(fmt_tok "$CTX_SIZE")

if [ -d "$VBW_PLANNING_DIR" ]; then
  printf '%s\n' "${CLAUDE_SESSION_ID:-unknown}|${PCT}|${CTX_SIZE}" > "$VBW_PLANNING_DIR/.context-usage" 2>/dev/null || true
fi
IN_TOK_FMT=$(fmt_tok "$IN_TOK")
OUT_TOK_FMT=$(fmt_tok "$OUT_TOK")
CACHE_W_FMT=$(fmt_tok "$CACHE_W")
CACHE_R_FMT=$(fmt_tok "$CACHE_R")
DUR_FMT=$(fmt_dur "$DUR_MS")
API_DUR_FMT=$(fmt_dur "$API_MS")
TOTAL_INPUT=$((IN_TOK + CACHE_W + CACHE_R))
CACHE_HIT_PCT=0
[ "$TOTAL_INPUT" -gt 0 ] && CACHE_HIT_PCT=$(( CACHE_R * 100 / TOTAL_INPUT ))
if [ "$CACHE_HIT_PCT" -ge 70 ]; then CACHE_COLOR="$G"
elif [ "$CACHE_HIT_PCT" -ge 40 ]; then CACHE_COLOR="$Y"
else CACHE_COLOR="$R"
fi

FAST_CF="${_CACHE}-fast"

if ! cache_fresh "$FAST_CF" 5 || lifecycle_artifacts_newer_than_cache "$FAST_CF" "$VBW_PLANNING_DIR"; then
  PH=""; TT=""; EF="balanced"; MP="quality"; BR=""
  PD=0; PT=0; PPD=0; PPT=0; QA="--"; QA_COLOR="D"; GH_URL=""
  PP_LABEL="this phase"; REM_ACTIVE="false"
  if [ -f "$VBW_PLANNING_DIR/STATE.md" ]; then
    _phase_line=$(grep -m1 "^Phase:" "$VBW_PLANNING_DIR/STATE.md" 2>/dev/null)
    PH=$(echo "$_phase_line" | sed -n 's/^Phase:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
    TT=$(echo "$_phase_line" | sed -n 's/.*[[:space:]]of[[:space:]]*\([0-9][0-9]*\).*/\1/p')
  fi
  if [ -f "$VBW_PLANNING_DIR/config.json" ]; then
    if ! jq -e '.model_profile' "$VBW_PLANNING_DIR/config.json" >/dev/null 2>&1; then
      TMP=$(mktemp)
      jq '. + {model_profile: "quality", model_overrides: {}}' "$VBW_PLANNING_DIR/config.json" > "$TMP" && mv "$TMP" "$VBW_PLANNING_DIR/config.json"
    fi
    EF=$(jq -r '.effort // "balanced"' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)
    MP=$(jq -r '.model_profile // "quality"' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)
    HIDE_AGENT_TMUX=$(jq -r '.statusline_hide_agent_in_tmux // false' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)
    COLLAPSE_AGENT_TMUX=$(jq -r '.statusline_collapse_agent_in_tmux // false' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)
  fi
  if git rev-parse --git-dir >/dev/null 2>&1; then
    BR=$(git branch --show-current 2>/dev/null)
    GH_URL=$(git remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||' | sed 's|https://[^@]*@|https://|')
    GIT_STAGED=$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_MODIFIED=$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  fi
  if [ -d "$VBW_PLANNING_DIR/phases" ]; then
    PT=0
    PD=0
    while IFS= read -r _sl_pdir; do
      [ -d "$_sl_pdir" ] || continue
      PT=$((PT + $(count_phase_plans "$_sl_pdir")))
      PD=$((PD + $(count_complete_summaries "$_sl_pdir")))
      for _sl_rdir in "$_sl_pdir"remediation/uat/round-*/; do
        [ -d "$_sl_rdir" ] || continue
        PD=$((PD + $(count_complete_summaries "$_sl_rdir")))
      done
    done < <(list_canonical_phase_dirs "$VBW_PLANNING_DIR/phases")
    if [ -n "$PH" ] && [ "$PH" != "0" ]; then
      PDIR=$(find_phase_dir_by_ref "$VBW_PLANNING_DIR" "$PH")
      [ -n "$PDIR" ] && PPD=$(count_complete_summaries "$PDIR")
      [ -n "$PDIR" ] && PPT=$(count_phase_plans "$PDIR")
      if [ -n "$PDIR" ] && [ -f "$PDIR/remediation/uat/.uat-remediation-stage" ]; then
        REM_ACTIVE="true"
        PP_LABEL="this remediation"
        _rem_ppt=0; _rem_ppd=0
        for _rem_rdir in "$PDIR"/remediation/uat/round-*/; do
          [ -d "$_rem_rdir" ] || continue
          _rem_ppt=$((_rem_ppt + $(find "$_rem_rdir" -maxdepth 1 -name '*-PLAN.md' 2>/dev/null | wc -l | tr -d ' ')))
          _rem_ppd=$((_rem_ppd + $(count_complete_summaries "$_rem_rdir")))
        done
        PPT="$_rem_ppt"
        PPD="$_rem_ppd"
      elif [ -n "$PDIR" ] && [ -f "$PDIR/.uat-remediation-stage" ]; then
        REM_ACTIVE="true"
        PP_LABEL="this remediation"
      fi
      if [ -n "$PDIR" ]; then
        _uat_file=$(current_uat "$PDIR" 2>/dev/null || true)
        [ -n "$_uat_file" ] && [ ! -f "$_uat_file" ] && _uat_file=""
        if [ -n "$_uat_file" ]; then
          _uat_status=$(awk 'NR==1 && /^---/{f=1;next} f && /^---/{exit} f && /^status:/{gsub(/^status:[[:space:]]*/,""); print; exit}' "$_uat_file" 2>/dev/null | tr '[:upper:]' '[:lower:]')
          _uat_status=$(normalize_uat_status "$_uat_status")
          case "$_uat_status" in
            complete)
              QA="UAT: pass"; QA_COLOR="G"
              ;;
            in_progress|in-progress|draft|pending)
              QA="UAT: in progress"; QA_COLOR="Y"
              ;;
            issues_found)
              _rem_stage="none"
              if [ -f "$PDIR/remediation/uat/.uat-remediation-stage" ]; then
                _rem_stage=$(grep '^stage=' "$PDIR/remediation/uat/.uat-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
                _rem_stage="${_rem_stage:-none}"
              elif [ -f "$PDIR/.uat-remediation-stage" ]; then
                _rem_stage=$(tr -d '[:space:]' < "$PDIR/.uat-remediation-stage")
              fi
              case "$_rem_stage" in
                none)         QA="UAT: Issues";       QA_COLOR="R" ;;
                research)     QA="UAT: Researching";  QA_COLOR="Y" ;;
                plan)         QA="UAT: Planning";     QA_COLOR="Y" ;;
                execute|fix)  QA="UAT: Fixing";       QA_COLOR="Y" ;;
                done|verify|verified) QA="UAT: Verification"; QA_COLOR="Y" ;;
                *)            QA="UAT: Fixing";       QA_COLOR="Y" ;;
              esac ;;
            *) QA="UAT: ?"; QA_COLOR="Y" ;;
          esac
        elif [ -f "$PDIR/remediation/qa/.qa-remediation-stage" ]; then
          _qa_rem_stage=$(grep '^stage=' "$PDIR/remediation/qa/.qa-remediation-stage" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
          _qa_rem_stage="${_qa_rem_stage:-none}"
          case "$_qa_rem_stage" in
            plan)    QA="QA: Planning fix"; QA_COLOR="Y" ;;
            execute) QA="QA: Fixing";       QA_COLOR="Y" ;;
            verify)  QA="QA: Re-verifying"; QA_COLOR="Y" ;;
            done)    ;;
            *)       _qa_rem_stage="none" ;;
          esac
        fi
        if [ -z "$_uat_file" ]; then
          _verif_file=""
          if [ "${_qa_rem_stage:-none}" = "done" ]; then
            _verif_file=$(bash "$_SL_SCRIPT_DIR/resolve-verification-path.sh" current "$PDIR" 2>/dev/null || true)
            [ -n "$_verif_file" ] && [ ! -f "$_verif_file" ] && _verif_file=""
          elif [ "${_qa_rem_stage:-none}" = "none" ]; then
            _verif_file=$(bash "$_SL_SCRIPT_DIR/resolve-verification-path.sh" phase "$PDIR" 2>/dev/null || true)
            [ -n "$_verif_file" ] && [ ! -f "$_verif_file" ] && _verif_file=""
          fi
          if [ -n "$_verif_file" ]; then
            _qa_result=$(awk '
              BEGIN { in_fm=0 }
              NR==1 && /^---[[:space:]]*$/ { in_fm=1; next }
              in_fm && /^---[[:space:]]*$/ { exit }
              in_fm && /^result:/ { sub(/^result:[[:space:]]*/, ""); print; exit }
            ' "$_verif_file" 2>/dev/null) || _qa_result=""
            case "$_qa_result" in
              PASS)
                if qa_verification_stale "$_verif_file"; then
                  QA="QA: pending"; QA_COLOR="Y"
                else
                  QA="QA: pass"; QA_COLOR="G"
                fi
                ;;
              FAIL) QA="QA: FAIL"; QA_COLOR="R" ;;
              PARTIAL) QA="QA: partial"; QA_COLOR="Y" ;;
              *) QA="QA: pending"; QA_COLOR="Y" ;;
            esac
          fi
        fi
      fi
    fi
  fi

  EXEC_STATUS=""; EXEC_WAVE=0; EXEC_TWAVES=0; EXEC_DONE=0; EXEC_TOTAL=0; EXEC_CURRENT=""
  if [ -f "$VBW_PLANNING_DIR/.execution-state.json" ]; then
    IFS='|' read -r EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT <<< \
      "$(jq -r '[
        (.status // ""),
        (.wave // 0),
        (.total_waves // 0),
        ([.plans[] | select(.status == "complete" or .status == "partial")] | length),
        (.plans | length),
        ([.plans[] | select(.status == "running")][0].title // "")
      ] | join("|")' "$VBW_PLANNING_DIR/.execution-state.json" 2>/dev/null)"
    if [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_DONE:-0}" -gt 0 ] 2>/dev/null; then
      _exec_phase=$(jq -r '.phase // ""' "$VBW_PLANNING_DIR/.execution-state.json" 2>/dev/null)
      if [ -n "$_exec_phase" ]; then
        _exec_pdir=$(find_phase_dir_by_ref "$VBW_PLANNING_DIR" "$_exec_phase")
        if [ -n "$_exec_pdir" ] && [ -d "$_exec_pdir" ]; then
          _actual_done=$(count_done_summaries "$_exec_pdir")
          if [ "${_actual_done:-0}" -lt "${EXEC_DONE:-0}" ] 2>/dev/null; then
            EXEC_DONE="$_actual_done"
          fi
        fi
      fi
    fi
  fi

  AGENT_DATA="0"

  _EXEC_CURRENT_SAFE="${EXEC_CURRENT//|/-}"

  atomic_write_string "$FAST_CF" "${PH:-0}|${TT:-0}|${EF}|${MP}|${BR}|${PD}|${PT}|${PPD}|${QA}|${GH_URL}|${GIT_STAGED:-0}|${GIT_MODIFIED:-0}|${GIT_AHEAD:-0}|${EXEC_STATUS:-}|${EXEC_WAVE:-0}|${EXEC_TWAVES:-0}|${EXEC_DONE:-0}|${EXEC_TOTAL:-0}|${_EXEC_CURRENT_SAFE:-}|${AGENT_DATA:-0}|${PPT:-0}|${QA_COLOR:-D}|${HIDE_AGENT_TMUX:-false}|${COLLAPSE_AGENT_TMUX:-false}|${PP_LABEL:-this phase}|${REM_ACTIVE:-false}" 2>/dev/null || true
fi

if [ -O "$FAST_CF" ]; then
  IFS='|' read -r PH TT EF MP BR PD PT PPD QA GH_URL GIT_STAGED GIT_MODIFIED GIT_AHEAD \
                  EXEC_STATUS EXEC_WAVE EXEC_TWAVES EXEC_DONE EXEC_TOTAL EXEC_CURRENT \
                  AGENT_N PPT QA_COLOR HIDE_AGENT_TMUX COLLAPSE_AGENT_TMUX \
                  PP_LABEL REM_ACTIVE < "$FAST_CF"
  PP_LABEL="${PP_LABEL:-this phase}"
  REM_ACTIVE="${REM_ACTIVE:-false}"
fi

VBW_CTX=0; [ -f "$VBW_PLANNING_DIR/.vbw-context" ] && VBW_CTX=1
if [ "$VBW_CTX" = "1" ]; then
  VC="${C}${B}"
else
  VC="${D}"
fi

AGENT_LINE=""

if [ -n "${TMUX:-}" ]; then
  _GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
  _GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$_GIT_DIR" ] && [ -n "$_GIT_COMMON" ] && [ "$_GIT_DIR" != "$_GIT_COMMON" ]; then
    _MAIN_ROOT=$(dirname "$_GIT_COMMON")
    _COLLAPSE_WT=$(jq -r '.statusline_collapse_agent_in_tmux // false' \
      "$_MAIN_ROOT/.vbw-planning/config.json" 2>/dev/null)
    if [ "$_COLLAPSE_WT" = "true" ]; then
      [ "$PCT" -ge 90 ] && BC="$R" || { [ "$PCT" -ge 70 ] && BC="$Y" || BC="$G"; }
      printf '%b\n' "Model: ${D}${MODEL}${X} ${D}│${X} Context: ${BC}${PCT}%${X} ${CTX_USED_FMT}/${CTX_SIZE_FMT} ${D}│${X} Tokens: ${IN_TOK_FMT}"
      exit 0
    fi
  fi
fi

SLOW_CF="${_CACHE}-slow"

_SLOW_TTL=60
if [ -O "$SLOW_CF" ]; then
  _PREV_STATUS=$(awk -F'|' '{print $10}' "$SLOW_CF" 2>/dev/null)
  [ "$_PREV_STATUS" = "fail" ] || [ "$_PREV_STATUS" = "ratelimited" ] && _SLOW_TTL=300
fi
if [ "$_SLOW_TTL" -gt 60 ] 2>/dev/null; then
  _resolve_notraffic
  [ -n "$_NOTRAFFIC_ACTIVE" ] && _SLOW_TTL=60
fi

if ! cache_fresh "$SLOW_CF" "$_SLOW_TTL"; then
  FIVE_PCT=0; FIVE_EPOCH=0; WEEK_PCT=0; WEEK_EPOCH=0; SONNET_PCT=-1
  EXTRA_ENABLED=0; EXTRA_PCT=-1; EXTRA_USED_C=0; EXTRA_LIMIT_C=0; FETCH_OK="noauth"
  OAUTH_TOKEN=""
  AUTH_METHOD=""
  AUTH_CLASS="api_key"
  HIDE_LIMITS=$(jq -r '.statusline_hide_limits // false' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)
  HIDE_LIMITS_API=$(jq -r '.statusline_hide_limits_for_api_key // false' "$VBW_PLANNING_DIR/config.json" 2>/dev/null)

  if [ -n "${VBW_OAUTH_TOKEN:-}" ]; then
    OAUTH_TOKEN="$VBW_OAUTH_TOKEN"
    AUTH_CLASS="oauth"
  fi

  if [ -z "$OAUTH_TOKEN" ] && [ "${VBW_SKIP_KEYCHAIN:-0}" != "1" ]; then
    if [ "$_OS" = "Darwin" ]; then
      CRED_JSON=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
      if [ -n "$CRED_JSON" ]; then
        OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
        [ -n "$OAUTH_TOKEN" ] && AUTH_CLASS="oauth"
      fi
    else
      if command -v secret-tool &>/dev/null; then
        CRED_JSON=$(secret-tool lookup service "Claude Code-credentials" 2>/dev/null)
        if [ -n "$CRED_JSON" ]; then
          OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
          [ -n "$OAUTH_TOKEN" ] && AUTH_CLASS="oauth"
        fi
      elif command -v pass &>/dev/null; then
        CRED_JSON=$(pass show "claude-code/credentials" 2>/dev/null)
        if [ -n "$CRED_JSON" ]; then
          OAUTH_TOKEN=$(echo "$CRED_JSON" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
          [ -n "$OAUTH_TOKEN" ] && AUTH_CLASS="oauth"
        fi
      fi
    fi
  fi

  if [ -z "$OAUTH_TOKEN" ]; then
    if [ "${VBW_SKIP_KEYCHAIN:-0}" = "1" ]; then
      _p3_dirs=("${CLAUDE_CONFIG_DIR:-}")
    else
      _p3_dirs=("${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude-code" "$HOME/.claude")
    fi
    for _cdir in "${_p3_dirs[@]}"; do
      [ -z "$_cdir" ] && continue
      for _cred in "$_cdir/.credentials.json" "$_cdir/credentials.json"; do
        if [ -f "$_cred" ]; then
          OAUTH_TOKEN=$(jq -r '.claudeAiOauth.accessToken // empty' "$_cred" 2>/dev/null)
          if [ -n "$OAUTH_TOKEN" ]; then
            AUTH_CLASS="oauth"
            break 2
          fi
        fi
      done
    done
  fi

  if [ -z "$OAUTH_TOKEN" ] && [ "${VBW_SKIP_AUTH_CLI:-0}" != "1" ]; then
    AUTH_STATUS=$(CLAUDECODE="" claude auth status --json 2>/dev/null) || AUTH_STATUS=""
    if [ -n "$AUTH_STATUS" ]; then
      AUTH_METHOD=$(echo "$AUTH_STATUS" | jq -r '.authMethod // empty' 2>/dev/null)
      [ "$AUTH_METHOD" = "claude.ai" ] && AUTH_CLASS="oauth"
    fi
  fi

  _resolve_notraffic
  [ -n "$_NOTRAFFIC_ACTIVE" ] && FETCH_OK="notraffic"

  if [ "$FETCH_OK" = "notraffic" ]; then
    : # skip usage fetch and version check entirely
  else

  if [ -n "$OAUTH_TOKEN" ]; then
    HTTP_CODE="000"
    USAGE_RAW=""
    HTTP_RAW=$(curl -s -w $'\n%{http_code}' --max-time 3 \
      -H "Authorization: Bearer ${OAUTH_TOKEN}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || HTTP_RAW=""
    if [ -n "$HTTP_RAW" ]; then
      HTTP_CODE="${HTTP_RAW##*$'\n'}"
      case "$HTTP_RAW" in
        *$'\n'*) USAGE_RAW="${HTTP_RAW%$'\n'*}" ;;
      esac
    fi

    if [ -n "$USAGE_RAW" ] && echo "$USAGE_RAW" | jq -e '.five_hour' >/dev/null 2>&1; then
      IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                      EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C <<< \
        "$(echo "$USAGE_RAW" | jq -r '
          def pct: floor;
          def epoch: gsub("\\.[0-9]+"; "") | gsub("Z$"; "+00:00") | split("+")[0] + "Z" | fromdate;
          [
            ((.five_hour.utilization // 0) | pct),
            ((.five_hour.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day.utilization // 0) | pct),
            ((.seven_day.resets_at // "") | if . == "" or . == null then 0 else epoch end),
            ((.seven_day_sonnet.utilization // -1) | pct),
            (if .extra_usage.is_enabled == true then 1 else 0 end),
            ((.extra_usage.utilization // -1) | pct),
            ((.extra_usage.used_credits // 0) | floor),
            ((.extra_usage.monthly_limit // 0) | floor)
          ] | join("|")
        ' 2>/dev/null)"
      FETCH_OK="ok"
    else
      if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        FETCH_OK="auth"
      elif [ "$HTTP_CODE" = "429" ]; then
        FETCH_OK="ratelimited"
      else
        FETCH_OK="fail"
      fi
    fi
  fi

  UPDATE_AVAIL=""
  _SKIP_UPDATE_CHECK=false
  case "${VBW_SKIP_UPDATE_CHECK:-0}" in
    1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|[Oo][Nn]) _SKIP_UPDATE_CHECK=true ;;
  esac
  if [ "$_SKIP_UPDATE_CHECK" = false ]; then
    REMOTE_VER=$(curl -sf --max-time 3 "https://raw.githubusercontent.com/michaelheichler/vibe-better-with-claude-code-vbw/main/VERSION" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$REMOTE_VER" ] && [ -n "$_VER" ] && [ "$REMOTE_VER" != "$_VER" ]; then
      NEWEST=$(printf '%s\n%s\n' "$_VER" "$REMOTE_VER" | (sort -V 2>/dev/null || sort -t. -k1,1n -k2,2n -k3,3n) | tail -1)
      [ "$NEWEST" = "$REMOTE_VER" ] && UPDATE_AVAIL="$REMOTE_VER"
    fi
  fi

  fi # end: notraffic guard

  atomic_write_string "$SLOW_CF" "${FIVE_PCT:-0}|${FIVE_EPOCH:-0}|${WEEK_PCT:-0}|${WEEK_EPOCH:-0}|${SONNET_PCT:--1}|${EXTRA_ENABLED:-0}|${EXTRA_PCT:--1}|${EXTRA_USED_C:-0}|${EXTRA_LIMIT_C:-0}|${FETCH_OK}|${UPDATE_AVAIL:-}|${AUTH_METHOD:-}|${AUTH_CLASS:-api_key}|${HIDE_LIMITS:-false}|${HIDE_LIMITS_API:-false}" 2>/dev/null || true
fi

if [ -O "$SLOW_CF" ]; then
  IFS='|' read -r FIVE_PCT FIVE_EPOCH WEEK_PCT WEEK_EPOCH SONNET_PCT \
                  EXTRA_ENABLED EXTRA_PCT EXTRA_USED_C EXTRA_LIMIT_C \
                  FETCH_OK UPDATE_AVAIL AUTH_METHOD AUTH_CLASS HIDE_LIMITS HIDE_LIMITS_API < "$SLOW_CF"
  if [ "$AUTH_CLASS" = "true" ] || [ "$AUTH_CLASS" = "false" ]; then
    HIDE_LIMITS_API="$HIDE_LIMITS"
    HIDE_LIMITS="$AUTH_CLASS"
    AUTH_CLASS="api_key"
    [ "$AUTH_METHOD" = "claude.ai" ] && AUTH_CLASS="oauth"
  fi
  AUTH_CLASS="${AUTH_CLASS:-api_key}"
fi

COST_CF="${_CACHE}-cost"
LEDGER_FILE="$VBW_PLANNING_DIR/.cost-ledger.json"
PREV_COST=""
_COST_LOCK_DIR="${_CACHE}-cost.lock"
if acquire_lock_dir "$_COST_LOCK_DIR"; then
  [ -O "$COST_CF" ] && PREV_COST=$(cat "$COST_CF" 2>/dev/null)
  atomic_write_string "$COST_CF" "${COST}" 2>/dev/null || true

  if [ -n "$PREV_COST" ] && [ -d "$VBW_PLANNING_DIR" ]; then
  _to_cents() {
    local val="$1" w f
    w="${val%%.*}"
    if [ "$w" = "$val" ]; then f="00"; else f="${val#*.}"; f="${f}00"; f="${f:0:2}"; fi
    echo $(( 10#${w:-0} * 100 + 10#$f ))
  }
  PREV_CENTS=$(_to_cents "$PREV_COST")
  CURR_CENTS=$(_to_cents "$COST")
  DELTA_CENTS=$((CURR_CENTS - PREV_CENTS))

  if [ "$DELTA_CENTS" -gt 0 ]; then
    ACTIVE_AGENT="other"
    [ -f "$VBW_PLANNING_DIR/.active-agent" ] && ACTIVE_AGENT=$(cat "$VBW_PLANNING_DIR/.active-agent" 2>/dev/null)
    [ -z "$ACTIVE_AGENT" ] && ACTIVE_AGENT="other"

    if [ -f "$LEDGER_FILE" ] && jq empty "$LEDGER_FILE" 2>/dev/null; then
      _LEDGER_JSON=$(jq --arg agent "$ACTIVE_AGENT" --argjson delta "$DELTA_CENTS" \
        '.[$agent] = ((.[$agent] // 0) + $delta)' "$LEDGER_FILE" 2>/dev/null)
      [ -n "${_LEDGER_JSON:-}" ] && atomic_write_string "$LEDGER_FILE" "$_LEDGER_JSON" 2>/dev/null || true
    else
      atomic_write_string "$LEDGER_FILE" "{\"$ACTIVE_AGENT\":$DELTA_CENTS}" 2>/dev/null || true
    fi
  fi
fi
  release_lock_dir "$_COST_LOCK_DIR"
else
  atomic_write_string "$COST_CF" "${COST}" 2>/dev/null || true
fi
unset _COST_LOCK_DIR _LEDGER_JSON

USAGE_LINE=""
if [ "$FETCH_OK" = "ok" ]; then
  countdown() {
    local epoch="$1"
    if [ "${epoch:-0}" -gt 0 ] 2>/dev/null; then
      local diff=$((epoch - NOW))
      if [ "$diff" -gt 0 ]; then
        if [ "$diff" -ge 86400 ]; then
          local dd=$((diff / 86400)) hh=$(( (diff % 86400) / 3600 ))
          echo "~${dd}d ${hh}h"
        else
          local hh=$((diff / 3600)) mm=$(( (diff % 3600) / 60 ))
          echo "~${hh}h${mm}m"
        fi
      else
        echo "now"
      fi
    fi
  }

  FIVE_REM=$(countdown "$FIVE_EPOCH")
  WEEK_REM=$(countdown "$WEEK_EPOCH")

  USAGE_LINE="Session: $(progress_bar "${FIVE_PCT:-0}" 10) ${FIVE_PCT:-0}%"
  [ -n "$FIVE_REM" ] && USAGE_LINE="$USAGE_LINE $FIVE_REM"
  USAGE_LINE="$USAGE_LINE ${D}│${X} Weekly: $(progress_bar "${WEEK_PCT:-0}" 10) ${WEEK_PCT:-0}%"
  [ -n "$WEEK_REM" ] && USAGE_LINE="$USAGE_LINE $WEEK_REM"
  if [ "${SONNET_PCT:--1}" -ge 0 ] 2>/dev/null; then
    USAGE_LINE="$USAGE_LINE ${D}│${X} Sonnet: $(progress_bar "${SONNET_PCT}" 10) ${SONNET_PCT}%"
  fi
  if [ "${EXTRA_ENABLED:-0}" = "1" ] && [ "${EXTRA_PCT:--1}" -ge 0 ] 2>/dev/null; then
    EXTRA_USED_D="$((EXTRA_USED_C / 100)).$( printf '%02d' $((EXTRA_USED_C % 100)) )"
    EXTRA_LIMIT_D="$((EXTRA_LIMIT_C / 100)).$( printf '%02d' $((EXTRA_LIMIT_C % 100)) )"
    USAGE_LINE="$USAGE_LINE ${D}│${X} Extra: $(progress_bar "${EXTRA_PCT}" 10) ${EXTRA_PCT}% \$${EXTRA_USED_D}/\$${EXTRA_LIMIT_D}"
  fi
elif [ "$FETCH_OK" = "auth" ]; then
  USAGE_LINE="${D}Limits: auth expired (run /login)${X}"
elif [ "$FETCH_OK" = "ratelimited" ]; then
  USAGE_LINE="${D}Limits: rate limited (retry in 5m, re-login if persistent)${X}"
elif [ "$FETCH_OK" = "fail" ]; then
  USAGE_LINE="${D}Limits: fetch failed (retry in 5m)${X}"
elif [ "$FETCH_OK" = "notraffic" ]; then
  USAGE_LINE="${D}Limits: skipped (nonessential traffic disabled)${X}"
elif [ "$AUTH_METHOD" = "claude.ai" ]; then
  USAGE_LINE="${D}Limits: keychain access denied (allow Terminal in Keychain Access.app or set VBW_OAUTH_TOKEN)${X}"
elif [ "$FETCH_OK" = "noauth" ]; then
  USAGE_LINE="${D}Limits: N/A (using API key)${X}"
else
  USAGE_LINE="${D}Limits: unavailable${X}"
fi

if [ "$HIDE_LIMITS" = "true" ]; then
  USAGE_LINE=""
elif [ "$HIDE_LIMITS_API" = "true" ] && [ "${AUTH_CLASS:-api_key}" = "api_key" ]; then
  USAGE_LINE=""
fi

GH_LINK=""
REPO_LABEL=""
if [ -n "$GH_URL" ]; then
  GH_NAME=$(basename "$GH_URL")
  REPO_LABEL="$GH_NAME"
  if [ -n "$BR" ]; then
    GH_BRANCH_URL="${GH_URL}/tree/${BR}"
    GH_LINK="\033]8;;${GH_BRANCH_URL}\a${GH_NAME}:${BR}\033]8;;\a"
  else
    GH_LINK="\033]8;;${GH_URL}\a${GH_NAME}\033]8;;\a"
  fi
else
  REPO_LABEL=$(basename "$_REPO_ROOT")
fi

[ "$PCT" -ge 90 ] && BC="$R" || { [ "$PCT" -ge 70 ] && BC="$Y" || BC="$G"; }
FL=$((PCT * 10 / 100)); EM=$((10 - FL))
CTX_BAR=""; [ "$FL" -gt 0 ] && CTX_BAR=$(printf "%${FL}s" | sed 's/ /▓/g')
[ "$EM" -gt 0 ] && CTX_BAR="${CTX_BAR}$(printf "%${EM}s" | sed 's/ /░/g')"

_HIDE_EXEC_TMUX=false
if [ "$HIDE_AGENT_TMUX" = "true" ] && [ -n "${TMUX:-}" ] && [ "$EXEC_STATUS" = "running" ]; then
  _HIDE_EXEC_TMUX=true
fi

if [ "$_HIDE_EXEC_TMUX" != "true" ] && [ "$EXEC_STATUS" = "running" ] && [ "${EXEC_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
  EXEC_PCT=$((EXEC_DONE * 100 / EXEC_TOTAL))
  L1="${VC}[VBW]${X} Build: $(progress_bar "$EXEC_PCT" 8) ${EXEC_DONE}/${EXEC_TOTAL} plans"
  [ "${EXEC_TWAVES:-0}" -gt 1 ] 2>/dev/null && L1="$L1 ${D}│${X} Wave ${EXEC_WAVE}/${EXEC_TWAVES}"
  [ -n "$EXEC_CURRENT" ] && L1="$L1 ${D}│${X} ${C}◆${X} ${EXEC_CURRENT}"
elif [ "$EXEC_STATUS" = "complete" ]; then
  rm -f "$VBW_PLANNING_DIR/.execution-state.json" "$FAST_CF" 2>/dev/null
  EXEC_STATUS=""
  L1="${VC}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  if [ "$PT" -gt 0 ] 2>/dev/null; then
    L1="$L1 ${D}│${X} Plans: ${PD}/${PT}"
    if [ "${TT:-0}" -gt 1 ] 2>/dev/null && [ "${PPT:-0}" -gt 0 ] 2>/dev/null; then
      if [ "$PD" -lt "$PT" ] 2>/dev/null || [ "$REM_ACTIVE" = "true" ]; then
        L1="$L1 (${PPD}/${PPT} ${PP_LABEL})"
      fi
    fi
  fi
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  _qc="$D"; case "${QA_COLOR:-D}" in G) _qc="$G";; Y) _qc="$Y";; R) _qc="$R";; esac
  L1="$L1 ${D}│${X} ${_qc}${QA}${X}"
elif [ -d "$VBW_PLANNING_DIR" ]; then
  L1="${VC}[VBW]${X}"
  [ "$TT" -gt 0 ] 2>/dev/null && L1="$L1 Phase ${PH}/${TT}" || L1="$L1 Phase ${PH:-?}"
  if [ "$PT" -gt 0 ] 2>/dev/null; then
    L1="$L1 ${D}│${X} Plans: ${PD}/${PT}"
    if [ "${TT:-0}" -gt 1 ] 2>/dev/null && [ "${PPT:-0}" -gt 0 ] 2>/dev/null; then
      if [ "$PD" -lt "$PT" ] 2>/dev/null || [ "$REM_ACTIVE" = "true" ]; then
        L1="$L1 (${PPD}/${PPT} ${PP_LABEL})"
      fi
    fi
  fi
  L1="$L1 ${D}│${X} Effort: $EF ${D}│${X} Model: $MP"
  _qc="$D"; case "${QA_COLOR:-D}" in G) _qc="$G";; Y) _qc="$Y";; R) _qc="$R";; esac
  L1="$L1 ${D}│${X} ${_qc}${QA}${X}"
else
  L1="${VC}[VBW]${X} ${D}no project${X}"
fi
if [ -n "$BR" ] || [ -n "$GH_LINK" ] || [ -n "$REPO_LABEL" ]; then
  if [ -n "$GH_LINK" ]; then
    L1="$L1 ${D}│${X} ${GH_LINK}"
  elif [ -n "$REPO_LABEL" ] && [ -n "$BR" ]; then
    L1="$L1 ${D}│${X} ${REPO_LABEL}:${BR}"
  elif [ -n "$REPO_LABEL" ]; then
    L1="$L1 ${D}│${X} ${REPO_LABEL}"
  elif [ -n "$BR" ]; then
    L1="$L1 ${D}│${X} $BR"
  fi
  GIT_IND=""
  [ "${GIT_STAGED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${G}+${GIT_STAGED}${X}"
  [ "${GIT_MODIFIED:-0}" -gt 0 ] 2>/dev/null && GIT_IND="${GIT_IND}${Y}~${GIT_MODIFIED}${X}"
  [ -n "$GIT_IND" ] && L1="$L1 ${D}Files:${X} $GIT_IND"
  [ "${GIT_AHEAD:-0}" -gt 0 ] 2>/dev/null && L1="$L1 ${D}Commits:${X} ${C}↑${GIT_AHEAD}${X}"
  L1="$L1 ${D}Diff:${X} ${G}+${ADDED}${X} ${R}-${REMOVED}${X}"
fi

L2="Context: ${BC}${CTX_BAR}${X} ${BC}${PCT}%${X} ${CTX_USED_FMT}/${CTX_SIZE_FMT}"
L2="$L2 ${D}│${X} Tokens: ${IN_TOK_FMT} in  ${OUT_TOK_FMT} out"
L2="$L2 ${D}│${X} Prompt Cache: ${CACHE_COLOR}${CACHE_HIT_PCT}% hit${X} ${CACHE_W_FMT} write ${CACHE_R_FMT} read"

L3="$USAGE_LINE"
L4="Model: ${D}${MODEL}${X} ${D}│${X} Time: ${DUR_FMT} (API: ${API_DUR_FMT})"
[ -n "$AGENT_LINE" ] && L4="$L4 ${D}│${X} ${AGENT_LINE}"
if [ -n "$UPDATE_AVAIL" ]; then
  L4="$L4 ${D}│${X} ${Y}${B}VBW ${_VER:-?} → ${UPDATE_AVAIL}${X} ${Y}/vbw:update${X} ${D}│${X} ${D}CC ${VER}${X}"
else
  L4="$L4 ${D}│${X} ${D}VBW ${_VER:-?}${X} ${D}│${X} ${D}CC ${VER}${X}"
fi

printf '%b\n' "$L1"
printf '%b\n' "$L2"
[ -n "$L3" ] && printf '%b\n' "$L3"
printf '%b\n' "$L4"

exit 0
