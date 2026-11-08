#!/usr/bin/env bash
# screenshot.sh — take a 2x resolution screenshot with blur/transparency temporarily disabled
# Usage: screenshot.sh [mode]
#   mode: region (default), window, screen

MODE="${1:-region}"
# XDG_PICTURES_DIR is often NOT exported into the compositor session even when
# ~/.config/user-dirs.dirs exists, so fall back to querying xdg-user-dir directly
# rather than to $HOME (which is what dumped 300+ loose screenshots into ~ before
# 2026-08-28). Flat hyprshot dump lives alongside the dated session subfolders.
SAVEDIR="${HYPRSHOT_DIR:-${XDG_PICTURES_DIR:-$(xdg-user-dir PICTURES 2>/dev/null)}}"
SAVEDIR="${SAVEDIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$SAVEDIR"
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
        # Freeze the screen while selecting, so hover popups/tooltips that close
        # when slurp grabs the pointer are still in the shot (same trick as hyprshot -z).
        hyprpicker -r -z &
        PICKER=$!
        sleep 0.2
        GEOM=$(slurp)
        [ -n "$GEOM" ] && grim -g "$GEOM" "$FILEPATH"
        kill "$PICKER" 2>/dev/null
        ;;
esac

# Restore original values
hyprctl keyword decoration:blur:enabled true
hyprctl keyword decoration:inactive_opacity 0.7

if [ -f "$FILEPATH" ]; then
    wl-copy --type image/png < "$FILEPATH"
    notify-send "Screenshot saved" "$(basename "$FILEPATH")"
fi
