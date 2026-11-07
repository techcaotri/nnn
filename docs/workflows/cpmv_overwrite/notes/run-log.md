# Run log: cpmv fix and its three reviews

## Purpose

Record the background agents of the cpmv fix, what each review led to, and the state of the
work, so it can be resumed or audited. Briefs are in `../agents/`, reports in this directory.
The full write-up is Problem 16 in `docs/nnn_Problems_And_Solutions.md` (16.12 has the
disposition of every finding).

## Agents launched 2026-11-07 15:24 (all Sonnet, Agent tool, messageable with SendMessage)

| Name | agentId | Brief | Report | Status |
|---|---|---|---|---|
| correctness | `acf27d198de5b1d22` | `agents/review-correctness.md` | `notes/review-correctness.md` | DONE 16:03 (39 min), triaged |
| test strength | `ab2adee0a27db99b3` | `agents/review-test-strength.md` | `notes/review-test-strength.md` | DONE 16:04 (40 min), triaged |
| integration | `a984948317f400e19` | `agents/review-integration.md` | `notes/review-integration.md` | DONE 15:43 (21 min), triaged |

Reviewed commit: `e2fcb93d`. Rule while any agent ran: nobody edited `plugins/cpmv` or
`misc/test/test-cpmv*.sh` in the repo; fixes were built and tested in scratch copies.

Backstop: a session-only cron job checked the agents every 20 minutes; it is deleted now that
all three reports are triaged.

## Triage summary

| Report | Findings | Outcome |
|---|---|---|
| correctness | 3 HIGH, 2 MEDIUM, 7 LOW, all confirmed by the reviewer; 7 hypotheses not reproduced | All fixed or documented; the author reproduced C1 to C5, C7 to C9, C12 |
| integration | 1 MEDIUM (Ctrl-C), 3 LOW | F1 fixed; F2 own lines shortened; F3 is rsync's own format; F4 message names the target |
| test strength | 73 mutants, 38 killed, 35 survived (32 real gaps), 24 proposed groups | Groups integrated and adapted; 6 weak assertions fixed |

Findings that changed the design (not only a line of code):

- C3 (a move deleted a source whose size and time matched the target but whose bytes
  differed) led to the checksum proof before a move removes an "identical" source.
- C2 (mode 2 on a directory move is not "newer only") led to mode 2 using the same plan as
  modes 3 and 4 for copy and move.
- C1 plus an own probe led to the type-change guard: rsync lists every type change as a new item,
  so a new item where a regular or special file sits at the target is refused.

## Lessons from the process

- Never locate a process with `pgrep -f` from a shell whose own command line contains the
  pattern. It matched the tool's own shell and a SIGINT hit it. The later runs start the
  plugin from Python in its own session and signal only that group.
- A mutation runner that passed a relative path made every plugin call fail, so every mutant
  looked killed. A uniformly "killed" result needs a control run against the unmutated plugin.
- `-S` with non-zero data matters for a Ctrl-C test: a test file of zeros is written sparse and
  the copy ends before a watcher sees the temp file grow.
- Two claims in a draft of the write-up were assumptions and were corrected after a test:
  `rsync -X` does not fail on this machine's NTFS volume, and `-S` does work with
  `--append-verify`.

## Housekeeping done

- Scratch fixtures of 8.8 GB removed from the session scratchpad (my own files).
- Four `/tmp/cpmv.*` directories left by the reviewers' mutant runs (a mutant without the cleanup
  trap) and two stale e2e tmux sockets of my first runs were removed after checking that no
  process used them. The user's live tmux socket was not touched.
- The real plugin leaves no temp directory after a normal exit, exit 1, SIGINT, SIGTERM or
  SIGHUP (checked with a private `TMPDIR`); `kill -9` cannot be trapped.
- `my_patches/nnn-cpmv` (the first draft) was marked superseded; `my_patches/` is in
  `.gitignore`, so that edit is local only.
