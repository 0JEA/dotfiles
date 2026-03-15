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
$ARCH_ISO_MIRRORS    = @(
    'https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso',
    'https://mirror.rackspace.com/archlinux/iso/latest/archlinux-x86_64.iso',
    'https://mirrors.edge.kernel.org/archlinux/iso/latest/archlinux-x86_64.iso'
)
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
    $userInput = Read-Host $display
    if ([string]::IsNullOrWhiteSpace($userInput)) { return $Default }
    return $userInput.Trim()
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
# Validate script directory contains install files
# ---------------------------------------------------------------------------
if (-not (Test-Path (Join-Path $SCRIPT_DIR 'arch-install.sh'))) {
    Write-Warning2 "arch-install.sh not found in $SCRIPT_DIR."
    Write-Warning2 "Run this script from the dotfiles/install/ directory."
    Write-Warning2 "The install scripts will not be available on the USB."
    $ok = Read-Choice -Prompt "  Continue anyway (you'll fetch scripts from GitHub on live USB)? [y/N]" -Default 'n'
    if ($ok -notmatch '^[Yy]') { exit 1 }
}

# ---------------------------------------------------------------------------
# Step 1: Select disk to shrink
# ---------------------------------------------------------------------------
Write-Header "Step 1: Select disk to shrink"
$allDisks = @(Get-Disk | Where-Object { $_.OperationalStatus -eq 'Online' })
if ($allDisks.Count -eq 0) { Write-Warning2 "No online disks found."; exit 1 }

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
$allParts   = Get-Partition -DiskNumber $targetDisk.DiskNumber
$partitions = @($allParts | Where-Object { $_.Type -ne 'Unknown' -and $_.Size -gt 1GB })
if ($partitions.Count -eq 0) { Write-Warning2 "No eligible partitions found on this disk."; exit 1 }

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

# Validate: confirm this is an NTFS Windows partition
$partVol    = Get-Volume -Partition $targetPart -ErrorAction SilentlyContinue
$partFsType = if ($partVol) { $partVol.FileSystem } else { '(unknown)' }
if (-not $partVol -or $partVol.FileSystem -ne 'NTFS') {
    Write-Warning2 "Selected partition does not appear to be an NTFS Windows partition (FileSystem: $partFsType)."
    $ok = Read-Choice -Prompt "  Proceed anyway? [y/N]" -Default 'n'
    if ($ok -notmatch '^[Yy]') { exit 1 }
}
if ($targetPart.DriveLetter -and $targetPart.DriveLetter -ne 'C') {
    Write-Warning2 "Selected partition is $($targetPart.DriveLetter):, not C:. Confirm this is your Windows partition."
    $ok = Read-Choice -Prompt "  Proceed? [y/N]" -Default 'n'
    if ($ok -notmatch '^[Yy]') { exit 1 }
}

# Warn if disk already has substantial unallocated space (may have been shrunk before)
$diskUnallocGB = [math]::Round(($targetDisk.Size - ($allParts | Measure-Object -Property Size -Sum).Sum) / 1GB, 1)
if ($diskUnallocGB -gt 10) {
    Write-Warning2 "Disk already has ~$diskUnallocGB GB unallocated. You may have already shrunk this partition."
    $ok = Read-Choice -Prompt "  Proceed with another shrink anyway? [y/N]" -Default 'n'
    if ($ok -notmatch '^[Yy]') { exit 0 }
}

# ---------------------------------------------------------------------------
# Step 3: How much space for Linux
# ---------------------------------------------------------------------------
Write-Header "Step 3: Allocate space for Linux"
$currentSizeGB = [math]::Round($targetPart.Size / 1GB, 1)
Write-Host "  Current partition size: $currentSizeGB GB" -ForegroundColor White

