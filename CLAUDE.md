# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal dotfiles for Arch Linux + Hyprland (Wayland). Managed with **GNU Stow** — each top-level directory maps to `$HOME` when stowed (e.g., `nvim/.config/nvim/` → `~/.config/nvim/`).

- **GitHub**: `git@github.com:0JEA/dotfiles.git`

## Common Commands

### Deploying dotfiles (via GNU Stow)
```bash
# From ~/dotfiles — stow a specific package
stow nvim
stow zsh hypr kitty tmux waybar

# Unstow a package
stow -D nvim

# Restow (remove and re-link, useful after restructuring)
stow -R nvim
```

### Theme System
```bash
# Regenerate all app themes from current wallpaper/colors
~/dotfiles/theme/apply-theme.sh
```
Matugen reads `theme/matugen/config.toml`, generates colors from a wallpaper, then renders Tera templates in `theme/templates/` for kitty, waybar, tmux, starship, lazygit, hyprlock, and wofi.

### Installation Scripts
```bash
# Run from Arch Linux live ISO (as root)
bash install/arch-install.sh

# Run after first boot (auto-run via systemd firstboot.service)
bash install/post-install.sh
```

### Package Lists
| File | Purpose |
|------|---------|
| `install/pkglist-pacman.txt` | pacman packages (`pacman -S --needed - < pkglist-pacman.txt`) |
| `install/pkglist-aur.txt` | AUR packages (`yay -S --needed - < pkglist-aur.txt`) |
| `install/pkglist-npm.txt` | Global npm packages |
| `install/pkglist-laptop.txt` | Installed by `post-install.sh` only on a laptop (chassis or battery check) |
| `install/pkglist-nvidia.txt` | Installed by `post-install.sh` only when an NVIDIA GPU is present |
| `install/packages.md` | Human-readable reference with categories |

After changing any list or `packages.md`, run `bash install/check-packages.sh`. It exits 1 if they disagree.

## Per-machine config (added 2026-11-16)

Two machines share this repo: a laptop (AMD, `eDP-1`, user `coke`) and a desktop
(NVIDIA, `DP-3` 4K, user `john`). **Never hardcode `/home/<user>` — use `$HOME`.**

Anything that depends on hardware lives in a tracked per-machine file, selected by
an UNTRACKED symlink that `machine-setup.sh <laptop|desktop>` creates:

| Shared file | Pulls in | Tracked machine files |
|---|---|---|
| `hypr/.config/hypr/hyprland.conf` | `~/.config/hypr/machine.conf` | `hypr/.config/hypr/machines/{laptop,desktop}.conf` |
| `waybar/.config/waybar/config.jsonc` | `~/.config/waybar/machine.jsonc` | `waybar/.config/waybar/machines/{laptop,desktop}.jsonc` |
| `bash/.bashrc` | `~/.config/bash/machine.sh` | `bash/machines/{laptop,desktop}.sh` |
| GTK `settings.ini` (laptop only) | symlink repointed | `gtk/machines/laptop/gtk-{3,4}.0/settings.ini` |

- Monitors, workspace pinning, `$fileManager`, brightness binds, `JAVA_TOOL_OPTIONS`
  and machine-only autostart go in the machine `.conf`, NOT in `hyprland.conf`.
- `scripts/brightness.sh` is the DESKTOP shader dimmer; the laptop binds
  `scripts/brightness-laptop.sh` (hardware backlight, then hyprsunset gamma).
- Hyprland binds accumulate, so a bind must exist in the shared file OR the machine
  files, never both.
- Check which machine a checkout is wired to: `readlink ~/.config/hypr/machine.conf`
- A missing `machine.conf` shows as a Hyprland config error; a missing
  `machine.jsonc` shows as an empty right side of the bar. Fix: run `machine-setup.sh`.

## Architecture

### Stow Package Layout
Each directory is a stow "package". The internal structure mirrors `$HOME`:
- `nvim/.config/nvim/` → `~/.config/nvim/`
- `zsh/.zshrc` → `~/.zshrc`
- `hypr/.config/hypr/` → `~/.config/hypr/`

### Theme Pipeline
`apply-theme.sh` → **Matugen** (Material You generator) → renders **Tera templates** → writes final configs for each app. Modifying a themed app's config means editing the `.tera` template in `theme/templates/`, not the output config directly.

### Desktop Environment Stack
- **WM**: Hyprland (config: `hypr/.config/hypr/hyprland.conf`)
- **Bar**: Waybar (config + scripts: `waybar/.config/waybar/`)
- **Terminal**: Kitty → auto-attaches to tmux on shell init
- **Shell**: Zsh (primary) / Bash
- **Prompt**: Starship with a custom path-coloring script (`theme/scripts/starship_path.sh`)
- **Launcher**: Wofi
- **Notifications**: Dunst
- **Editor**: Neovim (LazyVim, `nvim/.config/nvim/`)

### Shell Behavior
Both `.zshrc` and `.bashrc` auto-replace the shell process with tmux on startup. Starship is the prompt for both shells.
