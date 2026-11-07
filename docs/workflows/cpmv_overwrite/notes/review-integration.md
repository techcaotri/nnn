# Integration and user experience: review of e2fcb93d

## Purpose

Check that the new `plugins/cpmv` works through the real nnn binary in the owner's two-pane
setup, in situations that `misc/test/test-cpmv-e2e.sh` does not cover: two nnn instances with one
shared selection file, a multi-item paste, repeated rename, an interrupt (Ctrl-C) during a big
transfer, narrow terminals, and a failing paste in the `-r` (advcpmv) build.

## Verdict

The fix behaves correctly through the real nnn in every disk-state check I ran: no overwrite
went wrong, no source file was lost (also after Ctrl-C during `v` and `p` of 3 x 400 MiB files),
the shared selection is cleared in both panes, and nnn pauses with `'Enter' to continue` and
prints `failed!` when a paste fails. One behaviour should change: **Ctrl-C only stops the running
`rsync`, not the plugin** (finding F1, MEDIUM). The plugin goes on with the remaining selected
items, and after "apply to ALL" it does so without asking. The other findings are cosmetic
(narrow terminals, progress line, a partial copy left after a failed rename).

## Scenario results

| # | Scenario | Result | Evidence |
|---|---|---|---|
| 1 | Two panes, shared `NNN_SEL`, `NNN_DND_OSC72=1`, `p`, answer `4` | PASS | 22 checks, 0 failed |
| 2 | Two directories + one file, `v`, answer `4` then `y` | PASS | 26 checks, 0 failed; `Done. Press enter.` appears once |
| 3 | Mode `6` twice in a row, then `7`; plus one paste answered `6`,`6`,`7` | PASS | 17 checks, 0 failed |
| 4 | Ctrl-C during rsync, `v` and `p`, 3 x 400 MiB | PASS for data safety; finding F1 | no source file lost, no partial target, no temp files |
| 5 | Narrow terminal, 80 and 60 columns | 80: PASS. 60: FAIL for readability | findings F2 and F3 |
| 6 | Failing paste (`chmod 000`) in the `-r` build, modes 1, 6, 4 | PASS | nnn pauses, prints `failed!`, keeps the selection; retry works |
| 7 | Screen quality | captured | section "Screens" |

## Findings

| ID | Severity | file:line | Summary | Status |
|---|---|---|---|---|
| F1 | MEDIUM | `plugins/cpmv:333`, `plugins/cpmv:367`, `plugins/cpmv:119-124` | Ctrl-C ends only the running `rsync` (exit 20). The plugin counts one error and goes on with the next selected item. After "apply to ALL" the next item is processed with no prompt. | CONFIRMED |
| F2 | LOW | `plugins/cpmv:321-324`, `plugins/cpmv:243-244` | At 60 columns the conflict menu and the plan line wrap in the middle of words. At 80 columns they fit. | CONFIRMED |
| F3 | LOW | `plugins/cpmv:246`, `plugins/cpmv:258` | `--info=progress2` lines are 64 characters wide, so at 60 columns each update wraps and leaves fragments. Also the percentage ended at 80% when the tree held a symlink. | CONFIRMED (wrap). Cause of 80%: Assumption |
| F4 | LOW | `plugins/cpmv:262-277` (`rename_one`) | A failed copy in mode 6 leaves a partial `proj (1)`. A retry creates `proj (2)`. | CONFIRMED |

## Details

### F1: Ctrl-C does not cancel the plugin (MEDIUM)

Fact: the plugin has no `INT` trap (only `trap ... EXIT`, `plugins/cpmv:109`). The Ctrl-C reaches
the whole foreground process group (nnn, the plugin, rsync). rsync handles SIGINT itself and
exits normally with status 20, so bash does not treat the script as interrupted and continues
(bash rule: a child that exits normally after SIGINT means the child handled the signal).
`try` (`plugins/cpmv:119-124`) only counts the failure. The loop at `plugins/cpmv:333` then takes
the next item, and with `GLOBAL_MODE` set it runs `do_one` at `plugins/cpmv:367` without a prompt.

