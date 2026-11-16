#!/usr/bin/env bash
# Super+V clipboard history picker (cliphist + wofi).
# Only touch the clipboard if an entry was actually picked: piping a cancelled
# (empty) wofi selection into wl-copy would WIPE the current clipboard.
args=(--dmenu --width 400 --height 300)
# Optional picker styling; the file is not tracked, so only use it when present.
[ -f "$HOME/.config/wofi/clipboard.css" ] && args+=(--style "$HOME/.config/wofi/clipboard.css")
sel=$(cliphist list | wofi "${args[@]}") || exit 0
[ -n "$sel" ] || exit 0
printf '%s' "$sel" | cliphist decode | wl-copy