# Get supported resize range
try {
    $sizeRange = Get-PartitionSupportedSize -DiskNumber $targetDisk.DiskNumber -PartitionNumber $targetPart.PartitionNumber
} catch {
    Write-Warning2 "Could not determine supported resize range: $_"
    Write-Warning2 "The partition may be locked. Try: Optimize-Volume -DriveLetter $($targetPart.DriveLetter) -Defrag"
    exit 1
}
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
$usbDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' })

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
$newWindowsSizeBytes = $targetPart.Size - ($linuxGB * 1GB)
Write-Step "Resizing partition $($targetPart.PartitionNumber) to $([math]::Round($newWindowsSizeBytes / 1GB, 1)) GB..."
try {
    Resize-Partition -DiskNumber $targetDisk.DiskNumber `
                     -PartitionNumber $targetPart.PartitionNumber `
                     -Size $newWindowsSizeBytes
    Write-Step "Partition resized successfully."
} catch {
    Write-Host ""
    Write-Warning2 "Partition resize failed: $_"
    Write-Warning2 "Common causes and fixes:"
    Write-Warning2 "  1. Run: Optimize-Volume -DriveLetter $($targetPart.DriveLetter) -Defrag -Verbose"
    Write-Warning2 "  2. Disable hibernation: powercfg /h off  (re-enable after install)"
    Write-Warning2 "  3. Disable System Protection on $($targetPart.DriveLetter): temporarily"
    Write-Warning2 "  4. Reboot Windows and re-run this script"
    exit 1
}

# ---------------------------------------------------------------------------
# Action 2: Download Arch ISO
# ---------------------------------------------------------------------------
$isoPath     = Join-Path $env:TEMP $ARCH_ISO_FILENAME
$isoHash     = $null   # populated after checksum verification
$ARCH_ISO_URL = $null  # tracks which mirror succeeded (used for checksum URL)

if (Test-Path $isoPath) {
    $existingSize = (Get-Item $isoPath).Length
    Write-Step "Found existing ISO ($([math]::Round($existingSize / 1MB)) MB) at $isoPath"
    $reuse = Read-Choice -Prompt "  Reuse existing ISO? [Y/n]" -Default 'y'
    if ($reuse -match '^[Nn]') { Remove-Item $isoPath -Force }
}

if (-not (Test-Path $isoPath)) {
    Write-Header "Downloading Arch Linux ISO..."
    Write-Step "Destination: $isoPath"
    Write-Host ""

    $bitsAvailable = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue

    foreach ($mirrorUrl in $ARCH_ISO_MIRRORS) {
        try {
            Write-Step "Trying mirror: $mirrorUrl"
            if ($bitsAvailable) {
                Start-BitsTransfer -Source $mirrorUrl -Destination $isoPath -DisplayName "Arch Linux ISO" -Description "Downloading..."
            } else {
                $ProgressPreference = 'Continue'
                Invoke-WebRequest -Uri $mirrorUrl -OutFile $isoPath -UseBasicParsing -TimeoutSec 600
            }
            $ARCH_ISO_URL = $mirrorUrl
            break
        } catch {
            Write-Warning2 "Mirror failed: $_"
            if (Test-Path $isoPath) { Remove-Item $isoPath -Force }
        }
    }

    if (-not (Test-Path $isoPath)) {
        throw "All mirrors failed. Check your internet connection."
    }
    Write-Step "Download complete: $isoPath ($([math]::Round((Get-Item $isoPath).Length / 1MB)) MB)"
}

# Verify ISO checksum
Write-Step "Verifying ISO checksum..."
if ($null -eq $ARCH_ISO_URL) {
    # Reusing a cached ISO — use first mirror to fetch checksums
    $ARCH_ISO_URL = $ARCH_ISO_MIRRORS[0]
}
$checksumUrl = $ARCH_ISO_URL -replace '[^/]+$', 'sha256sums.txt'
try {
    $checksumRaw  = (Invoke-WebRequest -Uri $checksumUrl -UseBasicParsing -TimeoutSec 30).Content
    $isoPattern   = [regex]::Escape($ARCH_ISO_FILENAME)
    $expectedHash = ($checksumRaw -split "`n" |
        Where-Object { $_ -match "  $isoPattern\r?$" } |
        Select-Object -First 1) -replace '\s+.*', ''
    if ([string]::IsNullOrWhiteSpace($expectedHash)) {
        Remove-Item $isoPath -Force
        throw "Could not find expected hash for '$ARCH_ISO_FILENAME' in checksum file from $checksumUrl. ISO deleted."
    }
    $actualHash   = (Get-FileHash -Path $isoPath -Algorithm SHA256).Hash
    if ($actualHash -ne $expectedHash.ToUpper()) {
        Remove-Item $isoPath -Force
        throw "Checksum mismatch! Expected: $expectedHash  Got: $actualHash. ISO deleted."
    }
    $isoHash = $actualHash
    Write-Step "Checksum verified OK."
} catch {
    throw "ISO checksum verification failed: $_"
}

