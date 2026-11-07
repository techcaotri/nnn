# Brief: adversarial correctness review of plugins/cpmv

Read `docs/workflows/cpmv_overwrite/agents/_context.md` first and follow its rules.

Report path: `docs/workflows/cpmv_overwrite/notes/review-correctness.md`

## Your lens

Try to break the new `plugins/cpmv`. You are looking for (1) data loss, (2) a wrong overwrite
or a wrong "kept" decision against the mode table in the script header, (3) a failure that is
hidden, (4) a mtime or other side effect on a file the mode promises not to touch.

Do not trust the existing suite. Write your own reproducers, in your scratch directory, that
call the plugin exactly as nnn does:

```bash
printf '%s' "/abs/src/item" > sel            # several items: separate them with NUL, no trailing NUL
cd /abs/dst && printf '4\n' | /path/to/plugins/cpmv 'cp -iRp --' /abs/sel .      # or 'mv -i --'
```

## Areas to attack

1. Move safety: find ANY sequence where a source file is removed but its content is not at
   the target. Think about: failed rsync midway, a file changing between the dry run and the
   transfer, `finish_move` pruning (`find -depth -type d -exec rmdir`), symlinks inside the
   source, a source that is itself a symlink, hard links, a source directory that contains
   the destination, a destination inside the source.
2. Plan parsing: `plan_xfer` parses `rsync -n -ii --out-format='%i %n'`. Try names and file
   types that could confuse it: names that start with a space or contain `->`, hard links,
   fifos, sockets, device files (if you can create them without root), sparse files, empty
   files, a file that is a directory on one side, items with `\#` in the name, names with high
   bytes that are not valid UTF-8, very long names, a name ending in a dot.
3. Mode semantics from the header table: every combination of source/target
   {older, same time, newer} x {smaller, same size, bigger}, as a file and nested in a
   directory, for modes 1 to 5, copy and move. Include equal mtime with different size, and a
   one-second difference. Check content AND mtime of the target, and the source after a move.
4. Mode 4 when the target file is read-only (mode 444) or its directory is read-only (555).
5. The type clash menu, `GLOBAL_MODE` ("apply to all") with a clash and with a missing item.
6. Exit codes and pauses: when does the plugin exit 1, when does it print `Done. Press enter.`,
   can any path read stdin forever (EOF handling) or exit 0 after a failure?
7. Portability reading: the script claims to work on bash 3.2 style constructs. Read it for
   constructs that need a newer bash (arrays with `set -u`, `printf -v`, `+=`, `${var:off:len}`
   with arithmetic). You cannot run bash 3.2 here, so label these `Not verified`.
8. Anything in `plugins/cpmv` that differs between GNU find and `bfs` (this machine's `find`
   is bfs 4.1.1): `-depth`, `-exec ... {} +`, `! -type d`.

## Deliverable

The report at the path above, in the layout of `_context.md`. Put every reproducer in the
report as an exact command block. Finish with the count of reproducers you ran.
