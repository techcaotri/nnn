# Test strength (mutation analysis): review of e2fcb93d

Lens: if someone breaks `plugins/cpmv` in a realistic way, do `misc/test/test-cpmv.sh` (unit) and `misc/test/test-cpmv-e2e.sh` (e2e) notice?

## Verdict

The tests pin the reported bug and the move safety well, but they miss about half of the other realistic breaks. I wrote 73 realistic mutants of `plugins/cpmv`; the two suites killed 38 and 35 survived (both suites pass on a broken plugin). Of the survivors, 2 are equivalent (M15, M32) and 1 is benign (M70), so 32 are real test gaps. The unit suite kills 35 mutants and the e2e suite 15; three (M20, M43, M66) are killed only by the e2e suite: the unit suite has no assertion for the pause or the extra prompt, and its assertion for the kept notice is vacuous (`test-cpmv.sh:160`). Every mutant that re-creates the original bug or the original data-loss path (M01 to M08) is killed, so the fix itself is well pinned. The gaps that matter: a dropped `-I` in the mode 1 directory move deletes the source and keeps the old target (T1, HIGH); a dropped `--append-verify` completes a damaged file with wrong bytes (T2, HIGH); a dropped `grep -x` replaces a newer target with an older source (T3, HIGH); ignored comparison failures give a silent partial copy or move with exit 0 (T5); a menu read without `|| choice=7` spins forever on EOF (T6); unquoted destination paths (T11); and no test for the same-file guard, dangling links, rename rules, a missing rsync, or the temp directory. I wrote 24 new test groups (appendix, 371 lines, `g_*` functions in the style of `test-cpmv.sh`) and two one-line assertion fixes. Each of the 32 real gaps, and the three mutants that only the e2e suite kills, is killed by at least one new group, and all new groups pass on the real plugin (494 checks, three runs, `shellcheck` clean). No mutant exposed a defect in the plugin itself; two questions about plugin behaviour that I found on the way are in O1 and O2. What must change: add the new groups (or equivalents) to `SUITE`, fix the assertions at `test-cpmv.sh:160` and `test-cpmv-e2e.sh:67`, and decide O1.

## Findings

Severity is the effect of the undetected break (HIGH = data loss or wrong overwrite, MEDIUM = wrong result or hidden failure, LOW = cosmetic or rare). Status is CONFIRMED when I ran the mutant and the new test (both results are in Details).

| id | severity | file:line | summary | status |
|---|---|---|---|---|
| T1 | HIGH | plugins/cpmv:286 | M49: dropping `-I` from the mode 1 directory move is not noticed; target keeps old bytes, source deleted | CONFIRMED |
| T2 | HIGH | plugins/cpmv:300 | M48: `--append-verify` to `--append` is not noticed; damaged partial file is completed with wrong bytes | CONFIRMED |
| T3 | HIGH | plugins/cpmv:205 | M29: `grep -x` dropped is not noticed; a newer target is replaced by an older source | CONFIRMED |
| T4 | MEDIUM | plugins/cpmv:204-205 | M28, M30: candidate matching without `-F`, or without `-a`/`LC_ALL=C`, silently skips files with `[`, `*` or invalid UTF-8 in the name | CONFIRMED |
| T5 | MEDIUM | plugins/cpmv:167, 200 | M54, M55: a failed rsync comparison can be ignored without any test failing (silent partial copy or move, exit 0) | CONFIRMED |
| T6 | MEDIUM | plugins/cpmv:360, 383 | M16, M17: menu `read` without the `choice=7` fallback loops forever on EOF; no test reaches EOF at a menu | CONFIRMED |
| T7 | MEDIUM | plugins/cpmv:343 | M39: the same-file guard can be removed; no test selects an item inside the destination directory | CONFIRMED |
| T8 | MEDIUM | plugins/cpmv:337, 348 | M38, M40: dangling symlink as source or as target is untested | CONFIRMED |
| T9 | MEDIUM | plugins/cpmv:144 | M72: `rs_unescape` decoding only the first escape of a name is not noticed | CONFIRMED |
| T10 | MEDIUM | plugins/cpmv:258 | M73: moving a directory onto a symlink to a directory without `-K` is not noticed (only the copy path is tested) | CONFIRMED |
| T11 | MEDIUM | plugins/cpmv:247, 288 | M63, M64, M65: unquoted destination or source-parent path is not noticed; no test path contains a space | CONFIRMED |
| T12 | MEDIUM | plugins/cpmv:127 | M56: the missing-rsync path (`need_rsync`) is never run | CONFIRMED |
| T13 | MEDIUM | plugins/cpmv:189 | M25: identical symlinks left behind by a move are not noticed (no move test has a symlink) | CONFIRMED |
| T14 | MEDIUM | plugins/cpmv:225 | M53: the "kept in the source" notice for a plain file (not a directory) is untested | CONFIRMED |
| T15 | MEDIUM | plugins/cpmv:229, 390, 407 | M66, M43, M20: killed only by the e2e suite; the unit assertion meant to cover them is vacuous or missing | CONFIRMED |
| T16 | LOW | plugins/cpmv:267-272 | M34 to M37: rename rules (extension, dotfile, dotted directory, dangling link in the way) are untested | CONFIRMED |
| T17 | LOW | plugins/cpmv:375 | M41, M42: y/N prompt default and the Y/yes/YES answers are untested | CONFIRMED |
| T18 | LOW | plugins/cpmv:109 | M47: the temp directory cleanup (`trap ... EXIT`) is untested | CONFIRMED |
| T19 | LOW | plugins/cpmv:311, 357, 384 | M50, M51, M52: directory header, type-clash menu text and invalid menu input are untested | CONFIRMED |
| T20 | LOW | plugins/cpmv:207 | M31: the "N kept" count of the plan line is unasserted | CONFIRMED |
| T21 | LOW | plugins/cpmv:249 | M74: a COPY that removes empty source directories is not noticed (`test-cpmv.sh:83` checks 2 of 8 source entries) | CONFIRMED |
| W1 | MEDIUM | misc/test/test-cpmv.sh:160 | vacuous assertion: `kept\|left in the source` matches the plan line "N kept (...)" | CONFIRMED |
| W2 | LOW | misc/test/test-cpmv-e2e.sh:67 | vacuous wait: `proj\|dst` matches the echoed command line, so "nnn started" cannot fail | CONFIRMED |
| W3 | LOW | misc/test/test-cpmv.sh:361-375 | `g_oracle` checks destination content only: no exit status, no source side for moves | CONFIRMED (by reading) |
| W4 | LOW | misc/test/test-cpmv-e2e.sh:31, 69 | every run leaves a stale `/tmp/tmux-<uid>/cpmve2e-<pid>` socket file | CONFIRMED |
| O1 | HIGH if not intended | plugins/cpmv:184, 195 | a MOVE in modes 2, 3, 4 treats "same size and same mtime" as identical: the source is deleted although the content differs | CONFIRMED (Open question) |
| O2 | LOW | plugins/cpmv:288 | a dangling symlink at the target: answering `y` cannot overwrite it (`cp: not writing through dangling symlink`, exit 1) | CONFIRMED (Open question) |

Further weak points (W5 to W11) are listed in Details, section D5.

## Details

### D1. Method and baseline

`Fact`: this review edited no tracked file, ran every mutant from a scratch copy, and never changed the repo plugin. The only file it created in the repo is this report.

1. `plugins/cpmv` was copied to the scratch directory. A small Python script applied one literal edit per mutant and asserted that the old text occurs exactly once.
2. `bash -n` was run on every mutant: 0 INVALID.
3. Each mutant ran against both suites, three runs at a time (`xargs -P 3`), each run with a 280 s ceiling:

```bash
CPMV=/scratch/mut/M49.cpmv timeout 280 misc/test/test-cpmv.sh | tail -3
CPMV=/scratch/mut/M49.cpmv timeout 280 misc/test/test-cpmv-e2e.sh | tail -3
```

4. KILLED means at least one suite exits non-zero. SURVIVED means both exit 0.

| Baseline on the real plugin | Command | Result | Time |
|---|---|---|---|
| unit | `misc/test/test-cpmv.sh` | `578 passed, 0 failed` (plain ops, then advcpmv ops) | 21 s |
| e2e | `misc/test/test-cpmv-e2e.sh` | `20 passed, 0 failed` | 11 s |

Result: 73 mutants, 38 KILLED (unit-only 23, e2e-only 3, both 12), 35 SURVIVED, 0 INVALID.

### D2. Mutant table

`Line` is the line of `plugins/cpmv` that was edited. `First failing` lists the first groups of the unit suite that failed, or the e2e check text.

