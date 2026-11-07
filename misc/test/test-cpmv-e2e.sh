#!/usr/bin/env bash
# End-to-end test of the cpmv conflict menu through the REAL nnn binary.
#
# Purpose: misc/test/test-cpmv.sh runs plugins/cpmv directly. This script checks the
# whole path a user takes: nnn reads the selection, presses 'p' (copy) or 'v' (move),
# runs the plugin on the terminal, shows nnn's own pause on failure, and clears or
# keeps the selection. Background: docs/nnn_Problems_And_Solutions.md Problem 16.
#
# Isolation: a private tmux server (socket "cpmve2e-<pid>"), a private config dir
# (XDG_CONFIG_HOME) and a private selection file (NNN_SEL). The user's running tmux
# sessions, nnn sessions and real selection are never touched.
#
# Usage:  misc/test/test-cpmv-e2e.sh
#         NNN=/path/to/nnn CPMV=/path/to/cpmv misc/test/test-cpmv-e2e.sh
# Time:   about 30 seconds. Every wait has a 15 s ceiling; the whole run is capped at 240 s.
# Exit:   0 when all checks pass, 1 otherwise, 2 when tmux or the nnn binary is missing.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
NNN=${NNN:-$REPO/nnn}
CPMV=${CPMV:-$REPO/plugins/cpmv}
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 2; }
[ -x "$NNN" ] || { echo "nnn binary not found: $NNN (build it with ./build.sh)"; exit 2; }
strings -a "$NNN" 2>/dev/null | grep -q 'plugins/cpmv' || { echo "this nnn build lacks FZ_CPMV (use ./build.sh)"; exit 2; }

S=$(mktemp -d "${TMPDIR:-/tmp}/nnn-cpmv-e2e.XXXXXX") || exit 2
SOCK="cpmve2e-$$"
START=$SECONDS
tm() { tmux -L "$SOCK" "$@"; }
cleanup() {
    tm kill-server 2>/dev/null
    rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"          # kill-server leaves the socket file behind
    chmod -R u+rwX "$S" 2>/dev/null; rm -rf "$S"
}
trap cleanup EXIT

