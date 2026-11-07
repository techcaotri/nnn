# Brief: strength of the cpmv tests (mutation analysis)

Read `docs/workflows/cpmv_overwrite/agents/_context.md` first and follow its rules.

Report path: `docs/workflows/cpmv_overwrite/notes/review-test-strength.md`

## Your lens

Answer one question: if someone breaks `plugins/cpmv` in a realistic way, do
`misc/test/test-cpmv.sh` and `misc/test/test-cpmv-e2e.sh` notice? A test that passes for a
broken plugin is a defect in the test.

## Method

1. Copy `plugins/cpmv` into your scratch directory. Never edit the repo file.
2. Create at least 15 mutants by editing the COPY with `sed` or a small script. Each mutant is
   one realistic bug. Suggested mutants (add your own):
   - mode 4 goes back to `rsync -a --update` on the whole tree
   - mode 3 goes back to `rsync -a --size-only`
   - the plan keeps only `s`-flag files and forgets the "source is newer" candidates
   - the plan adds files the mode should keep
   - a move forgets `--remove-source-files` and removes the source with `rm -rf`
   - `finish_move` removes non-empty directories
   - identical files are no longer added to the list for a move
   - `try` does not count failures; `exit 1` becomes `exit 0`
   - the file-versus-directory clash check is removed
   - `GLOBAL_MODE` is applied to a clash item
   - `-K` is dropped from `RS`
   - `rs_unescape` returns the name unchanged
   - the directory trailing slash is no longer stripped
   - `read -r choice || choice=7` becomes a loop that never ends on EOF
   - mode 1 move of a directory goes back to `mv -f`
   - the pause rule: `kept_in_src` no longer triggers `Done. Press enter.`
3. For each mutant run both suites against it:

   ```bash
   CPMV=/your/scratch/mutant1 timeout 280 misc/test/test-cpmv.sh | tail -3
   CPMV=/your/scratch/mutant1 timeout 280 misc/test/test-cpmv-e2e.sh | tail -3
   ```

   The unit suite takes under a minute. The e2e suite takes under a minute. Run mutants one at a
   time or a few in parallel, but never edit or move a mutant while a suite uses it.
   A mutant is KILLED when a suite fails, SURVIVED when both pass, and INVALID when the mutated
   script does not parse (check `bash -n` first).
4. For every SURVIVED mutant, write the missing test as a bash function in the style of
   `misc/test/test-cpmv.sh` (use `new_case`, `put`, `run`, `fc`, `check`) inside your report.
   Prove it: show it fails against the mutant and passes against the real plugin by running it
   from a COPY of the test script in your scratch directory.

## Also review the tests themselves

List any assertion in the two test scripts that is vacuous or too weak: a `check` that cannot
fail, a path that is never reached, an expectation that merely mirrors the implementation, a
cleanup that could delete something outside the temp dir.

## Deliverable

The report at the path above: a mutant table (id, description, KILLED/SURVIVED/INVALID, which
suite killed it), then the new tests for survivors, then the weak assertions.
