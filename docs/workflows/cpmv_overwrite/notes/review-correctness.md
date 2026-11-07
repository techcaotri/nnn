# correctness: review of e2fcb93d

## Purpose

Adversarial correctness review of `plugins/cpmv` at commit `e2fcb93d` (the fix for menu mode
`4) different size or newer`). Lens: data loss, wrong overwrite or wrong "kept" decision against the
mode table in the script header, hidden failure, side effects on files a mode promises not to touch.

Environment (Fact): bash 5.2.37, rsync 3.2.7, GNU coreutils `cp`/`mv` 8.32, advcpmv `cpg`/`mvg`
(coreutils 9.3 based, `/usr/local/bin`), GNU find 4.8.0, bfs 4.1.1 (through a wrapper), uid 1000
(not root), ext4 under `/tmp`, locale `en_US.utf8`. Every reproducer calls the plugin the way nnn
does: NUL-separated selection file without trailing NUL, `cd` into the destination, argument `.`.

## Verdict

The fix does what the commit says for the reported bug: mode 4 now replaces a target of different
size even when the target is newer, and a 15-case size/time matrix (mode 1 to 4, copy and move,
nested and top-level, plain, advcpmv and bfs variants, 900 checks) decides correctly everywhere
except in two places listed below. The plan parser survived every awkward name I could build. But the
commit's central safety claim, "a move removes only what reached the target", is not true, and three
HIGH problems remain: (C1) a nested directory-versus-file name clash makes rsync delete the target
file silently, now also for `v` modes 1 and 2 on a directory; (C2) mode 2 on a directory move uses
`rsync --update`, which is not "newer only"; (C3) a move deletes a source file whose size and
mtime match the target's but whose content differs. Must change before the fix is called safe:
C1, C2, C3. Should change: C4, C5. The LOW items are cosmetic, rare, or pre-existing.

## Findings

| id | severity | file:line | summary | status |
|---|---|---|---|---|
| C1 | HIGH | `plugins/cpmv:186,246-247,258,300-301` (guard only at `:350-365`) | A nested directory that meets a FILE of the same name at the target replaces (destroys) that file, rc 0, no message. Modes 3/4/5 copy and move, and `v` modes 1/2 on a directory. | CONFIRMED |
| C2 | HIGH | `plugins/cpmv:292`, `:258` | Mode 2 on a directory move runs `rsync --update`: equal mtime with different size is replaced; an older symlink/fifo replaces a newer regular file. Copy (`cp -u`) keeps both. | CONFIRMED |
| C3 | HIGH | `plugins/cpmv:184,189,246-247,258,300-301` | A move deletes the source file when size and mtime (whole seconds) match but the content differs. Modes 3, 4, 5 and mode 2 on a directory. | CONFIRMED |
| C4 | MEDIUM | `plugins/cpmv:333-348` | No "destination inside the source" guard on the rsync paths. cp/mv refuse (rc 1); modes 3/4 copy the tree into itself with rc 0; mode 5 move can leave a mixed-content file (`OLDA`). | CONFIRMED |
| C5 | MEDIUM | `plugins/cpmv:184,189,246-247,300-301` | Move (and mode 5 copy) syncs permission bits onto a kept, identical target file (600 becomes 644). Header promises kept files are never touched. | CONFIRMED |
| C6 | LOW | `plugins/cpmv:82-84,288,294` | Commit message says a symlinked target directory is merged into "like cp does". `cp -R` refuses it (rc 1); only the rsync paths merge. | CONFIRMED |
| C7 | LOW | `plugins/cpmv:84` | rsync paths inflate sparse files and drop xattrs/ACLs; `cp`/`mv` keep sparseness (and `mv` keeps xattrs). | CONFIRMED |
| C8 | LOW | `plugins/cpmv:335` | A selected name that ends in a newline is overwritten with no conflict menu (`$(basename)` strips the newline). Pre-existing. | CONFIRMED |
| C9 | LOW | `plugins/cpmv:337-340` | Selecting a directory and a file inside it, then moving: everything moves, but the plugin exits 1 with "not found". | CONFIRMED |
| C10 | LOW | `plugins/cpmv:292-295` | Mode 2 on files: `mv -u` prompts on the tty and eats an answer; kept files are not reported; `cp -u` cannot replace a 444 target. | CONFIRMED |
| C11 | LOW | `plugins/cpmv:288,294` | `cp` modes 1/2 write THROUGH a symlink in the target (changes the file outside the tree); rsync modes and `mv` replace the link. Pre-existing. | CONFIRMED |
| C12 | LOW | `plugins/cpmv:199,292-295` | Source newer by less than one second: `cp -u` (mode 2 copy) replaces, rsync paths keep. | CONFIRMED |
| N1 | - | `plugins/cpmv:246-247` | A source file that is appended to, replaced or deleted during the real transfer (slowed rsync, change one second in) loses data. The gap between the dry run and the transfer was not simulated on its own (rsync re-checks every file at transfer time). | NOT REPRODUCED |
| N2 | - | `plugins/cpmv:156-217` | Plan parser misreads a name (44 awkward names, 3 locales). | NOT REPRODUCED |
| N3 | - | `plugins/cpmv:221-232` | `finish_move` prunes wrongly or differs between GNU find and bfs. | NOT REPRODUCED |
| N4 | - | `plugins/cpmv:356-362,381-385,408` | A stdin read that loops forever at EOF; exit 0 after a failure; EXIT trap leaking its status. | NOT REPRODUCED |
| N5 | - | `plugins/cpmv:109` | Temp directory left behind on SIGINT, SIGTERM, SIGHUP at a prompt. | NOT REPRODUCED |
| N6 | - | `plugins/cpmv:246-247` | A move loses a symlink, dangling link, fifo, socket, hard link, empty file or empty directory. | NOT REPRODUCED |
| N7 | - | `plugins/cpmv:288-301` | Read-only target file, read-only target directory or read-only source directory fails silently. | NOT REPRODUCED |

