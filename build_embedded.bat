@echo off
REM ============================================================
REM build_embedded.bat -- prepare embedded Python bundle for the
REM SF6 Overlay Editor. ONE-TIME build step.
REM
REM Produces editor\python\ containing a fully self-contained
REM Python 3.11 runtime + fastapi + uvicorn + pydantic.
REM End users do not need Python installed.
REM
REM Requires internet on the build machine. ~75 MB download
REM total, ~120 MB extracted before cleanup, ~55 MB final.
REM ============================================================

setlocal EnableDelayedExpansion

REM -- Config -------------------------------------------------
set "PYVER=3.11.9"
set "PY_URL=https://www.python.org/ftp/python/%PYVER%/python-%PYVER%-embed-amd64.zip"
set "PIP_URL=https://bootstrap.pypa.io/get-pip.py"
set "BUILD_DIR=%~dp0_build"
set "DEST_DIR=%~dp0editor\python"

REM -- 0. Clean previous build --------------------------------
if exist "!DEST_DIR!"  rmdir /S /Q "!DEST_DIR!"
if exist "!BUILD_DIR!" rmdir /S /Q "!BUILD_DIR!"
mkdir "!BUILD_DIR!"
mkdir "!DEST_DIR!"

echo.
echo ============================================
echo   Embedded Python bundle build
echo ============================================
echo.

REM -- 1. Download embeddable Python --------------------------
echo [1/5] Downloading Python %PYVER% embeddable...
powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = 'Tls12';" ^
    "Invoke-WebRequest -Uri '%PY_URL%' -OutFile '!BUILD_DIR!\python-embed.zip'"
if errorlevel 1 (
    echo ERROR: failed to download embeddable Python.
    pause
    exit /b 1
)

echo [2/5] Extracting...
powershell -NoProfile -Command ^
    "Expand-Archive -Path '!BUILD_DIR!\python-embed.zip' -DestinationPath '!DEST_DIR!' -Force"

REM -- 2. Enable site-packages in the embed distribution ------
REM The embeddable Python ships with a python311._pth file that
REM disables `import site` -- which means pip-installed packages
REM in site-packages are invisible. We uncomment that line.
echo [3/5] Patching python311._pth to enable site-packages...
powershell -NoProfile -Command ^
    "$f = Get-ChildItem '!DEST_DIR!\python*._pth' | Select-Object -First 1;" ^
    "(Get-Content $f.FullName) -replace '#import site','import site' | Set-Content $f.FullName"

REM -- 3. Install pip into the embedded Python ----------------
echo [4/5] Bootstrapping pip...
powershell -NoProfile -Command ^
    "[Net.ServicePointManager]::SecurityProtocol = 'Tls12';" ^
    "Invoke-WebRequest -Uri '%PIP_URL%' -OutFile '!BUILD_DIR!\get-pip.py'"
"!DEST_DIR!\python.exe" "!BUILD_DIR!\get-pip.py" --no-warn-script-location
if errorlevel 1 (
    echo ERROR: get-pip.py failed.
    pause
    exit /b 1
)

REM -- 4. Install runtime dependencies ------------------------
echo [5/5] Installing fastapi, uvicorn, pydantic...
"!DEST_DIR!\python.exe" -m pip install -r "%~dp0editor\source\requirements.txt" --no-warn-script-location --no-cache-dir
if errorlevel 1 (
    echo ERROR: pip install failed.
    pause
    exit /b 1
)

REM -- 5. Strip junk to slim the bundle -----------------------
echo Stripping caches and unused files...
REM Remove .pyc caches, pip's own caches, test suites, and the
REM Scripts\ folder (we never invoke pip from the bundled python
REM in production -- only via this build script).
for /f "delims=" %%d in ('dir /b /s /ad "!DEST_DIR!\__pycache__" 2^>nul') do rmdir /S /Q "%%d"
for /f "delims=" %%d in ('dir /b /s /ad "!DEST_DIR!\tests"        2^>nul') do rmdir /S /Q "%%d"
for /f "delims=" %%d in ('dir /b /s /ad "!DEST_DIR!\test"         2^>nul') do rmdir /S /Q "%%d"
if exist "!DEST_DIR!\Scripts" rmdir /S /Q "!DEST_DIR!\Scripts"

REM -- 6. Verify --------------------------------------------------
echo.
echo Verifying bundle can import the deps...
"!DEST_DIR!\python.exe" -c "import fastapi, uvicorn, pydantic, multipart; print('OK: fastapi', fastapi.__version__, '| multipart', multipart.__version__)"
if errorlevel 1 (
    echo ERROR: dep import verification failed. Bundle is broken.
    pause
    exit /b 1
)

REM Deeper check: actually import server.py so route construction
REM runs (this is where missing transitive deps like python-multipart
REM surface -- they don't show up on a plain `import fastapi`).
REM server.py is __main__-guarded so importing it doesn't start uvicorn.
echo Verifying server.py can be imported (catches missing deps)...
"!DEST_DIR!\python.exe" -c "import sys; sys.path.insert(0, r'%~dp0editor\source'); import server; print('OK: server.py loaded')"
if errorlevel 1 (
    echo ERROR: server.py import failed. Likely a missing dep in requirements.txt.
    pause
    exit /b 1
)

REM -- 7. Cleanup ---------------------------------------------
rmdir /S /Q "!BUILD_DIR!"

echo.
echo ============================================
echo   Done.
echo ============================================
echo.
echo Embedded Python bundle at:
echo   !DEST_DIR!
echo.
for /f %%S in ('powershell -NoProfile -Command "'{0:N1} MB' -f ((Get-ChildItem '!DEST_DIR!' -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB)"') do echo Size: %%S MB
echo.
echo Next: zip the whole SF6_Overlay_v1.0\ folder for distribution,
echo       or send editor\python\ back to Claude to repackage.
echo.
pause
endlocal
