#!/usr/bin/env bash
# Chained brightness control: hardware backlight first, then gamma.
#
# Going down: drains the hardware backlight 100% -> 0% (power-efficient, full
# color depth), then continues into hyprsunset gamma 100 -> 0 for true black,
# which is darker than the panel's own minimum.
# Going up reverses the order.
#
# hyprsunset has no way to query its current gamma, so we track it ourselves.

set -euo pipefail

STEP=5
DEV=amdgpu_bl1
STATE="${XDG_RUNTIME_DIR:-/tmp}/brightness-gamma"

get_hw() { brightnessctl -m -d "$DEV" | cut -d, -f4 | tr -d '%'; }
get_gamma() { cat "$STATE" 2>/dev/null || echo 100; }

set_gamma() {
    local g=$1
    ((g < 0)) && g=0
    ((g > 100)) && g=100
    hyprctl hyprsunset gamma "$g" >/dev/null 2>&1 || return 0
    echo "$g" >"$STATE"
}

case "${1:-}" in
up)
    if (( $(get_gamma) < 100 )); then
        set_gamma "$(( $(get_gamma) + STEP ))"
    else
        brightnessctl -d "$DEV" set "${STEP}%+" >/dev/null
    fi
    ;;
down)
    if (( $(get_hw) > 0 )); then
        brightnessctl -d "$DEV" set "${STEP}%-" >/dev/null
    else
        set_gamma "$(( $(get_gamma) - STEP ))"
    fi
    ;;
reset)
    # Called at login: hardware to max, gamma to full.
    brightnessctl -d "$DEV" set 100% >/dev/null
    set_gamma 100
    ;;
*)
    echo "usage: ${0##*/} {up|down|reset}" >&2
    exit 1
    ;;
esac
