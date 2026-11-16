#!/bin/bash
# Emit Waybar JSON for caps lock state.
# Reads the kernel LED brightness — no X11/D-Bus dependency.
# Glob rather than hardcode: the inputN index varies by machine and replug.
CAPS=$(cat /sys/class/leds/*capslock/brightness 2>/dev/null | grep -qx 1 && echo 1 || echo 0)
if [ "$CAPS" = "1" ]; then
  printf '{"text":" ","class":"caps-active"}\n'
else
  printf '{"text":" ","class":""}\n'
fi
