#!/usr/bin/env bash
# Regression tests for plugins/cpmv (the FileZilla-style copy/move conflict menu).
#
# Purpose: prove that every menu mode does what its label says, for copy ('p')
# and move ('v'), on files and on directory trees, and that failures are visible.
# Background: docs/nnn_Problems_And_Solutions.md Problem 16.
#
# Usage:   misc/test/test-cpmv.sh                  # test plugins/cpmv in this repo
#          CPMV=/path/to/other/cpmv misc/test/test-cpmv.sh
#          VERBOSE=1 misc/test/test-cpmv.sh        # also print PASS lines
#          ONLY=move misc/test/test-cpmv.sh        # run groups whose name contains "move"
# Exit status: 0 when every check passed, 1 otherwise.
#
# The script only touches a private temp directory (removed on exit). It never
# reads or writes the user's real files. It runs the suite once with plain
# cp/mv ops and once more with the advcpmv ops (cpg/mvg) when they are installed.
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CPMV=${CPMV:-$HERE/../../plugins/cpmv}
[ -x "$CPMV" ] || { echo "cpmv not executable: $CPMV"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/nnn-cpmv-test.XXXXXX") || exit 2
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT

OLD=1700000000; MID=1750000000; NEW=1800000000      # epoch seconds
pass=0; fail=0
C=""; OUT=""; RC=0; CPOP=""; MVOP=""; GROUP=""

ok()  { pass=$((pass + 1)); [ "${VERBOSE:-0}" = 1 ] && printf '  PASS  %s\n' "$1"; return 0; }
bad() { fail=$((fail + 1)); printf '  FAIL  [%s] %s\n        %s\n' "$GROUP" "$1" "$2"; return 0; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected=[$2] actual=[$3]"; fi; }

# ---- fixture helpers (all paths are relative to the current case dir $C) ----
new_case() { C="$T/$1"; rm -rf "$C"; mkdir -p "$C/src" "$C/dst"; GROUP="$1"; }
put()  { local f="$C/$1"; mkdir -p "$(dirname -- "$f")"; printf '%s' "$2" > "$f"; touch -d "@$3" "$f"; }
getc() { local f="$C/$1"; if [ -L "$f" ]; then printf '<link:%s>' "$(readlink -- "$f")"
         elif [ -e "$f" ]; then cat -- "$f"; else printf '<missing>'; fi; }
getm() { stat -c %Y -- "$C/$1" 2>/dev/null || printf 'missing'; }
# fc <label> <path> <expected content> [<expected mtime>]
fc() { check "$GROUP: $1 content" "$3" "$(getc "$2")"
       [ $# -ge 4 ] && check "$GROUP: $1 mtime" "$4" "$(getm "$2")"; return 0; }
has_out() { if grep -qE -- "$2" "$OUT"; then ok "$1"; else bad "$1" "pattern [$2] not in output: $(tr '\r' '\n' < "$OUT" | tail -5 | tr '\n' '|')"; fi; }
no_out()  { if grep -qE -- "$2" "$OUT"; then bad "$1" "unexpected pattern [$2] in output"; else ok "$1"; fi; }

# run <op> <typed-answers> <item>...   items are paths relative to $C
run() {
    local op="$1" ans="$2" it; shift 2
    local abs=(); for it in "$@"; do abs+=("$C/$it"); done
    printf '%s\0' "${abs[@]}" | head -c -1 > "$C/sel"        # nnn truncates the last NUL
    OUT="$C/out"
    ( cd "$C/dst" && printf '%b' "$ans" | timeout 60 "$CPMV" "$op" "$C/sel" . ) > "$OUT" 2>&1
    RC=$?
}
want() { [ -z "${ONLY:-}" ] || [[ "$1" == *"$ONLY"* ]]; }

# Mixed fixture: every size/mtime relationship, nested, plus extras on both sides.
#   dn = destination newer, do = destination older, sn = source newer
mixed_fixture() {
    put src/proj/dn_diff.txt "AAAAA"     $OLD;  put dst/proj/dn_diff.txt "xxxxxxx"           $NEW  # dest newer, size differs
    put src/proj/do_diff.txt "DDDDDDDD"  $MID;  put dst/proj/do_diff.txt "zzz"               $OLD  # dest older, size differs
    put src/proj/sn_same.txt "SNEWER"    $NEW;  put dst/proj/sn_same.txt "sold!!"            $OLD  # source newer, same size
    put src/proj/dn_same.txt "SOLD!!"    $OLD;  put dst/proj/dn_same.txt "DNEWER"            $NEW  # dest newer, same size
    put src/proj/ident.txt   "SAME"      $MID;  put dst/proj/ident.txt   "SAME"              $MID  # identical
    put src/proj/only_src.txt "ONLYSRC"  $MID
    put dst/proj/only_dst.txt "ONLYDST"  $MID
    put src/proj/sub/deep/n_dn.txt "nested-src" $OLD; put dst/proj/sub/deep/n_dn.txt "nested-dst-longer" $NEW
    mkdir -p "$C/src/proj/emptydir"
}

# ============================== COPY, directory ==============================
g_copy_mode4() {
    new_case copy-mode4; mixed_fixture
    run "$CPOP" '4\n' src/proj
    fc "dest newer + size differs (the reported bug)" dst/proj/dn_diff.txt  "AAAAA"    $OLD
    fc "dest older + size differs"                    dst/proj/do_diff.txt  "DDDDDDDD" $MID
    fc "source newer + same size"                     dst/proj/sn_same.txt  "SNEWER"   $NEW
    fc "dest newer + same size is kept"               dst/proj/dn_same.txt  "DNEWER"   $NEW
    fc "identical stays"                              dst/proj/ident.txt    "SAME"     $MID
    fc "only in source is created"                    dst/proj/only_src.txt "ONLYSRC"  $MID
    fc "only in destination is kept"                  dst/proj/only_dst.txt "ONLYDST"  $MID
    fc "nested dest newer + size differs"             dst/proj/sub/deep/n_dn.txt "nested-src" $OLD
    check "copy-mode4: empty source dir is created" "yes" "$([ -d "$C/dst/proj/emptydir" ] && echo yes || echo no)"
    check "copy-mode4: source tree untouched" "AAAAA|SOLD!!" "$(getc src/proj/dn_diff.txt)|$(getc src/proj/dn_same.txt)"
    check "copy-mode4: exit status 0" "0" "$RC"
    no_out "copy-mode4: single directory shows no pause" 'Press enter'
}

g_copy_mode3() {
    new_case copy-mode3; mixed_fixture
    run "$CPOP" '3\n' src/proj
    fc "size differs, dest newer is replaced"  dst/proj/dn_diff.txt "AAAAA"    $OLD
    fc "size differs, dest older is replaced"  dst/proj/do_diff.txt "DDDDDDDD" $MID
    fc "same size, source newer is NOT touched (content and mtime)" dst/proj/sn_same.txt "sold!!" $OLD
    fc "same size, dest newer is NOT touched"  dst/proj/dn_same.txt "DNEWER"   $NEW
    fc "only in source is created"             dst/proj/only_src.txt "ONLYSRC" $MID
    fc "nested size differs is replaced"       dst/proj/sub/deep/n_dn.txt "nested-src" $OLD
    # Regression: a size-only run must not make a stale file look current to a later run.
    run "$CPOP" '4\n' src/proj
    fc "mode 4 after mode 3 still refreshes the source-newer file" dst/proj/sn_same.txt "SNEWER" $NEW
}

g_copy_mode2() {
    new_case copy-mode2; mixed_fixture
    run "$CPOP" '2\n' src/proj
    fc "source newer is copied"                dst/proj/sn_same.txt "SNEWER"   $NEW
    fc "dest older (size differs) is copied"   dst/proj/do_diff.txt "DDDDDDDD" $MID
    fc "dest newer + size differs is kept"     dst/proj/dn_diff.txt "xxxxxxx"  $NEW
    fc "dest newer + same size is kept"        dst/proj/dn_same.txt "DNEWER"   $NEW
    fc "only in source is created"             dst/proj/only_src.txt "ONLYSRC" $MID
}

g_copy_mode1() {
    new_case copy-mode1; mixed_fixture
    chmod 444 "$C/dst/proj/dn_same.txt"                       # read-only target
    run "$CPOP" '1\n' src/proj
    fc "dest newer + size differs overwritten" dst/proj/dn_diff.txt "AAAAA"    $OLD
    fc "dest newer + same size overwritten"    dst/proj/dn_same.txt "SOLD!!"   $OLD
    fc "read-only target is overwritten too"   dst/proj/dn_same.txt "SOLD!!"
    fc "only in destination is kept"           dst/proj/only_dst.txt "ONLYDST" $MID
    check "copy-mode1: exit status 0" "0" "$RC"
}

g_copy_mode567() {
    new_case copy-mode5
    put src/proj/big.bin "0123456789ABCDEFGHIJ" $MID;  put dst/proj/big.bin "0123456789" $MID   # interrupted copy
    put src/proj/ok.txt  "SAME" $MID;                   put dst/proj/ok.txt  "SAME" $MID
    run "$CPOP" '5\n' src/proj
    fc "resume completes the partial file" dst/proj/big.bin "0123456789ABCDEFGHIJ"
    fc "resume leaves a complete file"     dst/proj/ok.txt  "SAME" $MID
    new_case copy-mode6; mixed_fixture
    run "$CPOP" '6\n' src/proj;  run "$CPOP" '6\n' src/proj
    fc "rename keeps the original"          dst/proj/dn_diff.txt       "xxxxxxx"
    fc "rename makes 'proj (1)'"            "dst/proj (1)/dn_diff.txt" "AAAAA"
    fc "second rename makes 'proj (2)'"     "dst/proj (2)/dn_diff.txt" "AAAAA"
    new_case copy-mode7; mixed_fixture
    run "$CPOP" '7\n' src/proj
    fc "skip changes nothing" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    check "copy-mode7: no new files" "<missing>" "$(getc dst/proj/only_src.txt)"
}

# =============================== MOVE, directory =============================
miss() { check "$GROUP: $1 is gone" "<missing>" "$(getc "$2")"; }

g_move_mode4() {
    new_case move-mode4; mixed_fixture
    run "$MVOP" '4\n' src/proj
    fc "dest newer + size differs is moved over"  dst/proj/dn_diff.txt  "AAAAA"    $OLD
    fc "dest older + size differs is moved over"  dst/proj/do_diff.txt  "DDDDDDDD" $MID
    fc "source newer + same size is moved over"   dst/proj/sn_same.txt  "SNEWER"   $NEW
    fc "dest newer + same size keeps the target"  dst/proj/dn_same.txt  "DNEWER"   $NEW
    fc "nested file is moved over"                dst/proj/sub/deep/n_dn.txt "nested-src" $OLD
    fc "only-in-source is moved"                  dst/proj/only_src.txt "ONLYSRC"  $MID
    miss "moved source dn_diff" src/proj/dn_diff.txt
    miss "moved source only_src" src/proj/only_src.txt
    miss "identical source (already at target)" src/proj/ident.txt
    miss "emptied source subdir" src/proj/sub
    miss "emptied source empty dir" src/proj/emptydir
    fc "skipped file stays in the SOURCE (no data loss)" src/proj/dn_same.txt "SOLD!!" $OLD
    check "move-mode4: exit status 0" "0" "$RC"
    has_out "move-mode4: tells the user a file was kept" 'kept|left in the source'
}

g_move_mode3() {
    new_case move-mode3; mixed_fixture
    run "$MVOP" '3\n' src/proj
    fc "size differs is moved over"          dst/proj/dn_diff.txt "AAAAA" $OLD
    fc "same size, source newer: target untouched" dst/proj/sn_same.txt "sold!!" $OLD
    fc "same size, source newer stays in the SOURCE" src/proj/sn_same.txt "SNEWER" $NEW
    fc "same size, dest newer stays in the SOURCE"   src/proj/dn_same.txt "SOLD!!" $OLD
    miss "identical source" src/proj/ident.txt
}

g_move_mode2() {
    new_case move-mode2; mixed_fixture
    run "$MVOP" '2\n' src/proj
    fc "source newer is moved"             dst/proj/sn_same.txt "SNEWER"   $NEW
    fc "dest older is moved"               dst/proj/do_diff.txt "DDDDDDDD" $MID
    fc "dest newer + size differs is kept" dst/proj/dn_diff.txt "xxxxxxx"  $NEW
    fc "and its source stays"              src/proj/dn_diff.txt "AAAAA"    $OLD
    fc "nested dest-newer source stays"    src/proj/sub/deep/n_dn.txt "nested-src" $OLD
    miss "moved source sn_same" src/proj/sn_same.txt
    check "move-mode2: exit status 0 (no 'Directory not empty' failure)" "0" "$RC"
    no_out "move-mode2: no mv error" 'cannot move'
}

g_move_mode1() {
    new_case move-mode1; mixed_fixture
    run "$MVOP" '1\n' src/proj
    fc "dest newer + same size overwritten" dst/proj/dn_same.txt "SOLD!!" $OLD
    fc "dest newer + size differs overwritten" dst/proj/dn_diff.txt "AAAAA" $OLD
    fc "only in destination is kept"        dst/proj/only_dst.txt "ONLYDST" $MID
    fc "nested overwritten"                 dst/proj/sub/deep/n_dn.txt "nested-src" $OLD
    miss "whole source tree" src/proj
    check "move-mode1: exit status 0 (no 'Directory not empty' failure)" "0" "$RC"
    no_out "move-mode1: no mv error" 'cannot move'
}

g_move_mode567() {
    new_case move-mode5
    put src/proj/big.bin "0123456789ABCDEFGHIJ" $MID; put dst/proj/big.bin "0123456789" $MID
    run "$MVOP" '5\n' src/proj
    fc "resume completes the partial file" dst/proj/big.bin "0123456789ABCDEFGHIJ"
    miss "source after resumed move" src/proj
    new_case move-mode6; mixed_fixture
    run "$MVOP" '6\n' src/proj
    fc "rename moves the whole tree to 'proj (1)'" "dst/proj (1)/dn_diff.txt" "AAAAA"
    fc "rename keeps the original target"          dst/proj/dn_diff.txt "xxxxxxx"
    miss "source after rename-move" src/proj
    new_case move-mode7; mixed_fixture
    run "$MVOP" '7\n' src/proj
    fc "skip leaves the source intact" src/proj/dn_diff.txt "AAAAA"
    fc "skip leaves the target intact" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    new_case move-noconflict
    put src/proj/a.txt "A" $MID
    run "$MVOP" '' src/proj
    fc "no conflict: moved"  dst/proj/a.txt "A" $MID
    miss "no conflict: source" src/proj
}

# =================== single file, multiple items, apply-to-all ===============
g_single_file_prompt() {
    new_case single-file-y
    put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
    run "$CPOP" 'y\n' src/f.txt
    fc "copy file, answer y overwrites" dst/f.txt "new" $NEW
    has_out "single file uses the simple y/N prompt" "overwrite 'f.txt'\? \[y/N\]"
    no_out  "single file never shows the 7-way menu" 'CONFLICT'
    new_case single-file-n
    put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
    run "$CPOP" 'n\n' src/f.txt
    fc "copy file, answer n keeps target" dst/f.txt "old-longer" $OLD
    new_case single-file-mv
    put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
    run "$MVOP" 'y\n' src/f.txt
    fc "move file, answer y overwrites" dst/f.txt "new" $NEW
    miss "move file source" src/f.txt
}

two_dirs_and_file() {         # A, B (dest newer + size differs) and file c.txt (same)
    put src/A/x.txt "A-src" $OLD;  put dst/A/x.txt "A-dst-longer" $NEW
    put src/B/y.txt "B-src" $OLD;  put dst/B/y.txt "B-dst-longer" $NEW
    put src/c.txt   "C-src" $OLD;  put dst/c.txt   "C-dst-longer" $NEW
}

g_apply_to_all() {
    new_case apply-all; two_dirs_and_file
    run "$CPOP" '4\ny\n\n' src/A src/B src/c.txt
    fc "first item uses mode 4"                 dst/A/x.txt "A-src" $OLD
    fc "second item reuses mode 4 (apply to all)" dst/B/y.txt "B-src" $OLD
    fc "plain file reuses mode 4 (apply to all)" dst/c.txt   "C-src" $OLD
    has_out "several conflicts end with a pause for review" 'Done\. Press enter'
    new_case apply-no; two_dirs_and_file
    run "$CPOP" '4\nn\n7\n' src/A src/B
    fc "first item uses mode 4"           dst/A/x.txt "A-src" $OLD
    fc "second item skipped by its own answer" dst/B/y.txt "B-dst-longer" $NEW
    new_case apply-all-move; two_dirs_and_file
    run "$MVOP" '4\ny\n\n' src/A src/B src/c.txt
    fc "move: first item mode 4"  dst/A/x.txt "A-src" $OLD
    fc "move: second item mode 4" dst/B/y.txt "B-src" $OLD
    fc "move: plain file mode 4"  dst/c.txt   "C-src" $OLD
    miss "move: source A" src/A; miss "move: source c.txt" src/c.txt
}

# ============================ errors must be visible =========================
g_errors() {
    local mode
    # An unreadable source file makes cp and rsync fail for real (rsync, unlike cp,
    # can write into a read-only directory that the user owns, so that is no test).
    for mode in 4 3 1; do
        new_case "err-copy-$mode"; mixed_fixture
        chmod 000 "$C/src/proj/sub/deep/n_dn.txt"
        run "$CPOP" "$mode\\n" src/proj
        chmod 644 "$C/src/proj/sub/deep/n_dn.txt"
        fc "other files are still copied (best effort)" dst/proj/only_src.txt "ONLYSRC" $MID
        fc "the unreadable file leaves the target unchanged" dst/proj/sub/deep/n_dn.txt "nested-dst-longer" $NEW
        check "err-copy-$mode: non-zero exit so nnn pauses and keeps the selection" "1" "$RC"
        has_out "err-copy-$mode: the error is printed" 'Permission denied|failed|error'
        has_out "err-copy-$mode: a summary lists the problem" 'problem\(s\)'
    done
    for mode in 4 3 1; do
        new_case "err-move-$mode"; mixed_fixture
        chmod 000 "$C/src/proj/sub/deep/n_dn.txt"
        run "$MVOP" "$mode\\n" src/proj
        chmod 644 "$C/src/proj/sub/deep/n_dn.txt"
        fc "the file that could not be read is NOT lost: it stays in the source" src/proj/sub/deep/n_dn.txt "nested-src" $OLD
        check "err-move-$mode: non-zero exit" "1" "$RC"
    done
    new_case err-vanished
    run "$CPOP" '' src/ghost
    check "missing source gives a non-zero exit" "1" "$RC"
    has_out "missing source is named in the output" 'ghost'
}

g_type_mismatch() {
    new_case mismatch
    put src/thing "i am a file" $NEW; mkdir -p "$C/dst/thing"; put dst/thing/keep.txt "KEEP" $MID
    run "$CPOP" '4\n7\n' src/thing
    has_out "file onto directory: modes that cannot work are rejected" 'invalid'
    fc "directory with its content is untouched" dst/thing/keep.txt "KEEP" $MID
    check "mismatch skipped by the user: exit 0" "0" "$RC"
    new_case mismatch-rename
    put src/thing "i am a file" $NEW; mkdir -p "$C/dst/thing"
    run "$CPOP" '6\n' src/thing
    fc "rename keeps both" "dst/thing (1)" "i am a file"
    new_case mismatch-allmode; two_dirs_and_file; put src/thing "file" $NEW; mkdir -p "$C/dst/thing"
    run "$CPOP" '4\ny\n7\n\n' src/A src/thing
    fc "apply-to-all does not force a mode on a type clash" dst/A/x.txt "A-src" $OLD
    check "type clash still a directory" "yes" "$([ -d "$C/dst/thing" ] && echo yes || echo no)"
}

# ============================ awkward file names =============================
g_names() {
    # shellcheck disable=SC2016  # the dollar and glob characters below are meant literally
    local names=("with space.txt" "-dash.txt" "quo'te.txt" 'dq"uote.txt' 'glob*[x]?.txt' 'back\slash.txt'
                 'back\#012x.txt' $'new\nline.txt' $'tab\there.txt' ' leading.txt' 'ünï.txt' '~tilde.txt' '$dollar.txt' '--help')
    local n mode op
    for mode in 4 3; do
        new_case "names-copy-$mode"
        for n in "${names[@]}"; do put "src/we ird'dir/$n" "src" $OLD; put "dst/we ird'dir/$n" "dest-longer" $NEW; done
        run "$CPOP" "$mode\\n" "src/we ird'dir"
        for n in "${names[@]}"; do fc "$n" "dst/we ird'dir/$n" "src" $OLD; done
    done
    new_case names-move
    for n in "${names[@]}"; do put "src/we ird'dir/$n" "src" $OLD; put "dst/we ird'dir/$n" "dest-longer" $NEW; done
    run "$MVOP" '4\n' "src/we ird'dir"
    for n in "${names[@]}"; do fc "move: $n" "dst/we ird'dir/$n" "src" $OLD; done
    miss "move: source dir with awkward names" "src/we ird'dir"
}

g_symlinks() {
    new_case symlinks
    put src/proj/real.txt "REAL-NEW" $NEW; ln -s real.txt "$C/src/proj/lnk"
    put dst/proj/real.txt "old" $OLD
    run "$CPOP" '4\n' src/proj
    fc "regular file next to a link updated" dst/proj/real.txt "REAL-NEW" $NEW
    fc "source symlink is copied as a symlink" dst/proj/lnk "<link:real.txt>"
    new_case dirlink
    put src/proj/f.txt "SRC" $OLD; put dst/realdir/f.txt "dest-longer" $NEW; ln -s realdir "$C/dst/proj"
    run "$CPOP" '4\n' src/proj
    fc "a symlinked target directory is merged INTO (like cp does)" dst/realdir/f.txt "SRC" $OLD
    check "dirlink: the target symlink is kept" "yes" "$([ -L "$C/dst/proj" ] && echo yes || echo no)"
}

# ===================== randomized check against a simple oracle =============
build_oracle() {     # fills the trees and the expected-content maps E3 and E4
    local i d f c
    RANDOM=20261107; E3=(); E4=()
    for i in $(seq 1 160); do
        d=$((RANDOM % 5)); f="proj/d$d/f$i.txt"; c=$((RANDOM % 7))
        case $c in
        0) put "src/$f" "S$i" $MID; E3[$f]="S$i"; E4[$f]="S$i" ;;                                  # missing in dest
        1) put "src/$f" "SAME$i" $MID; put "dst/$f" "SAME$i" $MID; E3[$f]="SAME$i"; E4[$f]="SAME$i" ;;
        2) put "src/$f" "s$i" $OLD; put "dst/$f" "d$i-longer" $NEW; E3[$f]="s$i"; E4[$f]="s$i" ;;   # dest newer, size differs
        3) put "src/$f" "src-long-$i" $MID; put "dst/$f" "d" $OLD; E3[$f]="src-long-$i"; E4[$f]="src-long-$i" ;;
        4) put "src/$f" "NEWER-$i" $NEW; put "dst/$f" "older-$i" $OLD; E3[$f]="older-$i"; E4[$f]="NEWER-$i" ;;  # source newer, same size
        5) put "src/$f" "SOLD-$i" $OLD; put "dst/$f" "dnew-$i" $NEW; E3[$f]="dnew-$i"; E4[$f]="dnew-$i" ;;     # dest newer, same size
        6) put "dst/$f" "ONLYDST-$i" $MID; E3[$f]="ONLYDST-$i"; E4[$f]="ONLYDST-$i" ;;
        esac
    done
}
g_oracle() {
    local mode f bad_n op
    for op in copy move; do
        for mode in 3 4; do
            new_case "oracle-$op-$mode"; declare -gA E3 E4; build_oracle
            if [ $op = copy ]; then run "$CPOP" "$mode\\n" src/proj; else run "$MVOP" "$mode\\n" src/proj; fi
            bad_n=0
            for f in "${!E3[@]}"; do
                if [ $mode = 3 ]; then want_c="${E3[$f]}"; else want_c="${E4[$f]}"; fi
                [ "$(getc "dst/$f")" = "$want_c" ] || { bad_n=$((bad_n + 1)); [ $bad_n -le 3 ] && bad "oracle $op mode $mode: $f" "expected=[$want_c] actual=[$(getc "dst/$f")]"; }
            done
            check "oracle $op mode $mode: all ${#E3[@]} files match the policy" "0" "$bad_n"
        done
    done
}

# @@APPEND@@

# ================================ main ======================================
run_suite() {
    local g
    for g in "$@"; do want "${g#g_}" && "$g"; done
}
SUITE=(g_copy_mode4 g_copy_mode3 g_copy_mode2 g_copy_mode1 g_copy_mode567
       g_move_mode4 g_move_mode3 g_move_mode2 g_move_mode1 g_move_mode567
       g_single_file_prompt g_apply_to_all g_errors g_type_mismatch g_names g_symlinks g_oracle)

if [ "${1:-}" = "--list" ]; then printf '%s\n' "${SUITE[@]}"; exit 0; fi
printf 'cpmv under test: %s\n' "$CPMV"
CPOP="cp -iRp --"; MVOP="mv -i --"
echo "--- ops: $CPOP / $MVOP"; run_suite "${SUITE[@]}"
if command -v cpg >/dev/null 2>&1 && command -v mvg >/dev/null 2>&1; then
    CPOP="cpg -giRp --"; MVOP="mvg -gi --"
    echo "--- ops: $CPOP / $MVOP"; run_suite "${SUITE[@]}"
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
