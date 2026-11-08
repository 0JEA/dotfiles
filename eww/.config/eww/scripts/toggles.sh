#!/usr/bin/env bash
# Quick-toggle state and actions for the eww panel.
#
# The toggle set is deliberately machine-specific. A generic panel would ship
# wifi / bluetooth / power-profile buttons; on THIS desktop all three are dead
# controls and were dropped rather than rendered as buttons that do nothing:
#   - no wifi device (nmcli shows ethernet only)
#   - no bluetooth controller (bluetoothctl show returns nothing; note it also
#     HANGS without a tty, so it must never be called from a poll)
#   - power-profiles-daemon is installed but its systemd unit is masked
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
TOGGLES_FALLBACK='{"dnd":false,"paper":false}'

PAPER_TOGGLE="$HOME/dotfiles/theme/scripts/toggle-paper-shader.sh"

state_json() {
    local dnd shader paper
    dnd=$(dunstctl is-paused 2>/dev/null || echo false)
    [ "$dnd" = "true" ] || dnd=false
    shader=$(hyprctl getoption decoration:screen_shader 2>/dev/null | grep -oE 'str: .*' | sed 's/^str: //')
    if printf '%s' "$shader" | grep -q 'paper'; then paper=true; else paper=false; fi
    jq -nc --argjson dnd "$dnd" --argjson paper "$paper" '{dnd:$dnd, paper:$paper}' \
      | emit_json "$TOGGLES_FALLBACK"
}

# Push the new state to eww the moment it changes. The toggles poll runs every
# 2 seconds, so without this a tile stayed visibly "off" for up to two seconds
# after being clicked.
push() { "$HOME/.config/eww/scripts/eww-push.sh" toggles "$(state_json)"; }

case "${1:-get}" in
get)
    # One code path, so `get` and the push after an action cannot drift apart --
    # and so both go through emit_json's guarantee of valid output.
    state_json
    ;;
dnd)
    dunstctl set-paused toggle 2>/dev/null
    push
    ;;
paper)
    [ -x "$PAPER_TOGGLE" ] && "$PAPER_TOGGLE" >/dev/null 2>&1 &
    # Delayed on purpose: the toggle above is detached and Hyprland has not
    # swapped the screen_shader yet, so an immediate read would push back the
    # state we just changed away from.
    ( sleep 0.5; push ) >/dev/null 2>&1 &
    ;;
esac
