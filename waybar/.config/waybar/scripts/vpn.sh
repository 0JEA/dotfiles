#!/usr/bin/env bash
# ~/.config/waybar/scripts/vpn.sh
# Cisco Secure Client VPN toggle + status for waybar custom module.
# Left-click connects to UofA VPN; right-click disconnects.

VPN_BIN="/opt/cisco/secureclient/bin/vpn"
VPN_HOST="vpn.ualberta.ca"

if [[ "${1:-}" == "--connect" ]]; then
    "$VPN_BIN" connect "$VPN_HOST" &
    exit 0
fi

if [[ "${1:-}" == "--disconnect" ]]; then
    "$VPN_BIN" disconnect &
    exit 0
fi

# ── Read state ───────────────────────────────────────────────────────
STATE=$("$VPN_BIN" state 2>/dev/null | grep -oE 'Connected|Disconnected' | tail -1)

if [[ "$STATE" == "Connected" ]]; then
    printf '{"text":"󰌆 VPN","tooltip":"UofA VPN connected\nRight-click to disconnect","class":"connected"}\n'
else
    printf '{"text":"󰌊 VPN","tooltip":"UofA VPN disconnected\nClick to connect","class":"disconnected"}\n'
fi