## Details

### Common helpers used by every reproducer

```bash
P=/home/tripham/Dev/Playground_Terminal/nnn/plugins/cpmv
mk()  { T=$(mktemp -d /tmp/cpmv-review-XXXXXX); mkdir -p "$T/src" "$T/dst"; }
put() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; touch -d "@$3" "$1"; }   # put FILE CONTENT EPOCH
run() { local op=$1 ans=$2; shift 2; printf '%s\0' "$@" | head -c -1 > "$T/sel"; (cd "$T/dst" && printf "$ans" | "$P" "$op" "$T/sel" . >"$T/out" 2>&1); RC=$?; }   # run OP ANSWERS ITEM...
```

Each reproducer below deletes its own `$T` (`rm -rf "$T"`). For the regression notes I saved
`git show e2fcb93d~1:plugins/cpmv` to a scratch file and ran the same blocks with `P` pointing at it.

### C1 (HIGH, CONFIRMED): nested file-versus-directory clash destroys the target file

Where: the clash guard at `plugins/cpmv:350-365` checks only the selected item itself. Inside a
tree the plan keeps a source directory whose target name is a file (`:186`) and the real rsync runs
(`:246-247`, `:258`, `:300-301`) delete the file to make room for the directory. rsync does this
without `--delete`.

Fact: the commit message says "a file and a directory with the same name only offer rename or
skip". That is true only for the top-level item.

```bash
for op in 'cp -iRp --' 'mv -i --'; do for mode in 1 2 3 4 5; do
  mk; put "$T/src/proj/x/inner.txt" IN 1700000000; put "$T/dst/proj/x" PRECIOUS 1800000000
  run "$op" "$mode\n\n" "$T/src/proj"
  if [ -d "$T/dst/proj/x" ]; then s="DIRECTORY, the file is destroyed"; else s="still a file ($(cat "$T/dst/proj/x"))"; fi
  echo "$op mode $mode rc=$RC: dst/proj/x is $s"; rm -rf "$T"
done; done
```

Expected: `dst/proj/x` stays the newer file (or the plugin asks or refuses). Actual (same with plain
`cp`/`mv` and with advcpmv `cpg`/`mvg` in `PATH`):

| op | mode 1 | mode 2 | mode 3 | mode 4 | mode 5 |
|---|---|---|---|---|---|
| `cp` | file kept, rc 1 | file kept, rc 1 | DESTROYED, rc 0 | DESTROYED, rc 0 | DESTROYED, rc 0 |
| `mv` | DESTROYED, rc 0 | DESTROYED, rc 0 | DESTROYED, rc 0 | DESTROYED, rc 0 | DESTROYED, rc 0 |

Regression (Fact, ran the original plugin with the same block): original `cp` modes 3/4/5 and `mv`
modes 3/4/5 destroyed the file too (pre-existing). Original `mv` modes 1/2 kept the file (the old
`mv` failed), so the `v` mode 1/2 rows are new in `e2fcb93d`.

Related (Fact): with rsync a source symlink or fifo also replaces a target regular file (see C2 for
mode 2). For the reverse (source file over a NON-EMPTY target directory) rsync refuses with status
23, which is visible, but only after earlier files were already transferred in modes 5 and `v`
1/2 (modes 3/4 fail in the dry run before changing anything). An EMPTY target directory in the way
is deleted silently (harmless).

Direction (Not verified): before any rsync run, walk the planned names; if `$dest/$name` exists and
its directory-ness differs from the source's, call `note_err` and skip that item.

### C2 (HIGH, CONFIRMED): mode 2 on a directory move is not "newer only"

Where: `plugins/cpmv:292` (`move_merge "$src" --update`), executed at `:258`. The header table says
"2 newer only: replace when the source is newer (size is ignored)".