Reproducer (run 1: next item asks again; run 2: next item is processed silently). Both used
`tmux -L cpmv-review-integ-<name>`, a private `XDG_CONFIG_HOME` holding a symlink to
`plugins/cpmv`, and a private `NNN_SEL`. Run 2 setup:

```bash
# fixture: three directories in src/ and dst/, mode 4 must replace every file in dst/
mkdir -p src/a_first src/bigproj src/zlast dst/a_first dst/bigproj dst/zlast
printf 'first-src-longer' > src/a_first/f.txt;  printf 'ff' > dst/a_first/f.txt
for i in 1 2 3; do yes "big$i-pattern" | head -c 419430400 > src/bigproj/big$i.bin
                   printf 'old-small-%s' $i > dst/bigproj/big$i.bin; done
printf 'last-src-longer' > src/zlast/z.txt;     printf 'zz' > dst/zlast/z.txt
touch -d @1700000000 $(find src -type f); touch -d @1800000000 $(find dst -type f)   # target newer
# left pane: cd src; nnn <owner's options>; Space x3 (selects a_first, bigproj, zlast)
# right pane: cd dst; nnn <owner's options>; press v; answer 4; then y (apply to all)
# while dst/bigproj/.big1.bin.* has >= 100 MB: tmux -L <sock> send-keys -t <right pane> C-c
```

Expected: the run stops, `zlast` untouched. Actual (plugin output, trimmed):

```text
  comparing bigproj ...
  bigproj: 3 file(s) to move, 0 kept (same size, target not older), 0 identical
         32,768   0%    0.00kB/s    0:00:00  ^C
rsync error: received SIGINT, SIGTERM, or SIGHUP (code 20) at rsync.c(716) [sender=3.2.7]
  ! bigproj: 'rsync' failed (status 20)
  comparing zlast ...
  zlast: 1 file(s) to move, 0 kept (same size, target not older), 0 identical
cpmv: 1 problem(s):
  - bigproj: 'rsync' failed (status 20)
'Enter' to continue
```

Disk after run 2: `src/zlast/z.txt` missing, `dst/zlast/z.txt` = `last-src-longer`. The item after the
interrupted one was moved, although the user had pressed Ctrl-C.

Run 1 (`v`, two items `bigproj` and `zsecond`, answer `4`, Ctrl-C during `big1.bin`): the plugin printed
`! bigproj: 'rsync' failed (status 20)`, then `apply to ALL remaining conflicts? [y/N]:` and the
menu `CONFLICT: zsecond`. The user has to answer more prompts after pressing Ctrl-C.

Impact: no data is lost (the interrupted rsync keeps the source, see scenario 4). But a cancel
does not cancel, and with "apply to ALL = overwrite" the remaining items are overwritten or moved
after the user asked to stop.

### F2: menu and plan line wrap at 60 columns (LOW)

At 60 columns (pane width, real nnn, `tmux -L ... split-window -l 60`):

```text
    1) overwrite          2) newer only        3) different
size only
    4) different size or newer                 5) resume (in
terrupted)
    6) rename (keep both) 7) skip
    choose [1-7]:
...
  proj: 5 file(s) to copy, 1 kept (same size, target not old
er), 0 identical
```

The longest menu line is 70 characters, the plan line 76. At 80 columns both fit.

### F3: progress line wraps and can end below 100% (LOW)

The rsync progress line is 64 columns wide. At 60 columns every update wraps; the last frame before
nnn redrew showed four stacked copies of the line and a loose `/10)` below them:

```text
             46  80%   40.04kB/s    0:00:00 (xfr#5, to-chk=0
             46  80%   40.04kB/s    0:00:00 (xfr#5, to-chk=0
             46  80%   40.04kB/s    0:00:00 (xfr#5, to-chk=0
             46  80%   40.04kB/s    0:00:00 (xfr#5, to-chk=0
/10)
```

