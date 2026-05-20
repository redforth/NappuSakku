@echo off
REM ============================================================
REM SF6 Overlay Editor — launcher
REM
REM Detection order:
REM   1. editor\python\python.exe (bundled embedded Python)
REM   2. system Python on PATH (+ auto-venv)
REM   3. Error out with install instructions
REM ============================================================

setlocal

cd /d "%~dp0"

REM ── 1. Bundled embedded Python? ────────────────────────────
if exist "python\python.exe" (
    echo Using bundled Python.
    echo Starting editor at http://localhost:8765
    echo Close this window to stop the server.
    echo.
    "python\python.exe" source\server.py
    goto :end
)

REM ── 2. System Python fallback ──────────────────────────────
echo No bundled Python found, trying system Python...
python --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo ============================================
    echo   ERROR: Python not available
    echo ============================================
    echo.
    echo This package was distributed without the embedded Python
    echo bundle, and Python is not installed on your system.
    echo.
    echo Either:
    echo   A) Download the full package (includes Python), OR
    echo   B) Install Python 3.10+ from https://python.org
    echo      (tick "Add Python to PATH" during install), then
    echo      re-run this script.
    echo.
    pause
    exit /b 1
)

echo Preparing virtual environment...
if not exist "source\venv\Scripts\activate.bat" (
    python -m venv source\venv
    if errorlevel 1 (
        echo ERROR: failed to create venv.
        pause
        exit /b 1
    )
    call source\venv\Scripts\activate.bat
    python -m pip install --upgrade pip --quiet
    python -m pip install -r source\requirements.txt --quiet
) else (
    call source\venv\Scripts\activate.bat
)

echo.
echo Starting editor at http://localhost:8765
echo Close this window to stop the server.
echo.
python source\server.py

:end
endlocal
pause