Fact: `rsync --update` skips only a target that is newer. With an equal mtime it still sends the
file when the sizes differ, and it replaces a target regular file by a source symlink or fifo
whatever the times. `cp -u` (the copy path) keeps the target in both cases (output below). For
`mv -u` on single files the equal-mtime case is covered by block `M` (form B keeps the target); the
symlink case was not run for `mv -u` (Not verified).

```bash
for op in 'cp -iRp --' 'mv -i --'; do
  mk
  put "$T/src/proj/f.txt" SRC-LONGER-CONTENT 1750000000     # same mtime as the target, different size
  put "$T/dst/proj/f.txt" DST 1750000000
  ln -s /etc/hostname "$T/src/proj/lnk"; touch -h -d @1700000000 "$T/src/proj/lnk"   # OLD symlink
  put "$T/dst/proj/lnk" LOCAL-NEWER-REGULAR-FILE 1800000000                           # NEWER regular file
  run "$op" '2\n\n' "$T/src/proj"
  echo "$op mode 2 rc=$RC: f.txt=$(cat "$T/dst/proj/f.txt") ; lnk is $([ -L "$T/dst/proj/lnk" ] && echo SYMLINK || echo 'the regular file')"
  rm -rf "$T"
done
```

Expected: both lines `f.txt=DST` and `the regular file`. Actual:

```text
cp -iRp -- mode 2 rc=0: f.txt=DST ; lnk is the regular file
mv -i -- mode 2 rc=0: f.txt=SRC-LONGER-CONTENT ; lnk is SYMLINK
```

The 15-case matrix (block `M` in "What I checked") finds the same: `f_eq_small` and `f_eq_big`
(equal mtime, target smaller or bigger) are replaced by `v` mode 2 on a directory, form A only.

Regression (Fact, ran the original): original `mv` mode 2 on a directory failed with "Directory
not empty" and changed nothing, so this wrong overwrite is new in `e2fcb93d`.

Likelihood: needs an equal mtime to the second AND different sizes, or a type change. Low, but the
result is a wrong overwrite of the target.

Direction (Not verified): treat mode 2 like mode 4: plan with the D1/D2 dry runs and copy only the
files whose mtime differs and whose source is newer, plus missing ones, through `--files-from`.

### C3 (HIGH, CONFIRMED): a move deletes a source whose content differs from the target

Where: identical items are added to the move list at `plugins/cpmv:184` (regular files) and `:189`
(links and specials); the real run removes them (`:246-247`). Mode 5 does the same at `:300-301` and
the directory merge at `:258`.

Fact: rsync's quick check is size plus mtime in whole seconds. Two files of the same size written
within the same second look identical. The header says a move removes "only what reached the target
(or was already there, identical)"; here "identical" is only quick-check identical.

```bash
for mode in 2 3 4 5; do
  mk; put "$T/src/proj/f.txt" AAAAAA 1750000000; put "$T/dst/proj/f.txt" BBBBBB 1750000000
  run 'mv -i --' "$mode\n\n" "$T/src/proj"
  echo "mv mode $mode rc=$RC: dst/proj/f.txt=$(cat "$T/dst/proj/f.txt") ; src/proj/f.txt=$(cat "$T/src/proj/f.txt" 2>/dev/null || echo '<gone>')"; rm -rf "$T"
done
```

Expected: either the source `AAAAAA` stays (and is reported as kept) or the target holds it. Actual:
all four lines show `dst/proj/f.txt=BBBBBB ; src/proj/f.txt=<gone>`, so `AAAAAA` is lost.

Realistic variant, no `touch` (two files written in the same second). Actual: 6 of 6 runs lose the
source.

```bash
lost=0; for i in 1 2 3 4 5 6; do
  mk; mkdir -p "$T/src/proj" "$T/dst/proj"
  printf 'AAAAAA' > "$T/src/proj/f.txt"; printf 'BBBBBB' > "$T/dst/proj/f.txt"
  run 'mv -i --' '4\n\n' "$T/src/proj"
  [ ! -e "$T/src/proj/f.txt" ] && [ "$(cat "$T/dst/proj/f.txt")" = BBBBBB ] && lost=$((lost+1)); rm -rf "$T"
done; echo "AAAAAA lost in $lost of 6 runs"
```

Regression (Fact, ran the original): original modes 3/4/5 also deleted the source (`rm_src`); original
mode 2 on a directory failed safely. So modes 3/4/5 are pre-existing, mode 2 on a directory is new,
and all of them contradict the new move guarantee.

Direction (Not verified): in a move, verify each quick-check-identical file with `cmp -s` before it
goes into the list; on a mismatch count it as kept (stays in the source, reported). Removing those
sources with `rm` after `cmp` instead of through rsync would also fix C5.

### C4 (MEDIUM, CONFIRMED): destination inside the source is not refused on the rsync paths