In scenario 1 the progress stopped at 80% (`46` bytes). That tree held an 11-byte symlink
(`link-to-file`), and 46 + 11 = 57, which would be 100%. Assumption: rsync counts the symlink in the
total but not in the bytes sent. In scenario 2 (no symlink) the same line reached `100%`.

### F4: partial copy left after a failed rename (LOW)

Source `proj/` holds `ok.txt` and an unreadable `locked.txt` (`chmod 000`). Key `p`, answer `6`
(`nnn -r`, `cpg` is used):

```text
cpg: cannot open '.../src/proj/locked.txt' for reading: Permission denied      ]  0.0 %
1 folder(s) ( 12.0 KiB) copied in  0.0s (  0.0 KiB/s).
  ! proj: 'cpg' failed (status 1)
cpmv: 1 problem(s):
  - proj: 'cpg' failed (status 1)
'Enter' to continue
```

Disk afterwards: `dst/proj (1)/ok.txt` exists, `locked.txt` is missing in it. nnn kept the selection,
so a retry with `6` makes `proj (2)`. This is how `cp -R` fails; the plugin does not remove or
mention the partial `proj (1)`. (The `]  0.0 %` after the error text is a leftover of the `cpg`
progress bar, not of the plugin.)

## Scenario 1: two panes, shared selection (PASS)

