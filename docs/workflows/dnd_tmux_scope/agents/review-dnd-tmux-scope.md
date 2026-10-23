# Brief: independent review of the OSC-72 drag-source scope fix

## Purpose

Review an uncommitted change to `src/nnn.c` and a new test, `misc/test/test-dnd-osc72-scope.py`,
against the real code. Find correctness bugs and regressions. You are a reviewer, not an
implementer: do not edit `src/`, the tests, or any doc other than your report.

## The reported problem (from the owner)

In kitty 0.49.2 with tmux 3.7b (session `main_fish`), after running
`~/bin/start_dual_nnn.sh` (two nnn panes with `NNN_DND_OSC72=1`), selecting text with the mouse
in OTHER tmux windows breaks: after 2-3 characters the selection freezes, and the next left
click types text like `:x=1:y=10:X=23:Y=38772;t=o:x=64:y=14:X=1152:Y=531` into the shell.
Without the dual nnn, mouse selection works.

## The change under review

Read it yourself: `git -C /home/tripham/Dev/Playground_Terminal/nnn diff -- src/nnn.c` and the
new file `misc/test/test-dnd-osc72-scope.py`. The intent, in one paragraph: kitty keeps one
OSC-72 drag-source flag per kitty window, so inside tmux the flag nnn sets covers every tmux
window and pane; the change arms the flag only for a left-button gesture that starts on nnn's
own list and disarms it when that gesture ends. Bare kitty (no tmux) is meant to be unchanged.
Judge the code, not this paragraph.

## Sources you can read (do not modify)

| What | Path |
|---|---|
| nnn | `/home/tripham/Dev/Playground_Terminal/nnn/src/nnn.c` |
| kitty 0.49.2 (`kitty/mouse.c`, `kitty/dnd.c`) | `/tmp/claude-1000/-home-tripham-Dev-Playground-Terminal-nnn/77411640-6908-4bc0-b2ad-804bf7d152a4/scratchpad/kitty-src/kitty` |
| tmux 3.7b (builds the installed binary) | `/home/tripham/Dev/Playground_Terminal/tmux` |
| ncurses 6.3 `lib_mouse.c` | `/tmp/claude-1000/-home-tripham-Dev-Playground-Terminal-nnn/77411640-6908-4bc0-b2ad-804bf7d152a4/scratchpad/ncurses/lib_mouse.c` |
| kitty's protocol spec | `/home/tripham/.local/kitty.app/share/doc/kitty/html/_sources/dnd-protocol.rst.txt` |

## What to check (not exhaustive)

1. Every place nnn reads input while button releases are subscribed: can a release now
   answer a prompt, exit a prompt, trigger an action, or be lost so a gesture stays armed?
2. Every path that can leave kitty's flag ON after a gesture ends, inside tmux.
3. Two nnn instances in one tmux window: can one instance's disarm break the other's
   in-flight drag, or can the wrong instance answer an offer?
4. Bare kitty (no tmux) behaviour: is anything changed beyond the ncurses mask reset?
5. `O_NOMOUSE` builds and other `O_*` combinations: compile, and is behaviour sensible?
6. The new test: does it model kitty 0.49.2 faithfully (check `handle_potential_drag()` and
   `handle_button_event()` in `kitty/mouse.c`)? Could it pass while the real thing fails?

## How to work

- Build in a scratch copy, never in the repo: the repo's `nnn` binary is what the owner's
  live panes run. For example:
  `S=$(mktemp -d); cp -r Makefile src $S/; make -C $S -j8 O_EMOJI=1 O_PCRE2=1 O_QSORT=1 O_SSN_ON_CD=1 O_SSN_PIPE=1 O_FZ_CPMV=1 O_HIST=1 O_DND=1`
- Run the tests against your scratch build:
  `python3 -I misc/test/test-dnd-osc72-scope.py --nnn $S/nnn` and
  `bash misc/test/test-dnd-tmux-mouse.sh`. Both use isolated tmux sockets.
- Never touch the owner's live tmux server (the default socket), its options, or the running
  nnn processes. Any tmux server you start must use its own `-L` socket and be killed by you.
- Search and inspection commands carry `timeout 60` or less. Anything longer than about a
  minute runs in the background. Keep tool rounds short: the orchestrator may send you
  instructions, and you only read them between tool rounds.
- Delete what you create (scratch dirs, tmux servers, test files) when you finish, also on
  failure paths. Never delete anything you did not create.

## Findings and report

A finding counts only with implementation facts: cite `file:line` of the code and give a command
or reproducer that shows it. Something the code "should" do, without a reproducer, goes under
"Questions", not "Findings".

Write your report to
`/home/tripham/Dev/Playground_Terminal/nnn/docs/workflows/dnd_tmux_scope/notes/review-dnd-tmux-scope.md`
with sections: Purpose, Commands run (exact command, result, pass/fail), Findings (most severe
first: `file:line`, defect, reproducer, suggested fix), Questions, Verified OK. Plain ASCII, no em
dashes. Also return a short summary of the findings in your final message.