Where: the main loop `plugins/cpmv:333-348` has no guard; the rsync runs are at `:166`, `:246`,
`:258`, `:300`. User flow: select `proj`, enter `proj/sub`, press `p` or `v`, while `proj/sub/proj`
already exists (a conflict). Without that nested name there is no conflict and `cp`/`mv` refuse.

```bash
for mode in 1 3 4; do
  mk; put "$T/src/proj/a.txt" AAAA 1750000000; put "$T/src/proj/sub/proj/a.txt" OLD 1700000000
  printf '%s' "$T/src/proj" > "$T/sel"; (cd "$T/src/proj/sub" && printf "$mode\n\n" | "$P" 'cp -iRp --' "$T/sel" . >"$T/out" 2>&1); RC=$?
  echo "cp mode $mode rc=$RC: nested copy proj/sub/proj/sub/proj/a.txt exists: $([ -e "$T/src/proj/sub/proj/sub/proj/a.txt" ] && echo YES || echo no)"; rm -rf "$T"
done
n=0; for i in 1 2 3 4 5 6 7 8 9 10; do
  mk; put "$T/src/proj/a.txt" AAAA 1750000000; put "$T/src/proj/sub/proj/a.txt" OLD 1700000000
  printf '%s' "$T/src/proj" > "$T/sel"; (cd "$T/src/proj/sub" && printf '5\n\n' | "$P" 'mv -i --' "$T/sel" . >"$T/out" 2>&1)
  [ "$(cat "$T/src/proj/sub/proj/sub/proj/a.txt" 2>/dev/null)" = OLDA ] && n=$((n+1)); rm -rf "$T"
done; echo "mv mode 5: in $n of 10 runs a file ended as OLDA (neither OLD nor AAAA)"
```

Actual: `cp` mode 1 rc=1 (refused, visible); `cp` modes 3 and 4 rc=0 and the tree is copied into itself
without any message; `mv` mode 5 gives rc=1 ("Skipping sender remove for changed file") and in 6 of 10
runs (7 of 10 in a second session) one file holds `OLDA`, because `--append-verify` appended to a
file that was both source and target. The count varies from run to run (timing). `mv` modes 3 and
4 also end with rc=1 and a relocated, nested tree (no content lost there).

Regression (Fact, ran the original): original `mv` mode 5 ended with `src/proj` gone completely
(`rm -rf` of the source tree that contained the destination), so the new code is safer, but not
guarded.

Direction (Not verified): `case "$dest/" in "$src"/*) note_err ...; continue ;; esac`, using
physical paths (`pwd -P`) for both sides.

### C5 (MEDIUM, CONFIRMED): move syncs permissions onto a kept identical file

Where: identical entries are put in the move list (`plugins/cpmv:184,189`) and handed to rsync with
`-a` (`:246-247`); mode 5 (`:300-301`) uses `-a` on the whole tree. The header says "Files the mode
keeps are never touched".

```bash
for op in 'cp -iRp --' 'mv -i --'; do for mode in 3 4; do
  mk; put "$T/src/proj/same.txt" SAME 1750000000; chmod 644 "$T/src/proj/same.txt"
  put "$T/dst/proj/same.txt" SAME 1750000000; chmod 600 "$T/dst/proj/same.txt"
  run "$op" "$mode\n\n" "$T/src/proj"
  echo "$op mode $mode: dst/proj/same.txt perms $(stat -c %a "$T/dst/proj/same.txt") (was 600)"; rm -rf "$T"
done; done
```

Actual: `cp` modes 3/4 keep 600; `mv` modes 3/4 give 644 (also `v` mode 2 on a directory and mode 5
copy and move, seen in my harness). A private file becomes world-readable.

Regression (Fact): original `cp` modes 3/4 also changed it to 644, so copy improved; move is the
same as before.

### C6 (LOW, CONFIRMED): "merged into, like cp does" is false for `cp` modes 1 and 2

Where: comment `plugins/cpmv:82-83`, `-K` at `:84`; `cp` calls at `:288` and `:294`.

```bash
for mode in 1 2 4; do
  mk; put "$T/src/proj/a.txt" NEW-CONTENT-LONGER 1800000000; put "$T/real/a.txt" old 1700000000; ln -s ../real "$T/dst/proj"
  run 'cp -iRp --' "$mode\n\n" "$T/src/proj"
  echo "cp mode $mode rc=$RC: real/a.txt=$(cat "$T/real/a.txt")"; rm -rf "$T"
done
```

Actual: modes 1 and 2 give rc=1 (`cp: cannot overwrite non-directory 'dst/proj' with directory
'src/proj'`, same for `cpg`, and for a nested symlinked directory); mode 4 merges into `real/`
(rc=0). The failure is visible, so this is a documentation error plus an inconsistency between
modes. Original behaviour (Fact, ran it): `cp` modes failed the same way; rsync mode 4 replaced the
symlink `dst/proj` by a real directory and left `real/` unchanged, so `-K` is an improvement.

