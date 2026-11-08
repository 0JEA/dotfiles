#!/usr/bin/env bash
# MPRIS state for the eww panel, as one JSON object per invocation (defpoll).
#
# WHY POLLING AND NOT `playerctl --follow` + deflisten:
# --follow only fires on METADATA changes. Playback position is not metadata, so
# a seek bar driven by --follow sits frozen until the track changes. Position
# needs ~1s sampling either way, so polling is the honest mechanism and the
# extra cost of one playerctl call per second is negligible.
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
MEDIA_FALLBACK='{"available":false,"status":"Stopped","title":"","artist":"","album":"","art":"","position":0,"length":0,"progress":0,"pos_str":"0:00","len_str":"0:00","player":""}'

ART_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww/art"
mkdir -p "$ART_DIR"

# Emitted whenever there is no usable player. Every key the yuck references must
# be present even in the empty case: eww throws on a missing field access, and a
# throwing poll silently blanks the whole widget tree rather than just this card.
none() {
    printf '{"available":false,"status":"Stopped","title":"","artist":"","album":"","art":"","position":0,"length":0,"progress":0,"pos_str":"0:00","len_str":"0:00","player":""}\n'
    exit 0
}

command -v playerctl >/dev/null 2>&1 || none

player=$(playerctl -l 2>/dev/null | head -1)
[ -n "$player" ] || none

status=$(playerctl -p "$player" status 2>/dev/null) || none
[ -n "$status" ] || none

title=$(playerctl -p "$player" metadata title 2>/dev/null || true)
artist=$(playerctl -p "$player" metadata artist 2>/dev/null || true)
album=$(playerctl -p "$player" metadata album 2>/dev/null || true)
arturl=$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null || true)

# mpris:length is MICROseconds; `playerctl position` is a float in SECONDS.
# Mixing the two units is the classic way to get a seek bar that is off by 10^6.
len_us=$(playerctl -p "$player" metadata mpris:length 2>/dev/null || echo 0)
[[ "$len_us" =~ ^[0-9]+$ ]] || len_us=0
pos_s=$(playerctl -p "$player" position 2>/dev/null || echo 0)
[[ "$pos_s" =~ ^[0-9.]+$ ]] || pos_s=0

len_s=$(awk -v u="$len_us" 'BEGIN{printf "%.0f", u/1000000}')
pos_i=$(awk -v p="$pos_s" 'BEGIN{printf "%.0f", p}')
if [ "$len_s" -gt 0 ] 2>/dev/null; then
    progress=$(awk -v p="$pos_i" -v l="$len_s" 'BEGIN{v=(p/l)*100; if(v>100)v=100; if(v<0)v=0; printf "%.2f", v}')
else
    progress=0
fi
fmt_time() { awk -v s="$1" 'BEGIN{printf "%d:%02d", int(s/60), int(s%60)}'; }

# Album art. Spotify hands back an https URL, so it has to be fetched and cached
# on disk before GTK can draw it.
#
# The fetch is BACKGROUNDED on purpose. This script runs on a 1s poll, and a
# stalled network would otherwise block the poll and freeze every widget bound
# to it. On a cache miss this invocation returns no art and the next poll (once
# the download lands) picks it up.
art=""
case "$arturl" in
    file://*)
        art="${arturl#file://}"
        ;;
    http://*|https://*)
        key=$(printf '%s' "$arturl" | md5sum | cut -d' ' -f1)
        f="$ART_DIR/$key"
        if [ -s "$f" ]; then
            art="$f"
        elif [ ! -e "$f.part" ]; then
            # .part doubles as an in-flight lock so a slow download is not
            # restarted by every subsequent poll.
            ( if curl -sfL --max-time 10 -o "$f.part" "$arturl"; then
                  mv -f "$f.part" "$f"
              else
                  rm -f "$f.part"
              fi ) >/dev/null 2>&1 &
        fi
        ;;
esac

jq -nc \
    --arg status "$status" \
    --arg title "${title:-Unknown}" \
    --arg artist "${artist:-}" \
    --arg album "${album:-}" \
    --arg art "$art" \
    --arg player "$player" \
    --arg pos_str "$(fmt_time "$pos_i")" \
    --arg len_str "$(fmt_time "$len_s")" \
    --argjson position "$pos_i" \
    --argjson length "$len_s" \
    --argjson progress "$progress" \
    '{available:true, status:$status, title:$title, artist:$artist, album:$album,
      art:$art, player:$player, position:$position, length:$length,
      progress:$progress, pos_str:$pos_str, len_str:$len_str}' \
  | emit_json "$MEDIA_FALLBACK"
