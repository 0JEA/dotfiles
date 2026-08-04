#!/bin/bash
# Emit Waybar JSON for caps lock state.
# Reads the kernel LED brightness — no X11/D-Bus dependency.
CAPS=$(cat /sys/class/leds/input3::capslock/brightness 2>/dev/null || echo 0)
if [ "$CAPS" = "1" ]; then
  printf '{"text":" ","class":"caps-active"}\n'
else
  printf '{"text":" ","class":""}\n'
fi