| id | line | mutation | result | killed by | first failing |
|---|---|---|---|---|---|
| M01 | 296 | mode 4 goes back to rsync -a --update on the whole tree (move keeps --remove-source-files) | KILLED | unit+e2e | unit: copy-mode4, move-mode4, apply-all +10 / e2e: dest newer + size differs is overwritten; nested dest newer + size differs overwritten |
| M02 | 296 | mode 3 goes back to rsync -a --size-only on the whole tree (move keeps --remove-source-files) | KILLED | unit | unit: copy-mode3, move-mode3 |
| M03 | 178 | plan forgets the "source is newer" candidates (mode 4 acts like mode 3) | KILLED | unit+e2e | unit: copy-mode4, copy-mode3, move-mode4 +2 / e2e: source newer + same size is overwritten |
| M04 | 205 | plan copies every time-differing candidate (mode 4 ignores the D2 --update result) | KILLED | unit+e2e | unit: copy-mode4, move-mode4, oracle-copy-4 +1 / e2e: dest newer + same size is kept; move that kept a file pauses for review |
| M05 | 181 | mode 3 also copies files whose only difference is the time | KILLED | unit | unit: copy-mode3, move-mode3, oracle-copy-3 +1 |
| M06 | 241,249 | move: no --remove-source-files, source removed with rm -rf afterwards (the original data-loss bug) | KILLED | unit+e2e | unit: move-mode4, move-mode3 / e2e: move that kept a file pauses for review; kept notice |
| M07 | 223 | finish_move removes non-empty directories (rm -rf instead of rmdir of empty ones) | KILLED | unit+e2e | unit: move-mode4, move-mode3, move-mode2 / e2e: move that kept a file pauses for review; kept notice |
| M08 | 184 | identical files are not added to the list for a move (their source stays behind) | KILLED | unit | unit: move-mode4, move-mode3 |
| M09 | 122 | try() does not count failures | KILLED | unit+e2e | unit: err-copy-4, err-copy-3, err-copy-1 +3 / e2e: nnn pauses after a failed paste; problem list |
| M10 | 401 | final exit 1 becomes exit 0 (errors are printed but nnn is told success) | KILLED | unit+e2e | unit: err-copy-4, err-copy-3, err-copy-1 +4 / e2e: nnn pauses after a failed paste; problem list |
| M11 | 353 | file-versus-directory clash check removed | KILLED | unit | unit: mismatch, mismatch-rename, mismatch-allmode |
| M12 | 367 | GLOBAL_MODE is applied before the clash check (to a clash item) | KILLED | unit | unit: mismatch-allmode |
| M13 | 84 | -K dropped from RS | KILLED | unit | unit: dirlink |
| M14 | 137-138 | rs_unescape returns the name unchanged | KILLED | unit | unit: names-copy-4, names-copy-3, names-move |
| M15 | 212 | the directory trailing slash is no longer stripped | SURVIVED | - | - |
| M16 | 383 | EOF at the main menu: `read -r choice` without the `\|\| choice=7` fallback (loops forever on EOF) | SURVIVED | - | - |
| M17 | 360 | EOF at the clash menu: `read -r choice` without the `\|\| choice=7` fallback (loops forever on EOF) | SURVIVED | - | - |
| M18 | 285 | mode 1 move of a directory goes back to mv -f (no merge) | KILLED | unit | unit: move-mode1 |
| M19 | 291 | mode 2 move of a directory goes back to mv -u (no merge) | KILLED | unit | unit: move-mode2 |
| M20 | 407 | kept_in_src no longer triggers the "Done. Press enter." pause | KILLED | e2e | e2e: move that kept a file pauses for review; kept notice |
| M21 | 166 | D1 dry run uses -i instead of -ii (unchanged items are not listed) | KILLED | unit | unit: move-mode4, move-mode3 |
| M22 | 173 | D1 name offset off by one (line:11 keeps a leading space) | KILLED | unit+e2e | unit: copy-mode4, copy-mode3, move-mode4 +16 / e2e: dest newer + size differs is overwritten; source newer + same size is overwritten |
| M23 | 176 | D1 no longer recognises a file that is missing at the target (+++++++++) | KILLED | unit | unit: copy-mode3, err-copy-3, oracle-copy-3 +1 |
| M24 | 186 | D1 does not list new directories (empty source dirs are not created) | KILLED | unit | unit: copy-mode4 |
| M25 | 189 | identical links/specials are not listed for a move | SURVIVED | - | - |
| M26 | 188 | new links/specials are not listed (symlinks not copied by modes 3/4) | KILLED | unit | unit: symlinks |
| M27 | 199 | D2 runs without --update (a newer target of equal size is overwritten) | KILLED | unit+e2e | unit: copy-mode4, move-mode4, oracle-copy-4 +1 / e2e: dest newer + same size is kept; move that kept a file pauses for review |
| M28 | 205 | candidate match drops grep -F (names used as regular expressions) | SURVIVED | - | - |
| M29 | 205 | candidate match drops grep -x (substring match instead of whole-line match) | SURVIVED | - | - |
| M30 | 204-205 | locale hardening removed from D2 (no -a, no LC_ALL=C) | SURVIVED | - | - |
| M31 | 207 | PLAN_KEEP count wrong for mode 4 (summary line only) | SURVIVED | - | - |
| M32 | 246 | -d dropped from the --files-from transfer (directory entries are skipped) | SURVIVED | - | - |
| M33 | 272 | rename: the (n) collision loop is removed (always "(1)") | KILLED | unit | unit: copy-mode6 |
| M34 | 269 | rename: the extension is dropped ("a.txt" becomes "a (1)") | SURVIVED | - | - |
| M35 | 269 | rename: a dotfile is split at its leading dot (".bashrc" becomes " (1).bashrc") | SURVIVED | - | - |
| M36 | 267 | rename: the directory guard is removed ("dir.v2" becomes "dir (1).v2") | SURVIVED | - | - |
| M37 | 272 | rename: a dangling symlink named "x (1)" counts as free | SURVIVED | - | - |
| M38 | 337 | a dangling symlink in the selection is reported "not found" | SURVIVED | - | - |
| M39 | 343 | the same-file check is removed (item onto itself) | SURVIVED | - | - |
| M40 | 348 | a dangling symlink at the target is treated as "no conflict" | SURVIVED | - | - |
| M41 | 375 | single-file prompt: only an explicit n skips (empty answer / EOF overwrites) | SURVIVED | - | - |
| M42 | 375 | single-file prompt: only lowercase y accepted | SURVIVED | - | - |
| M43 | 390 | "apply to ALL" is also offered for the last item | KILLED | e2e | e2e: selection is cleared after a successful copy; move that kept a file pauses for review |
| M44 | 392 | "apply to ALL" is set whatever the answer | KILLED | unit | unit: apply-no |
| M45 | 407 | pause after every conflict, also a single directory | KILLED | unit+e2e | unit: copy-mode4 / e2e: selection is cleared after a successful copy; selection is cleared after the retry succeeds |
| M46 | 338 | a source that is not found is printed but not counted | KILLED | unit | unit: err-vanished |
| M47 | 109 | the temp directory is never removed (trap deleted) | SURVIVED | - | - |
| M48 | 300 | mode 5: --append-verify becomes --append (no checksum verification) | SURVIVED | - | - |
| M49 | 286 | mode 1 move merge: -I dropped (same size and mtime files are not overwritten, source still removed) | SURVIVED | - | - |
| M50 | 311 | conflict header shows byte sizes for directories again | SURVIVED | - | - |
| M51 | 357 | the clash menu is not filtered (shows options 1-5 that cannot be chosen) | SURVIVED | - | - |
| M52 | 384 | main menu accepts any digit (0, 8, 9 silently do nothing) | SURVIVED | - | - |
| M53 | 225 | finish_move: a kept plain FILE is counted as 0 left | SURVIVED | - | - |
| M54 | 167 | D1 failure is ignored (rc not checked) | SURVIVED | - | - |
| M55 | 200 | D2 failure is ignored (rc not checked) | SURVIVED | - | - |
| M56 | 127 | need_rsync never reports a missing rsync | SURVIVED | - | - |
| M57 | 299 | mode 5 move: --remove-source-files dropped | KILLED | unit | unit: move-mode5 |
| M58 | 103 | the last, NUL-less path of the selection is dropped | KILLED | unit+e2e | unit: copy-mode4, copy-mode3, copy-mode2 +32 / e2e: menu shown after pressing p; CONFLICT menu is shown |
| M59 | 288 | mode 1 copy without -f (read-only target not replaced) | KILLED | unit | unit: copy-mode1 |
| M60 | 75 | copy base flags lose -p (times not preserved) | KILLED | unit | unit: copy-mode2, copy-mode1, single-file-y +1 |
| M61 | 292 | mode 2 move merge: --update dropped (newer targets are overwritten) | KILLED | unit | unit: move-mode2 |
| M62 | 294 | mode 2 copy: -u becomes -f (newer targets are overwritten) | KILLED | unit | unit: copy-mode2 |
| M63 | 247 | the xfer_policy transfer uses an unquoted $dest | SURVIVED | - | - |
| M64 | 288 | mode 1 copy uses an unquoted $dest | SURVIVED | - | - |
| M65 | 247 | xfer_policy source parent unquoted | SURVIVED | - | - |
| M66 | 229 | the "kept in the source" line is not printed (the pause still happens) | KILLED | e2e | e2e: kept notice |
| M67 | 249 | finish_move is also run after a COPY (modes 3/4) | KILLED | unit+e2e | unit: copy-mode4 / e2e: selection is cleared after a successful copy; selection is cleared after the retry succeeds |
| M68 | 68 | advcpmv move op (mvg) is not recognised as a move | KILLED | unit | unit: move-mode4, move-mode3, move-mode2 +7 |
| M70 | 247 | a failed transfer in xfer_policy no longer stops finish_move (the `\|\| return 1` removed) | SURVIVED | - | - |
| M71 | 272 | rename: the collision test uses -f, so a directory named "x (1)" is not seen | KILLED | unit | unit: copy-mode6 |
| M72 | 144 | rs_unescape decodes only the FIRST escape of a name (while becomes a single pass) | SURVIVED | - | - |
| M73 | 258 | move_merge (dir move onto an existing dir) hard-codes -a -8: no -K, a target symlink to a directory is replaced | SURVIVED | - | - |
| M74 | 249 | the empty-directory cleanup also runs after a COPY (modes 3/4), without the kept notice | SURVIVED | - | - |

