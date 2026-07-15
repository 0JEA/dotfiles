#!/usr/bin/env bash
# Toggle the procedural paper-texture screen shader (Super+Shift+P).
#
#   toggle-paper-shader.sh          -> toggle the default (calm)
#   toggle-paper-shader.sh bold     -> stronger variant
#   toggle-paper-shader.sh 1.6      -> any strength you like
#
# Papers light backgrounds (PDF pages, docs) with a warm tone + procedural
# grain, leaving dark UI alone. The pattern is static — it never animates, so it
# cannot shimmer while reading.
#
# Hyprland screen shaders take NO custom uniforms, so strength cannot be a
# runtime parameter: each variant must be a distinct file on disk. Rather than
# commit near-identical copies (which silently diverge the moment someone edits
# one), the single source paper.frag.tmpl is rendered on demand into the cache.
set -euo pipefail

for c in hyprctl jq sed; do
    command -v "$c" >/dev/null || {
        # bound to a key with no terminal attached: a notification is the ONLY
        # way the failure is visible at all
        notify-send -a paper "Paper texture" "missing dependency: $c" 2>/dev/null || true
        echo "toggle-paper-shader: missing dependency: $c" >&2
        exit 1
    }
done
note() { notify-send -t 1500 -a paper "Paper texture" "$1" 2>/dev/null || true; }

VARIANT="${1:-calm}"
case "$VARIANT" in
    calm)          STRENGTH=1.0 ;;
    bold)          STRENGTH=2.2 ;;
    [0-9]*.[0-9]*|[0-9]*) STRENGTH="$VARIANT" ;;
    *) echo "usage: ${0##*/} [calm|bold|<strength>]" >&2; exit 1 ;;
esac

TMPL="$HOME/dotfiles/theme/shaders/paper.frag.tmpl"
[[ -f "$TMPL" ]] || { note "missing template"; echo "missing: $TMPL" >&2; exit 1; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/paper-shader"
SHADER="$CACHE/paper-$STRENGTH.frag"
mkdir -p "$CACHE"

CURRENT=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')

# Render first, so we can compare CONTENT rather than just the path. Comparing
# paths alone means that after editing the template the cached file is stale but
# the path still matches -- so the toggle would switch OFF instead of picking up
# your edit, and you'd have to press the key twice with no clue why. Same if the
# cache was cleared while the keyword still pointed at it.
sed "s/__STRENGTH__/$STRENGTH/" "$TMPL" > "$SHADER.new"
if [[ "$CURRENT" == "$SHADER" ]] && cmp -s "$SHADER.new" "$SHADER"; then
    rm -f "$SHADER.new"
    hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    note "Off"
else
    mv -f "$SHADER.new" "$SHADER"
    # re-apply even if the path is unchanged, so an edited template takes effect
    hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null
    note "On (${VARIANT})"
fi
