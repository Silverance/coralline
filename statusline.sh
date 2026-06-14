#!/usr/bin/env bash
# coralline — a configurable, Powerlevel10k-inspired statusline for Claude Code
# https://github.com/Nanako0129/coralline
# Visual style is a tribute to https://github.com/romkatv/powerlevel10k
#
# Design goals:
#   * One jq call, one git call — cheap enough for refreshInterval: 1
#   * Pure bash arithmetic (no bc), works on macOS bash 3.2 and Linux
#   * Everything themeable via ~/.claude/coralline.conf (sourced bash)
#
# Requires: jq, and a Nerd Font terminal unless VL_ASCII=1
#
# Flags:
#   --doctor / --check   validate the config and render a sample bar, without
#                        needing Claude Code to pipe a session on stdin

case "$1" in --doctor|--check) VL_DOCTOR=1 ;; esac

if [ "${VL_DOCTOR:-0}" = "1" ]; then
  # Synthetic session so --doctor renders a preview outside Claude Code.
  input='{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Claude Fable 5"},"version":"2.1.160","session_id":"abcd1234-5678-90ef","effort":{"level":"high"},"vim":{"mode":"NORMAL"},"worktree":{"name":"demo-wt","branch":"feat/demo"},"output_style":{"name":"Explanatory"},"context_window":{"used_percentage":62,"total_input_tokens":1234567,"total_output_tokens":45678,"current_usage":{"cache_read_input_tokens":98765,"cache_creation_input_tokens":4321}},"rate_limits":{"five_hour":{"used_percentage":41},"seven_day":{"used_percentage":79},"seven_day_sonnet":{"used_percentage":55},"seven_day_opus":{"used_percentage":88}},"cost":{"total_cost_usd":1.23,"total_lines_added":321,"total_lines_removed":87,"total_duration_ms":5432100}}'
else
  input=$(cat)
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'coralline: jq not found — install it from https://jqlang.github.io/jq/\n'
  exit 0
fi

# ── Defaults (every value can be overridden by the config file) ──────────────
VL_STYLE="pill"                 # pill: powerline pills · lean: p10k-lean flat text
VL_LEAN_SEP=""                  # lean only — extra text between segments, e.g. "·"
VL_LAYOUT="fixed"               # fixed: one line per VL_SEGMENTS* var
                                # auto:  single line, wraps when the window is narrow
VL_MAX_LINES=3                  # auto only — wrap into at most this many lines
VL_WRAP_MARGIN=4                # auto only — keep this many columns free on the right.
                                # 4 covers Claude Code's full-width L/R padding (2 cols each)
VL_SEGMENTS="dir git model ctx limit5h limit7d cost clock"
VL_SEGMENTS2=""                 # fixed only — optional second line
VL_SEGMENTS3=""                 # fixed only — optional third line
VL_BAR_WIDTH=5
VL_CTX_TOKENS="full"            # ctx token detail: full (↑↓ + cache) | io (↑↓ only) | off
VL_BAR_FILL="▰"
VL_BAR_EMPTY="▱"
VL_CLOCK="12h"                  # 12h | 24h | off
VL_CLOCK_SECONDS=1
VL_PATH_DEPTH=4                 # collapse paths deeper than this
VL_NAME_MAX=0                   # max chars for project/git names before … truncation (0 = off)
VL_COST_DECIMALS=2
VL_WARN_PCT=50                  # percentage thresholds for bar colors
VL_HOT_PCT=75
VL_GIT_CACHE=0                  # >0 = reuse `git status` for this many seconds, so
                                # huge repos don't re-scan every render; 0 = always live
VL_LIMIT_RESET="countdown"      # limit gauges: countdown | clock (absolute) | both
VL_GIT_LINK=0                   # 1 = OSC 8 hyperlink the git branch to its GitHub page
                                # (opt-in; needs a terminal that passes OSC 8 through)
VL_CUSTOM_CMD=""                # shell command for the `custom` segment (first line of stdout)
VL_CUSTOM_TIMEOUT=1             # seconds before the custom command is killed (if `timeout` exists)
VL_ASCII=0                      # 1 = no Nerd Font glyphs (plain colored blocks)

# Powerline glyphs (overridable; cleared when VL_ASCII=1)
VL_CAP_L=$(printf '\xee\x82\xb6')   # U+E0B6 left rounded cap
VL_CAP_R=$(printf '\xee\x82\xb4')   # U+E0B4 right rounded cap
VL_SEP=$(printf '\xee\x82\xb0')     # U+E0B0 segment separator

