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
| `install/packages.md` | Human-readable reference with categories |

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
- **Shell**: Zsh (primary) / Bash — both define a `gem()` function for Gemini CLI
- **Prompt**: Starship with a custom path-coloring script (`theme/scripts/starship_path.sh`)
- **Launcher**: Wofi
- **Notifications**: Dunst
- **Editor**: Neovim (LazyVim, `nvim/.config/nvim/`)

### Shell Behavior
Both `.zshrc` and `.bashrc` auto-replace the shell process with tmux on startup. Starship is the prompt for both shells.
