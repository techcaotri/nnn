#!/usr/bin/env python3
"""
Directly measure how many fs.inotify instances this UID can still create.

This is the only reliable measurement: the kernel's per-user instance counter is
not exposed anywhere in /proc, and counting `anon_inode:inotify` symlinks in
/proc/*/fd counts DESCRIPTORS, not instances -- descriptors shared through
fork()/dup() point at one instance the kernel charges once, so that count is an
upper bound only. (Dedup by inode does not work either: every anon_inode shares
a single inode from the anon_inodefs superblock.)

So: just ask the kernel. Open inotify instances until it says EMFILE, report the
number, and close them all again.
"""
import ctypes
import errno
import os
import sys

libc = ctypes.CDLL("libc.so.6", use_errno=True)

IN_NONBLOCK = 0o4000
IN_CLOEXEC = 0o2000000

cap = int(open("/proc/sys/fs/inotify/max_user_instances").read().strip())

fds = []
err = None
try:
    while len(fds) <= cap + 16:          # never spin forever
        fd = libc.inotify_init1(IN_NONBLOCK | IN_CLOEXEC)
        if fd < 0:
            err = ctypes.get_errno()
            break
        fds.append(fd)
finally:
    for fd in fds:
        os.close(fd)

free = len(fds)
print("fs.inotify.max_user_instances : %d" % cap)
print("instances this UID could open : %d" % free)
if err is not None:
    print("stopped with                  : %s (%s)"
          % (errno.errorcode.get(err, err), os.strerror(err)))

if free == 0:
    print("\nVERDICT: cap is FULLY EXHAUSTED right now -- any program calling")
    print("         inotify_init() fails with EMFILE ('Too many open files').")
    sys.exit(1)
elif free < 10:
    print("\nVERDICT: only %d slot(s) left -- nnn may start now and fail minutes" % free)
    print("         later. Effectively exhausted.")
    sys.exit(1)
else:
    print("\nVERDICT: %d slots free of %d." % (free, cap))
    sys.exit(0)
