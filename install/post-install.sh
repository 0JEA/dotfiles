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
BASE_URL="https://raw.githubusercontent.com/0JEA/dotfiles/main/install"

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
systemctl enable bluetooth
systemctl enable cups
systemctl enable NetworkManager

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
STOW_PKGS=(bash zsh nvim hypr kitty lazygit tmux starship waybar wofi yazi btop gh dunst qutebrowser)

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
# shellcheck disable=SC2086
sudo -u "$USERNAME" npm install -g $NPM_PKGS

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

# ---------------------------------------------------------------------------
# 14. tealdeer cache update
# ---------------------------------------------------------------------------
log "Updating tldr cache..."
sudo -u "$USERNAME" tldr --update 2>/dev/null || log "  WARNING: tldr update failed (non-fatal)"

# ---------------------------------------------------------------------------
# 15. Fix git remote to use SSH (not HTTPS)
# ---------------------------------------------------------------------------
log "Switching dotfiles remote to SSH..."
sudo -u "$USERNAME" git -C "$USER_HOME/dotfiles" \
    remote set-url origin git@github.com:0JEA/dotfiles.git 2>/dev/null || true

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
