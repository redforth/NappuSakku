# ============================================================
# create_shortcut.ps1
#
# Creates a Windows desktop shortcut (.lnk) pointing at the
# SF6 Overlay Editor launcher.
#
# Target priority (auto-detected):
#   1. editor\sf6_editor.exe       (PyInstaller build, preferred)
#   2. editor\run_editor.bat       (Python folder build, fallback)
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File create_shortcut.ps1 -InstallDir "C:\path\to\SF6_Overlay_v1.0"
# ============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"

# ---- 1. Resolve absolute install path ---------------------
$InstallDir = (Resolve-Path -LiteralPath $InstallDir).Path

# ---- 2. Find launcher target ------------------------------
$exePath = Join-Path $InstallDir "editor\sf6_editor.exe"
$batPath = Join-Path $InstallDir "editor\run_editor.bat"

if (Test-Path $exePath) {
    $targetPath  = $exePath
    $workingDir  = Split-Path $exePath -Parent
    $description = "SF6 Overlay Editor"
    Write-Host "Target: sf6_editor.exe (PyInstaller build)"
} elseif (Test-Path $batPath) {
    $targetPath  = $batPath
    $workingDir  = Split-Path $batPath -Parent
    $description = "SF6 Overlay Editor (web UI)"
    Write-Host "Target: run.bat (Python folder build)"
} else {
    Write-Host "ERROR: No launcher found. Expected one of:"
    Write-Host "  $exePath"
    Write-Host "  $batPath"
    exit 1
}

# ---- 3. Locate icon (optional) ----------------------------
# Try a few likely names; fall back to the target's own icon if none present.
$iconCandidates = @(
    "editor\sf6_overlay.ico",
    "editor\icon.ico",
    "editor\app.ico"
)
$iconPath = $null
foreach ($candidate in $iconCandidates) {
    $candidateFull = Join-Path $InstallDir $candidate
    if (Test-Path $candidateFull) {
        $iconPath = $candidateFull
        break
    }
}

# ---- 4. Build the shortcut --------------------------------
$desktopPath  = [System.Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "SF6 Overlay Editor.lnk"

$wsh      = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)

$shortcut.TargetPath       = $targetPath
$shortcut.WorkingDirectory = $workingDir
$shortcut.Description      = $description
$shortcut.WindowStyle      = 7   # 7 = minimized (hides the bat console window if .bat is target)

if ($iconPath) {
    $shortcut.IconLocation = "$iconPath,0"
    Write-Host "Icon:   $iconPath"
} else {
    # No custom icon found - use the target's default icon.
    $shortcut.IconLocation = "$targetPath,0"
}

$shortcut.Save()

# ---- 5. Verify --------------------------------------------
if (Test-Path $shortcutPath) {
    Write-Host "Desktop shortcut created: $shortcutPath"
    exit 0
} else {
    Write-Host "ERROR: shortcut creation reported success but file is missing."
    exit 1
}
