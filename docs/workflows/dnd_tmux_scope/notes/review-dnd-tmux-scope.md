# Review: OSC-72 drag-source scope fix (uncommitted `src/nnn.c` and `misc/test/test-dnd-osc72-scope.py`)

## Purpose

This is an independent review of one uncommitted change: nnn now arms kitty's OSC-72
drag-source flag only for a left-button gesture that starts on its own list (inside tmux), and
disarms it when the gesture ends. The reviewer read the real diff, built it in a scratch copy,
ran the repo tests, and re-ran the owner's scenario on a real kitty.

Scope: correctness bugs and regressions in `src/nnn.c` and in the new test. The repo, the
owner's live tmux server (default socket, display `:1`) and the running nnn processes were not
touched. Nothing in the repo was edited except this report.

Labels used: `Fact` (checked by a command or by reading the code), `Assumption` (inferred, not
checked), `Risk`, `Open question`, `Not verified`.

## Verdict

| Area | Result |
|---|---|
| Reported symptom (selection freeze, garbage on next click) | Fixed. Verified on a real kitty 0.49.2 + tmux 3.7b + nnn rig. The HEAD binary reproduces it on the same rig. |
| Drag-out of files from nnn to an external GUI app (tmux) | Works end to end (arm, offer, agree, XDND drop, `t=e:x=4`, disarm). |
| Bare kitty (no tmux) | Outbound OSC-72 stream is identical to HEAD. One behaviour change: the `mousemask()` reset after a drag (fixes a lost first click). |
| Builds | 9 variants of the working tree compile clean (7 of them also built from HEAD: same warnings). ASan/UBSan run is clean. |
| Repo tests | `test-dnd-osc72-scope.py` PASS=30 FAIL=0. `test-dnd-tmux-mouse.sh` PASS=21 FAIL=0. HEAD binary: PASS=11 FAIL=19 (the test does detect the bug). |
| Defects | 2 Medium design-level gaps that leave kitty's flag ON (F1, F2), 1 Medium test-coverage gap (F3), 4 Low items (F4-F7), 1 Info item (F8). No crash, no memory error, no regression in normal flows found. |

## What was reviewed

| Item | Value |
|---|---|
| `src/nnn.c` md5 | `d7ea91445fc84c8ec4b535dedfd6c496` (unchanged during the review) |
| Repo `nnn` binary md5 | `091a1a9462e8733bd4006efa8d8ded00`, byte-identical to the reviewer's scratch build of that source |
| Test file | `misc/test/test-dnd-osc72-scope.py` (md5 `0a86ff792a43f2acf47e98fc3fd0517d`) |
| Stack | kitty 0.49.2, tmux 3.7b (byte-identical to `~/Dev/Playground_Terminal/tmux/tmux`), libncursesw 6.3, gcc 11.5, Linux 6.8.0-138 |

## Test rigs

| Rig | What it is | Used for |
|---|---|---|
| A: fake kitty | The repo's own `FakeKitty`/`Run` harness (real tmux 3.7b and real nnn, fake outer terminal in a pty). Loaded unchanged as a module for scratch scenarios. | Fast scenarios, mutation testing, reproducers that need no X server. |
| B: real kitty | Real kitty 0.49.2 (`~/.local/kitty.app`, `--debug-input`) on a private `Xvfb :97` (2000x800), a private tmux `-L` socket, real nnn, `xdotool` for the pointer, and `mousepad` (GTK3) as an external XDND drop target moved outside the kitty window. Ground truth for offers: the line `Sent drag start event to child` in kitty's debug log. | Everything that depends on kitty's real timing and on a real drop. |

