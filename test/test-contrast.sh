#!/usr/bin/env bash
# Contrast regression for the segments this fork adds.
#
# These segments draw a fixed foreground knob onto their own pill, so a theme
# that sets the pill to (or near) that same colour makes the segment invisible.
# That is not hypothetical: catppuccin-mocha once shipped VL_BG_SHA and
# VL_BG_VERSION equal to VL_FG_DIM, a 1.00:1 pair that rendered nothing at all.
#
# Two tiers, because the segments do different jobs:
#   4.5  worktree / vim / custom / conflict / cache — carry signal you must read
#   3.0  sha / version / session — deliberately recessed metadata drawn in
#        VL_FG_DIM; they must never be invisible, but must not out-shout the
#        data segments either.
#
#   bash test/test-contrast.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/.."
fail=0
ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=1; }

command -v python3 >/dev/null 2>&1 || { ok "contrast (skipped: no python3)"; exit 0; }

out=$(python3 - "$ROOT" <<'PY'
import glob,os,re,sys,colorsys
root=sys.argv[1]
def xterm(i):
    i=int(i)
    if i<16:
        return [(0,0,0),(128,0,0),(0,128,0),(128,128,0),(0,0,128),(128,0,128),(0,128,128),(192,192,192),
                (128,128,128),(255,0,0),(0,255,0),(255,255,0),(0,0,255),(255,0,255),(0,255,255),(255,255,255)][i]
    if i<232:
        i-=16; l=[0,95,135,175,215,255]; return (l[i//36],l[(i//6)%6],l[i%6])
    v=8+(i-232)*10; return (v,v,v)
def rgb(v):
    v=v.strip().strip('"').strip("'")
    if not v: return None
    if ',' in v:
        try: return tuple(int(x) for x in v.split(','))
        except ValueError: return None
    return xterm(v) if v.isdigit() else None
def lum(c):
    f=lambda x: (x/255)/12.92 if (x/255)<=0.03928 else (((x/255)+0.055)/1.055)**2.4
    return 0.2126*f(c[0])+0.7152*f(c[1])+0.0722*f(c[2])
def ratio(a,b):
    la,lb=lum(a),lum(b); hi,lo=max(la,lb),min(la,lb); return (hi+0.05)/(lo+0.05)
def parse(path):
    d={}
    for line in open(path,encoding="utf-8"):
        m=re.match(r'^(VL_(?:BG|FG)_[A-Z0-9_]+)=(.*?)(?:\s+#.*)?$',line.rstrip("\n"))
        if m: d[m.group(1)]=m.group(2)
    return d
# fg knob(s) each segment draws with, and its tier
SPEC={'WORKTREE':(['VL_FG_TEXT'],4.5),'VIM':(['VL_FG_TEXT'],4.5),
      'CUSTOM':(['VL_FG_TEXT'],4.5),'CONFLICT':(['VL_FG_TEXT'],4.5),
      'CACHE':(['VL_FG_OK','VL_FG_WARN','VL_FG_HOT'],4.5),
      'SHA':(['VL_FG_DIM'],3.0),'VERSION':(['VL_FG_DIM'],3.0),'SESSION':(['VL_FG_DIM'],3.0)}
base=parse(os.path.join(root,"statusline.sh"))
# lunar-pink's gauge inks span deep red to bright green; no single ground clears
# 4.5 against both, and its own ctx/limit segments have the same ceiling. Pinned
# to the best its palette allows so the suite still catches a regression there.
EXCEPT={('lunar-pink','CACHE'):3.0}
for path in sorted(glob.glob(os.path.join(root,"themes","*.conf"))):
    name=os.path.basename(path)[:-5]
    t=dict(base); t.update(parse(path))
    for seg,(fgks,target) in SPEC.items():
        target=EXCEPT.get((name,seg),target)
        bg=rgb(t.get('VL_BG_'+seg,''))
        fgs=[rgb(t[k]) for k in fgks if k in t and rgb(t[k])]
        if bg is None: print(f"MISS {name} {seg}"); continue
        if not fgs:    print(f"MISS {name} {seg}-fg"); continue
        r=min(ratio(bg,f) for f in fgs)
        print(("PASS " if r>=target else "FAIL ")+f"{name} {seg} {r:.2f} {target:.1f}")
PY
)
while read -r verdict theme seg got want; do
  case "$verdict" in
    PASS) : ;;
    FAIL) bad "$theme $seg" "contrast ${got}:1, want >= ${want}:1" ;;
    MISS) bad "$theme $seg" "no value and no runtime default" ;;
  esac
done <<< "$out"
total=$(printf '%s\n' "$out" | grep -c .)
passed=$(printf '%s\n' "$out" | grep -c '^PASS')
[ "$fail" -eq 0 ] && ok "$passed/$total theme x segment pairs meet their contrast tier"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
