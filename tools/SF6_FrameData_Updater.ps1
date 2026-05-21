#Requires -Version 5.1
<#
.SYNOPSIS
    SF6 Frame Data Updater
    Downloads FAT (Frame Assistant Tool) SF6 frame data and writes
    per-character JSON files for the SF6 Overlay REFramework script.

.DESCRIPTION
    Run this script once, and again after each SF6 patch.
    Right-click the file -> "Run with PowerShell"
    No installs required -- PowerShell is built into Windows.

.NOTES
    Output location:
        <SF6 folder>\reframework\data\sf6_framedata\<CharacterName>\framedata.json

    Data source:
        FAT (Frame Assistant Tool) by D4RKONION
        https://github.com/D4RKONION/FAT
#>

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
# Bypass execution policy for this process only — lets right-click "Run with
# PowerShell" succeed on machines where the user-scope policy is Restricted.
# Scope=Process means it dies with this shell and never touches system state.
try { Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$host.UI.RawUI.WindowTitle = "SF6 Frame Data Updater"
try { Clear-Host } catch {}

function Write-Header {
    Write-Host ""
    Write-Host "  +================================================+" -ForegroundColor DarkBlue
    Write-Host "  |       SF6 Frame Data Updater                   |" -ForegroundColor Blue
    Write-Host "  |  Downloads FAT data for the SF6 Overlay mod    |" -ForegroundColor DarkBlue
    Write-Host "  +================================================+" -ForegroundColor DarkBlue
    Write-Host ""
}
function Write-OK    ($msg) { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Info  ($msg) { Write-Host "  [....] $msg" -ForegroundColor Cyan }
function Write-Warn  ($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail  ($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Write-Step  ($msg) { Write-Host "  $msg" -ForegroundColor DarkCyan }
function Write-Dim   ($msg) { Write-Host "  $msg" -ForegroundColor DarkGray }

Write-Header

# -- FAT data source (URL fallback list) -----------------------
$FAT_URL_CANDIDATES = @(
    "https://raw.githubusercontent.com/D4RKONION/FAT/master/release/SF6/FrameData/SF6FrameData.json",
    "https://raw.githubusercontent.com/D4RKONION/FAT/main/release/SF6/FrameData/SF6FrameData.json",
    "https://raw.githubusercontent.com/D4RKONION/FAT/master/src/js/constants/framedata/SF6FrameData.json",
    "https://raw.githubusercontent.com/D4RKONION/FAT/main/src/js/constants/framedata/SF6FrameData.json",
    "https://raw.githubusercontent.com/D4RKONION/FAT/master/src/data/framedata/SF6FrameData.json",
    "https://raw.githubusercontent.com/D4RKONION/FAT/main/src/data/framedata/SF6FrameData.json"
)
$FAT_URL = $null

# -- Character maps --------------------------------------------
# Overlay display name -> FAT JSON key.
# Verified against the real SF6FrameData.json.
$FAT_NAME_MAP = [ordered]@{
    "Ryu"      = "Ryu"
    "Luke"     = "Luke"
    "Kimberly" = "Kimberly"
    "Chun-Li"  = "Chun-Li"
    "Manon"    = "Manon"
    "Zangief"  = "Zangief"
    "JP"       = "JP"
    "Dhalsim"  = "Dhalsim"
    "Cammy"    = "Cammy"
    "Ken"      = "Ken"
    "Dee Jay"  = "Dee Jay"
    "Lily"     = "Lily"
    "AKI"      = "A.K.I."
    "Rashid"   = "Rashid"
    "Blanka"   = "Blanka"
    "Juri"     = "Juri"
    "Marisa"   = "Marisa"
    "Guile"    = "Guile"
    "Ed"       = "Ed"
    "E.Honda"  = "E.Honda"
    "Jamie"    = "Jamie"
    "Akuma"    = "Akuma"
    "Sagat"    = "Sagat"
    "M.Bison"  = "M.Bison"
    "Terry"    = "Terry"
    "Mai"      = "Mai"
    "Elena"    = "Elena"
    "C.Viper"  = "C.Viper"
    "Alex"     = "Alex"
}

# -- Locate SF6 ------------------------------------------------
function Find-SF6Path {
    try {
        $val = (Get-ItemProperty "HKCU:\Software\Valve\Steam\Apps\1364780" -ErrorAction Stop).InstallLocation
        if ($val -and (Test-Path (Join-Path $val "StreetFighter6.exe"))) { return $val }
    } catch {}

    try {
        $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath
        if ($steamPath) {
            $vdf = Join-Path $steamPath "steamapps\libraryfolders.vdf"
            if (Test-Path $vdf) {
                $txt  = Get-Content $vdf -Raw
                $libs = [regex]::Matches($txt, '"path"\s*"([^"]+)"[\s\S]*?"apps"\s*\{([^}]*)\}')
                foreach ($m in $libs) {
                    if ($m.Groups[2].Value -match '"1364780"') {
                        $p = $m.Groups[1].Value -replace '\\\\', '\'
                        $candidate = Join-Path $p "steamapps\common\Street Fighter 6"
                        if (Test-Path (Join-Path $candidate "StreetFighter6.exe")) { return $candidate }
                    }
                }
            }
        }
    } catch {}
    return $null
}

$SF6_PATH = Find-SF6Path
if (-not $SF6_PATH) {
    Write-Warn "Could not auto-detect Street Fighter 6 install."
    $manual = Read-Host "  Enter SF6 folder path manually (or Enter to abort)"
    if (-not $manual) { exit 1 }
    $manual = $manual.Trim('"').TrimEnd('\')
    if (-not (Test-Path (Join-Path $manual "StreetFighter6.exe"))) {
        Write-Fail "StreetFighter6.exe not found at: $manual"
        Read-Host "  Press Enter to exit"
        exit 1
    }
    $SF6_PATH = $manual
}
Write-OK "Found SF6 at: $SF6_PATH"

$OUTPUT_BASE = Join-Path $SF6_PATH "reframework\data\sf6_framedata"
if (-not (Test-Path $OUTPUT_BASE)) {
    New-Item -ItemType Directory -Path $OUTPUT_BASE -Force | Out-Null
    Write-OK "Created output folder"
}

# -- Download FAT JSON -----------------------------------------
Write-Info "Downloading FAT frame data from GitHub..."
$rawJson = $null
foreach ($url in $FAT_URL_CANDIDATES) {
    try {
        Write-Dim "Trying: $url"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
        if ($response.StatusCode -eq 200 -and $response.Content.Length -gt 1000) {
            $rawJson = $response.Content
            $FAT_URL = $url
            $kb = [math]::Round($rawJson.Length / 1024)
            Write-OK "Downloaded FAT JSON -- ${kb} KB"
            break
        }
    } catch {
        Write-Dim "  No luck: $($_.Exception.Message)"
    }
}
if (-not $rawJson) {
    Write-Fail "Could not download frame data from any known URL."
    Write-Warn "Check https://github.com/D4RKONION/FAT for the current path."
    Read-Host "  Press Enter to exit"
    exit 1
}

try {
    $fatData = $rawJson | ConvertFrom-Json
    Write-OK "Parsed FAT JSON"
} catch {
    Write-Fail "Failed to parse FAT JSON: $_"
    Read-Host "  Press Enter to exit"
    exit 1
}

# Raw backup
$rawBackup = Join-Path $OUTPUT_BASE "_fat_raw.json"
[System.IO.File]::WriteAllText($rawBackup, $rawJson, [System.Text.UTF8Encoding]::new($false))

# -- Normalize / extract moves ---------------------------------
function ConvertTo-NormalizedMove {
    param($raw, $catName)
    # Scalar field → string, or "-" when null/empty.
    function gs($key) {
        $v = $raw.$key
        if ($null -eq $v -or $v -eq "") { return "-" }
        return [string]$v
    }
    # Array field → join with separator, or "-" when null/empty.
    # FAT's current schema delivers `xx` and `extraInfo` as arrays.
    function gsa($key, $sep) {
        $v = $raw.$key
        if ($null -eq $v) { return "-" }
        if ($v -is [array]) {
            if ($v.Count -eq 0) { return "-" }
            return ($v -join $sep)
        }
        if ($v -eq "") { return "-" }
        return [string]$v
    }

    $mt = $raw.moveType
    if (-not $mt -or $mt -eq "") { $mt = $catName }

    # FAT schema (2026): numCmd / plnCmd / dmg / xx / extraInfo
    # replace the legacy input / altInput / damage / cancelsTo / notes fields.
    return [ordered]@{
        name     = gs "moveName"
        input    = gs "numCmd"
        inputAlt = gs "plnCmd"
        startup  = gs "startup"
        active   = gs "active"
        recovery = gs "recovery"
        total    = gs "total"
        onHit    = gs "onHit"
        onBlock  = gs "onBlock"
        damage   = gs "dmg"
        cancel   = gsa "xx" ", "
        moveType = [string]$mt
        notes    = gsa "extraInfo" " | "
    }
}

function Get-CharMoves {
    param($fatData, $fatKey)
    $charData = $fatData.$fatKey
    if ($null -eq $charData) { return $null }

    $moves    = [System.Collections.Generic.List[object]]::new()
    $rawMoves = $charData.moves
    if ($null -eq $rawMoves) { return $null }

    foreach ($cat in $rawMoves.PSObject.Properties) {
        $catName = $cat.Name
        $catData = $cat.Value
        if ($null -eq $catData) { continue }

        foreach ($moveProp in $catData.PSObject.Properties) {
            $moveObj = $moveProp.Value
            if ($null -eq $moveObj) { continue }
            if ($moveObj -isnot [System.Management.Automation.PSCustomObject]) { continue }
            if (-not $moveObj.moveName -and -not $moveObj.numCmd) { continue }
            $moves.Add((ConvertTo-NormalizedMove $moveObj $catName))
        }
    }

    if ($moves.Count -eq 0) { return $null }
    return $moves
}

function Write-CharJson {
    param($charName, $moves)
    $folder = Join-Path $OUTPUT_BASE $charName
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    $target = Join-Path $folder "framedata.json"
    $obj = [ordered]@{
        character  = $charName
        source     = "FAT"
        source_url = $FAT_URL
        updated    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        move_count = $moves.Count
        moves      = $moves
    }
    $json = $obj | ConvertTo-Json -Depth 6
    # UTF-8 NO BOM -- REFramework's Lua json parser fails on BOM.
    [System.IO.File]::WriteAllText($target, $json, [System.Text.UTF8Encoding]::new($false))
}

# -- Process all characters ------------------------------------
Write-Host ""
Write-Step "Processing characters..."
$ok = 0; $miss = 0; $fail = 0
foreach ($pair in $FAT_NAME_MAP.GetEnumerator()) {
    $ourName = $pair.Key
    $fatKey  = $pair.Value
    try {
        $moves = Get-CharMoves $fatData $fatKey
        if ($null -eq $moves) {
            Write-Warn "$ourName -- not found in FAT under '$fatKey'"
            $miss++
            continue
        }
        Write-CharJson $ourName $moves
        Write-OK "$ourName ($($moves.Count) moves)"
        $ok++
    } catch {
        Write-Fail "$ourName -- $_"
        $fail++
    }
}

$meta = [ordered]@{
    updated    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    source_url = $FAT_URL
    chars_ok   = $ok
    chars_miss = $miss
    chars_fail = $fail
}
[System.IO.File]::WriteAllText(
    (Join-Path $OUTPUT_BASE "_meta.json"),
    ($meta | ConvertTo-Json),
    [System.Text.UTF8Encoding]::new($false)
)

Write-Host ""
Write-Host "  Done.  OK: $ok   Missing: $miss   Failed: $fail" -ForegroundColor Cyan
Write-Host ""
Write-Dim "Output: $OUTPUT_BASE"
Write-Host ""
Read-Host "  Press Enter to exit"
