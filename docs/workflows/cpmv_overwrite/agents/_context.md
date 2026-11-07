# Shared context for the cpmv review agents

## Purpose

Three independent reviewers check the fix in commit `e2fcb93d` (`git show e2fcb93d`).
Read this file first, then your own brief in the same directory.

## The change under review

- `plugins/cpmv`: the nnn plugin behind the copy ('p') and move ('v') CONFLICT menu.
  nnn calls `cpmv "<op>" "<selection-file>" .` with stdin on the terminal.
- Reported bug: menu mode `4) different size or newer` sometimes did not overwrite files.
  Cause: mode 4 used `rsync --update`, which skips every newer target even when its size differs.
- The fix also changed: modes 3/4 (plan with rsync dry runs, copy with `--files-from`),
  move safety (`--remove-source-files`, never delete a skipped file), directory move
  in modes 1/2 (rsync merge), error handling (exit 1), file-versus-directory clash.
- Read `docs/workflows/cpmv_overwrite/notes/investigation.md` for the root causes and design.
- The mode table is in the header comment of `plugins/cpmv`.

## Tests that already exist

| File | What it does | Command |
|---|---|---|
| `misc/test/test-cpmv.sh` | 578 checks on the plugin, plain and advcpmv ops | `misc/test/test-cpmv.sh` |
| `misc/test/test-cpmv-e2e.sh` | real nnn in an isolated tmux server | `misc/test/test-cpmv-e2e.sh` |

Both pass on the commit. `CPMV=<path>` runs the suite against another copy of the plugin.
The original plugin is `git show e2fcb93d~1:plugins/cpmv`.

## Rules for every reviewer

1. Model and cost: you run on Sonnet. Keep tool rounds short. The orchestrator may send you
   instructions with SendMessage; they are read at your next tool round.
2. Do NOT edit any tracked file in the repo. The only file you create in the repo is your
   report (path in your brief). Do not run `git add`, `git commit`, `git stash` or `git checkout`.
3. Work in your own scratch directory: `mktemp -d /tmp/cpmv-review-XXXXXX` (or the scratchpad
   directory named in your prompt). Delete what you create, including on failure paths.
   Never delete anything you did not create.
4. Do not touch the user's real nnn state: `~/.config/nnn`, the user's tmux server, any
   file under `/media`. If you need tmux, use a private socket: `tmux -L cpmv-review-<name>`
   and set `XDG_CONFIG_HOME` and `NNN_SEL` to paths inside your scratch directory.
5. Command timeouts: every search or inspection command gets `timeout 60` or less. Anything
   longer than a minute goes to the background. Every loop has a per-iteration and a whole-run
   deadline.
6. Evidence rule: a finding counts only when it cites `file:line` of the code and gives an
   exact command or reproducer that shows it. A finding based on what the code "should" do is
   a QUESTION, not a defect. Label each finding `CONFIRMED` (you reproduced it) or
   `NOT REPRODUCED`.
7. Writing style for the report: plain ASCII, no em dashes, no smart quotes, short sections,
   Markdown tables for summaries, commands in fenced code blocks. Separate `Fact`, `Assumption`
   and `Open question`. Say `Not verified` where you did not run something.

## Report layout

```text
# <lens>: review of e2fcb93d
## Verdict            (one paragraph: is the fix correct, what must change)
## Findings           (table: id, severity, file:line, one-line summary, CONFIRMED/NOT REPRODUCED)
## Details            (per finding: reproducer commands, expected, actual)
## What I checked and found fine   (short list, so the orchestrator knows the coverage)
## Not verified
```

Severity: `HIGH` = data loss or a wrong overwrite, `MEDIUM` = wrong result or hidden failure,
`LOW` = cosmetic or rare.
