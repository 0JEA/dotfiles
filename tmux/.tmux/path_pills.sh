#!/usr/bin/env bash

# ==============================================================================
# TMUX PATH BREADCRUMBS SCRIPT
# ==============================================================================
# This script generates a connected "pill" chain of the current directory path
# for the tmux status line. Each directory in the path becomes a color-coded
# segment, starting with a special orange terminal icon.
#
# USAGE: Add this to your .tmux.conf:
# set -g status-left "#(bash ~/.tmux/path_pills.sh \"#{pane_current_path}\")"
# ==============================================================================

# --- COLOR PALETTE (Tokyo Night Pro inspired) ---
# Edit these hex codes to change the look of your breadcrumbs.
TEXT_DARK="#1a1b26"   # Used for text inside the colored pills
ICON_ORANGE="#ff9e64" # Used for the terminal icon segment
BG_DEFAULT="default"  # Usually transparent or your tmux status-bg

# High-contrast colors for path segments (will be cycled through)
SEGMENT_COLORS=(
    "#7aa2f7" # Blue
    "#7dcfff" # Cyan
    "#bb9af7" # Magenta
    "#9ece6a" # Green
    "#e0af68" # Yellow
    "#ff9e64" # Orange
    "#f7768e" # Red
)
NUM_COLORS=${#SEGMENT_COLORS[@]}

# --- PATH PROCESSING ---
PATH_RAW="$1"
# Replace the absolute home path with a tilde (~) for brevity
PATH_DISPLAY=$(echo "$PATH_RAW" | sed "s|$HOME|~|")

# Split the path into an array of directory names using '/' as delimiter
IFS='/' read -ra PATH_PARTS <<< "$PATH_DISPLAY"

# Clean up empty elements (occurs if path starts with /)
FINAL_SEGMENTS=()
for segment in "${PATH_PARTS[@]}"; do
    [[ -n "$segment" ]] && FINAL_SEGMENTS+=("$segment")
done

# Edge case: If the path is just the root directory "/"
[[ -z "${FINAL_SEGMENTS[*]}" && "$PATH_DISPLAY" == "/" ]] && FINAL_SEGMENTS+=("/")

# --- SEGMENT GENERATION ---
# 1. THE TERMINAL ICON (The "Anchor")
# - Slanted left edge: 
# - Connected right edge:  (transitioning to the first path color)
FIRST_PATH_COLOR=${SEGMENT_COLORS[0]}
printf "#[fg=$ICON_ORANGE,bg=$BG_DEFAULT]"
printf "#[fg=$TEXT_DARK,bg=$ICON_ORANGE,bold] 󰆍 "

# 2. THE PATH SEGMENTS
count=0
total_segments=${#FINAL_SEGMENTS[@]}

for segment in "${FINAL_SEGMENTS[@]}"; do
    current_color=${SEGMENT_COLORS[$((count % NUM_COLORS))]}
    
    # CONNECTOR: Transition from the previous segment's color
    if [ $count -eq 0 ]; then
        # From Orange Icon to First Path Segment
        printf "#[fg=$ICON_ORANGE,bg=$current_color]"
    else
        # From Previous Path Segment to Current Segment
        prev_color=${SEGMENT_COLORS[$(((count - 1) % NUM_COLORS))]}
        printf "#[fg=$prev_color,bg=$current_color]"
    fi

    # CONTENT: The directory name itself
    # We add a leading space for padding
    printf "#[fg=$TEXT_DARK,bg=$current_color,bold] %s" "$segment"

    # CLOSING: The final rounded cap at the very end of the chain
    if [ $((count + 1)) -eq $total_segments ]; then
        printf "#[fg=$current_color,bg=$BG_DEFAULT]"
    fi
    
    ((count++))
done
