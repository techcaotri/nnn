# Round 2 review: OSC-72 drag-source scope fix (revised `src/nnn.c` and test)

## Purpose

This is the second independent review of the fix that arms kitty's OSC-72 drag-source flag only for a
left-button gesture that starts on nnn's own list (inside tmux). Round 1 found two Medium gaps that left
kitty's flag on (F1 stale arm, F2 wedge), a Medium test gap (F3) and several Low items. The orchestrator
changed `src/nnn.c` and `misc/test/test-dnd-osc72-scope.py` in response. This round re-checks each round 1
finding, checks the new pieces for regressions, mutation-tests the new test, and re-compares bare kitty.

Labels: `Fact` (checked by a command or by reading the code), `Assumption` (inferred), `Open question`,
`Not verified`. The repo, the owner's tmux server (default socket), kitty on display `:1` and the running
nnn panes were not touched. Nothing in the repo was edited except this report.

## Verdict

| Area | Result |
|---|---|
| F1 stale arm | Fixed on real kitty: the arm ends about 2 s after a lost release. Trade-off: a drag that starts moving more than about 2 s after the press gets no offer. |
| F2 wedge | Fixed on real kitty: a peer that starts mid-drag no longer kills the drag, and a dead drag is dropped by the next release. |
| tmux mouse-grab race | Real, and the fix is right: the previous (detached) grab stranded tmux's mouse off in 7 of 35 quick drags on real kitty, the new one in 0 of 35. |
| Bare kitty | Outbound OSC-72 stream identical to HEAD (normalised log, real kitty). One difference: the `mousemask()` reset after a drag (fixes a first click that HEAD loses). |
| Default (no `NNN_DND_OSC72`) | Silent: zero OSC-72 output and no child process, same as HEAD (`strace`). |
| Builds | 8 variants plus the old-ncurses branch compile clean, same warnings as HEAD. |
| Tests | Scope test `PASS=44 FAIL=0` (7 runs, 6 of them three at a time), `test-dnd-tmux-mouse.sh` `PASS=21 FAIL=0`, HEAD binary `PASS=13 FAIL=31`. ASan/UBSan run clean. |
| New defects | No Medium code defect. Three Low code findings (N1 to N3), two Info (N4, N5), one Medium test finding (N6). |
| Mutation test | 40 mutants: 24 killed, 16 survived. 13 of the survivors are real test gaps (2 are dead code, 1 is a redundant layer). Round 1 set: 14 of 19 killed (was 9 of 19). |

## State reviewed

| Item | Value |
|---|---|
| `src/nnn.c` md5 | `6a53deec533c0800ed0579803c7f58f3` (unchanged during the review) |
| Test md5 | `65741d46600c26a81b94f5080c904193` (unchanged) |
| Git | The orchestrator committed this state as `e60f2e27` while the review ran (`git diff HEAD` is empty for both files) |
| Repo `nnn` binary | `fec5d682c6ac80f8f411aec41f350837`, byte-identical to the reviewer's scratch build of this source |
| `nnn.bak-2026-10-23-pre-dnd-scope` | `a4e036aaa249c5611a3f7f1022f50c4d`, byte-identical to the reviewer's build of the pre-fix source (`git show 2362eb91:src/nnn.c`), so "HEAD" below means the pre-fix code |
| Stack | kitty 0.49.2, tmux 3.7b, libncursesw 6.3 (X10 mouse encoding inside tmux panes), gcc 11.5 |

## Test rigs

| Rig | What it is |
|---|---|
| A, fake kitty | The repo test's own `FakeKitty` and `Run` (real tmux, real nnn), loaded as a module for scratch scenarios. |
| B, real kitty | Real kitty 0.49.2 (`--debug-input`) on a private `Xvfb :97` (2000x800), a private tmux `-L` socket, real nnn, `xdotool` for the pointer. The external XDND drop target is a second kitty window at x=1300 (round 1 used `mousepad`; it was dropped because it shows a modal "restore session" dialog after an unclean exit and then refuses every drop). Offers are counted from kitty's own `Sent drag start event to child` line. |

Rig B rebuilt from the round 1 Appendix A recipe. Validity (Fact): `nnn.bak` (pre-fix) reproduces the owner's
symptom on rig A (test `PASS=13 FAIL=31`) and the new build does not.

