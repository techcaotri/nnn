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
    ( cd "$C/${DEST:-dst}" && printf '%b' "$ans" | timeout 60 "$CPMV" "$op" "$C/sel" . ) > "$OUT" 2>&1
    RC=$?
}
want() { [ -z "${ONLY:-}" ] || [[ "$1" == *"$ONLY"* ]]; }
# Checks that rely on chmod (000 to make a file unreadable, 600 to keep a private file) cannot work
# for root, or on a file system that ignores chmod (NTFS and FAT mounts): skip them there.
needs_chmod() {
    local f="$T/.chmod-probe"
    if [ "$(id -u)" -ne 0 ]; then
        : > "$f"; chmod 000 "$f"
        if [ ! -r "$f" ]; then chmod 600 "$f"; rm -f "$f"; return 0; fi
        chmod 600 "$f"; rm -f "$f"
    fi
    printf '  SKIP  [%s] needs a non-root user on a file system that honors chmod\n' "$1"; return 1
}

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
    has_out "copy-mode4: compact plan line" 'proj: [0-9]+ to copy, [0-9]+ kept, [0-9]+ identical'
    has_out "copy-mode4: says why a file was kept" 'kept = same size, target not older'
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
    has_out "move-mode4: tells the user a file was kept" 'kept in the source: 1 file\(s\) of proj'
    has_out "move-mode4: names the kept file" 'proj/dn_same\.txt'
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
    needs_chmod errors || return 0
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
    new_case err-rename; mixed_fixture
    chmod 000 "$C/src/proj/sub/deep/n_dn.txt"
    run "$CPOP" '6\n' src/proj
    chmod 644 "$C/src/proj/sub/deep/n_dn.txt"
    check "err-rename: non-zero exit" "1" "$RC"
    has_out "err-rename: names the target that may be incomplete" "proj -> 'proj \(1\)'"
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

# ============ a directory in the source over a FILE in the target ============
# rsync would delete the target file without a word. cpmv must refuse instead.
clash_fixture() {
    put src/proj/x/f.txt "in-dir" $MID;  put dst/proj/x "TARGET FILE x" $MID      # directory over a file
    put src/proj/lnk/g.txt "g" $MID;     ln -s nowhere "$C/dst/proj/lnk"          # directory over a dangling link
    put src/proj/ok.txt "OK" $MID
}
g_nested_clash() {
    local mode
    for mode in 4 3 5; do
        new_case "clash-copy-$mode"; clash_fixture
        run "$CPOP" "$mode\\n" src/proj
        fc "the target FILE survives" dst/proj/x "TARGET FILE x" $MID
        check "$GROUP: the target link survives" "<link:nowhere>" "$(getc dst/proj/lnk)"
        check "$GROUP: nothing is copied for this item" "<missing>" "$(getc dst/proj/ok.txt)"
        check "$GROUP: exit 1" "1" "$RC"
        has_out "$GROUP: the clash is named" "'proj/x' would replace a file of a different type"
    done
    for mode in 4 3 2 1 5; do
        new_case "clash-move-$mode"; clash_fixture
        run "$MVOP" "$mode\\n" src/proj
        fc "the target FILE survives" dst/proj/x "TARGET FILE x" $MID
        fc "the source directory is intact" src/proj/x/f.txt "in-dir" $MID
        fc "the source file is intact" src/proj/ok.txt "OK" $MID
        check "$GROUP: exit 1" "1" "$RC"
    done
    for mode in 1 2; do          # cp refuses by itself; make sure nothing is lost and the failure shows
        new_case "clash-copy-$mode"; clash_fixture
        run "$CPOP" "$mode\\n" src/proj
        fc "the target FILE survives" dst/proj/x "TARGET FILE x" $MID
        check "$GROUP: exit 1" "1" "$RC"
    done
    new_case clash-file-over-dir                   # a source FILE over a non-empty target directory
    put src/proj/y "src-file" $NEW; put dst/proj/y/inner.txt "keep" $MID
    run "$CPOP" '4\n' src/proj
    fc "the inner file of the target directory survives" dst/proj/y/inner.txt "keep" $MID
    check "$GROUP: exit 1" "1" "$RC"
    new_case clash-none                            # control: directories on both sides merge normally
    put src/proj/x/f.txt "in-dir" $MID; put dst/proj/x/keep.txt "keep" $MID
    run "$CPOP" '4\n' src/proj
    fc "merge into an existing directory" dst/proj/x/f.txt "in-dir" $MID
    fc "and the existing file stays" dst/proj/x/keep.txt "keep" $MID
}

# ============ multi-item moves of plain FILES (mv -u / mvg -u) ================
g_move_files() {
    new_case move-files-mode2
    put src/new.txt "NEW-CONTENT" $NEW;  put dst/new.txt "old-content-x" $OLD     # source newer: moved
    put src/old.txt "OLD-CONTENT" $OLD;  put dst/old.txt "newer-content" $NEW     # target newer: kept, source stays
    run "$MVOP" '2\ny\n\n' src/new.txt src/old.txt
    fc "source newer file replaces the target" dst/new.txt "NEW-CONTENT" $NEW
    miss "and leaves the source" src/new.txt
    fc "target newer file is kept" dst/old.txt "newer-content" $NEW
    fc "and its source stays" src/old.txt "OLD-CONTENT" $OLD
    new_case move-files-mode1
    put src/a.txt "A-src" $OLD; put dst/a.txt "A-dst-newer" $NEW; put src/b.txt "B-src" $OLD; put dst/b.txt "B-dst-newer" $NEW
    run "$MVOP" '1\ny\n\n' src/a.txt src/b.txt
    fc "overwrite moves the first file" dst/a.txt "A-src" $OLD
    fc "apply to all moves the second file" dst/b.txt "B-src" $OLD
    miss "first source" src/a.txt; miss "second source" src/b.txt
}

