# ============================================================
# detect_sf6.ps1
# Helper called by install.bat to locate the SF6 install path.
# Writes the path to stdout on success. Silent on failure.
#
# Detection order:
#   1. HKCU\Software\Valve\Steam\Apps\1364780\InstallLocation
#   2. Scan libraryfolders.vdf for App 1364780 in any library
# ============================================================

$ErrorActionPreference = "SilentlyContinue"

# -- 1. Direct Steam Apps key ---------------------------------
$direct = (Get-ItemProperty "HKCU:\Software\Valve\Steam\Apps\1364780").InstallLocation
if ($direct -and (Test-Path (Join-Path $direct "StreetFighter6.exe"))) {
    Write-Output $direct
    exit 0
}

# -- 2. libraryfolders.vdf scan -------------------------------
$sp = (Get-ItemProperty "HKCU:\Software\Valve\Steam").SteamPath
if (-not $sp) { exit 1 }

$vdf = Join-Path $sp "steamapps\libraryfolders.vdf"
if (-not (Test-Path $vdf)) { exit 1 }

$txt  = Get-Content $vdf -Raw
$libs = [regex]::Matches($txt, '"path"\s*"([^"]+)"[\s\S]*?"apps"\s*\{([^}]*)\}')

foreach ($m in $libs) {
    if ($m.Groups[2].Value -match '"1364780"') {
        $p = $m.Groups[1].Value -replace '\\\\', '\'
        $candidate = Join-Path $p "steamapps\common\Street Fighter 6"
        if (Test-Path (Join-Path $candidate "StreetFighter6.exe")) {
            Write-Output $candidate
            exit 0
        }
    }
}

exit 1