# ---------------------------------------------------------------------------
# Action 3: Write ISO to USB
# ---------------------------------------------------------------------------
if (-not $skipUSB) {

    # Check USB is large enough before writing
    $isoSize = (Get-Item $isoPath).Length
    if ($targetUSB.Size -lt ($isoSize + 64MB)) {
        Write-Warning2 "USB drive is too small ($([math]::Round($targetUSB.Size/1GB,1)) GB) for ISO ($([math]::Round($isoSize/1MB)) MB)."
        exit 1
    }

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
            } catch { Write-Warning2 "  Warning: could not dismount $($p.DriveLetter): — $_" }
        }
    }

    # Write ISO as raw bytes
    $bufferSize   = 4 * 1024 * 1024  # 4 MB chunks
    $usbDevPath   = "\\.\PhysicalDrive$($targetUSB.DiskNumber)"
    $isoStream    = $null
    $usbStream    = $null
    $isoLength    = 0

    try {
        $isoStream    = [System.IO.File]::OpenRead($isoPath)
        $isoLength    = $isoStream.Length
        $usbStream    = [System.IO.File]::Open($usbDevPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $buffer       = New-Object byte[] $bufferSize
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
    } finally {
        if ($usbStream) {
            try { $usbStream.Flush() } catch { }
            $usbStream.Dispose()
        }
        if ($isoStream) { $isoStream.Dispose() }
        Write-Progress -Activity "Writing ISO to USB" -Completed
    }

    Write-Step "ISO written successfully."

    # Optional: verify write integrity by re-reading and hashing USB
    $verifyWrite = Read-Choice -Prompt "  Verify write integrity (reads ~$([math]::Round($isoSize/1MB)) MB from USB, ~60 s)? [y/N]" -Default 'n'
    if ($verifyWrite -match '^[Yy]') {
        Write-Step "Verifying write integrity..."
        $verifyStream = $null
        $sha256       = $null
        try {
            $verifyStream = [System.IO.File]::OpenRead($usbDevPath)
            $sha256       = [System.Security.Cryptography.SHA256]::Create()
            $verifyBuf    = New-Object byte[] $bufferSize
            $verifyTotal  = 0
            while ($verifyTotal -lt $isoLength) {
                $toRead = [math]::Min($bufferSize, $isoLength - $verifyTotal)
                $n = $verifyStream.Read($verifyBuf, 0, $toRead)
                if ($n -eq 0) { break }
                $sha256.TransformBlock($verifyBuf, 0, $n, $null, 0) | Out-Null
                $verifyTotal += $n
            }
            $sha256.TransformFinalBlock(@(), 0, 0) | Out-Null
            $writtenHash = ([BitConverter]::ToString($sha256.Hash) -replace '-', '')
            if ($writtenHash -ne $isoHash) {
                throw "USB write verification failed (hash mismatch). Try a different USB drive."
            }
            Write-Step "Write verified OK."
        } catch {
            Write-Warning2 "Write verification error: $_"
            Write-Warning2 "USB may not be bootable. Re-run the script and try again."
        } finally {
            if ($verifyStream) { $verifyStream.Dispose() }
            if ($sha256)       { $sha256.Dispose() }
        }
    }

    # ---------------------------------------------------------------------------
    # Action 4: Mount FAT32 partition on USB and copy install files
    # ---------------------------------------------------------------------------
    Write-Header "Copying install files to USB..."

    # Poll for FAT32 partition — up to 60 s, checking every 5 s
    Write-Step "Waiting for USB partition table to appear..."
    $usbFatPart = $null
    $deadline   = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and $null -eq $usbFatPart) {
        Start-Sleep -Seconds 5
        $refreshScript = @"
rescan
select disk $($targetUSB.DiskNumber)
rescan
exit
"@
        $refreshScript | diskpart | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning2 "diskpart rescan exited with code $LASTEXITCODE" }
        foreach ($p in (Get-Partition -DiskNumber $targetUSB.DiskNumber -ErrorAction SilentlyContinue)) {
            try {
                $vol = Get-Volume -Partition $p -ErrorAction SilentlyContinue
                # Prefer partition 1 or any FAT32 partition ≤ 1 GB (Arch EFI is 512 MB–1 GB)
                if ($vol -and $vol.FileSystem -eq 'FAT32' -and ($p.PartitionNumber -eq 1 -or $p.Size -le 1GB)) {
                    $usbFatPart = $p; break
                }
            } catch { Write-Warning2 "  Warning: checking partition failed — $_" }
        }
    }

    if ($null -eq $usbFatPart) {
        Write-Warning2 "Could not auto-detect FAT32 partition on USB after 60 s."
        Write-Warning2 "You may need to manually copy install files after booting the Arch live USB."
        Write-Warning2 "Alternatively, mount the USB EFI partition and copy files from:"
        Write-Warning2 "  $SCRIPT_DIR"
    } else {
        # Assign a temporary drive letter if needed
        $driveLetter    = $usbFatPart.DriveLetter
        $assignedLetter = $false
        if (-not $driveLetter) {
            $freeLetter = [char[]](68..90) | Where-Object { -not (Test-Path "${_}:\") } | Select-Object -First 1
            if ($null -eq $freeLetter) { throw "No free drive letter available (D–Z all assigned)." }
            Add-PartitionAccessPath -DiskNumber $targetUSB.DiskNumber `
                                    -PartitionNumber $usbFatPart.PartitionNumber `
                                    -AccessPath "${freeLetter}:\"
            $driveLetter    = $freeLetter
            $assignedLetter = $true
        }

        $usbInstallDir = "${driveLetter}:\install"
        New-Item -ItemType Directory -Path $usbInstallDir -Force | Out-Null

        # Use usb source when post-install.sh is present alongside this script
        $installSource = if (Test-Path (Join-Path $SCRIPT_DIR 'post-install.sh')) { 'usb' } else { 'github' }

        # Generate arch-params.env
        $paramsContent = @"
# arch-params.env — generated by windows-setup.ps1
DISK=
USERNAME=$cfgUsername
HOSTNAME=$cfgHostname
TIMEZONE=$cfgTimezone
LOCALE=$cfgLocale
DOTFILES_REPO=$DEFAULT_DOTFILES
INSTALL_SCRIPT_SOURCE=$installSource
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
            $bcdeditOutput = bcdedit /enum firmware 2>&1

            # Parse bcdedit output into per-entry blocks keyed by GUID
            $entries     = @{}
            $currentGuid = $null
            foreach ($line in ($bcdeditOutput -split "`n")) {
                if ($line -match '(\{[a-f0-9-]+\})') { $currentGuid = $Matches[1] }
                if ($currentGuid) {
                    if (-not $entries.ContainsKey($currentGuid)) { $entries[$currentGuid] = '' }
                    $entries[$currentGuid] += $line + "`n"
                }
            }

            $usbGuid = $entries.Keys | Where-Object {
                $entries[$_] -match 'usbstor|[Uu][Ss][Bb]|[Rr]emovable'
            } | Select-Object -First 1

            if ($usbGuid) {
                bcdedit /set '{fwbootmgr}' bootsequence $usbGuid
                if ($LASTEXITCODE -ne 0) { throw "bcdedit exited with code $LASTEXITCODE" }
                Write-Step "UEFI boot sequence set to USB ($usbGuid)"
                Write-Step "The system will boot from USB on next restart, then revert."
            } else {
                Write-Warning2 "Could not auto-detect USB EFI entry. Found entries:"
                foreach ($guid in $entries.Keys) {
                    $desc = ($entries[$guid] -split "`n" | Select-String 'description') -replace '.*description\s+', ''
                    Write-Host "    $guid — $desc"
                }
                Write-Warning2 "Set boot order manually in BIOS/UEFI."
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