g_dangling_link() {          # a dangling symlink in the target holds the name
    new_case dangling-rename
    put src/thing/f.txt "F" $MID; ln -s nowhere "$C/dst/thing"
    run "$CPOP" '6\n' src/thing
    fc "rename gets a free name next to the dangling link" "dst/thing (1)/f.txt" "F"
    check "$GROUP: the dangling link itself is untouched" "<link:nowhere>" "$(getc dst/thing)"
}

# ====================== Ctrl-C stops the whole run =============================
# Ctrl-C goes to the whole foreground group. rsync handles SIGINT itself and exits with status 20,
# so the plugin has to stop by itself instead of going on with the next selected item.
# The stand-in rsync below does what rsync does (exit 20 on SIGINT); dry runs use the real one.
fake_rsync() {
    local real; real=$(command -v rsync)
    mkdir -p "$C/shim" "$C/tmp"
    cat > "$C/shim/rsync" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "-n" ] && exec "$real" "\$@"; done
: > "$C/rsync.running"
trap 'exit 20' INT
sleep 30 & wait \$!
EOF
    chmod +x "$C/shim/rsync"
}
# start_group <stdin-file>: run cpmv in its OWN process group (job control), result in GPID
start_group() {
    set -m
    ( cd "$C/dst" && exec env TMPDIR="$C/tmp" PATH="$C/shim:$PATH" "$CPMV" "$MVOP" "$C/sel" . ) < "$1" > "$C/out" 2>&1 &
    GPID=$!
    set +m
    [ "$(ps -o pgid= -p "$GPID" 2>/dev/null | tr -d ' ')" = "$GPID" ] || bad "$GROUP: own process group" "could not create one"
}
await_gone() {                         # await_gone <pid>: whole-run ceiling 15 s
    local t0=$SECONDS
    while kill -0 "$1" 2>/dev/null && [ $((SECONDS - t0)) -lt 15 ]; do sleep 0.05; done
    kill -0 "$1" 2>/dev/null && { kill -KILL -- "-$1" 2>/dev/null; bad "$GROUP: plugin stopped after SIGINT" "still running after 15 s"; }
    wait "$1" 2>/dev/null; RC=$?
}
g_interrupt() {
    local t0
    new_case interrupt-transfer; two_dirs_and_file; fake_rsync
    printf '%s\0' "$C/src/A" "$C/src/B" "$C/src/c.txt" | head -c -1 > "$C/sel"
    printf '4\ny\n' > "$C/answers"
    start_group "$C/answers"
    t0=$SECONDS; while [ ! -e "$C/rsync.running" ] && [ $((SECONDS - t0)) -lt 10 ]; do sleep 0.05; done
    [ -e "$C/rsync.running" ] || bad "$GROUP: the transfer started" "the stand-in rsync never ran"
    kill -INT -- "-$GPID" 2>/dev/null
    OUT="$C/out"; await_gone "$GPID"
    check "$GROUP: exit status 130" "130" "$RC"
    has_out "$GROUP: says it was interrupted" 'interrupted'
    no_out  "$GROUP: no second item is started" 'comparing B'
    fc "second item is untouched" dst/B/y.txt "B-dst-longer" $NEW
    fc "second item stays in the source" src/B/y.txt "B-src" $OLD
    fc "the plain file is untouched" dst/c.txt "C-dst-longer" $NEW
    check "$GROUP: no temp directory is left" "0" "$(ls -A "$C/tmp" | wc -l | tr -d ' ')"

    new_case interrupt-prompt; two_dirs_and_file; fake_rsync
    printf '%s\0' "$C/src/A" "$C/src/B" | head -c -1 > "$C/sel"
    mkfifo "$C/in"; exec 9<>"$C/in"                           # a stdin that stays open: the plugin waits at the menu
    start_group "$C/in"
    t0=$SECONDS; while ! grep -q 'choose \[1-7\]' "$C/out" 2>/dev/null && [ $((SECONDS - t0)) -lt 10 ]; do sleep 0.05; done
    kill -INT -- "-$GPID" 2>/dev/null
    OUT="$C/out"; await_gone "$GPID"; exec 9>&-
    check "$GROUP: exit status 130 at a prompt" "130" "$RC"
    has_out "$GROUP: says it was interrupted" 'interrupted'
    fc "nothing was changed" dst/A/x.txt "A-dst-longer" $NEW
    check "$GROUP: no temp directory is left" "0" "$(ls -A "$C/tmp" | wc -l | tr -d ' ')"
}

# ===========================================================================
# Groups proposed by the mutation review of e2fcb93d.
# Inserted at the @@APPEND@@ marker of misc/test/test-cpmv.sh in a COPY; the group
# names are listed in NEWSUITE. They use the helpers of that script
# (new_case, put, run, fc, check, has_out, no_out, miss, mixed_fixture, two_dirs_and_file).
# ===========================================================================

# run_capped: like run, but a plugin that loops forever is stopped after 10 s and
# its output is capped at 200 kB, so a missing "|| choice=7" cannot fill the disk.
run_capped() {
    local op="$1" ans="$2" it; shift 2
    local abs=(); for it in "$@"; do abs+=("$C/$it"); done
    printf '%s\0' "${abs[@]}" | head -c -1 > "$C/sel"
    OUT="$C/out"
    ( cd "$C/dst" && printf '%b' "$ans" | timeout 10 "$CPMV" "$op" "$C/sel" . 2>&1 | head -c 200000 > "$OUT"
      exit "${PIPESTATUS[1]}" )
    RC=$?
}

