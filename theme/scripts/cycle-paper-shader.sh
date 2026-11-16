#!/usr/bin/env bash
# Cycle the paper screen shader: OFF -> pdf -> web -> OFF, for A/B'ing the two
# looks. Rendering, validation and the brightness hand-off all live in
# toggle-paper-shader.sh; this only decides which look comes next.
set -euo pipefail
TOGGLE="$HOME/dotfiles/theme/scripts/toggle-paper-shader.sh"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/paper-shader"
active=$(cat "$CACHE/active-paper" 2>/dev/null || true)
case "$active" in
    *paper-pdf.frag) PAPER_FORCE_ON=1 "$TOGGLE" web ;;
    *paper-web.frag) "$TOGGLE" web ;;            # same look again = off
    *)               PAPER_FORCE_ON=1 "$TOGGLE" pdf ;;
esac
