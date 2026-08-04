#!/bin/bash

STATE_FILE="/tmp/hypr_brightness"
SHADER="$HOME/.config/hypr/shaders/dim.glsl"
TMP_SHADER="$HOME/.config/hypr/shaders/dim.glsl.tmp"

current=$(cat "$STATE_FILE" 2>/dev/null || echo "1.0")

if [ "$1" = "up" ]; then
    new=$(awk "BEGIN {v=$current+0.1; if(v>1.0) v=1.0; printf \"%.1f\", v}")
else
    new=$(awk "BEGIN {v=$current-0.1; if(v<0.1) v=0.1; printf \"%.1f\", v}")
fi

echo "$new" > "$STATE_FILE"

if [ "$new" = "1.0" ]; then
    hyprctl keyword decoration:screen_shader '[[EMPTY]]'
else
    printf 'precision mediump float;\nvarying vec2 v_texcoord;\nuniform sampler2D tex;\n\nvoid main() {\n    vec4 color = texture2D(tex, v_texcoord);\n    color.rgb *= %s;\n    gl_FragColor = color;\n}\n' "$new" > "$TMP_SHADER"
    mv "$TMP_SHADER" "$SHADER"
    hyprctl keyword decoration:screen_shader "$SHADER"
fi
