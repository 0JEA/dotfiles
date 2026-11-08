#!/usr/bin/env bash
# Open/close/toggle the widget panel (Super+W).
#
# The open/closed state lives in ONE place: a state file, which panel-gate.sh
# streams into the `panel-open` deflisten. That variable gates every expensive
# defpoll via :run-while, so a closed panel costs nothing -- no playerctl, no
# nvidia-smi, no dunstctl running on a timer all day.
#
# It used to be a defvar set here with `eww update`. That desynced: `eww reload`
# resets defvars, and eww reloads itself whenever a config file changes, so a
# matugen run left the panel open with its polls stopped and its data frozen.
# Writing the file instead means a reload re-reads the truth rather than
# clobbering it. See panel-gate.sh.
#
# The panel opens on the monitor you are actually looking at, not always
# monitor 0 -- with two outputs connected the old :monitor 0 could open the rail
# on the screen you were not using.
set -uo pipefail

WINDOW="panel"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/eww-panel.state"

# An armed Reboot/Shut down must not outlive the panel. Without this, arming
# one and then closing the panel left it armed, so the NEXT open showed the
# confirm row already up -- one click from shutting the machine down, which is
# most of what the confirmation was added to prevent.
# Guarded by ping: a bare `eww update` STARTS a daemon if none is running, and
# closing a panel that cannot be open is not a reason to spawn one.
disarm_power() {
    eww ping >/dev/null 2>&1 || return 0
    eww update pwr-arm='' 2>/dev/null || true
}

is_open() {
    eww active-windows 2>/dev/null | grep -qE "(^|: )${WINDOW}\$"
}

# eww --screen wants a GTK monitor INDEX. Neither the connector name nor
# Hyprland's own id is one -- see panel-screen.sh, which does the mapping.
focused_screen() { "$HOME/.config/eww/scripts/panel-screen.sh" 2>/dev/null; }

# Open on the focused monitor, falling back to the window's own :monitor if the
# index cannot be resolved. Opening on the wrong screen is a nuisance; failing
# to open at all is a broken keybind, so the fallback always runs.
open_panel() {
    printf 'true\n' > "$STATE_FILE"
    disarm_power

    local screen
    screen=$(focused_screen)

    if [ -n "$screen" ] && eww open --screen "$screen" "$WINDOW" 2>/dev/null; then
        return
    fi
    eww open "$WINDOW" 2>/dev/null
}

close_panel() {
    printf 'false\n' > "$STATE_FILE"
    disarm_power
    eww close "$WINDOW" 2>/dev/null
}

case "${1:-toggle}" in
open)   open_panel ;;
close)  close_panel ;;
toggle) if is_open; then close_panel; else open_panel; fi ;;
esac
