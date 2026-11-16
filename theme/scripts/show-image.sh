#!/usr/bin/env bash

# ==============================================================================
# SHOW-IMAGE SCRIPT
# ==============================================================================
# Renders an image inline in a dedicated kitty window on the real Hyprland
# desktop, using the kitty graphics protocol via remote control. Written so
# that a process with no controlling TTY (e.g. an agent's sandboxed shell)
# can still get real pixels onto screen: it drives a REAL kitty window's
# real shell by typing the icat command into it over the remote-control
# socket, rather than trying to draw graphics itself.
#
# Requires kitty.conf: allow_remote_control socket-only / listen_on set
# (see dotfiles/kitty/.config/kitty/kitty.conf) and reuses/creates a window
# titled "icat-display" tracked by Hyprland.
#
# Usage: show-image.sh /path/to/image.png
# ==============================================================================

set -euo pipefail

WINDOW_TITLE="icat-display"
IMG="${1:?usage: show-image.sh <path-to-image>}"
IMG="$(realpath "$IMG")"

# The path is typed into a live interactive shell further down (send-text), so
# a filename may not carry anything the shell would act on. realpath resolves
# the path but does not strip quotes — "x'; cmd; '.png" is a legal filename.
# Reject shell metacharacters outright, then shell-quote whatever survives.
case "$IMG" in
    *[\'\"\`\$\\]* | *$'\n'* | *$'\r'*)
        echo "show-image: refusing path with shell metacharacters: $IMG" >&2
        exit 1
        ;;
esac

find_socket() {
    local pid
    # Anchor with ^: an unanchored match also catches the `hyprctl dispatch exec
    # "kitty --title ..."` launcher (same string in its cmdline, lower PID, sorts
    # first), so find_socket would test /tmp/kitty-<hyprctl-pid> and fail.
    # The launcher's cmdline starts with hyprctl (or /bin/sh -c), so ^kitty
    # excludes it. NOTE: `pgrep -x kitty -f PATTERN` is NOT the fix -- pgrep
    # rejects that as two patterns ("only one pattern can be provided").
    pid=$(pgrep -f "^kitty --title $WINDOW_TITLE" | head -1) || return 1
    [[ -n "$pid" ]] || return 1
    local sock="/tmp/kitty-$pid"
    [[ -S "$sock" ]] || return 1
    echo "$sock"
}

SOCK="$(find_socket || true)"

if [[ -z "$SOCK" ]]; then
    hyprctl dispatch exec "kitty --title $WINDOW_TITLE" >/dev/null
    for _ in $(seq 1 20); do
        sleep 0.2
        SOCK="$(find_socket || true)"
        [[ -n "$SOCK" ]] && break
    done
fi

if [[ -z "$SOCK" ]]; then
    echo "show-image: failed to open a kitty window/socket" >&2
    exit 1
fi

# Typed into the window's real shell (not run as a remote-control overlay
# kitten) so the image persists on screen instead of being erased when the
# overlay exits and restores the prior screen contents.
printf -v IMG_Q '%q' "$IMG"
kitty @ --to "unix:$SOCK" send-text "kitty +kitten icat --transfer-mode=stream -- $IMG_Q
"

ADDR=$(hyprctl clients -j | jq -r --arg t "$WINDOW_TITLE" 'first(.[] | select(.title==$t) | .address) // ""')
# `[[ ... ]] && cmd` as the LAST line would make an empty ADDR the script's exit
# status -- reporting failure even though the image displayed fine.
if [[ -n "$ADDR" ]]; then
    hyprctl dispatch focuswindow "address:$ADDR" >/dev/null
fi
exit 0
