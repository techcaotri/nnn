# Brief: integration and user-experience review with the real nnn

Read `docs/workflows/cpmv_overwrite/agents/_context.md` first and follow its rules.

Report path: `docs/workflows/cpmv_overwrite/notes/review-integration.md`

## Your lens

The owner runs two nnn instances side by side in tmux (`~/bin/start_dual_nnn.sh`, aliases
`nnn_left` and `nnn_right`, option `-S -s left|right`, environment `NNN_DND_OSC72=1`). Both
instances share one selection file. Check that the new `plugins/cpmv` works through the real
nnn binary (`/home/tripham/Dev/Playground_Terminal/nnn/nnn`, built with FZ_CPMV) in situations
that `misc/test/test-cpmv-e2e.sh` does not cover. Read that script first and reuse its helpers
(private tmux socket, `XDG_CONFIG_HOME`, `NNN_SEL`).

IMPORTANT: never use the owner's tmux server or `~/.config/nnn`. Do not run
`start_dual_nnn.sh` itself, it kills panes of the current tmux window. Build the same layout
yourself inside a private tmux server (`tmux -L cpmv-review-integ ...`).

## Scenarios

1. Two panes, two nnn processes, same `NNN_SEL`, `NNN_DND_OSC72=1` exported, each started with
   `-e -a -o -r -R -i -d -H -P a -P p -s left|right -S -f` like the owner's aliases (use
   private session names so no real session is read). Select a directory in the left pane with
   Space, switch to the right pane, press `p`, answer `4`. Verify the files on disk and that the
   selection is cleared in BOTH panes afterwards.
2. Multi-select two conflicting directories and one file, press `v`, answer `4` then `y`
   (apply to all). Verify disk state and that `Done. Press enter.` appears once.
3. Mode `6` (rename) twice in a row, then `7` (skip).
4. Interruption: create a source directory with a few large files (for example 3 files of
   400 MB made with `truncate`/`dd` into your scratch directory; delete them afterwards) that
   conflict with an existing target directory. Press `v`, answer `4`, and send Ctrl-C to the
   pane while rsync runs. Verify that no source file is lost: every source file that is
   missing from the source must exist at the target with full content (compare with `cmp`).
   Repeat once with `p`.
5. Narrow terminal: run scenario 1 in a pane that is 80 columns wide and again at 60 columns.
   Report anything unreadable (wrapped progress lines, the menu, the plan line).
6. A failing paste (an unreadable source file, `chmod 000`) in the `-r` (advcpmv) build:
   nnn must pause with `'Enter' to continue`, print `failed!`, and keep the selection.
7. Screen quality: capture the pane text (`tmux capture-pane -p`) at each step of scenario 1
   and paste a trimmed copy into the report so the owner can see what the user sees.

## Deliverable

The report at the path above, in the layout of `_context.md`. For each scenario say PASS or
FAIL with the evidence (disk state, captured screen). Add a section `Suggestions` for UX
changes you would make, clearly marked as opinions.
