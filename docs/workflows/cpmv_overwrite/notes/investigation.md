# cpmv: why "4) different size or newer" sometimes does not overwrite

## Purpose

Record the investigation of the report: "when copying and replacing a directory with the
same name, at the CONFLICT menu I choose `4) different size or newer`, but sometimes files
with a newer date or a different size are still not overwritten".

Scope: the `plugins/cpmv` script that nnn calls for `p` (copy here) and `v` (move here).
The script is symlinked from `~/.config/nnn/plugins/cpmv`, so the repo file is the live file.

## How the report was reproduced

Fact: the plugin was run directly with nnn's exact selection format (NUL separated, last
NUL truncated), the menu answer `4`, and a source and target tree with controlled mtimes.

```bash
printf '4\n' | plugins/cpmv 'cp -iRp --' <selection-file> .
```

Result (before the fix): a target file that is NEWER than the source but has a DIFFERENT
size (`dest_newer_diff_size.txt`, 7 bytes vs 5 bytes) was left unchanged.

## Root causes

| # | Fact | Where | Effect |
|---|---|---|---|
| 1 | Mode 4 runs `rsync -a --update`. `--update` skips every target file that is newer than the source, whatever its size. The menu promises "different size OR newer". | `plugins/cpmv`, `do_one` mode 4 | Different-size files are kept when the target is newer. This is the reported bug. |
| 2 | Mode 3 runs `rsync -a --size-only`. For same-size files rsync still copies the source mtime onto the target without copying data. | `do_one` mode 3 | A same-size file whose source is newer gets the new mtime but old content. A later mode 4 run sees equal size and equal mtime and never fixes it. |
| 3 | The plugin always `exit 0` and, for one item, returns to nnn without a pause. | end of script | rsync/cp/mv errors vanish when nnn redraws, nnn clears the selection, so a failed paste looks like "it did not overwrite". |
| 4 | Move of a directory onto an existing directory with mode 1 or 2 runs `mv -f` / `mv -u`, which cannot merge directories. | `do_one` modes 1, 2 | `mv: cannot move ... Directory not empty`. Nothing moves, the error is invisible. |
| 5 | Move with modes 3, 4, 5 runs `rsync ... && rm -rf src`. | `rm_src` | Source files that were skipped (target newer, or same size) are deleted too. Data loss. |
| 6 | A directory conflict shows `4096 bytes` for both sides. | `show_conflict` | Misleading, it hides that the menu applies to a whole tree. |

## Evidence kept

- Move, mode 4: source `proj/` disappeared completely while 3 files were never copied
  (`AAAAA`, `SRCOLD`, `BBBBB` existed only in the source).
- rsync probe: `--remove-source-files` keeps files skipped by `--update` and removes
  identical files. `--size-only` rewrites target mtimes (`.f..t......`).
- rsync probe: `--files-from` with `--from0` touches only the listed items.
- rsync escapes control characters and a backslash before `#` as `\#ooo`, so names can be
  decoded safely.

## Design of the fix

1. Mode 3 and 4 become plan then execute. Dry runs (`rsync -n -ii --out-format='%i %n'`)
   decide per file. The real run is one `rsync --files-from` transfer, so files that the
   policy keeps are never touched (no mtime rewrite).
   - mode 3: copy when missing or size differs.
   - mode 4: copy when missing, or size differs, or the source is newer.
2. Move uses `--remove-source-files`, then removes empty source directories. Skipped files
   stay in the source and are reported.
3. Move of a directory in modes 1 and 2 goes through rsync (merge) instead of `mv`.
4. Errors are counted. Any failure prints a summary and exits non-zero, so nnn pauses and
   keeps the selection.
5. File versus directory name clashes only offer rename or skip.

## Status

- IN-PROGRESS: tests in `misc/test/test-cpmv.sh`, fix in `plugins/cpmv`.
