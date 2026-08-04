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

# Defaults = the original 'calm' tuning.
# SCRATCH_THRESH is the baseline scratch probability. 0.985 => 1.5% of cells, and
# the grid is only ~20x11 cells on a 1920x1080 screen => ~3 scratches on the WHOLE
# screen. That is why the imperfections read as missing: they were always that
# sparse, not weakened by any later change (the tuning constants are byte-identical
# across every version of the template).
SCRATCH_THRESH=0.985
SCRATCH_GAIN=1.0
FOLD_GAIN=1.0
FOLD_COUNT=7.0
# per-layer gains; 1.0 reproduces the original tuning exactly
ROUGH_GAIN=1.0
FIBER_GAIN=1.0
AO_GAIN=1.0
FADE_AMT=0.70
RELIEF_Z_VAL=1.8
SEED_VAL=3.0

VARIANT="${1:-calm}"
case "$VARIANT" in
    calm)          STRENGTH=1.0 ;;
    bold)          STRENGTH=2.2 ;;
    # worn: visible imperfections -- ~30 scratches per screen instead of ~3,
    # deeper and more numerous folds. This is the look picked out of the render
    # comparison as the one that reads like real paper.
    worn)          STRENGTH=1.8
                   SCRATCH_THRESH=0.85; SCRATCH_GAIN=1.8
                   FOLD_GAIN=2.4;       FOLD_COUNT=8.0 ;;
    # scratchy: the calm base, but with the imperfections actually visible
    scratchy)      STRENGTH=1.0
                   SCRATCH_THRESH=0.85; SCRATCH_GAIN=1.6 ;;
    live)          STRENGTH=1.0 ;;   # HUD-driven; every knob comes from PAPER_*
    [0-9]*.[0-9]*|[0-9]*) STRENGTH="$VARIANT" ;;
    *) echo "usage: ${0##*/} [calm|bold|worn|scratchy|live|<strength>]" >&2; exit 1 ;;
esac

# Env overrides come AFTER the case, or the variant would clobber them. This is
# how the live tuning HUD (theme/scripts/paper-hud.py) drives this script:
# PAPER_STRENGTH=1.8 PAPER_FOLD_GAIN=2.4 ... toggle-paper-shader.sh live
for k in STRENGTH SCRATCH_THRESH SCRATCH_GAIN FOLD_GAIN FOLD_COUNT \
         ROUGH_GAIN FIBER_GAIN AO_GAIN FADE_AMT RELIEF_Z_VAL SEED_VAL; do
    v="PAPER_$k"
    [[ -n "${!v:-}" ]] && printf -v "$k" '%s' "${!v}"
done

# The HUD re-applies on every slider change, so it must never toggle OFF on a
# repeat call. `apply` forces on; the bare toggle keeps its old behaviour.
FORCE_ON=0
[[ "${PAPER_FORCE_ON:-0}" == "1" ]] && FORCE_ON=1

TMPL="$HOME/dotfiles/theme/shaders/paper.frag.tmpl"
[[ -f "$TMPL" ]] || { note "missing template"; echo "missing: $TMPL" >&2; exit 1; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/paper-shader"
# Name by VARIANT, not by STRENGTH: two variants can share a strength but differ
# in the sparse-feature knobs, and a strength-only name would collide and serve
# the wrong shader from cache.
SHADER="$CACHE/paper-$VARIANT.frag"
mkdir -p "$CACHE"

CURRENT=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')

# Render first, so we can compare CONTENT rather than just the path. Comparing
# paths alone means that after editing the template the cached file is stale but
# the path still matches -- so the toggle would switch OFF instead of picking up
# your edit, and you'd have to press the key twice with no clue why. Same if the
# cache was cleared while the keyword still pointed at it.
sed -e "s/__STRENGTH__/$STRENGTH/" \
    -e "s/__SCRATCH_THRESH__/$SCRATCH_THRESH/" \
    -e "s/__SCRATCH_GAIN__/$SCRATCH_GAIN/" \
    -e "s/__FOLD_GAIN__/$FOLD_GAIN/" \
    -e "s/__FOLD_COUNT__/$FOLD_COUNT/" \
    -e "s/__ROUGH_GAIN__/$ROUGH_GAIN/" \
    -e "s/__FIBER_GAIN__/$FIBER_GAIN/" \
    -e "s/__AO_GAIN__/$AO_GAIN/" \
    -e "s/__FADE_AMT__/$FADE_AMT/" \
    -e "s/__RELIEF_Z_VAL__/$RELIEF_Z_VAL/" \
    -e "s/__SEED_VAL__/$SEED_VAL/" "$TMPL" > "$SHADER.new"
# An unsubstituted placeholder is a GLSL syntax error, and Hyprland reports a
# shader compile failure only as a black screen -- check before applying.
if grep -q '__[A-Z_]*__' "$SHADER.new"; then
    rm -f "$SHADER.new"
    note "template has unsubstituted placeholders"
    echo "toggle-paper-shader: unsubstituted placeholder in template" >&2
    exit 1
fi
if [[ $FORCE_ON == 0 ]] && [[ "$CURRENT" == "$SHADER" ]] && cmp -s "$SHADER.new" "$SHADER"; then
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