Mutants that only one assertion kills (thin coverage): M12 (`mismatch-allmode`), M13 (`dirlink`), M24 (empty directory check of `copy-mode4`), M26 (`symlinks`), M33 and M71 (`copy-mode6`), M44 (`apply-no`), M46 (`err-vanished`). One careless edit to those tests would remove the only guard.

### D3. Gaps: edit, effect, new test, proof

Rows M20, M43 and M66 are killed by the e2e suite only; the unit suite passes on them. All other rows survive both suites.

The edit lines come from `diff -u` of the real plugin against the mutant (`-` is the real line, `+` the mutant). Proof means: the new group run from a COPY of `test-cpmv.sh` in the scratch directory, as

```bash
NEWONLY=1 ONLY=<group> CPMV=<plugin or mutant> timeout 120 test-copy/test-cpmv.sh
```

`NEWONLY=1` is a switch that exists only in the scratch copy (it runs just the new groups). Counts are failed checks / total checks; each run covers the plain and the advcpmv pass.

| mutant | finding | new group | against mutant | against real plugin |
|---|---|---|---|---|
| M49 | T1 | `g_move_mode1_same_time` | FAIL 4 of 12 | PASS 12 |
| M48 | T2 | `g_resume_verify` | FAIL 2 of 2 | PASS 2 |
| M29 | T3 | `g_candidate_names` | FAIL 8 of 84 | PASS 84 |
| M28 | T4 | `g_candidate_names` | FAIL 24 of 84 | PASS 84 |
| M30 | T4 | `g_candidate_names` | FAIL 4 of 84 | PASS 84 |
| M54 | T5 | `g_compare_fails` | FAIL 20 of 56 | PASS 56 |
| M55 | T5 | `g_compare_fails_second_run` | FAIL 8 of 8 | PASS 8 |
| M16 | T6 | `g_eof_at_menu` | FAIL 4 of 20 | PASS 20 |
| M17 | T6 | `g_eof_at_menu` | FAIL 2 of 20 | PASS 20 |
| M39 | T7 | `g_same_file` | FAIL 14 of 40 | PASS 40 |
| M38 | T8 | `g_dangling_links` | FAIL 10 of 16 | PASS 16 |
| M40 | T8 | `g_dangling_links` | FAIL 4 of 16 | PASS 16 |
| M72 | T9 | `g_names_multi_escape` | FAIL 28 of 28 | PASS 28 |
| M73 | T10 | `g_move_dirlink` | FAIL 6 of 16 | PASS 16 |
| M63 | T11 | `g_paths_with_spaces` | FAIL 24 of 48 | PASS 48 |
| M64 | T11 | `g_paths_with_spaces` | FAIL 6 of 48 | PASS 48 |
| M65 | T11 | `g_paths_with_spaces` | FAIL 24 of 48 | PASS 48 |
| M56 | T12 | `g_no_rsync` | FAIL 4 of 18 | PASS 18 |
| M25 | T13 | `g_move_symlinks` | FAIL 12 of 28 | PASS 28 |
| M53 | T14 | `g_move_kept_file` | FAIL 2 of 16 | PASS 16 |
| M20 | T15 | `g_pause_rule` | FAIL 2 of 6 | PASS 6 |
| M43 | T15 | `g_apply_prompt` | FAIL 4 of 4 | PASS 4 |
| M66 | T15 | `g_plan_summary` | FAIL 2 of 6 | PASS 6 |
| M34 | T16 | `g_rename_names` | FAIL 4 of 16 | PASS 16 |
| M35 | T16 | `g_rename_names` | FAIL 2 of 16 | PASS 16 |
| M36 | T16 | `g_rename_names` | FAIL 2 of 16 | PASS 16 |
| M37 | T16 | `g_rename_names` | FAIL 4 of 16 | PASS 16 |
| M41 | T17 | `g_single_file_answers` | FAIL 16 of 36 | PASS 36 |
| M42 | T17 | `g_single_file_answers` | FAIL 12 of 36 | PASS 36 |
| M47 | T18 | `g_tmpdir_cleanup` | FAIL 8 of 10 | PASS 10 |
| M50 | T19 | `g_conflict_header` | FAIL 4 of 8 | PASS 8 |
| M51 | T19 | `g_clash_menu` | FAIL 2 of 4 | PASS 4 |
| M52 | T19 | `g_invalid_choice` | FAIL 6 of 6 | PASS 6 |
| M31 | T20 | `g_plan_summary` | FAIL 2 of 6 | PASS 6 |
| M74 | T21 | `g_copy_source_untouched` | FAIL 4 of 14 | PASS 14 |
| M15 | equivalent or benign | `g_candidate_names` (not a killer) | PASS 84 | PASS |
| M32 | equivalent or benign | `g_candidate_names` (not a killer) | PASS 84 | PASS |
| M70 | equivalent or benign | `g_compare_fails` (not a killer) | PASS 56 | PASS |

Effect of each surviving mutant, and its edit:

#### M49 (T1, plugins/cpmv:286)

Mode 1 move of a directory onto a directory: the target keeps its old bytes ("BBBB") and the source file is deleted. Data loss, exit 0. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-                move_merge "$src" -I            # -I: send everything, even when size and time match
+                move_merge "$src"            # -I: send everything, even when size and time match
```

#### M48 (T2, plugins/cpmv:300)

Mode 5 completes a damaged partial file with wrong bytes: "XXXXXXXXXXABCDEFGHIJ" instead of the source content. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            if try "$name" rsync "${RS[@]}" --partial --append-verify --info=progress2 \
+            if try "$name" rsync "${RS[@]}" --partial --append --info=progress2 \
```

#### M29 (T3, plugins/cpmv:205)

A target that is NEWER is replaced by the older source when its name contains another candidate (a.txt.bak, sub/proj/a.txt): expected "dstK", got "srcK". Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        n=$(LC_ALL=C grep -aFxf "$nm" "$cand" | tee -a "$xesc" | wc -l)
+        n=$(LC_ALL=C grep -aFf "$nm" "$cand" | tee -a "$xesc" | wc -l)
```

#### M28 (T4, plugins/cpmv:205)

Source-newer files named x[1].txt and x*.txt are silently not copied (24 failed checks). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        n=$(LC_ALL=C grep -aFxf "$nm" "$cand" | tee -a "$xesc" | wc -l)
+        n=$(LC_ALL=C grep -axf "$nm" "$cand" | tee -a "$xesc" | wc -l)
```

#### M30 (T4, plugins/cpmv:204-205)

A source-newer file whose name is not valid UTF-8 is silently not copied in a UTF-8 locale. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        LC_ALL=C grep -a '^>f' "$d2" | LC_ALL=C cut -c13- >"$nm"
-        n=$(LC_ALL=C grep -aFxf "$nm" "$cand" | tee -a "$xesc" | wc -l)
+        grep '^>f' "$d2" | cut -c13- >"$nm"
+        n=$(grep -Fxf "$nm" "$cand" | tee -a "$xesc" | wc -l)
```

#### M54 (T5, plugins/cpmv:167)

Unreadable source subdirectory (`chmod 000 src/proj/sub`): exit 0 and a partial copy. For a move the readable file is moved and the unreadable one stays in the source, with no error and no "kept in the source" line (reproduced). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    if [ "$rc" -ne 0 ]; then
+    if false; then
```

#### M55 (T5, plugins/cpmv:200)