# --- an item selected in the destination directory itself -----------------------
g_same_file() {
    local o
    for o in "$CPOP" "$MVOP"; do
        new_case "same-file-${o%% *}"
        put dst/f.txt "KEEP" $MID; put dst/proj/a.txt "AAA" $OLD; put dst/proj/sub/b.txt "BBB" $MID
        run "$o" '4\n4\n' dst/f.txt dst/proj
        has_out "same file is reported as skipped"      'skipped \(same file\) f\.txt'
        has_out "same directory is reported as skipped" 'skipped \(same file\) proj'
        no_out  "same file: no menu, no prompt"         'CONFLICT|\[y/N\]'
        fc "same file is untouched"      dst/f.txt        "KEEP" $MID
        fc "same directory is untouched" dst/proj/a.txt   "AAA"  $OLD
        fc "nested file is untouched"    dst/proj/sub/b.txt "BBB" $MID
        check "same-file-${o%% *}: exit status 0" "0" "$RC"
    done
}

# --- end of input at a menu must mean "skip", never an endless loop ---------------
g_eof_at_menu() {
    new_case eof-main-menu; mixed_fixture
    run_capped "$CPOP" '' src/proj
    check "eof-main-menu: the plugin ends by itself with status 0" "0" "$RC"
    fc "EOF at the menu skips: target untouched" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    new_case eof-clash-menu
    put src/thing "file" $NEW; mkdir -p "$C/dst/thing"
    run_capped "$CPOP" '' src/thing
    check "eof-clash-menu: the plugin ends by itself with status 0" "0" "$RC"
    check "eof-clash-menu: the directory is untouched" "yes" "$([ -d "$C/dst/thing" ] && echo yes || echo no)"
    new_case eof-apply-prompt; two_dirs_and_file
    run_capped "$CPOP" '4\n' src/A src/B
    check "eof-apply-prompt: ends with status 0" "0" "$RC"
    fc "first item got the typed mode 4"            dst/A/x.txt "A-src" $OLD
    fc "second item: EOF at its menu means skip"    dst/B/y.txt "B-dst-longer" $NEW
}

# --- the single-file y/N prompt: default is No, y/Y/yes/YES overwrite ------------
g_single_file_answers() {
    local i=0 ans
    for ans in '' '\n' 'maybe\n' 'nO\n'; do
        i=$((i + 1)); new_case "single-file-no-$i"
        put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
        run "$CPOP" "$ans" src/f.txt
        fc "answer [$ans] keeps the target (default is No)" dst/f.txt "old-longer" $OLD
        check "single-file-no-$i: exit status 0" "0" "$RC"
    done
    for ans in 'Y\n' 'yes\n' 'YES\n'; do
        i=$((i + 1)); new_case "single-file-yes-$i"
        put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
        run "$CPOP" "$ans" src/f.txt
        fc "answer [$ans] overwrites" dst/f.txt "new" $NEW
    done
}

# --- "apply to ALL" is offered only while items remain --------------------------
g_apply_prompt() {
    new_case apply-prompt-one; mixed_fixture
    run "$CPOP" '4\n' src/proj
    no_out "a single directory never asks 'apply to ALL'" 'apply to ALL'
    new_case apply-prompt-two; two_dirs_and_file
    run "$CPOP" '4\nn\n4\n\n' src/A src/B
    check "apply-prompt-two: asked once, not after the last item" "1" "$(grep -o 'apply to ALL' "$OUT" | wc -l)"
}

# --- rename: extension, dotfile, dotted directory, dangling link in the way -------
g_rename_names() {
    new_case rename-names
    put src/a.txt "S-a" $NEW;    put dst/a.txt "D-a" $OLD
    put src/.hid  "S-hid" $NEW;  put dst/.hid  "D-hid" $OLD
    put src/dir.v2/f "S-f" $NEW; put dst/dir.v2/f "D-f" $OLD
    put src/b.txt "S-b" $NEW;    put dst/b.txt "D-b" $OLD
    ln -s nowhere "$C/dst/b (1).txt"                       # a dangling link already holds the first free name
    run "$CPOP" '6\ny\n\n' src/a.txt src/.hid src/dir.v2 src/b.txt
    fc "a file keeps its extension: 'a (1).txt'"   "dst/a (1).txt" "S-a"
    fc "the original a.txt is untouched"           dst/a.txt "D-a" $OLD
    fc "a dotfile becomes '.hid (1)'"              "dst/.hid (1)" "S-hid"
    fc "a dotted directory becomes 'dir.v2 (1)'"   "dst/dir.v2 (1)/f" "S-f"
    fc "a dangling link name is skipped: 'b (2).txt'" "dst/b (2).txt" "S-b"
    check "rename-names: the dangling link is untouched" "<link:nowhere>" "$(getc 'dst/b (1).txt')"
    check "rename-names: exit status 0" "0" "$RC"
}

# --- dangling symbolic links ---------------------------------------------------
g_dangling_links() {
    local o
    for o in "$CPOP" "$MVOP"; do
        new_case "dangling-source-${o%% *}"
        ln -s nowhere "$C/src/lnk"
        run "$o" '' src/lnk
        fc "a dangling source link is transferred as a link" dst/lnk "<link:nowhere>"
        check "dangling-source-${o%% *}: exit status 0" "0" "$RC"
    done
    new_case dangling-source-mv-gone
    ln -s nowhere "$C/src/lnk"; run "$MVOP" '' src/lnk
    miss "moved dangling link" src/lnk
    new_case dangling-target
    put src/f.txt "SRC" $NEW; ln -s nowhere "$C/dst/f.txt"
    run "$CPOP" 'n\n' src/f.txt
    has_out "a dangling link at the target is a conflict: the prompt is shown" "overwrite 'f\.txt'\? \[y/N\]"
    check "dangling-target: answer n keeps the link" "<link:nowhere>" "$(getc dst/f.txt)"
    check "dangling-target: exit status 0" "0" "$RC"
}

