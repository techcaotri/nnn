#!/usr/bin/env bash
# Production build for this fork: every extended feature (see README.md
# "Fork Enhancements"), emoji icons, PCRE2 regex filters, optimized build.
#
# NNN_DND_OSC72 and NNN_DND_DEBUG are runtime environment variables, not
# build flags: they gate behavior in the resulting binary at startup and
# never need a rebuild to change. Set them when you run nnn, e.g.:
#   NNN_DND_OSC72=1 ./nnn
set -e

make -j$(($(nproc) - 2)) \
	O_EMOJI=1 \
	O_PCRE2=1 \
	O_QSORT=1 \
	O_SSN_ON_CD=1 \
	O_SSN_PIPE=1 \
	O_FZ_CPMV=1 \
	O_HIST=1 \
	O_DND=1