Rig validity (Fact): the HEAD binary reproduces the owner's symptom on both rigs. Rig A: T1 fails
with `:x=3:y=5:X=35:Y=110^[\72;t=o:x=21:y=8:X=215:Y=170^[\` typed into the pane. Rig B: the same
shape of text is typed (`:x=3:y=5:X=28:Y=93^[\72;t=o:x=21:y=8:X=175:Y=144^[\`) and kitty logs 2
offers.

Isolation (Fact): rig B used `DISPLAY=:97`, private `XDG_*` directories, its own tmux socket
names (`rev-*`, `nnn-dnd-scope-<pid>`) and `HOME` inside a scratch directory for nnn. Rig A and B
processes were killed by the reviewer (see "Cleanup record").

## Commands run

`$SCR` = the session scratchpad. `$S` = scratch copy of `Makefile` + `src/` made with
`mktemp -d`. `$W` = scratch work directory. HEAD = `git show HEAD:src/nnn.c` in a second scratch copy.

| # | Command (shortened paths) | Result | Status |
|---|---|---|---|
| 1 | `git -C <repo> diff --stat -- src/nnn.c` and `git diff -- src/nnn.c` | 212 insertions, 39 deletions in `src/nnn.c` | read |
| 2 | `make -C $S -j8 O_EMOJI=1 O_PCRE2=1 O_QSORT=1 O_SSN_ON_CD=1 O_SSN_PIPE=1 O_FZ_CPMV=1 O_HIST=1 O_DND=1` | exit 0, 1 warning (`fuzzyentrycmp` unused, also present in HEAD) | PASS |
| 3 | Build matrix: production flags, +`O_NOMOUSE=1`, default flags, `O_NOMOUSE=1`, `O_NOFIFO O_NOSSN O_NOX11 O_NOUG O_NOBATCH O_NOLC O_NOSORT` (with and without `O_NOMOUSE`), production +`O_DEBUG=1`; each for the working tree and for HEAD (14 builds) | all exit 0, warning counts equal between tree and HEAD | PASS |
| 4 | Working tree built with the `NCURSES_MOUSE_VERSION <= 1` branch forced on (`sed 's/^#if NCURSES_MOUSE_VERSION <= 1$/#if 1/'`), production flags | compiles; runtime Not verified | PASS (compile only) |
| 5 | `make O_NORL=0 O_DND=1` (readline build) | exit 0, 0 warnings | PASS |
| 6 | `python3 -I misc/test/test-dnd-osc72-scope.py --nnn $S/nnn` | `PASS=30 FAIL=0`, 24 s | PASS |
| 7 | `bash misc/test/test-dnd-tmux-mouse.sh` | `PASS=21 FAIL=0` (this script re-implements the shell snippets; it does not run nnn) | PASS |
| 8 | Same scope test against the HEAD build | `PASS=11 FAIL=19`, exit 1 (T0, T1, T2, T3, T4a/b, T5, T6 fail) | PASS (the test detects the bug) |
| 9 | ASan+UBSan build (`cc ... -O1 -g -fsanitize=address,undefined`, wrapper script sets `ASAN_OPTIONS=detect_leaks=0:log_path=...`) and the scope test | `PASS=30 FAIL=0`; no `asan.log*`/`ubsan.log*` file written | PASS |
| 10 | Mutation run: 19 one-line mutations of the new code, each built and run through the scope test (3 in parallel) | 9 killed, 10 survived (see F3) | finding |
| 11 | Stress: 150 press/release cycles in the dual-nnn window, random hold 0-250 ms, random gap 0-400 ms, random pane and file (rig A) | 0 lost arms, 0 lost disarms; disarm latency min 0.06, median 0.42, max 1.50 ms | PASS |
| 12 | Prompt scenarios (rig A): press on a file, key opens a prompt, then the release arrives: `t` (sort), `n` (new), `n f` (name prompt), `/` (filter), `f` (stats window), `D` (drag-drop prompt) | prompt still open after the release in all six; flag off | PASS |
| 13 | Double-click on a directory; presses on the context row, the last row and row `xlines-3` (rig A) | directory entered, flag off; the three non-list presses do not arm | PASS |
| 14 | Real kitty smoke test: T1 text drag in window 2, then drag `a.txt` out of nnn L | new: no offer in T1, 1 offer in T3, `drag finished` + `disarm: drag finished`. HEAD: 2 offers and garbage in T1 | PASS (new) |
| 15 | Real kitty, external drop on `mousepad`: drag `a.txt` from nnn L | offer sent, XDND drop, `mousepad` opened `.../files/a.txt`, nnn logged `drag finished` and disarmed | PASS |
| 16 | Real kitty, first click after the external drop (new, HEAD, mutant without the `mousemask()` reset) | new: cursor moves to the clicked row. HEAD and the mutant: click lost | PASS (new) |
| 17 | Real kitty, bare (no tmux), external drop, normalised `NNN_DND_DEBUG` log, HEAD vs new | outbound OSC-72 sequence list identical; first click after the drop lost in HEAD, works in new | PASS |
| 18 | Real kitty, race: press then first 12 px move after a delay `D` (xdotool), 6 drags per delay | `D`=0 ms: 0/6 start; 2 ms: 5/6; 4, 8, 15, 30, 60 ms: 6/6 | info (F1) |
| 19 | Real kitty, stale arm (F1 reproducers S4, S5 leak; S1, S2, S3 recover) | see F1 | finding |
| 20 | Real kitty, second nnn started while the first nnn's native drag is in flight, 3 trials | see F2 | finding |
| 21 | Fake-kitty reproducers `repro_stale_arm.py`, `repro_wedge.py` (sources in Appendix B) | both show the bug on the working tree | finding |
| 22 | Scratch copy with the suggested fixes (Appendix C): both reproducers, the scope test, real-kitty S4 with a 3 s wait, real-kitty external drop and drop on kitty itself | reproducers pass, scope test `PASS=30 FAIL=0`, real S4: 0 offers, real drops still end with `drag finished`, disarm and a working first click | PASS |
| 23 | Rig A, `nnn -c` with `NNN_OPENER` = a script that runs `sleep 3`; double-click a file; read the flag while the opener runs and after nnn resumes; repeat for mutants M08, M09, M08+M09 | working tree: OFF during and after. M08: ON during, OFF after (resync). M09: OFF. M08+M09: ON during and after | PASS |

## Findings (most severe first)

### F1 - Medium - kitty's flag stays ON when the arming press never gets its release

`Fact`. Where: arm at `src/nnn.c:4202-4210` (`dnd_osc72_arm()`), called from `src/nnn.c:10513-10514`.
The only disarms are: a release that reaches nnn (`src/nnn.c:10509-10512`, `:4231-4240`,
`:5538-5541`), any key (`:5248-5249`), `t=e:x=4` (`:4607`), a `t=E` error (`:4627`), an ignored or
empty offer (`:4367`, `:4372`), a subprocess (`:2952`), a resync (`:4764`), and exit (`:4740`).

Defect: tmux sends a release to the pane under the pointer, not to the pane that got the press
(`tmux/server-client.c:909-914`: drag events reuse the last pane, a release uses
`window_get_active_at()`). If the pointer is outside nnn's pane at the release, nnn never sees it,
`g_dnd_armed` stays TRUE and kitty's flag stays ON. kitty decides once, at the first pointer
sample more than 5 px from the press (`kitty/mouse.c:667-671`, called at `:724`). When the arm has
not arrived by then, no offer is sent, so a quick drag that leaves nnn's pane is not an OS drag
and the arm survives. Every later text drag in another pane then produces an offer typed into
that pane, which is the owner's original bug.

Measured race (`Fact`, rig B, idle 22-core machine): the arm needs a head start of about 2-4 ms.
Press then first motion after 0 ms: 0/6 drags start; 2 ms: 5/6; 4 ms and more: 6/6. Whether a
busy nnn (large directory, slow `stat`) loses the race at human speed is an `Assumption`, not
measured.

Reproducer, rig A (no X server; run from the repo root, source in Appendix B):
`python3 -B -I repro_stale_arm.py <nnn>`. Output on the working tree:

```text
after the flick: can_offer=True (expected False)
plain drag in the shell pane: offers=1 (expected 0)
```

Reproducer, rig B (real kitty), `xdotool` chain, then a drag in the shell pane:

```bash
xdotool mousemove <a.txt cell> sleep 0.15 mousedown 1 mousemove_relative -- 30 0 \
        mousemove <cell in the shell pane> sleep 0.1 mouseup 1
```

| Case | Next action | kitty offers in the probe drag in the shell pane |
|---|---|---|
| S4 | none | 1, and the pane enters copy mode (the leak) |
| S5 | plain click in the shell pane | 1 (a click outside nnn does not repair it) |
| S1 | a key in nnn | 0 |
| S2 | a click in the arming nnn | 0 |
| S3 | a click in the other nnn | 0 (kitty's flag is shared; by code reading the first nnn stays locally armed) |

Second-order effect (`Fact` for the drop, `Assumption` for the cause): after the first leak the
offer text `:x=...` opens a copy-mode prompt. A later key in nnn then logged `disarm: key`, but
the passthrough `t=o:x=2` never reached the outer terminal (tmux `-vv`: `input_dcs_dispatch` ran,
no `screen_write_set_client_cb` call, no `t=o:x=2` in `tmux-out`), and the next probe still got an
offer. The likely cause is `tty_client_ready()` returning 0 while the status prompt freezes the
client (`tmux/status.c:734`, `tmux/tty.c:1620`). So once a leak has happened, "press a key in nnn"
does not repair kitty.

Note: T7 in the new test (`misc/test/test-dnd-osc72-scope.py:408-424`) already prints
`stale arm after the lost race = True (known limit)` and passes. The consequence (an offer typed
into another pane) is not asserted.

Suggested fix: bound the life of an arm. Record `clock_gettime(DND_CLOCK, ...)` in
`dnd_osc72_arm()`. `nextsel()` already wakes every second (the `if (i == ERR) {` block at `:5258-5259`); there,
disarm when `g_dnd_armed && !g_dnd_b64` and the arm is older than about 2 s
(`dnd_osc72_disarm("disarm: timeout")`). Validated on a scratch copy (Appendix C): rig A
reproducer with a 3.5 s wait gives `can_offer=False` and 0 offers; rig B S4 with a 3 s wait gives
0 offers (unpatched: 1); the scope test stays `PASS=30 FAIL=0`. Trade-off: a drag that starts
moving more than the timeout after the press loses its offer (raise the timeout to 3-5 s if wanted).

### F2 - Medium (low probability on X11) - disarm and offers are blocked while `g_dnd_b64` is set, and nothing clears it if kitty never reports the end

`Fact`. Where: guard at `src/nnn.c:4218` (`if (!g_dnd_armed || g_dnd_b64) return;`), ignored offer
at `:4360-4363`, `g_dnd_b64` is cleared only by `t=e:x=4` (`:4605`), a `t=E` error (`:4623-4624`)
and a resync (`:4763`). The startup clear that can trigger it is at `:4707-4709`.

Defect: if kitty never sends `t=e:x=4` or `t=E`, the instance is wedged for good. Every later
release or key skips the disarm, every later offer is answered with "ignored", and kitty's flag
stays ON, so text drags in other panes leak. Two ways to get there:

1. kitty frees the offer while the OS drag is in flight and then stops reporting. `Fact` (read):
   any `t=o:x=2` calls `drag_free_offer()` (`kitty/dnd.c:1544-1548`), and `drag_notify()` returns
   at once when `ds.state < DRAG_SOURCE_STARTED` (`kitty/dnd.c:1862`), so `t=e:x=4` is never sent.
   A peer nnn that starts during the drag sends exactly that `t=o:x=2` (the startup clear at
   `:4707`); so does an unarmed peer refusing an offer (`:4355-4358`) and a peer exiting while armed.
2. The OS drag is silently ignored. `Fact` (read): kitty's own comment says the compositor can
   ignore a drag start (`kitty/mouse.c:975-978`, Wayland stale serial). Not verified on Wayland;
   the owner's session is X11.

Reproducer 1, rig B (3 of 3 trials): hold the button over `mousepad` after the offer was
answered, `tmux respawn-pane` a new nnn in the shell pane, then release. Result each time: the
drop still delivered the file, but the first nnn never logged `drag finished`, and the next press
in that nnn produced no `armed` line and no offer within 1.2 s. `Assumption`: tmux `mouse` was
still off from `dnd_grab_tmux_mouse()` until its 60 s watchdog (`show -gv mouse` was not read in
this run).

Reproducer 2, rig A (source in Appendix B): `python3 -B -I repro_wedge.py <nnn>`. kitty answers the
drag start with `t=E:m=0;OK`, then never starts an OS drag; the release is delivered. Output:

```text
after drag + release: can_offer=True (expected False)
after a click in nnn:  can_offer=True (expected False)
after a key in nnn:    can_offer=True (expected False)
```

The EPERM path is fine (`Fact`, rig A with kitty answering `t=E;EPERM:...`): nnn clears and
disarms (`:4623-4627`), the flag is OFF, a later probe drag in another pane gets 0 offers.

Suggested fix: a release that reaches nnn proves the pointer is not inside an OS drag (kitty
consumes it: `kitty/mouse.c:975`), so on the three release paths clear the dead drag before
disarming. Scratch patch: a helper `dnd_osc72_release_disarm()` that calls `dnd_clear_data()` when
`g_dnd_armed && g_dnd_b64`, then `dnd_osc72_disarm("disarm: release")`, used at `:4238`, `:5539`
and `:10510`. Also treat a new offer that arrives while `g_dnd_b64` is set as proof that the old
drag is dead. Validated: `repro_wedge.py` gives `can_offer=False` in all three steps and the scope
test stays `PASS=30 FAIL=0`.

### F3 - Medium - the new test leaves 10 of 19 mutations of the new code alive

`Fact`. Each mutation was applied to a scratch copy, built, and run through
`misc/test/test-dnd-osc72-scope.py` (command 10).

| Mutation | Result | Caught by |
|---|---|---|
| M01 drop `mousemask(g_mousemask, NULL)` after a drag (`:4615`) | killed | T3b |
| M02 no disarm on release in `browse()` (`:10510`) | killed | T5, T7 |
| M03 no startup `x=2` (`:4708`) | killed | T8 |
| M04 no refusal of an offer when not armed (`:4355`) | killed | T4a, T4b |
| M07 no disarm on a key (`:5249`) | killed | T7 |
| M11 `BUTTON1_RELEASED` not subscribed (`:2700`) | killed | T5, T7 |
| M14 no disarm on `t=e:x=4` (`:4607`) | killed | T3, T3b, T4a |
| M18 bare kitty: no startup `x=1` | killed | T9 |
| M19 arm does not set `g_dnd_armed` (`:4207`) | killed | T3, T3b |
| M05 `get_input()` does not eat releases (`:1688`) | SURVIVED | none |
| M06 filter prompt does not eat releases (`:5538-5541`) | SURVIVED | none |
| M08 no disarm before a subprocess (`:2952`) | SURVIVED | none |
| M09 no disarm in `dnd_osc72_resync()` (`:4764`) | SURVIVED | none |
| M10 arm on any row, not only the list rows (`:10513`) | SURVIVED | none |
| M12 `dnd_osc72_disable()` always sends `x=2` in tmux (`:4740`) | SURVIVED | none |
| M13 drop the `g_dnd_b64` guard in `dnd_osc72_disarm()` (`:4218`) | SURVIVED | none |
| M15 no disarm on a refused drag (`:4627`) | SURVIVED | none |
| M16 no disarm on an ignored offer (`:4367`) | SURVIVED | none |
| M17 no disarm on "nothing to drag" (`:4372`) | SURVIVED | none |

Run-time checks (commands 12, 13, 23 and the EPERM reproducer) show that the behaviours behind
M05, M06, M08, M09, M10 and M15 are correct today, so these are missing tests, not bugs. M08 and
M09 are one safety net in two layers: with only M08 the flag stays ON while a CLI opener runs, with
both removed it stays ON after nnn resumes. M12, M13, M16 and M17 were read, not exercised
(`Not verified` at run time; see F2 for M13).

Fidelity of `FakeKitty` against `kitty/mouse.c` (`Fact` unless marked):

| Aspect | Fake | Real kitty 0.49.2 | Effect |
|---|---|---|---|
| Decision point | first `move()` of a whole cell (10 px) | first pointer sample more than 5 px away, usually inside the pressed cell (`mouse.c:667-671`) | the real race window is tighter than T6 and T7 suggest |
| Arm latency in T6 | 0.5-1.2 ms between the fake and nnn | about 2-4 ms head start needed (rig B) | T6's numbers do not include kitty's loop |
| Release after an OS drag | always swallowed, `t=e:x=4` follows at once | external drop: swallowed (`Release ... no window for event` in `--debug-input`); drop on kitty itself: delivered after `XdndFinished` | T3b and T4a model the external-drop case only; the `mousemask()` reset is needed there (command 16) |
| `t=o:x=2` during a drag | sets `drag_state=None`, then a normal release is delivered | frees the offer and suppresses `t=e:x=4` | F2 is not modelled by the fake |
| T6 | counts arms only | | a lost disarm shows up only as a zero latency in the next round, never as a failure |
| T7 | prints the stale arm | | does not assert on the leak (F1) |

Suggested tests to add: (a) F1: after the T7 flick, wait past the timeout, then assert a drag in
`t:1.3` yields 0 offers; (b) F2: the `SilentKitty` case from Appendix B; (c) a prompt case
(`t` or `n`, then a release) and a filter case (`/`, then a release); (d) a press on the blank
rows below the entries must not arm (see F6); (e) a `t=E;EPERM` case; (f) disarm before a
subprocess (open a file with a CLI opener) and after it returns.

### F4 - Low - the first drag from the second nnn after a drag from the first is silently refused

`Fact` (rig B, external drop target, new binary): after a drag from nnn L, a drag from nnn R
produced one kitty offer, which the active pane (L) refused: `offer refused (gesture not armed
here)` at `src/nnn.c:4355-4358`. R's retry works. The cause is tmux: the OS drag swallowed the
release, so tmux treats the next press as the end of the old drag and does not select R. This is
the scenario of T4a and it is documented there. The HEAD binary answered the same offer from L
with L's hovered file: the files offered in order were `a.txt, a.txt, a.txt` for the drags L, L,
R-meant-`b.txt`. So the guard turns a wrong-file drag into a lost drag. Low because it is a known,
documented cost and a retry works. In the rig-B run with a drop on kitty itself (no external
window) the quirk did not occur; `Assumption`: because kitty then delivers a release after
`XdndFinished` (visible in its `--debug-input` log).

### F5 - Low - `get_input()` does not eat a release that arrives after `KEY_RESIZE`

`Fact`. `src/nnn.c:1688` eats releases for the first read only; the `KEY_RESIZE` loop at
`:1695-1703` reads with a plain `get_wch(ch)`. Reproducer (rig A): press on a file (arms), `t`
(sort prompt opens), `tmux resize-window -x 150 -y 38`, then deliver the release. Result: the
prompt is gone and `invalid key` is shown. The window needs a resize while a prompt is open and a
gesture is pending, so this is rare. Fix: run the eat loop around the resize loop as well, for
example `do { get_wch(ch); } while ((*ch == KEY_RESIZE ...) || (release eaten))`.

### F6 - Low - arming covers the blank rows below the last entry

`Fact`. `src/nnn.c:10513` arms for `event.y >= 2 && event.y < xlines - 3`, while the click
handler in the same function uses `event.y <= ndents + 1` for "a file was clicked". Reproducer
(rig A): press on a blank row of a 3-entry directory and move one cell. Result: `offers=1`, the
drag starts, and the dragged URI is the hovered file (`a.txt`). HEAD did the same (always-on), so
this is not a regression, but it does not match the stated intent "starts on nnn's own list".
Fix: add `&& event.y <= ndents + 1`.

### F7 - Low - `O_NOMOUSE` builds cannot arm, but the log says they do

`Fact`. `dnd_osc72_arm()` is compiled out under `NOMOUSE` (`:4194-4210`), so in tmux the drag
source is never armed and drag-out is silently unavailable. Bare kitty keeps the always-on
registration. Rig B with the NOMOUSE build: T1 passes (bug fixed), no offer for the drag out of
nnn. `src/nnn.c:4731-4732` still logs `enable sent (tmux: drag source armed per gesture)`. Behaviour is
sensible (no mouse support means no mouse drag); only the log text and the docs need a line.

### F8 - Info - side effects of the key-disarm condition

`Fact`. `nextsel()` (`:5248-5249`) disarms on any input except `KEY_MOUSE`, so `KEY_RESIZE`
also disarms: a window resize during a held button ends the arm and the drag will not start.
A lone Esc takes the `i == ERR` path and does not disarm. No user-visible problem was found.

## Questions

1. `Open question`: is a 2-5 s arm timeout (F1 fix) acceptable for the owner's drag habits? The
   old always-on design had no such limit.
2. `Open question`: the lost race was measured at 2 ms and below on an idle machine with kitty
   under software GL. It was not measured on the owner's hardware or with a busy nnn.
3. `Not verified`: Wayland (kitty's own comment says the OS drag can be ignored there), macOS/BSD,
   other tmux versions, and the `NCURSES_MOUSE_VERSION <= 1` branch at run time (it compiles).
4. `Open question`: the comments at `src/nnn.c:4349-4353` and `:4609-4614` say kitty "swallowed
   the drag's release". Measured: true for a drop on an external window, false for a drop on
   kitty's own window (kitty delivers a release after `XdndFinished`). Worth one sentence.
5. `Open question`: the startup clear (`:4707-4709`) reached the outer terminal in 20 of 20 starts
   on an idle server (rig A), but in the tmux `-vv` trace of the rig-B setup phase both startup
   clears were dropped by `screen_write_set_client_cb()` because `PANE_REDRAW` was set
   (`tmux/screen-write.c:149`). A leftover flag from an old nnn can therefore survive an upgrade
   until the first press and release in a new nnn. The code comment already calls it best effort.
6. `Open question`: `kill -9` of an armed nnn leaves the flag ON until another nnn is clicked or
   started (rig A, `kill -9` then release: `can_offer` stays True). Inherent to the per-gesture
   design; the F1 timeout does not help because nnn is dead.

## Verified OK

| Check | Evidence |
|---|---|
| Reported symptom fixed | Rig B T1: 0 offers, copy mode selects, no garbage; HEAD: 2 offers and garbage |
| Drag-out to an external GTK app | Rig B command 15: `mousepad` opened `.../files/a.txt`, `drag finished`, `disarm: drag finished` |
| Wrong-file drag (HEAD) fixed | Rig B: HEAD offered `a.txt` for R's gesture, new refuses (F4) |
| First click after an external drop | Lost in HEAD and in the mutant without the reset, works in new (tmux and bare kitty) |
| Bare kitty unchanged | Normalised `NNN_DND_DEBUG` outbound lines identical to HEAD: startup `x=1` and `t=a`, agree batch, `t=m` replies, finish. Only differences: log line prefix (time and pid) and the `mousemask()` reset |
| Inputs while releases are subscribed | `get_input()` and the filter prompt eat the release; `xreadline()` (`:5825`), the stats viewer (`:7394`), `dnd_consume_paste()` ignore `KEY_MOUSE`; the browse loop disarms and skips the redraw. Six prompt types checked (command 12) |
| Double-click and non-list presses | Directory entered, flag off; context row, last row, row `xlines-3` do not arm |
| Arm and disarm reliability | 150 stress cycles, 0 failures; real kitty 4 ms and more head start: 6/6 drags |
| EPERM from kitty | nnn clears the drag data and disarms; probe drag gets 0 offers |
| Unarmed instance refuses an offer | Rig A T4a and rig B (F4) |
| `dnd_log()` rewrite | One `write()` per line, prefix fits the 48-byte reserve, no interleaving seen in the shared log; the scope test ran clean under ASan/UBSan |
| Subprocess and resync disarm | Command 23: flag OFF while a CLI opener started by a double-click runs, and after nnn resumes |
| Compile variants | 9 working-tree variants clean; no new warning vs HEAD in the 7 compared |
| Test isolation | Only `-L nnn-dnd-scope-<pid>` sockets and `HOME` in a scratch dir; no owner state touched |

## Cleanup record

Created by the reviewer and removed at the end (checked by listing afterwards): the scratch
builds, mutation, ASan, real-rig and tmux-debug directories under `$SCR` (`review-build.*`,
`review-base`, `review-work`, `review-build-dir.txt`, `review-base-dir.txt`), the scope test's kept
scratch directory `/tmp/nnn-dnd-scope.2r0pt_13` (left by the intended HEAD failure), the private
`Xvfb :97`, the `mousepad` session with its D-Bus helpers, one orphaned scratch `nnn`, 64 dead
`rev-*` / `nnn-dnd-scope-*` tmux socket files and the dead `mousetest` socket left by command 7 in
`/tmp/tmux-1000` (no live server was left), and
every kitty started on `:97`. Not touched because not created by the reviewer: `$SCR/kitty-src`,
`$SCR/ncurses` and the other items already in `$SCR`, the owner's `default` tmux socket, the
owner's kitty on `:1`, the live nnn processes, `nnn.bak-2026-10-23-pre-dnd-scope`, and
everything in the repo except this file. One validation run created `misc/test/__pycache__/` in the
repo (an import of the test module); it was deleted again. Side effect that cannot be undone: kitty and `mousepad`
running OpenGL under Xvfb may have written to the shared Mesa shader cache
(`~/.cache/mesa_shader_cache_db`, a cache only).

## Appendix A - real-kitty rig recipe (the scripts were scratch files and are deleted)

```bash
Xvfb :97 -screen 0 2000x800x24 -nolisten tcp &
# external XDND target, isolated XDG dirs; then move it outside the kitty window
DISPLAY=:97 GDK_BACKEND=x11 dbus-run-session -- mousepad --disable-server &
xdotool search --class mousepad          # xdotool windowmove <id> 1300 0 windowsize <id> 700 700
# tmux: the harness config (mouse on, allow-passthrough on, mode-keys vi, escape-time 10,
# focus-events on, copy-mode-vi 'o' and MouseDragEnd1Pane bound to "cat >> logfile")
tmux -L rev -f conf new-session -d -s t -x 128 -y 40 'sleep 100000'   # + split-window x2, new-window
# kitty.conf: font_size 10, initial_window_width 1280, initial_window_height 800
DISPLAY=:97 kitty --config kitty.conf --class rev-kitty --debug-input tmux -L rev attach -t t:1 2> kitty.err
# nnn in the panes: env -i HOME=<scratch>/home PATH=... TERM="$TERM" TMUX="$TMUX" TMUX_PANE="$TMUX_PANE" \
#     NNN_DND_OSC72=1 NNN_DND_DEBUG=<scratch>/dnd.log <nnn> <scratch>/files
# ground truth for offers: grep -c 'Sent drag start event to child' kitty.err
# drag out to the external window and drop:
DISPLAY=:97 xdotool mousemove X Y sleep 0.2 mousedown 1 sleep 0.06 mousemove_relative -- 14 0 \
    sleep 0.05 mousemove_relative -- 14 0 sleep 0.05 mousemove 1400 300 sleep 0.1 mousemove 1500 320 \
    sleep 0.4 mouseup 1
```

## Appendix B - rig A reproducers (run from the repo root with `python3 -B -I`, so no `__pycache__` is written into `misc/test/`)

`repro_stale_arm.py` (F1):

```python
import importlib.util, os, sys, tempfile, shutil
spec = importlib.util.spec_from_file_location('scope', 'misc/test/test-dnd-osc72-scope.py')
H = importlib.util.module_from_spec(spec)
spec.loader.exec_module(H)
nnn = os.path.abspath(sys.argv[1])
S = tempfile.mkdtemp(prefix='rev-stale.')
r = H.Run(nnn, S)
try:
    r.setup()
    r.start_nnn('t:1.1')
    k = r.k
    r.tmux('select-window', '-t', 't:1')
    r.tmux('select-pane', '-t', 't:1.1')
    k.pump(0.3)
    col, row = r.row_of('t:1.1', 'a.txt')
    x3, y3, _, _ = r.geom('t:1.3')
    k.press(col, row)
    k.move(col + 1, row)              # moves past 5 px before the arm reaches kitty: no offer
    k.pump(0.2)
    k.move(x3 + 2, row)
    k.release(x3 + 2, row)            # released over the shell pane: tmux does not forward it to nnn
    k.pump(0.4)
    print('after the flick: can_offer=%s (expected False)' % k.can_offer)
    n0 = len(k.offers)
    k.drag(x3 + 2, y3 + 8, range(x3 + 3, x3 + 9))
    k.release(x3 + 8, y3 + 8)
    k.pump(0.6)
    print('plain drag in the shell pane: offers=%d (expected 0)' % (len(k.offers) - n0))
finally:
    r.teardown()
    shutil.rmtree(S, ignore_errors=True)
```

`repro_wedge.py` (F2): same preamble, plus this subclass, then drag, release, click, key:

```python
ESC, ST = '\x1b', '\x1b\\'

class SilentKitty(H.FakeKitty):
    """Answers the drag start with OK, then never starts an OS drag (no t=e:x=4); the release is delivered."""
    def _on_app_osc(self, body):
        meta, _, _ = body.partition(';')
        kv = dict(p.split('=', 1) for p in meta.split(':') if '=' in p)
        if kv.get('t') == 'P' and kv.get('x') == '-1' and self.drag_state == 'building':
            self.drag_state = 'ignored'
            self.write(ESC + ']72;t=E:m=0;OK' + ST)
            return
        super()._on_app_osc(body)

H.FakeKitty = SilentKitty
# ... r.setup(); r.start_nnn('t:1.1'); select pane t:1.1;
# k.drag(col, row, range(col+1, col+4)); k.pump(0.5); k.release(col+3, row); k.pump(0.6)
# print(k.can_offer)    # True; then press/release on b.txt and k.write('j'): still True
```

## Appendix C - suggested fix, as tested in a scratch copy (not applied to the repo)

```c
/* in dnd_osc72_arm(), after g_dnd_armed = TRUE: */
	clock_gettime(DND_CLOCK, &g_dnd_armed_ts);          /* static struct timespec g_dnd_armed_ts; */

/* in nextsel(), at the top of the "if (i == ERR) {" block, after ++idle: */
	if (g_dnd_armed && !g_dnd_b64) {
		struct timespec now;

		clock_gettime(DND_CLOCK, &now);
		if (now.tv_sec - g_dnd_armed_ts.tv_sec >= 2)
			dnd_osc72_disarm("disarm: timeout");
	}

/* new helper, used instead of dnd_osc72_disarm("disarm: release") at the three release sites: */
static void dnd_osc72_release_disarm(void)
{
	if (g_dnd_armed && g_dnd_b64)
		dnd_clear_data();       /* a release reached nnn: no OS drag holds the pointer */
	dnd_osc72_disarm("disarm: release");
}
```
