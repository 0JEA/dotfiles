#!/usr/bin/env bash
# PipeWire volume state and control via wpctl.
#
#   volume.sh get                -> {"sink":90,"sink_muted":false,"source":100,"source_muted":false}
#   volume.sh set-sink <0-100>
#   volume.sh set-source <0-100>
#   volume.sh toggle-sink | toggle-source
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
VOLUME_FALLBACK='{"sink":0,"sink_muted":false,"source":0,"source_muted":false}'

SINK="@DEFAULT_AUDIO_SINK@"
SOURCE="@DEFAULT_AUDIO_SOURCE@"

# `wpctl get-volume` prints "Volume: 0.90" or "Volume: 0.90 [MUTED]".
# The 0-1 float is scaled to a 0-100 integer for the eww scale widget.
read_vol() {
    local out vol muted
    out=$(wpctl get-volume "$1" 2>/dev/null) || { echo "0 true"; return; }
    vol=$(printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [ -n "$vol" ] || vol=0
    if printf '%s' "$out" | grep -q '\[MUTED\]'; then muted=true; else muted=false; fi
    awk -v v="$vol" -v m="$muted" 'BEGIN{printf "%.0f %s", v*100, m}'
}

state_json() {
    local sv sm cv cm
    read -r sv sm <<<"$(read_vol "$SINK")"
    read -r cv cm <<<"$(read_vol "$SOURCE")"
    sv=$(num "$sv"); cv=$(num "$cv")
    jq -nc --argjson sink "${sv:-0}" --argjson sink_muted "${sm:-false}" \
           --argjson source "${cv:-0}" --argjson source_muted "${cm:-false}" \
        '{sink:$sink, sink_muted:$sink_muted, source:$source, source_muted:$source_muted}' \
      | emit_json "$VOLUME_FALLBACK"
}

# Hand the new state to eww immediately instead of letting the panel wait up to
# a second for its next poll -- that delay was the whole reason a mute click
# felt laggy.
push() { "$HOME/.config/eww/scripts/eww-push.sh" volume "$(state_json)"; }

case "${1:-get}" in
get)
    state_json
    ;;
set-sink)
    # -l 1.0 caps at 100%. Without it a dragged slider can push PipeWire past
    # unity gain into clipping.
    wpctl set-volume -l 1.0 "$SINK" "${2:-0}%"
    push
    ;;
set-source)
    wpctl set-volume -l 1.0 "$SOURCE" "${2:-0}%"
    push
    ;;
toggle-sink)
    wpctl set-mute "$SINK" toggle
    push
    ;;
toggle-source)
    wpctl set-mute "$SOURCE" toggle
    push
    ;;
esac
