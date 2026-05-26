@echo off
REM ============================================================
REM SF6 Overlay v1.0 - installer (full auto-install)
REM
REM Pipeline:
REM   0. Disclaimer + user acknowledgement
REM   1. Detect SF6 install path
REM   2. Detect existing install (backup + confirm reinstall)
REM   3. Install REFramework (dinput8.dll only) + folder skeleton
REM   4. Install reframework-d2d plugin
REM   5. Copy overlay Lua to reframework\autorun\
REM   6. Download/install frame data (FAT -> offline fallback)
REM   7. Create desktop shortcut for the web editor (opt-in)
REM ============================================================

setlocal EnableDelayedExpansion

set "INSTALL_ROOT=%~dp0"
if "!INSTALL_ROOT:~-1!"=="\" set "INSTALL_ROOT=!INSTALL_ROOT:~0,-1!"

REM -- 0. DISCLAIMER ------------------------------------------
cls
echo ============================================================
echo   SF6 OVERLAY v1.0 - DISCLAIMER
echo ============================================================
echo.
echo This software is provided "AS IS" without warranty or support of any
echo kind, express or implied, including but not limited to the
echo warranties of merchantability, fitness for a particular
echo purpose, and noninfringement.
echo.
echo By installing and using this software, you acknowledge and
echo agree that:
echo.
echo  - The author of this software is NOT responsible or liable for
echo    any damage to your system, game files, save data, or
echo    Steam account, Street Fighter profile, or Capcom account that 
echo    may result from using the software you are about to install.
echo.
echo  - Modifying or injecting code into any online game carries inherent
echo    risk, including the possibility of account suspension
echo    or ban by Capcom at their sole discretion.
echo.
echo  - You assume FULL responsibility for any consequences of
echo    installing, using, modifying, or distributing this
echo    software.
echo.
echo  - This software is not affiliated with, endorsed by, or
echo    sponsored by Capcom Co., Ltd. Street Fighter 6 is a
echo    trademark of Capcom.
echo.
echo ============================================================
echo.
echo Press Y to acknowledge that you understand and accept these
echo terms and wish to install. Press N to cancel.
echo.
choice /C YN /M "Accept and install"
if errorlevel 2 (
    echo.
    echo Installation cancelled. No changes were made.
    echo.
    pause
    exit /b 0
)
cls

echo.
echo ============================================
echo   SF6 Overlay v1.0 - installer
echo ============================================
echo.

REM -- 1. Detect SF6 path via PowerShell helper ---------------
set "SF6_DIR="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\detect_sf6.ps1"`) do (
    set "SF6_DIR=%%P"
)

if not defined SF6_DIR (
    echo.
    echo Could not auto-detect Street Fighter 6.
    set /p "SF6_DIR=Enter SF6 folder path manually: "
)

set "SF6_DIR=!SF6_DIR:"=!"
if defined SF6_DIR if "!SF6_DIR:~-1!"=="\" set "SF6_DIR=!SF6_DIR:~0,-1!"

if not exist "!SF6_DIR!\StreetFighter6.exe" (
    echo.
    echo ERROR: StreetFighter6.exe not found at:
    echo   !SF6_DIR!
    echo.
    pause
    exit /b 1
)

echo Found SF6 at: !SF6_DIR!
echo.

REM -- 2. Existing install detection + backup ----------------
set "FRAMEDATA_DIR=!SF6_DIR!\reframework\data\sf6_framedata"
if exist "!FRAMEDATA_DIR!" (
    echo --------------------------------------------
    echo Existing SF6 Overlay install detected
    echo --------------------------------------------
    echo Found previous frame data folder at:
    echo   !FRAMEDATA_DIR!
    echo.
    echo Reinstalling will overwrite your existing frame data and overlay files.
    echo Your existing combo notes, custom edits, and ticker config will be
    echo preserved in a timestamped zip backup inside the installer folder.
    echo.
    choice /C YN /M "Proceed with reinstall (recommended)"
    if errorlevel 2 (
        echo.
        echo Install cancelled by user.
        echo.
        pause
        exit /b 0
    )

    echo.
    echo Creating backup...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$ts = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss';" ^
        "$dest = Join-Path '!INSTALL_ROOT!' \"sf6_framedata_backup_$ts.zip\";" ^
        "Compress-Archive -Path '!FRAMEDATA_DIR!\*' -DestinationPath $dest -Force;" ^
        "if (Test-Path $dest) { Write-Host \"Backup saved to: $dest\" } else { Write-Host 'ERROR: backup zip not created'; exit 1 }"

    if errorlevel 1 (
        echo.
        echo ERROR: Could not create backup. Aborting install to avoid data loss.
        echo You can manually back up this folder before retrying:
        echo   !FRAMEDATA_DIR!
        echo.
        pause
        exit /b 1
    )
    echo.
)

REM -- 3. Install REFramework (dinput8.dll + folder structure) -
echo --------------------------------------------
echo Step 1/5: REFramework
echo --------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_reframework.ps1" -SF6Dir "!SF6_DIR!"
set "RF_EXIT=!ERRORLEVEL!"
if not "!RF_EXIT!"=="0" (
    echo WARNING: REFramework auto-install reported errorlevel !RF_EXIT!.
    echo Manual install: https://github.com/praydog/REFramework/releases  (SF6.zip, extract ONLY dinput8.dll)
)

