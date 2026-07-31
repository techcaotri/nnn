#!/usr/bin/env bash
# Debug build for this fork: debug symbols via Makefile_debug, no DnD helper.
# See build.sh for the production build with all extended features.
#
# Note: Makefile_debug names its regex flag O_PCRE (not O_PCRE2, unlike the
# production Makefile) and links the legacy PCRE library instead of PCRE2.
set -e

make -j$(($(nproc) - 2)) \
	O_EMOJI=1 \
	O_PCRE=1 \
	O_QSORT=1 \
	O_SSN_ON_CD=1 \
	O_SSN_PIPE=1 \
	O_FZ_CPMV=1 \
	O_HIST=1 \
	O_DEBUG=1 \
	-f Makefile_debug
