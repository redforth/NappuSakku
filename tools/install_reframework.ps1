# ============================================================
# install_reframework.ps1
#
# Downloads REFramework and installs ONLY dinput8.dll into the
# SF6 folder.
#
# Strategy:
#   1. Try pinned URL (v1.5.9.1 - known to work with SF6)
#   2. If that 404s or fails, fall back to GitHub "latest" API
#
# CRITICAL: praydog explicitly warns "Only extract dinput8.dll
# into your game folder. DO NOT extract the other files, or your
# game may crash." This script enforces that rule strictly.
#
# Also creates the empty reframework\ subfolder structure so
# plugins (like reframework-d2d) and autorun scripts have a
# destination ready.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install_reframework.ps1 -SF6Dir "C:\...\StreetFighter6"
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SF6Dir
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ---- Configuration -----------------------------------------
# Pinned release - update this when a newer REFramework version
# has been verified against current SF6 patches.
$PINNED_VERSION = "v1.5.9.1"
$PINNED_URL     = "https://github.com/praydog/REFramework/releases/download/$PINNED_VERSION/SF6.zip"

# Force TLS 1.2 - PowerShell 5.1 won't talk to GitHub otherwise
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dinputPath = Join-Path $SF6Dir "dinput8.dll"

# ---- 0. Always (re)create the reframework folder structure ----
$rfRoot = Join-Path $SF6Dir "reframework"
$rfSubfolders = @("autorun", "plugins", "data", "scripts")
foreach ($sub in $rfSubfolders) {
    $path = Join-Path $rfRoot $sub
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Created: $path"
    }
}

# ---- 1. Skip download if dinput8.dll already exists ----------
if (Test-Path $dinputPath) {
    Write-Host "REFramework (dinput8.dll) already present - skipping download."
    exit 0
}

# ---- 2. Download (pinned URL first, latest API fallback) -----
$tmpZip = Join-Path $env:TEMP "REFramework-SF6.zip"
$tmpDir = Join-Path $env:TEMP "REFramework-SF6-extract"

if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

$downloaded = $false

# --- Attempt 1: Pinned URL ---
Write-Host "Downloading REFramework $PINNED_VERSION (pinned)..."
Write-Host "  $PINNED_URL"
try {
    Invoke-WebRequest `
        -Uri $PINNED_URL `
        -OutFile $tmpZip `
        -UserAgent "SF6-Overlay-Installer"
    $downloaded = $true
    Write-Host "Pinned download successful."
} catch {
    Write-Host "Pinned download failed: $($_.Exception.Message)"
    Write-Host "Falling back to GitHub latest API..."
}

# --- Attempt 2: GitHub latest API fallback ---
if (-not $downloaded) {
    try {
        $api = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/praydog/REFramework/releases/latest" `
            -UserAgent "SF6-Overlay-Installer"
    } catch {
        Write-Host "ERROR: Could not contact GitHub API for fallback."
        Write-Host $_.Exception.Message
        exit 1
    }

    $asset = $api.assets | Where-Object { $_.name -eq "SF6.zip" } | Select-Object -First 1
    if (-not $asset) {
        Write-Host "ERROR: SF6.zip not found in the latest release assets."
        Write-Host "Available assets:"
        $api.assets | ForEach-Object { Write-Host "  - $($_.name)" }
        exit 1
    }

    Write-Host "Latest release: $($api.tag_name)"
    Write-Host "Downloading from latest..."
    try {
        Invoke-WebRequest `
            -Uri $asset.browser_download_url `
            -OutFile $tmpZip `
            -UserAgent "SF6-Overlay-Installer"
        $downloaded = $true
    } catch {
        Write-Host "ERROR: Latest-version download also failed."
        Write-Host $_.Exception.Message
        exit 1
    }
}

if (-not $downloaded -or -not (Test-Path $tmpZip)) {
    Write-Host "ERROR: No REFramework zip available."
    exit 1
}

# ---- 3. Extract --------------------------------------------
Write-Host "Extracting..."
try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
} catch {
    Write-Host "ERROR: Extraction failed."
    Write-Host $_.Exception.Message
    exit 1
}

# ---- 4. Find dinput8.dll - and ONLY dinput8.dll --------------
$dinputSource = Get-ChildItem -Path $tmpDir -Recurse -Filter "dinput8.dll" |
                Select-Object -First 1

if (-not $dinputSource) {
    Write-Host "ERROR: dinput8.dll not found inside the SF6.zip archive."
    exit 1
}

Write-Host "Copying dinput8.dll to: $SF6Dir"
Copy-Item -Path $dinputSource.FullName -Destination $dinputPath -Force

# ---- 5. Cleanup --------------------------------------------
Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- 6. Verify ---------------------------------------------
if (Test-Path $dinputPath) {
    $size = (Get-Item $dinputPath).Length
    Write-Host "REFramework installed successfully (dinput8.dll, $([math]::Round($size/1KB)) KB)."
    exit 0
} else {
    Write-Host "ERROR: install ran but dinput8.dll is missing at:"
    Write-Host "  $dinputPath"
    exit 1
}