The second comparison fails (shim): ignored, the first-comparison plan is executed, exit 0. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        if [ "$rc" -ne 0 ]; then
+        if false; then
```

#### M16 (T6, plugins/cpmv:383)

stdin at EOF at the main menu: 300000 bytes of menu text in under 5 s, ended only by SIGPIPE (status 141). The real plugin prints "skipped proj" and ends with status 0. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        printf '    choose [1-7]: '; read -r choice || choice=7
+        printf '    choose [1-7]: '; read -r choice
```

#### M17 (T6, plugins/cpmv:360)

Same endless loop at the file-versus-directory menu. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            read -r choice || choice=7
+            read -r choice
```

#### M39 (T7, plugins/cpmv:343)

An item selected in the destination directory itself shows the CONFLICT menu; with mv, rsync refuses ("Skipping sender remove of destination file") and the exit status is 1. Real plugin: "skipped (same file)", status 0. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    if [ -e "$target" ] && [ "$src" -ef "$target" ]; then
+    if false; then
```

#### M38 (T8, plugins/cpmv:337)

A dangling symlink in the selection is reported "not found" and the exit status is 1. Real plugin copies the link. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
+    if [ ! -e "$src" ]; then
```

#### M40 (T8, plugins/cpmv:348)

A dangling symlink at the target is not a conflict: no prompt, cp fails, exit 1. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    if [ ! -e "$target" ] && [ ! -L "$target" ]; then do_one "$src" 1; continue; fi
+    if [ ! -e "$target" ]; then do_one "$src" 1; continue; fi
```

#### M72 (T9, plugins/cpmv:144)

A name with two rsync escapes (two newlines) is not decoded: rsync error, the file is not copied, exit 1. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        s=${s:${#pre}+5}
+        s=${s:${#pre}+5}; break
```

#### M73 (T10, plugins/cpmv:258)

Moving a directory onto a symlink that points to a directory replaces the symlink with a real directory; the linked directory is not merged into. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    try "$(basename -- "$src")" rsync "${RS[@]}" --info=progress2 --remove-source-files "$@" -- "$src" "$dest/" || return 1
+    try "$(basename -- "$src")" rsync -a -8 --info=progress2 --remove-source-files "$@" -- "$src" "$dest/" || return 1
```

#### M63 (T11, plugins/cpmv:247)

A destination path with a space or quote breaks the modes 3/4 transfer (24 failed checks). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            --from0 --files-from="$PLAN_LIST" -- "$(dirname -- "$src")/" "$dest/" || return 1
+            --from0 --files-from="$PLAN_LIST" -- "$(dirname -- "$src")/" $dest/ || return 1
```

#### M64 (T11, plugins/cpmv:288)

A destination path with a space or quote breaks the mode 1 copy. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-                try "$name" $CMD $BASE -f -- "$src" "$dest/"
+                try "$name" $CMD $BASE -f -- "$src" $dest/
```

#### M65 (T11, plugins/cpmv:247)

A source parent path with a space breaks the modes 3/4 transfer. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            --from0 --files-from="$PLAN_LIST" -- "$(dirname -- "$src")/" "$dest/" || return 1
+            --from0 --files-from="$PLAN_LIST" -- $(dirname -- "$src")/ "$dest/" || return 1
```

#### M56 (T12, plugins/cpmv:127)

Without rsync the message "rsync missing; skipped proj" is replaced by "compare failed (rsync status 127)" or a raw shell error. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    [ "$have_rsync" -eq 1 ] && return 0
+    return 0
```

#### M25 (T13, plugins/cpmv:189)

After a move, an identical symlink stays in the source, the source tree is not removed, and a "kept in the source" notice appears. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            .)     [ "$ACT" = mv ] && printf '%s\n' "$name" ;;
+            .)     : ;;
```

#### M53 (T14, plugins/cpmv:225)

A plain file kept by a move is not announced ("kept in the source: 1 file(s) of c.txt" is missing). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        if is_realdir "$src"; then left=$(find "$src" ! -type d 2>/dev/null | wc -l); else left=1; fi
+        if is_realdir "$src"; then left=$(find "$src" ! -type d 2>/dev/null | wc -l); else left=0; fi
```

#### M20 (T15, plugins/cpmv:407)

A move that leaves files behind returns to nnn without "Done. Press enter.", so the notice disappears at the next redraw. Only the e2e suite notices. Suites on the mutant: unit pass, e2e FAIL (killed by the e2e suite only).

```diff
-if { [ "$conflicts" -gt 0 ] && [ "$nfiles" -gt 1 ]; } || [ "$kept_in_src" -gt 0 ]; then
+if { [ "$conflicts" -gt 0 ] && [ "$nfiles" -gt 1 ]; }; then
```

#### M43 (T15, plugins/cpmv:390)

"apply to ALL remaining conflicts?" is asked after the LAST item too. Only the e2e suite notices (nnn hangs on the extra prompt). Suites on the mutant: unit pass, e2e FAIL (killed by the e2e suite only).

```diff
-    if [ "$idx" -lt "$nfiles" ]; then
+    if [ "$idx" -le "$nfiles" ]; then
```

#### M66 (T15, plugins/cpmv:229)

The "kept in the source" line is not printed. The unit assertion at test-cpmv.sh:160 still passes because the plan line also contains "kept". Only the e2e suite notices. Suites on the mutant: unit pass, e2e FAIL (killed by the e2e suite only).

```diff
-            printf '  - kept in the source: %d file(s) of %s (not replaced by this mode)\n' "$left" "$(basename -- "$src")"
+            :
```

#### M34 (T16, plugins/cpmv:269)

Rename drops the extension: "a.txt" becomes "a (1)". Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-                ?*.*) stem="${base%.*}"; ext=".${base##*.}" ;;
+                ?*.*) stem="${base%.*}"; ext="" ;;
```

#### M35 (T16, plugins/cpmv:269)

Rename of a dotfile: ".hid" becomes " (1).hid". Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-                ?*.*) stem="${base%.*}"; ext=".${base##*.}" ;;
+                *.*) stem="${base%.*}"; ext=".${base##*.}" ;;
```

#### M36 (T16, plugins/cpmv:267)

Rename of a directory with a dot: "dir.v2" becomes "dir (1).v2". Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        if [ ! -d "$src" ]; then            # "name (1).ext" for files, "dir.v2 (1)" for directories
+        if true; then            # "name (1).ext" for files, "dir.v2 (1)" for directories
```

#### M37 (T16, plugins/cpmv:272)

A dangling symlink named "b (1).txt" is overwritten or makes cp fail (exit 1) instead of picking "b (2).txt". Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        n=1; while [ -e "$dest/$stem ($n)$ext" ] || [ -L "$dest/$stem ($n)$ext" ]; do n=$((n + 1)); done
+        n=1; while [ -e "$dest/$stem ($n)$ext" ]; do n=$((n + 1)); done
```

#### M41 (T17, plugins/cpmv:375)

At the y/N prompt an empty answer or EOF overwrites the target (default became Yes). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        case "$yn" in y|Y|yes|YES) do_one "$src" 1 ;; *) do_one "$src" 7 ;; esac
+        case "$yn" in n|N|no|NO) do_one "$src" 7 ;; *) do_one "$src" 1 ;; esac
```

#### M42 (T17, plugins/cpmv:375)

Only a lowercase "y" is accepted; "Y", "yes", "YES" skip. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        case "$yn" in y|Y|yes|YES) do_one "$src" 1 ;; *) do_one "$src" 7 ;; esac
+        case "$yn" in y) do_one "$src" 1 ;; *) do_one "$src" 7 ;; esac
```

#### M47 (T18, plugins/cpmv:109)

One /tmp/cpmv.XXXXXX directory is left behind per plugin run (84 left by one unit suite run, measured with `TMPDIR` pointing at a scratch directory). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-trap '[ -n "$TMPD" ] && rm -rf "$TMPD"' EXIT
+:
```

#### M50 (T19, plugins/cpmv:311)

The conflict header shows "4096 bytes" for directories again (investigation.md, cause 6). Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    if [ -d "$2" ]; then printf '    %-7s: %12s   %s\n' "$1" "(directory)" "$(fmtime "$2")"
+    if false; then printf '    %-7s: %12s   %s\n' "$1" "(directory)" "$(fmtime "$2")"
```

#### M51 (T19, plugins/cpmv:357)

The file-versus-directory menu lists options 1 to 5, which are then rejected. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-            show_conflict "$src" "$target" | sed '/^    [1-5]) /d; /^    4) /d'
+            show_conflict "$src" "$target"
```

#### M52 (T19, plugins/cpmv:384)

Answers 0, 8 and 9 are accepted at the menu and silently do nothing. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        case "$choice" in 1|2|3|4|5|6|7) break ;; *) printf '    invalid.\n' ;; esac
+        case "$choice" in [0-9]) break ;; *) printf '    invalid.\n' ;; esac
```

#### M31 (T20, plugins/cpmv:207)

