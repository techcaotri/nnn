<h3 align="center"><img src="misc/logo/logo-128x128.png" alt="nnn"><br>nnn - <i>Supercharge your productivity!</i></h3>

<p align="center">
<a href="https://github.com/jarun/nnn/releases/latest"><img src="https://img.shields.io/github/release/jarun/nnn.svg?maxAge=600&label=rel" alt="Latest release" /></a>
<a href="https://repology.org/project/nnn/versions"><img src="https://repology.org/badge/tiny-repos/nnn.svg?header=repos" alt="Availability"></a>
<a href="https://circleci.com/gh/jarun/workflows/nnn"><img src="https://img.shields.io/circleci/project/github/jarun/nnn.svg?label=CircleCI" alt="Circle CI Status" /></a>
<a href="https://github.com/jarun/nnn/actions"><img src="https://img.shields.io/github/jarun/nnn/actions/workflows/ci.yml/badge.svg?branch=master" alt="GitHub CI Status" /></a>
<a href="https://en.wikipedia.org/wiki/Privacy-invasive_software"><img src="https://img.shields.io/badge/privacy-✓-crimson?maxAge=2592000" alt="Privacy Awareness" /></a>
<a href="https://github.com/jarun/nnn/blob/master/LICENSE"><img src="https://img.shields.io/badge/©-BSD%202--Clause-important.svg?maxAge=2592000" alt="License" /></a>
</p>

<p align="center"><a href="https://github.com/user-attachments/assets/541ca36d-ae26-49fb-97da-d1f7a12d4b9a"><img src="https://github.com/user-attachments/assets/a8ee4689-1552-4fb1-997e-b16fe8ef5086"></a></p>

<h3 align="center">[<a
href="https://github.com/jarun/nnn#features">Features</a>] [<a
href="https://github.com/jarun/nnn#quickstart">Quickstart</a>] [<a
href="https://github.com/jarun/nnn/tree/master/plugins#nnn-plugins">Plugins</a>] [<a
href="https://github.com/jarun/nnn/wiki">Wiki</a>]</h3>

`nnn` (_n³_) is a full-featured terminal file manager. It's tiny, nearly 0-config and [incredibly fast](https://github.com/jarun/nnn/wiki/Performance).

It is designed to be unobtrusive with smart workflows to match the trains of thought.

