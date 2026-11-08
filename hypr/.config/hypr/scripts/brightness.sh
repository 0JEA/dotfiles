#!/bin/bash
# Screen brightness for a DESKTOP with no backlight device.
#
# This machine drives an HDMI monitor, so there is no /sys backlight for
# brightnessctl to write and no DDC/CI helper installed. Brightness is faked by
# multiplying the final framebuffer in a Hyprland screen shader instead.
#
#   brightness.sh up | down    step by 10% (bound to Super+XF86MonBrightness*)
#   brightness.sh get          print current level as an integer 10-100
#   brightness.sh set <10-100> set an absolute level (used by the eww panel)
#
# CONFLICT WORTH KNOWING ABOUT: Hyprland has exactly ONE
# decoration:screen_shader slot, and theme/scripts/toggle-paper-shader.sh writes
# the same slot. Dimming while the paper shader is on replaces the paper shader,
# and toggling the paper shader on discards the dim. That was already true
# before the eww panel existed; the panel just makes it easier to hit.

STATE_FILE="/tmp/hypr_brightness"
SHADER="$HOME/.config/hypr/shaders/dim.glsl"
TMP_SHADER="$HOME/.config/hypr/shaders/dim.glsl.tmp"

# Hyprland has exactly ONE decoration:screen_shader slot, so dimming and the
# paper texture used to overwrite each other: dimming while paper was on threw
# the paper away, and toggling paper on threw the dim away.
#
# They compose instead now. Dim is a single multiply, so it can simply be
# appended to the paper shader's last write to fragColor -- the later write
# wins, which is exactly the dim applied after the paper effect. The result is
# checked with glslangValidator before it is installed, because Hyprland
# reports a shader that fails to compile as a BLACK SCREEN and nothing else.
PAPER_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/paper-shader"
ACTIVE_PAPER="$PAPER_CACHE/active-paper"   # written by toggle-paper-shader.sh
COMBINED="$PAPER_CACHE/paper+dim.frag"

# Build <paper shader> + dim, printing the path on success and nothing on failure.
compose_paper_dim() {
    local mult="$1" base="$2"
    [ -r "$base" ] || return 1
    mkdir -p "$PAPER_CACHE"

    awk -v m="$mult" '
        { line[NR] = $0 }
        END {
            last = 0
            for (i = NR; i >= 1; i--) {
                t = line[i]; gsub(/[ \t]/, "", t)
                if (t == "}") { last = i; break }
            }
            for (i = 1; i <= NR; i++) {
                if (i == last) printf "    fragColor.rgb *= %s;\n", m
                print line[i]
            }
        }' "$base" > "$COMBINED.new" || return 1

    if ! glslangValidator -S frag "$COMBINED.new" >/dev/null 2>&1; then
        rm -f "$COMBINED.new"
        return 1
    fi
    mv -f "$COMBINED.new" "$COMBINED"
    printf '%s' "$COMBINED"
}

current=$(cat "$STATE_FILE" 2>/dev/null || echo "1.0")

# Push the level straight into eww. The panel polls this every 2 seconds, so
# without it the slider and its number lagged behind the key or the drag by up
# to two seconds. Also keeps the panel correct when brightness is changed with
# Super+= / Super+- while the panel is open.
push_eww() {
    local helper="$HOME/.config/eww/scripts/eww-push.sh"
    [ -x "$helper" ] || return 0
    "$helper" bright "$(awk "BEGIN {printf \"%.0f\", $1*100}")"
}

# Write a 0.1-1.0 multiplier to the state file and install (or clear) the shader.
apply() {
    local new="$1"
    echo "$new" > "$STATE_FILE"

    # Paper on? Then never clobber it -- dim on top of it, or hand back the
    # plain paper shader when dimming is off.
    local paper_base=""
    [ -r "$ACTIVE_PAPER" ] && paper_base=$(cat "$ACTIVE_PAPER" 2>/dev/null)
    if [ -n "$paper_base" ] && [ -r "$paper_base" ]; then
        if [ "$new" = "1.0" ]; then
            hyprctl keyword decoration:screen_shader "$paper_base"
        else
            local combined
            combined=$(compose_paper_dim "$new" "$paper_base")
            # A failed compose must leave paper alone rather than black the screen.
            hyprctl keyword decoration:screen_shader "${combined:-$paper_base}"
        fi
        push_eww "$new"
        return
    fi

    if [ "$new" = "1.0" ]; then
        hyprctl keyword decoration:screen_shader '[[EMPTY]]'
    else
        printf 'precision mediump float;\nvarying vec2 v_texcoord;\nuniform sampler2D tex;\n\nvoid main() {\n    vec4 color = texture2D(tex, v_texcoord);\n    color.rgb *= %s;\n    gl_FragColor = color;\n}\n' "$new" > "$TMP_SHADER"
        mv "$TMP_SHADER" "$SHADER"
        hyprctl keyword decoration:screen_shader "$SHADER"
    fi

    push_eww "$new"
}

# These two must be matched BEFORE the up/down branch below. That branch treats
# every non-"up" argument as "down", so an unguarded `get` would dim the screen.
case "$1" in
reapply)
    # Called by toggle-paper-shader.sh after it turns paper on or off, so the
    # dim level survives the change instead of being silently discarded.
    apply "$current"
    exit 0
    ;;
get)
    awk "BEGIN {printf \"%.0f\", $current*100}"
    exit 0
    ;;
set)
    pct="$2"
    case "$pct" in ''|*[!0-9.]*) exit 1 ;; esac
    new=$(awk "BEGIN {v=$pct/100; if(v>1.0) v=1.0; if(v<0.1) v=0.1; printf \"%.1f\", v}")
    apply "$new"
    exit 0
    ;;
esac

if [ "$1" = "up" ]; then
    new=$(awk "BEGIN {v=$current+0.1; if(v>1.0) v=1.0; printf \"%.1f\", v}")
else
    new=$(awk "BEGIN {v=$current-0.1; if(v<0.1) v=0.1; printf \"%.1f\", v}")
fi

apply "$new"
