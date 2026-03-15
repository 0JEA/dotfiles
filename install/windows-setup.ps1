#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Arch Linux dual-boot setup — Windows side.
    Shrinks a Windows partition, downloads Arch ISO, writes it to USB,
    copies install scripts, and optionally sets UEFI to boot USB next restart.

.NOTES
    Run from an elevated PowerShell prompt (right-click → Run as Administrator).
    Requires Windows 10/11 with UEFI firmware.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Defaults (edit these or override interactively)
# ---------------------------------------------------------------------------
$DEFAULT_LINUX_GB    = 200
$DEFAULT_USERNAME    = 'coke'
$DEFAULT_HOSTNAME    = 'archlinux'
$DEFAULT_TIMEZONE    = 'America/Chicago'
$DEFAULT_LOCALE      = 'en_US.UTF-8'
$DEFAULT_DOTFILES    = 'https://github.com/0JEA/dotfiles.git'
$ARCH_ISO_URL        = 'https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso'
$ARCH_ISO_FILENAME   = 'archlinux-x86_64.iso'
$SCRIPT_DIR          = Split-Path -Parent $MyInvocation.MyCommand.Path

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------
function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Text)
    Write-Host "  ==> " -NoNewline -ForegroundColor Green
    Write-Host $Text
}

function Write-Warning2 {
    param([string]$Text)
    Write-Host "  [!] " -NoNewline -ForegroundColor Yellow
    Write-Host $Text -ForegroundColor Yellow
}

function Read-Choice {
    param([string]$Prompt, [string]$Default = '')
    $display = if ($Default) { "$Prompt [$Default]: " } else { "${Prompt}: " }
    $input = Read-Host $display
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input.Trim()
}

function Read-Int {
    param([string]$Prompt, [int]$Default, [int]$Min = 1, [int]$Max = [int]::MaxValue)
    while ($true) {
        $raw = Read-Choice -Prompt $Prompt -Default "$Default"
        if ($raw -match '^\d+$') {
            $val = [int]$raw
            if ($val -ge $Min -and $val -le $Max) { return $val }
        }
        Write-Host "  Please enter a number between $Min and $Max." -ForegroundColor Red
    }
}

# ---------------------------------------------------------------------------
# Step 1: Select disk to shrink
# ---------------------------------------------------------------------------
Write-Header "Step 1: Select disk to shrink"
$allDisks = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' }

Write-Host "  Available disks:" -ForegroundColor White
$idx = 0
foreach ($d in $allDisks) {
    $sizeGB = [math]::Round($d.Size / 1GB, 1)
    Write-Host ("  [{0}] Disk {1} — {2} — {3} GB — {4}" -f $idx, $d.DiskNumber, $d.FriendlyName, $sizeGB, $d.PartitionStyle)
    $idx++
}
Write-Host ""
$diskChoice = Read-Int -Prompt "  Select disk number (0-$($allDisks.Count - 1))" -Default 0 -Min 0 -Max ($allDisks.Count - 1)
$targetDisk = $allDisks[$diskChoice]
Write-Step "Selected: Disk $($targetDisk.DiskNumber) — $($targetDisk.FriendlyName)"

# ---------------------------------------------------------------------------
# Step 2: Select partition to shrink
# ---------------------------------------------------------------------------
Write-Header "Step 2: Select partition to shrink"
$partitions = Get-Partition -DiskNumber $targetDisk.DiskNumber | Where-Object { $_.Type -ne 'Unknown' -and $_.Size -gt 1GB }

Write-Host "  Partitions on disk $($targetDisk.DiskNumber):" -ForegroundColor White
$pidx = 0
foreach ($p in $partitions) {
    $sizeGB  = [math]::Round($p.Size / 1GB, 1)
    $letter  = if ($p.DriveLetter) { "($($p.DriveLetter):)" } else { "(no letter)" }
    $label   = try { (Get-Volume -Partition $p -ErrorAction SilentlyContinue).FileSystemLabel } catch { "" }
    Write-Host ("  [{0}] Partition {1} — {2} GB — {3} {4}" -f $pidx, $p.PartitionNumber, $sizeGB, $letter, $label)
    $pidx++
}
Write-Host ""
$partChoice = Read-Int -Prompt "  Select partition to shrink (default: 0 — usually C:)" -Default 0 -Min 0 -Max ($partitions.Count - 1)
$targetPart = $partitions[$partChoice]
Write-Step "Selected: Partition $($targetPart.PartitionNumber) ($($targetPart.DriveLetter):)"

