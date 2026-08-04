#!/usr/bin/env bash
# auto-power.sh — runs as user via systemd timer + udev
# Decides which power profile is appropriate and calls set-profile.sh if needed.

set -euo pipefail

OVERRIDE_LOCK="/run/user/1000/power-override.lock"
STATE_FILE="/run/current-power-profile"
SET_PROFILE="/home/coke/dotfiles/power/scripts/set-profile.sh"

# ── Respect manual override (5-minute window) ────────────────────────────────
if [[ -f "$OVERRIDE_LOCK" ]]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "$OVERRIDE_LOCK") ))
    if [[ "$AGE" -lt 300 ]]; then
        exit 0
    else
        rm -f "$OVERRIDE_LOCK"
    fi
fi

# ── Read system state ─────────────────────────────────────────────────────────
AC=$(cat /sys/class/power_supply/AC0/online 2>/dev/null || echo "1")
PCT=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null | grep -E '^[0-9]+$' || echo "50")
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# ── Decide profile ────────────────────────────────────────────────────────────
if [[ "$AC" == "1" ]]; then
    WANTED="ac"
elif [[ "$PCT" -le 20 ]]; then
    WANTED="critical"
else
    WANTED="battery"
fi

# ── Apply only if changed ─────────────────────────────────────────────────────
if [[ "$WANTED" != "$CURRENT" ]]; then
    sudo "$SET_PROFILE" "$WANTED"
fi
