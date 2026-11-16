#!/usr/bin/env bash
# System readings that eww's built-in magic variables do not cover.
#
# CPU / RAM / DISK / TEMPS all come from EWW_CPU, EWW_RAM, EWW_DISK and
# EWW_TEMPS directly in the yuck, so they are deliberately NOT duplicated here.
# This script covers only the gaps: the NVIDIA GPU and the network link.
set -uo pipefail

# num() and emit_json(): see lib.sh. Every branch below MUST print valid JSON,
# because an empty poll result blanks the entire panel, not just one row.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

GPU_FALLBACK='{"available":false,"util":0,"mem_used":0,"mem_total":0,"mem_perc":0,"temp":0,"name":"gpu unavailable"}'
NET_FALLBACK='{"connected":false,"type":"none","name":"offline","device":"","icon":""}'

case "${1:-all}" in
gpu)
    # nvidia-smi is absent on the laptop (AMD) and can fail transiently while
    # the driver reloads, so every failure path still emits a complete object.
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo '{"available":false,"util":0,"mem_used":0,"mem_total":0,"mem_perc":0,"temp":0,"name":"no nvidia gpu"}'
        exit 0
    fi
    out=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name \
                     --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -z "$out" ]; then
        echo '{"available":false,"util":0,"mem_used":0,"mem_total":0,"mem_perc":0,"temp":0,"name":"gpu unavailable"}'
        exit 0
    fi
    IFS=',' read -r util mused mtotal temp name <<<"$out"
    trim() { printf '%s' "$1" | sed 's/^ *//; s/ *$//'; }
    name=$(trim "$name")
    # THE BUG: nvidia-smi prints the literal "[N/A]" for a field it cannot read,
    # jq rejects that with "invalid JSON text passed to --argjson", and the
    # script then exits having printed nothing at all -- which blanks the panel.
    # num() turns any non-numeric reading into 0 before jq ever sees it.
    util=$(num "$(trim "$util")")
    mused=$(num "$(trim "$mused")")
    mtotal=$(num "$(trim "$mtotal")")
    temp=$(num "$(trim "$temp")")
    mem_perc=$(awk -v u="$mused" -v t="$mtotal" 'BEGIN{if(t<=0)t=1; printf "%.1f", (u/t)*100}')
    mem_perc=$(num "$mem_perc")
    jq -nc --argjson util "$util" --argjson mem_used "$mused" \
           --argjson mem_total "$mtotal" --argjson mem_perc "$mem_perc" \
           --argjson temp "$temp" --arg name "${name:-gpu}" \
        '{available:true, util:$util, mem_used:$mem_used, mem_total:$mem_total,
          mem_perc:$mem_perc, temp:$temp, name:$name}' \
      | emit_json "$GPU_FALLBACK"
    ;;
net)
    # This box is ethernet-only: there is no wifi device and no bluetooth
    # controller, which is why the panel shows link STATUS rather than the
    # wifi/bluetooth toggles a laptop panel would carry.
    line=$(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device status 2>/dev/null \
           | awk -F: '$2!="loopback" && $3=="connected"' | head -1)
    if [ -z "$line" ]; then
        echo '{"connected":false,"type":"none","name":"offline","device":"","icon":"睊"}'
        exit 0
    fi
    IFS=':' read -r dev type state conn <<<"$line"
    case "$type" in
        ethernet) icon="󰈀" ;;
        wifi)     icon="󰖩" ;;
        *)        icon="󰛳" ;;
    esac
    jq -nc --arg type "$type" --arg name "${conn:-$type}" --arg device "$dev" --arg icon "$icon" \
        '{connected:true, type:$type, name:$name, device:$device, icon:$icon}' \
      | emit_json "$NET_FALLBACK"
    ;;
uptime)
    up=$(cut -d' ' -f1 /proc/uptime)
    awk -v s="$up" 'BEGIN{
        d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60);
        if(d>0) printf "up %dd %dh", d, h;
        else if(h>0) printf "up %dh %dm", h, m;
        else printf "up %dm", m;
    }'
    ;;
esac
