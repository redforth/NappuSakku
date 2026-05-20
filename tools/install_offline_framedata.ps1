# ============================================================
# install_offline_framedata.ps1
# Helper called by install.bat when the FAT download fails.
# Takes the bundled flat <Name>-framedata.json files and copies
# them into the per-character folder layout the overlay expects.
#
# Args: -Src <bundled folder>  -Dst <destination folder>
# Examples of name normalization (filename -> overlay name):
#   C_Viper -> C.Viper
#   M_Bison -> M.Bison
#   E_Honda -> E.Honda
#   Dee_Jay -> Dee Jay
# ============================================================

param(
    [Parameter(Mandatory=$true)] [string]$Src,
    [Parameter(Mandatory=$true)] [string]$Dst
)

$ErrorActionPreference = "Stop"

$nameMap = @{
    "C_Viper" = "C.Viper"
    "M_Bison" = "M.Bison"
    "E_Honda" = "E.Honda"
    "Dee_Jay" = "Dee Jay"
}

if (-not (Test-Path $Src)) {
    Write-Host "ERROR: source folder not found: $Src" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Dst)) {
    New-Item -ItemType Directory -Path $Dst -Force | Out-Null
}

$count = 0
Get-ChildItem -Path $Src -Filter "*-framedata.json" | ForEach-Object {
    $base = $_.BaseName -replace '-framedata$', ''
    $name = if ($nameMap.ContainsKey($base)) { $nameMap[$base] } else { $base }
    $folder = Join-Path $Dst $name
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    Copy-Item $_.FullName (Join-Path $folder "framedata.json") -Force
    Write-Host "  $name" -ForegroundColor Green
    $count++
}

Write-Host ""
Write-Host "Installed $count character framedata files." -ForegroundColor Cyan