### C7 (LOW, CONFIRMED): sparse files inflate, xattrs are lost on the rsync paths

Where: `RS=(-a -K -8)` at `plugins/cpmv:84` (no `-S`, no `-X`/`-A`).

```bash
for spec in 'cp -iRp --:1' 'cp -iRp --:4' 'mv -i --:1'; do op=${spec%:*}; mode=${spec#*:}
  mk; mkdir -p "$T/src/proj"; truncate -s 40M "$T/src/proj/sparse.bin"; put "$T/dst/proj/other" o 1700000000
  run "$op" "$mode\n\n" "$T/src/proj"
  echo "$op mode $mode: allocated KB at target = $(du -k "$T/dst/proj/sparse.bin" | cut -f1) (source was 0)"; rm -rf "$T"
done
mk; put "$T/src/proj/tagged" T 1750000000; python3 -c "import os,sys; os.setxattr(sys.argv[1],'user.tag',b'v')" "$T/src/proj/tagged"; put "$T/dst/proj/o" o 1700000000
run 'mv -i --' '1\n' "$T/src/proj"; python3 -c "import os,sys
try: print('xattr at target:', os.getxattr(sys.argv[1],'user.tag'))
except OSError as e: print('xattr at target: LOST', e)" "$T/dst/proj/tagged"; rm -rf "$T"
```

Actual: `cp` mode 1 keeps 0 KB; `cp` mode 4 and `mv` mode 1 (directory merge) allocate 40960 KB; the
xattr is lost in the `mv` mode 1 directory merge (a plain `mv` keeps it). Mode 1/2 directory merges
are new in `e2fcb93d`; modes 3/4/5 were already like this.

### C8 (LOW, CONFIRMED, pre-existing): name ending in a newline skips the conflict menu

Where: `plugins/cpmv:335`, `target="$dest/$(basename -- "$src")"`; command substitution strips
trailing newlines (same pattern at `:237`, `:264`, `:281`).

```bash
mk; N=$(printf 'nl\n_'); N=${N%_}                      # a file name that ends in a newline
printf 'NEW-LONGER' > "$T/src/$N"; printf 'old' > "$T/dst/$N"; : > "$T/src/zz"
run 'cp -iRp --' '7\n7\n\n' "$T/src/$N" "$T/src/zz"
c=$(cat "$T/dst/$N"; echo x); echo "rc=$RC, target now: ${c%x} (answers were skip; must still be 'old')"; rm -rf "$T"
```

Actual: `rc=0, target now: NEW-LONGER`. Pathological name, so LOW.

### C9 (LOW, CONFIRMED): false failure when a directory and its child are both selected

Where: `plugins/cpmv:337-340`.

```bash
mk; put "$T/src/proj/sub/x.txt" XX 1750000000
run 'mv -i --' '' "$T/src/proj" "$T/src/proj/sub/x.txt"
echo "rc=$RC ; moved fine: $([ -e "$T/dst/proj/sub/x.txt" ] && echo yes) ; $(grep -m1 'not found' "$T/out" | sed "s#$T#T#")"; rm -rf "$T"
```

Actual: `rc=1 ; moved fine: yes ;   ! not found: T/src/proj/sub/x.txt`. Per the commit message nnn
keeps the selection on exit 1 (Not verified here), so the next paste would fail again.

### C10 (LOW, CONFIRMED): mode 2 on single files has three rough edges

Where: `plugins/cpmv:292-295` (the `$CMD $BASE -u` branch, no `-f`, no `finish_move`).

(a) `mv -u` onto a read-only older target asks on the tty and consumes the next answer. Run under a
real pty with `script` (the block ends after about 20 s, because `script` waits for the plugin and
`timeout 20` stops it):

```bash
mk; put "$T/src/a.txt" A-NEW 1800000000; put "$T/dst/a.txt" a-old 1700000000; chmod 444 "$T/dst/a.txt"
put "$T/src/b.txt" B-NEW 1800000000; put "$T/dst/b.txt" b-old 1700000000
printf '%s\0%s' "$T/src/a.txt" "$T/src/b.txt" > "$T/sel"
(cd "$T/dst" && printf '2\ny\nn\n\n' | timeout 20 script -qec "$P 'mv -i --' $T/sel ." /dev/null 2>&1 | tr -d '\r' | sed "s#$T#T#g" | grep -E 'replace|choose|apply|invalid')
chmod -R u+rwX "$T"; rm -rf "$T"
```

Actual: `mv: replace 'T/dst/a.txt', overriding mode 0444 (r--r--r--)?` appears (`mvg:` when advcpmv
is in `PATH`); it takes the `y` meant for the "apply to ALL" prompt, the following prompts are
shifted, and `invalid.` is printed. Pre-existing.

(b) Files kept by `mv -u` are not reported; the directory path reports them:

