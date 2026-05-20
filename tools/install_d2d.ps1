# ============================================================
# install_d2d.ps1
# Downloads the latest reframework-d2d release from GitHub and
# copies the plugin files into the Street Fighter 6 folder.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install_d2d.ps1 -SF6Dir "C:\...\StreetFighter6"
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$SF6Dir
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # massive speedup for Invoke-WebRequest on PS 5.1

# Force TLS 1.2 — PowerShell 5.1 defaults to TLS 1.0, GitHub will refuse.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$pluginPath = Join-Path $SF6Dir "reframework\plugins\reframework-d2d.dll"

# ---- 1. Skip if already installed --------------------------
if (Test-Path $pluginPath) {
    Write-Host "reframework-d2d.dll already present - skipping download."
    exit 0
}

# ---- 2. Query GitHub for the latest release ----------------
Write-Host "Querying latest reframework-d2d release..."
try {
    $api = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/cursey/reframework-d2d/releases/latest" `
        -UserAgent "SF6-Overlay-Installer"
} catch {
    Write-Host "ERROR: Could not contact GitHub API."
    Write-Host $_.Exception.Message
    exit 1
}

# Pick the first .zip asset (filename has varied between releases)
$asset = $api.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
if (-not $asset) {
    Write-Host "ERROR: No .zip asset found in the latest release."
    exit 1
}

Write-Host "Release: $($api.tag_name)"
Write-Host "Asset:   $($asset.name) ($([math]::Round($asset.size/1KB)) KB)"

# ---- 3. Download into TEMP ---------------------------------
$tmpZip = Join-Path $env:TEMP "reframework-d2d.zip"
$tmpDir = Join-Path $env:TEMP "reframework-d2d-extract"

if (Test-Path $tmpZip) { Remove-Item $tmpZip -Force }
if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }

Write-Host "Downloading..."
try {
    Invoke-WebRequest `
        -Uri $asset.browser_download_url `
        -OutFile $tmpZip `
        -UserAgent "SF6-Overlay-Installer"
} catch {
    Write-Host "ERROR: Download failed."
    Write-Host $_.Exception.Message
    exit 1
}

# ---- 4. Extract --------------------------------------------
Write-Host "Extracting..."
try {
    Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force
} catch {
    Write-Host "ERROR: Extraction failed."
    Write-Host $_.Exception.Message
    exit 1
}

# ---- 5. Locate the reframework folder in the extracted tree
$srcRoot = Get-ChildItem -Path $tmpDir -Recurse -Directory -Filter "reframework" |
           Select-Object -First 1

if (-not $srcRoot) {
    # Some releases ship loose files (no top-level reframework/ folder).
    # In that case, find the DLL directly and construct a synthetic layout.
    $looseDll = Get-ChildItem -Path $tmpDir -Recurse -Filter "reframework-d2d.dll" |
                Select-Object -First 1
    if ($looseDll) {
        Write-Host "Detected loose asset layout - mapping files manually."
        $destPlugins = Join-Path $SF6Dir "reframework\plugins"
        if (-not (Test-Path $destPlugins)) { New-Item -ItemType Directory -Path $destPlugins -Force | Out-Null }
        Copy-Item -Path $looseDll.FullName -Destination $destPlugins -Force

        # Optional d2d.lua may live next to the dll
        $looseLua = Get-ChildItem -Path $tmpDir -Recurse -Filter "d2d.lua" | Select-Object -First 1
        if ($looseLua) {
            $destAutorun = Join-Path $SF6Dir "reframework\autorun"
            if (-not (Test-Path $destAutorun)) { New-Item -ItemType Directory -Path $destAutorun -Force | Out-Null }
            Copy-Item -Path $looseLua.FullName -Destination $destAutorun -Force
        }
    } else {
        Write-Host "ERROR: Could not locate reframework-d2d.dll inside the downloaded archive."
        exit 1
    }
} else {
    # Normal case: zip contains reframework\plugins\... and possibly reframework\autorun\...
    $destReframework = Join-Path $SF6Dir "reframework"
    if (-not (Test-Path $destReframework)) {
        New-Item -ItemType Directory -Path $destReframework -Force | Out-Null
    }

    Write-Host "Copying files into: $destReframework"
    Copy-Item -Path (Join-Path $srcRoot.FullName "*") `
              -Destination $destReframework `
              -Recurse -Force
}

# ---- 6. Cleanup --------------------------------------------
Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

# ---- 7. Verify ---------------------------------------------
if (Test-Path $pluginPath) {
    Write-Host "reframework-d2d installed successfully."
    exit 0
} else {
    Write-Host "ERROR: install ran but reframework-d2d.dll is missing at:"
    Write-Host "  $pluginPath"
    exit 1
}
