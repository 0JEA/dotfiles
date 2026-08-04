#!/bin/bash
# Usage: apply-theme.sh [image-path]
# If an image is given, extracts its dominant color via ffmpeg and generates theme from it.
# Falls back to hardcoded Tokyo Night color if no image is provided.
CONFIG=~/dotfiles/theme/matugen/config.toml
if [[ -n "$1" ]]; then
    COLOR=$(ffmpeg -i "$1" -vf "scale=1:1:flags=area" -frames:v 1 -f rawvideo -pix_fmt rgb24 pipe:1 2>/dev/null \
        | python3 -c "import sys; b=sys.stdin.buffer.read(3); print('#{:02x}{:02x}{:02x}'.format(b[0],b[1],b[2]))")
    matugen -c "$CONFIG" color hex "$COLOR"
else
    matugen -c "$CONFIG" color hex "#1a1b26"
fi
# Reload apps that need it
hyprctl reload
pkill -SIGUSR2 waybar
