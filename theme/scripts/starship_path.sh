#!/usr/bin/env bash

# ==============================================================================
# STARSHIP PATH BREADCRUMBS SCRIPT
# ==============================================================================
# Outputs ANSI escape code path pills for the starship custom.path module.
# Mirrors the tmux path_pills.sh style using ANSI codes instead of tmux format.
# ==============================================================================

# --- POWERLINE GLYPHS (hex escapes to survive file saves) ---
LEFT_CAP=$'\xEE\x82\xBA'    # U+E0BA slanted left opening
SEPARATOR=$'\xEE\x82\xB4'   # U+E0B4 between-pill connector
RIGHT_CAP=$'\xEE\x82\xB4'   # U+E0B4 closing right cap
ICON=$'\xF3\xB0\x86\x8D'    # U+F018D MDI console

# --- COLOR PALETTE (Tokyo Night) ---
# Text inside pills (dark background color)
TEXT_RGB="26;27;38"      # #1a1b26

# Icon pill color (orange)
ICON_RGB="255;158;100"   # #ff9e64

# High-contrast segment colors (cycled per directory level)
SEGMENT_COLORS=(
    "122;162;247"   # #7aa2f7 blue
    "125;207;255"   # #7dcfff cyan
    "187;154;247"   # #bb9af7 magenta
    "158;206;106"   # #9ece6a green
    "224;175;104"   # #e0af68 yellow
    "255;158;100"   # #ff9e64 orange
    "247;118;142"   # #f7768e red
)
# Darker variants (~70%) — alternate with SEGMENT_COLORS so each pill edge is visible
SEGMENT_COLORS_DARK=(
    "85;113;173"    # blue dark
    "88;145;179"    # cyan dark
    "131;108;173"   # magenta dark
    "111;144;74"    # green dark
    "157;123;73"    # yellow dark
    "179;111;70"    # orange dark
    "173;83;99"     # red dark
)
NUM_COLORS=${#SEGMENT_COLORS[@]}

# --- PATH PROCESSING ---
PATH_DISPLAY="${PWD/$HOME/\~}"

IFS='/' read -ra PATH_PARTS <<< "$PATH_DISPLAY"

FINAL_SEGMENTS=()
for segment in "${PATH_PARTS[@]}"; do
    [[ -n "$segment" ]] && FINAL_SEGMENTS+=("$segment")
done

[[ -z "${FINAL_SEGMENTS[*]}" ]] && FINAL_SEGMENTS+=("/")

# --- ICON PILL ---
# Left cap in icon color on transparent bg
printf "\e[38;2;${ICON_RGB}m\e[49m%s" "$LEFT_CAP"
# Icon content: icon-color bg, dark text, bold
printf "\e[48;2;${ICON_RGB}m\e[38;2;${TEXT_RGB}m\e[1m %s " "$ICON"

# --- PATH SEGMENTS ---
count=0
last_rgb="$ICON_RGB"

for segment in "${FINAL_SEGMENTS[@]}"; do
    color_idx=$((count / 2 % NUM_COLORS))
    if (( count % 2 == 0 )); then
        cur_rgb="${SEGMENT_COLORS[$color_idx]}"
    else
        cur_rgb="${SEGMENT_COLORS_DARK[$color_idx]}"
    fi

    # Powerline separator — fg = prev color, bg = current color
    printf "\e[38;2;${last_rgb}m\e[48;2;${cur_rgb}m%s" "$SEPARATOR"

    # Segment content: current bg, dark text, bold
    printf "\e[38;2;${TEXT_RGB}m\e[48;2;${cur_rgb}m\e[1m %s" "$segment"

    last_rgb="$cur_rgb"
    ((count++))
done

# Close path chain
printf "\e[38;2;${last_rgb}m\e[49m%s" "$RIGHT_CAP"
printf "\e[0m "