# --- the plan summary and the kept notice, with exact numbers ---------------------
g_plan_summary() {
    new_case summary-copy4; mixed_fixture
    put src/proj/dn_same2.txt "SOLD2!" $OLD; put dst/proj/dn_same2.txt "DNEW2!" $NEW      # a second kept file
    run "$CPOP" '4\n' src/proj
    has_out "mode 4 copy summary" 'proj: 5 to copy, 2 kept, 1 identical'
    has_out "mode 4 says why a file is kept" 'kept = same size, target not older'
    new_case summary-move3; mixed_fixture
    put src/proj/dn_same2.txt "SOLD2!" $OLD; put dst/proj/dn_same2.txt "DNEW2!" $NEW
    run "$MVOP" '3\n' src/proj
    has_out "mode 3 move summary" 'proj: 4 to move, 3 kept, 1 identical'
    has_out "mode 3 says why a file is kept" 'kept = same size'
    has_out "the kept notice counts the files left behind" 'kept in the source: 3 file\(s\) of proj'
}

# --- the pause rule -----------------------------------------------------------
g_pause_rule() {
    new_case pause-move-kept; mixed_fixture
    run "$MVOP" '4\n' src/proj
    has_out "a move that leaves files behind pauses for review" 'Done\. Press enter'
    new_case pause-move-clean
    put src/a.txt "A" $MID
    run "$MVOP" '' src/a.txt
    no_out "no conflict and nothing left behind: no pause" 'Press enter'
    new_case pause-copy-one-dir; mixed_fixture
    run "$CPOP" '4\n' src/proj
    no_out "a single directory copy: no pause" 'Press enter'
}

# --- a plain file kept by a move: announced and left in the source -------------------
g_move_kept_file() {
    new_case move-kept-file
    put src/c.txt "SOLD!!" $OLD; put dst/c.txt "DNEWER" $NEW            # same size, target newer: mode 4 keeps it
    put src/d.txt "D-src"  $OLD; put dst/d.txt "D-dst-longer" $NEW
    run "$MVOP" '4\ny\n\n' src/c.txt src/d.txt
    fc "the kept plain file stays in the source" src/c.txt "SOLD!!" $OLD
    fc "the kept plain file leaves the target alone" dst/c.txt "DNEWER" $NEW
    has_out "the kept file is announced" 'kept in the source: 1 file\(s\) of c\.txt'
    miss "moved plain file source" src/d.txt
    fc "moved plain file arrived" dst/d.txt "D-src" $OLD
}

# --- mode 1 move merge must overwrite a file with equal size and equal mtime -------
g_move_mode1_same_time() {
    new_case move-mode1-sametime
    put src/proj/s.txt "AAAA" $MID; put dst/proj/s.txt "BBBB" $MID      # same size, same mtime, different content
    put src/proj/o.txt "ONE"  $OLD; put dst/proj/o.txt "TWO"  $OLD
    run "$MVOP" '1\n' src/proj
    fc "overwrite replaces a target with the same size and mtime" dst/proj/s.txt "AAAA" $MID
    fc "same for another pair"                                     dst/proj/o.txt "ONE"  $OLD
    miss "source after the overwriting move" src/proj
    check "move-mode1-sametime: exit status 0" "0" "$RC"
}

# --- mode 5 verifies the part that is already there -----------------------------------
g_resume_verify() {
    new_case resume-badprefix
    put src/proj/big.bin "0123456789ABCDEFGHIJ" $MID; put dst/proj/big.bin "XXXXXXXXXX" $MID   # short AND damaged
    run "$CPOP" '5\n' src/proj
    fc "resume notices a damaged partial file and repairs it" dst/proj/big.bin "0123456789ABCDEFGHIJ"
}

# --- the conflict header ---------------------------------------------------------
g_conflict_header() {
    new_case header-dir; mixed_fixture
    run "$CPOP" '7\n' src/proj
    has_out "a directory conflict says (directory)" 'source +: +\(directory\)'
    no_out  "a directory conflict shows no byte size" 'bytes'
    new_case header-files
    put src/a.txt "12345" $NEW; put dst/a.txt "123" $OLD; put src/b.txt "x" $NEW; put dst/b.txt "y" $OLD
    run "$CPOP" '7\nn\n7\n\n' src/a.txt src/b.txt
    has_out "a file conflict shows the source size" 'source +: +5 bytes'
    has_out "a file conflict shows the target size" 'target +: +3 bytes'
}

# --- the type-clash menu only offers rename and skip --------------------------------
g_clash_menu() {
    new_case clash-menu
    put src/thing "f" $NEW; mkdir -p "$C/dst/thing"
    run "$CPOP" '7\n' src/thing
    has_out "the clash is explained"                      'a file and a directory share this name'
    no_out  "the clash menu does not list impossible modes" '1\) overwrite|3\) different size|4\) different size|5\) resume'
}

# --- an invalid menu answer is refused and asked again ------------------------------
g_invalid_choice() {
    new_case invalid-choice; mixed_fixture
    run "$CPOP" '9\n0\nx\n\n4\n' src/proj
    check "four invalid answers, four refusals" "4" "$(grep -c 'invalid\.' "$OUT")"
    fc "the real choice (4) is applied afterwards" dst/proj/dn_diff.txt "AAAAA" $OLD
}

