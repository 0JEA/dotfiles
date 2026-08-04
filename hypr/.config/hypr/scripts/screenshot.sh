#!/usr/bin/env bash
# screenshot.sh — take a 2x resolution screenshot with blur/transparency temporarily disabled
# Usage: screenshot.sh [mode]
#   mode: region (default), window, screen

MODE="${1:-region}"
SAVEDIR="${HYPRSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME}}"
FILEPATH="$SAVEDIR/$(date +'%Y-%m-%d-%H%M%S')_screenshot.png"

# Disable blur and make inactive windows fully opaque
hyprctl keyword decoration:blur:enabled false
hyprctl keyword decoration:inactive_opacity 1.0

sleep 0.15

case "$MODE" in
    screen)
        grim "$FILEPATH"
        ;;
    window)
        GEOM=$(hyprctl activewindow -j | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        grim -g "$GEOM" "$FILEPATH"
        ;;
    region|*)
        grim -g "$(slurp)" "$FILEPATH"
        ;;
esac

# Restore original values
hyprctl keyword decoration:blur:enabled true
hyprctl keyword decoration:inactive_opacity 0.7

if [ -f "$FILEPATH" ]; then
    wl-copy --type image/png < "$FILEPATH"
    notify-send "Screenshot saved" "$(basename "$FILEPATH")"
fi
