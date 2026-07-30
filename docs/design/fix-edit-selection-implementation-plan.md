# Fix: capitalized 'E' (edit selection) appears to not work

## Purpose

This document plans the fix for a reported bug: pressing capitalized `E` in `nnn`
(bound to "list/edit selection") does not seem to do anything useful. The
investigation was done by reading the relevant source (`src/nnn.h` keymap,
`src/nnn.c` selection/edit logic) and by reproducing the behavior live with a
disposable two-pane tmux + `nnn` session, mirroring the user's real dual-pane
workflow (`start_dual_nnn.sh`, `nnn_left` / `nnn_right`).

`Fact`: the keybinding itself is correct and the core edit-selection code path
works. The confusing behavior comes from two separate, confirmed causes:

1. `nnn`'s selection file is shared by default between the two dual-pane
   instances, and `E` deliberately refuses to open an editor for a selection it
   did not make itself, showing a silent, unexplained read-only dump instead.
2. The user's `$EDITOR` (`nvim`, a LazyVim/Mason-based config) has a slow,
   network-touching startup overlay that can make even the *working* case look
   stuck.

Only cause 1 is fixable in this repository; cause 2 is the user's own editor
config and is documented here for awareness, not fixed.

## Root cause (Fact, reproduced live)

### 1a. The keybinding is correct (ruled out)

`src/nnn.h:231`: `{ 'E', SEL_SELEDIT }`. Capitalized `E` is correctly bound to
the "list, edit selection" action. Not a missing- or wrong-keybinding bug.
Also checked `~/.config/tmux/tmux.conf*` for any unprefixed (`bind -n`) `E`
binding that could steal the key before `nnn` sees it: none found.

### 1b. The "same pane" case works (reproduced, confirmed working)

`src/nnn.c:10428-10440` (`case SEL_SELEDIT`) calls `editselection(FALSE)`
(`src/nnn.c:2228`). When the pressing instance has files selected in its own
memory (`selbufpos != 0`), `editselection` writes them to a temp file and does:

```c
spawn((cfg.waitedit ? enveditor : editor), g_tmpfpath, NULL, NULL, F_CLI);
```

`Fact`, reproduced live: created a disposable 2-pane tmux session running two
real `/home/tripham/bin/nnn` instances (this repo's built binary, confirmed
up to date with current `src/nnn.c` via matching commit/build timestamps) in a
scratch test directory, attached a real pty client (same technique used in the
Alt+/ investigation, so popups/curses redraw fully). In pane 1: selected 2
files with `Space`/`j`/`Space`, pressed `E`. Result: `nvim /tmp/.nnnAatThE`
launched as a real child process, and the temp file it opened contained
exactly the 2 selected file paths. This part of the feature works correctly.

### 1c. The cross-pane case is silently read-only (reproduced, this is the bug)

`nnn`'s selection file path (`selpath`) defaults to a single fixed path,
`${XDG_CONFIG_HOME:-$HOME/.config}/nnn/.selection`, **shared by every `nnn`
instance on the machine**, unless the `NNN_SEL` environment variable is set to
give each instance its own path (`src/nnn.c:11354-11369`).

`Fact`: this user's config does not set `NNN_SEL` anywhere
(`grep -rn NNN_SEL ~/.config/nnn/nnn_config.sh` and the live process
environment both confirm this). `nnn_left` and `nnn_right`
(`~/.config/fish` abbreviations, both `/home/tripham/bin/nnn -e -a -o -r -R -i
-d -H -P p -s <left|right> -S`) are two independent processes that therefore
both read and write the same `~/.config/nnn/.selection` file on disk. This is
almost certainly intentional on the user's part: it is what makes
select-in-one-pane / paste-in-the-other-pane work at all.

The selection buffer that `editselection` actually checks, `selbufpos`, is an
**in-memory, per-process** variable, separate from the shared on-disk file.
`src/nnn.c:2236`:

```c
if (!allowemptysel && !selbufpos) /* External selection is only editable at source */
    return listselfile();
```

`listselfile()` (`src/nnn.c:1877-1886`) does not open an editor at all. It
runs a read-only dump and waits for Enter:

```c
snprintf(g_buf, CMD_LEN_MAX, "tr '\\0' '\\n' < '%s'", selpath);
spawn(utils[UTIL_SH_EXEC], g_buf, NULL, NULL, F_CLI | F_CONFIRM);
```

`Fact`, reproduced live: in the same test session, pane 1 had files selected
(so its own `selbufpos != 0`); pane 2 had never selected anything itself
(`selbufpos == 0` in its memory), but the shared `~/.config/nnn/.selection`
file was non-empty (from the user's own real, concurrently running `nnn`
session on the same machine, which had 2 files selected during this
investigation). Pressing `E` in pane 2 produced:

```
/home/tripham/Downloads/Template DXS 2026.pptx
/home/tripham/Downloads/Business Plan-Commercial Leasing-5yrs-29072026.docx
'Enter' to continue
```

No editor opened. Just a plain-text dump with no explanation of why, and no
way to actually edit it from that pane. This is the reported bug: from the
user's point of view, they pressed `E` "to edit the current selection" and got
what looks like broken/no-op behavior (a static list, not an editable buffer),
with zero indication that this is intentional ("edit at the source instance")
rather than a malfunction.

`Assumption`: this is very likely what the user is hitting in normal daily use
of the dual-pane layout: select files in one pane, then (for whatever reason,
e.g. having switched focus, or the selection buffer having been reset by an
earlier action in that pane) press `E` in the *other* pane, or in the same
pane after its own local `selbufpos` no longer matches what's on disk.

### 1d. Contributing factor, not fixable here: slow $EDITOR startup

`Fact`, reproduced live: in the *working* case (1b above), after `nvim` was
spawned on the temp file, it did not show the temp file. It first showed a
`mason.nvim` plugin-manager overlay ("press g? for help", a package list, an
"Installed" count) and made live network calls (`git remote-https` /
`curl` to `github.com` for `mason-registry`, `tokyonight.nvim`,
`translate.nvim`, etc., confirmed via `ps -ef --forest`). The actual temp file
with the selected paths only became visible after manually pressing `q` to
dismiss that overlay, several seconds in. Network reachability itself was
fine (`curl -sI https://github.com` returned `200` in under a second), so this
is a startup-heavy editor config, not a hang, but it can easily read as
"nothing happened" if the user does not wait it out or does not know to press
`q`. This is entirely the user's `nvim`/LazyVim/Mason configuration, not
`nnn` code, so it is out of scope for a code fix in this repo. Noted here so
the user is aware it is a separate, real issue.

## 1. Current code structure

- `src/nnn.h`: `bindings[]` keymap. `{ 'E', SEL_SELEDIT }` (line 231),
  `{ 'e', SEL_EDIT }` (line 261, unrelated: edits the currently hovered file,
  not the selection).
