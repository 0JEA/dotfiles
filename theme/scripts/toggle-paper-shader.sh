#!/usr/bin/env bash
# Toggle the procedural paper-texture screen shader (Super+Shift+P).
#
#   toggle-paper-shader.sh          -> toggle the default (calm) shader
#   toggle-paper-shader.sh bold     -> toggle the stronger variant
#
# Applies Hyprland's decoration:screen_shader, which papers light backgrounds
# (PDF pages, docs) with a warm tone + procedural grain while leaving dark UI
# alone. Static pattern: it never animates, so it cannot shimmer while reading.
set -euo pipefail

VARIANT="${1:-calm}"
case "$VARIANT" in
    calm) SHADER="$HOME/dotfiles/theme/shaders/paper.frag" ;;
    bold) SHADER="$HOME/dotfiles/theme/shaders/paper-bold.frag" ;;
    *) echo "usage: ${0##*/} [calm|bold]" >&2; exit 1 ;;
esac

if [[ ! -f "$SHADER" ]]; then
    echo "toggle-paper-shader: missing shader: $SHADER" >&2
    exit 1
fi

CURRENT=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')

if [[ "$CURRENT" == "$SHADER" ]]; then
    hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    notify-send -t 1500 -a paper "Paper texture" "Off"
else
    hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null
    notify-send -t 1500 -a paper "Paper texture" "On (${VARIANT})"
fi
