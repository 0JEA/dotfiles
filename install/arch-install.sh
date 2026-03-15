#!/usr/bin/env bash
# arch-install.sh — Arch Linux live USB installer
# Run from the Arch live ISO as root. Reads arch-params.env for all config.
# Usage: bash /run/archiso/bootmnt/install/arch-install.sh
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "${GREEN}==> ${NC}${BOLD}$*${NC}"; }
warn()  { echo -e "${YELLOW}==> WARNING: $*${NC}"; }
die()   { echo -e "${RED}==> ERROR: $*${NC}"; exit 1; }
hr()    { echo -e "${BOLD}────────────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# Phase 0: Find and source arch-params.env
# ---------------------------------------------------------------------------
info "Searching for arch-params.env..."
PARAMS_FILE=""
for search_dir in /run/archiso/bootmnt /media /mnt /tmp; do
    found=$(find "$search_dir" -maxdepth 4 -name arch-params.env 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        PARAMS_FILE="$found"
        break
    fi
done

if [[ -z "$PARAMS_FILE" ]]; then
    echo ""
    echo "arch-params.env not found in common mount points."
    echo "If your USB is not auto-mounted, mount it manually:"
    echo "  mkdir -p /mnt/usb && mount /dev/sdX1 /mnt/usb"
    echo "Then re-run this script."
    echo ""
    echo "Or supply values manually by setting environment variables:"
    echo "  DISK=/dev/nvme0n1 USERNAME=coke HOSTNAME=archbox \\"
    echo "  TIMEZONE=America/Chicago LOCALE=en_US.UTF-8 \\"
    echo "  bash arch-install.sh"
    echo ""
    # Allow manual env override
    [[ -n "${DISK:-}" ]] || die "arch-params.env not found and DISK not set"
else
    info "Found params: $PARAMS_FILE"
    # shellcheck source=/dev/null
    source "$PARAMS_FILE"
fi

# Set defaults for any missing params
USERNAME="${USERNAME:-coke}"
HOSTNAME="${HOSTNAME:-archlinux}"
TIMEZONE="${TIMEZONE:-America/Chicago}"
LOCALE="${LOCALE:-en_US.UTF-8}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/0JEA/dotfiles.git}"
INSTALL_SCRIPT_SOURCE="${INSTALL_SCRIPT_SOURCE:-github}"  # "github" or "usb"

# Required
[[ -n "${DISK:-}" ]] || die "DISK not set in arch-params.env (e.g. /dev/nvme0n1)"

# ---------------------------------------------------------------------------
# Phase 1: Pre-flight checks
# ---------------------------------------------------------------------------
hr
info "Pre-flight checks..."

# UEFI mode
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode. Enable UEFI in BIOS."

# Disk exists
[[ -b "$DISK" ]] || { lsblk -d -o NAME,SIZE,MODEL 2>/dev/null || true; die "Disk $DISK not found (see above)."; }

# Network
info "Checking network connectivity..."
ping -c 1 -W 5 archlinux.org &>/dev/null || die "No network. Run: systemctl start NetworkManager && nmcli device connect <iface>"

# Clock sync
timedatectl set-ntp true

info "Pre-flight passed."

# ---------------------------------------------------------------------------
# Phase 2: Show plan and confirm
# ---------------------------------------------------------------------------
hr
echo ""
echo -e "${BOLD}Installation Plan${NC}"
hr
echo -e "  Disk:          ${YELLOW}$DISK${NC}"
echo -e "  Hostname:      $HOSTNAME"
echo -e "  Username:      $USERNAME"
echo -e "  Timezone:      $TIMEZONE"
echo -e "  Locale:        $LOCALE"
echo -e "  Dotfiles:      $DOTFILES_REPO"
echo ""
echo -e "${YELLOW}WARNING: A new btrfs partition will be created in all unallocated"
echo -e "space on $DISK. Windows and existing data will NOT be touched.${NC}"
echo ""
read -rp "Type YES to proceed: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || die "Aborted by user."

# ---------------------------------------------------------------------------
# Phase 3: Partition
# ---------------------------------------------------------------------------
hr
info "Partitioning $DISK..."

# Find existing EFI partition (type EF00)
EFI_PART=$(sgdisk -p "$DISK" 2>/dev/null | awk '/EF00/ {print $1; exit}')
if [[ -n "$EFI_PART" ]]; then
    # Construct full device path (handles nvme0n1p1 vs sda1)
    if [[ "$DISK" =~ nvme|mmcblk ]]; then
        EFI_DEV="${DISK}p${EFI_PART}"
    else
        EFI_DEV="${DISK}${EFI_PART}"
    fi
    info "Found existing EFI partition: $EFI_DEV"
else
    die "No EFI partition found on $DISK. Is this a GPT/UEFI disk with Windows?"
fi

# Snapshot highest existing partition number so we can identify the new one
PREV_LAST=$(sgdisk -p "$DISK" 2>/dev/null | awk 'NR>2 {last=$1} END {print last+0}')

# Create root partition using all unallocated space
info "Creating btrfs root partition in unallocated space..."
sgdisk --largest-new=0 --typecode=0:8300 --change-name=0:"Arch Linux" "$DISK"

# Find the new partition by looking for one with a higher number than before
ROOT_PART=$(sgdisk -p "$DISK" 2>/dev/null | awk -v prev="$PREV_LAST" 'NR>2 && $1 > prev {print $1; exit}')
[[ -n "$ROOT_PART" ]] || die "Failed to find new root partition after sgdisk"

if [[ "$DISK" =~ nvme|mmcblk ]]; then
    ROOT_DEV="${DISK}p${ROOT_PART}"
else
    ROOT_DEV="${DISK}${ROOT_PART}"
fi
info "Root partition: $ROOT_DEV"

# Inform kernel of partition table changes
partprobe "$DISK"
sleep 2

# ---------------------------------------------------------------------------
# Phase 4: Format and mount btrfs with subvolumes
# ---------------------------------------------------------------------------
hr
info "Formatting $ROOT_DEV as btrfs..."
mkfs.btrfs -f -L "Arch Linux" "$ROOT_DEV"

info "Creating btrfs subvolumes..."
mount "$ROOT_DEV" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
umount /mnt

BTRFS_OPTS="noatime,compress=zstd:1,space_cache=v2"

info "Mounting subvolumes..."
mount -o "subvol=@,$BTRFS_OPTS" "$ROOT_DEV" /mnt
mkdir -p /mnt/{home,.snapshots,var/log,boot/efi}
mount -o "subvol=@home,$BTRFS_OPTS"     "$ROOT_DEV" /mnt/home
mount -o "subvol=@snapshots,$BTRFS_OPTS" "$ROOT_DEV" /mnt/.snapshots
mount -o "subvol=@var_log,$BTRFS_OPTS"  "$ROOT_DEV" /mnt/var/log
mount "$EFI_DEV" /mnt/boot/efi

info "Mounted successfully."
lsblk "$DISK"

# ---------------------------------------------------------------------------
# Phase 5: Install base system
# ---------------------------------------------------------------------------
hr
info "Running pacstrap (this will take a few minutes)..."
if grep -q 'GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    UCODE_PKG="intel-ucode"
else
    UCODE_PKG="amd-ucode"
fi
info "CPU microcode package: $UCODE_PKG"
pacstrap -K /mnt \
    base linux linux-firmware "$UCODE_PKG" \
    btrfs-progs grub efibootmgr os-prober \
    networkmanager sudo wget curl git \
    base-devel

# ---------------------------------------------------------------------------
# Phase 6: Generate fstab
# ---------------------------------------------------------------------------
hr
info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
echo ""
info "fstab:"
cat /mnt/etc/fstab

# ---------------------------------------------------------------------------
# Phase 7: Chroot configuration
# ---------------------------------------------------------------------------
hr
info "Configuring system in chroot..."

# Copy post-install.sh into new system
POST_INSTALL_DEST="/mnt/home/$USERNAME/post-install.sh"
if [[ "$INSTALL_SCRIPT_SOURCE" == "usb" ]] && [[ -n "$PARAMS_FILE" ]]; then
    USB_INSTALL_DIR="$(dirname "$PARAMS_FILE")"
    if [[ -f "$USB_INSTALL_DIR/post-install.sh" ]]; then
        mkdir -p "$(dirname "$POST_INSTALL_DEST")"
        cp "$USB_INSTALL_DIR/post-install.sh" "$POST_INSTALL_DEST"
        info "Copied post-install.sh from USB"
    else
        warn "post-install.sh not found on USB, will fetch from GitHub at firstboot"
        INSTALL_SCRIPT_SOURCE="github"
    fi
fi

arch-chroot /mnt /bin/bash -euo pipefail << CHROOT_EOF

# ---- Locale & timezone ----
echo "$LOCALE UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

# ---- Hostname ----
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << 'HOSTS'
127.0.0.1   localhost
::1         localhost
127.0.1.1   HOSTNAME_PLACEHOLDER.localdomain HOSTNAME_PLACEHOLDER
HOSTS
sed -i "s/HOSTNAME_PLACEHOLDER/$HOSTNAME/g" /etc/hosts

# ---- Root password (locked — use sudo) ----
passwd -l root

# ---- User ----
useradd -m -G wheel,audio,video,storage,optical -s /bin/bash "$USERNAME"
echo "Set a password for $USERNAME:"
passwd "$USERNAME"
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# ---- mkinitcpio: add btrfs (handles any existing MODULES content) ----
sed -i '/^MODULES=/{/btrfs/!s/)/ btrfs)/}' /etc/mkinitcpio.conf
mkinitcpio -P

# ---- GRUB (dual-boot) ----
sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=10/' /etc/default/grub
# Enable os-prober for Windows detection
grep -q 'GRUB_DISABLE_OS_PROBER' /etc/default/grub \
    && sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub \
    || echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch --recheck
grub-mkconfig -o /boot/grub/grub.cfg
grep -q 'Windows' /boot/grub/grub.cfg \
    || echo "WARNING: No Windows entry in grub.cfg — os-prober may not have detected Windows inside chroot. After first boot run: grub-mkconfig -o /boot/grub/grub.cfg"

# ---- Services ----
systemctl enable NetworkManager

# ---- Install firstboot.service ----
cat > /etc/systemd/system/firstboot.service << SERVICE
[Unit]
Description=First boot provisioning
After=network-online.target
Wants=network-online.target
ConditionPathExists=/home/$USERNAME/post-install.sh

[Service]
Type=oneshot
Environment=ARCH_USERNAME=$USERNAME
Environment=DOTFILES_REPO=$DOTFILES_REPO
ExecStart=/bin/bash /home/$USERNAME/post-install.sh
ExecStartPost=/bin/systemctl disable firstboot.service
ExecStartPost=/bin/rm -f /etc/systemd/system/firstboot.service
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable firstboot.service

CHROOT_EOF

# Fix ownership of post-install.sh and home dir after user creation
if [[ -f "$POST_INSTALL_DEST" ]]; then
    arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/post-install.sh"
    arch-chroot /mnt chmod 755 "/home/$USERNAME/post-install.sh"
fi

# If fetching from GitHub at firstboot, create a downloader stub
if [[ "$INSTALL_SCRIPT_SOURCE" == "github" ]]; then
    info "Creating post-install.sh downloader stub (will fetch from GitHub at firstboot)..."
    cat > "$POST_INSTALL_DEST" << STUB
#!/usr/bin/env bash
# Download real post-install.sh from GitHub and execute it.
# ARCH_USERNAME and DOTFILES_REPO are inherited from firstboot.service Environment= directives.
set -euo pipefail
wget -q "https://raw.githubusercontent.com/0JEA/dotfiles/main/install/post-install.sh" \
    -O /tmp/post-install-real.sh
exec bash /tmp/post-install-real.sh
STUB
    arch-chroot /mnt chown "$USERNAME:$USERNAME" "/home/$USERNAME/post-install.sh"
    arch-chroot /mnt chmod 755 "/home/$USERNAME/post-install.sh"
fi

# ---------------------------------------------------------------------------
# Phase 8: Unmount
# ---------------------------------------------------------------------------
hr
info "Unmounting filesystems..."
umount -R /mnt

hr
echo ""
echo -e "${GREEN}${BOLD}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Remove the USB drive"
echo "  2. Reboot: systemctl reboot"
echo "  3. Boot into Arch Linux — firstboot.service will run automatically"
echo "     and install all packages. Monitor progress:"
echo "       journalctl -f -u firstboot.service"
echo "  4. System reboots into SDDM when done."
echo ""
