# Package Reference

Human-readable package list organized by category.
Machine-readable lists: `pkglist-pacman.txt`, `pkglist-aur.txt`, `pkglist-npm.txt`.

---

## Base System

| Package | Notes |
|---------|-------|
| `base` | Base system |
| `base-devel` | Build tools (gcc, make, etc.) |
| `linux` | Kernel |
| `linux-firmware` | Firmware blobs |
| `amd-ucode` | AMD CPU microcode updates |
| `sudo` | Privilege escalation |
| `nano` | Fallback editor |
| `vim` | Fallback editor |
| `wget` | HTTP downloader |
| `unzip` | Archive extraction |

## Boot

| Package | Notes |
|---------|-------|
| `grub` | Bootloader |
| `efibootmgr` | EFI boot entry manager |
| `os-prober` | Detects Windows for GRUB dual-boot menu |

## Filesystem

| Package | Notes |
|---------|-------|
| `btrfs-progs` | Btrfs user-space tools |
| `snapper` | Btrfs snapshot manager |
| `zram-generator` | Compressed RAM swap (configured in post-install) |

## Networking

| Package | Notes |
|---------|-------|
| `networkmanager` | Network management daemon |
| `network-manager-applet` | Tray applet for NM |
| `iwd` | Intel wireless daemon (backend for NM wifi) |
| `wpa_supplicant` | WPA/WPA2 authentication |
| `wireless_tools` | Legacy wireless CLI tools |
| `wireguard-tools` | WireGuard VPN |
| `openvpn` | OpenVPN client |

## Wayland / Desktop Environment

| Package | Notes |
|---------|-------|
| `hyprland` | Wayland compositor |
| `hyprlock` | Screen locker |
| `hyprpolkitagent` | Polkit authentication agent for Hyprland |
| `hyprshot` | Screenshot tool |
| `uwsm` | Universal Wayland session manager |
| `xdg-desktop-portal-hyprland` | XDG portal for Hyprland (screen share, file picker) |
| `xdg-desktop-portal-gtk` | GTK XDG portal fallback |
| `xdg-utils` | XDG utility scripts |
| `qt5-wayland` | Qt5 Wayland support |
| `qt6-wayland` | Qt6 Wayland support |
| `xorg-server` | X11 server (for apps that need it) |
| `xorg-xinit` | X11 init utilities |
| `polkit-kde-agent` | Polkit agent (KDE, works in Hyprland) |

## Status Bar & Launcher

| Package | Notes |
|---------|-------|
| `waybar` | Status bar |
| `wofi` | App launcher / dmenu replacement |
| `dunst` | Notification daemon |
| `swww` | Wallpaper daemon (smooth transitions) |

## Terminal & Shell

| Package | Notes |
|---------|-------|
| `kitty` | GPU-accelerated terminal |
| `tmux` | Terminal multiplexer |
| `starship` | Cross-shell prompt |
| `bash` | (base, already in `base`) |
| `zsh` | Z shell |

## CLI Tools

| Package | Notes |
|---------|-------|
| `eza` | Modern `ls` replacement |
| `fd` | Fast `find` replacement |
| `fzf` | Fuzzy finder |
| `tree` | Directory tree viewer |
| `tealdeer` | Fast `tldr` client |
| `stow` | Symlink manager (used for dotfiles) |
| `git` | Version control |
| `git-delta` | Better git diffs |
| `lazygit` | Terminal git UI |
| `github-cli` | `gh` GitHub CLI |
| `btop` | System monitor |
| `htop` | Process viewer |
| `smartmontools` | Disk health (smartctl) |

## File Management

| Package | Notes |
|---------|-------|
| `yazi` | Terminal file manager |
| `dolphin` | GUI file manager (KDE) |
| `feh` | Image viewer / wallpaper setter |
| `fuse2` | FUSE 2.x support (AppImages) |
| `7zip` | Archive tool |

## Display / GPU

| Package | Notes |
|---------|-------|
| `vulkan-radeon` | AMD Vulkan driver (RADV) |
| `xf86-video-amdgpu` | AMD modesetting driver |
| `xf86-video-ati` | Older AMD driver (fallback) |
| `brightnessctl` | Backlight control |

## Audio