```bash
mk; put "$T/src/a.txt" AAAA 1700000000; put "$T/dst/a.txt" AAAA-newer 1800000000
put "$T/src/b.txt" BBBB 1700000000; put "$T/dst/b.txt" BBBB-newer 1800000000
run 'mv -i --' '2\ny\n\n' "$T/src/a.txt" "$T/src/b.txt"
echo "files : kept-report lines=$(grep -c 'kept in the source' "$T/out"); still in src: $(ls "$T/src" | tr '\n' ' ')"; rm -rf "$T"
mk; put "$T/src/proj/a.txt" AAAA 1700000000; put "$T/dst/proj/a.txt" AAAA-newer 1800000000
run 'mv -i --' '2\n' "$T/src/proj"
echo "dir   : kept-report lines=$(grep -c 'kept in the source' "$T/out"); still in src: $(ls "$T/src/proj" | tr '\n' ' ')"; rm -rf "$T"
```

Actual: `files : kept-report lines=0; still in src: a.txt b.txt` and `dir   : kept-report lines=1`.

(c) "newer only" in copy mode cannot replace a read-only (444) older target, while modes 1, 3, 4 can:

```bash
mk; put "$T/src/f" NEW-LONGER 1800000000; put "$T/dst/f" old 1700000000; chmod 444 "$T/dst/f"
put "$T/src/g" g 1800000000; put "$T/dst/g" h 1700000000
run 'cp -iRp --' '2\ny\n\n' "$T/src/f" "$T/src/g"; echo "cp mode 2 on a 444 target: rc=$RC f=$(cat "$T/dst/f")"; rm -rf "$T"
```

Actual: `rc=1 f=old` (visible failure).

### C11 (LOW, CONFIRMED, pre-existing): `cp` modes 1 and 2 write through a target symlink

```bash
for spec in 'cp -iRp --:1' 'cp -iRp --:2' 'cp -iRp --:4'; do op=${spec%:*}; mode=${spec#*:}
  mk; put "$T/outside/real.txt" ORIGINAL 1700000000; put "$T/src/proj/lnk" SRC-NEWER-AND-LONGER 1800000000
  put "$T/src/proj/p" p 1800000000; put "$T/dst/proj/p" q 1700000000; ln -s ../../outside/real.txt "$T/dst/proj/lnk"
  run "$op" "$mode\n\n" "$T/src/proj"
  echo "$op mode $mode: outside/real.txt=$(cat "$T/outside/real.txt")"; rm -rf "$T"
done
```

Actual: modes 1 and 2 change `outside/real.txt` to the source content (a file outside the target
tree); mode 4 (and `mv`, modes 3, 5) replace the link and leave `outside/real.txt` alone.

### C12 (LOW, CONFIRMED): sub-second "newer"

```bash
for spec in 'cp -iRp --:2' 'cp -iRp --:4' 'mv -i --:2'; do op=${spec%:*}; mode=${spec#*:}
  mk; mkdir -p "$T/src/proj" "$T/dst/proj"; printf 'SRC---' > "$T/src/proj/f"; touch -d @1750000000.5 "$T/src/proj/f"
  printf 'DST---' > "$T/dst/proj/f"; touch -d @1750000000.0 "$T/dst/proj/f"
  run "$op" "$mode\n\n" "$T/src/proj"; echo "$op mode $mode: dst/proj/f=$(cat "$T/dst/proj/f")"; rm -rf "$T"
done
```

Actual: `cp` mode 2 gives `SRC---` (nanosecond compare); `cp` mode 4 and `mv` mode 2 give `DST---`
(rsync compares whole seconds). One-second differences are handled consistently by all paths.

## What I checked and found fine

Method note: about 470 plugin invocations while exploring, in 35 scratch scripts (deleted at the
end); the compact reproducers above and block `M` below are the surviving versions.

