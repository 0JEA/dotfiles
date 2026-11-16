#!/usr/bin/env bash
# Real monitor brightness over DDC/CI (VCP feature 0x10), for the panel slider.
#
#   monitor-brightness.sh get        print brightness 0-100 (cached, see below)
#   monitor-brightness.sh set <0-100>
#
# This changes the monitor's own backlight setting, the same one its OSD menu
# changes. It is separate from hypr/scripts/brightness.sh, which only dims the
# picture with a screen shader.
#
# Every ddcutil call takes ~0.7s and they all share one I2C bus, so:
# - `set` writes the wanted value to a file and returns at once. The write
#   itself runs in the background under a lock, and a queued write that has
#   been overtaken by a newer value skips itself. Dragging the slider therefore
#   sends a handful of writes, not one per step, and the last value always lands.
# - `get` answers from the cache while it is fresh, so the panel poll is not
#   hammering the bus. Changes made with the monitor's own buttons show up once
#   the cache goes stale.
set -uo pipefail

DIR="${XDG_RUNTIME_DIR:-/tmp}/monitor-brightness"
WANT="$DIR/want"       # last value asked for
CACHE="$DIR/value"     # last value known to be on the monitor (or about to be)
BUSF="$DIR/bus"        # I2C bus number, found once per boot
LOCK="$DIR/lock"
MAX_AGE=20             # seconds before `get` asks the monitor again
mkdir -p "$DIR"

bus() {
    local b
    b=$(cat "$BUSF" 2>/dev/null)
    if [ -z "$b" ]; then
        b=$(ddcutil detect --terse 2>/dev/null | sed -n 's|.*/dev/i2c-\([0-9]\+\).*|\1|p' | head -n1)
        [ -n "$b" ] && echo "$b" > "$BUSF"
    fi
    printf '%s' "$b"
}

ddc() {
    local b; b=$(bus)
    if [ -n "$b" ]; then ddcutil --bus "$b" "$@"; else ddcutil "$@"; fi
}

push_eww() {
    local helper="$HOME/.config/eww/scripts/eww-push.sh"
    [ -x "$helper" ] && "$helper" monbright "$1"
}

case "${1:-}" in
get)
    if [ -r "$CACHE" ] && [ $(( $(date +%s) - $(stat -c %Y "$CACHE") )) -lt $MAX_AGE ]; then
        cat "$CACHE"; exit 0
    fi
    # Do not queue behind a write: if the bus is busy, the cache is the answer.
    v=$(flock -w 2 "$LOCK" "$0" _read 2>/dev/null)
    if [ -n "$v" ]; then echo "$v" > "$CACHE"; printf '%s' "$v"
    else cat "$CACHE" 2>/dev/null || printf '100'; fi
    ;;
_read)
    # Internal: one read from the monitor, run under the lock by `get`.
    ddc getvcp 10 --brief 2>/dev/null | awk '$1=="VCP" {print $4; exit}'
    ;;
set)
    v="${2:-}"
    case "$v" in ''|*[!0-9.]*) exit 1 ;; esac
    v=$(awk -v x="$v" 'BEGIN {x=int(x+0.5); if (x>100) x=100; if (x<0) x=0; print x}')
    echo "$v" > "$WANT"
    echo "$v" > "$CACHE"
    push_eww "$v"
    (
        flock 9
        [ "$(cat "$WANT" 2>/dev/null)" = "$v" ] || exit 0   # overtaken by a newer value
        ddc setvcp 10 "$v" --noverify >/dev/null 2>&1
        touch "$CACHE"
    ) 9>"$LOCK" &
    ;;
*)
    echo "usage: $0 get | set <0-100>" >&2; exit 1 ;;
esac
