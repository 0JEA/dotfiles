# GTK theming

GTK is the one toolkit matugen never themes (kitty/waybar/tmux/wofi/starship/lazygit/hyprlock
are templated; GTK is not), so GTK apps ran on default light Adwaita until 2026-07-15.

> **2026-08-07 — this was laptop-only.** None of the setup below had ever been applied on the
> desktop: no `~/.themes`, no `settings.ini` symlinks, `sassc` not installed, and gsettings still
> on `Adwaita` / `color-scheme=default`. It is now applied on both, with the **Marigold** palette
> (`Gruvbox-Orange-Dark`) rather than Tokyo Night. Note the machines differ: the laptop uses
> thunar (GTK3), the desktop uses dolphin (Qt), so on the desktop the GTK apps that actually
> matter are gimp, inkscape, firefox dialogs, pavucontrol and nm-connection-editor.

## What's here

`.config/gtk-3.0/settings.ini` and `.config/gtk-4.0/settings.ini` — symlinked into `~/.config/`
(same pattern as dunst/tmux/starship; matugen-generated configs like kitty/waybar are copies
instead, because matugen writes them).

```bash
ln -sfn ~/dotfiles/gtk/.config/gtk-3.0/settings.ini ~/.config/gtk-3.0/settings.ini
ln -sfn ~/dotfiles/gtk/.config/gtk-4.0/settings.ini ~/.config/gtk-4.0/settings.ini
```

## The theme itself is NOT in this repo

`gtk-theme-name=Gruvbox-Orange-Dark` lives in `~/.themes/` (generated CSS — a build artifact, not
config). Rebuild it on a fresh machine:

```bash
sudo pacman -S --needed sassc              # only real dep for GTK3 (~8 KiB + libsass)
git clone https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git
cd Gruvbox-GTK-Theme/themes
./install.sh -c dark -t orange -s standard --tweaks black -l   # installs to ~/.themes
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Gruvbox-Orange-Dark'
```

`-t orange` picks the orange accent; `--tweaks black` darkens the base from gruvbox's default
`#282828` (a light green-grey that clashed badly with Marigold's `#1a1614`) down to `#0f0e0e`.
`-l` symlinks the gtk-4.0 theme into `~/.config/gtk-4.0` for libadwaita apps.

**This is the one surface that cannot match Marigold exactly.** The palette is authored upstream,
so it is "close warm orange", not our hexes. Getting an exact match would mean authoring a GTK
theme from scratch, which is not worth it for five apps.

Expect one harmless warning on every GTK3 app start — `Theme parsing error: gtk-dark.css:1048:16:
'border-spacing' is not a valid property name`. That is an upstream bug in the theme, not a
misconfiguration.

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

- Icons are `breeze-dark`. The upstream repo also ships a gruvbox icon set (`icons/`) if the blue
  Breeze folders ever grate against the orange.
- Theme colors aren't sourced from `theme/matugen/config.toml`. Worth noting matugen adds nothing
  dynamic here anyway: all 18 colors are `blend = false` and `apply-theme.sh` always passes the
  same base hex, so it emits identical output every run.
