#!/usr/bin/env bash
# Emit the panel's open/closed state for the `panel-open` deflisten.
#
# WHY THIS EXISTS: panel-open used to be a defvar that panel.sh set to true on
# open. `eww reload` resets every defvar to its declared default, and eww
# reloads itself whenever a config file changes -- so regenerating colors.scss
# with matugen, or editing eww.scss, flipped panel-open back to false while the
# window stayed open. Every :run-while poll then stopped and the visible panel
# silently froze at its :initial values until it was closed and reopened.
#
# A deflisten is restarted by a reload rather than reset, so re-reading the
# state file here makes the gate correct again within one tick. The file is the
# single source of truth; nothing keeps the state in two places any more.
#
# Polled rather than inotify-driven: inotify-tools is not installed, and this
# loop uses only bash builtins, so a tick costs no process spawn.
set -uo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/eww-panel.state"

last=""
while true; do
    cur=false
    if [ -r "$STATE_FILE" ]; then
        read -r cur < "$STATE_FILE" || cur=false
    fi
    [ "$cur" = "true" ] || cur=false

    if [ "$cur" != "$last" ]; then
        printf '%s\n' "$cur"
        last="$cur"
    fi
    sleep 0.3
done
