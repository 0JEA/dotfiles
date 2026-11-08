#!/usr/bin/env bash
# Countdown timer for the eww panel.
#
#   timer.sh start <minutes> <label> [volume-pct]  -> starts a countdown, replacing any running one
#   timer.sh cancel                                -> stops the running countdown
#   timer.sh status                                -> {"active":bool,"remaining":secs,"remaining_str":"MM:SS","label":str}
#
# volume-pct (0-100, default 100) is captured at start time and baked into the
# detached alarm job via `paplay --volume` (linear 0-65536 scale, PA_VOLUME_NORM
# = 65536 = 100%). It is NOT read live when the alarm fires, so changing the
# slider after starting a countdown has no effect on that countdown.
#
# State lives in a JSON file plus a detached `sleep` process (not systemd-run:
# a plain backgrounded+disowned job survives the eww process fine and needs no
# unit bookkeeping). The state file's "pid" is that sleep's pid, so cancel can
# kill it before it fires.
set -uo pipefail

STATE="$HOME/.cache/eww-timer.json"
SOUND="/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

case "${1:-status}" in
start)
    minutes="${2:?minutes required}"
    label="${3:-Timer}"
    volume_pct="${4:-100}"
    volume=$(( volume_pct * 65536 / 100 ))
    end=$(( $(date +%s) + $(awk -v m="$minutes" 'BEGIN{printf "%d", m*60}') ))

    # Replace whatever's running.
    if [ -f "$STATE" ]; then
        oldpid=$(jq -r '.pid // empty' "$STATE" 2>/dev/null)
        [ -n "$oldpid" ] && kill "$oldpid" 2>/dev/null
    fi

    (
        sleep "$(awk -v m="$minutes" 'BEGIN{printf "%d", m*60}')"
        notify-send -a "Timer" "${label}" "Time's up!"
        paplay --volume="$volume" "$SOUND" >/dev/null 2>&1
        rm -f "$STATE"
    ) >/dev/null 2>&1 &
    pid=$!
    disown

    jq -nc --argjson end "$end" --argjson pid "$pid" --arg label "$label" \
        '{end:$end, pid:$pid, label:$label}' >"$STATE"
    ;;
cancel)
    if [ -f "$STATE" ]; then
        pid=$(jq -r '.pid // empty' "$STATE" 2>/dev/null)
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -f "$STATE"
    fi
    ;;
status | *)
    if [ ! -f "$STATE" ]; then
        echo '{"active":false,"remaining":0,"remaining_str":"","label":""}'
        exit 0
    fi

    end=$(jq -r '.end' "$STATE" 2>/dev/null)
    label=$(jq -r '.label' "$STATE" 2>/dev/null)
    now=$(date +%s)
    remaining=$(( end - now ))

    if [ "$remaining" -le 0 ]; then
        rm -f "$STATE"
        echo '{"active":false,"remaining":0,"remaining_str":"","label":""}'
        exit 0
    fi

    printf -v remaining_str "%d:%02d" $(( remaining / 60 )) $(( remaining % 60 ))
    jq -nc --argjson remaining "$remaining" --arg remaining_str "$remaining_str" \
           --arg label "$label" \
        '{active:true, remaining:$remaining, remaining_str:$remaining_str, label:$label}'
    ;;
esac