REM -- 4. Install reframework-d2d plugin ----------------------
echo.
echo --------------------------------------------
echo Step 2/5: reframework-d2d plugin
echo --------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_d2d.ps1" -SF6Dir "!SF6_DIR!"
set "D2D_EXIT=!ERRORLEVEL!"
if not "!D2D_EXIT!"=="0" (
    echo WARNING: reframework-d2d auto-install reported errorlevel !D2D_EXIT!.
    echo Manual install: https://github.com/cursey/reframework-d2d/releases
)

REM -- 5. Copy overlay Lua ------------------------------------
echo.
echo --------------------------------------------
echo Step 3/5: Overlay script
echo --------------------------------------------
set "DEST_LUA=!SF6_DIR!\reframework\autorun"
if not exist "!DEST_LUA!" mkdir "!DEST_LUA!"

echo Copying SF6_Overlay.lua...
copy /Y "%~dp0reframework\autorun\SF6_Overlay.lua" "!DEST_LUA!\" >nul
if errorlevel 1 (
    echo ERROR: failed to copy SF6_Overlay.lua
    pause
    exit /b 1
)
echo Done.

REM -- 5b. Glyph icons (buttons + direction/motion PNGs) -----
REM The overlay loads icons via d2d.Image.new("<name>.png"), which resolves
REM relative to <SF6_DIR>\reframework\images\. Two icon families exist:
REM   - Button glyphs:  fist.png, foot.png
REM   - Direction/motion glyphs: U D F B UF UB DF DB N QCF QCB DP RDP HCF
REM     HCB SPD DD FF BB [B]F [D]U 720 360F 360B  (each <name>.png)
REM Every load is wrapped in pcall in the Lua, so missing files fall back to
REM "P"/"K" / lettered text. A copy failure here is therefore a WARNING,
REM not fatal. We mirror the whole source images dir so new glyphs added to
REM the Lua don't require editing this installer.
echo Installing glyph icons (buttons + directions/motions)...
set "SRC_IMG=%~dp0reframework\images"
set "DEST_IMG=!SF6_DIR!\reframework\images"
if not exist "!DEST_IMG!" mkdir "!DEST_IMG!"

set "GLYPH_OK=1"
if exist "!SRC_IMG!\*.png" (
    REM Copy every PNG in the source images folder (covers fist/foot +
    REM all direction/motion glyphs in one shot). robocopy is used for a
    REM reliable exit-code contract; treat codes >=8 as failure.
    robocopy "!SRC_IMG!" "!DEST_IMG!" *.png /NJH /NJS /NDL /NP >nul
    if !ERRORLEVEL! GEQ 8 set "GLYPH_OK=0"
) else (
    set "GLYPH_OK=0"
)

REM Sanity-check that the two button glyphs actually landed.
if not exist "!DEST_IMG!\fist.png" set "GLYPH_OK=0"
if not exist "!DEST_IMG!\foot.png" set "GLYPH_OK=0"

if "!GLYPH_OK!"=="0" (
    echo WARNING: glyph PNGs not fully installed.
    echo          The overlay will fall back to "P"/"K" / lettered text labels.
    echo          Expected source folder: !SRC_IMG!
) else (
    REM Report how many glyphs were copied for quick visual confirmation.
    set "GLYPH_N=0"
    for %%F in ("!DEST_IMG!\*.png") do set /a GLYPH_N+=1
    echo Glyph icons installed ^(!GLYPH_N! PNG files^).
)
echo.
REM -- 6. Frame data download + offline fallback --------------
echo --------------------------------------------
echo Step 4/5: Frame data
echo --------------------------------------------
echo Downloading current frame data from FAT...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\SF6_FrameData_Updater.ps1"

set "DEST_DATA=!SF6_DIR!\reframework\data\sf6_framedata"
set "RYU_CHECK=!DEST_DATA!\Ryu\framedata.json"

if not exist "!RYU_CHECK!" (
    echo.
    echo Frame data download did not produce expected files.
    echo Falling back to bundled offline framedata...
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_offline_framedata.ps1" -Src "%~dp0reframework\data\sf6_framedata" -Dst "!DEST_DATA!"

    if not exist "!RYU_CHECK!" (
        echo.
        echo ERROR: Offline fallback also failed. Frame data was not installed.
        pause
        exit /b 1
    )
    echo Offline framedata installed.
) else (
    echo Frame data installed from FAT.
)

REM -- 7. Desktop shortcut (opt-in) ---------------------------
echo.
echo --------------------------------------------
echo Step 5/5: Desktop shortcut
echo --------------------------------------------
echo The editor lets you edit per-character notes and combos.
choice /C YN /M "Create a desktop shortcut for the SF6 Overlay Editor"
if errorlevel 2 (
    echo Skipped shortcut creation.
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\create_shortcut.ps1" -InstallDir "%~dp0."
    if errorlevel 1 (
        echo WARNING: Could not create desktop shortcut.
        echo You can still launch the editor manually from: editor\run_editor.bat
    )
)

echo.
echo ============================================
echo   Install complete.
echo ============================================
echo.
echo Installed files:
echo   !SF6_DIR!\dinput8.dll                              (REFramework)
echo   !SF6_DIR!\reframework\plugins\reframework-d2d.dll  (d2d plugin)
echo   !DEST_LUA!\SF6_Overlay.lua                          (overlay)
echo   !DEST_IMG!\*.png                                    (button + direction glyphs)
echo   !DEST_DATA!\^<Character^>\framedata.json             (frame data)
echo.
echo NOTE: Do not move or delete this folder if you created a shortcut.
echo       The shortcut points at editor\ inside this directory.
echo.
echo To refresh frame data later (after SF6 patches), re-run:
echo   tools\SF6_FrameData_Updater.ps1
echo.
pause
exit /b 0