# ---------------------------------------------------------------------------
# Step 3: How much space for Linux
# ---------------------------------------------------------------------------
Write-Header "Step 3: Allocate space for Linux"
$currentSizeGB = [math]::Round($targetPart.Size / 1GB, 1)
Write-Host "  Current partition size: $currentSizeGB GB" -ForegroundColor White

# Get supported resize range
$sizeRange = Get-PartitionSupportedSize -DiskNumber $targetDisk.DiskNumber -PartitionNumber $targetPart.PartitionNumber
$minPartGB  = [math]::Ceiling($sizeRange.SizeMin / 1GB)
$maxPartGB  = [math]::Floor($sizeRange.SizeMax / 1GB)
$maxLinuxGB = $maxPartGB - 100  # Keep at least 100GB for Windows

if ($maxLinuxGB -lt 20) {
    Write-Warning2 "Not enough free space on partition to safely shrink (need at least 100 GB remaining for Windows)."
    Write-Host "  Current partition: $currentSizeGB GB, minimum safe Windows size: 100 GB"
    Write-Host "  Maximum allocatable for Linux: $maxLinuxGB GB"
    exit 1
}

Write-Host "  Maximum allocatable for Linux: $maxLinuxGB GB (keeps 100 GB for Windows)" -ForegroundColor Green
Write-Host ""
$linuxGB = Read-Int -Prompt "  GB to allocate for Linux" -Default $DEFAULT_LINUX_GB -Min 20 -Max $maxLinuxGB
Write-Step "Allocating $linuxGB GB for Linux"

# ---------------------------------------------------------------------------
# Step 4: USB drive for Arch ISO
# ---------------------------------------------------------------------------
Write-Header "Step 4: Select USB drive for Arch ISO"
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' }

$skipUSB = $false
if ($usbDisks.Count -eq 0) {
    Write-Warning2 "No USB drives detected."
    $ans = Read-Choice -Prompt "  Skip USB write? (you'll write the ISO yourself) [y/N]" -Default 'n'
    if ($ans -match '^[Yy]') { $skipUSB = $true }
    else { Write-Host "  Please insert a USB drive (8 GB+) and re-run."; exit 1 }
} else {
    Write-Host "  Available USB drives:" -ForegroundColor White
    $uidx = 0
    foreach ($u in $usbDisks) {
        $sizeGB = [math]::Round($u.Size / 1GB, 1)
        Write-Host ("  [{0}] Disk {1} — {2} — {3} GB" -f $uidx, $u.DiskNumber, $u.FriendlyName, $sizeGB)
        $uidx++
    }
    Write-Host ""
    Write-Warning2 "ALL DATA ON THE SELECTED USB WILL BE DESTROYED."
    $usbChoice = Read-Int -Prompt "  Select USB drive" -Default 0 -Min 0 -Max ($usbDisks.Count - 1)
    $targetUSB = $usbDisks[$usbChoice]
    Write-Step "Selected USB: Disk $($targetUSB.DiskNumber) — $($targetUSB.FriendlyName)"
}

# ---------------------------------------------------------------------------
# Step 5: System configuration
# ---------------------------------------------------------------------------
Write-Header "Step 5: System configuration"
$cfgHostname  = Read-Choice -Prompt "  Hostname"  -Default $DEFAULT_HOSTNAME
$cfgUsername  = Read-Choice -Prompt "  Username"  -Default $DEFAULT_USERNAME
$cfgTimezone  = Read-Choice -Prompt "  Timezone"  -Default $DEFAULT_TIMEZONE
$cfgLocale    = Read-Choice -Prompt "  Locale"    -Default $DEFAULT_LOCALE

# ---------------------------------------------------------------------------
# Step 6: UEFI boot entry
# ---------------------------------------------------------------------------
Write-Header "Step 6: UEFI boot entry"
$addUefiBoot = $false
if (-not $skipUSB) {
    Write-Host "  Adding a UEFI boot entry will make the USB boot on next restart only." -ForegroundColor White
    $ans = Read-Choice -Prompt "  Add UEFI boot entry to boot USB next restart? [y/N]" -Default 'n'
    $addUefiBoot = ($ans -match '^[Yy]')
}

