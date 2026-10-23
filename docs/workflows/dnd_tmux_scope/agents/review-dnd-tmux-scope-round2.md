# Brief: round 2 review of the OSC-72 drag-source scope fix

## Purpose

Your round 1 report is `docs/workflows/dnd_tmux_scope/notes/review-dnd-tmux-scope.md`. The
orchestrator has since changed `src/nnn.c` and `misc/test/test-dnd-osc72-scope.py` in response.
Review the new state against the real code, with the same rigs (fake kitty and real kitty on a
private Xvfb). Same rules as round 1: read-only on the repo except your new report, build in a
scratch copy, never touch the owner's live tmux server, kitty or nnn panes, cite `file:line` plus
a reproducer for every finding, delete everything you create.

State under review (md5): `src/nnn.c` `6a53deec533c0800ed0579803c7f58f3`,
`misc/test/test-dnd-osc72-scope.py` `65741d46600c26a81b94f5080c904193`. If either changes while
you work, say so in the report.

## What changed since round 1 (verify each; do not take this list on trust)

| Round 1 item | Change |
|---|---|
| F1 stale arm | `dnd_osc72_idle()`, called from the idle tick in `nextsel()`: an arm older than `DND_ARM_MAX_MS` (2000) is disarmed, then `dnd_mouse_reset()`. Skipped while `dnd_tmux_drag_live()` is TRUE. |
| F2 wedge | `dnd_osc72_release()` at the three release sites: a release that reaches nnn while `g_dnd_b64` is set drops the dead drag (sets `g_dnd_end_ts`, `dnd_clear_data()`), then disarms. |
| F2 trigger, Q5 | The startup `t=o:x=2` moved from `dnd_osc72_enable()` to the first idle tick in `dnd_osc72_idle()`, skipped if this instance is armed or `dnd_tmux_drag_live()`. |
| new | `dnd_tmux_drag_live()`: a blocking `spawn()` of a shell that succeeds when `@nnn_dnd_mouse` names a live pid. |
| new, found by the orchestrator | `dnd_grab_tmux_mouse()` now waits for its script (no `F_NOWAIT`). Reason: kitty's `t=E;EPERM` 1 ms after the answer made the detached release run before the detached grab, stranding tmux's mouse off with a marker until the 60 s watchdog. |
| new, found by the orchestrator | `dnd_mouse_reset()` (re-applies `g_mousemask`) also after the timeout and the key disarms: a flick's lost release leaves ncurses with button 1 down, and the next press in nnn decodes as motion and is lost. |
| new, found by the orchestrator | Side effect of that reset: a later real release decodes as motion, filtered by the mask, so `KEY_MOUSE` arrives with no event (`getmouse()` fails). `dnd_eat_release()` now also consumes a failed `getmouse()` and a `REPORT_MOUSE_POSITION` event; `filterentries()` ignores `REPORT_MOUSE_POSITION`. |
| F3 tests | New scenarios T7 (timeout), T7b (key), T8b (clear skipped while a drag is live), T10 (blank and header rows), T11 (EPERM, plus the grab race), T12 (ignored offer), T13 (silent kitty), T14 (`t` prompt), T15 (`/` prompt), T16 (CLI opener via `-c`). `FakeKitty` now decides at the first sample past 5 px inside the cell (18x36 px cells, `nudge()`), tracks tmux's mouse reporting modes, and models `t=o:x=2` mid-drag and `t=E;EPERM`. |
| F5 | `get_input()`: one loop that skips both releases and `KEY_RESIZE`. |
| F6 | Arming also requires `event.y <= ndents + 1`. |
| F7 | `O_NOMOUSE` log text: `enable sent (tmux: no mouse support, no drag-out)`. |
| F8 | The key disarm in `nextsel()` ignores `KEY_RESIZE`. |
| Q4 | Comments now say a drag dropped OUTSIDE kitty swallows the release. |

## What to check

1. Each change above, on the real code, with a reproducer; rig B for F1, F2 and the grab race.
2. Regressions the changes may cause, in particular: the ncurses reset in the key path while the
   button is still held; the blocking `spawn()` calls (grab, `dnd_tmux_drag_live()`) in the input
   loop; the deferred clear racing a peer's arm; anything that can now leave kitty's flag ON or
   tmux's mouse OFF.
3. Mutation testing of the new test against the new code (your round 1 set plus mutations of the
   new pieces). Report which survive.
4. Bare kitty: confirm the outbound stream is still identical to HEAD apart from the reset.

## Report

Write `docs/workflows/dnd_tmux_scope/notes/review-dnd-tmux-scope-round2.md`: Purpose, Commands
run (command, result, PASS/FAIL), Round 1 findings re-checked (each: fixed / not fixed / partly,
with evidence), New findings (most severe first, `file:line`, reproducer, suggested fix),
Mutation results, Questions, Verified OK, Cleanup record. Plain ASCII, no em dashes. Return a
short summary in your final message.