# Default theme: claude-coral (steel blue · mauve · Claude coral)
VL_BG_DIR="81,166,199"
VL_BG_GIT_OK=65
VL_BG_GIT_DIRTY=130
VL_BG_MODEL=173
VL_BG_CTX=238
VL_BG_5H=237
VL_BG_7D=236
VL_BG_COST="212,125,145"
VL_BG_CLOCK="70,80,110"
VL_BG_LINES=240
VL_BG_STYLE=96
VL_BG_DURATION=60
# New segments fall back to these if a theme doesn't set them (themes only need
# to override what they want to recolor).
VL_BG_EFFORT="${VL_BG_EFFORT:-97}"
VL_BG_VIM="${VL_BG_VIM:-240}"
VL_BG_CACHE="${VL_BG_CACHE:-238}"
VL_BG_WORKTREE="${VL_BG_WORKTREE:-66}"
VL_BG_VERSION="${VL_BG_VERSION:-238}"
VL_BG_SESSION="${VL_BG_SESSION:-238}"
VL_BG_SHA="${VL_BG_SHA:-240}"
VL_BG_CONFLICT="${VL_BG_CONFLICT:-160}"
VL_BG_CUSTOM="${VL_BG_CUSTOM:-240}"

VL_FG_TEXT=231
VL_FG_DIM=245
VL_FG_OK=114
VL_FG_WARN=179
VL_FG_HOT=167

# ── Load user config ─────────────────────────────────────────────────────────
VL_CONF="${CORALLINE_CONFIG:-$HOME/.claude/coralline.conf}"
[ -f "$VL_CONF" ] && . "$VL_CONF"

if [ "$VL_ASCII" = "1" ]; then
  VL_CAP_L="" ; VL_CAP_R="" ; VL_SEP=""
  VL_BAR_FILL="#" ; VL_BAR_EMPTY="-"
fi

# Lean style: no backgrounds or caps; each segment's VL_BG_* becomes its text
# accent color (an empty VL_FG_TEXT lets text inherit that accent).
if [ "$VL_STYLE" = "lean" ]; then
  VL_CAP_L="" ; VL_CAP_R=""
  VL_FG_TEXT="${VL_LEAN_FG:-}"
fi

# ── Parse JSON (single jq call) ──────────────────────────────────────────────
# Fields are joined with \x1f (unit separator): unlike tab, a non-whitespace
# IFS preserves empty fields instead of collapsing consecutive delimiters.
IFS=$'\037' read -r cwd model ctx_pct tok_in tok_out tok_cr tok_cw \
                 fh_pct fh_rst wd_pct wd_rst cost \
                 lines_add lines_del out_style dur_ms \
                 effort_lvl vim_mode cc_ver session_id wt_name wt_branch \
                 s7_pct s7_rst o7_pct o7_rst <<JSON
