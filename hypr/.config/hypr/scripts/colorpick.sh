#!/bin/bash
# Pick a color with nothing distorting the sampled pixels.
#
# hyprpicker reads the composited output, so two things corrupt a pick:
#   inactive_opacity  - unfocused windows blend with whatever is behind them
#   screen_shader     - brightness.sh multiplies rgb when brightness < 1.0
# Force both off for the duration, then put them back exactly as they were.

old_opacity=$(hyprctl getoption decoration:inactive_opacity -j | jq -r '.float')
old_shader=$(hyprctl getoption decoration:screen_shader -j | jq -r '.str')
[ -z "$old_shader" ] && old_shader='[[EMPTY]]'

restore() {
    hyprctl keyword decoration:inactive_opacity "$old_opacity" >/dev/null
    hyprctl keyword decoration:screen_shader "$old_shader" >/dev/null
}
trap restore EXIT INT TERM

hyprctl keyword decoration:inactive_opacity 1.0 >/dev/null
hyprctl keyword decoration:screen_shader '[[EMPTY]]' >/dev/null

# Let the compositor render one frame at full opacity before hyprpicker grabs it,
# otherwise -z freezes the still-transparent screen.
sleep 0.15

hyprpicker "$@"