| Package | Notes |
|---------|-------|
| `pipewire` | Audio/video server |
| `pipewire-alsa` | ALSA compatibility layer |
| `pipewire-jack` | JACK compatibility layer |
| `pipewire-pulse` | PulseAudio compatibility |
| `libpulse` | PulseAudio client library |
| `wireplumber` | PipeWire session manager |
| `gst-plugin-pipewire` | GStreamer PipeWire plugin |
| `pavucontrol` | PulseAudio volume control GUI |

## Bluetooth

| Package | Notes |
|---------|-------|
| `bluez` | Bluetooth protocol stack |
| `bluez-utils` | Bluetooth CLI tools (`bluetoothctl`) |

## Printing

| Package | Notes |
|---------|-------|
| `cups` | Print server |
| `cups-pk-helper` | Polkit helper for CUPS |
| `system-config-printer` | CUPS GUI frontend |

## Fonts

| Package | Notes |
|---------|-------|
| `ttf-jetbrains-mono-nerd` | JetBrainsMono Nerd Font (used everywhere) |
| `otf-font-awesome` | Icon font |

## Clipboard

| Package | Notes |
|---------|-------|
| `cliphist` | Wayland clipboard history manager |
| `wl-clipboard` | Wayland clipboard CLI (`wl-copy`, `wl-paste`) |

## Screenshot

| Package | Notes |
|---------|-------|
| `grim` | Wayland screenshot tool |
| `slurp` | Region selector for grim |

## Security / Auth

| Package | Notes |
|---------|-------|
| `gnome-keyring` | Secret storage daemon |
| `keepassxc` | Password manager (KeePassXC) |
| `fprintd` | Fingerprint authentication daemon |

## Development

| Package | Notes |
|---------|-------|
| `clang` | C/C++ compiler (LLVM) |
| `gdb` | GNU debugger |
| `cppcheck` | C/C++ static analysis |
| `nodejs` | Node.js runtime |
| `npm` | Node package manager |
| `jdk-openjdk` | Java Development Kit |
| `gradle` | Java/JVM build tool |
| `maven` | Java project management |
| `pyright` | Python type checker / LSP |
| `python-pynvim` | Python Neovim client (for Neovim plugins) |
| `luarocks` | Lua package manager |
| `mariadb` | MySQL-compatible database server |
| `mysql-workbench` | MySQL/MariaDB GUI |
| `dbeaver` | Universal database GUI |

## Editor

| Package | Notes |
|---------|-------|
| `neovim` | Primary editor (LazyVim config) |
| `code` | VS Code (secondary) |

## Browsers

| Package | Notes |
|---------|-------|
| `firefox` | Primary browser |
| `chromium` | Secondary browser |
| `qutebrowser` | Keyboard-driven browser |

## Media

| Package | Notes |
|---------|-------|
| `mpv` | Video player |

## Productivity

| Package | Notes |
|---------|-------|
| `obsidian` | Markdown notes |
| `zathura` | PDF/document viewer |
| `zathura-pdf-poppler` | PDF backend for Zathura |

## Network Tools

| Package | Notes |
|---------|-------|
| `qbittorrent` | Torrent client |

## Power

| Package | Notes |
|---------|-------|
| `power-profiles-daemon` | CPU power profile management |

## System Utilities

| Package | Notes |
|---------|-------|
| `sddm` | Display manager (login screen) |
| `sof-firmware` | Sound Open Firmware (modern Intel/AMD sound) |

---

## AUR Packages (`pkglist-aur.txt`)

Installed via `yay`. `yay` itself is bootstrapped from source in `post-install.sh`.

| Package | Notes |
|---------|-------|
| `libfprint-git` | Fingerprint reader driver (git version) — **known broken** on ELAN 04f3:0903 ("No minutiae found"); installed anyway for future fix |
| `matugen` | Material You theme generator (generates color schemes from wallpaper) |
| `spotify` | Music streaming client |
| `vesktop` | Discord client with Vencord (better than official Discord app) |
| `where-is-my-sddm-theme-git` | Minimal SDDM theme |

---

## npm Globals (`pkglist-npm.txt`)

Installed via `npm install -g`.

| Package | Notes |
|---------|-------|
| `@google/gemini-cli` | Google Gemini CLI |
| `pyright` | Python LSP (also in pacman — npm version for global CLI use) |

---

## Not Installed by Scripts

These are managed separately or are system-specific:

| Package | Notes |
|---------|-------|
| `yay` | AUR helper — bootstrapped from source in `post-install.sh`, not in any list |
| `discord` | Official Discord app — use `vesktop` instead |
| `wpa_supplicant` | Listed in pacman but NetworkManager usually handles this via iwd |