$(printf '%s' "$input" | jq -r '[
  (.workspace.current_dir // .cwd // ""),
  (.model.display_name // ""),
  (.context_window.used_percentage // "" | tostring),
  (.context_window.total_input_tokens // 0),
  (.context_window.total_output_tokens // 0),
  (.context_window.current_usage.cache_read_input_tokens // 0),
  (.context_window.current_usage.cache_creation_input_tokens // 0),
  (.rate_limits.five_hour.used_percentage // "" | tostring),
  (.rate_limits.five_hour.resets_at // "" | tostring),
  (.rate_limits.seven_day.used_percentage // "" | tostring),
  (.rate_limits.seven_day.resets_at // "" | tostring),
  (.cost.total_cost_usd // "" | tostring),
  (.cost.total_lines_added // 0),
  (.cost.total_lines_removed // 0),
  (.output_style.name // ""),
  (.cost.total_duration_ms // 0),
  (.effort.level // ""),
  (.vim.mode // ""),
  (.version // ""),
  (.session_id // ""),
  (.worktree.name // ""),
  (.worktree.branch // ""),
  (.rate_limits.seven_day_sonnet.used_percentage // "" | tostring),
  (.rate_limits.seven_day_sonnet.resets_at // "" | tostring),
  (.rate_limits.seven_day_opus.used_percentage // "" | tostring),
  (.rate_limits.seven_day_opus.resets_at // "" | tostring)
] | map(tostring) | join("\u001f")' 2>/dev/null)
JSON

# ── ANSI primitives ──────────────────────────────────────────────────────────
R=$'\033[0m'
BOLD=$'\033[1m'
NORM=$'\033[22m'

# bg/fg accept 256-color (single number) or true-color ("R,G,B");
# an empty argument emits nothing (the text inherits the current color)
bg() {
  [ -n "$1" ] || return 0
  if [ "${1#*,}" != "$1" ]; then
    local IFS=','; set -- $1; printf '\033[48;2;%s;%s;%sm' "$1" "$2" "$3"
  else printf '\033[48;5;%sm' "$1"; fi
}
fg() {
  [ -n "$1" ] || return 0
  if [ "${1#*,}" != "$1" ]; then
    local IFS=','; set -- $1; printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"
  else printf '\033[38;5;%sm' "$1"; fi
}

# ── Helpers ──────────────────────────────────────────────────────────────────
make_bar() {
  local pct="${1:-0}" width="${2:-$VL_BAR_WIDTH}" bar="" i filled
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  for ((i=0; i<filled; i++));        do bar="${bar}${VL_BAR_FILL}";  done
  for ((i=filled; i<width; i++));    do bar="${bar}${VL_BAR_EMPTY}"; done
  printf '%s' "$bar"
}

# 1234 → 1.2k · 1234567 → 1.2M (integer math only)
fmt_tok() {
  local n="${1:-0}"
  case "$n" in (''|*[!0-9]*) printf '%s' "$n"; return ;; esac
  if   [ "$n" -ge 1000000 ]; then printf '%d.%dM' $((n/1000000)) $(((n%1000000)/100000))
  elif [ "$n" -ge 1000 ];    then printf '%d.%dk' $((n/1000))    $(((n%1000)/100))
  else printf '%s' "$n"; fi
}

# Accepts epoch seconds (with or without decimals) or an ISO 8601 timestamp.
to_epoch() {
  local t="$1" s
  [ -z "$t" ] && return 1
  case "$t" in
    *T*)  # ISO 8601 — try GNU date, then BSD date (assume UTC if tz lost)
      date -u -d "$t" +%s 2>/dev/null && return 0
      s="${t%%[.+]*}" ; s="${s%Z}"
      date -ju -f '%Y-%m-%dT%H:%M:%S' "$s" +%s 2>/dev/null && return 0
      return 1 ;;
    *[0-9]*) printf '%s' "${t%%.*}" ;;
    *) return 1 ;;
  esac
}

fmt_countdown() {
  local rst epoch now diff d h m
  rst=$(to_epoch "$1") || return 0
  now=$(date +%s)
  diff=$(( rst - now ))
  if [ "$diff" -le 0 ]; then printf 'now'; return; fi
  d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 )); m=$(( (diff % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%02dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  else                      printf '%dm' "$m"; fi
}

fmt_duration() {
  local ms="${1:-0}" s h m
  s=$(( ms / 1000 )); h=$(( s / 3600 )); m=$(( (s % 3600) / 60 ))
  if   [ "$h" -gt 0 ]; then printf '%dh%02dm' "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf '%dm' "$m"
  else                      printf '%ds' "$s"; fi
}

# Absolute wall-clock time a limit resets at, in the VL_CLOCK format.
fmt_resetclock() {
  local epoch fmt; epoch=$(to_epoch "$1") || return 0
  if [ "$VL_CLOCK" = "12h" ]; then fmt='%I:%M%p'; else fmt='%H:%M'; fi
  date -r "$epoch" "+$fmt" 2>/dev/null || date -d "@$epoch" "+$fmt" 2>/dev/null
}

pct_fg() {
  local pct="${1:-0}"
  if   [ "$pct" -ge "$VL_HOT_PCT" ];  then printf '%s' "$VL_FG_HOT"
  elif [ "$pct" -ge "$VL_WARN_PCT" ]; then printf '%s' "$VL_FG_WARN"
  else                                     printf '%s' "$VL_FG_OK"; fi
}

# ── Git state (single subprocess, parsed once, used by git/stash segments) ──
GIT_BRANCH="" GIT_MARKS="" GIT_AB="" GIT_DIRTY=0 GIT_ROOT=""
GIT_SHA="" GIT_CONFLICTS=0 GIT_LINK="" GIT_WT=""

# Raw `git status` output, optionally reused for VL_GIT_CACHE seconds so a huge
# repo doesn't get re-scanned on every render. The cache file (keyed by cwd)
# holds the write epoch on line 1 and the porcelain output below it.
git_status_raw() {
  local cache now content
  if [ "${VL_GIT_CACHE:-0}" -gt 0 ] 2>/dev/null; then
    cache="${TMPDIR:-/tmp}/coralline-git-${cwd//\//%}"
    now=$(date +%s)
    if [ -f "$cache" ]; then
      content=$(<"$cache")
      if [ "$(( now - ${content%%$'\n'*} ))" -lt "$VL_GIT_CACHE" ] 2>/dev/null; then
        printf '%s' "${content#*$'\n'}"
        return
      fi
    fi
    content=$(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
    printf '%s\n%s' "$now" "$content" > "$cache.$$" 2>/dev/null &&
      mv "$cache.$$" "$cache" 2>/dev/null
    printf '%s' "$content"
  else
    git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null
  fi
}

read_git() {
  local line oid="" head="" a="" b="" staged=0 unstaged=0 untracked=0 conflicts=0
  [ -n "$cwd" ] || return
  while IFS= read -r line; do
    case "$line" in
      "# branch.oid "*)      oid="${line#\# branch.oid }" ;;
      "# branch.head "*)     head="${line#\# branch.head }" ;;
      "# branch.ab "*)       set -- ${line#\# branch.ab }; a="${1#+}"; b="${2#-}" ;;
      "? "*)                 untracked=1 ;;
      [12]" "*)              line="${line#? }"
                             case "${line:0:1}" in [!.]) staged=1 ;; esac
                             case "${line:1:1}" in [!.]) unstaged=1 ;; esac ;;
      "u "*)                 unstaged=1; conflicts=$(( conflicts + 1 )) ;;
    esac
  done <<GIT
$(git_status_raw)
GIT
  [ -z "$oid" ] && return                     # not a repo
  GIT_SHA="${oid:0:7}"                         # short commit hash (seg_sha)
  GIT_CONFLICTS=$conflicts                      # unmerged paths (seg_conflicts)
  if [ "$head" = "(detached)" ] || [ -z "$head" ]; then
    GIT_BRANCH="${oid:0:7}"
  else
    GIT_BRANCH="$head"
  fi
  # Optional OSC 8 hyperlink target for the branch — one extra git call, only
  # when the user opts in. Normalises git@host:owner/repo(.git) and https URLs
  # to https://host/owner/repo/tree/<branch>.
  if [ "$VL_GIT_LINK" = "1" ] && [ -n "$head" ] && [ "$head" != "(detached)" ]; then
    local url="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null)"
    case "$url" in
      git@*:*)     url="${url#git@}"; url="https://${url%%:*}/${url#*:}" ;;
      ssh://git@*) url="https://${url#ssh://git@}" ;;
    esac
    url="${url%.git}"
    case "$url" in https://*) GIT_LINK="${url}/tree/${head}" ;; esac
  fi
  # Resolve the MAIN repo root (seg_project) and linked-worktree status
  # (seg_worktree) in one rev-parse. The common git-dir is shared by every
  # linked worktree, so GIT_ROOT stays constant whichever worktree you're in;
  # when the per-worktree git-dir lives under .../worktrees/<name>, this is a
  # linked worktree and GIT_WT is its name. Only run when those segments are on.
  case " $VL_SEGMENTS $VL_SEGMENTS2 $VL_SEGMENTS3 " in *" project "*|*" worktree "*)
    local rp gdir cdir
    rp=$(git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null)
    gdir="${rp%%$'\n'*}" ; cdir="${rp#*$'\n'}"
    [ -n "$cdir" ] || cdir=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$cdir" ]; then
      cdir="${cdir%/}" ; cdir="${cdir%/.git}"
      GIT_ROOT="${cdir##*/}"
    fi
    case "$gdir" in *"/worktrees/"*) GIT_WT="${gdir##*/}" ;; esac ;;
  esac
  [ "$staged"    -eq 1 ] && GIT_MARKS="${GIT_MARKS}+"
  [ "$unstaged"  -eq 1 ] && GIT_MARKS="${GIT_MARKS}!"
  [ "$untracked" -eq 1 ] && GIT_MARKS="${GIT_MARKS}?"
  [ "${a:-0}" -gt 0 ] 2>/dev/null && GIT_AB="${GIT_AB}⇡${a}"
  [ "${b:-0}" -gt 0 ] 2>/dev/null && GIT_AB="${GIT_AB}⇣${b}"
  [ -n "$GIT_MARKS" ] && GIT_DIRTY=1
}
case " $VL_SEGMENTS $VL_SEGMENTS2 $VL_SEGMENTS3 " in
  *" git "*|*" stash "*|*" project "*|*" sha "*|*" conflicts "*) read_git ;;
esac

# ── Segments ─────────────────────────────────────────────────────────────────
# Each seg_* appends (background, text, visible width) to the segment arrays.
ESC=$'\033'
strip_ansi() {  # → STRIP_R = $1 with ANSI CSI (…m) and OSC 8 (…ST) sequences removed
  local s="$1" plain="" rest
  while [ "${s#*$ESC}" != "$s" ]; do
    plain+="${s%%$ESC*}"            # text before the ESC
    rest="${s#*$ESC}"              # everything after it
    case "$rest" in
      '['*)  rest="${rest#*m}" ;;                   # CSI colour/style → ends at 'm'
      ']'*)  case "$rest" in                        # OSC (hyperlinks) → ends at ST or BEL
               *"$ESC\\"*) rest="${rest#*"$ESC\\"}" ;;
               *) rest="${rest#*$'\a'}" ;;
             esac ;;
      *)     rest="${rest#?}" ;;                    # lone ESC: drop the next byte
    esac
    s="$rest"
  done
  STRIP_R="$plain$s"
}

# Display columns of a plain (ANSI-free) string. Pure-ASCII strings are just
# their length; otherwise the UTF-8 bytes are decoded to codepoints so that
# CJK/Kana/Hangul/fullwidth/emoji count as two cells and the responsive layout
# wraps correctly for non-Latin names. (bash's printf "'c" gives the first byte,
# not the codepoint, so we decode by hand under LC_ALL=C byte semantics.)
disp_width() {
  local s="$1" w=0
  if [ "${s//[!$'\001'-$'\177']/}" = "$s" ]; then printf '%s' "${#s}"; return; fi
  local LC_ALL=C LANG=                      # byte semantics for the decode below
  local n=${#s} i=0 b cp extra              # n must be BYTE count, so set after locale
  while [ "$i" -lt "$n" ]; do
    b=$(printf '%d' "'${s:i:1}"); [ "$b" -lt 0 ] && b=$(( b + 256 ))
    if   [ "$b" -lt 192 ]; then cp=$b;             extra=0   # ASCII / stray byte
    elif [ "$b" -lt 224 ]; then cp=$(( b - 192 )); extra=1   # 2-byte lead
    elif [ "$b" -lt 240 ]; then cp=$(( b - 224 )); extra=2   # 3-byte lead
    else                        cp=$(( b - 240 )); extra=3   # 4-byte lead
    fi
    i=$(( i + 1 ))
    while [ "$extra" -gt 0 ] && [ "$i" -lt "$n" ]; do
      b=$(printf '%d' "'${s:i:1}"); [ "$b" -lt 0 ] && b=$(( b + 256 ))
      cp=$(( cp * 64 + (b - 128) )); i=$(( i + 1 )); extra=$(( extra - 1 ))
    done
    if { [ "$cp" -ge 4352   ] && [ "$cp" -le 4447   ]; } ||   # Hangul Jamo
       { [ "$cp" -ge 8986   ] && [ "$cp" -le 8987   ]; } ||   # watch · hourglass
       { [ "$cp" -ge 11904  ] && [ "$cp" -le 19903  ]; } ||   # CJK radicals … ext-A
       { [ "$cp" -ge 19968  ] && [ "$cp" -le 40959  ]; } ||   # CJK Unified
       { [ "$cp" -ge 44032  ] && [ "$cp" -le 55203  ]; } ||   # Hangul syllables
       { [ "$cp" -ge 63744  ] && [ "$cp" -le 64255  ]; } ||   # CJK compatibility
       { [ "$cp" -ge 65040  ] && [ "$cp" -le 65135  ]; } ||   # CJK compat forms
       { [ "$cp" -ge 65280  ] && [ "$cp" -le 65519  ]; } ||   # fullwidth forms
       { [ "$cp" -ge 127744 ] && [ "$cp" -le 129791 ]; } ||   # emoji
       [ "$cp" -ge 131072 ]; then                             # CJK ext-B and beyond
      w=$(( w + 2 ))
    else
      w=$(( w + 1 ))
    fi
  done
  printf '%s' "$w"
}
push() {
  SEG_BGS[${#SEG_BGS[@]}]="$1"
  SEG_TXT[${#SEG_TXT[@]}]="$2"
}

trunc() {  # echo $1 clipped to $2 visible chars, middle-truncated with … ; $2=0/unset → unchanged
  local s="$1" max="${2:-0}" head tail start
  case "$max" in (''|*[!0-9]*) max=0 ;; esac
  if [ "$max" -le 0 ] || [ "${#s}" -le "$max" ]; then printf '%s' "$s"; return; fi
  if [ "$max" -lt 3 ]; then printf '%s' "${s:0:max}"; return; fi   # no room for head+…+tail
  # Keep head and tail so names sharing a long prefix stay distinguishable.
  head=$(( (max - 1) / 2 )); tail=$(( max - 1 - head )); start=$(( ${#s} - tail ))
  printf '%s…%s' "${s:0:head}" "${s:start}"
}

seg_project() {  # stable repo-root name (same in every worktree); hidden outside a repo
  [ -n "$GIT_ROOT" ] || return 0
  push "$VL_BG_DIR" "${BOLD}$(fg $VL_FG_TEXT) ⬢ $(trunc "$GIT_ROOT" "$VL_NAME_MAX") ${NORM}"
}

seg_dir() {
  [ -n "$cwd" ] || return 0
  local short="${cwd/#$HOME/~}" n last
  local IFS='/'; set -- $short; n=$#
  eval "last=\${$n}"
  last="$(trunc "$last" "$VL_NAME_MAX")"          # truncate the long leaf (e.g. repo dir)
  if [ "$n" -gt "$VL_PATH_DEPTH" ]; then
    short="$1/$2/…/$last"
  else
    case "$short" in */*) short="${short%/*}/$last" ;; *) short="$last" ;; esac
  fi
  push "$VL_BG_DIR" "${BOLD}$(fg $VL_FG_TEXT) ${short} ${NORM}"
}

seg_git() {
  [ -n "$GIT_BRANCH" ] || return 0
  local bgc="$VL_BG_GIT_OK" name
  [ "$GIT_DIRTY" -eq 1 ] && bgc="$VL_BG_GIT_DIRTY"
  name="$(trunc "$GIT_BRANCH" "$VL_NAME_MAX")"
  # OSC 8 hyperlink: ESC ] 8 ; ; URL ST  text  ESC ] 8 ; ; ST
  [ -n "$GIT_LINK" ] && name="${ESC}]8;;${GIT_LINK}${ESC}\\${name}${ESC}]8;;${ESC}\\"
  push "$bgc" "${BOLD}$(fg $VL_FG_TEXT) ⎇ ${name}${GIT_MARKS}${GIT_AB} ${NORM}"
}

seg_model() {
  [ -n "$model" ] || return 0
  push "$VL_BG_MODEL" "${BOLD}$(fg $VL_FG_TEXT) ◆ ${model#Claude } ${NORM}"
}

seg_ctx() {
  [ -n "$ctx_pct" ] || return 0
  local ci bar cn det=""
  ci=$(printf '%.0f' "$ctx_pct" 2>/dev/null) || ci=0
  bar=$(make_bar "$ci"); cn=$(pct_fg "$ci")
  case "$VL_CTX_TOKENS" in
    off) ;;
    io)  det="$(fg $VL_FG_DIM)↑$(fmt_tok $tok_in) ↓$(fmt_tok $tok_out) " ;;
    *)   det="$(fg $VL_FG_DIM)↑$(fmt_tok $tok_in) ↓$(fmt_tok $tok_out) cr:$(fmt_tok $tok_cr) cw:$(fmt_tok $tok_cw) " ;;
  esac
  push "$VL_BG_CTX" "$(fg $cn) ⬡ ${bar} ${ci}% ${det}"
}

seg_limit() {  # $1=label $2=pct $3=resets_at $4=bg
  [ -n "$2" ] || return 0
  local v bar cn cd clk rst=""
  v=$(printf '%.0f' "$2" 2>/dev/null) || v=0
  bar=$(make_bar "$v"); cn=$(pct_fg "$v")
  case "$VL_LIMIT_RESET" in
    clock) clk=$(fmt_resetclock "$3"); [ -n "$clk" ] && rst="$(fg $VL_FG_DIM)↺${clk}" ;;
    both)  cd=$(fmt_countdown "$3"); clk=$(fmt_resetclock "$3")
           [ -n "$cd" ] && rst="$(fg $VL_FG_DIM)↺${cd}${clk:+ ${clk}}" ;;
    *)     cd=$(fmt_countdown "$3"); [ -n "$cd" ] && rst="$(fg $VL_FG_DIM)↺${cd}" ;;
  esac
  push "$4" "$(fg $cn) $1 ${bar} ${v}% ${rst} "
}
seg_limit5h() { seg_limit "5h" "$fh_pct" "$fh_rst" "$VL_BG_5H"; }
seg_limit7d() { seg_limit "7d" "$wd_pct" "$wd_rst" "$VL_BG_7D"; }
seg_limit7ds() { seg_limit "7dS" "$s7_pct" "$s7_rst" "$VL_BG_7D"; }  # per-model: Sonnet
seg_limit7do() { seg_limit "7dO" "$o7_pct" "$o7_rst" "$VL_BG_7D"; }  # per-model: Opus

seg_cost() {
  [ -n "$cost" ] && [ "$cost" != "0" ] || return 0
  local fmt
  fmt=$(printf "\$%.${VL_COST_DECIMALS}f" "$cost" 2>/dev/null) || fmt="\$$cost"
  push "$VL_BG_COST" "$(fg $VL_FG_TEXT) ${fmt} "
}

seg_clock() {
  [ "$VL_CLOCK" = "off" ] && return 0
  local t ap=""
  if [ "$VL_CLOCK" = "24h" ]; then
    t=$(date '+%H:%M'); [ "$VL_CLOCK_SECONDS" = "1" ] && t=$(date '+%H:%M:%S')
  else
    t=$(date '+%I:%M'); [ "$VL_CLOCK_SECONDS" = "1" ] && t=$(date '+%I:%M:%S')
    ap=" $(LC_ALL=C date '+%p' | tr '[:upper:]' '[:lower:]')"
  fi
  push "$VL_BG_CLOCK" "$(fg $VL_FG_TEXT) ⊙ ${t}${ap} "
}

seg_lines() {
  [ "${lines_add:-0}" -gt 0 ] 2>/dev/null || [ "${lines_del:-0}" -gt 0 ] 2>/dev/null || return 0
  push "$VL_BG_LINES" " $(fg $VL_FG_OK)+${lines_add} $(fg $VL_FG_HOT)-${lines_del} "
}

seg_style() {
  [ -n "$out_style" ] && [ "$out_style" != "default" ] || return 0
  push "$VL_BG_STYLE" "$(fg $VL_FG_TEXT) ✎ ${out_style} "
}

seg_duration() {
  [ "${dur_ms:-0}" -gt 0 ] 2>/dev/null || return 0
  push "$VL_BG_DURATION" "$(fg $VL_FG_TEXT) ⧖ $(fmt_duration $dur_ms) "
}

seg_stash() {
  [ -n "$GIT_BRANCH" ] || return 0
  local n
  n=$(git -C "$cwd" rev-list --walk-reflogs --count refs/stash 2>/dev/null) || return 0
  [ "${n:-0}" -gt 0 ] || return 0
  push "$VL_BG_GIT_OK" "$(fg $VL_FG_TEXT) ⚑ ${n} "
}

# ── Segments ported from ccstatusline (all free of extra subprocesses) ─────────
seg_effort() {  # thinking effort level (.effort.level)
  [ -n "$effort_lvl" ] && [ "$effort_lvl" != "null" ] || return 0
  push "$VL_BG_EFFORT" "$(fg $VL_FG_TEXT) ✲ ${effort_lvl} "
}

seg_vim() {  # vim mode (.vim.mode) — hidden unless vim mode is on
  [ -n "$vim_mode" ] && [ "$vim_mode" != "null" ] || return 0
  push "$VL_BG_VIM" "$(fg $VL_FG_TEXT) ⌨ ${vim_mode} "
}

seg_cache() {  # cache hit rate from token counts already on stdin
  local cr="${tok_cr:-0}" cw="${tok_cw:-0}" total hit cn
  case "$cr$cw" in *[!0-9]*) return 0 ;; esac
  total=$(( cr + cw )); [ "$total" -gt 0 ] || return 0
  hit=$(( (cr * 100 + total / 2) / total ))
  cn=$(pct_fg $(( 100 - hit )))                 # high hit rate is good → green
  push "$VL_BG_CACHE" "$(fg $cn) ↯ ${hit}% "
}

seg_worktree() {  # linked-worktree badge: prefers Claude Code's .worktree.*,
                  # falls back to git (shows the parent repo it branches from)
  local name=""
  if [ -n "$wt_name" ] && [ "$wt_name" != "null" ]; then
    name="$wt_name"
    [ -n "$wt_branch" ] && [ "$wt_branch" != "null" ] && name="${name} ⎇ ${wt_branch}"
  elif [ -n "$GIT_WT" ]; then
    name="$GIT_ROOT"                            # parent project of this linked worktree
  fi
  [ -n "$name" ] || return 0
  push "$VL_BG_WORKTREE" "$(fg $VL_FG_TEXT) ⧉ $(trunc "$name" "$VL_NAME_MAX") "
}

seg_version() {  # Claude Code CLI version (.version)
  [ -n "$cc_ver" ] && [ "$cc_ver" != "null" ] || return 0
  push "$VL_BG_VERSION" "$(fg $VL_FG_DIM) v${cc_ver} "
}

seg_session() {  # short session id (.session_id)
  [ -n "$session_id" ] && [ "$session_id" != "null" ] || return 0
  push "$VL_BG_SESSION" "$(fg $VL_FG_DIM) #${session_id:0:8} "
}

seg_sha() {  # short commit hash (from branch.oid; no extra git call)
  [ -n "$GIT_SHA" ] || return 0
  push "$VL_BG_SHA" "$(fg $VL_FG_DIM) @${GIT_SHA} "
}

seg_conflicts() {  # unmerged-path count (from git status; no extra git call)
  [ "${GIT_CONFLICTS:-0}" -gt 0 ] 2>/dev/null || return 0
  push "$VL_BG_CONFLICT" "$(fg $VL_FG_TEXT) ⚠ ${GIT_CONFLICTS} "
}

seg_custom() {  # first line of $VL_CUSTOM_CMD's stdout
  [ -n "$VL_CUSTOM_CMD" ] || return 0
  local out
  if   command -v timeout  >/dev/null 2>&1; then out=$(timeout  "$VL_CUSTOM_TIMEOUT" sh -c "$VL_CUSTOM_CMD" 2>/dev/null)
  elif command -v gtimeout >/dev/null 2>&1; then out=$(gtimeout "$VL_CUSTOM_TIMEOUT" sh -c "$VL_CUSTOM_CMD" 2>/dev/null)
  else                                           out=$(sh -c "$VL_CUSTOM_CMD" 2>/dev/null); fi
  out="${out%%$'\n'*}"                          # first line only
  [ -n "$out" ] || return 0
  push "$VL_BG_CUSTOM" "$(fg $VL_FG_TEXT) ${out} "
}

# ── Render ───────────────────────────────────────────────────────────────────
build_segments() {
  local s
  SEG_BGS=() ; SEG_TXT=() ; SEG_LEN=()
  for s in $1; do
    command -v "seg_$s" >/dev/null 2>&1 && "seg_$s"
  done
}

print_range() {  # render segments $1..$2 (inclusive) as one row
  local i out next
  if [ "$VL_STYLE" = "lean" ]; then
    out=""
    for ((i=$1; i<=$2; i++)); do
      out+="${R}$(fg ${SEG_BGS[$i]})${SEG_TXT[$i]}"
      [ "$i" -lt "$2" ] && out+="${R}${VL_LEAN_SEP}"
    done
    printf '%s\n' "${out}${R}"
    return 0
  fi
  out="${R}$(fg ${SEG_BGS[$1]})${VL_CAP_L}"
  for ((i=$1; i<=$2; i++)); do
    out+="$(bg ${SEG_BGS[$i]})${SEG_TXT[$i]}"
    if [ "$i" -lt "$2" ]; then
      next="${SEG_BGS[$((i+1))]}"
      out+="$(bg $next)$(fg ${SEG_BGS[$i]})${VL_SEP}"
    fi
  done
  out+="${R}$(fg ${SEG_BGS[$2]})${VL_CAP_R}${R}"
  printf '%s\n' "$out"
}

# Terminal width for auto layout; 0 = unknown (then stay on one line).
term_cols() {
  local c=""
  if [ -n "$COLUMNS" ]; then
    c="$COLUMNS"
  else
    c=$(stty size 2>/dev/null </dev/tty) && c="${c#* }" || c=""
  fi
  case "$c" in (''|*[!0-9]*) c=0 ;; esac
  printf '%s' "$c"
}

if [ "${VL_DOCTOR:-0}" = "1" ]; then
  {
    printf 'coralline doctor\n'
    printf '  config : %s' "$VL_CONF"
    [ -f "$VL_CONF" ] && printf ' (found)\n' || printf ' (not found — using defaults)\n'
    printf '  jq     : ok\n'
    printf '  style  : %s · layout: %s\n' "$VL_STYLE" "$VL_LAYOUT"
    for s in $VL_SEGMENTS $VL_SEGMENTS2 $VL_SEGMENTS3; do
      if command -v "seg_$s" >/dev/null 2>&1; then
        printf '  segment: %-10s ok\n' "$s"
      else
        printf '  segment: %-10s UNKNOWN — not a valid segment name\n' "$s"
      fi
    done
    printf '  preview:\n'
  } >&2
fi

if [ "$VL_LAYOUT" = "auto" ]; then
  build_segments "$VL_SEGMENTS"
  total=${#SEG_BGS[@]}
  [ "$total" -eq 0 ] && exit 0
  for ((i=0; i<total; i++)); do
    strip_ansi "${SEG_TXT[i]}"
    SEG_LEN[i]=$(disp_width "$STRIP_R")
  done
  W=$(term_cols)
  if [ "$W" -le 0 ] || [ "$VL_MAX_LINES" -le 1 ]; then
    print_range 0 $((total - 1))
    exit 0
  fi
  # Reserve a right-hand margin so wrapped lines never touch the window edge.
  W=$(( W - VL_WRAP_MARGIN ))
  [ "$W" -lt 1 ] && W=1
  # Greedy wrap: per line, width = caps + segment widths + separators.
  # Once VL_MAX_LINES is reached, everything left stays on the last line.
  if [ "$VL_STYLE" = "lean" ]; then CAP_W=0 ; SEP_W=${#VL_LEAN_SEP}
  else                              CAP_W=2 ; SEP_W=1 ; fi
  start=0 ; line=1 ; cur=$(( CAP_W + SEG_LEN[0] ))
  for ((i=1; i<total; i++)); do
    need=$(( cur + SEP_W + SEG_LEN[i] ))
    if [ "$need" -gt "$W" ] && [ "$line" -lt "$VL_MAX_LINES" ]; then
      print_range "$start" $((i - 1))
      start=$i ; line=$((line + 1)) ; cur=$(( CAP_W + SEG_LEN[i] ))
    else
      cur=$need
    fi
  done
  print_range "$start" $((total - 1))
else
  for list in "$VL_SEGMENTS" "$VL_SEGMENTS2" "$VL_SEGMENTS3"; do
    [ -n "$list" ] || continue
    build_segments "$list"
    [ "${#SEG_BGS[@]}" -gt 0 ] && print_range 0 $(( ${#SEG_BGS[@]} - 1 ))
  done
fi
exit 0