mkdir -p "$S/cfg/nnn/plugins" "$S/home"
ln -s "$CPMV" "$S/cfg/nnn/plugins/cpmv"
SEL="$S/sel"
OLD=1700000000; NEW=1800000000
pass=0; fail=0
ok()    { pass=$((pass + 1)); printf '  PASS  %s\n' "$1"; }
bad()   { fail=$((fail + 1)); printf '  FAIL  %s\n        %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected=[$2] actual=[$3]"; fi; }

pane()  { tm capture-pane -p -t t 2>/dev/null; }
# waitfor <regex> [seconds]: poll the pane (ceiling 15 s per wait, 240 s for the run)
waitfor() {
    local re="$1" max=${2:-15} t0=$SECONDS
    while [ $((SECONDS - t0)) -lt "$max" ] && [ $((SECONDS - START)) -lt 240 ]; do
        pane | grep -qE -- "$re" && return 0
        sleep 0.2
    done
    return 1
}
keys() { tm send-keys -t t "$@"; }
# wait_content <file> <expected> [seconds]: poll until the file holds the text (ceiling 15 s by default)
wait_content() {
    local f="$1" want="$2" max=${3:-15} t0=$SECONDS
    while [ $((SECONDS - t0)) -lt "$max" ] && [ $((SECONDS - START)) -lt 240 ]; do
        [ "$(cat -- "$f" 2>/dev/null)" = "$want" ] && return 0
        sleep 0.2
    done
    return 1
}
# wait_gone <path> [seconds]: poll until the path no longer exists
wait_gone() {
    local f="$1" max=${2:-15} t0=$SECONDS
    while [ $((SECONDS - t0)) -lt "$max" ] && [ $((SECONDS - START)) -lt 240 ]; do
        [ -e "$f" ] || return 0
        sleep 0.2
    done
    return 1
}
put()  { mkdir -p "$(dirname -- "$1")"; printf '%s' "$2" > "$1"; touch -d "@$3" "$1"; }
cat_or() { if [ -e "$1" ]; then cat -- "$1"; else printf '<missing>'; fi; }
sel_set() { printf '%s' "$1" > "$SEL"; }                  # nnn truncates the last NUL
sel_len() { stat -c %s "$SEL" 2>/dev/null || echo 0; }

# One nnn per case: a fresh shell with a clean environment, then nnn in <dir>.
start_nnn() {   # start_nnn <dir> [nnn options]
    local dir="$1"; shift
    tm kill-server 2>/dev/null
    tm -f /dev/null new-session -d -s t -x 150 -y 40 \
        "env -i HOME='$S/home' PATH='$PATH' TERM=xterm-256color LANG=C.UTF-8 XDG_CONFIG_HOME='$S/cfg' NNN_SEL='$SEL' bash --norc --noprofile"
    sleep 0.5
    keys "cd '$dir' && '$NNN' $* ." Enter
    waitfor '^1 2 3 4 5 6 7 8 ' 10 || bad "nnn started in $dir" "pane: $(pane | head -5 | tr '\n' '|')"
}
stop_nnn() { keys q; sleep 0.3; tm kill-server 2>/dev/null; }

fixture() {      # fixture <case-dir>: the user's situation, a newer target of a different size
    rm -rf "$1"; mkdir -p "$1/src" "$1/dst"
    put "$1/src/proj/dn_diff.txt" "AAAAA"    $OLD;  put "$1/dst/proj/dn_diff.txt" "xxxxxxx" $NEW   # the reported bug
    put "$1/src/proj/sn_same.txt" "SNEWER"   $NEW;  put "$1/dst/proj/sn_same.txt" "sold!!"  $OLD
    put "$1/src/proj/dn_same.txt" "SOLD!!"   $OLD;  put "$1/dst/proj/dn_same.txt" "DNEWER"  $NEW   # policy: keep
    put "$1/src/proj/sub/deep.txt" "deep-src" $OLD; put "$1/dst/proj/sub/deep.txt" "deep-dst-longer" $NEW
}

# ---------------------------------------------------------------- 1. copy
echo "== E2E 1: copy with 'p', menu answer 4 (the reported case)"
C="$S/c1"; fixture "$C"; sel_set "$C/src/proj"
start_nnn "$C/dst"
keys p
waitfor 'choose \[1-7\]' || bad "menu shown after pressing p" "pane: $(pane | tail -12 | tr '\n' '|')"
pane | grep -q 'CONFLICT: proj' && ok "CONFLICT menu is shown for the directory" || bad "CONFLICT menu is shown" "no CONFLICT line"
keys 4 Enter
wait_content "$C/dst/proj/dn_diff.txt" "AAAAA" || true
wait_content "$SEL" "" || true                         # nnn clears the selection when the plugin has returned
check "dest newer + size differs is overwritten"     "AAAAA"  "$(cat_or "$C/dst/proj/dn_diff.txt")"
check "source newer + same size is overwritten"      "SNEWER" "$(cat_or "$C/dst/proj/sn_same.txt")"
check "dest newer + same size is kept"               "DNEWER" "$(cat_or "$C/dst/proj/dn_same.txt")"
check "nested dest newer + size differs overwritten" "deep-src" "$(cat_or "$C/dst/proj/sub/deep.txt")"
check "selection is cleared after a successful copy" "0" "$(sel_len)"
check "source is untouched by a copy"                "AAAAA" "$(cat_or "$C/src/proj/dn_diff.txt")"
stop_nnn

# ---------------------------------------------------------------- 2. move with leftovers
echo "== E2E 2: move with 'v', answer 4, a kept file stays in the source"
C="$S/c2"; fixture "$C"; sel_set "$C/src/proj"
start_nnn "$C/dst"
keys v
waitfor 'choose \[1-7\]' || bad "menu shown after pressing v" "pane: $(pane | tail -12 | tr '\n' '|')"
keys 4 Enter
waitfor "Done\. Press enter" || bad "move that kept a file pauses for review" "pane: $(pane | tail -8 | tr '\n' '|')"
pane | grep -q 'kept in the source' && ok "the pause names the kept file" || bad "kept notice" "not on screen"
keys Enter
wait_content "$SEL" "" || true
check "moved over: dest newer + size differs" "AAAAA" "$(cat_or "$C/dst/proj/dn_diff.txt")"
check "kept target of the same size"          "DNEWER" "$(cat_or "$C/dst/proj/dn_same.txt")"
check "kept file is still in the SOURCE"      "SOLD!!" "$(cat_or "$C/src/proj/dn_same.txt")"
check "moved file left the source"            "<missing>" "$(cat_or "$C/src/proj/dn_diff.txt")"
check "selection is cleared after the move"   "0" "$(sel_len)"
stop_nnn

# ---------------------------------------------------------------- 3. failure keeps the selection
echo "== E2E 3: a failing copy shows nnn's pause and keeps the selection, retry works"
C="$S/c3"; fixture "$C"; sel_set "$C/src/proj"
chmod 000 "$C/src/proj/sub/deep.txt"
start_nnn "$C/dst"
keys p
waitfor 'choose \[1-7\]' || bad "menu shown" "pane: $(pane | tail -12 | tr '\n' '|')"
keys 4 Enter
waitfor "Enter' to continue" || bad "nnn pauses after a failed paste" "pane: $(pane | tail -10 | tr '\n' '|')"
pane | grep -q 'problem(s)' && ok "the problems are listed on screen" || bad "problem list" "not on screen"
keys Enter
waitfor 'failed!' 5 && ok "nnn reports failed!" || bad "nnn reports failed!" "pane: $(pane | tail -4 | tr '\n' '|')"
[ "$(sel_len)" -gt 0 ] && ok "selection is KEPT after a failure" || bad "selection kept" "selection file is empty"
check "other files were still copied" "AAAAA" "$(cat_or "$C/dst/proj/dn_diff.txt")"
chmod 644 "$C/src/proj/sub/deep.txt"
keys p
waitfor 'choose \[1-7\]' || bad "retry shows the menu again" "pane: $(pane | tail -8 | tr '\n' '|')"
keys 4 Enter
wait_content "$C/dst/proj/sub/deep.txt" "deep-src" || true
wait_content "$SEL" "" || true
check "retry copies the file that failed" "deep-src" "$(cat_or "$C/dst/proj/sub/deep.txt")"
check "selection is cleared after the retry succeeds" "0" "$(sel_len)"
stop_nnn

# ---------------------------------------------------------------- 4. advcpmv (-r)
if command -v cpg >/dev/null 2>&1; then
    echo "== E2E 4: the same copy with nnn -r (advcpmv cpg/mvg ops)"
    C="$S/c4"; fixture "$C"; sel_set "$C/src/proj"
    start_nnn "$C/dst" -r
    keys p
    waitfor 'choose \[1-7\]' || bad "menu shown with -r" "pane: $(pane | tail -8 | tr '\n' '|')"
    keys 4 Enter
    wait_content "$C/dst/proj/dn_diff.txt" "AAAAA" || true
    wait_content "$SEL" "" || true
    check "advcpmv build: dest newer + size differs overwritten" "AAAAA" "$(cat_or "$C/dst/proj/dn_diff.txt")"
    stop_nnn
fi

printf '\n%d passed, %d failed (%ds)\n' "$pass" "$fail" "$((SECONDS - START))"
[ "$fail" -eq 0 ]
