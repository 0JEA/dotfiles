#!/usr/bin/env bash
# dunst's notification history, reshaped for the eww panel.
#
# This script is the reason the panel does NOT need swaync. dunst exposes its
# full history as structured JSON over dunstctl, so eww can own the notification
# centre and dunst stays the daemon that draws the popups.
#
# Subcommands:
#   list   -> JSON array of recent notifications (default)
#   count  -> integer, how many are in history
#   clear  -> empty the history
set -uo pipefail

# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

LIMIT=30

cmd="${1:-list}"

case "$cmd" in
clear)
    dunstctl history-clear 2>/dev/null
    exit 0
    ;;
count)
    dunstctl history 2>/dev/null | jq -r '.data[0] | length' 2>/dev/null || echo 0
    exit 0
    ;;
esac

# dunst stamps notifications with CLOCK_MONOTONIC MICROseconds (time since boot),
# NOT a unix epoch. Treating them as epoch yields "56 years ago" on every row.
# /proc/uptime is the matching monotonic clock, so ages are computed against it.
up=$(cut -d' ' -f1 /proc/uptime 2>/dev/null || echo 0)

dunstctl history 2>/dev/null | jq -c --argjson up "$up" --argjson limit "$LIMIT" '
  def ago(sec):
    if   sec < 0    then "now"
    elif sec < 60   then "now"
    elif sec < 3600 then "\((sec/60)|floor)m ago"
    elif sec < 86400 then "\((sec/3600)|floor)h ago"
    else "\((sec/86400)|floor)d ago"
    end;
  # dunst bodies may carry pango/HTML markup. eww renders label text literally,
  # so raw tags would show up as visible "<b>" noise.
  def strip: gsub("<[^>]*>"; "") | gsub("&amp;";"&") | gsub("&lt;";"<") | gsub("&gt;";">");
  # Word-wrap here rather than in the widget. GTK ellipsises these labels no
  # matter what: :limit-width ellipsises, and dropping it does not make :wrap
  # work either, because the label requests its natural width and there is
  # nothing to wrap against (:truncate false does not change this -- all three
  # were rendered and checked). Wrapping the text itself is the one approach
  # that survives. The widths match the card inside the 380px rail at 11-12px.
  def wrap($n):
    if . == "" then "" else
      ( [splits(" +")]
        | reduce .[] as $w ([];
            if (length == 0) then [$w]
            elif ((.[-1] | length) + 1 + ($w | length)) <= $n
              then (.[0:-1] + [.[-1] + " " + $w])
              else (. + [$w]) end)
        | join("\n") )
    end;
  [ .data[0][]
    | { id:      .id.data,
        app:     (.appname.data // "" | strip),
        summary: (.summary.data // "" | strip | wrap(38)),
        body:    (.body.data // "" | strip | gsub("\n"; "  ") | wrap(42)),
        urgency: (.urgency.data // "NORMAL"),
        icon:    (.icon_path.data // ""),
        age:     ago($up - ((.timestamp.data // 0) / 1000000))
      }
  ] | .[0:$limit]
' 2>/dev/null | emit_json '[]'
