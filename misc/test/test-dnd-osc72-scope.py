#!/usr/bin/env python3
"""
Regression test for the scope of nnn's kitty OSC-72 drag source inside tmux
(docs/nnn_Problems_And_Solutions.md Problem 15).

kitty keeps ONE drag-source flag per kitty window (w->drag_source.can_offer,
kitty/dnd.c). Inside tmux that window is the whole tmux client, so whatever an
nnn pane registers covers every tmux window and pane. This script plays kitty
0.49.2: it drives a tmux client in a pty, tracks the flag from the OSC-72
sequences tmux passes through, and sends a "t=o" gesture offer exactly when
kitty's handle_potential_drag() would.

What the fake reproduces from kitty 0.49.2 (kitty/mouse.c, kitty/dnd.c):
- every left press arms a potential drag; kitty decides ONCE per gesture, at
  the first pointer sample more than drag_threshold (5 px) from the press,
  which can still be inside the pressed cell; it offers only if the flag is
  set at that moment;
- motion is reported to tmux only when the pointer changes cell, and nothing
  is reported while tmux has mouse reporting off (nnn's drag-time grab);
- a drag dropped outside kitty swallows the release; t=o:x=2 during a drag
  frees it and suppresses the t=e:x=4 that would end it.

Isolation: a private tmux server (-L socket, -f config), nnn with HOME, its
selection file and its debug log in a scratch directory. A live session is
never touched. The copy-mode keys the leak depends on are mirrored from the
owner's tmux config, with xdg-open and xsel replaced by a log file.

Usage:  misc/test/test-dnd-osc72-scope.py               # tests ./nnn
        misc/test/test-dnd-osc72-scope.py --nnn PATH    # another build
        misc/test/test-dnd-osc72-scope.py --keep        # keep the scratch dir
        misc/test/test-dnd-osc72-scope.py --debug       # tmux -vv logs, pane states
"""
import argparse
import base64
import fcntl
import math
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

RUN_LIMIT_S = 300       # whole-run ceiling (normal run: about 75 s)
ESC, ST = '\x1b', '\x1b\\'
OSC72 = re.compile(rb'\x1b\]72;([^\x07\x1b]*)(?:\x1b\\|\x07)')
MODE = re.compile(rb'\x1b\[\?([\d;]+)([hl])')
QUERIES = [  # what tmux asks the outer terminal at attach, and a kitty-like answer
    (b'\x1b[c', '\x1b[?62;22;52c'),
    (b'\x1b[>c', '\x1b[>1;4000;29c'),
    (b'\x1b]10;?', '\x1b]10;rgb:dddd/dddd/dddd\x1b\\'),
    (b'\x1b]11;?', '\x1b]11;rgb:0000/0000/0000\x1b\\'),
]
T0 = time.monotonic()


def note(msg):
    print('[%5.1fs] %s' % (time.monotonic() - T0, msg), flush=True)


