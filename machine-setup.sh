#!/usr/bin/env bash
# Point this machine at its per-machine config files.
#
#   ~/dotfiles/machine-setup.sh laptop
#   ~/dotfiles/machine-setup.sh desktop
#
# Shared configs (hyprland.conf, waybar config.jsonc, .bashrc) pull in one
# machine file each through an UNTRACKED symlink. This script creates those
# symlinks. Safe to re-run. Run it once per machine, and again after a pull that
# adds a new per-machine file.
set -euo pipefail

m="${1:-}"
case "$m" in laptop|desktop) ;; *) echo "usage: $0 <laptop|desktop>" >&2; exit 2 ;; esac
repo="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

link() {  # link <target> <linkpath>
    [ -e "$1" ] || { echo "skip   $2 (no $1)"; return 0; }
    mkdir -p "$(dirname "$2")"
    ln -sfn "$1" "$2"
    echo "linked $2 -> $1"
}

link "$repo/hypr/.config/hypr/machines/$m.conf"       "$HOME/.config/hypr/machine.conf"
link "$repo/waybar/.config/waybar/machines/$m.jsonc"  "$HOME/.config/waybar/machine.jsonc"
link "$repo/bash/machines/$m.sh"                      "$HOME/.config/bash/machine.sh"
# GTK: only machines that keep their own theme have files here (the laptop).
for v in 3.0 4.0; do
    link "$repo/gtk/machines/$m/gtk-$v/settings.ini"  "$HOME/.config/gtk-$v/settings.ini"
done

if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null && echo "hyprland reloaded; errors (empty = good):" && hyprctl configerrors
fi
