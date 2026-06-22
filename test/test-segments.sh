#!/usr/bin/env bash
# Integration tests for the fork's grafted segments and combined-segment options
# that the upstream merge re-introduced and which the existing suite never covered:
#   - grafted segments: effort, vim, cache, worktree, version, session, sha, custom
#   - per-model rate limits: limit7ds (Sonnet), limit7do (Opus)
#   - VL_CTX_TOKENS modes: off / io / full
#   - VL_LIMIT_RESET modes: countdown / clock / both
#   - a field-alignment canary: four distinct rate-limit percentages must each land
#     in their own segment, guarding the jq-output-order <-> read-variable-list
#     alignment (a future insert/delete on one side would cross-wire the rest).
#
#   bash test/test-segments.sh
#
# Renders the real statusline.sh end-to-end (ANSI stripped) and greps the output.
# Needs bash + jq (+ git, for the sha case). Exits non-zero if any case fails.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../statusline.sh"
SAMPLE="$HERE/sample-input.json"
fail=0
check() {  # $1=description ; $2=1 if pass
  if [ "$2" = "1" ]; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; fail=1; fi
}

tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/coralline-seg-test.XXXXXX") || exit 1
trap 'rm -rf "$tmpdir"' EXIT

# Comprehensive input: the sample plus every field the grafted segments read.
# Distinct, non-colliding rate-limit percentages (41/79/55/88) make the alignment
# canary meaningful — a shifted field would surface the wrong number.
input="$tmpdir/input.json"
jq '.vim.mode = "NORMAL"
  | .version = "2.1.160"
  | .session_id = "abcd1234-5678-90ef"
  | .worktree.name = "demo-wt" | .worktree.branch = "feat/x"
  | .rate_limits.seven_day.used_percentage = 79
  | .rate_limits.seven_day_sonnet = {used_percentage: 55, resets_at: "2030-01-02T00:00:00Z"}
  | .rate_limits.seven_day_opus   = {used_percentage: 88, resets_at: "2030-01-02T00:00:00Z"}' \
  "$SAMPLE" > "$input"

# render SEGMENTS [extra-conf-lines] -> plain (ANSI-stripped) stdout.
# CORALLINE_NO_SAMPLE=1: the 2030 resets are sentinels — never let a test render
# poison the cross-session burn/limit stores.
render() {
  local conf="$tmpdir/c.conf"
  {
    printf 'VL_STYLE="lean"\nVL_LAYOUT="fixed"\nVL_CLOCK="off"\n'
    printf 'VL_SEGMENTS="%s"\n' "$1"
    [ "${2:-}" = "" ] || printf '%s\n' "$2"
  } > "$conf"
  CORALLINE_NO_SAMPLE=1 CORALLINE_CONFIG="$conf" bash "$SCRIPT" < "$input" \
    | sed $'s/\033\\[[0-9;]*m//g'
}
has()  { grep -q "$1" <<<"$2"; }      # substring present
hasE() { grep -qE "$1" <<<"$2"; }     # regex present

# ── Grafted segments render their glyph/label/value ──────────────────────────
out=$(render "effort");  has 'ψ high'     "$out" && check "effort: psi high"        1 || check "effort: psi high"        0
out=$(render "vim");     has '⌨ NORMAL'   "$out" && check "vim: NORMAL"             1 || check "vim: NORMAL"             0
out=$(render "version"); has 'v2.1.160'   "$out" && check "version: v2.1.160"       1 || check "version: v2.1.160"       0
out=$(render "session"); has '#abcd1234'  "$out" && check "session: #abcd1234"      1 || check "session: #abcd1234"      0
out=$(render "cache");   has '↯ 96%'      "$out" && check "cache: hit rate 96%"     1 || check "cache: hit rate 96%"     0
out=$(render "worktree")
  { has '⧉ demo-wt' "$out" && has 'feat/x' "$out"; } && check "worktree: name + branch" 1 || check "worktree: name + branch" 0
out=$(render "custom" 'VL_CUSTOM_CMD="echo hello-custom"')
  has 'hello-custom' "$out" && check "custom: command stdout" 1 || check "custom: command stdout" 0

