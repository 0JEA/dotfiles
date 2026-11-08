#!/usr/bin/env bash
# post-install.sh — First-boot provisioning script
# Run automatically by firstboot.service (as root) on first Arch boot.
# Installs all packages, clones dotfiles, stows configs, then reboots into SDDM.
set -euo pipefail

LOG_TAG="firstboot"
log()  { echo "[$LOG_TAG] $*" | tee /dev/kmsg 2>/dev/null || echo "[$LOG_TAG] $*"; }
die()  { log "ERROR: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Resolve username — set by arch-install.sh via arch-params.env baked into
# firstboot.service, or fall back to the first non-root user with a home dir.
# ---------------------------------------------------------------------------
USERNAME="${ARCH_USERNAME:-}"
if [[ -z "$USERNAME" ]]; then
    USERNAME=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
fi
[[ -n "$USERNAME" ]] || die "Could not determine target username"
USER_HOME="/home/$USERNAME"
log "Provisioning for user: $USERNAME (home: $USER_HOME)"

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/0JEA/dotfiles.git}"
# Derive raw GitHub content URL from DOTFILES_REPO so forks work automatically
if [[ "$DOTFILES_REPO" =~ ^https://github\.com/([^/]+)/([^/]+?)(\.git)?$ ]]; then
    BASE_URL="https://raw.githubusercontent.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/main/install"
else
    BASE_URL="https://raw.githubusercontent.com/0JEA/dotfiles/main/install"
fi

# ---------------------------------------------------------------------------
# 1. Full system update
# ---------------------------------------------------------------------------
log "Syncing and updating packages..."
pacman -Syu --noconfirm

# ---------------------------------------------------------------------------
# 2. Fetch latest package lists from GitHub
# ---------------------------------------------------------------------------
log "Fetching package lists from GitHub..."
wget -q "$BASE_URL/pkglist-pacman.txt" -O /tmp/pkglist-pacman.txt
wget -q "$BASE_URL/pkglist-aur.txt"    -O /tmp/pkglist-aur.txt
wget -q "$BASE_URL/pkglist-npm.txt"    -O /tmp/pkglist-npm.txt

# ---------------------------------------------------------------------------
# 3. Install pacman packages
# ---------------------------------------------------------------------------
log "Installing pacman packages..."
pacman -S --needed --noconfirm - < /tmp/pkglist-pacman.txt

# ---------------------------------------------------------------------------
# 3a. Set default shell to zsh
# ---------------------------------------------------------------------------
log "Setting default shell to zsh..."
chsh -s /usr/bin/zsh "$USERNAME"

# ---------------------------------------------------------------------------
# 4. Configure zram
# ---------------------------------------------------------------------------
log "Configuring zram..."
mkdir -p /etc/systemd
cat > /etc/systemd/zram-generator.conf << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
EOF

# ---------------------------------------------------------------------------
# 5. Enable system services
# ---------------------------------------------------------------------------
log "Enabling system services..."
systemctl enable sddm
systemctl enable cups
systemctl enable NetworkManager

# snapper: create root config and enable timers
if pacman -Qq snapper &>/dev/null; then
    snapper -c root create-config / 2>/dev/null \
        || log "  WARNING: snapper root config failed (may already exist)"
    systemctl enable snapper-timeline.timer snapper-cleanup.timer
fi

# User services: enable pipewire + wireplumber via systemd user symlinks
# (user session is not running yet, so we create the enable symlinks directly)
log "Enabling user services (pipewire, wireplumber)..."
USER_WANTS_DIR="$USER_HOME/.config/systemd/user/default.target.wants"
sudo -u "$USERNAME" mkdir -p "$USER_WANTS_DIR"
for svc in pipewire.service pipewire-pulse.service wireplumber.service; do
    [[ -f "/usr/lib/systemd/user/$svc" ]] && \
        sudo -u "$USERNAME" ln -sf "/usr/lib/systemd/user/$svc" "$USER_WANTS_DIR/$svc"
done

# ---------------------------------------------------------------------------
# 6. Build and install yay (as user, not root)
# ---------------------------------------------------------------------------
log "Building yay from AUR..."
rm -rf /tmp/yay
sudo -u "$USERNAME" git clone https://aur.archlinux.org/yay.git /tmp/yay
sudo -u "$USERNAME" bash -c "cd /tmp/yay && makepkg -si --noconfirm"

# ---------------------------------------------------------------------------
# 7. Install AUR packages
# ---------------------------------------------------------------------------
log "Installing AUR packages..."
AUR_PKGS=$(tr '\n' ' ' < /tmp/pkglist-aur.txt)
# shellcheck disable=SC2086
sudo -u "$USERNAME" yay -S --needed --noconfirm $AUR_PKGS

# Install one hardware-specific list from GitHub. Repo packages go through
# pacman as root; only AUR ones need yay.
install_list() {
    local name=$1 p
    local repo=() aur=()
    wget -q "$BASE_URL/$name" -O "/tmp/$name"
    while read -r p; do
        [[ -z "$p" ]] && continue
        if pacman -Si "$p" &>/dev/null; then repo+=("$p"); else aur+=("$p"); fi
    done < "/tmp/$name"
    if [[ ${#repo[@]} -gt 0 ]]; then
        pacman -S --needed --noconfirm "${repo[@]}"
    fi
    if [[ ${#aur[@]} -gt 0 ]]; then
        sudo -u "$USERNAME" yay -S --needed --noconfirm "${aur[@]}"
    fi
}

# Laptop-only hardware packages (Wi-Fi, Bluetooth, backlight, AMD graphics).
# Laptop = hostnamectl says so, or any battery is present.
CHASSIS=$(hostnamectl chassis 2>/dev/null || true)
HAS_BATTERY=0
for t in /sys/class/power_supply/*/type; do
    [[ -r "$t" && "$(cat "$t")" == "Battery" ]] && HAS_BATTERY=1
done
if [[ "$CHASSIS" =~ ^(laptop|convertible|tablet)$ ]] || [[ $HAS_BATTERY -eq 1 ]]; then
    log "Laptop detected (chassis=${CHASSIS:-unknown}), installing pkglist-laptop.txt..."
    install_list pkglist-laptop.txt
    systemctl enable bluetooth
    systemctl enable power-profiles-daemon
else
    log "Not a laptop (chassis=${CHASSIS:-unknown}), skipping pkglist-laptop.txt"
fi

# NVIDIA driver, only when an NVIDIA display card is present (PCI vendor 0x10de,
# class 0x03xxxx). Read from sysfs so it doesn't need pciutils.
HAS_NVIDIA=0
for d in /sys/bus/pci/devices/*; do
    [[ "$(cat "$d/vendor" 2>/dev/null)" == "0x10de" && "$(cat "$d/class" 2>/dev/null)" == 0x03* ]] && HAS_NVIDIA=1
done
if [[ $HAS_NVIDIA -eq 1 ]]; then
    log "NVIDIA GPU detected, installing pkglist-nvidia.txt..."
    install_list pkglist-nvidia.txt
else
    log "No NVIDIA GPU, skipping pkglist-nvidia.txt"
fi

# ---------------------------------------------------------------------------
# 8. SDDM theme configuration
# ---------------------------------------------------------------------------
log "Configuring SDDM theme..."
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=where_is_my_sddm_theme
EOF

# ---------------------------------------------------------------------------
# 9. Clone dotfiles
# ---------------------------------------------------------------------------
log "Cloning dotfiles..."
if [[ -d "$USER_HOME/dotfiles" ]]; then
    log "dotfiles already present, skipping clone"
else
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" "$USER_HOME/dotfiles"
fi

# ---------------------------------------------------------------------------
# 10. Stow all config packages
# ---------------------------------------------------------------------------
log "Stowing dotfiles..."
STOW_PKGS=(bash zsh nvim hypr kitty lazygit tmux starship waybar wofi yazi btop gh dunst qutebrowser eww)
# Stowed with --no-folding: ~/.config/gtk-3.0 must stay a real directory, or GTK
# writes bookmarks and other state into the repo.
NO_FOLD_PKGS=(gtk)

# Ensure stow target dirs exist
sudo -u "$USERNAME" mkdir -p "$USER_HOME/.config"

for pkg in "${STOW_PKGS[@]}"; do
    if [[ -d "$USER_HOME/dotfiles/$pkg" ]]; then
        sudo -u "$USERNAME" bash -c "cd '$USER_HOME/dotfiles' && stow --target='$USER_HOME' '$pkg'" \
            && log "  stowed: $pkg" \
            || log "  WARNING: stow failed for $pkg (conflicts?)"
    else
        log "  SKIP: $pkg directory not found in dotfiles"
    fi
done
for pkg in "${NO_FOLD_PKGS[@]}"; do
    if [[ -d "$USER_HOME/dotfiles/$pkg" ]]; then
        sudo -u "$USERNAME" bash -c "cd '$USER_HOME/dotfiles' && stow --no-folding --target='$USER_HOME' '$pkg'" \
            && log "  stowed: $pkg (no folding)" \
            || log "  WARNING: stow failed for $pkg (conflicts?)"
    else
        log "  SKIP: $pkg directory not found in dotfiles"
    fi
done

# Make waybar scripts executable
chmod +x "$USER_HOME/dotfiles/waybar/.config/waybar/scripts/"*.sh 2>/dev/null || true

# ---------------------------------------------------------------------------
# 11. matugen config symlink
# ---------------------------------------------------------------------------
log "Setting up matugen config symlink..."
MATUGEN_CONF_DIR="$USER_HOME/.config/matugen"
MATUGEN_DOTFILES_CONF="$USER_HOME/dotfiles/theme/matugen/config.toml"
if [[ -f "$MATUGEN_DOTFILES_CONF" ]]; then
    sudo -u "$USERNAME" mkdir -p "$MATUGEN_CONF_DIR"
    sudo -u "$USERNAME" ln -sf "$MATUGEN_DOTFILES_CONF" "$MATUGEN_CONF_DIR/config.toml"
    log "  matugen config symlinked"
else
    log "  SKIP: matugen config not found at $MATUGEN_DOTFILES_CONF"
fi

# ---------------------------------------------------------------------------
# 12. npm global packages
# ---------------------------------------------------------------------------
log "Installing npm global packages..."
NPM_PKGS=$(tr '\n' ' ' < /tmp/pkglist-npm.txt)
# Install as root → lands in /usr/local/lib/node_modules, on PATH for all users
# shellcheck disable=SC2086
npm install -g $NPM_PKGS

# ---------------------------------------------------------------------------
# 13. Tmux Plugin Manager
# ---------------------------------------------------------------------------
log "Installing TPM (Tmux Plugin Manager)..."
TPM_DIR="$USER_HOME/.tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
    sudo -u "$USERNAME" git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    log "  TPM already present, skipping"
fi
log "  Installing TPM plugins..."
sudo -u "$USERNAME" TMUX_PLUGIN_MANAGER_PATH="$USER_HOME/.tmux/plugins" \
    "$TPM_DIR/bin/install_plugins" 2>/dev/null \
    || log "  WARNING: TPM plugin auto-install failed — run prefix+I manually in tmux"

# ---------------------------------------------------------------------------
# 14. tealdeer cache update
# ---------------------------------------------------------------------------
log "Updating tldr cache..."
sudo -u "$USERNAME" tldr --update 2>/dev/null || log "  WARNING: tldr update failed (non-fatal)"

# ---------------------------------------------------------------------------
# 14a. Generate SSH key
# ---------------------------------------------------------------------------
log "Generating SSH key for $USERNAME..."
if [[ ! -f "$USER_HOME/.ssh/id_ed25519" ]]; then
    sudo -u "$USERNAME" mkdir -p "$USER_HOME/.ssh"
    sudo -u "$USERNAME" chmod 700 "$USER_HOME/.ssh"
    sudo -u "$USERNAME" ssh-keygen -t ed25519 -C "$USERNAME@$(hostname)" \
        -N "" -f "$USER_HOME/.ssh/id_ed25519"
    log "  SSH key generated. Add the public key to GitHub before your first push:"
    log "  $(cat "$USER_HOME/.ssh/id_ed25519.pub")"
else
    log "  SSH key already exists, skipping"
fi

# ---------------------------------------------------------------------------
# 15. Fix git remote to use SSH (not HTTPS)
# ---------------------------------------------------------------------------
log "Switching dotfiles remote to SSH..."
SSH_REMOTE=$(echo "$DOTFILES_REPO" | sed 's|https://github\.com/|git@github.com:|; s|\.git$||').git
sudo -u "$USERNAME" git -C "$USER_HOME/dotfiles" \
    remote set-url origin "$SSH_REMOTE" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log ""
log "============================================================"
log "  First-boot provisioning complete!"
log "============================================================"
log ""
log "After SDDM login, run the following manually:"
log "  cd ~/dotfiles && bash theme/apply-theme.sh"
log "  tmux → prefix+I  (install tmux plugins via TPM)"
log ""
log "Rebooting into SDDM in 5 seconds..."
sleep 5
systemctl reboot
