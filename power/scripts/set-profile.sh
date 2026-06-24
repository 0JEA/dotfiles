#!/usr/bin/env bash
# set-profile.sh — runs as root via sudo NOPASSWD
# Applies GPU, NVMe, and WiFi power settings for the given profile.
# CPU governor/turbo is handled by auto-cpufreq — not touched here.
#
# Usage: sudo set-profile.sh <ac|battery|critical>

set -euo pipefail

PROFILE="${1:-}"
VALID=("ac" "battery" "critical")

# Validate against allowlist — required since this runs as root via NOPASSWD
if [[ -z "$PROFILE" ]] || ! printf '%s\n' "${VALID[@]}" | grep -qx "$PROFILE"; then
    echo "Usage: $0 <ac|battery|critical>" >&2
    exit 1
fi

# ── AMD GPU power level ───────────────────────────────────────────────────────
# Dynamically find the AMD card — avoids hardcoding card0/card1
GPU_CONTROL=$(find /sys/class/drm -name "power_dpm_force_performance_level" 2>/dev/null | head -1)
if [[ -n "$GPU_CONTROL" ]]; then
    case "$PROFILE" in
        ac)                echo "auto" > "$GPU_CONTROL" ;;
        battery|critical)  echo "low"  > "$GPU_CONTROL" ;;
    esac
fi

# ── NVMe runtime power management ────────────────────────────────────────────
NVME_PM="/sys/block/nvme0n1/device/power/control"
if [[ -f "$NVME_PM" ]]; then
    case "$PROFILE" in
        ac)                echo "on"   > "$NVME_PM" ;;
        battery|critical)  echo "auto" > "$NVME_PM" ;;
    esac
fi

# ── WiFi power save ───────────────────────────────────────────────────────────
# Auto-detect wireless interface (uses iwconfig — iw not installed, system uses iwd/NM)
WIFI_IFACE=$(iwconfig 2>/dev/null | awk '/^[^ ].*ESSID/{print $1}' | head -1)
if [[ -n "$WIFI_IFACE" ]]; then
    case "$PROFILE" in
        ac)                iwconfig "$WIFI_IFACE" power off ;;
        battery|critical)  iwconfig "$WIFI_IFACE" power on  ;;
    esac
fi

# ── Write state file for waybar ───────────────────────────────────────────────
echo "$PROFILE" > /run/current-power-profile
chmod 644 /run/current-power-profile
