#!/usr/bin/env bash
# Regression test for the OSC-72 drag tmux `mouse` grab (src/nnn.c,
# dnd_grab_tmux_mouse / dnd_release_tmux_mouse / dnd_repair_tmux_mouse).
# Exercises the exact shell those functions emit against an ISOLATED tmux server
# on socket "mousetest", so a running session is never touched.
#
# Usage:  misc/test/test-dnd-tmux-mouse.sh        # watchdog cap 4s (default)
#         MAX=10 misc/test/test-dnd-tmux-mouse.sh # slower machines
# See docs/nnn_Problems_And_Solutions.md Problem 13.
set -u

S=$(mktemp -d "${TMPDIR:-/tmp}/nnn-dnd-mousetest.XXXXXX") || exit 1
trap 'rm -rf "$S"' EXIT
SOCK=mousetest
REAL=$(command -v tmux) || { echo "tmux not found"; exit 1; }
MAX=${MAX:-4}          # watchdog cap, shortened from the code's 60s for testing

# tmux shim so both this script and tmux's own run-shell children talk to the
# isolated server, exactly as a bare `tmux` would inside a real session.
mkdir -p "$S/shimbin"
cat > "$S/shimbin/tmux" <<EOF
#!/bin/sh
exec $REAL -L $SOCK "\$@"
EOF
chmod +x "$S/shimbin/tmux"
export PATH="$S/shimbin:$PATH"

$REAL -L $SOCK kill-server 2>/dev/null
$REAL -L $SOCK -f /dev/null new-session -d -s t 2>/dev/null
sleep 0.5