class FakeKitty:
    """The parts of kitty 0.49.2 that decide whether a drag offer is sent."""
    CELL_W, CELL_H = 18, 36     # cell size on the owner's screen (X=1152 at x=64)
    DRAG_THRESHOLD = 5          # px, kitty's default drag_threshold

    def __init__(self, argv, rows, cols, rawlog):
        self.can_offer = False
        self.offers = []        # (time, col, row) offers sent to the app
        self.app_osc = []       # (time, body) OSC-72 received from the app
        self.drag_state = None  # None | 'building' | 'started' | 'freed' | 'silent'
        self.start_reply = 'OK' # answer to t=P:x=-1: 'OK', 'EPERM' or 'SILENT'
        self.uri_b64 = ''
        self.press_px = None
        self.ptr = (0, 0)
        self.cell = (0, 0)
        self.modes = set()      # mouse reporting modes tmux enabled (1000, 1002, 1003)
        self.tail = b''
        self.buf = b''
        self.rawlog = open(rawlog, 'wb')
        pid, fd = pty.fork()
        if pid == 0:
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))
            os.environ.pop('TMUX', None)
            os.environ['TERM'] = 'xterm-kitty'
            os.execvp(argv[0], argv)
        self.pid, self.fd = pid, fd

    @property
    def reporting(self):
        return bool(self.modes)

    def write(self, s):
        os.write(self.fd, s.encode())

    def pump(self, secs, until=None):
        """Read and act on tmux's output for secs, or until until() holds."""
        end = time.monotonic() + secs
        while True:
            left = end - time.monotonic()
            if left <= 0:
                return
            r, _, _ = select.select([self.fd], [], [], left)
            if not r:
                return
            try:
                data = os.read(self.fd, 65536)
            except OSError:
                return
            self.rawlog.write(data)
            self._modes(data)
            for q, reply in QUERIES:
                if q in data:
                    self.write(reply)
            self.buf += data
            self._parse()
            if until and until():
                return

    def pump_until(self, pred, secs):
        if not pred():
            self.pump(secs, pred)
        return pred()

    def _modes(self, data):
        chunk = self.tail + data
        for m in MODE.finditer(chunk):
            if m.end() <= len(self.tail):
                continue
            for n in m.group(1).split(b';'):
                if n in (b'1000', b'1002', b'1003'):
                    if m.group(2) == b'h':
                        self.modes.add(n)
                    else:
                        self.modes.discard(n)
        self.tail = chunk[-16:]

    def _parse(self):
        pos = 0
        for m in OSC72.finditer(self.buf):
            self._on_app_osc(m.group(1).decode('latin-1'))
            pos = m.end()
        rest = self.buf[pos:]
        k = rest.rfind(b'\x1b]72;')
        self.buf = rest[k:] if k >= 0 else b''

    def _on_app_osc(self, body):
        self.app_osc.append((time.monotonic(), body))
        meta, _, payload = body.partition(';')
        kv = dict(p.split('=', 1) for p in meta.split(':') if '=' in p)
        t = kv.get('t')
        if t == 'o':
            if 'o' in kv:                   # agree-drag
                self.drag_state = 'building'
                self.uri_b64 = ''
            elif kv.get('x') == '1':        # EnableDrag
                self.can_offer = True
            elif kv.get('x') == '2':        # stop offering: drag_free_offer()
                self.can_offer = False
                if self.drag_state == 'started':
                    self.drag_state = 'freed'   # the OS drag goes on, unreported
                else:
                    self.drag_state = None
        elif t == 'p' and kv.get('x') == '0':
            self.uri_b64 += payload
        elif t == 'P' and kv.get('x') == '-1' and self.drag_state == 'building':
            if self.start_reply == 'EPERM':
                self.drag_state = None
                self.write(ESC + ']72;t=E;EPERM' + ST)
            else:
                self.drag_state = 'started' if self.start_reply == 'OK' else 'silent'
                self.write(ESC + ']72;t=E:m=0;OK' + ST)

    def px(self, col, row):
        return (col * self.CELL_W + self.CELL_W // 2, row * self.CELL_H + self.CELL_H // 2)

    def _mouse(self, code, col, row, final):
        if self.reporting:
            self.write('%s[<%d;%d;%d%s' % (ESC, code, col + 1, row + 1, final))

    def press(self, col, row):
        self.ptr = self.px(col, row)
        self.cell = (col, row)
        self.press_px = self.ptr    # armed on EVERY left press
        self._mouse(0, col, row, 'M')

    def move(self, col, row):
        self.move_px(*self.px(col, row))

    def nudge(self, dx):
        """Move the pointer dx pixels right, without leaving the cell if dx is small."""
        self.move_px(self.ptr[0] + dx, self.ptr[1])

    def move_px(self, x, y):
        self.ptr = (x, y)
        cell = (x // self.CELL_W, y // self.CELL_H)
        if cell != self.cell:
            self.cell = cell
            if self.drag_state not in ('started', 'freed'):   # an OS drag owns the pointer
                self._mouse(32, cell[0], cell[1], 'M')
        if self.press_px is not None and math.dist((x, y), self.press_px) > self.DRAG_THRESHOLD:
            self.press_px = None    # decided once per gesture
            if self.can_offer:
                self.offers.append((time.monotonic(), cell[0], cell[1]))
                self.write('%s]72;t=o:x=%d:y=%d:X=%d:Y=%d%s' % (ESC, cell[0], cell[1], x, y, ST))

    def release(self, col, row):
        self.press_px = None
        if self.drag_state == 'started':    # dropped outside kitty: release swallowed
            self.drag_state = None
            self.write(ESC + ']72;t=e:x=4:y=0' + ST)
        elif self.drag_state == 'freed':    # freed mid-drag: swallowed and never reported
            self.drag_state = None
        else:
            if self.drag_state == 'silent':
                self.drag_state = None
            self._mouse(0, col, row, 'm')

    def drag(self, col, row, cols, gap=0.06, step=0.016):
        """A human-paced left drag: press, pause, then move cell by cell."""
        self.press(col, row)
        self.pump(gap)
        for c in cols:
            self.move(c, row)
            self.pump(step)

    def osc_since(self, t):
        return [b for ts, b in self.app_osc if ts >= t]

    def close(self):
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.kill(self.pid, sig)
                os.waitpid(self.pid, 0)
                break
            except OSError:
                pass
        os.close(self.fd)
        self.rawlog.close()


class Run:
    def __init__(self, nnn, scratch, debug=False):
        self.nnn, self.S, self.debug = nnn, scratch, debug
        self.tmuxbin = shutil.which('tmux')
        self.sock = 'nnn-dnd-scope-%d' % os.getpid()
        self.env = dict(os.environ)
        self.env.pop('TMUX', None)
        self.passed = self.failed = 0
        self.k = None

    def tmux(self, *a):
        return subprocess.run([self.tmuxbin, '-L', self.sock] + list(a), capture_output=True,
                              text=True, env=self.env, timeout=10).stdout

    def chk(self, label, ok, detail=''):
        if ok:
            self.passed += 1
            print('  PASS  %-60s %s' % (label, detail))
        else:
            self.failed += 1
            print('  FAIL  %-60s %s' % (label, detail))

    def nnn_cmd(self, flags='', env=''):
        return ("exec env -i HOME=%s/home PATH=/usr/local/bin:/usr/bin:/bin LANG=en_US.UTF-8 "
                "TERM=\"$TERM\" TMUX=\"$TMUX\" TMUX_PANE=\"$TMUX_PANE\" NNN_DND_OSC72=1 "
                "NNN_DND_DEBUG=%s/dnd.log %s %s %s %s/files"
                % (self.S, self.S, env, self.nnn, flags, self.S))

    def setup(self):
        S = self.S
        os.makedirs(S + '/home', exist_ok=True)
        os.makedirs(S + '/files', exist_ok=True)
        for n in ('a.txt', 'b.txt', 'c.txt'):
            with open(S + '/files/' + n, 'w') as f:
                f.write(n + '\n')
        with open(S + '/opener.sh', 'w') as f:
            f.write('#!/bin/sh\nsleep 1.5\n')
        os.chmod(S + '/opener.sh', 0o755)
        with open(S + '/tmux.conf', 'w') as f:
            f.write('set -g base-index 1\nsetw -g pane-base-index 1\n'
                    'set -g default-shell /bin/sh\nset -g mouse on\nset -s escape-time 10\n'
                    'set -s focus-events on\nset -g mode-keys vi\nset -g allow-passthrough on\n'
                    # the owner's 'o' runs xdg-open on the selection; MouseDragEnd1Pane runs xsel
                    'bind -T copy-mode-vi o send-keys -X copy-pipe-and-cancel "cat >> %s/o-binding.log"\n'
                    'bind -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel '
                    '"cat >> %s/dragend.log"\n' % (S, S))
        # window 1: nnn L | nnn R | shell (like the dual-nnn window); window 2: shell
        vv = ['-vv'] if self.debug else []
        if self.debug:
            os.chdir(S)             # tmux -vv writes its logs to the cwd
        self.tmux(*(vv + ['-f', S + '/tmux.conf', 'new-session', '-d', '-s', 't', '-x', '160',
                          '-y', '40', '-n', 'dual', 'sleep 100000']))
        self.tmux('split-window', '-h', '-t', 't:1', 'sleep 100000')
        self.tmux('split-window', '-h', '-t', 't:1.2', '/bin/cat -v')
        self.tmux('select-layout', '-t', 't:1', 'even-horizontal')
        self.tmux('new-window', '-d', '-t', 't:2', '-n', 'other', '/bin/cat -v')
        self.k = FakeKitty([self.tmuxbin, '-L', self.sock, 'attach', '-t', 't:1'], 40, 160,
                           S + '/client.raw')
        self.k.pump(1.0)

    def start_nnn(self, pane, flags='', env=''):
        """Start nnn in a pane of the window on show, and wait for its list."""
        self.tmux('select-window', '-t', pane.rsplit('.', 1)[0])
        self.tmux('respawn-pane', '-k', '-t', pane, "sh -c '%s'" % self.nnn_cmd(flags, env))
        self.k.pump_until(lambda: 'a.txt' in self.tmux('capture-pane', '-p', '-t', pane), 5)
        self.k.pump(0.5)

    def geom(self, pane):
        x, y, w, h = map(int, self.tmux('display', '-p', '-t', pane,
                                        '#{pane_left} #{pane_top} #{pane_width} #{pane_height}').split())
        return x, y, w, h

    def row_of(self, pane, name):
        x, y, _, _ = self.geom(pane)
        for i, line in enumerate(self.tmux('capture-pane', '-p', '-t', pane).splitlines()):
            if name in line:
                return x + line.index(name) + 1, y + i
        raise RuntimeError('%s not shown in %s' % (name, pane))

    def bottom(self, pane):
        """The last three rows of a pane: where nnn draws its prompts."""
        return '\n'.join(self.tmux('capture-pane', '-p', '-t', pane).split('\n')[-4:])

    def garbage(self, pane):
        text = self.tmux('capture-pane', '-p', '-t', pane)
        return [l for l in text.splitlines() if re.search(r'72;|t=o|:x=\d|:X=\d', l)]

    def probe(self, pane):
        """A text-selection drag in pane; returns the number of offers kitty sent."""
        x, y, _, _ = self.geom(pane)
        n0 = len(self.k.offers)
        self.k.drag(x + 2, y + 6, range(x + 3, x + 9))
        self.k.release(x + 8, y + 6)
        self.k.pump(0.4)
        return len(self.k.offers) - n0

    def log(self):
        p = self.S + '/dnd.log'
        return open(p).read().splitlines() if os.path.exists(p) else []

    def logged(self, mark, text):
        return any(text in line for line in self.log()[mark:])

    def state(self, tag):
        if not self.debug:
            return
        print('    [%s] %s' % (tag, self.tmux('list-panes', '-s', '-F',
              '#{window_index}.#{pane_index}:act=#{pane_active}/#{window_active}:mode=#{pane_in_mode}:cmd=#{pane_current_command}').split()))
        print('    [%s] mouse=%s marker=%r can_offer=%s reporting=%s' % (
              tag, self.tmux('show', '-gv', 'mouse').strip(),
              self.tmux('show', '-gv', '@nnn_dnd_mouse').strip(), self.k.can_offer, self.k.reporting))

    def logfile(self, name):
        p = self.S + '/' + name
        return open(p).read() if os.path.exists(p) else None

    def teardown(self):
        if self.k:
            self.k.close()
        try:
            self.tmux('kill-server')
        except Exception:
            pass
        sock = os.path.join(os.environ.get('TMUX_TMPDIR', '/tmp'), 'tmux-%d' % os.getuid(), self.sock)
        try:
            os.unlink(sock)         # tmux leaves the socket file behind
        except OSError:
            pass


def scenarios(r):
    k = r.k
    note('starting nnn L (t:1.1) and nnn R (t:1.2) with NNN_DND_OSC72=1')
    t = time.monotonic()
    r.start_nnn('t:1.1')
    r.start_nnn('t:1.2')
    print('  startup OSC-72 from nnn: %s' % k.osc_since(t))
    r.chk('T0 startup leaves kitty\'s drag source OFF (tmux)', not k.can_offer,
          'can_offer=%s' % k.can_offer)

    note('T1: text-selection drag in ANOTHER tmux window (the reported bug)')
    r.tmux('select-window', '-t', 't:2')
    k.pump(0.4)
    n0 = len(k.offers)
    k.drag(2, 5, range(3, 9))
    k.pump(0.2)
    in_mode = r.tmux('display', '-p', '-t', 't:2', '#{pane_in_mode}').strip()
    k.release(8, 5)
    k.pump(0.4)
    k.drag(20, 8, [21])             # "left-click again", with a few px of jitter
    k.release(21, 8)
    k.pump(0.4)
    r.chk('T1 no gesture offer sent for a drag outside nnn', len(k.offers) == n0,
          'offers=%d' % (len(k.offers) - n0))
    r.chk('T1 copy mode selected text normally', in_mode == '1' and r.logfile('dragend.log') is not None,
          'pane_in_mode=%s dragend.log=%r' % (in_mode, r.logfile('dragend.log')))
    r.chk('T1 no OSC-72 text typed into the pane', not r.garbage('t:2'), repr(r.garbage('t:2')))
    r.chk('T1 copy-mode "o" (xdg-open) never fired', r.logfile('o-binding.log') is None,
          'o-binding.log=%r' % r.logfile('o-binding.log'))

    note('T2: drag in the shell pane of the dual-nnn window')
    r.tmux('select-window', '-t', 't:1')
    k.pump(0.4)
    offers = r.probe('t:1.3')
    r.chk('T2 no gesture offer for a drag in a non-nnn pane', offers == 0, 'offers=%d' % offers)
    r.chk('T2 no OSC-72 text typed into the pane', not r.garbage('t:1.3'), repr(r.garbage('t:1.3')))

    def drag_out(label, pane, name, what):
        note('%s: %s' % (label, what))
        k.pump_until(lambda: k.reporting, 2)
        col, row = r.row_of(pane, name)
        t = time.monotonic()
        n0 = len(k.offers)
        k.uri_b64 = ''
        k.drag(col, row, range(col + 1, col + 4))
        k.pump_until(lambda: k.drag_state == 'started', 1)
        started = k.drag_state == 'started'
        uri = base64.b64decode(k.uri_b64 + '=' * (-len(k.uri_b64) % 4)).decode(errors='replace')
        k.release(col + 3, row)
        k.pump_until(lambda: not k.can_offer, 2)
        k.pump(0.3)
        seq = [b.split(';')[0] for b in k.osc_since(t)]
        k.pump(0.7)                 # let the self-drop guard window (600 ms) pass
        r.state(label)
        return started, uri.strip(), seq, len(k.offers) - n0

    for label, pane, name, what in (
            ('T3', 't:1.1', 'a.txt', 'drag a.txt out of nnn L'),
            ('T3b', 't:1.1', 'c.txt', 'drag again from nnn L (first press after a native drag)'),
            ('T4b', 't:1.2', 'b.txt', None)):
        if label == 'T4b':
            # First press after a native drag, in the OTHER pane: tmux treats it
            # as the end of the old drag, so it does not select nnn R, and the
            # offer reaches nnn L, which did not arm this gesture.
            started, uri, seq, offers = drag_out('T4a', 't:1.2', 'b.txt',
                                                 'drag from nnn R right after a drag from nnn L')
            r.chk('T4a nnn L refuses an offer for a gesture it did not arm',
                  offers == 1 and not started and 't=o:o=3' not in seq, 'osc=%s' % seq)
            r.chk('T4a no file was dragged (never the wrong one)', uri == '', repr(uri))
            r.chk('T4a kitty\'s drag source is off afterwards', not k.can_offer,
                  'can_offer=%s' % k.can_offer)
            what = 'retry the drag from nnn R'
        started, uri, seq, offers = drag_out(label, pane, name, what)
        r.chk('%s armed by the press, one offer sent' % label, offers == 1, 'osc=%s' % seq[:3])
        r.chk('%s nnn answered and the drag started' % label, started, 'drag_state=%s' % k.drag_state)
        r.chk('%s the dragged URI is the pressed file' % label, uri.endswith('/files/' + name),
              repr(uri))
        r.chk('%s disarmed after the drop (t=o:x=2)' % label, not k.can_offer and 't=o:x=2' in seq,
              'can_offer=%s' % k.can_offer)
    mouse = r.tmux('show', '-gv', 'mouse').strip()
    marker = r.tmux('show', '-gv', '@nnn_dnd_mouse').strip()
    r.chk('T3/T4 tmux mouse grab restored after the drags', mouse == 'on' and not marker,
          'mouse=%s marker=%r' % (mouse, marker))

    note('T5: plain click on a file (press + release, no motion)')
    col, row = r.row_of('t:1.1', 'c.txt')
    t = time.monotonic()
    n0 = len(k.offers)
    k.press(col, row)
    armed = k.pump_until(lambda: k.can_offer, 1)
    k.pump(0.05)
    k.release(col, row)
    k.pump_until(lambda: not k.can_offer, 1)
    k.pump(0.2)
    r.chk('T5 click arms then disarms, no offer', armed and not k.can_offer and len(k.offers) == n0,
          'osc=%s' % [b.split(';')[0] for b in k.osc_since(t)])

    note('T6: arm latency, press -> t=o:x=1 seen by kitty (20 presses)')
    lat, stale = [], 0
    for i in range(20):
        col, row = r.row_of('t:1.1', ('a.txt', 'b.txt', 'c.txt')[i % 3])
        stale += k.can_offer        # the previous release must have disarmed
        t = time.monotonic()
        k.press(col, row)
        if k.pump_until(lambda: k.can_offer, 1):
            lat.append((time.monotonic() - t) * 1000)
        k.release(col, row)
        k.pump_until(lambda: not k.can_offer, 1)
        k.pump(0.45)                # stay clear of nnn's double-click window
    lat.sort()
    r.chk('T6 every press armed, every release disarmed', len(lat) == 20 and not stale and not k.can_offer,
          'armed %d/20, stale before a press %d' % (len(lat), stale))
    if lat:
        print('        latency ms: min %.2f  median %.2f  max %.2f' % (lat[0], lat[len(lat) // 2], lat[-1]))

    def flick():
        """Press on a.txt and move 6 px at once: kitty decides before the arm
        lands, so no drag. Then leave the pane and release over the shell pane,
        where tmux does not hand the release to nnn."""
        col, row = r.row_of('t:1.1', 'a.txt')
        x3, _, _, _ = r.geom('t:1.3')
        n0 = len(k.offers)
        k.press(col, row)
        k.nudge(6)                  # same instant, still inside the cell
        k.pump(0.2)
        k.move(x3 + 2, row)
        k.release(x3 + 2, row)
        k.pump(0.3)
        return len(k.offers) - n0

    note('T7: lost race (a flick out of the pane), then nothing')
    mark = len(r.log())
    offers = flick()
    stale = k.can_offer
    r.chk('T7 no offer when the race is lost (the drag does not start)', offers == 0, 'offers=%d' % offers)
    cleared = k.pump_until(lambda: not k.can_offer, 4.5)
    r.chk('T7 the arm left by the flick ends by itself', stale and cleared
          and r.logged(mark, 'disarm: no release (timeout)'),
          'stale after the flick=%s, cleared=%s' % (stale, cleared))
    offers = r.probe('t:1.3')
    r.chk('T7 a later text drag in the shell pane is not an offer', offers == 0, 'offers=%d' % offers)

    note('T7b: lost race, then a key in nnn')
    mark = len(r.log())
    flick()
    stale = k.can_offer
    k.write('j')
    k.pump_until(lambda: not k.can_offer, 1)
    r.chk('T7b a key in nnn ends the stale arm at once', stale and not k.can_offer
          and r.logged(mark, 'disarm: key'), 'stale=%s can_offer=%s' % (stale, k.can_offer))

    note('T10: presses outside the list do not arm')
    x, y, _, _ = r.geom('t:1.1')
    col, row = r.row_of('t:1.1', 'c.txt')
    t = time.monotonic()
    for cx, cy in ((x, y), (col, row + 1)):     # header row; first blank row below c.txt
        k.press(cx, cy)
        k.pump(0.08)
        k.release(cx, cy)
        k.pump(0.3)
    sent = [b for b in k.osc_since(t) if b.startswith('t=o:x=1')]
    r.chk('T10 header row and blank row do not arm', not sent, 'osc=%s' % sent)
    n0 = len(k.offers)
    k.drag(col, row + 1, range(col + 1, col + 4))
    k.release(col + 3, row + 1)
    k.pump(0.4)
    r.chk('T10 a drag from a blank row is not an offer', len(k.offers) == n0 and not k.can_offer,
          'offers=%d' % (len(k.offers) - n0))

    note('T11: kitty refuses to start the drag (t=E;EPERM)')
    mark = len(r.log())
    k.start_reply = 'EPERM'
    col, row = r.row_of('t:1.1', 'b.txt')
    k.drag(col, row, range(col + 1, col + 4))
    k.pump(0.3)
    k.release(col + 3, row)
    k.pump(0.4)
    k.start_reply = 'OK'
    r.chk('T11 a refused drag disarms', not k.can_offer and r.logged(mark, 'disarm: drag refused'),
          'can_offer=%s' % k.can_offer)
    k.pump(0.7)
    # kitty refused 1 ms after the answer: the grab and its release ran back
    # to back, and a release that overtook the grab stranded tmux's mouse
    mouse = r.tmux('show', '-gv', 'mouse').strip()
    marker = r.tmux('show', '-gv', '@nnn_dnd_mouse').strip()
    r.chk('T11 the tmux mouse grab is released, not stranded', mouse == 'on' and not marker,
          'mouse=%s marker=%r' % (mouse, marker))

    note('T12: a second offer right after a drop (self-drop guard) is ignored')
    k.pump_until(lambda: k.reporting, 2)
    col, row = r.row_of('t:1.1', 'a.txt')
    k.drag(col, row, range(col + 1, col + 4))
    k.pump_until(lambda: k.drag_state == 'started', 1)
    k.release(col + 3, row)
    k.pump_until(lambda: k.reporting and not k.can_offer, 1)
    mark = len(r.log())
    col, row = r.row_of('t:1.1', 'b.txt')
    k.drag(col, row, range(col + 1, col + 4), gap=0.03)
    k.pump(0.3)
    k.release(col + 3, row)
    k.pump(0.4)
    r.chk('T12 an offer inside the 600 ms guard disarms', not k.can_offer
          and r.logged(mark, 'disarm: offer ignored'), 'can_offer=%s' % k.can_offer)
    k.pump(0.7)

    note('T13: kitty accepts the drag, never runs it, never reports its end')
    mark = len(r.log())
    k.start_reply = 'SILENT'
    col, row = r.row_of('t:1.1', 'c.txt')
    k.drag(col, row, range(col + 1, col + 4))
    k.pump(0.3)
    # The release still reaches nnn: with tmux's mouse off, tmux keeps the
    # mouse mode the ACTIVE pane asked for (1000) and forwards it there.
    k.release(col + 3, row)
    k.pump_until(lambda: not k.can_offer, 1)
    k.pump(0.3)
    k.start_reply = 'OK'
    mouse = r.tmux('show', '-gv', 'mouse').strip()
    marker = r.tmux('show', '-gv', '@nnn_dnd_mouse').strip()
    r.chk('T13 the release drops the dead drag and disarms', not k.can_offer
          and r.logged(mark, 'drag never ended'), 'can_offer=%s' % k.can_offer)
    r.chk('T13 the tmux mouse grab is released with it', mouse == 'on' and not marker,
          'mouse=%s marker=%r' % (mouse, marker))
    offers = r.probe('t:1.3')
    r.chk('T13 a later text drag in the shell pane is not an offer', offers == 0, 'offers=%d' % offers)

    for label, key, what in (('T14', 't', 'the sort prompt (get_input)'),
                             ('T15', '/', 'the filter prompt (filterentries)')):
        note('%s: a release that arrives while %s waits' % (label, what))
        col, row = r.row_of('t:1.1', 'b.txt')
        k.press(col, row)
        k.pump(0.1)
        k.write(key)
        k.pump(0.4)
        before = r.bottom('t:1.1')
        k.release(col, row)
        k.pump(0.4)
        after = r.bottom('t:1.1')
        k.write(ESC)
        k.pump(0.5)
        r.chk('%s the prompt is still open after the release' % label,
              before.strip() != '' and before == after and not k.can_offer,
              'changed=%s can_offer=%s' % (before != after, k.can_offer))

    note('T16: a subprocess started by a double-click runs with the drag source off')
    r.start_nnn('t:2.1', flags='-c', env='NNN_OPENER=%s/opener.sh' % r.S)
    mark = len(r.log())
    col, row = r.row_of('t:2.1', 'a.txt')
    k.press(col, row)
    k.pump(0.04)
    k.release(col, row)
    k.pump(0.08)
    k.press(col, row)               # second click: SEL_OPEN, the CLI opener sleeps 1.5 s
    k.pump(0.04)
    k.release(col, row)
    k.pump(0.6)
    during = k.can_offer
    k.pump(1.6)
    r.chk('T16 off while the opener runs, and after nnn resumes', not during and not k.can_offer
          and r.logged(mark, 'disarm: subprocess'),
          'during=%s after=%s' % (during, k.can_offer))

    note('T8: a new nnn clears a drag source left on by an older or crashed nnn')
    r.tmux('select-window', '-t', 't:1')
    k.pump(0.3)
    mark = len(r.log())
    k.can_offer = True              # what an old binary's startup EnableDrag leaves set
    r.start_nnn('t:1.2')
    cleared = k.pump_until(lambda: not k.can_offer, 3)
    r.chk('T8 a new nnn turns a leftover drag source off', cleared
          and r.logged(mark, 'cleared a leftover drag source'), 'can_offer=%s' % k.can_offer)

    note('T8b: but not while another nnn has a drag in flight')
    r.tmux('set', '-g', '@nnn_dnd_mouse', '%d.1:on' % os.getpid())   # a live owner
    k.can_offer = True
    r.start_nnn('t:1.2')
    k.pump(2.5)
    kept = k.can_offer
    r.tmux('set', '-gu', '@nnn_dnd_mouse')
    r.chk('T8b the clear is skipped while a drag is in flight', kept, 'can_offer=%s' % kept)
    col, row = r.row_of('t:1.1', 'a.txt')
    k.press(col, row)               # a click in nnn ends any leftover
    k.pump(0.08)
    k.release(col, row)
    k.pump_until(lambda: not k.can_offer, 1)


def bare_kitty(r):
    """Outside tmux nnn owns the kitty window: the registration stays for life."""
    note('T9: bare kitty (no tmux) keeps the always-on registration')
    env = ('env -i HOME=%s/home PATH=/usr/bin:/bin LANG=en_US.UTF-8 TERM=xterm-kitty '
           'NNN_DND_OSC72=1 NNN_DND_DEBUG=%s/dnd-bare.log %s %s/files'
           % (r.S, r.S, r.nnn, r.S)).split()
    k = FakeKitty(env, 30, 100, r.S + '/bare.raw')
    try:
        k.pump_until(lambda: k.can_offer, 5)
        k.pump(0.3)
        seq = [b.split(';')[0] for _, b in k.app_osc]
        r.chk('T9 bare kitty: EnableDrag + EnableDrop at startup',
              k.can_offer and 't=a' in seq, 'osc=%s' % seq)
        k.write('q')
        k.pump_until(lambda: not k.can_offer, 3)
        r.chk('T9 bare kitty: quitting withdraws the drag source', not k.can_offer,
              'can_offer=%s' % k.can_offer)
    finally:
        k.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--nnn', default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  '..', '..', 'nnn'))
    ap.add_argument('--keep', action='store_true', help='keep the scratch directory')
    ap.add_argument('--debug', action='store_true', help='tmux -vv logs and pane state dumps')
    args = ap.parse_args()
    nnn = os.path.abspath(args.nnn)
    if not shutil.which('tmux') or not os.access(nnn, os.X_OK):
        sys.exit('need tmux on PATH and an nnn binary at %s' % nnn)
    signal.signal(signal.SIGALRM, lambda *_: sys.exit('whole-run limit of %ds reached' % RUN_LIMIT_S))
    signal.alarm(RUN_LIMIT_S)
    S = tempfile.mkdtemp(prefix='nnn-dnd-scope.')
    note('nnn=%s scratch=%s' % (nnn, S))
    r = Run(nnn, S, args.debug)
    try:
        r.setup()
        scenarios(r)
    finally:
        r.teardown()
    try:
        bare_kitty(r)
    finally:
        print('==================  PASS=%d  FAIL=%d  ==================' % (r.passed, r.failed))
        if r.failed and os.path.exists(S + '/dnd.log'):
            print('--- last lines of %s/dnd.log:' % S)
            print(''.join(open(S + '/dnd.log').readlines()[-25:]))
        if args.keep or args.debug or r.failed:
            print('scratch kept: %s' % S)
        else:
            shutil.rmtree(S, ignore_errors=True)
    sys.exit(1 if r.failed else 0)


if __name__ == '__main__':
    main()
