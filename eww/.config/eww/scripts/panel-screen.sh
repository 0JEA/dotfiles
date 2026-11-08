#!/usr/bin/env bash
# Print the GTK monitor INDEX of the currently focused Hyprland monitor.
#
# eww's --screen resolves against GTK's monitor list, and GTK does not use
# connector names or Hyprland's ids. Verified on this machine:
#
#   Hyprland : id=1  name=DP-3            3840x2160 @ scale 1.5
#   GTK      : [0]   model='MAG 274U E16M' 2560x1440 (logical)
#
# So `--screen DP-3` finds nothing AND `--screen 1` is out of range, and the
# open silently falls back to the window's own :monitor 0. That is exactly the
# bug the focused-monitor work was meant to fix, so it has to be an index.
#
# Geometry is the reliable join: GTK reports logical coordinates and so does
# Hyprland once its scale is applied, so the origins match exactly.
#
# The GTK query costs ~100ms, which is too much on every keypress, so the answer
# is cached against a signature of the current monitor layout and only recomputed
# when something is plugged, unplugged or moved.
set -uo pipefail

CACHE="${XDG_RUNTIME_DIR:-/tmp}/eww-panel-screen"

mons=$(hyprctl monitors -j 2>/dev/null) || exit 0
[ -n "$mons" ] || exit 0

sig=$(printf '%s' "$mons" | jq -c 'map({name,x,y,width,height,scale,focused})' 2>/dev/null)
[ -n "$sig" ] || exit 0

if [ -r "$CACHE" ]; then
    cached_sig=$(head -1 "$CACHE")
    cached_idx=$(sed -n '2p' "$CACHE")
    if [ "$cached_sig" = "$sig" ] && [ -n "$cached_idx" ]; then
        printf '%s\n' "$cached_idx"
        exit 0
    fi
fi

# Focused monitor's logical origin, per Hyprland.
read -r fx fy < <(printf '%s' "$mons" | jq -r 'map(select(.focused))[0] | "\(.x) \(.y)"' 2>/dev/null)
[ -n "${fx:-}" ] || exit 0

idx=$(python3 - "$fx" "$fy" <<'PY' 2>/dev/null
import sys
import gi
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk

fx, fy = int(sys.argv[1]), int(sys.argv[2])
d = Gdk.Display.get_default()
if d is None:
    sys.exit(1)
for i in range(d.get_n_monitors()):
    g = d.get_monitor(i).get_geometry()
    if g.x == fx and g.y == fy:
        print(i)
        break
PY
)

[ -n "$idx" ] || exit 0
printf '%s\n%s\n' "$sig" "$idx" > "$CACHE"
printf '%s\n' "$idx"