# ---------------------------------------------------------------------------
# Confirmation screen
# ---------------------------------------------------------------------------
Write-Header "Confirmation"
Write-Host "  Disk to shrink:      Disk $($targetDisk.DiskNumber) — $($targetDisk.FriendlyName)" -ForegroundColor White
Write-Host "  Partition to shrink: $($targetPart.DriveLetter): (Partition $($targetPart.PartitionNumber))" -ForegroundColor White
Write-Host "  Space for Linux:     $linuxGB GB" -ForegroundColor White
Write-Host "  Remaining Windows:   $([math]::Round($currentSizeGB - $linuxGB, 1)) GB" -ForegroundColor White
if (-not $skipUSB) {
    Write-Host "  USB drive:           Disk $($targetUSB.DiskNumber) — $($targetUSB.FriendlyName) [ALL DATA LOST]" -ForegroundColor Yellow
}
Write-Host "  Hostname:            $cfgHostname" -ForegroundColor White
Write-Host "  Username:            $cfgUsername" -ForegroundColor White
Write-Host "  Timezone:            $cfgTimezone" -ForegroundColor White
Write-Host "  Locale:              $cfgLocale" -ForegroundColor White
Write-Host "  Add UEFI boot entry: $addUefiBoot" -ForegroundColor White
Write-Host ""
Write-Warning2 "This will resize your Windows partition. Ensure you have a backup."
Write-Host ""
$confirm = Read-Host "  Type CONFIRM to proceed"
if ($confirm -ne 'CONFIRM') {
    Write-Host "  Aborted." -ForegroundColor Red
    exit 0
}

# ---------------------------------------------------------------------------
# Action 1: Shrink partition
# ---------------------------------------------------------------------------
Write-Header "Shrinking partition..."
$newWindowsSizeBytes = ($currentSizeGB - $linuxGB) * 1GB
Write-Step "Resizing partition $($targetPart.PartitionNumber) to $([math]::Round($newWindowsSizeBytes / 1GB, 1)) GB..."
Resize-Partition -DiskNumber $targetDisk.DiskNumber `
                 -PartitionNumber $targetPart.PartitionNumber `
                 -Size $newWindowsSizeBytes
Write-Step "Partition resized successfully."

# ---------------------------------------------------------------------------
# Action 2: Download Arch ISO
# ---------------------------------------------------------------------------
$isoPath = Join-Path $env:TEMP $ARCH_ISO_FILENAME

if (Test-Path $isoPath) {
    $existingSize = (Get-Item $isoPath).Length
    Write-Step "Found existing ISO ($([math]::Round($existingSize / 1MB)) MB) at $isoPath"
    $reuse = Read-Choice -Prompt "  Reuse existing ISO? [Y/n]" -Default 'y'
    if ($reuse -match '^[Nn]') { Remove-Item $isoPath -Force }
}

if (-not (Test-Path $isoPath)) {
    Write-Header "Downloading Arch Linux ISO..."
    Write-Step "Destination: $isoPath"
    Write-Step "Source: $ARCH_ISO_URL"
    Write-Host ""

    # Try BITS first (resumable, shows progress)
    $bitsAvailable = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bitsAvailable) {
        Write-Step "Using BITS transfer (resumable)..."
        Start-BitsTransfer -Source $ARCH_ISO_URL -Destination $isoPath -DisplayName "Arch Linux ISO" -Description "Downloading..."
    } else {
        Write-Step "BITS unavailable, using Invoke-WebRequest..."
        $ProgressPreference = 'Continue'
        Invoke-WebRequest -Uri $ARCH_ISO_URL -OutFile $isoPath -UseBasicParsing
    }
    Write-Step "Download complete: $isoPath ($([math]::Round((Get-Item $isoPath).Length / 1MB)) MB)"
}