The "N kept" count in the plan line is wrong whenever candidates minus copied differs from copied. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-        PLAN_KEEP=$((PLAN_KEEP + $(wc -l <"$cand") - n))
+        PLAN_KEEP=$((PLAN_KEEP + n))
```

#### M74 (T21, plugins/cpmv:249)

A COPY with mode 3 or 4 removes the empty directories of the SOURCE tree. Suites on the mutant: unit pass, e2e pass (SURVIVED).

```diff
-    [ "$ACT" = mv ] && finish_move "$src"
+    if [ "$ACT" = mv ]; then finish_move "$src"; else find "$src" -depth -type d -exec rmdir -- {} + 2>/dev/null; fi
```

Equivalent or benign survivors (no test proposed):

- **M15** (plugins/cpmv:212): Equivalent. Only directories that are CREATED are listed (`cd+++++++++`), so every entry below a listed "dir/" is new and already listed. Differential run of the real plugin against M15: copy and move, modes 3 and 4, with new, nested, empty and spaced directories: the trees are identical (only the mtime of a symlink made by the fixture differs).

  ```diff
  -        name=${name%/}
  ```

- **M32** (plugins/cpmv:246): Equivalent. The rsync man page says "The --dirs option is implied by the --files-from option" when --recursive is not given. The suites cannot tell, and no test can.

  ```diff
  -        try "$name" rsync "${RS[@]}" --no-r -d --info=progress2 ${rm[@]+"${rm[@]}"} \
  +        try "$name" rsync "${RS[@]}" --no-r --info=progress2 ${rm[@]+"${rm[@]}"} \
  ```

- **M70** (plugins/cpmv:247): Benign. After a failed transfer the mutant also removes now-empty source directories and prints the "kept in the source" line. The exit status stays 1 and no data is at risk, so no test is proposed.

  ```diff
  -            --from0 --files-from="$PLAN_LIST" -- "$(dirname -- "$src")/" "$dest/" || return 1
  +            --from0 --files-from="$PLAN_LIST" -- "$(dirname -- "$src")/" "$dest/"
  ```

### D4. Reproducers for the HIGH findings

`Fact`: run in a scratch case directory with the plugin copy that carries the mutant. The `put` helper sets content and mtime (`touch -d @N`).

T1 (M49), mode 1 move, same size and same mtime, different content:

```bash
# src/proj/s.txt = AAAA (mtime 1750000000), dst/proj/s.txt = BBBB (mtime 1750000000)
printf '1\n' | PLUGIN "mv -i --" sel .          # run inside dst, as nnn does; PLUGIN is the real plugin or the mutant
# real plugin: dst/proj/s.txt = AAAA, source gone     (RC=0)
# M49:         dst/proj/s.txt = BBBB, source GONE     (RC=0)   <- the source bytes are lost
```

T2 (M48), mode 5 copy, partial file with a damaged prefix:

```text
src/proj/big.bin = 0123456789ABCDEFGHIJ   dst/proj/big.bin = XXXXXXXXXX (10 bytes)
real plugin: dst = 0123456789ABCDEFGHIJ     M48: dst = XXXXXXXXXXABCDEFGHIJ
```

T3 (M29): `g_candidate_names` has same-size files that differ only in time. `a.txt` is source-newer, `a.txt.bak` is target-newer. With `grep -aFf` (no `-x`) the pattern `proj/a.txt` matches the candidate line `proj/a.txt.bak`, so the newer target is replaced by the older source (`expected=[dstK] actual=[srcK]`). The same happens for `sub/proj/a.txt`, which contains `proj/a.txt` as a tail.

T5 (M54): `chmod 000 src/proj/sub`, mode 4 copy, then move:

```text
real plugin: RC=1, "! proj: compare failed (rsync status 23) ... opendir ... failed: Permission denied", nothing copied, source untouched
M54:         RC=0, "proj: 2 file(s) to copy ..." (copy);  RC=0 and dn_diff.txt moved, "sub" left unreported (move)
```

T6 (M16): stdin at EOF while the menu is shown:

```bash
( cd dst && timeout 5 PLUGIN "cp -iRp --" sel . < /dev/null 2>&1 | head -c 300000 | wc -c )
# real plugin: 485 bytes, status 0, last line "- skipped proj"
# M16:         300000 bytes (head had to close the pipe), plugin status 141
```

`Risk`: with a real terminal Ctrl-D is not sticky, but when the terminal is closed while a menu waits, `read` fails for ever and the plugin spins at 100% CPU. That is why the `|| choice=7` exists.

### D5. Weak or vacuous assertions in the two suites

| id | where | problem | proof or evidence | fix |
|---|---|---|---|---|
| W1 | `test-cpmv.sh:160` | `has_out ... 'kept\|left in the source'` is always true for modes 3 and 4: the plan line `proj: 3 file(s) to move, 1 kept (same size, target not older), 1 identical` contains "kept". It cannot see the "kept in the source" notice. | M66 (notice removed) passes the unit suite. | Pattern `kept in the source: 1 file\(s\) of proj`. Run from a copy: real plugin `578 passed, 0 failed`; M66 `576 passed, 2 failed` (plain and advcpmv pass). |
| W2 | `test-cpmv-e2e.sh:67` | `waitfor 'proj\|dst' 10`: the typed line `cd '.../dst' && nnn .` already matches, so "nnn started" cannot fail and the next key may arrive before nnn is up. | Private tmux with a missing nnn binary: old pattern MATCH, proposed pattern no match. With a real nnn both match. | Pattern `^1 2 3 4 5 6 7 8 ` (the nnn context bar). Run from a copy against the real plugin: `20 passed, 0 failed (11s)`. |
| W3 | `test-cpmv.sh:361-375` | `g_oracle` (160 random files) compares destination content only. It does not check the exit status or, after a move, that every source file either still exists or has its content at the target. | By reading. | Add a source-content map and the exit status check (not written; the explicit groups already cover the known cases). |
| W4 | `test-cpmv-e2e.sh:31, 69` | `tmux kill-server` leaves the socket file: one `cpmve2e-<pid>` file per run stays in `/tmp/tmux-<uid>/`. | One e2e run added exactly one new socket file (checked by listing `/tmp/tmux-1000/` before and after). | `rm -f "/tmp/tmux-$(id -u)/$SOCK"` in `cleanup`. |
| W5 | `test-cpmv-e2e.sh:87, 106, 132, 145` | Fixed `sleep 1.5` / `0.8` before reading files. A slow host gives a false failure, not a false pass. | By reading. | Poll the file or the selection with `waitfor`-style loops. |
| W6 | `test-cpmv.sh:118` | Repeats line 117 (same file, same content); the read-only property is gone after the first overwrite, so it adds nothing. | By reading. | Delete it, or assert the mode of the file. |
| W7 | `test-cpmv.sh:183, 195` | `no_out ... 'cannot move'` depends on the English text of `mv`; under another `LANG` it is vacuous. The `RC` check next to it still guards. | By reading. | Run the plugin with `LC_ALL=C` in `run`. |
| W8 | `test-cpmv.sh:51` | `run` gives a hanging plugin 60 s and does not cap the output. M16 wrote 197 kB in 3 s (about 4 MB per `run` before the timeout), and each such `run` costs a full minute. | M16 reproducer above. | Use `run_capped` (appendix) for tests that may hang. |
| W9 | `test-cpmv.sh:271, 282` | `g_errors` needs `chmod 000` to fail. As root it fails (false failure, not a pass). | Not verified (no root run). | Skip with a message when `id -u` is 0. |
| W10 | `test-cpmv.sh:392`, `test-cpmv-e2e.sh:138` | The advcpmv pass and E2E 4 are skipped silently when `cpg` is missing; M68 (`mvg` not recognised) is killed only by that pass. | M68 is killed by the unit advcpmv pass only. | Print `SKIP advcpmv` so a missing pass is visible. |
| W11 | `test-cpmv.sh:277` | `'Permission denied\|failed\|error'` is loose: any of three words passes. | By reading. | Match the plugin line `compare failed\|failed \(status`. |

No cleanup in either script can delete outside its own temp directory: `rm -rf` is only run on `$T` and `$C` (unit) and `$S` and `$1` of `fixture` (e2e), all built from `mktemp -d` and fixed case names, and tmux is always addressed with the private `-L` socket.

### D6. Observations about the plugin (outside the test lens)

**O1 (Open question, reproduced).** In a MOVE with mode 2, 3 or 4, a file with the same size and the same mtime as the target is "identical" (rsync quick check). The plan lists it so that rsync removes the source. If the content differs, the source bytes are lost:

```text
src/proj/s.txt = AAAA (1750000000)   dst/proj/s.txt = BBBB (1750000000)
mv, mode 2: dst = BBBB, source GONE, RC=0
mv, mode 3: dst = BBBB, source GONE, RC=0
mv, mode 4: dst = BBBB, source GONE, RC=0
```

Mode 1 is safe because of `-I`. `Assumption`: this is the rsync convention and the owner may accept it; files with fixed mtimes (reproducible builds) are a realistic case. `Decision` needed. No test pins either behaviour, so I did not write one.

**O2 (Open question, reproduced).** A dangling symlink at the target is a conflict, and the y/N prompt is shown, but `y` cannot succeed: `cp: not writing through dangling symlink` (also with `cpg`), status 1. The failure is reported and nothing is lost. Command: dangling link `dst/f.txt`, `printf 'y\n' | PATH=/usr/bin:/bin plugins/cpmv "cp -iRp --" sel .`.

### D7. How to add the new tests

1. Paste the appendix block at the `# @@APPEND@@` marker of `misc/test/test-cpmv.sh`.
2. Add the group names listed in `NEWSUITE` to the `SUITE` array and delete the `NEWSUITE` line (in the scratch copy `NEWSUITE` only lets `NEWONLY=1` run the new groups alone).
3. Apply the two one-line assertion fixes (W1, W2).
4. Run `misc/test/test-cpmv.sh`. Measured on the real plugin from the scratch copy: `1072 passed, 0 failed` in 37 s (578 old + 494 new checks, plain and advcpmv passes). The new groups alone take 14 s.

The groups need GNU `find -printf` (helper `snap`) and `stat -c`, like the existing script. `g_no_rsync` links a fixed list of tools into a PATH without rsync. `g_candidate_names` runs the plugin with `LC_ALL=C.UTF-8` and skips the invalid-UTF-8 name when the file system refuses it.

## What I checked and found fine

- **The fix and the original bugs.** M01 to M08 (mode 4 back to `--update`, mode 3 back to `--size-only`, no source-newer candidates, candidates copied blindly, no `--remove-source-files` plus `rm -rf`, `finish_move` removing non-empty directories, identical files not removed on a move) are all killed, by several groups each.
- **Exit status and nnn integration.** M09, M10, M46, M58 (errors uncounted, `exit 1` to `exit 0`, missing source uncounted, last path dropped) are killed; the e2e suite adds the pause, the kept selection and the retry.
- **Policy details.** D1 offsets and flags (M21 to M24, M26, M27), `-K` (M13), `-p`/`-f`/`-u` flags (M59 to M62), mode 5 move (M57), directory move in modes 1 and 2 (M18, M19, M61), clash and apply-to-all state (M11, M12, M44, M45), rename numbering (M33, M71), `mvg` detection (M68).
- **Test hygiene.** The new groups pass 3 of 3 repeated runs on the real plugin, are `shellcheck` clean, and leave no temp directory (`TMPDIR` is a case directory in `g_tmpdir_cleanup`). Nothing in either existing script deletes outside its own temp directory.
- **e2e suite.** It checks what the unit suite cannot: the pause, `failed!`, the kept selection and the retry. Its 20 checks kill 15 of 73 mutants; it is narrow (mode 4, one directory) by design.

## Not verified

- Old-bash behaviour: the `${rm[@]+"${rm[@]}"}` guard matters on bash 3.2 and 4.3 only. Only bash 5.2.37 was used.
- BSD and macOS tools (`stat -f`, BSD `cp`, `find`, `grep`): not run.
- Running the suites as root: not run (W9 is reasoning only).
- Real tty behaviour of `cp`/`mv` prompts (for example `mv` asking about a read-only target): the unit suite pipes stdin and the e2e suite uses mode 4 only.
- A machine without advcpmv (`cpg`, `mvg`): not run; M68 would then survive.
- The new groups under a plain `C` locale: `g_candidate_names` forces `LC_ALL=C.UTF-8`; M30 is only killable in a UTF-8 locale.
- A move across file systems (`mv` falling back to copy and delete): no suite covers it, and I did not test it.
- Mutation coverage is hand-written (73 mutants, one edit each); I ran no automatic operator sweep.
- W3 (stronger oracle) has no written test.
- Cleanup: I removed the 95 `/tmp/cpmv.*` directories left by the first M47 run and by e2e runs whose plugin was killed, and my 77 stale tmux socket files. Four other `/tmp/cpmv.*` directories (three at 15:44 with plan files, one empty at 15:54) and two older `cpmve2e-*` sockets could not be attributed to my runs and were left in place.

## Appendix: new tests (all pass on the real plugin)

Insert at the `# @@APPEND@@` marker of `misc/test/test-cpmv.sh`. Proof of each group is in D3.

```bash
# ===========================================================================
# Groups proposed by the mutation review of e2fcb93d.
# Inserted at the @@APPEND@@ marker of misc/test/test-cpmv.sh in a COPY; the group
# names are listed in NEWSUITE. They use the helpers of that script
# (new_case, put, run, fc, check, has_out, no_out, miss, mixed_fixture, two_dirs_and_file).
# ===========================================================================

# run_capped: like run, but a plugin that loops forever is stopped after 10 s and
# its output is capped at 200 kB, so a missing "|| choice=7" cannot fill the disk.
run_capped() {
    local op="$1" ans="$2" it; shift 2
    local abs=(); for it in "$@"; do abs+=("$C/$it"); done
    printf '%s\0' "${abs[@]}" | head -c -1 > "$C/sel"
    OUT="$C/out"
    ( cd "$C/dst" && printf '%b' "$ans" | timeout 10 "$CPMV" "$op" "$C/sel" . 2>&1 | head -c 200000 > "$OUT"
      exit "${PIPESTATUS[1]}" )
    RC=$?
}

# --- an item selected in the destination directory itself -----------------------
g_same_file() {
    local o
    for o in "$CPOP" "$MVOP"; do
        new_case "same-file-${o%% *}"
        put dst/f.txt "KEEP" $MID; put dst/proj/a.txt "AAA" $OLD; put dst/proj/sub/b.txt "BBB" $MID
        run "$o" '4\n4\n' dst/f.txt dst/proj
        has_out "same file is reported as skipped"      'skipped \(same file\) f\.txt'
        has_out "same directory is reported as skipped" 'skipped \(same file\) proj'
        no_out  "same file: no menu, no prompt"         'CONFLICT|\[y/N\]'
        fc "same file is untouched"      dst/f.txt        "KEEP" $MID
        fc "same directory is untouched" dst/proj/a.txt   "AAA"  $OLD
        fc "nested file is untouched"    dst/proj/sub/b.txt "BBB" $MID
        check "same-file-${o%% *}: exit status 0" "0" "$RC"
    done
}

# --- end of input at a menu must mean "skip", never an endless loop ---------------
g_eof_at_menu() {
    new_case eof-main-menu; mixed_fixture
    run_capped "$CPOP" '' src/proj
    check "eof-main-menu: the plugin ends by itself with status 0" "0" "$RC"
    fc "EOF at the menu skips: target untouched" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    new_case eof-clash-menu
    put src/thing "file" $NEW; mkdir -p "$C/dst/thing"
    run_capped "$CPOP" '' src/thing
    check "eof-clash-menu: the plugin ends by itself with status 0" "0" "$RC"
    check "eof-clash-menu: the directory is untouched" "yes" "$([ -d "$C/dst/thing" ] && echo yes || echo no)"
    new_case eof-apply-prompt; two_dirs_and_file
    run_capped "$CPOP" '4\n' src/A src/B
    check "eof-apply-prompt: ends with status 0" "0" "$RC"
    fc "first item got the typed mode 4"            dst/A/x.txt "A-src" $OLD
    fc "second item: EOF at its menu means skip"    dst/B/y.txt "B-dst-longer" $NEW
}

# --- the single-file y/N prompt: default is No, y/Y/yes/YES overwrite ------------
g_single_file_answers() {
    local i=0 ans
    for ans in '' '\n' 'maybe\n' 'nO\n'; do
        i=$((i + 1)); new_case "single-file-no-$i"
        put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
        run "$CPOP" "$ans" src/f.txt
        fc "answer [$ans] keeps the target (default is No)" dst/f.txt "old-longer" $OLD
        check "single-file-no-$i: exit status 0" "0" "$RC"
    done
    for ans in 'Y\n' 'yes\n' 'YES\n'; do
        i=$((i + 1)); new_case "single-file-yes-$i"
        put src/f.txt "new" $NEW; put dst/f.txt "old-longer" $OLD
        run "$CPOP" "$ans" src/f.txt
        fc "answer [$ans] overwrites" dst/f.txt "new" $NEW
    done
}

# --- "apply to ALL" is offered only while items remain --------------------------
g_apply_prompt() {
    new_case apply-prompt-one; mixed_fixture
    run "$CPOP" '4\n' src/proj
    no_out "a single directory never asks 'apply to ALL'" 'apply to ALL'
    new_case apply-prompt-two; two_dirs_and_file
    run "$CPOP" '4\nn\n4\n\n' src/A src/B
    check "apply-prompt-two: asked once, not after the last item" "1" "$(grep -o 'apply to ALL' "$OUT" | wc -l)"
}

# --- rename: extension, dotfile, dotted directory, dangling link in the way -------
g_rename_names() {
    new_case rename-names
    put src/a.txt "S-a" $NEW;    put dst/a.txt "D-a" $OLD
    put src/.hid  "S-hid" $NEW;  put dst/.hid  "D-hid" $OLD
    put src/dir.v2/f "S-f" $NEW; put dst/dir.v2/f "D-f" $OLD
    put src/b.txt "S-b" $NEW;    put dst/b.txt "D-b" $OLD
    ln -s nowhere "$C/dst/b (1).txt"                       # a dangling link already holds the first free name
    run "$CPOP" '6\ny\n\n' src/a.txt src/.hid src/dir.v2 src/b.txt
    fc "a file keeps its extension: 'a (1).txt'"   "dst/a (1).txt" "S-a"
    fc "the original a.txt is untouched"           dst/a.txt "D-a" $OLD
    fc "a dotfile becomes '.hid (1)'"              "dst/.hid (1)" "S-hid"
    fc "a dotted directory becomes 'dir.v2 (1)'"   "dst/dir.v2 (1)/f" "S-f"
    fc "a dangling link name is skipped: 'b (2).txt'" "dst/b (2).txt" "S-b"
    check "rename-names: the dangling link is untouched" "<link:nowhere>" "$(getc 'dst/b (1).txt')"
    check "rename-names: exit status 0" "0" "$RC"
}

# --- dangling symbolic links ---------------------------------------------------
g_dangling_links() {
    local o
    for o in "$CPOP" "$MVOP"; do
        new_case "dangling-source-${o%% *}"
        ln -s nowhere "$C/src/lnk"
        run "$o" '' src/lnk
        fc "a dangling source link is transferred as a link" dst/lnk "<link:nowhere>"
        check "dangling-source-${o%% *}: exit status 0" "0" "$RC"
    done
    new_case dangling-source-mv-gone
    ln -s nowhere "$C/src/lnk"; run "$MVOP" '' src/lnk
    miss "moved dangling link" src/lnk
    new_case dangling-target
    put src/f.txt "SRC" $NEW; ln -s nowhere "$C/dst/f.txt"
    run "$CPOP" 'n\n' src/f.txt
    has_out "a dangling link at the target is a conflict: the prompt is shown" "overwrite 'f\.txt'\? \[y/N\]"
    check "dangling-target: answer n keeps the link" "<link:nowhere>" "$(getc dst/f.txt)"
    check "dangling-target: exit status 0" "0" "$RC"
}

# --- the plan summary and the kept notice, with exact numbers ---------------------
g_plan_summary() {
    new_case summary-copy4; mixed_fixture
    put src/proj/dn_same2.txt "SOLD2!" $OLD; put dst/proj/dn_same2.txt "DNEW2!" $NEW      # a second kept file
    run "$CPOP" '4\n' src/proj
    has_out "mode 4 copy summary" 'proj: 5 file\(s\) to copy, 2 kept \(same size, target not older\), 1 identical'
    new_case summary-move3; mixed_fixture
    put src/proj/dn_same2.txt "SOLD2!" $OLD; put dst/proj/dn_same2.txt "DNEW2!" $NEW
    run "$MVOP" '3\n' src/proj
    has_out "mode 3 move summary" 'proj: 4 file\(s\) to move, 3 kept \(same size\), 1 identical'
    has_out "the kept notice counts the files left behind" 'kept in the source: 3 file\(s\) of proj'
}

# --- the pause rule -----------------------------------------------------------
g_pause_rule() {
    new_case pause-move-kept; mixed_fixture
    run "$MVOP" '4\n' src/proj
    has_out "a move that leaves files behind pauses for review" 'Done\. Press enter'
    new_case pause-move-clean
    put src/a.txt "A" $MID
    run "$MVOP" '' src/a.txt
    no_out "no conflict and nothing left behind: no pause" 'Press enter'
    new_case pause-copy-one-dir; mixed_fixture
    run "$CPOP" '4\n' src/proj
    no_out "a single directory copy: no pause" 'Press enter'
}

# --- a plain file kept by a move: announced and left in the source -------------------
g_move_kept_file() {
    new_case move-kept-file
    put src/c.txt "SOLD!!" $OLD; put dst/c.txt "DNEWER" $NEW            # same size, target newer: mode 4 keeps it
    put src/d.txt "D-src"  $OLD; put dst/d.txt "D-dst-longer" $NEW
    run "$MVOP" '4\ny\n\n' src/c.txt src/d.txt
    fc "the kept plain file stays in the source" src/c.txt "SOLD!!" $OLD
    fc "the kept plain file leaves the target alone" dst/c.txt "DNEWER" $NEW
    has_out "the kept file is announced" 'kept in the source: 1 file\(s\) of c\.txt'
    miss "moved plain file source" src/d.txt
    fc "moved plain file arrived" dst/d.txt "D-src" $OLD
}

# --- mode 1 move merge must overwrite a file with equal size and equal mtime -------
g_move_mode1_same_time() {
    new_case move-mode1-sametime
    put src/proj/s.txt "AAAA" $MID; put dst/proj/s.txt "BBBB" $MID      # same size, same mtime, different content
    put src/proj/o.txt "ONE"  $OLD; put dst/proj/o.txt "TWO"  $OLD
    run "$MVOP" '1\n' src/proj
    fc "overwrite replaces a target with the same size and mtime" dst/proj/s.txt "AAAA" $MID
    fc "same for another pair"                                     dst/proj/o.txt "ONE"  $OLD
    miss "source after the overwriting move" src/proj
    check "move-mode1-sametime: exit status 0" "0" "$RC"
}

# --- mode 5 verifies the part that is already there -----------------------------------
g_resume_verify() {
    new_case resume-badprefix
    put src/proj/big.bin "0123456789ABCDEFGHIJ" $MID; put dst/proj/big.bin "XXXXXXXXXX" $MID   # short AND damaged
    run "$CPOP" '5\n' src/proj
    fc "resume notices a damaged partial file and repairs it" dst/proj/big.bin "0123456789ABCDEFGHIJ"
}

# --- the conflict header ---------------------------------------------------------
g_conflict_header() {
    new_case header-dir; mixed_fixture
    run "$CPOP" '7\n' src/proj
    has_out "a directory conflict says (directory)" 'source +: +\(directory\)'
    no_out  "a directory conflict shows no byte size" 'bytes'
    new_case header-files
    put src/a.txt "12345" $NEW; put dst/a.txt "123" $OLD; put src/b.txt "x" $NEW; put dst/b.txt "y" $OLD
    run "$CPOP" '7\nn\n7\n\n' src/a.txt src/b.txt
    has_out "a file conflict shows the source size" 'source +: +5 bytes'
    has_out "a file conflict shows the target size" 'target +: +3 bytes'
}

# --- the type-clash menu only offers rename and skip --------------------------------
g_clash_menu() {
    new_case clash-menu
    put src/thing "f" $NEW; mkdir -p "$C/dst/thing"
    run "$CPOP" '7\n' src/thing
    has_out "the clash is explained"                      'a file and a directory share this name'
    no_out  "the clash menu does not list impossible modes" '1\) overwrite|3\) different size|4\) different size|5\) resume'
}

# --- an invalid menu answer is refused and asked again ------------------------------
g_invalid_choice() {
    new_case invalid-choice; mixed_fixture
    run "$CPOP" '9\n0\nx\n\n4\n' src/proj
    check "four invalid answers, four refusals" "4" "$(grep -c 'invalid\.' "$OUT")"
    fc "the real choice (4) is applied afterwards" dst/proj/dn_diff.txt "AAAAA" $OLD
}

# --- a comparison that fails must be reported, not ignored ----------------------------
g_compare_fails() {
    local o mode
    for o in "$CPOP" "$MVOP"; do for mode in 4 3; do
        new_case "compare-fails-${o%% *}-$mode"; mixed_fixture
        chmod 000 "$C/src/proj/sub"                      # rsync cannot list this directory
        run "$o" "$mode\\n" src/proj
        chmod 755 "$C/src/proj/sub"
        check "compare-fails-${o%% *}-$mode: non-zero exit" "1" "$RC"
        has_out "compare-fails-${o%% *}-$mode: the comparison failure is named" 'compare failed'
        fc "nothing is transferred after a failed comparison" dst/proj/dn_diff.txt "xxxxxxx" $NEW
        fc "the source is untouched" src/proj/dn_diff.txt "AAAAA" $OLD
    done; done
}

# a shim that makes only the second comparison (rsync -n --update) fail
g_compare_fails_second_run() {
    new_case compare-fails-d2; mixed_fixture
    mkdir -p "$C/bin"
    cat > "$C/bin/rsync" <<SHIM
#!/bin/sh
case " \$* " in *" --update "*) case " \$* " in *" -n "*) echo "rsync: injected failure" >&2; exit 23 ;; esac ;; esac
exec $(command -v rsync) "\$@"
SHIM
    chmod +x "$C/bin/rsync"
    PATH="$C/bin:$PATH" run "$CPOP" '4\n' src/proj
    check "second comparison fails: non-zero exit" "1" "$RC"
    has_out "second comparison fails: it is named, with the status of THAT run" 'compare failed \(rsync status 23\).*injected failure'
    fc "second comparison fails: nothing is copied" dst/proj/dn_diff.txt "xxxxxxx" $NEW
}

# --- rsync not installed ---------------------------------------------------------
g_no_rsync() {
    local t p o
    new_case no-rsync; mixed_fixture
    mkdir -p "$C/nobin"
    for t in bash env cat cp mv rm rmdir mkdir mktemp find basename dirname stat cut head tr wc grep sed timeout cpg mvg; do
        p=$(command -v "$t") && ln -s "$p" "$C/nobin/$t"
    done
    PATH="$C/nobin" run "$CPOP" '4\n' src/proj
    has_out "without rsync, mode 4 says so" 'rsync missing'
    check "without rsync: non-zero exit" "1" "$RC"
    fc "without rsync: nothing changed" dst/proj/dn_diff.txt "xxxxxxx" $NEW
    new_case no-rsync-move; mixed_fixture
    mkdir -p "$C/nobin"
    for t in bash env cat cp mv rm rmdir mkdir mktemp find basename dirname stat cut head tr wc grep sed timeout cpg mvg; do
        p=$(command -v "$t") && ln -s "$p" "$C/nobin/$t"
    done
    PATH="$C/nobin" run "$MVOP" '1\n' src/proj
    has_out "without rsync, a directory move onto a directory says so" 'rsync missing'
    fc "without rsync: the source is untouched" src/proj/dn_diff.txt "AAAAA" $OLD
    fc "without rsync: the target is untouched" dst/proj/dn_diff.txt "xxxxxxx" $NEW
}

# --- the temp directory of the plugin is always removed -----------------------------
g_tmpdir_cleanup() {
    local mode
    for mode in 4 3 1; do
        new_case "tmpdir-$mode"; mixed_fixture; mkdir -p "$C/tmp"
        TMPDIR="$C/tmp" run "$CPOP" "$mode\\n" src/proj
        check "tmpdir-$mode: nothing is left in TMPDIR" "0" "$(find "$C/tmp" -mindepth 1 | wc -l)"
    done
    new_case tmpdir-failure; mixed_fixture; mkdir -p "$C/tmp"
    chmod 000 "$C/src/proj/sub/deep/n_dn.txt"
    TMPDIR="$C/tmp" run "$CPOP" '4\n' src/proj
    chmod 644 "$C/src/proj/sub/deep/n_dn.txt"
    check "tmpdir-failure: the run failed as intended" "1" "$RC"
    check "tmpdir-failure: nothing is left in TMPDIR after a failure" "0" "$(find "$C/tmp" -mindepth 1 | wc -l)"
}

# --- paths with spaces and quotes in the DESTINATION and in the source parent --------------
g_paths_with_spaces() {
    local o mode
    for o in "$CPOP" "$MVOP"; do for mode in 4 3 1 2; do
        new_case "sp ace's [dir] ${o%% *} $mode"; mixed_fixture
        run "$o" "$mode\\n" src/proj
        fc "size differs, dest newer: replaced (mode $mode)" dst/proj/do_diff.txt "DDDDDDDD" $MID
        check "spaces ${o%% *} $mode: exit status 0" "0" "$RC"
    done; done
}

# --- candidates: same size, only the time differs; awkward names -----------------------------
g_candidate_names() {
    local bad=$'bad\xffutf8.txt' n
    local snew=("a.txt" 'x[1].txt' 'x*.txt' 'sp ace.txt' 'back\slash.txt' $'nl\nname.txt' $'\xc3\xbcn\xc3\xaf.txt' "$bad")
    local tnew=("a.txt.bak" 'aXtxt' 'x1.txt' 'sub/proj/a.txt' 'xyz.txt')
    new_case candidate-names
    for n in "${snew[@]}"; do put "src/proj/$n" "SRC1" $NEW; put "dst/proj/$n" "dst1" $OLD; done
    for n in "${tnew[@]}"; do put "src/proj/$n" "srcK" $OLD; put "dst/proj/$n" "dstK" $NEW; done
    [ -e "$C/src/proj/$bad" ] || snew=("${snew[@]:0:7}")                  # the file system refuses that name
    LC_ALL=C.UTF-8 run "$CPOP" '4\n' src/proj
    for n in "${snew[@]}"; do fc "source newer is copied: $n" "dst/proj/$n" "SRC1" $NEW; done
    for n in "${tnew[@]}"; do fc "target newer is kept: $n"   "dst/proj/$n" "dstK" $NEW; done
    new_case candidate-names-3
    for n in "${snew[@]}"; do put "src/proj/$n" "SRC1" $NEW; put "dst/proj/$n" "dst1" $OLD; done
    LC_ALL=C.UTF-8 run "$CPOP" '3\n' src/proj
    for n in "${snew[@]}"; do fc "mode 3 leaves a same-size file alone: $n" "dst/proj/$n" "dst1" $OLD; done
}

# --- moving symbolic links: identical ones must not stay behind -------------------------
g_move_symlinks() {
    local mode
    for mode in 4 3; do
        new_case "move-symlinks-$mode"
        put src/proj/real.txt "REAL" $MID; put dst/proj/real.txt "REAL" $MID
        ln -s real.txt "$C/src/proj/same_lnk"; ln -s real.txt "$C/dst/proj/same_lnk"    # identical link on both sides
        ln -s real.txt "$C/src/proj/new_lnk"                                            # link only in the source
        run "$MVOP" "$mode\\n" src/proj
        fc "a new link arrives as a link" dst/proj/new_lnk "<link:real.txt>"
        fc "an identical link stays a link" dst/proj/same_lnk "<link:real.txt>"
        miss "identical link in the source" src/proj/same_lnk
        miss "moved link in the source" src/proj/new_lnk
        miss "whole source tree" src/proj
        check "move-symlinks-$mode: exit status 0" "0" "$RC"
        no_out "move-symlinks-$mode: nothing reported as left behind" 'kept in the source'
    done
}

# --- names that rsync escapes more than once (\#ooo twice or more) ------------------------------
g_names_multi_escape() {
    local names=($'two\nnew\nlines.txt' $'tab\there\nand\nnewline.txt' 'a\#012b\#012c.txt') n mode
    for mode in 4 3; do
        new_case "names-multi-escape-$mode"
        for n in "${names[@]}"; do put "src/proj/$n" "src" $OLD; put "dst/proj/$n" "dest-longer" $NEW; done
        run "$CPOP" "$mode\\n" src/proj
        for n in "${names[@]}"; do fc "$n" "dst/proj/$n" "src" $OLD; done
        check "names-multi-escape-$mode: exit status 0" "0" "$RC"
    done
}

# --- a directory move onto a symbolic link that points to a directory ----------------------
g_move_dirlink() {
    local mode
    for mode in 1 4; do
        new_case "move-dirlink-$mode"
        put src/proj/f.txt "SRC" $OLD; put dst/realdir/f.txt "dest-longer" $NEW; ln -s realdir "$C/dst/proj"
        run "$MVOP" "$mode\\n" src/proj
        fc "move mode $mode: the linked target directory is merged INTO" dst/realdir/f.txt "SRC" $OLD
        check "move-dirlink-$mode: the target symlink is kept" "yes" "$([ -L "$C/dst/proj" ] && echo yes || echo no)"
        miss "source after the move" src/proj
    done
}

# --- a COPY never changes the source tree (whole-tree snapshot, every mode) --------------
snap() { ( cd "$C/$1" && find . -printf '%p %y %s %T@ %l\n' | sort; find . -type f -exec md5sum {} + | sort ); }
g_copy_source_untouched() {
    local mode before after
    for mode in 1 2 3 4 5 6 7; do
        new_case "copy-src-untouched-$mode"; mixed_fixture
        before=$(snap src)
        run "$CPOP" "$mode\\n" src/proj
        after=$(snap src)
        check "copy mode $mode: the source tree is unchanged (names, types, sizes, mtimes, content)" "$before" "$after"
    done
}

NEWSUITE=(g_same_file g_eof_at_menu g_single_file_answers g_apply_prompt g_rename_names g_dangling_links
          g_plan_summary g_pause_rule g_move_kept_file g_move_mode1_same_time g_resume_verify g_conflict_header
          g_clash_menu g_invalid_choice g_compare_fails g_compare_fails_second_run g_no_rsync g_tmpdir_cleanup
          g_paths_with_spaces g_candidate_names g_move_symlinks g_names_multi_escape g_move_dirlink g_copy_source_untouched)
```

