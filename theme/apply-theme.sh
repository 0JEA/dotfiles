#!/bin/bash
matugen color "#1a1b26"
# Reload apps that need it
hyprctl reload
pkill -SIGUSR2 waybar