## Commands run

`$W` = scratch work directory. `new` = scratch build of the reviewed source. `head` = scratch build of the pre-fix source.

| # | Command (shortened) | Result | Status |
|---|---|---|---|
| 1 | `md5sum` of both files, the repo binary, `nnn.bak`; `git diff --stat -- src/nnn.c` | md5s as above; 328 insertions and 52 deletions against the pre-fix source | PASS |
| 2 | Build matrix, new and head: production flags, `+O_NOMOUSE=1`, default, `O_NOMOUSE=1`, `O_NOFIFO O_NOSSN O_NOX11 O_NOUG O_NOBATCH O_NOLC O_NOSORT` (with and without `O_NOMOUSE`), production `+O_DEBUG=1`, `O_NORL=0 O_DND=1`; plus new with the `NCURSES_MOUSE_VERSION <= 1` branch forced on | all exit 0; warnings equal to head (1 for the `O_QSORT` sets, the unused `fuzzyentrycmp`, 0 otherwise); old-ncurses branch compiles, run time Not verified | PASS |
| 3 | `python3 -B -I misc/test/test-dnd-osc72-scope.py --nnn $W/m-new-prod/nnn` | `PASS=44 FAIL=0`, 40 s | PASS |
| 4 | Same test, 3 at a time, 2 rounds, unmutated build | 6 runs, all `PASS=44 FAIL=0` | PASS |
| 5 | `bash misc/test/test-dnd-tmux-mouse.sh` | `PASS=21 FAIL=0` (re-implements the shell snippets, does not run nnn) | PASS |
| 6 | Same scope test against the head build | `PASS=13 FAIL=31` (the orchestrator's numbers reproduced) | PASS |
| 7 | ASan+UBSan build (`-O1 -g -fsanitize=address,undefined`, wrapper sets `ASAN_OPTIONS=detect_leaks=0:log_path=...`) and the scope test | `PASS=44 FAIL=0`; no `asan.log*` or `ubsan.log*` written | PASS |
| 8 | Mutation run: 40 one-line mutants, each built and run through the scope test (3 in parallel); M17, N12, N20 rerun alone | 24 killed, 16 survived (see "Mutation results") | finding (N6) |
| 9 | Rig B, F1: flick, wait T, probe in the shell pane (T = 1.5, 2.5, 3.5 s) | probe offers 1, 0, 0; timeout line logged from 2.5 s | PASS |
| 10 | Rig B, hold before dragging: press, hold H, then drag out (H = 0.5, 1.5, 2.3, 3.2 s) | drag starts for 0.5 and 1.5 s, not for 2.3 and 3.2 s | info (N4) |
| 11 | Rig B, click 0.4 s and 3.5 s after a flick | click lost at 0.4 s, delivered at 3.5 s | info (N4) |
| 12 | Rig B, F2: a second nnn started while the first nnn's native drag is in flight, 2 trials; mutant N07 (`dnd_tmux_drag_live` always false) for contrast | new: drag finishes, mouse restored, click works. N07: no `t=e:x=4` ever, mouse stays off, recovered by the next click's release | PASS |
| 13 | Rig B, grab race: press, 12 px nudge, release D ms later (D = 0, 1, 3, 6, 12, 25, 50 ms, 5 reps each); new vs mutant N09 (detached grab) | new: 0 of 35 stranded. N09: 7 of 35 (D = 0: 4 of 5, D = 1: 3 of 5) | PASS |
| 14 | Rig B, same sweep with an immediate jump out of the window | no offer is sent at all (kitty sees no in-window motion), nothing stranded for either build | info |
| 15 | Rig B, drop on kitty itself (S1 over nnn L, S2 over the shell pane), new vs head | same visible outcome in both; new: flag off, mouse on, marker empty, no `drag never ended`, click works. head: S2 click lost and probe leaks | PASS |
| 16 | Rig B, upgrade: head nnn leaves the flag on; a new nnn is started (visible, then hidden window) | visible: cleared, probe 0. Hidden: probe 1 although the log says "cleared" (N2) | finding |
| 17 | Rig B, bare kitty (no tmux), external drop and a click, head vs new, normalised `NNN_DND_DEBUG` log (16 lines) | identical; head loses the first click, new does not; 4 s of idle added nothing | PASS |
| 18 | Rig B, two nnn: drag L, then R at once, then R again | R's first drag refused, retry works, mouse on, probe 0 (unchanged by design, F4) | info |
| 19 | Rig B, window resize while the button is held, with and without the resize | control: `disarm: release`, probe 0. Resize: no disarm line, probe 1 (N1) | finding |
| 20 | Rig B, a key while the button is held (then keep holding, then also drag), then a click | no offer, `disarm: key`, click delivered, probe 0 | PASS |
| 21 | Rig A scenarios: get_input plus resize plus release; blank row press; resize keeps the arm; reset after a key; hold 1.5 s and 2.6 s; round 1 reproducers; `O_NOMOUSE` build | see "Round 1 findings re-checked" and N1 | PASS |
| 22 | Rig A, default mode (no `NNN_DND_OSC72`) under `strace -f -e trace=execve,clone,vfork`, head vs new | both: 0 OSC-72 sequences, 2 `execve` (strace's `env` and nnn), no child | PASS |
| 23 | Rig A, deferred clear against a peer's arm, hold 0.10 s and 0.45 s, press offsets 0.50 to 1.46 s | arm wiped at offsets 0.94 and 0.98 (hold 0.10), at 0.54 to 0.98 (hold 0.45) (N2) | finding |
| 24 | Rig A, instrumented build that logs how long the blocking spawns take; idle server and a flood in another pane | grab 10 to 16 ms (median 13), `dnd_tmux_drag_live` 2 to 4 ms (median 3), same under the flood | info |
| 25 | Rig A, a `tmux` shim that sleeps 1.5 s, resize during the blocking spawn | the resize is lost (N3) | finding |
| 26 | `probe.c` (ncurses 6.3, X10 mouse, `TERM=tmux-256color`): press, release, reset, stale press cases | a release or press ncurses decodes as motion gives `KEY_MOUSE` with `getmouse() == ERR` (see N5) | PASS |
| 27 | T16 alone, 3 runners x 8 iterations in parallel | 24 of 24 pass | PASS |
| 28 | Rig B, the reported symptom: two nnn running, three text drags and a click in window 2, new vs pre-fix | new: 0 offers, copy mode selects, no text typed, copy-mode `o` never fires. Pre-fix: 4 offers, offer text typed into the pane, `o` fired | PASS |

## Round 1 findings re-checked

| Round 1 item | Status | Evidence |
|---|---|---|
| F1 stale arm (a release that never reaches nnn leaves kitty's flag on) | Fixed, with a residual window | Rig B (command 9): probe in the shell pane 1.5 s after the flick leaks (offers 1, pane in copy mode), 2.5 s and 3.5 s after it does not; the log shows `disarm: no release (timeout)`. The arm lives about 2.0 s (idle ticks come every 1 s, `src/nnn.c:4312`). Rig A reproducer of round 1 with a 4 s wait: `can_offer=False`, probe 0. Residual: a leak is still possible during the first 2 s (by design). |
| F2 wedge (disarm and offers blocked while `g_dnd_b64` is set) | Fixed | Rig B (command 12): new build, peer started mid-drag: the marker names the dragging nnn's pid during the drag, the peer's clear is skipped (`dnd_tmux_drag_live`, `src/nnn.c:4307`), `drag finished` logged, mouse on, marker empty, click works. Mutant N07 shows the wedge on real kitty (no finish, mouse off after the drop) and the F2 release path recovering it at the next click (`drag never ended` logged, mouse on, marker empty). Rig A silent kitty (T13 and round 1 reproducer): flag off, mouse on, marker empty. |
| F2 trigger and Q5 (startup `x=2`) | Partly | The clear moved to the first idle tick, so tmux no longer drops it during the first redraw: rig B upgrade case delivers it in a visible window (command 16, probe 0), and it is skipped while a drag is live (command 12). Still lost in a hidden pane, still races a peer's arm, still consumed when skipped (N2). |
| F3 tests | Partly | Round 1 set: 14 of 19 mutants killed (round 1: 9 of 19). 13 genuine gaps remain among the 40 mutants and one assertion is masked by the timeout (N6). T6 now checks every disarm, T7 asserts the consequence, T10 to T16 are new. |
| F4 first drag from the second nnn is refused | Unchanged by design | Rig B (command 18): R's first drag refused (`offer refused (gesture not armed here)`), the retry works. HEAD dragged the wrong file in round 1. |
| F5 `get_input()` and a release after `KEY_RESIZE` | Fixed | Rig A (command 21): sort prompt, resize, release: prompt still open, no `invalid key`. `src/nnn.c:1686-1706`. |
| F6 arming on blank rows | Fixed | Rig A: press on a blank row and a one-cell move: no arm, no offer. T10. `src/nnn.c:10615-10617`. |
| F7 `O_NOMOUSE` log text | Fixed | Rig A: `enable sent (tmux: no mouse support, no drag-out)`, no arm, no offer. |
| F8 key disarm and `KEY_RESIZE` | Changed, with a side effect | The arm now survives a resize, but ncurses forgets the press on resize, so the release can no longer end it (N1). |
| Q4 comments about the swallowed release | Fixed | The comments at `src/nnn.c:4205-4212`, `:4448-4455` and `:4709` now say a drop OUTSIDE kitty swallows it. Matches rig B: external drop logs `Release ... no window for event`, a drop on kitty itself delivers a release after `XdndFinished`. |
| Q6 `kill -9` of an armed nnn | Not fixed (inherent) | A dead nnn cannot time out. |

## New findings (most severe first)

### N1 - Low - after a window resize the release of a held gesture cannot end the arm

`Fact`. Where: `src/nnn.c:5338-5347` (the key path ignores `KEY_RESIZE`), `src/nnn.c:1622-1626`
(`handle_key_resize()` is `endwin(); refresh();`, which makes ncurses forget that button 1 is down), and
`src/nnn.c:10603-10604` (a `KEY_MOUSE` whose `getmouse()` fails goes to `nochange`, without
`dnd_osc72_release()`).

Defect: a resize during a held gesture is now allowed to keep the arm (round 1 F8). But after the resize
ncurses decodes the later release as motion, so nnn never sees `BUTTON1_RELEASED`. The arm then ends only
at the 2 s timeout, and any text drag in another pane during that time becomes an offer typed into that pane
(the original bug, for up to 2 s).

Reproducer, rig B (command 19): press on `b.txt`, `tmux resize-window -t t:1 -x 150 -y 38`, release,
probe in the shell pane 0.5 s later. Control without the resize: log `armed`, `disarm: release`, probe 0.
With the resize: log `armed` only, probe 1.

Reproducer, rig A (`python3 -B -I repro_resize.py <nnn>` from the repo root, source in Appendix A):

```text
flag 0.5 s after the release: can_offer=True (expected False)
ended by the timeout after 1.5 s more
```

Suggested fix: disarm on `KEY_RESIZE` again (a resize makes the gesture unreliable anyway, and the round 1
cost was only a drag that does not start), or accept the 2 s window and document it. A fix inside
`browse()` is not possible: a failed `getmouse()` looks the same for a lost release and for a press that
ncurses decoded as motion.

### N2 - Low - the deferred startup clear: lost in a hidden pane, can wipe a peer's arm, consumed when skipped

`Fact`. Where: `src/nnn.c:4299-4311` (`dnd_osc72_idle()`, first clause).

1. Lost in a hidden pane. tmux delivers passthrough only for the client's current window
   (`tmux/screen-write.c:134-146`), so a nnn started in a window that is not on show clears nothing, yet logs
   `cleared a leftover drag source` and never retries. Rig B (command 16): head nnn left the flag on; a new
   nnn started in the hidden window `t:2.1`: probe after 3 s gave 1 offer and the log said "cleared". In a
   visible window the same sequence gave probe 0.
2. It can wipe a peer's concurrent arm. The clear runs at the first idle tick, about 1.0 s after a nnn draws
   its list, and it does not know about another nnn's arm. Rig A (command 23): a press-and-hold in nnn R
   whose hold spans that tick loses its arm. Window = from tick minus hold to tick: with a 0.10 s hold the
   presses at 0.94 s and 0.98 s were wiped, with a 0.45 s hold the presses from 0.54 s to 0.98 s. It happens
   once per started nnn and only if the user is clicking in another nnn in that second.
3. `cleared` is set before the conditions are tested (`:4306`), so a first tick that finds this nnn armed or
   a drag live skips the clear for good. T8b relies on this: after the skip the leftover flag stays on until
   some click.

Impact: the only thing at stake is a flag left on by an older nnn until the first click and release in any
nnn. Low.

Suggested fix: log `sent a clear` (delivery is unknowable), and clear again on the first idle tick after
the first key or press (the pane is then on show). To close item 2, send the clear once from `nextsel()`'s
first idle tick only if no key or mouse event arrived in the last second, which is when no gesture can be
in progress in this nnn (it does not help for a peer, so also document it).

### N3 - Low - blocking `spawn()` calls: SIGWINCH and SIGHUP are ignored while nnn waits for tmux

`Fact`. Where: the grab `src/nnn.c:3985` and `dnd_tmux_drag_live()` `src/nnn.c:4282`. `xfork()`
(`src/nnn.c:2850-2860`) sets SIGHUP and SIGWINCH to `SIG_IGN` in the parent until `join()` returns. The
calls used to be detached, so there was no window.

Measured (rig A, instrumented build, `TIMING` lines in `NNN_DND_DEBUG`): the grab blocks nnn for 10 to 16
ms (median 13) per drag, `dnd_tmux_drag_live()` for 2 to 4 ms (median 3), and a flood in another pane
changed nothing. So the window is tiny in normal use.

Reproducer (rig A, command 25): start nnn with `PATH=<dir>:...` where `<dir>/tmux` is
`#!/bin/sh` / `sleep 1.5` / `exec /usr/local/bin/tmux "$@"`. The first idle tick calls
`dnd_tmux_drag_live()` and blocks for 1.5 s (`TIMING drag_live blocked 1509 ms`). A
`tmux resize-window -t t:1 -x 150 -y 24` issued during that second is lost: after the block nnn's last
visible line is a stale `2 b` and there is no entry counter; the control run (no shim) shows
`2/3  2026-10-23 12:11 -rw-rw-r-- ...` on the last line.

Also: nnn is unresponsive for as long as the tmux server does not answer a command (same as any blocking
child, but new in the input loop).

Suggested fix: after a blocking spawn compare `LINES`/`COLS` with `ioctl(TIOCGWINSZ)` and call
`handle_key_resize()` if they differ, or give the two scripts a short timeout (`timeout 1 sh -c`).

### N4 - Info - two costs of the 2 s arm lifetime, measured

`Fact`, rig B (commands 10 and 11).
- Hold before dragging: press, hold 0.5 s or 1.5 s, then drag out: the drag starts. Hold 2.3 s or 3.2 s: no
  offer (`disarm: no release (timeout)` already logged). HEAD had no such limit. `Open question`: is 2 s
  acceptable for the owner's drag habits? A 3 to 5 s limit costs only a longer leak window after a lost
  release (F1) and after a resize (N1).
- A click within about 2 s after a lost release is swallowed (ncurses still has button 1 down; the reset
  only happens at the timeout or at a key). Click 0.4 s after a flick: cursor stays on `a.txt`. 3.5 s
  after: it moves. HEAD loses that click too (pre-existing), and a key in between resets it at once (rig
  A, command 21: flick, `k`, click: delivered).

### N5 - Info - the `REPORT_MOUSE_POSITION` branches are dead code

`Fact`. `src/nnn.c:4337` and `src/nnn.c:5642` test for `REPORT_MOUSE_POSITION`, but nnn's mask never
contains it, and ncurses 6.3 drops filtered events from its queue: `probe.c` (command 26) shows `KEY_MOUSE`
followed by `getmouse() == ERR` and `bstate == 0` for a release after a reset, for a release with no press,
and for a press decoded as motion. The `getmouse() != OK` branch at `:4333` does the work. Harmless; mutants
N06 and N21 are equivalent.

### N6 - Medium (test) - the new test leaves gaps, and the timeout masks one assertion

`Fact`, command 8 and the table below. Details:

1. Survivors that are real gaps (13): M06, M12, M13, M17, N03, N10, N11, N12, N14, N15, N16, N17, N20.
   Not covered: the filter prompt's `BUTTON1_RELEASED` path (M06), the exit-time `x=2` in tmux (M12), the
   in-flight guard in `dnd_osc72_disarm()` (M13), the "nothing to drag" disarm (M17), the key-path reset
   (N03), the self-drop timestamp set by the release path (N10), a resize inside `get_input()` (N11) and
   at the key disarm (N12), the timeout skip for an in-flight or peer drag (N14, N15), the clear skip for
   an own arm (N16), the idle tick in bare kitty (N17), the bottom-row bound (N20).
2. T15 does not test what it says. T14 and T15 press, type a key, then release. The key resets ncurses
   (`:5345`), so the release always decodes as motion and arrives as `KEY_MOUSE` with a failed `getmouse()`;
   the `BUTTON1_RELEASED` branch in `filterentries()` is never reached, which is why mutant M06 survives.
   A click on the bottom rows opens the filter prompt on the press with no key in between. Reproducer
   (`python3 -B -I repro_clickfilter.py <nnn>`, Appendix A): new build prints `prompt unchanged by the
   release: True`, mutant M06 prints `False`.
3. The 2 s timeout masks the drop-time disarm. Mutant M14 (no disarm on `t=e:x=4`) passes T3, T3b and T4b:
   the arm ends by the timeout inside the 2 s wait of `drag_out()` (`k.pump_until(lambda: not k.can_offer,
   2)`) and `'t=o:x=2' in seq` is satisfied by the timeout's `x=2`. In M14's own log: `drag finished` at
   22.423, `disarm: no release (timeout)` at 24.430. Only T12 kills M14. Fix: assert the log line
   `disarm: drag finished` (like T11, T12 and T13 do) or wait less than the timeout.
4. Load sensitivity. T16 appeared among the failures of 6 of the 40 three-parallel mutant runs (M10, M17,
   N07, N08, N12, N20). M17, N12 and N20 passed when rerun alone (flakes), so T16 is load-sensitive; for the
   other three a mutation effect cannot be excluded. The unmutated build passed 6 of 6 three-parallel full
   runs and T16 alone passed 24 of 24 in three parallel runners, so the flake is rare and its cause was not
   isolated (`Not verified`).
5. EPERM cannot be produced by real kitty on X11. T11 models a refusal with `t=E;EPERM`. On rig B nothing
   refuses: a jump out of the window sends no offer at all (command 14) and a release 0 ms after the
   offer-triggering motion still starts the drag. The race that T11 guards is real on X11 only as a quick
   drag (command 13, mutant N09: 7 of 35 stranded), and T11 does kill N09, so it works as a proxy. A test
   that releases right after a started drag (fake: `started` then an immediate release) would model the
   X11 case directly.

Suggested additions, in order of value: the click-on-bottom-row filter case (M06), assertions on log
lines for the three drop-time disarms (M14), a key-path reset case (flick, key, immediate click on
another row: cursor must move; N03), a resize inside a prompt (N11, N12), a drag in flight with an armed
peer past 2 s (N14, N15), and a stale arm in bare kitty (N17).

## Mutation results

Method: each mutant is a one-line change to a scratch copy of the reviewed `nnn.c`, built with the production
flags and run through `misc/test/test-dnd-osc72-scope.py` (3 in parallel, `TMPDIR` inside the scratch area).
M17, N12 and N20 were reported killed by T16 in the parallel run and survived when rerun alone, so they are
counted as survivors. "Tests" lists the first failing checks; T16 (and once T14) can appear for load reasons (N6.4).

| Mutant | Result | Tests |
|---|---|---|
| M01 no `mousemask()` reset after a finished drag | killed | T3b |
| M02 no disarm on release in `browse()` | killed | T5, T6, T7 |
| M03 no startup clear | killed | T8 |
| M04 no refusal of an offer when not armed | killed | T4a, T4b |
| M05 `get_input()` does not eat releases | killed | T14 |
| M06 filter prompt does not eat releases | SURVIVED | none (N6.2) |
| M07 no disarm on a key | killed | T7b, T14, T15 |
| M08 no disarm before a subprocess | killed | T16 |
| M09 no disarm in resync | SURVIVED | none (redundant with M08's line) |
| M10 arm on any row | killed | T10, T11 (and T16) |
| M11 release not subscribed | killed | T5, T6, T7 |
| M12 `dnd_osc72_disable()` always sends `x=2` in tmux | SURVIVED | none |
| M13 `dnd_osc72_disarm()` ignores an in-flight drag | SURVIVED | none |
| M14 no disarm on `t=e:x=4` | killed | T12 only (masked in T3, N6.3) |
| M15 no disarm on a refused drag | killed | T11 |
| M16 no disarm on an ignored offer | killed | T12 |
| M17 no disarm on "nothing to drag" | SURVIVED | none |
| M18 bare kitty: no startup `x=1` | killed | T9 |
| M19 arm does not set `g_dnd_armed` | killed | T3, T3b |
| N01 idle timeout disarm removed | killed | T7, T7b |
| N02 no reset after the timeout | killed | T7b |
| N03 no reset in the key path | SURVIVED | none |
| N04 release does not drop a dead drag | killed | T13 (and T14) |
| N05 failed `getmouse()` not consumed in `dnd_eat_release()` | killed | T14 |
| N06 motion reports not consumed in `dnd_eat_release()` | SURVIVED | none (dead code, N5) |
| N07 `dnd_tmux_drag_live()` always false | killed | T8b (and T16) |
| N08 `dnd_tmux_drag_live()` always true | killed | T7, T7b |
| N09 grab detached again (`F_NOWAIT`) | killed | T11, T13, T8 |
| N10 release does not set the self-drop timestamp | SURVIVED | none |
| N11 `get_input()` does not skip `KEY_RESIZE` | SURVIVED | none |
| N12 key disarm fires on `KEY_RESIZE` again | SURVIVED | none |
| N13 timeout 20 s instead of 2 s | killed | T7, T7b |
| N14 timeout ignores an in-flight drag | SURVIVED | none |
| N15 timeout ignores a live peer drag | SURVIVED | none |
| N16 clear ignores own arm | SURVIVED | none |
| N17 idle tick runs in bare kitty too | SURVIVED | none |
| N18 arm lacks the `ndents` bound only | killed | T10, T11 |
| N19 idle tick not called | killed | T7, T7b, T8 |
| N20 bottom-row bound `xlines - 3` removed | SURVIVED | none |
| N21 filter prompt: motion reports end the prompt | SURVIVED | none (dead code, N5) |

Totals: 40 mutants, 24 killed, 16 survived (13 real gaps, 2 dead-code equivalents N06 and N21, 1 redundant
layer M09). Round 1 set (M01 to M19): 14 killed, 5 survived (M06, M09, M12, M13, M17).

## Questions

1. `Open question`: is a 2 s arm lifetime right (N4)? Holding the button 2 s before dragging gives no
   drag; 3 to 5 s would widen the leaks of F1 and N1 by the same amount.
2. `Open question`: should a resize disarm (N1)? The round 1 F8 reason (the drag would not start) is
   weaker than the leak window it opens.
3. `Not verified`: Wayland (kitty's own comment says an OS drag can be silently ignored there, which is the
   F2 case the release path now recovers), macOS and BSD, other tmux versions, a busy tmux server beyond a
   `yes` flood, the old-ncurses mouse branch at run time, kitty with a hardware GL driver.
4. `Observation` (not part of the change): dropping a dragged file back onto the kitty window shows
   `dnd: cancelled` in nnn 60 ms after the release, in both the pre-fix and the new build (rig B, command
   15): the copy or move prompt of the paste fallback is answered by something at once. Pre-existing.

## Verified OK

| Check | Evidence |
|---|---|
| Reported symptom | Rig A tests T1 and T2; rig B command 28 (new: 0 offers and no garbage; pre-fix: 4 offers, garbage typed, `o` fired) |
| F1 and F2 on real kitty | Commands 9, 12 |
| Grab race fix | Command 13: new 0 of 35, previous design 7 of 35 stranded |
| Idle tick cost | Command 24: 2 to 4 ms per call, once at startup and once per second only while armed past 2 s |
| Key path reset while the button is held | Command 20: no offer, `disarm: key`, no lost click afterwards |
| Self-drop | Command 15: no `drag never ended` misfire, flag off, mouse on, same visible state as before |
| Peer drag protection | Command 12 (rig B) and T8b (rig A) |
| Bare kitty | Command 17: identical outbound stream, no idle traffic, first click now works |
| Default mode | Command 22: silent |
| Prompts | T14, T15, command 21 (resize inside `get_input()`), click-on-bottom-row filter case |
| Builds and sanitizers | Commands 2, 7 |
| Test isolation | Only `-L` sockets named `nnn-dnd-scope-<pid>` and `r2-*`, `HOME` in scratch, display `:97` |

## Cleanup record

Created by the reviewer and removed at the end (checked by listing afterwards): `$SCR/r2-work` (builds,
mutants, ASan, instrumented build, rig B scripts and scratch dirs, screenshots, probe), `$SCR/r2-diff-head.txt`,
the private `Xvfb :97`, the target kitty and every kitty started on `:97`, the mousepad and D-Bus session
helpers started early in the round, orphaned scratch `nnn` processes, and the dead `r2-*` and
`nnn-dnd-scope-*` tmux socket files created in `/tmp/tmux-1000`. Not touched: `$SCR/kitty-src`,
`$SCR/ncurses` and the other items the orchestrator left in `$SCR`, the owner's tmux `default` socket, kitty
on `:1`, the live nnn processes, `nnn.bak-2026-10-23-pre-dnd-scope`, the repo. Side effect that cannot be
undone: OpenGL under Xvfb may have written to the shared Mesa shader cache (`~/.cache/mesa_shader_cache_db`).

## Appendix A - reproducers (rig A, run from the repo root with `python3 -B -I`)

`repro_resize.py` (N1):

```python
import importlib.util, os, sys, tempfile, shutil, time
spec = importlib.util.spec_from_file_location('scope', 'misc/test/test-dnd-osc72-scope.py')
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)
nnn = os.path.abspath(sys.argv[1])
S = tempfile.mkdtemp(prefix='rev-rz.')
r = H.Run(nnn, S)
try:
    r.setup()
    r.start_nnn('t:1.1')
    k = r.k
    r.tmux('select-window', '-t', 't:1')
    r.tmux('select-pane', '-t', 't:1.1')
    k.pump(0.3)
    col, row = r.row_of('t:1.1', 'b.txt')
    k.press(col, row)
    k.pump_until(lambda: k.can_offer, 1)
    r.tmux('resize-window', '-t', 't:1', '-x', '150', '-y', '38')   # nnn: KEY_RESIZE -> endwin() + refresh()
    k.pump(0.6)
    col, row = r.row_of('t:1.1', 'b.txt')
    k.release(col, row)
    k.pump(0.5)
    print('flag 0.5 s after the release: can_offer=%s (expected False)' % k.can_offer)
    t = time.monotonic()
    k.pump_until(lambda: not k.can_offer, 4)
    print('ended by the timeout after %.1f s more' % (time.monotonic() - t))
finally:
    r.teardown()
    shutil.rmtree(S, ignore_errors=True)
```

`repro_clickfilter.py` (N6.2): same preamble, then:

```python
    r.setup()
    r.start_nnn('t:1.1')
    k = r.k
    r.tmux('select-window', '-t', 't:1')
    r.tmux('select-pane', '-t', 't:1.1')
    k.pump(0.4)
    x, y, w, h = r.geom('t:1.1')
    k.press(x + 3, y + h - 2)       # a press on the bottom rows opens the filter prompt, no key in between
    k.pump(0.3)
    before = r.bottom('t:1.1')
    k.release(x + 3, y + h - 2)     # its release reaches the prompt as BUTTON1_RELEASED
    k.pump(0.5)
    print('prompt unchanged by the release: %s (expected True)' % (before == r.bottom('t:1.1')))
```

Rig B recipe, as in round 1 (Appendix A there), with these changes: the drop target is a second kitty
(`kitty --class r2-target -o initial_window_width=700 -o initial_window_height=700 cat -v`, moved to x=1300
with `xdotool windowmove`), offers are counted from kitty's `--debug-input` line `Sent drag start event to
child`, a drag that the target accepted ends with `t=e:x=4:y=0` in nnn's log (`y=1` is a cancelled drag),
and the flag is probed with a plain text drag in the shell pane (offers there mean kitty's flag is on).