# --- a comparison that fails must be reported, not ignored ----------------------------
g_compare_fails() {
    needs_chmod compare_fails || return 0
    local o mode
    for o in "$CPOP" "$MVOP"; do for mode in 4 3; do
        new_case "compare-fails-${o%% *}-$mode"; mixed_fixture
        chmod 000 "$C/src/proj/sub"                      # rsync cannot list this directory
        run "$o" "$mode\\n" src/proj
        chmod 755 "$C/src/proj/sub"
        check "compare-fails-${o%% *}-$mode: non-zero exit" "1" "$RC"
        has_out "compare-fails-${o%% *}-$mode: the comparison failure is named" 'compare failed'
        fc "nothing is transferred after a failed comparison" dst/proj/dn_diff.txt "xxxxxxx" $NEW
        fc "the source is untouched" src/proj/dn_diff.txt "AAAAA" $OLD
    done; done
}

# a shim that makes only the second comparison (rsync -n --update) fail
g_compare_fails_second_run() {
    new_case compare-fails-d2; mixed_fixture
    mkdir -p "$C/bin"
    cat > "$C/bin/rsync" <<SHIM
#!/bin/sh
case " \$* " in *" --update "*) case " \$* " in *" -n "*) echo "rsync: injected failure" >&2; exit 23 ;; esac ;; esac
exec $(command -v rsync) "\$@"
SHIM
    chmod +x "$C/bin/rsync"
    PATH="$C/bin:$PATH" run "$CPOP" '4\n' src/proj
    check "second comparison fails: non-zero exit" "1" "$RC"
    has_out "second comparison fails: it is named, with the status of THAT run" 'compare failed \(rsync status 23\).*injected failure'
    fc "second comparison fails: nothing is copied" dst/proj/dn_diff.txt "xxxxxxx" $NEW
}

# --- rsync not installed ---------------------------------------------------------
g_no_rsync() {
    local t p o
    new_case no-rsync; mixed_fixture
    mkdir -p "$C/nobin"
    for t in bash env cat cp mv rm rmdir mkdir mktemp find basename dirname stat cut head tr wc grep sed timeout cpg mvg; do
        p=$(command -v "$t") && ln -s "$p" "$C/nobin/$t"
    done
    PATH="$C/nobin" run "$CPOP" '4\n' src/proj
    has_out "without rsync, mode 4 says so" 'rsync missing'
    check "without rsync: non-zero exit" "1" "$RC"
    fc "without rsync: nothing changed" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    new_case no-rsync-move; mixed_fixture
    mkdir -p "$C/nobin"
    for t in bash env cat cp mv rm rmdir mkdir mktemp find basename dirname stat cut head tr wc grep sed timeout cpg mvg; do
        p=$(command -v "$t") && ln -s "$p" "$C/nobin/$t"
    done
    PATH="$C/nobin" run "$MVOP" '1\n' src/proj
    has_out "without rsync, a directory move onto a directory says so" 'rsync missing'
    fc "without rsync: the source is untouched" src/proj/dn_diff.txt "AAAAA" $OLD
    fc "without rsync: the target is untouched" dst/proj/dn_diff.txt "xxxxxxx" $NEW
}

# --- the temp directory of the plugin is always removed -----------------------------
g_tmpdir_cleanup() {
    local mode root=0; needs_chmod tmpdir_failure_case || root=1
    for mode in 4 3 1; do
        new_case "tmpdir-$mode"; mixed_fixture; mkdir -p "$C/tmp"
        TMPDIR="$C/tmp" run "$CPOP" "$mode\\n" src/proj
        check "tmpdir-$mode: nothing is left in TMPDIR" "0" "$(find "$C/tmp" -mindepth 1 | wc -l)"
    done
    [ "$root" -eq 1 ] && return 0
    new_case tmpdir-failure; mixed_fixture; mkdir -p "$C/tmp"
    chmod 000 "$C/src/proj/sub/deep/n_dn.txt"
    TMPDIR="$C/tmp" run "$CPOP" '4\n' src/proj
    chmod 644 "$C/src/proj/sub/deep/n_dn.txt"
    check "tmpdir-failure: the run failed as intended" "1" "$RC"
    check "tmpdir-failure: nothing is left in TMPDIR after a failure" "0" "$(find "$C/tmp" -mindepth 1 | wc -l)"
}

# --- paths with spaces and quotes in the DESTINATION and in the source parent --------------
g_paths_with_spaces() {
    local o mode
    for o in "$CPOP" "$MVOP"; do for mode in 4 3 1 2; do
        new_case "sp ace's [dir] ${o%% *} $mode"; mixed_fixture
        run "$o" "$mode\\n" src/proj
        fc "size differs, dest newer: replaced (mode $mode)" dst/proj/do_diff.txt "DDDDDDDD" $MID
        check "spaces ${o%% *} $mode: exit status 0" "0" "$RC"
    done; done
}

# --- candidates: same size, only the time differs; awkward names -----------------------------
g_candidate_names() {
    local bad=$'bad\xffutf8.txt' n
    local snew=("a.txt" 'x[1].txt' 'x*.txt' 'sp ace.txt' 'back\slash.txt' $'nl\nname.txt' $'\xc3\xbcn\xc3\xaf.txt' "$bad")
    local tnew=("a.txt.bak" 'aXtxt' 'x1.txt' 'sub/proj/a.txt' 'xyz.txt')
    new_case candidate-names
    for n in "${snew[@]}"; do put "src/proj/$n" "SRC1" $NEW; put "dst/proj/$n" "dst1" $OLD; done
    for n in "${tnew[@]}"; do put "src/proj/$n" "srcK" $OLD; put "dst/proj/$n" "dstK" $NEW; done
    [ -e "$C/src/proj/$bad" ] || snew=("${snew[@]:0:7}")                  # the file system refuses that name
    LC_ALL=C.UTF-8 run "$CPOP" '4\n' src/proj
    for n in "${snew[@]}"; do fc "source newer is copied: $n" "dst/proj/$n" "SRC1" $NEW; done
    for n in "${tnew[@]}"; do fc "target newer is kept: $n"   "dst/proj/$n" "dstK" $NEW; done
    new_case candidate-names-3
    for n in "${snew[@]}"; do put "src/proj/$n" "SRC1" $NEW; put "dst/proj/$n" "dst1" $OLD; done
    LC_ALL=C.UTF-8 run "$CPOP" '3\n' src/proj
    for n in "${snew[@]}"; do fc "mode 3 leaves a same-size file alone: $n" "dst/proj/$n" "dst1" $OLD; done
}