# ── Per-model limits + field-alignment canary ────────────────────────────────
out=$(render "limit5h limit7d limit7ds limit7do")
{ has '7dS' "$out" && has '7dO' "$out"; } && check "per-model labels: 7dS / 7dO" 1 || check "per-model labels: 7dS / 7dO" 0
{ has '41%' "$out" && has '79%' "$out" && has '55%' "$out" && has '88%' "$out"; } \
  && check "alignment canary: 41/79/55/88 each in its own segment" 1 \
  || check "alignment canary: 41/79/55/88 each in its own segment" 0

# ── VL_CTX_TOKENS modes (off / io / full) ────────────────────────────────────
out=$(render "ctx" 'VL_CTX_TOKENS="off"')
{ has '62%' "$out" && ! has '↑' "$out"; } && check "ctx off: gauge only, no tokens" 1 || check "ctx off: gauge only, no tokens" 0
out=$(render "ctx" 'VL_CTX_TOKENS="io"')
{ has '↑' "$out" && has '↓' "$out" && ! has 'cr:' "$out"; } && check "ctx io: arrows, no cache" 1 || check "ctx io: arrows, no cache" 0
out=$(render "ctx" 'VL_CTX_TOKENS="full"')
{ has 'cr:' "$out" && has 'cw:' "$out"; } && check "ctx full: cache counts" 1 || check "ctx full: cache counts" 0

# ── VL_LIMIT_RESET modes (countdown / clock / both) ──────────────────────────
# VL_CLOCK is off and only limit5h is shown, so the only ':' comes from a
# clock-formatted reset. The 2030 sentinel reset is years out, so a countdown
# always contains a days field ([0-9]+d) — distinct from the "5h" segment label.
out=$(render "limit5h" 'VL_LIMIT_RESET="countdown"')
{ has '↺' "$out" && ! has ':' "$out" && hasE '[0-9]+d' "$out"; } && check "reset countdown: duration, no clock time" 1 || check "reset countdown: duration, no clock time" 0
out=$(render "limit5h" 'VL_LIMIT_RESET="clock"')
{ has '↺' "$out" && has ':' "$out" && ! hasE '[0-9]+d' "$out"; } && check "reset clock: time, no duration" 1 || check "reset clock: time, no duration" 0
out=$(render "limit5h" 'VL_LIMIT_RESET="both"')
{ has '↺' "$out" && has ':' "$out" && hasE '[0-9]+d' "$out"; } && check "reset both: duration + time" 1 || check "reset both: duration + time" 0

# ── sha segment (needs a real git repo: use this checkout) ────────────────────
gitinput="$tmpdir/git.json"
reporoot=$(cd "$HERE/.." && pwd)
jq --arg cwd "$reporoot" '.cwd = $cwd | .workspace.current_dir = $cwd' "$input" > "$gitinput"
shaconf="$tmpdir/sha.conf"
printf 'VL_STYLE="lean"\nVL_LAYOUT="fixed"\nVL_CLOCK="off"\nVL_SEGMENTS="sha"\n' > "$shaconf"
shaout=$(CORALLINE_NO_SAMPLE=1 CORALLINE_CONFIG="$shaconf" bash "$SCRIPT" < "$gitinput" | sed $'s/\033\\[[0-9;]*m//g')
hasE '@[0-9a-f]{7}' "$shaout" && check "sha: @<7-hex> from real repo" 1 || check "sha: @<7-hex> from real repo" 0

# ── Group divider (sep segment) ──────────────────────────────────────────────
# A `sep` between two segments renders the divider glyph and drops the lean
# separator on both sides, so the row reads "a ┃ b", never "a · ┃ · b".
out=$(render "model sep cost" 'VL_LEAN_SEP="·"')
{ has '┃' "$out" && ! has '·' "$out"; } && check "sep: divider replaces the lean separators" 1 || check "sep: divider replaces the lean separators" 0
out=$(render "model effort sep cost" 'VL_LEAN_SEP="·"')
{ has '┃' "$out" && has '·' "$out"; } && check "sep: divider and normal separators coexist" 1 || check "sep: divider and normal separators coexist" 0

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; exit 1; fi
