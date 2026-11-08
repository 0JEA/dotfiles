#!/usr/bin/env bash
# Portrait toggle for the eww panel: rotate.sh get | toggle
#
# Rotates the FOCUSED monitor between landscape and portrait, for when the
# screen is physically turned on its stand.
#
# The monitor rule is re-applied from hyprland.conf's own `monitor=` line with
# a transform appended, rather than rebuilt from `hyprctl monitors`. That line
# carries bitdepth 10, vrr and the dcip3 colour mode, none of which the live
# monitor dump reports in a form that can be fed back, and dropping them would
# silently revert DP-3 to 8-bit sRGB every time it rotates.
#
# Not persistent on purpose: `hyprctl reload` or a re-login re-reads the config
# and comes back landscape, which reads back here as "off".
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
ROTATE_FALLBACK='{"portrait":false}'
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

# Hyprland transform for portrait. 1 = 90 deg, 3 = 270 deg. Which one is right
# depends on which way the screen turns on its stand: if the picture comes out
# upside down, swap this for the other.
PORTRAIT_TRANSFORM=1

focused() { hyprctl monitors -j 2>/dev/null | jq -c 'map(select(.focused))[0] // empty'; }

state_json() {
    local t
    t=$(focused | jq -r '.transform // 0')
    jq -nc --argjson p "$([ "${t:-0}" != 0 ] && echo true || echo false)" '{portrait:$p}' \
      | emit_json "$ROTATE_FALLBACK"
}

case "${1:-get}" in
get)
    state_json
    ;;
toggle)
    mon=$(focused) || exit 0
    [ -n "$mon" ] || exit 0
    name=$(printf '%s' "$mon" | jq -r .name)
    # The connector's own rule from the config, minus any transform already on it.
    rule=$(grep -E "^monitor=${name}," "$HYPR_CONF" | tail -1 | sed -E 's/^monitor=//; s/,transform,[0-9]+//')
    if [ -z "$rule" ]; then
        # No dedicated line (caught by the catch-all rule): rebuild the basics.
        rule=$(printf '%s' "$mon" | jq -r '"\(.name),\(.width)x\(.height)@\(.refreshRate),\(.x)x\(.y),\(.scale)"')
    fi
    if [ "$(printf '%s' "$mon" | jq -r .transform)" = 0 ]; then t=$PORTRAIT_TRANSFORM; else t=0; fi
    hyprctl keyword monitor "${rule},transform,${t}" >/dev/null 2>&1
    # The rail was laid out for the old screen shape; close it so the next
    # Super+W opens it against the rotated geometry.
    "$HOME/.config/eww/scripts/panel.sh" close >/dev/null 2>&1
    ;;
esac