# --- moving symbolic links: identical ones must not stay behind -------------------------
g_move_symlinks() {
    local mode
    for mode in 4 3; do
        new_case "move-symlinks-$mode"
        put src/proj/real.txt "REAL" $MID; put dst/proj/real.txt "REAL" $MID
        ln -s real.txt "$C/src/proj/same_lnk"; ln -s real.txt "$C/dst/proj/same_lnk"    # identical link on both sides
        ln -s real.txt "$C/src/proj/new_lnk"                                            # link only in the source
        run "$MVOP" "$mode\\n" src/proj
        fc "a new link arrives as a link" dst/proj/new_lnk "<link:real.txt>"
        fc "an identical link stays a link" dst/proj/same_lnk "<link:real.txt>"
        miss "identical link in the source" src/proj/same_lnk
        miss "moved link in the source" src/proj/new_lnk
        miss "whole source tree" src/proj
        check "move-symlinks-$mode: exit status 0" "0" "$RC"
        no_out "move-symlinks-$mode: nothing reported as left behind" 'kept in the source'
    done
}

# --- names that rsync escapes more than once (\#ooo twice or more) ------------------------------
g_names_multi_escape() {
    local names=($'two\nnew\nlines.txt' $'tab\there\nand\nnewline.txt' 'a\#012b\#012c.txt') n mode
    for mode in 4 3; do
        new_case "names-multi-escape-$mode"
        for n in "${names[@]}"; do put "src/proj/$n" "src" $OLD; put "dst/proj/$n" "dest-longer" $NEW; done
        run "$CPOP" "$mode\\n" src/proj
        for n in "${names[@]}"; do fc "$n" "dst/proj/$n" "src" $OLD; done
        check "names-multi-escape-$mode: exit status 0" "0" "$RC"
    done
}

# --- a directory move onto a symbolic link that points to a directory ----------------------
g_move_dirlink() {
    local mode
    for mode in 1 4; do
        new_case "move-dirlink-$mode"
        put src/proj/f.txt "SRC" $OLD; put dst/realdir/f.txt "dest-longer" $NEW; ln -s realdir "$C/dst/proj"
        run "$MVOP" "$mode\\n" src/proj
        fc "move mode $mode: the linked target directory is merged INTO" dst/realdir/f.txt "SRC" $OLD
        check "move-dirlink-$mode: the target symlink is kept" "yes" "$([ -L "$C/dst/proj" ] && echo yes || echo no)"
        miss "source after the move" src/proj
    done
}

# --- a COPY never changes the source tree (whole-tree snapshot, every mode) --------------
snap() { ( cd "$C/$1" && find . -printf '%p %y %s %T@ %l\n' | sort; find . -type f -exec md5sum {} + | sort ); }
g_copy_source_untouched() {
    local mode before after
    for mode in 1 2 3 4 5 6 7; do
        new_case "copy-src-untouched-$mode"; mixed_fixture
        before=$(snap src)
        run "$CPOP" "$mode\\n" src/proj
        after=$(snap src)
        check "copy mode $mode: the source tree is unchanged (names, types, sizes, mtimes, content)" "$before" "$after"
    done
}


# ===========================================================================
# Groups for the findings of the correctness review (C1 to C12), commit e2fcb93d.
# ===========================================================================

# --- C1: a type change that would delete a regular file of the target is refused -----------
# rsync turns a directory or a link over a regular file into "new item" and deletes the file.
g_type_change_guard() {
    local o mode modes
    for o in "$CPOP" "$MVOP"; do
        if [ "${o%% *}" = cp ] || [ "${o%% *}" = cpg ]; then modes="2 3 4 5"; else modes="1 2 3 4 5"; fi
        for mode in $modes; do
            new_case "typechange-${o%% *}-$mode"
            put src/proj/x/inner.txt "IN" $OLD;   put dst/proj/x "PRECIOUS-X" $NEW         # directory over a file
            ln -s elsewhere "$C/src/proj/l";      put dst/proj/l "PRECIOUS-L" $NEW         # symlink over a file
            put src/proj/ok.txt "OK" $MID
            run "$o" "$mode\\n" src/proj
            fc "directory over a file: the file survives" dst/proj/x "PRECIOUS-X" $NEW
            fc "symlink over a file: the file survives"   dst/proj/l "PRECIOUS-L" $NEW
            check "$GROUP: nothing else was copied" "<missing>" "$(getc dst/proj/ok.txt)"
            check "$GROUP: exit 1" "1" "$RC"
            has_out "$GROUP: both clashes are named" "would replace a file of a different type"
            [ "${o%% *}" = mv ] || [ "${o%% *}" = mvg ] && fc "$GROUP: the source stays" src/proj/ok.txt "OK" $MID
        done
    done
    # not destructive, so allowed: a directory over a link, a file over an empty directory
    new_case typechange-allowed
    put src/proj/d/f.txt "DIRFILE" $MID
    mkdir -p "$C/dst/proj"; ln -s nowhere "$C/dst/proj/d"                                  # dangling link where a directory comes
    put src/proj/e "FILE-OVER-EMPTYDIR" $MID; mkdir -p "$C/dst/proj/e"                      # empty directory where a file comes
    put src/proj/keep.txt "K" $MID
    run "$CPOP" '4\n' src/proj
    fc "a directory replaces a dangling link" dst/proj/d/f.txt "DIRFILE" $MID
    fc "a file replaces an empty directory"   dst/proj/e "FILE-OVER-EMPTYDIR" $MID
    check "typechange-allowed: exit 0" "0" "$RC"
}