# ---------------------------------------------------------------------------
# Action 3: Write ISO to USB
# ---------------------------------------------------------------------------
if (-not $skipUSB) {
    Write-Header "Writing ISO to USB..."
    Write-Warning2 "This will DESTROY ALL DATA on Disk $($targetUSB.DiskNumber)."
    Write-Step "Writing $ARCH_ISO_FILENAME to Disk $($targetUSB.DiskNumber)..."

    # Dismount all volumes on USB first
    $usbPartitions = Get-Partition -DiskNumber $targetUSB.DiskNumber -ErrorAction SilentlyContinue
    foreach ($p in $usbPartitions) {
        if ($p.DriveLetter) {
            try {
                $vol = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
                if ($vol) {
                    Write-Step "Dismounting $($p.DriveLetter):..."
                    $vol | Get-Partition | Set-Partition -NewDriveLetter $null -ErrorAction SilentlyContinue
                }
            } catch { }
        }
    }

    # Write ISO as raw bytes
    $bufferSize = 4 * 1024 * 1024  # 4 MB chunks
    $usbDevPath = "\\.\PhysicalDrive$($targetUSB.DiskNumber)"

    try {
        $isoStream  = [System.IO.File]::OpenRead($isoPath)
        $isoLength  = $isoStream.Length
        $usbStream  = [System.IO.File]::Open($usbDevPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $buffer     = New-Object byte[] $bufferSize
        $totalWritten = 0

        Write-Host ""
        while (($bytesRead = $isoStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $usbStream.Write($buffer, 0, $bytesRead)
            $totalWritten += $bytesRead
            $pct = [math]::Round(($totalWritten / $isoLength) * 100, 1)
            Write-Progress -Activity "Writing ISO to USB" `
                           -Status "$pct% — $([math]::Round($totalWritten / 1MB)) MB / $([math]::Round($isoLength / 1MB)) MB" `
                           -PercentComplete $pct
        }
        $usbStream.Flush()
    } finally {
        if ($isoStream) { $isoStream.Dispose() }
        if ($usbStream) { $usbStream.Dispose() }
    }

    Write-Progress -Activity "Writing ISO to USB" -Completed
    Write-Step "ISO written successfully."

    # ---------------------------------------------------------------------------
    # Action 4: Mount FAT32 partition on USB and copy install files
    # ---------------------------------------------------------------------------
    Write-Header "Copying install files to USB..."
    Write-Step "Waiting for USB partitions to remount (10 seconds)..."
    Start-Sleep -Seconds 10

    # Rescan disks so Windows sees the new partition table
    $refreshScript = @"
rescan
select disk $($targetUSB.DiskNumber)
rescan
exit
"@
    $refreshScript | diskpart | Out-Null
    Start-Sleep -Seconds 5

    # Find the FAT32 partition (Arch EFI partition) on the USB
    $usbFatPart = $null
    $usbDiskObj = Get-Disk -Number $targetUSB.DiskNumber
    foreach ($p in (Get-Partition -DiskNumber $targetUSB.DiskNumber -ErrorAction SilentlyContinue)) {
        try {
            $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
            if ($vol -and $vol.FileSystem -eq 'FAT32') {
                $usbFatPart = $p
                break
            }
        } catch { }
    }

    if ($null -eq $usbFatPart) {
        Write-Warning2 "Could not auto-detect FAT32 partition on USB."
        Write-Warning2 "You may need to manually copy install files after booting the Arch live USB."
        Write-Warning2 "Alternatively, mount the USB EFI partition and copy files from:"
        Write-Warning2 "  $SCRIPT_DIR"
    } else {
        # Assign a temporary drive letter if needed
        $driveLetter = $usbFatPart.DriveLetter
        if (-not $driveLetter) {
            # Assign temporary letter
            $freeLetter = [char[]](68..90) | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
            Add-PartitionAccessPath -DiskNumber $targetUSB.DiskNumber `
                                    -PartitionNumber $usbFatPart.PartitionNumber `
                                    -AccessPath "${freeLetter}:\"
            $driveLetter = $freeLetter
            $assignedLetter = $true
        }

        $usbInstallDir = "${driveLetter}:\install"
        New-Item -ItemType Directory -Path $usbInstallDir -Force | Out-Null

        # Generate arch-params.env
        $paramsContent = @"
# arch-params.env — generated by windows-setup.ps1
DISK=
USERNAME=$cfgUsername
HOSTNAME=$cfgHostname
TIMEZONE=$cfgTimezone
LOCALE=$cfgLocale
DOTFILES_REPO=$DEFAULT_DOTFILES
INSTALL_SCRIPT_SOURCE=github
"@
        # Note: DISK is left blank — user must verify their disk on the live USB
        # (sda vs nvme0n1 etc. cannot be determined from Windows side reliably)
        Set-Content -Path "$usbInstallDir\arch-params.env" -Value $paramsContent -Encoding UTF8

        # Copy scripts and package lists
        $filesToCopy = @('arch-install.sh', 'post-install.sh', 'pkglist-pacman.txt', 'pkglist-aur.txt', 'pkglist-npm.txt')
        foreach ($f in $filesToCopy) {
            $src = Join-Path $SCRIPT_DIR $f
            if (Test-Path $src) {
                Copy-Item $src -Destination $usbInstallDir -Force
                Write-Step "  Copied: $f"
            } else {
                Write-Warning2 "  Not found (skip): $f — fetch from GitHub on the live USB"
            }
        }

        # Remove temporary drive letter if we assigned one
        if ($assignedLetter) {
            Remove-PartitionAccessPath -DiskNumber $targetUSB.DiskNumber `
                                       -PartitionNumber $usbFatPart.PartitionNumber `
                                       -AccessPath "${driveLetter}:\"
        }

        Write-Step "Install files copied to USB:\install\"
        Write-Warning2 "IMPORTANT: Edit arch-params.env on the USB and set DISK= to your"
        Write-Warning2 "Arch target disk (e.g. /dev/nvme0n1 or /dev/sda)."
        Write-Warning2 "Run 'lsblk' from the Arch live USB to identify the correct disk."
    }

    # ---------------------------------------------------------------------------
    # Action 5: Optional UEFI boot entry
    # ---------------------------------------------------------------------------
    if ($addUefiBoot) {
        Write-Header "Adding UEFI boot entry..."
        try {
            # Use bcdedit to add a one-time boot from the USB EFI entry
            # This sets the USB as bootsequence (boots from it once, then reverts)
            $bcdeditOutput = bcdedit /enum firmware 2>&1
            # Find USB-related EFI entry GUID
            $usbGuid = $bcdeditOutput | Select-String -Pattern '\{[a-f0-9-]+\}' |
                ForEach-Object { $_.Matches[0].Value } |
                Where-Object { $bcdeditOutput -match "$_ .*[Uu][Ss][Bb]" } |
                Select-Object -First 1

            if ($usbGuid) {
                bcdedit /set '{fwbootmgr}' bootsequence $usbGuid
                Write-Step "UEFI boot sequence set to USB ($usbGuid)"
                Write-Step "The system will boot from USB on next restart, then revert."
            } else {
                Write-Warning2 "Could not find USB EFI entry in bcdedit. Set boot order manually in BIOS."
            }
        } catch {
            Write-Warning2 "bcdedit failed: $_"
            Write-Warning2 "Set USB as first boot device manually in your BIOS/UEFI."
        }
    }
}

# ---------------------------------------------------------------------------
# Final instructions
# ---------------------------------------------------------------------------
Write-Header "Setup Complete!"
Write-Host ""
Write-Host "  Summary of what was done:" -ForegroundColor White
Write-Host "    - Shrunk Windows partition by $linuxGB GB" -ForegroundColor Green
if (-not $skipUSB) {
    Write-Host "    - Wrote Arch ISO to USB Disk $($targetUSB.DiskNumber)" -ForegroundColor Green
    Write-Host "    - Copied install scripts to USB:\install\" -ForegroundColor Green
}
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Verify DISK= in arch-params.env on the USB (use lsblk on live USB)" -ForegroundColor White
Write-Host "    2. Boot from the USB (set boot order in BIOS or use F12 boot menu)" -ForegroundColor White
Write-Host "    3. From the Arch live environment, run:" -ForegroundColor White
Write-Host "         bash /run/archiso/bootmnt/install/arch-install.sh" -ForegroundColor Yellow
Write-Host "       If that path doesn't work, mount the USB FAT32 partition:" -ForegroundColor White
Write-Host "         mount /dev/sdX1 /mnt/usb && bash /mnt/usb/install/arch-install.sh" -ForegroundColor Yellow
Write-Host "    4. After install, reboot — first-boot service installs everything automatically." -ForegroundColor White
Write-Host ""
Write-Host "  Monitor first-boot progress from another TTY (Ctrl+Alt+F2):" -ForegroundColor Cyan
Write-Host "    journalctl -f -u firstboot.service" -ForegroundColor Yellow
Write-Host ""