pass=0; fail=0
chk() { # chk <label> <expected> <actual>
	if [ "$2" = "$3" ]; then printf '  PASS  %-46s %s\n' "$1" "$2"; pass=$((pass+1))
	else printf '  FAIL  %-46s expected=[%s] actual=[%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
mouse()  { tmux show -gv mouse 2>/dev/null; }
marker() { tmux show -gv @nnn_dnd_mouse 2>/dev/null; }
reset()  { tmux set -gu @nnn_dnd_mouse 2>/dev/null; tmux set -g mouse "${1:-on}"; }

grab() { # grab <pid> <token>
	sh -c "if [ -z \"\$(tmux show -gv @nnn_dnd_mouse 2>/dev/null)\" ]; then m=\$(tmux show -gv mouse 2>/dev/null); [ -n \"\$m\" ] || m=on; tmux set -g @nnn_dnd_mouse \"$1.$2:\$m\"; fi; tmux set -g mouse off; tmux run-shell -b 'i=0; while [ \$i -lt $MAX ]; do sleep 1; i=\$((i+1)); kill -0 $1 2>/dev/null || break; done; v=\$(tmux show -gv @nnn_dnd_mouse 2>/dev/null); [ \"\${v%%:*}\" = $1.$2 ] || exit 0; tmux set -g mouse \"\${v##*:}\"; tmux set -gu @nnn_dnd_mouse'"
}
release() { # release <pid> <token>
	sh -c "v=\$(tmux show -gv @nnn_dnd_mouse 2>/dev/null); [ \"\${v%%:*}\" = $1.$2 ] || exit 0; tmux set -g mouse \"\${v##*:}\"; tmux set -gu @nnn_dnd_mouse"
}
repair() {
	sh -c 'v=$(tmux show -gv @nnn_dnd_mouse 2>/dev/null); [ -n "$v" ] || exit 0; p=${v%%:*}; kill -0 ${p%%.*} 2>/dev/null && exit 0; tmux set -g mouse "${v##*:}"; tmux set -gu @nnn_dnd_mouse'
}

echo "=== T1: normal grab then release (the happy path) ==="
reset on
sleep 60 & OWNER=$!
grab $OWNER 1; sleep 0.4
chk "mouse off during drag"        "off"          "$(mouse)"
chk "marker records pid.token:on"  "$OWNER.1:on"  "$(marker)"
release $OWNER 1; sleep 0.4
chk "mouse restored on release"    "on"           "$(mouse)"
chk "marker cleared"               ""             "$(marker)"
kill $OWNER 2>/dev/null; wait $OWNER 2>/dev/null

echo "=== T2: owner KILLED mid-drag (SIGKILL: no atexit) ==="
reset on
sleep 60 & OWNER=$!
grab $OWNER 1; sleep 0.4
chk "mouse off during drag"        "off"          "$(mouse)"
kill -9 $OWNER 2>/dev/null; wait $OWNER 2>/dev/null
sleep 2.5
chk "watchdog restored after kill" "on"           "$(mouse)"
chk "marker cleared by watchdog"   ""             "$(marker)"

echo "=== T3: drag never ends, owner alive (watchdog timeout ${MAX}s) ==="
reset on
sleep 60 & OWNER=$!
grab $OWNER 1; sleep 0.4
chk "mouse off during drag"        "off"          "$(mouse)"
sleep $((MAX + 2))
chk "watchdog restored on timeout" "on"           "$(mouse)"
chk "marker cleared by watchdog"   ""             "$(marker)"
kill $OWNER 2>/dev/null; wait $OWNER 2>/dev/null

echo "=== T4: user preference 'mouse off' is preserved, not forced on ==="
reset off
sleep 60 & OWNER=$!
grab $OWNER 1; sleep 0.4
chk "marker saved off"             "$OWNER.1:off" "$(marker)"
release $OWNER 1; sleep 0.4
chk "still off after release"      "off"          "$(mouse)"
kill $OWNER 2>/dev/null; wait $OWNER 2>/dev/null

echo "=== T5: dual-pane -- 2nd grabber must not overwrite the saved value ==="
reset on
sleep 60 & A=$!
sleep 60 & B=$!
grab $A 1; sleep 0.3
grab $B 1; sleep 0.3
chk "marker still owned by A"      "$A.1:on"      "$(marker)"
release $B 1; sleep 0.3
chk "B's release is a no-op"       "off"          "$(mouse)"
release $A 1; sleep 0.3
chk "A's release restores"         "on"           "$(mouse)"
kill $A $B 2>/dev/null; wait 2>/dev/null

echo "=== T6: stale watchdog must not cancel a NEWER grab by the same pid ==="
reset on
sleep 60 & OWNER=$!
grab $OWNER 1; sleep 0.3          # token 1
release $OWNER 1; sleep 0.3       # ends normally; token-1 watchdog still sleeping
grab $OWNER 2; sleep 0.3          # token 2 grab, while token-1 watchdog is alive
chk "mouse off under token 2"      "off"          "$(mouse)"
sleep $((MAX + 2))                # token-1 watchdog has now expired
chk "token-2 grab survived, then its own watchdog fired" "on" "$(mouse)"
kill $OWNER 2>/dev/null; wait $OWNER 2>/dev/null

echo "=== T7: startup repair of a grab stranded with no watchdog ==="
reset on
tmux set -g mouse off
tmux set -g @nnn_dnd_mouse "999999.1:on"    # pid that does not exist
repair; sleep 0.4
chk "repair restored saved value"  "on"           "$(mouse)"
chk "repair cleared marker"        ""             "$(marker)"

echo "=== T8: repair must NOT touch a live grab ==="
reset on
sleep 60 & OWNER=$!
tmux set -g mouse off
tmux set -g @nnn_dnd_mouse "$OWNER.1:on"
repair; sleep 0.4
chk "live grab left alone"         "off"          "$(mouse)"
chk "marker left alone"            "$OWNER.1:on"  "$(marker)"
kill $OWNER 2>/dev/null; wait $OWNER 2>/dev/null

$REAL -L $SOCK kill-server 2>/dev/null
echo
echo "==================  PASS=$pass  FAIL=$fail  =================="
[ "$fail" -eq 0 ]