# --- C2: mode 2 is "newer only": equal time with another size is NOT newer ---------------
g_mode2_newer_only() {
    local o
    for o in "$CPOP" "$MVOP"; do
        new_case "newer-only-${o%% *}"
        put src/proj/f.txt "SRC-LONGER-CONTENT" $MID; put dst/proj/f.txt "DST" $MID       # same second, other size: keep
        put src/proj/n.txt "NEW-LONGER" $NEW;         put dst/proj/n.txt "old" $OLD       # source newer: replace
        put src/proj/o.txt "OLD" $OLD;                put dst/proj/o.txt "NEWER-LONGER" $NEW   # target newer: keep
        run "$o" '2\n' src/proj
        fc "equal time, other size: kept" dst/proj/f.txt "DST" $MID
        fc "source newer: replaced"       dst/proj/n.txt "NEW-LONGER" $NEW
        fc "target newer: kept"           dst/proj/o.txt "NEWER-LONGER" $NEW
        check "$GROUP: exit 0" "0" "$RC"
        if [ "${o%% *}" = mv ] || [ "${o%% *}" = mvg ]; then
            fc "the kept sources stay" src/proj/f.txt "SRC-LONGER-CONTENT" $MID
            fc "also the one that is older" src/proj/o.txt "OLD" $OLD
            miss "the moved source" src/proj/n.txt
        fi
    done
    new_case newer-only-readonly        # no tty prompt from mv -u, a read-only older target is replaced
    put src/a.txt "A-NEW" $NEW; put dst/a.txt "a-old" $OLD; chmod 444 "$C/dst/a.txt"
    put src/b.txt "B-NEW" $NEW; put dst/b.txt "b-old" $OLD
    run "$MVOP" '2\ny\n\n' src/a.txt src/b.txt
    fc "a read-only older target is replaced" dst/a.txt "A-NEW" $NEW
    fc "'apply to ALL' got its own answer"    dst/b.txt "B-NEW" $NEW
    no_out "no prompt from mv" 'overriding mode|replace .*\?'
    no_out "no invalid answer" 'invalid'
    new_case newer-only-subsecond       # one rule everywhere: whole seconds, as rsync compares them
    put src/proj/f "SRC---" $MID; touch -d "@$MID.5" "$C/src/proj/f"; put dst/proj/f "DST---" $MID
    run "$CPOP" '2\n' src/proj;  fc "mode 2: half a second newer is not newer" dst/proj/f "DST---" $MID
    run "$CPOP" '4\n' src/proj;  fc "mode 4: the same"                          dst/proj/f "DST---" $MID
}

# --- C3 and C5: a MOVE deletes a source file only when its bytes are proven identical ----------
g_move_verify() {
    local mode
    for mode in 2 3 4 5; do
        new_case "move-verify-$mode"
        put src/proj/f.txt "AAAAAA" $MID;   put dst/proj/f.txt "BBBBBB" $MID                # same size, same second, other bytes
        put src/proj/same.txt "SAME" $MID;  put dst/proj/same.txt "SAME" $MID               # really identical
        put src/proj/sub/g.txt "CCCC" $MID; put dst/proj/sub/g.txt "DDDD" $MID              # the same, nested
        ln -s real "$C/src/proj/lnk"; ln -s real "$C/dst/proj/lnk"                           # identical links
        run "$MVOP" "$mode\\n" src/proj
        fc "different bytes: the target is untouched"   dst/proj/f.txt "BBBBBB" $MID
        fc "different bytes: the SOURCE stays (no loss)" src/proj/f.txt "AAAAAA" $MID
        fc "nested: the target is untouched"            dst/proj/sub/g.txt "DDDD" $MID
        fc "nested: the SOURCE stays"                   src/proj/sub/g.txt "CCCC" $MID
        miss "a verified identical source" src/proj/same.txt
        miss "an identical link in the source" src/proj/lnk
        has_out "$GROUP: the user is told" 'other content'
        has_out "$GROUP: the files are reported as kept" 'kept in the source: 2 file\(s\) of proj'
        check "$GROUP: exit 0" "0" "$RC"
    done
    needs_chmod move_verify_permissions || return 0
    for mode in 2 3 4; do               # permissions of a kept, identical target are not touched
        new_case "move-perms-$mode"
        put src/proj/same.txt "SAME" $MID; chmod 644 "$C/src/proj/same.txt"
        put dst/proj/same.txt "SAME" $MID; chmod 600 "$C/dst/proj/same.txt"
        run "$MVOP" "$mode\\n" src/proj
        check "$GROUP: the target keeps its permissions" "600" "$(stat -c %a "$C/dst/proj/same.txt")"
        miss "the identical source" src/proj
    done
}

# --- C4: a folder cannot be copied or moved into itself -----------------------------------
g_into_itself() {
    local o mode
    for o in "$CPOP" "$MVOP"; do for mode in 1 3 4 5; do
        new_case "into-itself-${o%% *}-$mode"
        put dst/proj/a.txt "AAAA" $MID; put dst/proj/sub/proj/a.txt "OLD" $OLD       # the destination dst/proj/sub already holds a proj
        DEST=dst/proj/sub run "$o" "$mode\\n" dst/proj
        check "$GROUP: exit 1" "1" "$RC"
        has_out "$GROUP: says why" 'into itself'
        fc "nothing was changed" dst/proj/sub/proj/a.txt "OLD" $OLD
        fc "the folder is intact" dst/proj/a.txt "AAAA" $MID
        check "$GROUP: no tree inside the tree" "<missing>" "$(getc dst/proj/sub/proj/sub)"
    done; done
}