| area | what I ran | result |
|---|---|---|
| Mode matrix | block `M`: 15 target cases (mtime older, 1 s older, equal, 1 s newer, newer x size smaller, same, bigger), modes 1-5, copy and move, nested (form A) and 15 top-level items with apply-to-all (form B), variants plain cp/mv, advcpmv, bfs (900 checks); target content and mtime, source after move | all decisions match the header table except C2 and C3 |
| Mode 5 | same matrix plus a true interrupted copy (target is a prefix of the source) | resume completes copy and move; a target that is longer or of equal size is kept and the source stays |
| Plan parser | 44 names (leading, trailing and double spaces, `->`, `\`, `\#012`, `\#`, `\#1`, `\#0123`, `\\#012`, newline, tab, CR, ESC, DEL, invalid UTF-8, UTF-8, CJK, `-dash`, glob characters, quotes, `$`, `;`, backtick, `%s`, 240-byte name, `dot.`, `...`) in three cases each (size differs, same size source newer, same size target newer), `LC_ALL=C`, `en_US.utf8`, `C.utf8`, copy and move, modes 3 and 4 | every file ended in the expected state, no missing file, no wrong kept/replaced |
| Specials | fifo, unix socket, hard-link pair, relative/absolute/dangling/dir symlinks, empty file, 3 MB sparse file, nested empty directories, in a moved tree, modes 1-5; invariant "every source entry is still in the source or present at the target" (checker validated with a negative test) | no loss |
| Source is a symlink | selected item is a symlink to a directory, to a file, dangling; target is a regular file; modes 1-5 copy and move | the link is copied or moved as a link, never dereferenced |
| Race | shim `rsync` that slows the real transfer (`--bwlimit`) and appends to, replaces, or deletes a source file one second in; modes 3, 4 | rsync prints "Skipping sender remove for changed file", plugin exits 1, source kept; deleted source gives rc 0 with the target complete |
| Read-only | target file 444, target directory 555, source directory 555, modes 1-5 copy and move, plain and advcpmv | every failure is counted, exit 1, nothing lost. Side note (Fact): rsync modes 4 and 5 and `v` 4 did write into the 555 target directory and left it 755 (the source mode); `cp` mode 1 failed to create the new file (rc 1) and also left 755. I did not investigate why rsync could write. |
| Menu | clash menu (rename/skip only, invalid answers, EOF), apply-to-all with a clash and a missing item in between, apply-to-all skip, file over directory single item | behaves as designed; clash menu ignores apply-to-all as intended |
| Exit and pause | no conflict, single directory conflict, move that keeps files, two-file conflict, missing item, no rsync (modes 4 and `v` 1 on a directory), unusable `TMPDIR` with modes 4 and 1, empty or missing selection | exit codes and pauses as documented; source intact when rsync is missing; the EXIT trap does not leak its status |
| EOF and signals | stdin empty at every prompt; SIGINT, SIGTERM, SIGHUP while waiting at the menu | no endless loop; temp directory removed in all three cases |
| `finish_move` | 4-level empty directory chains plus a kept file, GNU find 4.8.0, bfs 4.1.1 with `-S dfs` and with its default breadth-first order | identical result: empty chains pruned, kept file and its parents stay |
| Symlinked target dir | target `dst/proj` and nested `dst/proj/sub` are symlinks to directories, rsync modes and `v` modes | merged correctly (`-K` works); only `cp` modes 1/2 fail (C6) |
| advcpmv | all of the above that reach `cp`/`mv` also run with `cpg`/`mvg` in `PATH` | same results as plain `cp`/`mv` |

Note on `find`: in a clean environment `find` is `/usr/bin/find`; the bfs `find` of this shell is a
function that is not exported (Fact: `env -i PATH=$PATH bash -c 'type -a find'` prints only
`/usr/bin/find`), so nnn never starts the plugin with bfs. I tested it anyway.

Block `M` (matrix; prints only the cases that break the header table or lose content):

```bash
M=1750000000; declare -A TM=([older]=$((M-1000)) [older1]=$((M-1)) [eq]=$M [newer1]=$((M+1)) [newer]=$((M+1000)))
declare -A TC=([small]=TTTT [same]=TTTTTTTTTT [big]=TTTTTTTTTTTTTTT)
expect() { local sn=0 sd=0; case $2 in older|older1) sn=1;; esac; [ "$3" != same ] && sd=1
  case $1 in 1) echo R;; 2) ((sn)) && echo R || echo K;; 3) ((sd)) && echo R || echo K;; 4) ((sd||sn)) && echo R || echo K;; esac; }
for form in A B; do for op in 'cp -iRp --' 'mv -i --'; do for mode in 1 2 3 4; do
  mk; items=(); [ $form = A ] && base=proj || base=.
  for t in "${!TM[@]}"; do for s in "${!TC[@]}"; do n="f_${t}_${s}.txt"
    put "$T/src/${base#.}/$n" SSSSSSSSSS $M; put "$T/dst/${base#.}/$n" "${TC[$s]}" "${TM[$t]}"
    [ $form = B ] && items+=("$T/src/$n"); done; done
  if [ $form = A ]; then run "$op" "$mode\n\n" "$T/src/proj"; d=proj; else run "$op" "$mode\ny\n\n" "${items[@]}"; d=.; fi
  for t in "${!TM[@]}"; do for s in "${!TC[@]}"; do n="f_${t}_${s}.txt"; f="$T/dst/${d#.}/$n"
    c=$(cat "$f"); m=$(stat -c %Y "$f"); e=$(expect $mode $t $s)
    if [ "$c" = SSSSSSSSSS ] && [ "$m" = $M ]; then got=R; else got=K; fi
    [ "$got" != "$e" ] && echo "WRONG-DECISION form$form ${op%% *} mode$mode $n expected=$e got=$got"
    if [ "${op%% *}" = mv ] && [ ! -e "$T/src/${d#.}/$n" ] && [ "$c" != SSSSSSSSSS ]; then echo "SOURCE-CONTENT-LOST form$form mv mode$mode $n (target holds $c)"; fi
  done; done; rm -rf "$T"
done; done; done
```

Actual output (run after the helpers above): the same 7 lines with plain and with advcpmv `PATH`
(line order varies because of the associative arrays). The full harness behind it, which also
covered mode 5 and a bfs `find` in `PATH`, printed these 7 plus the two mode 5 lines of C3 for
every variant.

```text
WRONG-DECISION formA mv mode2 f_eq_big.txt expected=K got=R
WRONG-DECISION formA mv mode2 f_eq_small.txt expected=K got=R
SOURCE-CONTENT-LOST formA mv mode2 f_eq_same.txt (target holds TTTTTTTTTT)
SOURCE-CONTENT-LOST formA mv mode3 f_eq_same.txt (target holds TTTTTTTTTT)
SOURCE-CONTENT-LOST formA mv mode4 f_eq_same.txt (target holds TTTTTTTTTT)
SOURCE-CONTENT-LOST formB mv mode3 f_eq_same.txt (target holds TTTTTTTTTT)
SOURCE-CONTENT-LOST formB mv mode4 f_eq_same.txt (target holds TTTTTTTTTT)
```

(Mode 5 is judged separately: `v` mode 5 also loses `f_eq_same`, form A and B; see C3.)

## Test gap (for the test-strength reviewer)

Fact: the shared fixture `misc/test/test-cpmv.sh:58-68` has no pair with an equal mtime and a
different size, no pair with equal size and mtime but different content, and no nested
file-versus-directory pair. The only type-clash group, `g_type_mismatch` (`:294-309`), uses a
top-level item. C1, C2 and C3 live exactly in those gaps. I did not read the other groups of the
578 checks. Not verified: whether the randomized oracle (`:344`) draws equal mtimes.

## Not verified

- bash 3.2 (not available). Constructs to check by reading, none run: `local ... rm=() why` and
  `local rm=()` (`plugins/cpmv:236`, `:299`, array in `local`); `printf -v` and `%b` with `\0NNN`
  (`:142`, needs bash 3.1+); `+=` on strings and arrays (`:104`, `:116`, `:143`, needs 3.1+);
  `${s:${#pre}+2:3}` (`:141`, `:144`, arithmetic substring offsets, indexing is per character in a
  UTF-8 locale); `"${files[@]}"` and `"${err_msgs[@]}"` under `set -u` (only expanded when non-empty,
  so safe on 3.2 and 4.0-4.3); `${rm[@]+"${rm[@]}"}` (`:246`, `:301`, the 3.2-safe form). I found no
  `[[ ]]`, `declare -A`, `mapfile`, `${var,,}` or `|&` in the script.
- BSD/macOS: `stat -f`, `rmdir --`, BSD `grep -aFxf`, `wc -l` padding (the script already strips it
  with `$((left + 0))` and in arithmetic), and rsync older than 3.1 (macOS ships 2.6.9; options
  `-8`, `--info=progress2`, `--remove-source-files` would fail with status 1, which is visible).
- FAT/exFAT/NTFS targets under `/media`: `rsync -a` often reports status 23 for chown/chmod there and
  FAT stores even seconds, so mode 4 would copy again every file whose time differs by one second.
  Cannot mount here. Open question: should the rsync calls use `--no-o --no-g --modify-window=1`?
- Device files, ACLs, file capabilities, case-insensitive file systems, ENOSPC midway, Ctrl-C while rsync
  runs, trees with 10^5 files (the plan loops are plain bash `while read`).
- How nnn reacts to exit status 1 (integration reviewer's lens), and the single-file `y/N` prompt under
  a pty (only the menu path was run under a pty).
- Fix directions in C1 to C4 were not implemented or run.
- Housekeeping note: when I started, 98 directories `/tmp/cpmv.*` (dated 15:40 to 15:45) existed that I
  did not create (the later ones hold the fixture names of `misc/test/test-cpmv.sh`, so they come from
  suite or mutant runs of another agent). My own runs do not leak (count 99 before and after five plan
  runs; the pty block of C10 (a) also leaves nothing). One empty directory left by my own SIGKILLed
  pty run was removed. Someone else has since removed most of the others; 4 remain (3 with suite
  fixture names, 1 empty from 15:54), which I left alone.

Reproducers run: about 620 plugin invocations. About 470 while exploring (35 scratch scripts, all
deleted), plus 148 when I extracted the 16 bash blocks above (C1 to C12 and `M`, after the helper
block) from this file and ran each one verbatim in a fresh shell, once with a `PATH` without
`/usr/local/bin` (plain `cp`/`mv`) and once with advcpmv. The two runs gave the same output for all
16 blocks, except for the random `OLDA` count in C4 and the progress-bar text in the C10 (a) output.
