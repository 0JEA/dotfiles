#!/usr/bin/env bash
# Toggle the procedural paper-texture screen shader (Super+Shift+P).
#
#   toggle-paper-shader.sh          -> toggle the default (pdf: zathura-p's look)
#   toggle-paper-shader.sh web      -> paperweb's default paper preset
#   toggle-paper-shader.sh 0.6      -> the pdf look at any strength you like
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

# Knob defaults = the PDF look: zathura-p's tuned values, copied from
# zathura/.config/zathura/zathurarc. Each knob maps to a recolor-paper-* setting
# of the same name, so a value tuned in one carries straight over to the other.
LOOK=0
STRENGTH=0.45
TOOTH=1.0
DEPTH=0.275
DEPTH_SCALE=14.5
MARKS=0.28
MARK_DENSITY=0.15
MARK_SCALE=40.0
PITS=0.545
PIT_DENSITY=0.015
PIT_SCALE=9.0
SCRATCHES=0.344
SCRATCH_DENSITY=0.036
SCRATCH_SCALE=11.94
SEED=1
# The web look is sized in CSS pixels, so it needs the scale of the monitor it
# lands on. The focused one is the best guess; fall back to 1.
MON_SCALE=$(hyprctl monitors -j 2>/dev/null | jq -r 'map(select(.focused))[0].scale // 1' 2>/dev/null || echo 1)
[[ $MON_SCALE =~ ^[0-9.]+$ ]] || MON_SCALE=1

VARIANT="${1:-pdf}"
case "$VARIANT" in
    pdf)           ;;
    # web: paperweb's default `paper` preset. Its layers are fixed in the
    # template; only the look switch differs.
    web)           LOOK=1 ;;
    live)          ;;   # HUD-driven; every knob comes from PAPER_*
    [0-9]*.[0-9]*|[0-9]*) STRENGTH="$VARIANT" ;;
    *) echo "usage: ${0##*/} [pdf|web|live|<strength>]" >&2; exit 1 ;;
esac

KNOBS=(LOOK STRENGTH TOOTH DEPTH DEPTH_SCALE MARKS MARK_DENSITY MARK_SCALE
       PITS PIT_DENSITY PIT_SCALE SCRATCHES SCRATCH_DENSITY SCRATCH_SCALE SEED
       MON_SCALE)

# Env overrides come AFTER the case, or the variant would clobber them. This is
# how the live tuning HUD (theme/scripts/paper-hud.py) drives this script:
# PAPER_STRENGTH=0.6 PAPER_DEPTH=0.4 ... toggle-paper-shader.sh live
for k in "${KNOBS[@]}"; do
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
subst=()
for k in "${KNOBS[@]}"; do subst+=(-e "s/__${k}__/${!k}/g"); done
sed "${subst[@]}" "$TMPL" > "$SHADER.new"
# An unsubstituted placeholder is a GLSL syntax error, and Hyprland reports a
# shader compile failure only as a black screen -- check before applying.
if grep -q '__[A-Z_]*__' "$SHADER.new"; then
    rm -f "$SHADER.new"
    note "template has unsubstituted placeholders"
    echo "toggle-paper-shader: unsubstituted placeholder in template" >&2
    exit 1
fi
# Same reason: a shader that does not compile is a black screen, so validate it
# before Hyprland ever sees it.
if command -v glslangValidator >/dev/null && ! glslangValidator -S frag "$SHADER.new" >/dev/null 2>&1; then
    rm -f "$SHADER.new"
    note "shader failed to compile; left the screen alone"
    echo "toggle-paper-shader: generated shader does not compile" >&2
    exit 1
fi
# Hyprland has ONE screen_shader slot, which brightness.sh also writes. Record
# whether paper is on and which file is the base, then let brightness.sh place
# the shader: it composes paper+dim when the screen is dimmed and installs plain
# paper when it is not. Previously each simply overwrote the other.
BRIGHTNESS="$HOME/.config/hypr/scripts/brightness.sh"
ACTIVE_PAPER="$CACHE/active-paper"

place_shader() {
    if [ -x "$BRIGHTNESS" ]; then
        "$BRIGHTNESS" reapply >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Paper is considered on if the live shader is the paper file OR the composed
# paper+dim file that brightness.sh builds from it.
if [[ $FORCE_ON == 0 ]] && [[ "$CURRENT" == "$SHADER" || "$CURRENT" == "$CACHE/paper+dim.frag" ]] && cmp -s "$SHADER.new" "$SHADER"; then
    rm -f "$SHADER.new"
    rm -f "$ACTIVE_PAPER"
    # Hand back to brightness.sh so an active dim is restored rather than lost.
    place_shader || hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    note "Off"
else
    mv -f "$SHADER.new" "$SHADER"
    printf '%s\n' "$SHADER" > "$ACTIVE_PAPER"
    # re-apply even if the path is unchanged, so an edited template takes effect
    hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    place_shader || hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null
    note "On (${VARIANT})"
fi