- `src/nnn.c`:
  - `editselection(bool allowemptysel)` (~line 2228): core "edit the
    selection list" logic. Early-returns to `listselfile()` when there is no
    local selection to edit (the read-only path). Otherwise writes the
    selection to a temp file, spawns `$EDITOR`/`$VISUAL`, and applies edits
    back on return if the temp file's mtime changed.
  - `listselfile(void)` (~line 1877): the read-only fallback. This is the
    function that needs the fix (Step below).
  - `case SEL_SELEDIT:` (~line 10428, inside `browse()`'s main switch): calls
    `editselection(FALSE)` and turns its return value into a status message
    (`MSG_0_SELECTED` / `MSG_FAILED`) or a status-bar refresh. No change
    needed here.
  - Selection file path setup (~line 11354-11369): `selpath` defaults to
    `<cfgpath>/.selection` unless `NNN_SEL` is set. Confirms the shared-path
    behavior; not something to change (changing the default would be a
    behavior change well beyond this bug, and the user's cross-pane
    paste workflow depends on the sharing).

## 2. Files likely to change

| File | Change |
|---|---|
| `src/nnn.c` | Required. Add a short, clear explanatory message inside `listselfile()` before it dumps the external selection, so the read-only behavior is self-explanatory instead of looking broken. |
| `docs/` (this plan doc) | Already created by this task; no further doc change required unless the user wants the man page / in-app help updated too (optional, see Risks). |

`plugins/` and `src/nnn.h` are not touched. This is a small, single-function,
message-only change; it does not alter `editselection`'s "external selection
is only editable at source" safety behavior, since that behavior protects
against two `nnn` processes racing to overwrite the same shared selection
file inconsistently, and removing it would be a real regression risk, not a
UX fix.

## 3. Data structures / functions to add or update

No new data structures. One function body changes:

- `listselfile(void)` (`src/nnn.c`, current body):
  ```c
  static bool listselfile(void)
  {
      if (isselfileempty())
          return FALSE;

      snprintf(g_buf, CMD_LEN_MAX, "tr \'\\0\' \'\\n\' < '%s'", selpath);
      spawn(utils[UTIL_SH_EXEC], g_buf, NULL, NULL, F_CLI | F_CONFIRM);

      return TRUE;
  }
  ```
  New body (only the `snprintf` format string changes, prepending one `echo`
  line before the existing `tr` pipeline so the explanation appears on the
  same screen, right above the listing, since `spawn(..., F_CLI, ...)` has
  already called `exitcurses()` by the time this runs):
  ```c
  static bool listselfile(void)
  {
      if (isselfileempty())
          return FALSE;

      snprintf(g_buf, CMD_LEN_MAX,
               "echo 'Selection was made in another nnn instance - showing it read-only.'; "
               "echo 'Switch to that instance to edit it.'; echo; "
               "tr \'\\0\' \'\\n\' < '%s'", selpath);
      spawn(utils[UTIL_SH_EXEC], g_buf, NULL, NULL, F_CLI | F_CONFIRM);

      return TRUE;
  }
  ```
  `Risk`: keep the existing `tr '\0' '\n' < '%s'` part byte-for-byte identical
  (same quoting), only prepend the two `echo` statements and a blank-line
  `echo`. Do not change quoting style for `selpath`'s `%s` substitution.

## 4. Implementation steps

1. Open `src/nnn.c`, locate `listselfile()` (~line 1877).
2. Apply the body change from Section 3 above.
3. Rebuild the binary (`make` from the repo root; confirm the Makefile target
   used elsewhere in this repo's normal build flow) and confirm
   `/home/tripham/bin/nnn` (a symlink to the repo's `nnn` binary) picks up the
   change automatically, since it is a symlink, not a copy.
4. No other files need to change for the required fix.

## 5. Test plan

`Risk callout`: do not claim a step passed without actually running it.

1. **Build check**: `make` (or the repo's normal build command) completes
   with no new warnings/errors introduced by this change.
2. **Same-pane regression check** (must still work exactly as before): in a
   throwaway test directory (not the user's real files), run `nnn`, select 2+
   files with `Space`, press `E`. Expect `$EDITOR` to open on a temp file
   containing exactly those paths, same as the confirmed-working behavior in
   Section 1b. This must be unchanged by the fix.
3. **Cross-pane message check** (the actual fix): with two `nnn` instances
   pointed at the same test directory (or reuse the two-pane tmux
   reproduction from this investigation), select files in instance A only,
   then press `E` in instance B (which has nothing selected locally). Expect
   to now see the explanatory lines ("Selection was made in another nnn
   instance...") printed above the file listing, followed by the same
   `'Enter' to continue` prompt as before. Confirm no editor is spawned in
   instance B (unchanged safety behavior), only the message + listing.
4. **Zero-selection check** (must still work exactly as before): with no
   selection anywhere (local or on-disk), press `E`. Expect the existing
   `MSG_0_SELECTED` status-bar message, unchanged.
5. **Live manual check (needs a human)**: the user tries their normal
   dual-pane workflow (`start_dual_nnn.sh`), selects files in one pane,
   switches to the other pane, presses `E`, and confirms the message now
   makes it clear why no editor opened. `Not verified` until the user does
   this themselves.

## 6. Risks

- `Risk`: this fix only makes the existing "external selection is read-only"
  behavior *understandable*; it does not change the behavior. If the user
  actually wants `E` to work cross-pane (open an editable buffer no matter
  which pane you press it in), that requires either (a) giving each pane its
  own `NNN_SEL` (breaks cross-pane copy/paste, not recommended, see Section
  1c), or (b) a real cross-instance sync mechanism (a genuine feature
  addition, out of scope for a bug fix; would need design work of its own if
  wanted).
- `Risk`: the message text is spawned through `sh -c` via `utils[UTIL_SH_EXEC]`
  and `snprintf` into a shared buffer (`g_buf`, size `CMD_LEN_MAX`). Keep the
  added text short so the combined command string has no realistic chance of
  approaching `CMD_LEN_MAX` (the existing `selpath` substitution is the only
  variable-length part; the added text is a small fixed literal).
- `Risk`: rebuilding `nnn` replaces the binary the user's live dual-pane
  session is currently running from (`/home/tripham/bin/nnn` is a symlink to
  this repo's build output). A running process keeps using its already-loaded
  code in memory, so this is safe for processes already started, but the user
  will need to restart their `nnn` panes (or run `start_dual_nnn.sh` again) to
  pick up the fix.
- `Open question`: whether the user also wants the in-app help screen
  (`show_help`, bound to `?`) or the man page to spell out the "edit selection
  only works at the source instance" rule explicitly. Not required for the
  bug fix; only do this if asked.
- `Out of scope, flagged for awareness`: the slow `nvim`/Mason startup
  (Section 1d) is a real, reproducible source of "looks broken" even when
  `nnn`'s code is working correctly. Fixing it means changing the user's nvim
  config (e.g. not auto-opening Mason, or using a lighter editor/flag when
  invoked for this kind of quick scratch-buffer edit), not this repo. Only
  pursue this if the user explicitly asks.
- `Note`: during this investigation, the shared `~/.config/nnn/.selection`
  file was observed to change due to the user's own real, concurrently
  running `nnn` session (unrelated to this investigation's test panes). This
  confirms the file is genuinely live/shared, but also means any future
  testing against it should avoid clearing or overwriting it while the user
  may be actively working, and should prefer a throwaway test directory /
  disposable tmux session (as done here) rather than the user's real panes.

## 7. Sonnet execution checklist

1. [ ] Read `src/nnn.c` around `listselfile()` (~line 1877) and confirm the
       current body matches Section 3's "current body" exactly before
       editing (guard against drift since this plan was written).
2. [ ] Apply the body change from Section 3.
3. [ ] Build the project with this repo's normal build command; confirm no
       new compiler warnings/errors. Record the exact command and result.
4. [ ] Run the same-pane regression check (Test plan step 2) in a throwaway
       test directory, not the user's real files. Record pass/fail.
5. [ ] Run the cross-pane message check (Test plan step 3), reusing the
       disposable two-pane tmux + attached-pty-client technique from this
       investigation (or an equivalent). Record the exact output seen and
       pass/fail. Clean up every disposable session/process/temp file
       created for this test afterward; do not touch the user's real
       `~/.config/nnn/.selection` or real tmux sessions/panes.
6. [ ] Run the zero-selection check (Test plan step 4). Record pass/fail.
7. [ ] `git status` / `git diff` to confirm only `src/nnn.c` changed, then
       commit with a descriptive message (no AI co-author trailer, per this
       user's documentation-style policy). Do not push unless asked.
8. [ ] Tell the user they need to restart their `nnn` panes (or rerun
       `start_dual_nnn.sh`) to pick up the rebuilt binary, since currently
       running instances keep their already-loaded code.
9. [ ] Ask the user to do the live manual check (Test plan step 5); do not
       claim it passed without their confirmation.
10. [ ] Mention the out-of-scope nvim/Mason startup finding (Section 1d) in
        the final summary so the user is aware of it, without acting on it
        unless they ask.

---

# Part 2: Brainstorm

Everything above documents the shipped fix (a message-only change, commit
`d26ddd15`). Everything below is design exploration for follow-up work. Nothing
in Part 2 has been implemented.

`Note on verification status`: the options below were produced by parallel
investigation agents that read the real source and config, then put through
adversarial review. `A4` had one reviewer; `A1`, `A2` and `A3` had two
independent reviewers each, several of whom applied the patch to a throwaway
copy, built it with `./build.sh`, and drove it under a pty. **No option came
back `SOUND`.** Findings are in section 8.5.2, and section 8.6 states what to do
about them. Where a reviewer corrected an earlier claim, the correction is
recorded rather than the original quietly edited.

`Fact`: no work in Part 2 has been implemented in this repository. All reviewer
builds and experiments were done in `/tmp` copies; `git status` stayed clean and
the live `~/.config/nnn/.selection` was never written.

## 8. Why external selections are read-only, and how to make them editable

### 8.1 The real reason (Fact)

`nnn` stores the selection in two places that are not kept in sync:

| Storage | Scope | Written by | Read by |
|---|---|---|---|
| `pselbuf` + `selbufpos` + `nselected` | in-memory, per process | `appendfpath()` (line 1803) | most of the UI and `editselection()` |
| `selpath` file | on disk, shared by all instances | `writesel()` (line 1788) | external consumers (`xargs`, plugins) |

The in-memory format is one NUL-terminated path per entry, so
`selbufpos == sum(len_i) + N`. Every `writesel()` call passes `selbufpos - 1`
(lines 2075, 2121, 2134, 2227, 2333, 10349), which strips the final NUL. So the
on-disk format is NUL-**separated**, not NUL-terminated: `N` paths produce `N-1`
NUL bytes. `Fact`: verified directly by reading those call sites, and this repo's
own `plugins/cpmv:70-71` documents the same thing.

`editselection()` gates on `selbufpos` alone (line 2236). It never looks at
`selpath` before deciding. And here is the actual root cause:

> `Fact`: **there is no inverse of `writesel()` anywhere in `src/nnn.c`.**
> Nothing in the codebase ever reads `selpath` back into `pselbuf`.

The only readers of the selection file are `confirm_force()` (line 1750, counts
entries only, never reads paths), `listselfile()` (line 1877, shells out to
`tr`), `cpmv_rename()` (line 2841, shells out to `tr`), and external
`xargs -0` consumers. So when `selbufpos == 0`, `editselection()` has no way to
obtain the paths, and falls back to the read-only dump. The restriction is a
consequence of missing code, not a deliberate safety design.

`Fact` (from `git log -S`): the guard arrived in `589065f9` (2020-01-14,
"Remove redundant question"), which replaced an earlier y/n prompt. Commit
`714d8063` (2021-04-28) only *added* the explanatory comment "External selection
is only editable at source" after the fact.

### 8.2 The concurrency model that retroactively justifies it (Fact)

Even though it was not designed as a concurrency guard, one is warranted:

- `writesel()` is `open(O_CREAT|O_WRONLY|O_TRUNC)` plus `write()`. There is no
  locking anywhere: `grep` for `flock`/`lockf`/`F_SETLK`/`O_EXCL` in `src/nnn.c`
  returns nothing. There is no atomic write-then-`rename`.
- Every process treats its own `pselbuf` as authoritative and blindly rewrites
  the whole shared file on any selection change.
- Therefore a non-owner's edit would be silently reverted by the owner's next
  selection keypress.

The only existing cross-process reconciliation is `handle_event()` (line 3580):
`if (nselected && isselfileempty()) clearselection();`. That handles only the
file becoming *empty*, and fires on a directory-watch event; `selpath` itself is
never watched.

### 8.3 Data loss that already exists today (Risk)

`Risk`: these are not hypothetical. They are properties of the current shared
model, independent of any change discussed here. An investigating agent reported
reproducing the first three with two live instances; `Not verified` by me
directly, though the code paths read exactly as described.

| # | Scenario | Mechanism |
|---|---|---|
| 1 | Pane B's first selection erases pane A's entire selection | `addtoselbuf()` ends at line 2121 with a full `O_TRUNC` rewrite of B's local buffer |
| 2 | Quitting either pane deletes the other's selection | `unlink(selpath)` on normal exit (line ~11960) and in `printerr()` (line 1656) |
| 3 | `xlink()` wipes the shared file | With `selbufpos == 0` the loop at line 5428 runs zero times, so `count == nselected` (0 == 0) fires `clearselection()` |

`Decision`: this matters for framing. Making external selections editable does
not make the shared model safe; the everyday exposure above is larger and more
likely than any edit-window race. Fixing one without acknowledging the other
would give a false sense of safety.

### 8.4 Why the "can only shrink, never grow" checks exist (Fact)

Two guards in `editselection()` reject an edited list that grew:

- Line 2283, `else if (sb.st_size > selbufpos)`. This is a **capacity check**.
  The `!allowemptysel` path never calls `selbufrealloc()`, and the read at line
  2289 is capped at `selbuflen`. Since `selbufpos <= selbuflen` always holds,
  `st_size <= selbufpos` guarantees the edited file fits. Remove this guard
  without adding a realloc and you get a silently truncated read plus a corrupt
  trailing path.
- Line 2327, `if (!allowemptysel && (lines > nselected))`. This is **policy**.
  The selection feeds destructive consumers (`cpmvrm_selection()` including
  `SEL_TRASH` and `SEL_RM_RF`, `xargs -0 sh -c`, `archive_selection()`). A typo
  or stray paste in the editor would become a real path handed to `rm` or `mv`.
  Adding paths is allowed only through `editselection(TRUE)`, whose single
  caller (line 2880) fires only when the selection file is empty and the
  operation is `SEL_CP` or `SEL_MV`, never a delete.

### 8.5 Options

All four options have now been adversarially reviewed. `A1`, `A2` and `A3` each
got **two independent reviewers** who read the source, and in several cases
applied the patch to a throwaway copy, built it with `./build.sh`, and drove it
under a pty. No option came back `SOUND`.

| Option | Mechanism | Change type | Effort (real) | Verdict |
|---|---|---|---|---|
| `A1` `readselfile()` | Load `selpath` into `pselbuf`, then edit normally | C change | medium | `FLAWED` x2, fixable |
| `A2` Atomic write + edit token | `rename(2)` write, plus optimistic stat token | C change | medium-large | `FLAWED` x2, L1 salvageable |
| `A3` `seledit` plugin | Plugin edits the shared file directly | plugin only | small to build | `FLAWED` x2, two reproduced defects |
| `A4` Per-instance `NNN_SEL` | Separate files plus a `selpush` transfer plugin | config | small | **Rejected** |

### 8.5.1 The finding that dominates everything: `selbufpos` is overloaded

`Fact`, converged on independently by four reviewers across `A1` and `A2`:

> `selbufpos` is not just a byte count. It is nnn's de facto **"this instance
> owns a selection"** predicate, and it is read in at least seven places outside
> `editselection()`.

Any design that makes `selbufpos` non-zero in a pane that did not make the
selection silently changes behavior everywhere else that flag is read. The known
readers are:

| Line | Consumer | What changes if a non-owning pane adopts |
|---|---|---|
| 1701, 1708 | `get_cur_or_sel()` | With `-u` (`cfg.prefersel`), the current-vs-selection prompt disappears for `x`/`X` |
| 2178 | `endselection()` | Runs instead of returning early in list mode |
| 2840 | `cpmv_rename()` | Switches from the file branch to the memory branch |
| 3830 | `dnd_prepare_data()` | A mouse drag exports the whole adopted selection |
| 8531 | `send_to_explorer()` | In fifomode, Enter ships the adopted selection and clears it |
| 10967 | `SEL_QUITERR` (`Q`) | Turns the pane into a picker |
| 11952 | picker exit write | Writes the adopted selection to stdout |

`Risk`: the original `A1` proposal audited exactly one of these and got it
wrong. It claimed "the DND path does not touch `pselbuf`", but
`dnd_prepare_data()` at line 3830 reads it directly. This fork builds with
`O_DND=1`, so that path is live.

### 8.5.2 Review findings per option

#### A1: `readselfile()` - core is correct, surroundings are not

`Fact`: reviewer 1 tried to refute the core arithmetic and **could not**. They
applied the patch to `/tmp/nnnrev`, built it with the fork's real flags, and ran
a byte-level harness:

- Buffer arithmetic exactly right (3 paths, `sum=45`: disk `st_size=47 =
  sum+N-1`; after adopt `selbufpos=48`, `nselected=3`).
- No heap overflow via `invertselbuf()`; `nmarked <= nselected` always holds.
- Both grow-guards keep their exact meaning. Confirmed the editor temp file is
  exactly `selbufpos` bytes, guard 2283 passes on a deletion and **bites** on an
  added line.
- List mode is **not** a corruption bug (the earlier concern was wrong):
  adopted paths are `listroot`-form, so `is_prefix()` at 1850 fails and
  `seltofile()` writes them verbatim.
- It compiles clean with `./build.sh`.

What the reviews found instead:

- `Risk` **reproduced end to end**: with the patch applied, pressing `E` then
  `Q` in the adopting pane turns it into a picker, prints the adopted paths to
  stdout, returns `EXIT_SUCCESS` instead of `EXIT_FAILURE`, and stops unlinking
  the shared selection.
- `Risk` **missing short-read check**. `count = read(fd, pselbuf, sb.st_size)`
  is never compared to `sb.st_size`. A short read appends a NUL mid-path, and a
  truncated absolute path is often still a *valid* path to an ancestor directory
  (`/home/u/Documents/report.pdf` becomes `/home/u/Documents`), which then gets
  written back and later handed to `rm -rf`. Fix: `if (count != sb.st_size)
  return FALSE;`.
- `Risk`: the "optional hardening" in the original proposal is itself
  destructive. Its guard makes `readselfile()` reachable with `selbufpos != 0`,
  and `selbufpos = 0;` executes *before* the `if (count <= 0) return FALSE;`
  bail, so a failed read destroys a live local buffer. Its change detector also
  uses whole-second `st_mtime`, so it is blind to the exact fast
  select-left/edit-right sequence it exists to catch.
- `Correction`: one earlier worry was withdrawn. `startselection()` truncating
  the shared file is **not** new data loss; today's `SEL_SEL` path does an
  `O_TRUNC` rewrite anyway, so net on-disk bytes are unchanged. Both reviewers
  agreed on this.

`Decision`: A1's 25-line core is sound. The honest effort is **medium**, not
small: the diff is small, but shipping it requires the short-read bail plus an
explicit before/after decision for each of the seven `selbufpos` consumers.

#### A2: L1 is worth doing, L2 is dangerous

`Fact`: both reviewers rejected layer 2 for the same reason, arrived at
independently.

- Reviewer 1: `startselection()` (1905-1909) and the other `selbufpos` readers
  are unaudited, same overloading problem as A1 but without A1's compensating
  care.
- Reviewer 2 found the sharper version: L2 makes `editselection()`'s
  `emptyedit:` label reachable from a non-owning pane. That label calls
  `clearselection()`, which calls `writesel(NULL, 0)`. **Five** `goto`s reach it,
  and two are ordinary user actions (adding a line, or an editor that grows the
  file). So "press `E` in the wrong pane and type one extra path" silently
  truncates the other pane's entire selection, with no confirmation and no
  message.

`Correction` to a claim in Part 2 above and in the proposal: `writesel()` is
**not** the only writer, and the no-trailing-NUL invariant is **not** universal
in this repo. `main()` writes `selpath` directly in picker mode (11953-11954),
bypassing `writesel()`. And `plugins/dragdrop:46` does
`printf '%s\0' "$@" >> "$selection"`, appending a NUL after *every* path
including the last. Any format assumption must tolerate both forms.

`Decision`: keep **L1 only** (atomic write-temp-then-`rename`). It is
independently useful and does not touch `selbufpos`. It needs a real fallback
for `open(tmp)` failure, which the sketch promised in prose but omitted in code.

#### A3: two defects reproduced by execution

`Fact`: reviewers ran the actual script rather than only reading it.

- `Risk` **reproduced**: `trap '... rm -f "$tmp" "$out"' EXIT INT HUP TERM`
  makes `Ctrl-C` during the editor **destructive** rather than a cancel.
  `/bin/sh` here is `dash`, which runs the INT handler and then *resumes*. The
  reviewer reproduced the full chain with a stand-in editor and `kill -INT`: the
  trap deletes `$tmp`, the "unchanged" guard is bypassed, `$out` is created
  empty, and the user who just pressed `Ctrl-C` to cancel is prompted to clear
  the shared selection. Given how slow the editor was, `Ctrl-C` at that moment
  is exactly what a user would do.
- `Risk` **reproduced**: adding a non-absolute line, the plugin's headline
  feature over built-in `E`, silently corrupts the list. Lines `/etc/hosts`,
  `notes.txt`, `/etc/passwd` produce one NUL and the bogus entry
  `/etc/hosts\nnotes.txt`, silently dropping an entry. `sed -z` only splits
  before a `/`.
- `Risk`: list mode defeats the design. `endselection()` (2168) rewrites
  `selpath` from the stale buffer at 2227 and runs immediately before paste, the
  `%j` prompt, and plugin invocation, so the edit is reverted by the very
  keypress meant to consume it.
- `Fact`, to the proposal's credit and verified by both reviewers: the byte
  round trip is exactly right (`cmp` identical, N-1 NULs, no trailing NUL), and
  the non-obvious `NNN_PIPE` `-` handshake analysis is correct.

`Correction`: reviewer 1 claimed the growth problem is "exactly what guard 2327
exists to prevent". Reviewer 2 showed this misattributes a pre-existing hole:
nnn has **no** cross-instance protection at all, and the same under-reported
delete is already reachable in stock nnn with two panes. What the plugin
genuinely adds is that never-selected, unvalidated paths can enter the set that
`rm` consumes.

#### A1: `readselfile()` (recommended)

Add a loader and call it from the one guard line:

```c
if (!allowemptysel && !selbufpos && !readselfile())
	return listselfile();
```

The loader reads `selpath` into `pselbuf`, appends a NUL if the last byte is not
one (converting the separated on-disk form back to the terminated in-memory
form), sets `selbufpos = count`, and sets `nselected` to the NUL count.

`Fact`, self-verified: this arithmetic is exactly right. On disk `st_size =
sum + N - 1`; after appending the NUL, `selbufpos = sum + N`, matching what
`appendfpath()` would have produced, and the NUL count is exactly `N`. Getting
`nselected` right is not cosmetic: `invertselbuf()` (line 1974) does
`malloc(nselected * sizeof(selmark))`, so an off-by-one here is a heap overflow,
not a display bug.

The elegant part: **adoption restores the invariant the grow-guards depend on**,
so neither guard needs weakening. They go back to comparing against a real local
buffer instead of against zero, which is what they were written for.

`Risk`, flagged by a second agent and not yet resolved: list mode (`-l`,
`listpath` set) makes `seltofile()` rewrite `listpath` to `listroot` on write
(lines 1841-1858), so the on-disk bytes differ from `pselbuf`. A naive re-read
would corrupt every path under `listroot`. Guard with `if (!listpath)`.

#### A2: Atomic writes plus an optimistic edit token

Independent of A1 and worth doing on its own merits: make `writesel()` write to
a temp file in the same directory and `rename(2)` over `selpath`. That closes
the truncate/read race for every external consumer at a cost of about 20 lines.

Layer two: capture a stat token (`ino` + `size` + `mtime` including nanoseconds)
immediately before `spawn(editor)` and re-check on return, refusing the
write-back if another pane touched the file meanwhile.

`Risk`: `rename(2)` gives `EXDEV` if the temp file is not on the same
filesystem, so derive the temp name from `dirname(selpath)`, never `/tmp`.
`Risk`: refusing the write-back loses the user's editor work; keep the edited
temp file and report its path instead of unlinking it.
`Open question`: real `flock` was judged unworkable because the actual readers
are shell pipelines (`xargs`, `tr`) that would need to cooperate.

#### A3: `seledit` plugin (no C change)

A POSIX `sh` plugin converts the NUL-separated file to one path per line, opens
`$EDITOR`, and writes it back. Works from either pane and can also *add* entries,
which built-in `E` refuses.

`Risk`, and this is the trap: the owning pane still holds a stale `pselbuf`, and
its next selection keypress rewrites the file from that stale memory, silently
reinstating the pre-edit list. The plugin can inoculate only the pane it was
launched from (via the `NNN_PIPE` `-` op), never the peer. Usable, but it comes
with a workflow rule ("do the paste next, do not go back and re-select"), which
is exactly the kind of hidden constraint that produced the original bug report.

#### A4: Per-instance `NNN_SEL` plus a push plugin (rejected)

`Decision`: **rejected.** This was the one option that got a full adversarial
review, and the review found it does not fix the bug.

The plumbing is sound: an agent traced every cross-pane consumer and confirmed
paste, trash, archive, rename and `%j` are all **file**-based, not memory-based,
so an explicit push would keep them working. But:

- `E` already works today in the pane that made the selection, shared file or
  not, because `editselection()` gates on in-memory `selbufpos` and never
  consults `selpath`. Per-pane files change nothing on that path.
- After a push, the receiving pane still has `selbufpos == 0` with a non-empty
  file, so it hits the identical guard and shows the identical read-only dump.
  The proposal reproduces the reported bug rather than removing it.
- It costs an extra keypress on every cross-pane `p`/`v`/`w`/`x`/`X`/`z`.

The review also found two real bugs in the proposed transfer script (appending
without a separating NUL glues two paths into one garbage entry; the entry
counter reports `N-1` because of the stripped trailing NUL).

### 8.6 Recommendation (after review)

`Decision`: **A1 plus A2 layer one, in two separate steps, in this order.**

**Step 1, do this regardless: A2 layer one (atomic `writesel()`).** Write to a
temp file in the same directory as `selpath` and `rename(2)` over it, with a
fallback to the old in-place write if `open(tmp)` fails. It touches no
`selbufpos` semantics, closes a real torn-read race for every external consumer,
and is useful whether or not cross-pane editing ever ships.

**Step 2, if you want cross-pane `E`: A1, with three mandatory additions** that
the review made non-optional:

1. `if (count != sb.st_size) return FALSE;` after the read. Without it a short
   read produces a mangled-but-plausible path that reaches `rm`.
2. An explicit decision for each of the seven `selbufpos` consumers in the table
   in section 8.5.1. At minimum, `SEL_QUITERR` (`Q`) must not turn the adopting
   pane into a picker; that was reproduced.
3. Drop the proposal's "optional hardening" as written. It is destructive
   (clears `selbufpos` before its failure bail) and its second-granularity
   `st_mtime` detector is blind to the case it targets. If you want it, it needs
   `st_ino` plus `st_dev` plus `st_mtim.tv_nsec`, and must not mutate state
   before it can fail.

What I would **not** do:

- **A3 as written.** Two defects were reproduced by execution, one of which
  turns `Ctrl-C` into "destroy the shared selection". Both are small fixes
  (drop `INT HUP TERM` from the trap, reject added lines not matching `^/`), but
  the design still leaves `E` and `;m` with two different safety models, and
  list mode silently reverts it.
- **A2 layer two.** Superseded by A1, which does the same job with more care.
- **A4.** Refuted; it reproduces the bug rather than fixing it.
- **Removing the grow-guards.** Line 2283 is load-bearing for memory safety;
  line 2327 is load-bearing for not handing typos to `rm`.
- **Un-sharing the selection file.** The cross-pane paste workflow depends on it.

`Open question`: even with A1, the *other* pane's stale in-memory buffer can
still clobber the result on its next selection keypress. Fully closing that
needs a resync before `SEL_SEL` as well. Decide how far to go before starting.

`Risk`, worth stating plainly: nnn has **no** cross-instance selection
protection today, and the reviews surfaced several pre-existing destructive
paths that none of these options fix (`xlink()` wiping the shared file from a
non-owning pane; either pane's exit `unlink()`ing it; an under-reported `x`/`X`
confirmation count). Shipping A1 makes `E` work cross-pane; it does not make the
shared-selection model safe. Do not let it imply otherwise.

## 9. Making `$EDITOR` start fast for `nnn`'s scratch edits

### 9.1 What is actually slow (Fact)

`Fact`, measured on this machine: Neovim itself is fine. The problem is two
specific config settings.

| Command | Startup |
|---|---|
| `nvim --headless -u NONE +qa` | 0.01 s |
| `nvim` with the real LazyVim config | 247-267 ms |
| `nvim --clean` | 9-12 ms |
| `NVIM_APPNAME` profile with a 4-line `init.lua` | 18-19 ms |

CPU startup is ~150-250 ms, which is not what the user sees. The perceived hang
is a Mason window plus 1-10 s of blocking network.

**Root cause 1: `nvim-java` runs `setup()` before `mason.setup()`.**
`Fact`, proven by an agent's live runtime probe (no files modified):

```
PROBE is_outdated=true
PROBE >>> refresh_registry() CALLED - unconditional network Registry.update()
PROBE >>> mason.ui.open() CALLED - this is the overlay
```

LazyVim loads `~/.config/nvim/lua/config/options.lua` while `lazy.nvim` is still
sourcing plugin specs, so `mason.setup()` has not run and mason's registry source
list is literally empty. `nvim-java` then cannot find `java-debug-adapter`,
concludes its dependencies are outdated, opens the Mason UI over the buffer, and
fires a registry download that has **no TTL check** (unlike `Registry.refresh`,
which is gated at 24 h). Corroborating on-disk evidence: `mason.log` contains
199 `Cannot find package "java-debug-adapter"` entries against 203 logged setups,
and the measured delay is median 2 s, max 10 s.

Side effect: `nvim-java` then returns early, so it is left permanently
half-configured on every startup.

**Root cause 2: `checker = { enabled = true }`** in `lua/config/lazy.lua:32`
runs unthrottled `git fetch` against `github.com` for all 86 installed plugins
whenever the last check is over an hour old. `Fact`: all 86
`~/.local/share/nvim/lazy/*/.git/FETCH_HEAD` files carry mtimes within ~1 s of
each other, matching `checker.last_check` in `state.json`. Those are exactly the
`tokyonight`/`which-key`/`yanky` fetches seen in the original live trace.

**Not a cause**: `defaults = { lazy = false }` is a no-op. `false` is already
`lazy.nvim`'s own default; the line is LazyVim starter boilerplate.

### 9.2 Options

| Option | What it does | Change type | Effort | Keeps your nvim setup? |
|---|---|---|---|---|
| `B1a` Register mason registries first | Kills the overlay and the per-startup download | nvim config | trivial | Yes, fully |
| `B1b` Disable the update checker | Kills the 86-plugin fetch storm | nvim config | trivial | Yes (use `:Lazy check` manually) |
| `B1c` Make `nvim-java` load on `ft=java` | Removes it from the non-Java startup path | nvim config | small | Yes, with ordering risk |
| `B2` Route scratch edits to a fast profile | `nnn`'s temp buffers get a stripped nvim | wrapper script | small | Separate minimal profile |

#### B1a (primary, verified): register the registries before `nvim-java`

In `~/.config/nvim/lua/config/options.lua`, immediately before the existing
`require('java').setup({...})`:

```lua
require('mason').setup({
  registries = {
    'github:nvim-java/mason-registry',
    'github:mason-org/mason-registry',
  },
})
```

`Fact`, proven by the same probe technique: with the registries registered first,
`is_outdated` becomes `nil`, no overlay opens, no network call fires, and
`JavaPostSetup` fires for the first time. Trades away nothing functional;
LazyVim's later `require("mason").setup(opts)` de-duplicates.

#### B1b: turn off the update checker

In `~/.config/nvim/lua/config/lazy.lua:32`, change `checker = { enabled = true }`
to `checker = { enabled = false }` and run `:Lazy check` by hand when you want
updates. Alternative if you want to keep it: raise `frequency` well above the
3600 s default.

#### B2: a fast profile for `nnn`'s scratch buffers only

`Fact`: `nnn`'s scratch files are `mkstemp` on the pattern `/.nnnXXXXXX`
(`messages[STR_TMPFILE]`, line 709; `create_tmp_file()`, line 1592). The `.nmv`
batch-rename plugin uses the same pattern. So `argv[1]` uniquely identifies a
scratch buffer, and a one-word wrapper can dispatch on it:

```sh
#!/bin/sh
# nnn scratch buffers are mkstemp "/.nnnXXXXXX"
case "$1" in
    /tmp/.nnn??????|"${TMPDIR:-/tmp}"/.nnn??????)
        exec env NVIM_APPNAME=nnnfast nvim "$@" ;;
esac
exec nvim "$@"
```

Set it as both `VISUAL` and `EDITOR`. Because it is a single word it is safe
everywhere, and because it dispatches on the path, `git commit` still gets the
full editor.

**Keeping your basic settings (your stated requirement).** Do **not** use
`nvim --clean` for the fast branch: `--clean` skips your config entirely, so
`clipboard = "unnamedplus"` would be gone and yanks would not reach the system
clipboard. Use an `NVIM_APPNAME` profile instead, which costs about 8 ms over
`--clean` and keeps whatever you put in it. Create
`~/.config/nnnfast/init.lua`:

```lua
vim.opt.clipboard = "unnamedplus"   -- yank to system clipboard
vim.opt.number = true
vim.keymap.set("n", "<leader>w", "<cmd>wq<cr>")
```

`Fact`: `clipboard = "unnamedplus"` is a plain vim option with no plugin
dependency, and this machine has `xclip`, `xsel` and `wl-copy` installed on an
X11 session, so the provider works with zero plugins loaded.

`Risk`: a multi-word `$EDITOR` (for example `nvim --clean`) breaks
`plugins/suedit`, which quotes `"$EDITOR"`, and `spawn()` silently rejects
anything over 6 whitespace-separated words (`parseargs`, line 2563) by returning
`-1` with **no error message and no editor**. The one-word wrapper avoids both.

`Note`: the documented alternative (`nnn -E` with `EDITOR` fast and `VISUAL`
heavy) works for 3 of the internal edit sites but misses `export_file_list()`
(the `>` key, line 2385), which hardcodes `editor`, and is bypassed for batch
rename (`r`), which prefers the `.nmv` plugin reading `$EDITOR` directly. The
wrapper covers all of them.

### 9.3 Option `B3`: point `$EDITOR` at `lvim-new` (what the user actually did)

`Fact`: the user switched `$EDITOR` to `/home/tripham/.local/bin/lvim-new` and
reports it is fast. Investigated, and the result **confirms the root-cause
analysis** rather than sidestepping it.

`lvim-new` is a 9-line wrapper:

```sh
export NVIM_APPNAME="lvim-lazyvim"
export VIMRUNTIME="/home/tripham/Dev/Playground_Terminal/neovim/runtime"
exec -a lvim-new "/home/tripham/Dev/Playground_Terminal/neovim/build/bin/nvim" "$@"
```

So it is already exactly the `NVIM_APPNAME` mechanism `B2` proposed, pointed at
a separate LazyVim profile (`~/.config/lvim-lazyvim`) on a locally built
Neovim.

#### Why it is faster (Fact, measured)

| Profile | Plugins | `nvim-java` present | `Cannot find package` in `mason.log` | Headless startup |
|---|---|---|---|---|
| `nvim` (main config) | 86 | **yes** | 205 | 203-216 ms |
| `lvim-new` (`lvim-lazyvim`) | **131** | no | 0 | 132-159 ms |

The decisive column is not plugin count. `lvim-lazyvim` loads **more** plugins
(131 vs 86) and is still faster, which rules out general config weight. What it
does not have is `nvim-java`, and therefore it never hits root cause 1: no
`mason.setup()` ordering bug, no Mason overlay, and no unconditional blocking
registry download. Its `mason.log` has zero `Cannot find package` entries
against 205 in the main config.

`Decision`: this is a legitimate fix, not a workaround. It removes the only
*blocking* cost. The remaining 132-159 ms is ordinary startup.

#### Does it meet the clipboard requirement? Yes (Fact, verified)

Both layers are present:

- `opt.clipboard = "unnamedplus"` is set by LazyVim's own defaults
  (`lazy/LazyVim/lua/lazyvim/config/options.lua:57`, guarded on
  `SSH_CONNECTION`).
- `~/.config/lvim-lazyvim/lua/config/options.lua:64` additionally pins an
  explicit `vim.g.clipboard` provider using `xclip`, on non-Wayland sessions.

This session is X11 with `xclip`, `xsel` and `wl-copy` all installed, so yank to
system clipboard works in the scratch buffer. This is strictly better than the
`nvim --clean` idea in `B2`, which would have dropped it.

#### One thing it does not fix (Risk)

`Fact`: `~/.config/lvim-lazyvim/lua/config/lazy.lua:52` has
`checker = { enabled = true, notify = false }`. The checker **is** running: all
131 `FETCH_HEAD` files carry mtimes matching `checker.last_check` to the second.

So root cause 2 is still present in this profile, just **silent** rather than
absent. It is a background `git fetch` against 131 repositories, not a blocking
stall, which is why it does not feel slow. `notify = false` means the user never
sees it. If the background network churn is unwanted, set `enabled = false` here
too and use `:Lazy check` manually.

`Risk`: `lvim-new` runs a **locally built** Neovim from a source tree
(`Dev/Playground_Terminal/neovim/build/bin/nvim`) with `VIMRUNTIME` pointed at
that tree. If that tree is rebuilt, moved, or cleaned, `$EDITOR` breaks for nnn.
A system `nvim` would not have that coupling. `Open question`: whether to
guard the wrapper with a fallback if the built binary is missing.

`Note`: `lvim-new` is a single word as far as `spawn()` is concerned, so it is
safe with `parseargs()` (no multi-word `$EDITOR` hazard), and
`/home/tripham/.local/bin` is on the `PATH` inherited by nnn's children.

### 9.4 Recommendation

`Decision`: **keep `lvim-new` as `$EDITOR` (`B3`), and still apply `B1a` to the
main config.**

Reasoning:

1. `B3` already solves the reported symptom for nnn, and it satisfies the
   clipboard requirement. No further work needed for the nnn path.
2. `B1a` is still worth applying, because the main `nvim` config is **also what
   the user edits real files with**, and it is currently broken in a way that
   goes beyond slowness: `nvim-java` returns early on every startup, so it is
   left permanently half-configured (`JavaPostSetup` never fires). Fixing the
   ordering repairs that, not just the delay.
3. `B1b` / `B1c` are optional. Consider `checker = { enabled = false }` in
   **both** profiles if you would rather not have 86 + 131 background fetches.

| Option | Fixes nnn scratch edits | Fixes real-file editing | Keeps clipboard | Status |
|---|---|---|---|---|
| `B3` `lvim-new` | Yes | No (separate profile) | Yes | **In use** |
| `B1a` mason ordering | n/a | Yes, and repairs `nvim-java` | Yes | Recommended |
| `B1b` checker off | Minor | Minor | Yes | Optional |
| `B2` wrapper + minimal profile | Yes | n/a | Only with a custom profile | Superseded by `B3` |

`Not verified`: `B1a`, `B1b` and `B1c` have not been applied. The probes that
produced these findings were read-only. The measurements in this section are
real and were run on this machine; the diffs are proposed, not tested in place.
`B3` is in use by the user, and its properties above were measured, but its
end-to-end behavior inside nnn (`E` opening the scratch list in `lvim-new`) is
`Not verified` by me and needs the user's confirmation.

## 10. Cross-pane selection live-sync

### 10.1 Purpose

Two `nnn` instances in tmux share one selection file (`~/.config/nnn/.selection`, because `NNN_SEL` is unset). Each instance also keeps a private copy in `pselbuf` / `selbufpos` / `nselected` (declared at `src/nnn.c:477`, `src/nnn.c:455`, `src/nnn.c:449`). Once an instance owns a non-empty private copy it never re-reads the file again, so changes made by the other instance are invisible to it.

This section specifies a poll that closes that gap: an instance notices when the on-disk selection has stopped matching its private copy, and replaces the private copy with the file contents.

### 10.2 Problem statement and the semantic decision

`Fact` (from the reproduced bug report, and confirmed by reading the code):

1. Select 2 files in LEFT. `SEL_SEL` at `src/nnn.c:10435-10437` appends to `pselbuf` and calls `writesel()`.
2. In RIGHT press `E`. `editselection()` at `src/nnn.c:2308-2312` sees `!selbufpos`, calls `readselfile()` (`src/nnn.c:1926`) and adopts. The user deletes every line and saves, so `writesel()` at `src/nnn.c:2421` writes a 0-byte file and RIGHT's local state is emptied.
3. Back in LEFT press `E`. LEFT still lists the original 2 files. LEFT's `selbufpos` was never 0, so `editselection()` skips the adopt branch entirely and edits its own stale copy.
4. In RIGHT press `E` again: `readselfile()` fails on the empty file, `listselfile()` (`src/nnn.c:1904`) returns `FALSE`, `editselection()` returns 0 and `SEL_SELEDIT` prints `MSG_0_SELECTED` (`src/nnn.c:10521-10523`).

Step 3 is the defect. Nothing propagates *into* an instance that already owns a selection.

`Decision 1 - the file is authoritative.` When the on-disk selection differs from the local copy, the local copy loses. Justification: the file is the only shared state, every mutation path already writes it immediately (`src/nnn.c:10437`, `src/nnn.c:2189`, `src/nnn.c:2202`, `src/nnn.c:2143`, `src/nnn.c:2421`), and the alternative (last-writer-in-memory wins) has no way to merge two divergent buffers without inventing a conflict UI.

`Decision 2 - the sync never writes selpath.` It only reads. Every write path is a data-loss vector for the peer, and `clearselection()` (`src/nnn.c:1981-1987`) calls `writesel(NULL, 0)` which truncates the shared file. Dropping local state must therefore be done by hand, exactly as the existing revert path in `editselection()` already does at `src/nnn.c:2364-2368`.

`Decision 3 - default on, with a kill switch.` Enabled by default because the current behavior is a correctness bug, the cost is one `stat(2)` per main-loop iteration, and there is already a partial precedent in-tree (`handle_event()` at `src/nnn.c:3668-3672` clears the local selection when the shared file goes empty). Opt out with `NNN_NO_SELSYNC=1`. Precedent for a plain `getenv()` outside `env_cfg[]`: `NNN_DND_OSC72` at `src/nnn.c:3768`. Hard-disabled in picker mode (`-p`) and while `listpath` is set (`-l`); see 10.6.

`Decision 4 - accept the ownership side effects.` After a sync, the pane genuinely owns the peer's selection, so `Q` (`SEL_QUITERR`, `src/nnn.c:11055`) will dump it to stdout and `-u` / `cfg.prefersel` (`src/nnn.c:1708`) will skip the current-vs-selection prompt. That is the intended meaning of "both panes show the same selection". The "peek without side effects" revert in `editselection()` (`src/nnn.c:2352-2368`) stays in the tree: it still fires when the sync is disabled or suppressed.

### 10.3 Chosen trigger: `stat(2)` poll at the `browse()` drain point

The user asked to "re-sync the selections whenever the current active/focus cursor leaves it". The direction that actually fixes step 3 is resync on focus *return*, and an unfocused pane receives no keystrokes, so "the state is correct by the time the next key is processed" is functionally equivalent to focus-in and needs no terminal support at all.

`Decision` - poll `selpath` with one `stat(2)` at the top of the `browse()` main loop, at the existing drain point (`src/nnn.c:9787-9790`, immediately before `sel = nextsel(presel);` at `src/nnn.c:9792`).

`Fact` - that point is reached both after every keypress and about once per second while idle: `settimeout()` is `timeout(1000)` (`src/nnn.c:899`); on a timeout `nextsel()` returns 0, `browse()` falls into `default:` at `src/nnn.c:11064` and does `goto nochange` at `src/nnn.c:11074`, returning to `nochange:` at `src/nnn.c:9774`.

`Decision` - a focus-out hook is not needed and is not specified. Every selection mutation already calls `writesel()` immediately (see 10.2), so there is nothing buffered to flush on focus loss.

#### Trigger comparison

| Option | Works without terminal/tmux support | Survives `writesel()`'s `rename(2)` | Cost | Verdict |
| --- | --- | --- | --- | --- |
| Terminal focus events (`ESC[?1004h`, `ESC[I` / `ESC[O`) | No | n/a | High | Rejected |
| `inotify` watch on `selpath` itself | Yes | No | Low | Rejected |
| `inotify` watch on `dirname(selpath)` | Yes | Yes (`IN_MOVED_TO`) | Medium | Rejected |
| `stat(2)` poll at the drain point | Yes | Yes | 1 syscall per iteration | **Chosen** |

Why focus events were rejected, plainly:

- `Fact` - `nnn` has no focus-event support. Nothing in `src/nnn.c` enables mode 1004 or parses `ESC[I` / `ESC[O`.
- `Fact` - tmux only requests and forwards focus events when `focus-events` is on, and only "if supported" by the outer terminal (`man tmux`, `focus-events [on | off]`). It is not set in `~/.config/tmux/`. The fix would require the user to change tmux config, and would silently do nothing on terminals that do not implement 1004 (common over `ssh`, in `screen`, in some multiplexed setups).
- `Risk` - `ESC[I` / `ESC[O` collide with `nnn`'s Alt-key handling in `nextsel()` (`src/nnn.c:4629-4665`): an `ESC` followed by any other character is rewritten to `';'`, which is bound to `SEL_PLUGIN` (`src/nnn.h:263`). Getting the parse wrong makes stray focus events open the plugin prompt. The OSC-72 code at `src/nnn.c:4636-4647` already needs a 100 ms timed peek because tmux splits escape sequences across reads; a focus parser inherits that same fragmentation problem.
- The payoff over a `stat(2)` is zero: the poll already produces a correct screen before the first post-focus keystroke is acted on.

Why `inotify` on `selpath` was rejected:

- `Fact` - `writesel()` now writes a sibling temp file and `rename(2)`s over `selpath` (`src/nnn.c:1798-1817`). The watch descriptor follows the *old* inode, so `IN_MODIFY` stops firing after the first peer write. Watching the parent directory for `IN_MOVED_TO` would work, but `inotify_wd` is a single descriptor reused for the browsed directory (`src/nnn.c:876`, added at `src/nnn.c:9745-9746`, removed at `src/nnn.c:9687-9689` and `src/nnn.c:10263-10265`), so a second watch means new state, new lifetime rules, and a `#ifdef` fork for `BSD_KQUEUE` (`src/nnn.c:4706`) and `HAIKU_NM` (`src/nnn.c:4714`). A `stat(2)` is portable and needs none of it.
- `selpath` may not exist yet, so the watch would need lazy (re)arming anyway.

### 10.4 The sync function

Two new functions plus one static struct. `Decision` - place them immediately above `static int nextsel(int presel)` (currently `src/nnn.c:4579`). They must sit after `g_dnd_b64` (`src/nnn.c:3688`) and after `resetselind()` (`src/nnn.c:1960`) and `selbufrealloc()` (`src/nnn.c:1842`), which the sketch below uses.

```c
/*
 * ===== Cross-pane selection live-sync =====
 *
 * selpath is shared by every nnn instance that does not override $NNN_SEL, but
 * each instance also keeps a private copy in pselbuf/selbufpos/nselected. Once
 * an instance owns a non-empty private copy it never re-reads the file, so a
 * change made by another instance stays invisible to it.
 *
 * syncselfile() closes that gap. The file is authoritative; the local copy is
 * replaced when they differ. This code NEVER writes selpath: clearselection()
 * would truncate a selection this instance does not own.
 */
static struct {
	dev_t dev;
	ino_t ino;
	off_t size;
	time_t mtsec;
	long mtnsec;
	bool valid;  /* holds a previous observation */
	bool exists; /* selpath existed at that observation */
} g_selstamp;

static bool g_selsync; /* set in setup_config() */

/*
 * Read selpath into a fresh heap buffer in pselbuf format: every path NUL
 * terminated, including the last one. Returns NULL on any problem, leaving the
 * caller's state untouched.
 */
static char *loadselfile(off_t size, uint_t *plen, int *pcount)
{
	char *buf;
	ssize_t count, start = 0;
	int n = 0;
	int fd = open(selpath, O_RDONLY);

	if (fd == -1)
		return NULL;

	buf = malloc((size_t)size + 1);
	if (!buf) {
		close(fd);
		return NULL;
	}

	count = read(fd, buf, (size_t)size);
	close(fd);

	if (count != size) { /* short read: refuse rather than adopt a truncated path */
		free(buf);
		return NULL;
	}

	/* plugins/dragdrop already NUL terminates every path; writesel() does not */
	if (buf[count - 1] != '\0')
		buf[count++] = '\0';

	/* Validate before adopting: every entry must be a non-empty absolute path */
	for (ssize_t i = 0; i < count; ++i) {
		if (buf[i] != '\0')
			continue;
		if ((i == start) || (buf[start] != '/')) {
			free(buf);
			return NULL;
		}
		start = i + 1;
		++n;
	}

	*plen = (uint_t)count;
	*pcount = n;
	return buf;
}

/*
 * Returns TRUE if the local selection state was replaced. The caller MUST then
 * force a full reload and redraw (presel = CONTROL('L')): pdents[] carries the
 * materialized FILE_SELECTED/FILE_SCANNED view of the old buffer and only
 * dentfill() resets it.
 */
static bool syncselfile(void)
{
	struct stat sb;
	char *buf;
	uint_t len;
	int count;
	bool exists;

	if (!g_selsync || !selpath)
		return FALSE;

	exists = !stat(selpath, &sb) && S_ISREG(sb.st_mode);

	/* Fast path: one stat(2), nothing observably changed since the last poll */
	if (g_selstamp.valid && (exists == g_selstamp.exists)
	    && (!exists || ((sb.st_dev == g_selstamp.dev)
			    && (sb.st_ino == g_selstamp.ino)
			    && (sb.st_size == g_selstamp.size)
			    && (sb.st_mtim.tv_sec == g_selstamp.mtsec)
			    && (sb.st_mtim.tv_nsec == g_selstamp.mtnsec))))
		return FALSE;

	/*
	 * Something changed, but swapping the buffer now would corrupt a
	 * half-finished operation. Return WITHOUT recording the new stamp so the
	 * change is picked up by a later poll instead of being dropped.
	 */
	if (g_state.selmode || g_state.rangesel || listpath || g_dnd_b64 || cfg.blkorder)
		return FALSE;

	/* From here the change is consumed: record the new identity */
	g_selstamp.valid = TRUE;
	g_selstamp.exists = exists;
	if (exists) {
		g_selstamp.dev = sb.st_dev;
		g_selstamp.ino = sb.st_ino;
		g_selstamp.size = sb.st_size;
		g_selstamp.mtsec = sb.st_mtim.tv_sec;
		g_selstamp.mtnsec = sb.st_mtim.tv_nsec;
	}

	/* Peer exited and unlinked selpath (main() does this at every non-picker
	 * exit). That is not "cleared": keep what we have.
	 */
	if (!exists)
		return FALSE;

	if (!sb.st_size) { /* peer cleared the selection */
		if (!selbufpos && !nselected)
			return FALSE;
		resetselind();
		findselpos = NULL;
		selbufpos = 0;
		nselected = 0;
		return TRUE;
	}

	buf = loadselfile(sb.st_size, &len, &count);
	if (!buf) {
		g_selstamp.valid = FALSE; /* transient: retry on the next poll */
		return FALSE;
	}

	/* Identical contents, typically our own write coming back */
	if ((len == selbufpos) && pselbuf && !memcmp(buf, pselbuf, len)) {
		free(buf);
		return FALSE;
	}

	/* Atomic swap of the whole selection state */
	selbufpos = 0;
	selbufrealloc(len); /* errexit()s on OOM, like every other caller */
	memcpy(pselbuf, buf, len);
	selbufpos = len;
	nselected = count;
	free(buf);

	findselpos = NULL; /* pselbuf may have moved: kill the stale cursor */
	resetselind();
	return TRUE;
}
```

`setup_config()` (`src/nnn.c:11377`) gets one line after the selection-file block that ends at `src/nnn.c:11462`:

```c
	g_selsync = !g_state.picker && selpath && !getenv("NNN_NO_SELSYNC");
```

Call site, inserted in `browse()` directly after the existing `g_dnd_resync` drain at `src/nnn.c:9787-9790` and before `sel = nextsel(presel);` at `src/nnn.c:9792`:

```c
		if (!presel && syncselfile())
			presel = CONTROL('L'); /* SEL_REDRAW: reload + repaint, consumes no key */
```

#### Why `presel = CONTROL('L')` and not a hand-rolled repaint

This is the load-bearing detail. Swapping the buffer in place is not enough, because `nnn` keeps a materialized view of `pselbuf` in two places outside the buffer:

- the per-entry `FILE_SELECTED` / `FILE_SCANNED` bits on `pdents[]` (`src/nnn.c:259-260`), which drive the on-screen `+` marker. `resetselind()` (`src/nnn.c:1960-1965`) clears only `FILE_SELECTED`; `findmarkentry()` (`src/nnn.c:2022-2028`) refuses to re-derive anything that still has `FILE_SCANNED`. The only code that clears both is `dentfill()`, which assigns `dentp->flags` fresh at `src/nnn.c:8478`.
- `findselpos` (`src/nnn.c:477`), a raw `char *` into `pselbuf`, seeded only by `scanselforpath()` (`src/nnn.c:2205-2226`), which is called from `redraw()` (`src/nnn.c:9525`) and `showselsize()` (`src/nnn.c:9580`), never from `draw_line()`.

`Fact` - the drain point does not repaint by itself: on the idle tick `nextsel()` returns 0, `browse()` hits `default:` (`src/nnn.c:11064`) and `goto nochange` (`src/nnn.c:11074`), which skips `redraw(path); statusbar(path);` at `src/nnn.c:9764-9767`. Setting `presel = CONTROL('L')` fixes this and does the flag reset for free:

1. `nextsel()` begins `wint_t c = presel;` and only calls `get_wch()` when `c == 0 || c == MSGWAIT` (`src/nnn.c:4581-4586`). `CONTROL('L')` is 12 and `MSGWAIT` is `'$'` (`src/nnn.c:196`), so no keystroke is swallowed and the idle `inotify` branch at `src/nnn.c:4681-4705` is skipped for this iteration.
2. `CONTROL('L')` maps to `SEL_REDRAW` (`src/nnn.h:220`), which sets `refresh = TRUE` (`src/nnn.c:10370-10372`).
3. `refresh == TRUE` bypasses the type-to-nav early exit at `src/nnn.c:10412-10415`, so control reaches `copycurname(); cd = FALSE; goto begin;` (`src/nnn.c:10418-10421`). The cursor position is preserved via `lastname`, and `cd = FALSE` suppresses the history/`record_visit()` push at `src/nnn.c:9731-9735`.
4. `begin:` runs `populate(path, lastname)` (`src/nnn.c:9736`) -> `dentfill()` -> every `dentp->flags` reassigned at `src/nnn.c:8478`.
5. The loop top then runs `redraw()` + `statusbar()` (`src/nnn.c:9764-9767`), which reseeds `findselpos` via `scanselforpath()` at `src/nnn.c:9525` and re-derives every `+` marker via `findmarkentry()` at `src/nnn.c:9534`. `statusbar()` prints the new `nselected` at `src/nnn.c:9013-9014`.

The invariant "`FILE_SELECTED` implies present in `pselbuf`" is therefore re-established by reload, not by hand. This is the same mechanism the existing `handle_event()` relies on: it mutates the selection asynchronously and returns `CONTROL('L')` (`src/nnn.c:3668-3672`).

`Fact` - `presel = CONTROL('L')` does **not** clear an active filter here. `clearfilter()` on `CONTROL('L')` lives inside the `if (c == 0 || c == MSGWAIT)` block (`src/nnn.c:4669-4673`), which a non-zero `presel` skips.

`Decision` - guard with `!presel` so the sync never overwrites a pending simulated key (`FILTER`, `MSGWAIT`). Losing one poll iteration is harmless: `presel` is reset to 0 at `src/nnn.c:9793` after a single use.

### 10.5 Decision table

Rows are the local state, columns the observed state of `selpath`. "Local owns" means `selbufpos != 0`.

| Local state | Disk: unchanged (stamp match) | Disk: changed, contents differ | Disk: changed, contents identical | Disk: 0 bytes | Disk: missing (`stat` fails) |
| --- | --- | --- | --- | --- | --- |
| Empty (`!selbufpos && !nselected`) | no-op | adopt, force reload | no-op, stamp updated | no-op, stamp updated | no-op, stamp updated |
| Locally owned | no-op | replace, force reload | no-op, stamp updated (this is our own write) | drop local state (no write), force reload | keep local state, stamp updated |
| Suppressed state (see 10.6) | no-op | defer, stamp NOT updated | defer, stamp NOT updated | defer, stamp NOT updated | defer, stamp NOT updated |
| `loadselfile()` failed (short read, unreadable, invalid entry) | n/a | keep local state, invalidate stamp so the next poll retries | n/a | n/a | n/a |

Notes on two cells:

- **Disk missing.** `Fact` - `main()` unlinks `selpath` on every non-picker exit, regardless of whether `NNN_SEL` was set: `} else if (selpath) unlink(selpath);` at `src/nnn.c:12048-12049`, with `selpath` taken from the environment at `src/nnn.c:11447-11449`. So closing either pane deletes the shared file while the survivor may still hold a valid selection. Treating "gone" as "cleared" would silently wipe the survivor. `Decision` - missing means *no information*: keep local state, do not write. `isselfileempty()` (`src/nnn.c:1692-1697`) folds `stat` failure and zero size into one boolean and must not be used for this decision. `Open question` - whether the survivor should re-create the file from its own buffer. Not specified here (it would be a write); the next local selection change re-creates it anyway.
- **Disk 0 bytes.** This is `clearselection()`'s `writesel(NULL, 0)` from the peer. Drop local state by hand (`resetselind(); findselpos = NULL; selbufpos = 0; nselected = 0;`), never by calling `clearselection()`, which would write. This subsumes the narrower check in `handle_event()` at `src/nnn.c:3670`; `Decision` - leave `handle_event()` unchanged, it becomes a harmless no-op once the sync has already cleared `nselected`.

### 10.6 Suppression states

The sync defers (returns `FALSE` **before** recording the new stamp, so the change is retried later) whenever any of these hold:

| State | Test | Reason |
| --- | --- | --- |
| Picker mode | `g_selsync` is FALSE when `g_state.picker` | The buffer is the program's return value, written at `src/nnn.c:12039-12047`. Silently changing it changes what the calling editor receives. |
| Opt-out | `g_selsync` is FALSE when `NNN_NO_SELSYNC` is set | Kill switch. |
| Selection mode | `g_state.selmode` | Set at `src/nnn.c:1969-1970`; a multi-select is in progress. |
| Range selection | `g_state.rangesel` | Set at `src/nnn.c:10460`; `selstartid` is a `browse()`-local index into `pdents[]` (`src/nnn.c:9599`) captured at `src/nnn.c:10469`. A swap between the two `SEL_SELMUL` presses appends the range on top of the peer's paths. |
| List mode | `listpath` | `endselection()` (`src/nnn.c:2236-2295`) round-trips the buffer through a spawn and rewrites `selpath` with `listroot`-rewritten paths at `src/nnn.c:2295`. |
| DnD in flight | `g_dnd_b64` | `g_dnd_b64` (`src/nnn.c:3688`) is built once and held while the terminal completes the drag asynchronously. |
| du mode | `cfg.blkorder` | A forced reload recomputes disk usage, which can take seconds. Matches the existing gate at `src/nnn.c:4685`. Known limit: cross-pane sync is deferred until du mode is turned off, at which point the next poll picks it up. |
| Pending simulated key | `presel != 0` at the call site | Do not clobber `FILTER` / `MSGWAIT`. |

### 10.7 Hazards that must be handled

Derived from the adversarial review of the earlier hazard audit. Where the audit's evidence was wrong, the corrected version is recorded.

| # | Hazard | Class | Mitigation in this design |
| --- | --- | --- | --- |
| H1 | `findselpos` dangles after `selbufrealloc()` moves `pselbuf` (`xrealloc()` is plain `realloc()`, `src/nnn.c:1060-1068`). `findinsel()` then computes `size_t buflen = selbufpos - (startpos - pselbuf)` at `src/nnn.c:1998` from a garbage difference: `size_t` underflow and a `memmem()` over a huge region, plus the `*(found - 1)` read at `src/nnn.c:2005`. | Memory-unsafe | `findselpos = NULL` inside the swap (`findinsel()` handles a NULL `startpos` at `src/nnn.c:1993-1995`), plus the forced reload, whose `redraw()` reseeds it at `src/nnn.c:9525`. |
| H2 | Heap overflow in `invertselbuf()`: `selmark *marked = malloc(nselected * sizeof(selmark));` at `src/nnn.c:2042`, sized from `nselected`, while pass 1 (`src/nnn.c:2050-2083`) writes one entry per `pdents[]` row that is both `FILE_SELECTED` and present in `pselbuf`. Safe only while "`FILE_SELECTED` implies present in `pselbuf`" holds. | Memory-unsafe | The forced reload re-derives every flag from the new buffer in `dentfill()` (`src/nnn.c:8478`), so the invariant is never broken across a keypress boundary. |
| H3 | Shared-file truncation: `rmfromselbuf()` ends `nselected ? writesel(pselbuf, selbufpos - 1) : clearselection();` at `src/nnn.c:2202` (same tail in `invertselbuf()` at `src/nnn.c:2143`). With stale flags, deselects can drive `nselected` to 0 while `pselbuf` still holds the peer's paths, and `clearselection()` truncates the shared file. | Data loss | Same mitigation as H2. `Correction`: the audit's original trace was wrong. `rmfromselbuf()` returns early at `src/nnn.c:2195-2197` (`if (!found) return;`) when the deselected path is absent from the adopted buffer, so it never reaches the tail. The real trace needs an *overlapping* selection: local `{A, B}`, peer rewrites to `{A, C}`; deselecting `B` decrements `nselected` with no buffer change (early return), then deselecting `A` removes `A` and the tail fires `clearselection()` with `C` still in `pselbuf`. |
| H4 | Stale `+` markers and a status bar that disagrees with the screen: `FILE_SCANNED` (`src/nnn.c:260`) memoizes and is cleared only by `dentfill()`; `resetselind()` (`src/nnn.c:1960-1965`) does not clear it. | Wrong behavior | The forced reload. `Correction`: a hand-rolled flag clear at the drain point does not repaint, because the drain point is skipped by `goto nochange` (`src/nnn.c:11074`) before `redraw()` at `src/nnn.c:9764`. `presel = CONTROL('L')` is mandatory, not optional. |
| H5 | Swap between two `SEL_SELMUL` presses corrupts a range selection. | Wrong behavior | Suppression on `g_state.rangesel` and `g_state.selmode` (10.6). Deferral, not drop, so the change is not lost. |
| H6 | Peer exit unlinks `selpath` (`src/nnn.c:12048-12049`), which a naive check reads as "cleared". | Data loss | Explicit `exists` vs `st_size == 0` split in `syncselfile()`. `isselfileempty()` is not used. |
| H7 | `readselfile()` (`src/nnn.c:1926-1957`) sets `selbufpos = 0` at `src/nnn.c:1939` *before* the read, and on a short read returns `FALSE` leaving `selbufpos == 0` with partially clobbered `pselbuf`. Calling it from the poll would silently destroy a locally owned selection on a transient read error. | Data loss | `syncselfile()` does not call `readselfile()`. `loadselfile()` reads into its own heap buffer and only commits on success. `readselfile()` stays as-is for `editselection()`, where it is only reached with `selbufpos == 0`. |
| H8 | Adopting garbage: a 1-byte file containing a single NUL yields one zero-length "path"; a plugin writing newline-separated text yields one bogus entry. | Wrong behavior | `loadselfile()` validates that every entry is non-empty and begins with `/`; otherwise it refuses and the local state is untouched. |
| H9 | Spurious reload loop from the instance's own writes. | Performance / flicker | Content compare (`memcmp` against `pselbuf`) before swapping, and the stamp is updated on every consumed observation. `plugins/dragdrop:46` appends a NUL after every path while `writesel()` omits the last one; `loadselfile()` normalizes both to the same in-memory form, so the two representations compare equal. |
| H10 | Async mutation during a blocking prompt: `xlink()` caches `char *psel = pselbuf;` at `src/nnn.c:5486` before calling `get_cur_or_sel()` (which blocks in `get_input()`, `src/nnn.c:1699-1715`), then walks `psel` at `src/nnn.c:5518-5529`. | Memory-unsafe if containment is lost | Containment is preserved: the sync runs only at `src/nnn.c:9787`, never inside `get_input()` (`src/nnn.c:1665`, uses `get_wch()` directly), `xreadline()` (`src/nnn.c:5190`) or `spawn()`. `nextsel()` has exactly one caller, `src/nnn.c:9792`. Do not move the call site. |
| H11 | `nselected != 0` with `selbufpos == 0` is reachable today (`batch_rename()` at `src/nnn.c:3038` and `src/nnn.c:3064`; `SEL_QUITCD` in picker mode at `src/nnn.c:11048-11049`), and `confirm_force()` produces the mirror image at `src/nnn.c:1749-1753`. | Wrong behavior | The "already empty" fast exit tests both: `if (!selbufpos && !nselected) return FALSE;`. The swap always sets both together. |
| H12 | Ownership side effects after an automatic adopt: `Q` dumps to stdout (`src/nnn.c:11055`), `-u` skips the prompt (`src/nnn.c:1708`), a DnD drag exports the selection (`dnd_prepare_data()`, `src/nnn.c:3904-3936`). | Behavior change | Accepted by `Decision 4` in 10.2. Documented, not mitigated. |
| H13 | `entries_in_file()` returns `++count` for `NUL_CHAR` (`src/nnn.c:1741`), so it over-counts by one. | Cosmetic | The sync does not use it. `Correction`: the only `NUL_CHAR` caller is `confirm_force()` at `src/nnn.c:1753`; `cpmv_rename()` at `src/nnn.c:2932` passes `NEWLINE_CHAR` and is unaffected. Out of scope. |

`Risk` - pre-existing, found during this review, not caused by the sync and not fixed by it: `endselection()` does `selbufpos = count; pselbuf[--count] = '\0';` at `src/nnn.c:2289-2290` with no zero check, so a zero-length replace-script output writes `pselbuf[-1]`. `editselection()` guards the identical pattern at `src/nnn.c:2394-2397`. Worth a separate commit.

`Risk` - pre-existing cross-instance TOCTOU: `cpmvrm_selection()` (`src/nnn.c:2967-3018`) reads the selection at `src/nnn.c:2971`, `2972`, `2974`, and the spawned shell re-reads `selpath` itself at `src/nnn.c:3009`. "Delete 3 files?" can already delete more if the peer writes in between. The sync does not worsen it (it never writes), and does not fix it.

`Risk` - no size cap on `loadselfile()`'s `malloc`. Matches existing `readselfile()` behavior, but a hostile or corrupt `selpath` allocates its full size. `Open question` - whether to add a ceiling (for example 16 MB) and refuse above it.

### 10.8 Out of scope

- Merging divergent selections. Last writer to the file wins.
- Any write to `selpath` from the sync path, including re-creating the file after a peer exit unlinks it.
- Terminal focus reporting (mode 1004) and tmux `focus-events`. Rejected in 10.3.
- Watching `selpath` with `inotify` / `kqueue`. Rejected in 10.3.
- Cross-instance locking of `selpath`. `writesel()`'s `rename(2)` already makes each write atomic for readers.
- Fixing the H3 root cause inside `rmfromselbuf()` / `invertselbuf()` (not decrementing `nselected` when `findinsel()` fails, sizing `marked[]` from a real buffer scan). Worth doing independently; this design avoids the trigger rather than the latent defect.
- du mode (`cfg.blkorder`) and list mode (`-l`) live-sync.
- Picker mode (`-p`) live-sync.
- Any change to `handle_event()` (`src/nnn.c:3668-3672`).

### 10.9 Test plan

`Not verified` - nothing in this section has been run. Everything below is a procedure for the implementer.

Build with the canonical script, not bare `make`:

```bash
cp -a /home/tripham/Dev/Playground_Terminal/nnn /tmp/nnn-selsync
cd /tmp/nnn-selsync && ./build.sh
```

Use a throwaway selection file for every test. Do not touch `~/.config/nnn/.selection`:

```bash
mkdir -p /tmp/selsync-test/{a,b}
touch /tmp/selsync-test/a/{f1,f2,f3,f4}
export NNN_SEL=/tmp/selsync-test/.selection
```

Run two instances in one tmux window, both with the same `NNN_SEL`.

| # | Test | Steps | Pass criteria |
| --- | --- | --- | --- |
| T1 | The user's exact repro | (1) Select `f1` and `f2` in LEFT with `space`. (2) In RIGHT press `E`, delete every line, save, quit the editor. (3) Switch to LEFT and press `E`. (4) Switch to RIGHT and press `E`. | Step 2: RIGHT shows no selection. Step 3: LEFT's `+` markers and the status-bar count are already gone before `E` is pressed, and `E` prints `0 selected`. Step 4: `0 selected`. |
| T2 | Peer adds to the selection | Select `f1` in LEFT. In RIGHT select `f3`. Look at LEFT without pressing any key. | Within about one second LEFT shows the count `2`; `f1` keeps its `+`; navigating to `/tmp/selsync-test/a` in RIGHT shows `+` on both. |
| T3 | Peer edit via `E` | Select `f1`, `f2`, `f3` in LEFT. In RIGHT press `E`, delete the `f2` line, save. | LEFT's count drops to 2 and `f2` loses its `+` without any keypress in LEFT. |
| T4 | No self-triggered churn | Select and deselect files in LEFT only, with RIGHT idle. | LEFT does not flicker or reload on its own writes; the cursor position and any active filter survive. Confirm with `strace -f -e trace=openat -p <pid>` that LEFT reopens `selpath` only when it changed. |
| T5 | Peer exit does not wipe the survivor | Select `f1` and `f2` in LEFT. Quit RIGHT with `q`. Wait 3 seconds. | `selpath` is gone (`ls -l "$NNN_SEL"` fails). LEFT still shows 2 selected and both `+` markers. `E` in LEFT still lists both files. |
| T6 | Recovery after peer exit | Continue from T5: in LEFT press `space` on `f3`. | `selpath` is re-created and contains all three paths (`tr '\0' '\n' < "$NNN_SEL"`). |
| T7 | Range selection is not corrupted | In LEFT press `SEL_SELMUL` to start a range. While the range is open, in RIGHT select a different file. Complete the range in LEFT. | LEFT's range covers exactly the intended rows and does not include RIGHT's file. The sync applies after the range completes. |
| T8 | Filter survives a sync | In LEFT apply a filter that hides some files. In RIGHT change the selection. | LEFT's filter is still active after the forced reload, and the cursor stays on the same entry. |
| T9 | Garbage file is refused | With LEFT holding a selection, run `printf 'not-a-path\n' > "$NNN_SEL"`. | LEFT keeps its selection and does not crash. Repeat with `printf '\0' > "$NNN_SEL"`. |
| T10 | Trailing-NUL writer | With LEFT holding a selection, run `printf '%s\0' /tmp/selsync-test/a/f4 > "$NNN_SEL"` (mimics `plugins/dragdrop:46`). | LEFT adopts exactly one entry, count `1`, `+` on `f4` only, and does not reload repeatedly afterwards. |
| T11 | Kill switch | Restart LEFT with `NNN_NO_SELSYNC=1`. Repeat T2. | LEFT does not change until the user presses `E`, which falls back to the existing `editselection()` adopt path. |
| T12 | Picker mode unaffected | `nnn -p - /tmp/selsync-test/a`, select files, and change `$NNN_SEL` from another shell. | The picker's output is unchanged by the external write. |
| T13 | ASan run | Rebuild with `./build.sh` plus `-fsanitize=address -fno-omit-frame-pointer`, then repeat T1, T2, T3 and T7 and additionally: local `{f1, f2, f3, f4}`, peer rewrites to `{f1, f2}`, then deselect `f3` and `f4` in the first pane, then press `SEL_SELINV`. | No ASan report. This exercises the H1/H2 window directly. |

For each test, record the exact command, the observed result and a pass/fail verdict. Do not mark the feature `DONE` until T1, T2, T5 and T13 have all been run and recorded.

### 10.10 Implementer checklist

1. Add the `g_selstamp` struct and `g_selsync` flag, plus `loadselfile()` and `syncselfile()`, immediately above `static int nextsel(int presel)` (currently `src/nnn.c:4579`). They must be placed after `g_dnd_b64` (`src/nnn.c:3688`).
2. Initialize `g_selsync` in `setup_config()` (`src/nnn.c:11377`), just after the selection-file block that ends at `src/nnn.c:11462`:
   `g_selsync = !g_state.picker && selpath && !getenv("NNN_NO_SELSYNC");`
3. Add the call site in `browse()` directly after the `g_dnd_resync` drain (`src/nnn.c:9787-9790`), before `sel = nextsel(presel);` (`src/nnn.c:9792`):
   `if (!presel && syncselfile()) presel = CONTROL('L');`
4. Confirm the sync is called from nowhere else. In particular not from `get_input()` (`src/nnn.c:1665`), `xreadline()` (`src/nnn.c:5190`), `spawn()`, `handle_event()` (`src/nnn.c:3668`), or any plugin callback.
5. Verify the swap sets all five pieces of state together: `pselbuf` contents, `selbufpos`, `nselected` (counted from the buffer, never carried), `findselpos = NULL`, and `resetselind()`.
6. Verify `syncselfile()` contains no call to `writesel()`, `clearselection()`, `startselection()` or `endselection()`. Grep the new code for `writesel` and expect zero hits.
7. Verify the deferral gates return **before** the stamp is recorded, and the consume paths return **after**.
8. Verify `readselfile()` (`src/nnn.c:1926`) and the `adopted` revert in `editselection()` (`src/nnn.c:2352-2368`) are left untouched: they still serve the suppressed and opted-out cases.
9. Verify `handle_event()` (`src/nnn.c:3668-3672`) is left untouched.
10. Build with `./build.sh` (not bare `make`) and confirm no new warnings.
11. Run the test plan in 10.9 against a copy in `/tmp` with `NNN_SEL` pointing at a throwaway file. Do not run any test against `~/.config/nnn/.selection`.
12. Run T13 under ASan before declaring the work `DONE`.
13. Document `NNN_NO_SELSYNC` in the README next to the existing selection notes, and note the du-mode and list-mode limits.
14. Commit with a message describing the behavior change: the shared selection file becomes authoritative and every instance tracks it live.