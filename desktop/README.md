# `desktop` — application entries and default-app handling

Partly a stow package. From `~/dotfiles`:

```sh
stow desktop            # symlinks .local/bin/imv-open only
./desktop/install.sh    # copies applications/*.desktop as REAL files + rebuilds caches
```

The `.desktop` entries are deliberately NOT stowed — see `install.sh` for why, and for the
honest caveat that the symlink-vs-real-file theory is suspected rather than proven.
`.stow-local-ignore` keeps stow from linking `README.md`, `install.sh` and `applications/`
into `$HOME`.

The rationale that would normally sit as comments inside the `.desktop` files lives in this file
instead, purely so the entries stay short and diffable.

To be clear about one thing that was actually tested rather than assumed: `#` comment blocks
inside `[Desktop Entry]` are **fine** — KDE parses a commented entry and resolves it correctly.
Comments were briefly suspected of breaking Dolphin's handling and were ruled out by putting them
back and re-testing. Don't strip comments from a `.desktop` file expecting that to fix anything.

## `imv-open.desktop` + `.local/bin/imv-open`

Opens images in imv. Two problems it works around:

1. **The packaged entries are hidden.** Both `/usr/share/applications/imv.desktop` and
   `imv-dir.desktop` set `NoDisplay=true`, so they never appear in an application menu or in
   Dolphin's "Open With" list, and KDE will not accept a `NoDisplay=true` entry as a default.
   This entry is visible.

2. **imv cannot open `file://` URLs.** KDE/KIO hands applications percent-encoded URLs, and imv
   answers with `Invalid starting image: file:///...` and exits. From a file manager that looks
   exactly like double-clicking doing nothing. The `imv-open` wrapper strips the scheme and
   percent-decodes before handing the path to imv.

The wrapper also reproduces `/usr/bin/imv-dir`'s useful behaviour: given ONE image, load the whole
containing folder with that image selected, so the arrow keys page through the directory instead
of showing a single stranded picture.

`Exec` uses an absolute path by necessity: the Desktop Entry spec does not expand `~` or `$HOME`,
and a graphical session's `PATH` does not reliably include `~/.local/bin`.

## `nvim-kitty.desktop`

The packaged `nvim.desktop` is `Exec=nvim %F` with `Terminal=true`, which asks the desktop
environment to find a terminal. That needs a full DE or an xterm fallback; this is a bare Hyprland
session with neither, so double-clicking a text file with that entry does nothing. Naming kitty
explicitly removes the indirection. `kitty -e` also execs nvim directly rather than through a login
shell, so `.zshrc`'s auto-attach-to-tmux does not fire and swallow the editor.

## The one that actually broke everything: an empty `/etc/xdg/menus/`

Dolphin ignored every default and its "Open With" dialog showed a **completely empty**
application list — no GIMP, no Chromium, nothing.

This is a bare Hyprland session, so no desktop environment ever installed an
`applications.menu`, and the session sets `XDG_MENU_PREFIX=hyprland-` so KDE looked for
`hyprland-applications.menu`. KDE builds that application list from the XDG **menu**, not from
`mimeapps.list`, so with no menu file it can never list or resolve an application. Every mime
association was correct the entire time, which is exactly what made it so hard to see.

Fix (2026-08-14):

```sh
sudo pacman -S archlinux-xdg-menu
sudo ln -sf /etc/xdg/menus/arch-applications.menu /etc/xdg/menus/hyprland-applications.menu
sudo ln -sf /etc/xdg/menus/arch-applications.menu /etc/xdg/menus/applications.menu
kbuildsycoca6 --noincremental
```

Verify with `kbuildsycoca6 --menutest`, which should print many `Category/ app.desktop` lines.
Empty output means the menu is broken again. Note those symlinks are NOT package-managed, so a
future `/etc/xdg/menus` change may need them recreated.

## Gotchas when changing default applications

- **Dolphin resolves handlers through ksycoca, not `mimeapps.list` directly.** After adding or
  changing a `.desktop` file run `kbuildsycoca6 --noincremental` — the default incremental update
  keys off directory mtimes and silently skips newly stowed entries. A running Dolphin must also be
  restarted.
- **`xdg-mime default APP m1 m2 m3` is broken here.** It writes every mimetype into a single
  malformed `m1 m2 m3=app.desktop` key that matches nothing. Set one mimetype per call, or edit
  `~/.config/mimeapps.list` directly and re-query to confirm.
- **KDE rewrites `~/.config/mimeapps.list`** (sorting it and stripping comments) whenever you use
  the "Open With" dialog, so do not expect hand-written formatting to survive.
- **Beware KDE's generated `<app>-N.desktop` files.** Picking an application in the "Open With"
  dialog can create e.g. `~/.local/share/applications/imv-2.desktop` containing `Exec=imv` with no
  `%F` placeholder and `NoDisplay=true`. Such an entry launches the app with no file argument and
  is not valid as a default, so the chooser keeps reappearing even after ticking "remember".
  Delete the generated file and repoint the association.

`~/.config/mimeapps.list` itself is NOT tracked in this repo; it is owned and rewritten by KDE.
