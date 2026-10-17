#!/usr/bin/env bash
# Super+V clipboard history picker (cliphist + wofi).
# Only touch the clipboard if an entry was actually picked: piping a cancelled
# (empty) wofi selection into wl-copy would WIPE the current clipboard.
sel=$(cliphist list | wofi --dmenu --width 400 --height 300) || exit 0
[ -n "$sel" ] || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
