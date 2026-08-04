# GTK theming

GTK was the one toolkit matugen never themed (kitty/waybar/tmux/wofi/starship/lazygit/hyprlock
are templated; GTK was not), so Thunar ran on default light Adwaita until 2026-07-15.

## What's here

`.config/gtk-3.0/settings.ini` and `.config/gtk-4.0/settings.ini` — symlinked into `~/.config/`
(same pattern as dunst/tmux/starship; matugen-generated configs like kitty/waybar are copies
instead, because matugen writes them).

```bash
ln -sfn ~/dotfiles/gtk/.config/gtk-3.0/settings.ini ~/.config/gtk-3.0/settings.ini
ln -sfn ~/dotfiles/gtk/.config/gtk-4.0/settings.ini ~/.config/gtk-4.0/settings.ini
```

## The theme itself is NOT in this repo

`gtk-theme-name=Tokyonight-Dark` lives in `~/.themes/Tokyonight-Dark` (2.7 MB of generated CSS —
a build artifact, not config). Rebuild it on a fresh machine:

```bash
sudo pacman -S --needed sassc              # only real dep for GTK3 (~8 KiB + libsass)
git clone https://github.com/Fausto-Korpsvart/Tokyo-Night-GTK-Theme.git
cd Tokyo-Night-GTK-Theme/themes
./install.sh -c dark -t default -s standard   # installs to ~/.themes
```

The README claims `murrine-engine` and `gnome-themes-extra` are required — **they are not, for
GTK3**. Both are GTK2-era; Thunar is GTK3 and uses plain CSS. (`gtk-engine-murrine` isn't even in
core/extra anymore.) `sassc` is the only thing actually needed.

## Gotchas (each cost real debugging time)

- **`@define-color` overrides do NOTHING on GTK3 Adwaita.** Verified by experiment: the window
  stayed `#2d2d2d`. Adwaita 3.24 is Sass-compiled to literal hex, so its rules never reference the
  named colors. Direct selectors *do* work (a `window { background-color: #ff00ff; }` control test
  turned the window magenta). This is why a real theme beats hand-written recolouring — half the
  dotfiles guides online recommend the `@define-color` trick and it silently fails.
- **`gtk-theme-name=Adwaita-dark` is not a valid theme** — it silently falls back to light. Use
  `gtk-theme-name=Adwaita` + `gtk-application-prefer-dark-theme=1`. (`Adwaita:dark` works only for
  the `GTK_THEME` env var, never in settings.ini.)
- **Thunar is GTK3 → reads its theme at startup only.** Icon theme applies live; the theme does
  not. `thunar -q` to restart it. `GTK_USE_PORTAL=1` live-switches GTK4/libadwaita, not GTK3.
- **Thunar is one daemon** — every window shares a pid, so `pkill thunar` closes the user's windows
  too. Check `hyprctl clients` first.
- **`sed -i` destroys symlinks** (writes a temp file and renames over it). Edit the file in this
  repo, not through the `~/.config` symlink, or use `sed --follow-symlinks`.

## Not done

- Icons are `breeze-dark`. The upstream repo also ships a Tokyo Night icon set (`icons/`) if the
  blue Breeze folders ever grate.
- Theme colors aren't sourced from `theme/matugen/config.toml`. Worth noting matugen adds nothing
  dynamic here anyway: all 17 colors are `blend = false` and `apply-theme.sh` always passes the
  same `#1a1b26`, so it emits identical output every run.