`nnn` can analyze disk usage, batch rename, launch apps and pick files. The plugin repository has tons of plugins to extend the capabilities further e.g. [live previews](https://github.com/jarun/nnn/wiki/Live-previews), (un)mount disks, find & list, file/dir diff, upload files. A [patch framework](https://github.com/jarun/nnn/tree/master/patches) hosts sizable user-submitted patches which are subjective in nature.

Independent (neo)vim plugins - [nnn.vim](https://github.com/mcchrish/nnn.vim), [vim-floaterm nnn wrapper](https://github.com/voldikss/vim-floaterm#nnn) and [nnn.nvim](https://github.com/luukvbaal/nnn.nvim) (neovim exclusive).

Runs on the Pi, [Termux](https://www.youtube.com/embed/AbaauM7gUJw) (Android), Linux, macOS, BSD, Haiku, Cygwin, WSL, across DEs or a strictly CLI env.

[_(more use cases)_](https://github.com/jarun/nnn/wiki/Basic-use-cases#the_nnn-magic)

## Features

- Quality
  - Privacy-aware (no unconfirmed user data collection)
  - POSIX-compliant, follows Linux kernel coding style
  - Highly optimized, static analysis integrated code
- Frugal
  - Typically needs less than 3.5MB resident memory
  - Works with 8 colors (and xterm 256 colors)
  - Disk-IO sensitive (few disk reads and writes)
  - No FPU usage (all integer maths, even for file size)
  - Minimizes screen refresh with fast line redraws
  - Tiny binary (typically around 100KB)
  - 1-column mode for smaller terminals and form factors
  - Hackable - compile in/out features and dependencies
- Portable
  - Language-agnostic plugins
  - Static binary available (no need to install)
  - Minimal library deps, easy to compile
  - No config file, minimal config with sensible defaults
  - Plugin to backup configuration
  - Widely available on many packagers
  - Touch enabled, handheld-friendly shortcuts
  - Unicode support
- Modes
  - Light (default), detail
  - Disk usage analyzer (block/apparent)
  - File picker, (neo)vim plugin
- Navigation
  - Filter with automatic dir entry on unique match
  - *Type-to-nav* (turbo navigation/always filter) mode
  - Jump to an entry with visible relative offset
  - Contexts (_aka_ tabs/workspaces) with custom colors
  - Sessions, bookmarks, mark and visit a dir
  - Remote mounts (needs `sshfs`, `rclone`)
  - Familiar shortcuts (arrows, <kbd>~</kbd>, <kbd>-</kbd>, <kbd>@</kbd>), quick look-up
  - `cd` on quit (*easy* shell integration)
  - Proceed to next file on file open and selection
- Search
  - Instant filtering with *search-as-you-type*
  - Fuzzy, regex (POSIX/PCRE2) and string (default) filters
  - Subtree search plugin to open or edit files
- Sort
  - Ordered pure numeric names by default (visit `/proc`)
  - Case-insensitive version (_aka_ natural) sort
  - By name, access/change/mod (default) time, size, extn
  - Reverse sort
  - Directory-specific ordering
- Mimes
  - Preview hovered files in FIFO-based previewer
  - Open with desktop opener or specify a custom opener
  - File-specific colors (or minimal _dirs in context color_)
  - Icons and Emojis support (customize and compile-in)
  - Plugin for image, video and audio thumbnails
  - Create, list, extract (to), mount (FUSE based) archives
  - Option to open all text files in `$EDITOR`
- Convenience
  - Detailed file stats and mime information
  - Run plugins and custom commands with hotkeys
  - FreeDesktop compliant trash utility integration
  - Cross-dir file/all/range selection
  - Create (with parents), rename, duplicate files and dirs
  - Create new file or directory (tree) on startup
  - Batch renamer for selection or dir
  - List input stream of file paths from stdin or plugin
  - Copy (as), move (as), delete, archive, link selection
  - Easily copy, move paths in system clipboard to current dir
  - Dir updates, notification on `cp`, `mv`, `rm` completion
  - Copy file paths to system clipboard on select
  - Launch apps, run commands, spawn a shell, toggle exe
  - Access context paths/files at prompt or spawned shell
  - Lock terminal after configurable idle timeout
  - Capture and show output of a program in help screen
  - Basic support for screen readers and braille displays

## Quickstart

1. [Install](https://github.com/jarun/nnn/wiki/Usage) `nnn` and the dependencies you need.
2. The desktop opener is default. Use `-e` to open text files in the terminal. Optionally [open detached](https://github.com/jarun/nnn/wiki/Basic-use-cases#detached-text).
3. Configure [`cd` on quit](https://github.com/jarun/nnn/wiki/Basic-use-cases#configure-cd-on-quit).
4. [Sync subshell `$PWD`](https://github.com/jarun/nnn/wiki/Basic-use-cases#sync-subshell-pwd) to `nnn`.
5. [Install plugins](https://github.com/jarun/nnn/tree/master/plugins#installation).
6. Use `-x` to sync selection to clipboard, show notis on `cp`, `mv`, `rm` and set xterm title.
7. For a CLI-only environment, set [`NNN_OPENER`](https://github.com/jarun/nnn/wiki/Usage#configuration) to [`nuke`](https://github.com/jarun/nnn/blob/master/plugins/nuke). Use option `-c`.
8. Bid `ls` goodbye! `alias ls='nnn -de'` :sunglasses:
9. Visit the [Live previews](https://github.com/jarun/nnn/wiki/Live-previews) and [Troubleshooting](https://github.com/jarun/nnn/wiki/Troubleshooting) Wiki pages.

Don't memorize! Arrows, <kbd>/</kbd>, <kbd>q</kbd> suffice. <kbd>Tab</kbd> creates and/or cycles contexts. <kbd>?</kbd> lists shortcuts.

[![](https://github.com/user-attachments/assets/e93f7571-8b8d-4703-bef1-93fc804adf7d)](https://www.youtube.com/embed/-knZwdd1ScU)

[![Wiki](https://img.shields.io/badge/RTFM-nnn%20Wiki-important?maxAge=2592000)](https://github.com/jarun/nnn/wiki)

## Videos

- [nnn file manager on Termux (Android)](https://www.youtube.com/embed/AbaauM7gUJw)
- [NNN File Manager](https://www.youtube.com/embed/1QXU4XSqXNo)
- [This Week in Linux 114 - TuxDigital](https://www.youtube.com/watch?v=5W9ja0DQjSY&t=2059s)
- [nnn file manager basics - Linux](https://www.youtube.com/embed/il2Fm-KJJfM)
- [I'M GOING TO USE THE NNN FILE BROWSER! 😮](https://www.youtube.com/embed/U2n5aGqou9E)
- [NNN: Is This Terminal File Manager As Good As People Say?](https://www.youtube.com/embed/KuJHo-aO_FA)
- [nnn - A File Manager (By Uoou, again.)](https://www.youtube.com/embed/cnzuzcCPYsk)

## Elsewhere

- [AddictiveTips](https://www.addictivetips.com/ubuntu-linux-tips/navigate-linux-filesystem/)
- [ArchWiki](https://wiki.archlinux.org/index.php/Nnn)
- [FOSSMint](https://www.fossmint.com/nnn-linux-terminal-file-browser/)
- [gHacks Tech News](https://www.ghacks.net/2019/11/01/nnn-is-an-excellent-command-line-based-file-manager-for-linux-macos-and-bsds/)
- Hacker News [[1](https://news.ycombinator.com/item?id=18520898)] [[2](https://news.ycombinator.com/item?id=19850656)]
- [It's FOSS](https://itsfoss.com/nnn-file-browser-linux/)
- [Linux Format Issue 265; Manage files with nnn](https://linuxformat.com/archives?issue=265)
- LinuxLinks [[1](https://www.linuxlinks.com/nnn-fast-and-flexible-file-manager/)] [[2](https://www.linuxlinks.com/bestconsolefilemanagers/)] [[3](https://www.linuxlinks.com/excellent-system-tools-nnn-portable-terminal-file-manager/)]
- [Linux Magazine; FOSSPicks](https://www.linux-magazine.com/Issues/2017/205/FOSSPicks/(offset)/15)
- [Make Tech Easier](https://www.maketecheasier.com/nnn-file-manager-terminal/)
- [Opensource.com](https://opensource.com/article/22/12/linux-file-manager-nnn)
- [Open Source For You](https://www.opensourceforu.com/2019/12/nnn-this-feature-rich-terminal-file-manager-will-enhance-your-productivity/)
- [PCLinuxOS Magazine Issue June 2021](https://pclosmag.com/html/Issues/202106/page08.html)
- [Suckless Rocks](https://suckless.org/rocks/)
- [Ubuntu Full Circle Magazine Issue 135; Review: nnn](https://fullcirclemagazine.org/issue-135/)
- [Using and Administering Linux: Volume 2: Zero to SysAdmin: Advanced Topics](https://books.google.com/books?id=MqjDDwAAQBAJ&pg=PA32)
- [Wikipedia](https://en.wikipedia.org/wiki/Nnn_(file_manager))

## Developers

- [Arun Prakash Jana](https://github.com/jarun) (Copyright © 2016-2026)
- [0xACE](https://github.com/0xACE)
- [Anna Arad](https://github.com/annagrram)
- [KlzXS](https://github.com/KlzXS)
- [Léo Villeveygoux](https://github.com/leovilok)
- [Luuk van Baal](https://github.com/luukvbaal)
- [NRK](https://codeberg.org/NRK)
- [Sijmen J. Mulder](https://github.com/sjmulder)
- and other contributors

Visit the [Tracker](https://github.com/jarun/nnn/issues/1546) thread for a list of features in progress and anything up for grabs. Feel free to [discuss](https://github.com/jarun/nnn/discussions) new ideas or enhancement requests.

---

# 🚀 Fork Enhancements

This fork adds three major features on top of upstream nnn: **native Drag-and-Drop**, an **unlimited cross-instance directory history**, and a **CWD guard** that protects against a subtle Unix shell trap. All are opt-in and designed to minimize merge friction with upstream.

---

## ◈ Native Drag-and-Drop (DnD)

Drag files **OUT** of nnn into GUI apps (browsers, file managers, chat uploads, image editors), and drop files **IN** from GUI apps. A TUI owns no window, so drag-and-drop must be delegated. This fork provides **two complementary approaches**, automatically chosen at runtime.

### Why a TUI Cannot "Just Drag" by Itself

Drag-and-drop on X11 (XDND) and Wayland (`wl_data_device`) is a window-to-window conversation — the X server delivers DnD messages to the window under the pointer. That window belongs to the **terminal emulator**, not to nnn. nnn is a pty-bound process, and everything it receives arrives as bytes through the pty with no drawing surface the display server can address. So every TUI delegates DnD to something that does own a window — either a small helper GUI process (Approach B) or the terminal emulator itself via escape codes (Approach D).

### Key Binding

<kbd>D</kbd> — `SEL_DRAGDROP`: prompt for **(d)rag out** or **\(r)eceive** (drop in).

### Approach B — `nnn-dnd`: Bundled Native XDND Helper (libX11)

A small C helper ([src/nnn-dnd.c](src/nnn-dnd.c), ~900 lines) that implements the XDND protocol version 5 directly on **libX11** — no GTK/Qt dependency. It is a CLI-compatible drop-in replacement for `dragon`/`ripdrag`.

**How it works:**

| Direction | Flow |
|-----------|------|
| **Drag OUT** | nnn spawns `nnn-dnd` detached with the selection; the helper creates a small window, owns `XdndSelection`, and drives the XDND handshake (XdndEnter → XdndPosition → XdndDrop → serve `text/uri-list`). nnn never blocks. |
| **Drop IN** | `nnn-dnd --target` creates an `XdndAware` window; on drop it parses the received `file://` URIs, prints plain paths, and the core (or plugin) appends them to `NNN_SEL` and shows them via `NNN_PIPE` list mode. |

**Build:** `make O_DND=1` — the default build is unchanged and links no new library. With `O_DND=1`, the Makefile also compiles `nnn-dnd` (links `-lX11` only — nnn itself gains no new dependency).

**CLI (dragon-compatible subset):**

| Flag | Meaning |
|------|---------|
| `(none) FILE...` | Source mode: offer files for dragging out |
| `-t, --target` | Target mode: receive a drop, print paths to stdout |
| `-x, --and-exit` | Exit after the first completed drag or drop |
| `-a, --all` | Offer all files as a single combined drag |
| `-p, --print-path` | Print plain paths instead of `file://` URIs |
| `-T, --on-top` | Keep the helper window always on top |
| `-I, --stdin` | Read file list from stdin (NUL or newline) |

**Wayland:** The helper works on most Wayland desktops via XWayland (the compositor bridges XDND to native Wayland). For pure-Wayland setups, it falls back to `ripdrag` (GTK4).

### Approach D — kitty OSC-72 Terminal Protocol (in-process, no helper)

An in-process escape-code protocol. nnn writes OSC 72 escape sequences to the terminal, and **kitty** (≥ 0.47.1) performs the real window-system drag on its behalf. **Zero helper, zero libX11, and it works over SSH and inside tmux.**

**Protocol overview (drag-OUT direction):**

```
EnableDrag (once at startup) → user mouse-drags on terminal
→ kitty sends inbound OFFER → nnn answers agree + present + start
→ kitty performs the OS drag
```

The protocol is **mouse-gesture-driven and bidirectional**: nnn declares itself a drag source once; the **user's mouse gesture** triggers the drag; the terminal sends nnn an inbound offer that nnn must answer.

**Prerequisites:**

- **kitty ≥ 0.47.1** (Ghostty has accepted the protocol).
- **Opt-in** via `NNN_DND_OSC72=1` (because enabling it changes the terminal's mouse-gesture handling).
- Inside **tmux**: additionally requires `set -g allow-passthrough on` (tmux 3.3+).
- **Debug mode:** `NNN_DND_DEBUG=/tmp/nnn-dnd.log` (or `=1` for the default log path) traces all inbound/outbound OSC-72 events to a file without corrupting the curses screen.

**Five bugs discovered and fixed during implementation (see [docs/nnn_Problems_And_Solutions.md](docs/nnn_Problems_And_Solutions.md) Problems 2–7):**

| # | Mistake | Effect | Fix |
|---|---------|--------|-----|
| 1 | Emitted drag on keypress instead of mouse gesture | Garbage + EPERM | Reimplemented as gesture-driven (bidirectional) |
| 2 | Wrote agree/present/start as separate writes | Interleaved bytes corrupt the drag build | Single atomic write |
| 3 | Emitted padded base64 (`=`) | kitty rejects padding; "error decoding base64" | Unpadded base64 |
| 4 | Advertised real hostname as machine-id | kitty treats drag as remote, asks for file contents → stall | Empty machine-id (local) |
| 5 | No drag icon | No visual feedback | Text icon label |

**Additional fixes for robustness:**

- **Post-subprocess resync** — opening a file runs a curses-suspending subprocess that makes kitty forget nnn is a drag source; a `g_dnd_resync` flag re-sends EnableDrag on return.
- **tmux pane-border protection** — dragging across a tmux pane boundary would resize panes; during an in-flight drag, tmux mouse is temporarily toggled off and restored on drag-end.
- **Self-drop prevention** — dropping a drag back onto nnn's own pane is a no-op (suppressed click, consumed bare `]` OSC-72 events).
- **Window focus** — on drop, emits BEL (urgency hint, always works) + attempts `kitten @ focus-window` (if kitty remote control is enabled).

### Drop-IN (Files INTO nnn from GUI apps)

Two capture paths converge on one copy/move handler:

| Mechanism | Works in tmux? | Notes |
|-----------|---------------|-------|
| **Native OSC-72** (`EnableDrop`) | No | tmux does not route inbound drop events to the pane; used in bare kitty only |
| **Bracketed-paste capture** (always active) | Yes | kitty wraps the drop-paste in `ESC[200~`…`ESC[201~`; tmux forwards it. Portable. |

On drop, nnn parses paths (handles `file://` URI percent-decoding, newline/space separated, quotes, backslash escapes), keeps only existing paths, asks **c**opy or **m**ove, then reuses the exact NUL-separated `xargs -0 cp/mv ... .` command that selection copy uses. A paste with **no** real files is silently swallowed — plain text pastes no longer leak as keystrokes.

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `NNN_DND_OSC72=1` | Enable kitty OSC-72 drag-and-drop (opt-in; changes terminal mouse gestures) |
| `NNN_DND_DEBUG=1` or `NNN_DND_DEBUG=/path/to/log` | Log all inbound/outbound OSC-72 events for diagnosis |
| `O_DND=1` (build flag) | Build the `nnn-dnd` XDND helper alongside nnn |

---

## ◈ Unlimited Cross-Instance Directory History

An **append-only shared visit log** that records every directory change across **all 8 contexts (tabs), both tmux panes, and across sessions**. Navigable via an fzf picker plugin.

### How It Works

- **One C hook** at the `begin:` choke point in `browse()` appends a TSV record (`timestamp | instance_id | session | ctx | path`) to `~/.config/nnn/.dirhistory` on every real directory change.
- **All nnn instances** write to the **same file** → the history is global across panes and restarts.
- **Lockless append** (single `write()` in `O_APPEND` mode, atomic for records < `PIPE_BUF`).

### The Picker Plugin — `nnn-history` (bound to `;h`)

1. Reads the shared log, deduplicates by path (keeping newest visit).
2. Labels entries by source: `[live L ctx3]` / `[past R ctx1]`.
3. Shows newest at the bottom (fzf), lets the user filter by pane/session/context.
4. On selection, writes `0c<path>` to `$NNN_PIPE` → instance jumps there.

### Compaction

Run `nnn-history --compact` (opportunistically when the file exceeds a threshold): takes `flock` on `.dirhistory.lock`, keeps the last N unique paths, atomic `rename()`.

### Build and Config

- **Build:** `make O_HIST=1` enables the visit-recorder C hook.
- **Env:** `NNN_HIST=global` turns it on; unset = off (upstream behaviour).
- **Plugin binding:** add `;h:nnn-history` to `NNN_PLUG`.
- **Path:** `~/.config/nnn/.dirhistory` (file mode `0600` for privacy).

For the full design, see [docs/Brainstorm_nnn_Support_Unlimited_History.md](docs/Brainstorm_nnn_Support_Unlimited_History.md).

---

## ◈ CWD Guard — Shell Protection Against the Trash Displacement Trap

A **shell prompt hook** that detects when your terminal's real working directory has been silently moved (e.g., into the Trash after an nnn delete and re-create) and auto-repairs it.

### The Problem (Unix quirk, not an nnn bug)

A shell's "current directory" is an **open handle to a directory inode**, not a path string. When `NNN_TRASH=1` routes deletes through `trash-put`, the directory is **moved** (renamed) into the Trash. On the same filesystem this preserves the inode — and the terminal's CWD **silently follows it into the Trash**. Re-creating the directory at the original path creates a new inode; the old terminal is still attached to the trashed inode, so everything it writes lands in the Trash. The bash/fish builtin `pwd -P` does not call `getcwd()` when the `$PWD` string names a valid directory — it looks correct but is wrong.

### The Fix

A guard that runs **before every prompt**, compares the inode the shell is really in against the inode `$PWD` names, and on mismatch **warns** and (by default) **re-attaches** to `$PWD` via `cd "$PWD"`.

**Installed:**

| File | Shell | Role |
|------|-------|------|
| `~/.config/fish/conf.d/nnn_cwd_guard.fish` | fish | Primary fix, runs on `fish_prompt` event |
| `~/.dotfiles/nnn/nnn_config.sh` (appended block) | bash | Via `PROMPT_COMMAND`; no-op when imported through `bass` |

**Toggles:**

| Variable | Effect |
|----------|--------|
| `NNN_CWD_GUARD=0` | Disable the guard entirely |
| `NNN_CWD_GUARD_AUTOCD=0` | Warn only — do NOT auto re-attach |
| (unset / default) | Enabled, with auto re-attach |

The guard uses `stat -c '%d:%i'` inode comparison with `stat -L` on `$PWD` (symlink-safe), so normal navigation and symlinked directories never trigger it. It only acts on a genuine inode mismatch. For the full investigation, see [docs/nnn_Problems_And_Solutions.md](docs/nnn_Problems_And_Solutions.md) Problem 1.

---

## ◈ Build Scripts

This fork provides two convenience build scripts in the project root that encode the preferred feature set.

### `build.sh` — Production Build

```sh
make -j$((`nproc`-2)) 0_NERD=1 O_EMOJI=1 O_PCRE=1 O_CTX8=1 O_QSORT=1 \
  O_SSN_ON_CD=1 O_FZ_CPMV=1 O_HIST=1 O_DND=1
```

**What each flag enables:**

| Flag | Feature | What it does |
|------|---------|--------------|
| `0_NERD=1` | Nerdfont icons | File-type icons using Nerd Font glyphs in the terminal. Requires a Nerd Font installed. Mutually exclusive with `O_ICONS` and `O_EMOJI`. |
| `O_EMOJI=1` | Emoji icons | File-type icons using emoji characters. Mutually exclusive with `O_ICONS` and `O_NERD`. |
| `O_PCRE=1` | PCRE regex | Links with PCRE2 for Perl-compatible regex in filters (`/` search). Without it, nnn uses POSIX regex (BRE/ERE). |
| `O_CTX8=1` | 8 contexts | Enables all 8 contexts (tabs/workspaces). Without it, nnn uses 4 contexts. |
| `O_QSORT=1` | Quick sort | Uses Alexey Tourbin's optimized QSORT implementation for faster sorting of large directories. |
| `O_SSN_ON_CD=1` | Session auto-save | Automatically saves the session on every directory change, so nnn always restores to the last state after a crash or restart. |
| `O_FZ_CPMV=1` | FileZilla-style copy/move | Enables conflict-resolution prompts (overwrite/skip/rename) during copy/move via the `cpmv` plugin. |
| `O_HIST=1` | Shared directory history | Enables the visit-recorder C hook — appends every directory change to the shared `.dirhistory` log used by the `nnn-history` plugin. See § Unlimited Cross-Instance Directory History. |
| `O_DND=1` | Drag-and-drop helper | Builds the `nnn-dnd` XDND helper binary alongside nnn. Links `-lX11`. The `NNN_DND_OSC72=1` env var is separate and handled at runtime. |

**Additional parameters:**
- `-j$((\`nproc\`-2))` — parallel build using all but 2 CPU cores (leaves headroom for the desktop).
- `NNN_DND_OSC72=1` is **already compiled in** (always-on code path, no link dependency) — the env var at runtime gates whether the protocol is active; no rebuild needed to toggle it.
- `NNN_DND_DEBUG=1` — enables the DnD debug log output (set to `1` for default path `/tmp/nnn-dnd.log`, or a custom path).

**Prerequisites:**
- **C compiler** (gcc/clang) with `-std=c11` support.
- **libX11** (for `O_DND=1`): `libx11-dev` (Debian/Ubuntu) or `libX11-devel` (Fedora).
- **libpcre2** (for `O_PCRE=1`): `libpcre2-dev` (Debian/Ubuntu) or `pcre2-devel` (Fedora).
- **libreadline** (default, unless `O_NORL=1`): `libreadline-dev`.
- **Nerd Font** (for `O_NERD=1`): e.g., `ttf-firacode-nerd` or `fonts-nerd-fonts`.

### `build_debug.sh` — Debug Build

```sh
make -j$((`nproc`-2)) 0_NERD=1 O_EMOJI=1 O_PCRE=1 O_CTX8=1 O_QSORT=1 \
  O_SSN_ON_CD=1 O_FZ_CPMV=1 O_HIST=1 O_DEBUG=1 -f Makefile_debug
```

**Differences from `build.sh`:**

| Aspect | `build.sh` (production) | `build_debug.sh` (debug) |
|--------|------------------------|--------------------------|
| Makefile | `Makefile` | `Makefile_debug` |
| `O_DEBUG` | not set | `O_DEBUG=1` → `-DDEBUG` + `-g3` |
| `O_DND` | `=1` (builds nnn-dnd) | not set (DnD helper excluded) |
| `NNN_DND_OSC72` | set at build time | not set (add at runtime if needed) |
| Binary size | stripped, optimized (`-O3`) | unstripped, debug symbols (`-g3`), with `-DDEBUG` preprocessor flag |
| Use case | Everyday use, full features | gdb/valgrind debugging, core dumps, development |

**Usage:**
```sh
# Production (full-featured, optimized):
./build.sh

# Debug (with debug symbols, no DnD helper):
./build_debug.sh

# Run with DnD enabled at runtime (either build can do this):
NNN_DND_OSC72=1 ./nnn

# Run with DnD debug tracing:
NNN_DND_OSC72=1 NNN_DND_DEBUG=/tmp/nnn-dnd.log ./nnn

# Run with shared history:
NNN_HIST=global ./nnn
```

**Clean builds:**
```sh
make clean              # Clean the production Makefile
make -f Makefile_debug clean  # Clean the debug Makefile
```

---

## ◈ Dual-Pane tmux Setup

The repo includes scripts for a dual-pane tmux layout (`start_dual_nnn.sh`) that launches two nnn instances side-by-side — `nnn_left` (`-s left`) and `nnn_right` (`-s right`). They share a common `NNN_FIFO` (`/tmp/nnn.fifo`) and `NNN_PLUG` configuration, enabling:

- **Cross-pane directory history** — both panes record to the same `.dirhistory`; the `nnn-history` picker can jump to a directory visited by the other pane.
- **Cross-pane DnD** — OSC-72 drag-out works inside tmux with `allow-passthrough on` (the outbound escapes reach kitty through tmux's DCS passthrough wrapper).

---

## ◈ Problem & Solution Log

A running log of real problems hit while using this nnn setup, with investigations and fixes, is kept in [docs/nnn_Problems_And_Solutions.md](docs/nnn_Problems_And_Solutions.md). Covered issues:

1. **New files silently land inside the Trash** after deleting and re-creating a directory (CWD guard fix)
2. **Native drag-and-drop never produced a drag** (5 protocol-level bugs: keypress-vs-gesture, interleaved writes, padded base64, machine-id, no icon)
3. **Drag stops working after opening a file** (EnableDrag lost on curses suspend)
4. **Dragging across tmux pane border resizes panes** (mouse grab conflict)
5. **Dropping files INTO nnn typed strange key sequences** (bracketed paste + native drop paths)
6. **Dropped file doesn't bring nnn to front** (pty cannot focus own window; BEL + kitten fallback)
7. **Self-drop opened the `>>>` prompt** (bare `]` consumed by ncurses before OSC-72 parser)
8. **"Too many open files" on fresh start** (exhausted `fs.inotify.max_user_instances`, not fd limit)

---

## ◈ Design Documents

- [docs/Brainstorm_nnn_Support_Drag_and_Drop.md](docs/Brainstorm_nnn_Support_Drag_and_Drop.md) — Full brainstorm, protocol deep-dives, XDND state machines, OSC-72 implementation guide.
- [docs/Brainstorm_nnn_Support_Unlimited_History.md](docs/Brainstorm_nnn_Support_Unlimited_History.md) — Shared visit log design, plugin architecture, compaction strategy.
- [docs/Brainstorm_nnn_Update.md](docs/Brainstorm_nnn_Update.md) — General fork update notes.
- [docs/nnn_Problems_And_Solutions.md](docs/nnn_Problems_And_Solutions.md) — Running log of real problems and their fixes.
