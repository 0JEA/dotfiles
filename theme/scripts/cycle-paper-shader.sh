#!/usr/bin/env bash
# Cycle the screen shader: OFF -> calm -> paperlab -> OFF. For A/B'ing the new
# paperlab-derived shader against the current calm one.
set -euo pipefail
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/paper-shader"
mkdir -p "$CACHE"
CALM="$CACHE/paper-calm.frag"
PAPERLAB="$CACHE/paperlab.frag"
INTERESTING="$CACHE/interesting.frag"
cp -f "$HOME/dotfiles/theme/shaders/paperlab.frag" "$PAPERLAB" 2>/dev/null || true
cp -f "$HOME/dotfiles/theme/shaders/interesting.frag" "$INTERESTING" 2>/dev/null || true

# ensure calm exists (render from the template if the cache was cleared)
if [[ ! -f "$CALM" ]]; then
    sed -e 's/__STRENGTH__/1.0/' -e 's/__SCRATCH_THRESH__/0.985/' -e 's/__SCRATCH_GAIN__/1.0/' \
        -e 's/__FOLD_GAIN__/1.0/' -e 's/__FOLD_COUNT__/7.0/' -e 's/__ROUGH_GAIN__/1.0/' \
        -e 's/__FIBER_GAIN__/1.0/' -e 's/__AO_GAIN__/1.0/' -e 's/__FADE_AMT__/0.70/' \
        -e 's/__RELIEF_Z_VAL__/1.8/' -e 's/__SEED_VAL__/3.0/' \
        "$HOME/dotfiles/theme/shaders/paper.frag.tmpl" > "$CALM"
fi

cur=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')
case "$cur" in
    *paperlab*)            next="[[EMPTY]]"; name="OFF" ;;
    *calm*)                next="$PAPERLAB"; name="paperlab" ;;
    *)                     next="$CALM";     name="calm (current)" ;;
esac
hyprctl keyword decoration:screen_shader "$next" >/dev/null
notify-send -t 1200 -a paper "Paper shader" "$name" 2>/dev/null || true
