#!/usr/bin/env bash
# ~/.config/waybar/scripts/battery-power.sh
# Outputs battery % + power profile info as JSON for waybar custom module.
# Pass --toggle to cycle the power profile.

set -euo pipefail

# Take the first BAT* entry when multiple batteries are present (e.g. BAT0/BAT1).
BATTERY_PATH=$(find /sys/class/power_supply -maxdepth 1 -name 'BAT*' | sort | head -1)
# No battery means this is a desktop or AC-only machine; output a static AC indicator.
[[ -z "$BATTERY_PATH" ]] && { printf '{"text":"󱉞 AC","tooltip":"No battery","class":"ac","percentage":100}\n'; exit 0; }

# ── Toggle mode ──────────────────────────────────────────────────────
if [[ "${1:-}" == "--toggle" ]]; then
    CURRENT=$(powerprofilesctl get)

    # Parse only the three profiles relevant to the cycle; the grep anchors on
    # leading whitespace to avoid matching lines that contain these words as
    # part of a longer string (e.g. driver names in verbose output).
    AVAILABLE=$(powerprofilesctl list | grep -E '^\s+(performance|balanced|power-saver):' \
        | awk '{gsub(/:$/,"",$1); print $1}')

    # Desired cycle order — not all systems expose all three profiles, so
    # FILTERED holds only those actually available on this machine.
    CYCLE=("performance" "balanced" "power-saver")
    FILTERED=()
    for p in "${CYCLE[@]}"; do
        # grep -q "^${p}$" matches the full line to avoid partial matches
        # (e.g. "power-saver" matching a hypothetical "ultra-power-saver").
        if echo "$AVAILABLE" | grep -q "^${p}$"; then
            FILTERED+=("$p")
        fi
    done

    # Nothing to cycle — powerprofilesctl may not be running or all profiles
    # are missing. Exit without error so waybar silently skips the click.
    [[ ${#FILTERED[@]} -eq 0 ]] && exit 1

    # Default to the first profile in case CURRENT is not in FILTERED (e.g.
    # the active profile is an unlisted vendor-specific mode).
    NEXT="${FILTERED[0]}"
    for i in "${!FILTERED[@]}"; do
        if [[ "${FILTERED[$i]}" == "$CURRENT" ]]; then
            # Wrap-around modulo advances to the next profile and loops back
            # from the last entry to the first.
            NEXT_IDX=$(( (i + 1) % ${#FILTERED[@]} ))
            NEXT="${FILTERED[$NEXT_IDX]}"
            break
        fi
    done
    powerprofilesctl set "$NEXT"
    exit 0
fi

# ── Read state ───────────────────────────────────────────────────────
# grep filters out stray non-numeric content that some kernels write to the
# capacity file (e.g. newline artifacts); falls back to 0 on read failure.
CAPACITY=$(cat "${BATTERY_PATH}/capacity" 2>/dev/null | grep -E '^[0-9]+$' || echo "0")
STATUS=$(cat "${BATTERY_PATH}/status" 2>/dev/null || echo "Unknown")
PROFILE=$(powerprofilesctl get 2>/dev/null || echo "balanced")

# ── Battery icon (based on charge level) ────────────────────────────
# Nerd Font battery glyphs come in two parallel sets: one for discharging
# (plain outlines) and one for charging (lightning bolt overlay). The icon
# tiers match the segment lines on a real battery gauge icon.
if [[ "$STATUS" == "Full" ]]; then
    BAT_ICON="󰁹"                          # fully charged, plug connected
elif [[ "$STATUS" == "Charging" ]]; then
    # Charging glyphs: each threshold corresponds to a filled segment count.
    if   [[ "$CAPACITY" -le 10 ]]; then BAT_ICON="󰢜"   # 1 bar + bolt
    elif [[ "$CAPACITY" -le 20 ]]; then BAT_ICON="󰂆"   # 2 bars + bolt
    elif [[ "$CAPACITY" -le 40 ]]; then BAT_ICON="󰂇"   # 3 bars + bolt
    elif [[ "$CAPACITY" -le 60 ]]; then BAT_ICON="󰂈"   # 4 bars + bolt
    elif [[ "$CAPACITY" -le 80 ]]; then BAT_ICON="󰂊"   # 5 bars + bolt
    else                                  BAT_ICON="󰂅"  # 6 bars + bolt (~full)
    fi
elif [[ "$CAPACITY" -le 10 ]]; then BAT_ICON="󰁺"       # discharging: 1 bar
elif [[ "$CAPACITY" -le 20 ]]; then BAT_ICON="󰁻"       # discharging: 2 bars
elif [[ "$CAPACITY" -le 40 ]]; then BAT_ICON="󰁽"       # discharging: 3 bars
elif [[ "$CAPACITY" -le 60 ]]; then BAT_ICON="󰁿"       # discharging: 4 bars
elif [[ "$CAPACITY" -le 80 ]]; then BAT_ICON="󰂁"       # discharging: 5 bars
else                                BAT_ICON="󰁹"        # discharging: full
fi

# ── Power profile icon ───────────────────────────────────────────────
case "$PROFILE" in
    performance) PROFILE_ICON="󱐋" ;;
    balanced)    PROFILE_ICON="󰾅" ;;
    power-saver) PROFILE_ICON="󰾆" ;;
    *)           PROFILE_ICON="󰾅" ;;  # unknown profile falls back to balanced glyph
esac

# ── CSS classes ──────────────────────────────────────────────────────
# Start with the profile name as the primary class (matches .performance,
# .balanced, .power-saver rules in style.css). Append "critical" as a
# second class when battery is low and not actively charging so that both
# the profile color and the critical background override can compose.
CSS_CLASS="$PROFILE"
if [[ "$CAPACITY" -le 15 && "$STATUS" != "Charging" ]]; then
    CSS_CLASS="${CSS_CLASS} critical"
fi

# ── JSON output ──────────────────────────────────────────────────────
# Waybar parses "text", "tooltip", "class", and "percentage" from this JSON.
# "class" may be a space-separated list; waybar applies each word as a CSS class.
printf '{"text": "%s%% %s %s", "tooltip": "%s%% · %s\\nProfile: %s", "class": "%s", "percentage": %s}\n' \
    "$CAPACITY" "$BAT_ICON" "$PROFILE_ICON" \
    "$CAPACITY" "$STATUS" "$PROFILE" \
    "$CSS_CLASS" "$CAPACITY"