# --- C7: sparse files stay sparse (cp does that by itself; rsync needs -S) -------------------
g_sparse() {
    local spec kb n=0
    for spec in "$CPOP:4" "$CPOP:3" "$CPOP:2" "$CPOP:5" "$MVOP:1" "$MVOP:4" "$MVOP:5"; do
        n=$((n + 1)); new_case "sparse-$n"
        mkdir -p "$C/src/proj"; truncate -s 40M "$C/src/proj/sparse.bin"; put dst/proj/other.txt "o" $OLD
        run "${spec%:*}" "${spec##*:}\\n" src/proj
        kb=$(du -k "$C/dst/proj/sparse.bin" 2>/dev/null | cut -f1)
        check "$GROUP: ${spec%% *} mode ${spec##*:}: the sparse file arrived sparse (allocated KB < 1024)" "yes" "$([ "${kb:-99999}" -lt 1024 ] && echo yes || echo "no ($kb KB)")"
        check "$GROUP: and at full size" "41943040" "$(stat -c %s "$C/dst/proj/sparse.bin" 2>/dev/null)"
    done
}

# --- C8: a name that ends in a newline is still a conflict ---------------------------------
g_newline_end_name() {
    local N c
    N=$(printf 'nl\n_'); N=${N%_}
    new_case newline-end
    printf 'NEW-LONGER' > "$C/src/$N"; printf 'old' > "$C/dst/$N"; : > "$C/src/zz"
    run "$CPOP" '7\n7\n\n' "src/$N" src/zz
    c=$(cat "$C/dst/$N"; echo x)
    check "the conflict menu was shown and skip kept the target" "old" "${c%x}"
    has_out "$GROUP: a menu was shown" 'CONFLICT'
}

# --- C9: a folder and a file inside it selected together ----------------------------------
g_dir_and_child() {
    new_case dir-then-child
    put src/proj/sub/x.txt "XX" $MID; put src/proj/y.txt "YY" $MID
    run "$MVOP" '' src/proj src/proj/sub/x.txt
    check "folder first: exit 0, no false 'not found'" "0" "$RC"
    no_out "folder first: no 'not found'" 'not found'
    has_out "folder first: the child is reported as moved with its folder" 'already moved with its folder'
    miss "everything left the source" src/proj
    fc "the child arrived inside the folder" dst/proj/sub/x.txt "XX" $MID
    new_case child-then-dir
    put src/proj/sub/x.txt "XX" $MID; put src/proj/y.txt "YY" $MID
    run "$MVOP" '' src/proj/sub/x.txt src/proj
    check "child first: exit 0" "0" "$RC"
    fc "the child went to the destination itself" dst/x.txt "XX" $MID
    fc "the folder arrived without it" dst/proj/y.txt "YY" $MID
    miss "the folder in the source" src/proj
}

# --- existing links: modes 3 and 4 bring them up to date, mode 2 ("newer only") only creates missing ones
g_link_policy() {
    local mode
    for mode in 2 3 4; do
        new_case "link-policy-$mode"
        put src/proj/f.txt "F" $MID; put dst/proj/f.txt "F" $MID
        ln -s newtarget "$C/src/proj/lnk"; ln -s oldtarget "$C/dst/proj/lnk"          # a link whose target differs
        ln -s created "$C/src/proj/fresh"                                             # a link that is missing
        run "$CPOP" "$mode\\n" src/proj
        fc "a missing link is created" dst/proj/fresh "<link:created>"
        if [ "$mode" = 2 ]; then fc "mode 2 keeps an existing link" dst/proj/lnk "<link:oldtarget>"
        else fc "mode $mode brings an existing link up to date" dst/proj/lnk "<link:newtarget>"; fi
        check "$GROUP: exit 0" "0" "$RC"
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
       g_single_file_prompt g_apply_to_all g_errors g_type_mismatch g_names g_symlinks g_oracle g_nested_clash g_move_files g_dangling_link g_interrupt
       g_same_file g_eof_at_menu g_single_file_answers g_apply_prompt g_rename_names g_dangling_links
       g_plan_summary g_pause_rule g_move_kept_file g_move_mode1_same_time g_resume_verify g_conflict_header
       g_clash_menu g_invalid_choice g_compare_fails g_compare_fails_second_run g_no_rsync g_tmpdir_cleanup
       g_paths_with_spaces g_candidate_names g_move_symlinks g_names_multi_escape g_move_dirlink g_copy_source_untouched
       g_type_change_guard g_mode2_newer_only g_move_verify g_into_itself g_sparse g_newline_end_name g_dir_and_child
       g_link_policy)

if [ "${1:-}" = "--list" ]; then printf '%s\n' "${SUITE[@]}"; exit 0; fi
printf 'cpmv under test: %s\n' "$CPMV"
CPOP="cp -iRp --"; MVOP="mv -i --"
echo "--- ops: $CPOP / $MVOP"; run_suite "${SUITE[@]}"
if command -v cpg >/dev/null 2>&1 && command -v mvg >/dev/null 2>&1; then
    CPOP="cpg -giRp --"; MVOP="mvg -gi --"
    echo "--- ops: $CPOP / $MVOP"; run_suite "${SUITE[@]}"
else
    echo "--- SKIP: cpg/mvg (advcpmv) are not installed, the advcpmv pass is not run"
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