Setup: one private tmux server, window 201 x 45, two panes of 100 columns, both started with
`-e -a -o -r -R -i -d -H -P a -P p -s <private name> -S -f` (the owner's alias options), environment
`NNN_DND_OSC72=1`, same `NNN_SEL`. Source tree `src/proj` (the e2e fixture plus: a file only in the
source, a file only in the target, a non-ASCII name with spaces `ünï cödé.txt`, an empty directory, a
symlink). Left pane in `src`, right pane in `dst`. Space in the left pane, `p` in the right pane,
answer `4`.

| Check | Result |
|---|---|
| Right pane showed `+1` after the left selection (live sync) | PASS, within 1 s |
| Dest newer + size differs (`dn_diff.txt`) | PASS, `AAAAA` |
| Source newer + same size (`sn_same.txt`) | PASS, `SNEWER` |
| Dest newer + same size (`dn_same.txt`) | PASS, kept `DNEWER`, mtime unchanged |
| Nested file (`sub/deep.txt`) | PASS, `deep-src` |
| File only in source created, file only in target untouched | PASS |
| Non-ASCII name with a space overwritten | PASS |
| Empty directory created, symlink copied as a symlink | PASS |
| Copied file has the source mtime | PASS |
| Source untouched | PASS |
| `NNN_SEL` file size 0 afterwards | PASS |
| No `+N` mark in the left pane, none in the right pane | PASS (left pane cleared within 1 s) |
| No `cpmv.*` temp directory in `TMPDIR`, no hidden rsync temp file | PASS |

Command run (harness in the scratch directory, removed after the review): `bash s1.sh s1 100`,
result `22 passed, 0 failed`.

## Scenario 2: multi-select, `v`, `4`, `y` (PASS)

Selection order (from `NNN_SEL`): `projA projB file1.txt`. One menu, one apply-to-all prompt, one
`Done. Press enter.` (counted in the captured plugin output: 1, 1, 1). Disk: both directories merged
by mode 4 (`dn_diff`, `sn_same`, `deep` moved over, `dn_same` kept at the target), `file1.txt`
moved over. The source tree afterwards: `projA/dn_same.txt` and `projB/dn_same.txt` only (the kept
files, empty `sub/` removed). Selection cleared in both panes. 26 checks, 0 failed.

## Scenario 3: rename twice, then skip (PASS)

Part A: `p` of `proj/` and `notes.txt` (both conflict), answers `6`,`n`,`6` three times.

| Round | Answers | Disk after |
|---|---|---|
| 1 | `6`, `6` | `proj (1)` full copy, `notes (1).txt`; originals untouched |
| 2 | `6`, `6` | `proj (2)`, `notes (2).txt`; round 1 results untouched |
| 3 | `7`, `7` | listing identical to before; no `(3)`; output `- skipped proj`, `- skipped notes.txt` |

Part B: one paste of three items with `v`, answers `6`,`6`,`7`. Selection order `m1 m3 m2.txt`
(directories first). `m1` and `m3` were renamed to `m1 (1)`, `m3 (1)` and moved out of the source;
`m2.txt` was skipped and stayed in the source, with no `(1)` copy. Selection cleared each time.
17 checks, 0 failed.

## Scenario 4: Ctrl-C during a big transfer (data safe, F1 found)

Fixture: `bigproj/` with `a_small.txt` and `big1.bin`, `big2.bin`, `big3.bin` (419430400 bytes each,
generated with `yes "bigN-pattern" | head -c 419430400`). The target `bigproj/` holds smaller files
with the same names and a NEWER mtime, so mode 4 must replace them by size. Ctrl-C was sent with
`tmux send-keys C-c` when the rsync temp file `dst/bigproj/.bigN.bin.XXXXXX` held at least 25% of
the file (100 to 127 MB). Content check: `cmp <(yes "bigN-pattern" | head -c 419430400) <file>`.

| Run | Key | Interrupted in | Source after | Target after | Verdict |
|---|---|---|---|---|---|
| s4v | `v` | `big2.bin` (107 MB written) | all 4 files present and equal to the original | `big1.bin` complete; `big2`, `big3` old; `a_small` copied | no loss |
| s4p | `p` | `big1.bin` (127 MB written) | all present and intact | `big1..3` old; `a_small` copied | no loss, source untouched |
| s4v2 | `v`, 2 items | `big1.bin` | same as s4v | same | no loss; F1 (next prompt) |
| s4c | `v`, 3 items + `y` | `bigproj` (119 MB written) | `zlast` moved out; `bigproj` content not compared in this run | `dst/zlast/z.txt` = `last-src-longer` | F1 (silent next item); data check of `bigproj` Not verified here |

Also in runs s4v, s4p and s4v2 (script checks, CONFIRMED):

- no hidden rsync temp file left in the target directory,
- no `cpmv.*` directory left in `TMPDIR` (the EXIT trap ran),
- no rsync process left,
- nnn survived, showed `'Enter' to continue`, then `failed!`, and kept the selection (file size > 0,
  `+1` still shown in the left pane).

Fact: files already copied are not always removed from the source at the interrupt. In s4v `big1.bin`
was complete at the target and still present in the source (rsync removes a source file lazily after
the receiver confirms it). This is safe: nothing is lost, only duplicated.

Screen after the interrupt (`v`, trimmed, path shortened):

```text
mv -> .../dst   (1 item[s])
  CONFLICT: bigproj
    source :  (directory)   2026-11-07 15:33:17
    target :  (directory)   2026-11-07 15:33:17
    ...
    choose [1-7]: 4
  comparing bigproj ...
  bigproj: 4 file(s) to move, 0 kept (same size, target not older), 0 identical
    419,430,417  33%    1.15GB/s    0:00:00 (xfr#2, to-chk=2/5)^C
rsync error: received SIGINT, SIGTERM, or SIGHUP (code 20) at rsync.c(716) [sender=3.2.7]
rsync error: received SIGINT, SIGTERM, or SIGHUP (code 20) at io.c(519) [generator=3.2.7]
  ! bigproj: 'rsync' failed (status 20)
cpmv: 1 problem(s):
  - bigproj: 'rsync' failed (status 20)
'Enter' to continue
```

## Scenario 5: narrow terminal

| Width | Menu | Plan line | Progress lines | Verdict |
|---|---|---|---|---|
| 100 | fits | fits | fits | PASS |
| 80 | fits (70 characters) | fits (76) | fits (64) | PASS |
| 60 | wraps inside words | wraps | wraps, stacked fragments | FAIL for readability (F2, F3) |

Disk results at 80 and 60 columns were identical to scenario 1 (22 checks each, 0 failed): only the
display suffers. Screens at 60 columns are in F2 and F3.

## Scenario 6: failing paste in the `-r` build (PASS)

`nnn -r ...`, `cpg` and `mvg` from `/usr/local/bin`, source `proj/locked.txt` with `chmod 000`.
Each mode was run in a fresh nnn pair (an earlier combined run matched stale text on the pane, so I
rely on the single-mode runs).

| Mode | Command used by the plugin | Plugin message | nnn pause | `failed!` | Selection kept |
|---|---|---|---|---|---|
| 1 overwrite | `cpg -g -Rp -f` | `! proj: 'cpg' failed (status 1)` | yes | yes | yes |
| 6 rename | `cpg -g -Rp` | `! proj: 'cpg' failed (status 1)` | yes | yes | yes (F4: partial `proj (1)`) |
| 4 diff size or newer | `rsync --files-from` | `! proj: 'rsync' failed (status 23)` | yes | yes | yes |

After `chmod 644` and a retry with mode 1: `locked.txt` and `ok.txt` copied, selection cleared, no
temp directory left.

## Screens (scenario 7)

What the user sees, scenario 1, 100 columns. Notes: the emoji icons of nnn are shown as `[dir]`;
the shell prompt lines above the plugin output (the command that started nnn) and the long path
are cut. The bottom line `invalid key` at start comes from `-P p` with no `NNN_PLUG` in the private
config (see "Not verified").

Left pane after Space on `proj`:

```text
1 2 3 4 5 6 7 8 /t/c/-/4/s/r/r/d/src
>2026-11-07 15:31  775       4K +[dir] proj/
  directory
  proj
1/1  +1  H 2026-11-07 15:31 drwxrwxr-x 4K
```

Right pane one second later (selection arrived through `NNN_SEL`):

```text
1 2 3 4 5 6 7 8 /t/c/-/4/s/r/r/d/dst
>2026-11-07 15:31  775       4K  [dir] proj/
  directory
  proj
1/1  +1  H 2026-11-07 15:31 drwxrwxr-x 4K
```

Right pane after `p` (nnn left the alternate screen; the old shell lines stay above):

```text
cp -> .../dst   (1 item[s])
  CONFLICT: proj
    source :  (directory)   2026-11-07 15:31:52
    target :  (directory)   2026-11-07 15:31:52
    1) overwrite          2) newer only        3) different size only
    4) different size or newer                 5) resume (interrupted)
    6) rename (keep both) 7) skip
    choose [1-7]:
```

After `4` and Enter (last frame before nnn redrew; it is on screen for about a second):

```text
  comparing proj ...
  proj: 5 file(s) to copy, 1 kept (same size, target not older), 0 identical
             46  80%   40.04kB/s    0:00:00 (xfr#5, to-chk=0/10)
```

Both panes afterwards (selection gone, no `+1`):

```text
1/1 H 2026-11-07 15:31 drwxrwxr-x 4K
```

Scenario 2, the single pause at the end (plugin output, trimmed):

```text
  CONFLICT: projA
    ...
    choose [1-7]: 4
  comparing projA ...
  projA: 3 file(s) to move, 1 kept (same size, target not older), 0 identical
             19 100%   13.67kB/s    0:00:00 (xfr#3, to-chk=0/6)
  - kept in the source: 1 file(s) of projA (not replaced by this mode)
    apply to ALL remaining conflicts? [y/N]: y
  comparing projB ...
  projB: 3 file(s) to move, 1 kept (same size, target not older), 0 identical
  - kept in the source: 1 file(s) of projB (not replaced by this mode)
  comparing file1.txt ...
  file1.txt: 1 file(s) to move, 0 kept (same size, target not older), 0 identical
Done. Press enter.
```

Left pane afterwards (two directories remain because each holds one kept file):

```text
>2026-11-07 15:38  775       4K  [dir] projA/
 2026-11-07 15:38  775       4K  [dir] projB/
1/2 H 2026-11-07 15:38 drwxrwxr-x 4K
```

## What I checked and found fine

- Live selection sync between the two panes, in both directions (set in the left pane, cleared by the
  paste in the right pane), through the shared `NNN_SEL`.
- `NNN_DND_OSC72=1` set in both panes and `TMUX` visible to nnn: no visible effect on the paste.
  Not exercised: no mouse events were sent.
- Mode 4 on a copy and a move: the reported bug case (dest newer + size differs) is overwritten; files
  the mode keeps are untouched (content and mtime).
- Move leaves a kept file in the source and says so; empty source directories are removed.
- `Done. Press enter.` appears once for a three-item paste with "apply to ALL".
- Mode 6 numbering (`(1)`, `(2)`), directories and files with an extension; mode 7 changes nothing.
- Failure path with `cpg` and `rsync`: nnn pauses, prints `failed!`, keeps the selection; a retry
  after the fix works and clears the selection.
- Interrupt: source files never lost, targets are old or complete, no temp files, no stray process.
- The binary tested is `/home/tripham/Dev/Playground_Terminal/nnn/nnn` (the same file as
  `~/bin/nnn`, md5 `c227c0e0a082e1194ef399f204c93ec4`), plugin `plugins/cpmv` at commit `e2fcb93d`.

## Not verified

- `-P p` ran with no `NNN_PLUG`, so nnn showed `invalid key` and did not start `preview-tui`. I left it
  out on purpose: it would split the tmux window. The owner's real `NNN_PLUG` and plugins were not used.
- Real terminal emulators (kitty with OSC-72 drag and drop). Only tmux 3.7b was used.
- Ctrl-C during modes 1, 2, 5, 6 (`cpg`/`mvg` path). Only mode 4 (rsync) was interrupted.
- Ctrl-C after "apply to ALL = 1" (overwrite). Mode 4 was run; the code path is the same.
- Running the same move again after an interrupt (expected: the files left in both places count as
  identical and their source is removed).
- Cross-filesystem moves, very long names, a selection made while a paste runs in the other pane.
- The reproducer snippet in F1 is condensed from the harness (a set of bash scripts driving a private
  tmux server, kept in the scratch directory and deleted after the review). The snippet itself was not
  run as written.
- Each scenario ran once. No repeat runs to look for timing flakiness. The first launch of scenarios 2,
  3 and 6 was disturbed by my own leftover script instances sending keys to the same panes; the results
  above are from clean reruns with one instance each.

## Suggestions (opinions, not defects)

1. Make Ctrl-C end the whole run. Treat rsync status 20 and 130 as "interrupted": print
   `interrupted, remaining items not processed`, stop the loop, exit 1 (selection kept). Or add a
   `trap` on `INT` that sets a flag the loop checks.
2. Keep every line at or below 56 characters, or switch layout when `tput cols` is below 72: for
   example a one-column menu, a shorter plan line (`proj: copy 5, keep 1, same 0`), and rsync
   progress through `cut -c1-$COLUMNS` or plain `--info=name1`.
3. After a single-directory `p` the screen flashes by and nnn redraws at once, so the user never sees
   `1 kept`. A short pause only when something was kept (as `v` already does) would remove the doubt
   "did mode 4 really skip it".
4. On a failed mode-6 copy, remove the partial `name (N)` or print its name in the problem list.
5. In the move pause, list the kept file names (up to about 5) next to the counts, so the user can
   clean the source without a second look.
