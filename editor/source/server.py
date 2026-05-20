"""
SF6 Overlay Editor — local web server.

Serves the editor frontend at http://localhost:8765 and provides
a JSON API for reading/writing the per-character JSON files in
the REFramework sf6_framedata folder.

First run: prompts for the sf6_framedata folder path and saves it
to settings.json next to the executable. Subsequent runs read that
path silently.

Run: python server.py    (or just double-click sf6_editor.exe after build)
"""

import io
import json
import os
import re
import shutil
import sys
import threading
import time
import webbrowser
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Any

# winreg is Windows-only stdlib; tolerate import failure so the
# script still runs from source on Linux/macOS for dev work.
try:
    import winreg  # type: ignore[import-not-found]
except ImportError:
    winreg = None  # type: ignore[assignment]

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn


# ── Paths ─────────────────────────────────────────────────────
# When frozen by PyInstaller, sys._MEIPASS is the temp extraction dir
# containing bundled data files (the frontend). The settings file
# lives next to the .exe so it survives between runs.
def app_dir() -> Path:
    """Folder containing the .exe (or the script when running from source)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).parent
    return Path(__file__).parent


def bundled_dir() -> Path:
    """Folder containing bundled read-only resources (frontend HTML)."""
    if getattr(sys, "frozen", False):
        return Path(sys._MEIPASS)  # type: ignore[attr-defined]
    return Path(__file__).parent.parent / "frontend"


def portraits_dir() -> Path:
    """Where character portrait PNGs live.

    When running as a frozen exe, prefer a `portraits/` folder sitting
    NEXT TO the exe — lets the user drop in/replace art without rebuilding.
    Falls back to the bundled location (frontend/portraits) if the
    external folder is missing or empty.

    When running from source, always use frontend/portraits.
    """
    if getattr(sys, "frozen", False):
        external = Path(sys.executable).parent / "portraits"
        if external.exists() and any(external.iterdir()):
            return external
    return bundled_dir() / "portraits"


SETTINGS_PATH = app_dir() / "settings.json"

# Last-resort fallback when settings.json is missing AND Steam autodetect
# fails (e.g. Steam not installed, or game not yet launched with REFramework).
# Empty string -> /roster returns "" -> frontend's FolderDialog opens so the
# user can pick the folder manually. Anything else would silently lock users
# into a path that doesn't exist on their machine.
DEFAULT_FRAMEDATA = ""

# Steam app ID for Street Fighter 6. Not used directly for path
# construction (we scan library folders instead, which is more robust
# than relying on an appID-keyed registry entry), but documented here
# in case future code needs to parse appmanifest_<id>.acf.
SF6_APP_ID = "1364780"

# Relative path from a Steam library root down to the framedata folder.
SF6_FRAMEDATA_REL = Path("steamapps") / "common" / "Street Fighter 6" / \
    "reframework" / "data" / "sf6_framedata"


def _steam_install_path() -> Path | None:
    """Read Steam's install dir from HKCU\\Software\\Valve\\Steam.

    Returns None on non-Windows, when Steam isn't installed, or if the
    key is missing/corrupt. Never raises — callers fall back to other
    detection methods.
    """
    if winreg is None:
        return None
    # Try HKCU first (per-user install, doesn't need admin); then HKLM
    # 32-bit view as the fallback for system-wide installs.
    candidates = [
        (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam",
         "InstallPath"),
    ]
    for hive, subkey, value_name in candidates:
        try:
            with winreg.OpenKey(hive, subkey) as k:
                val, _ = winreg.QueryValueEx(k, value_name)
                p = Path(str(val))
                if p.exists():
                    return p
        except OSError:
            continue
    return None


def _steam_libraries(steam_root: Path) -> list[Path]:
    """Return every Steam library folder this user has.

    Steam keeps a registry of library folders (one per drive) in
    `steamapps/libraryfolders.vdf`. The main install dir is always a
    library; additional ones get added when the user installs games
    on other drives. We parse the VDF with a regex because pulling in
    a real VDF library would bloat the PyInstaller bundle.
    """
    libs: list[Path] = [steam_root]
    vdf = steam_root / "steamapps" / "libraryfolders.vdf"
    if not vdf.exists():
        return libs
    try:
        text = vdf.read_text(encoding="utf-8", errors="ignore")
        # VDF stores paths with doubled backslashes ("E:\\SteamLibrary").
        # The regex captures the raw escaped form; we unescape before
        # constructing the Path.
        for m in re.finditer(r'"path"\s+"([^"]+)"', text):
            raw = m.group(1).replace("\\\\", "\\")
            p = Path(raw)
            if p.exists() and p not in libs:
                libs.append(p)
    except Exception as e:
        print(f"[warn] could not parse libraryfolders.vdf: {e}", flush=True)
    return libs


def _autodetect_framedata() -> Path | None:
    """Locate sf6_framedata/ by scanning every Steam library on the box.

    Returns the first match found. Returns None if Steam isn't
    installed, the user doesn't own SF6, or the REFramework mod folder
    hasn't been created yet (i.e. they haven't launched the game with
    REFramework installed).
    """
    root = _steam_install_path()
    if root is None:
        return None
    for lib in _steam_libraries(root):
        candidate = lib / SF6_FRAMEDATA_REL
        if candidate.exists():
            return candidate
    return None


def get_framedata_path() -> Path:
    """Resolve the sf6_framedata folder.

    Resolution order:
      1. `framedata_path` in settings.json (user-confirmed location)
      2. Steam registry + library scan (auto-detect on first run)
      3. Hard-coded DEFAULT_FRAMEDATA (last-resort fallback)

    On successful auto-detect we persist the path to settings.json so
    we only hit the registry once per install. The user can still
    override later via the editor's folder picker.
    """
    s = load_settings()
    saved = s.get("framedata_path")
    if saved and Path(saved).exists():
        return Path(saved)
    # Saved path is missing or no longer exists on this machine (e.g. the
    # exe was copied here from another box and settings.json hitched along,
    # or the drive letter changed). Drop the stale value and re-detect.
    if saved:
        print(
            f"[info] saved framedata_path '{saved}' no longer exists; "
            f"re-detecting",
            flush=True,
        )

    detected = _autodetect_framedata()
    if detected is not None:
        s["framedata_path"] = str(detected)
        try:
            save_settings(s)
        except Exception as e:
            # Non-fatal — we can still return the detected path even if
            # we couldn't cache it (e.g. read-only install location).
            print(f"[warn] could not save detected path: {e}", flush=True)
        return detected

    return Path(DEFAULT_FRAMEDATA)

# Roster mirrors the Lua script's ROSTER constant. Order matters for
# display purposes (groups originals vs. DLC).
ROSTER = [
    "Ryu", "Luke", "Kimberly", "Chun-Li", "Manon", "Zangief", "JP", "Dhalsim",
    "Cammy", "Ken", "Dee Jay", "Lily", "AKI", "Rashid", "Blanka", "Juri",
    "Marisa", "Guile", "Ed", "E.Honda", "Jamie", "Akuma", "Sagat", "M.Bison",
    "Terry", "Mai", "Elena", "C.Viper", "Alex",
]


# ── Settings ──────────────────────────────────────────────────
def load_settings() -> dict:
    if SETTINGS_PATH.exists():
        try:
            return json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def save_settings(s: dict) -> None:
    SETTINGS_PATH.write_text(json.dumps(s, indent=2), encoding="utf-8")


# get_framedata_path() is defined above (Steam autodetect chain).


# ── File helpers ──────────────────────────────────────────────
# Each character has its own folder; the JSONs live inside.
# combonotes.json — combo slot data (ticker overlay)
# notes.json      — profile card text + custom links (NEW)
# <Char>-framedata.json — read-only frame data (display reference)

def char_folder(name: str) -> Path:
    return get_framedata_path() / name


def hotkeys_path() -> Path:
    """Where the in-game hotkey config file lives.

    The Lua side (SF6_Overlay.lua) does `io.open("sf6_hotkeys.json")`
    which Lua resolves relative to `reframework/data/`. Since the
    framedata folder is `reframework/data/sf6_framedata/`, the parent
    of get_framedata_path() IS the data/ folder — exactly where the
    Lua looks. Writing here means the user doesn't have to manually
    drop the file anywhere.
    """
    return get_framedata_path().parent / "sf6_hotkeys.json"


def read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        raw = path.read_text(encoding="utf-8-sig")  # tolerates UTF-8 BOM
        return json.loads(raw)
    except Exception as e:
        print(f"[warn] could not parse {path}: {e}", flush=True)
        return default


def write_json(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    # Write WITHOUT a BOM — Lua's JSON parser silently breaks on BOM
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False),
                    encoding="utf-8")


COMBO_MAX_SLOTS = 30  # must match Lua COMBO_MAX_SLOTS
COMBO_MAX_ACTIVE = 5  # must match Lua COMBO_MAX_ACTIVE


def default_combonotes() -> dict:
    """Mirrors Lua default_combo_data — 30 slots, first 5 active by default."""
    return {
        "slots": [
            {
                "title": f"Slot {i + 1}",
                "active": i < COMBO_MAX_ACTIVE,
                "counter": 0,
                "tokens": [],
            }
            for i in range(COMBO_MAX_SLOTS)
        ]
    }


def pad_combonotes(data: dict) -> dict:
    """Pad a loaded combonotes payload up to COMBO_MAX_SLOTS.

    Legacy files on disk only have 10 slots. When a user upgrades to
    the 30-slot build, reading those files would only surface 10 slot
    buttons in the editor until the Lua side wrote back a 30-entry
    file. Padding here keeps editor / Lua slot counts in sync from the
    very first GET. Existing slot data is preserved as-is; only the
    new tail (slots 11..30 in the legacy case) is filled with empties.
    Active flags on new tail slots default to False so they don't
    silently push the active count over COMBO_MAX_ACTIVE.
    """
    if not isinstance(data, dict):
        return default_combonotes()
    slots = data.get("slots")
    if not isinstance(slots, list):
        return default_combonotes()
    if len(slots) >= COMBO_MAX_SLOTS:
        # Trim defensively if a file somehow grew past the cap so the
        # editor can't display rows the Lua side will never persist.
        data["slots"] = slots[:COMBO_MAX_SLOTS]
        return data
    for i in range(len(slots), COMBO_MAX_SLOTS):
        slots.append({
            "title": f"Slot {i + 1}",
            "active": False,
            "counter": 0,
            "tokens": [],
        })
    return data


def default_notes() -> dict:
    return {
        "notes": "",       # in-game profile card text
        "links": [],       # [{label, url}]
    }


# ── Models ────────────────────────────────────────────────────
class NotesIn(BaseModel):
    notes: str
    links: list[dict]


class CombosIn(BaseModel):
    slots: list[dict]


class FolderIn(BaseModel):
    path: str


class HotkeysIn(BaseModel):
    """In-game controller hotkey config. Shape matches the v2 schema
    written by the editor's Settings → SHIFT CONFIG modal:

        {
          "version": 2,
          "active": "<profile name>",
          "profiles": {
            "<profile name>": { "modifier": "MK", "bindings": {...} },
            ...
          }
        }

    `active` names which profile the Lua should use; all profiles are
    persisted so future per-controller auto-switching is possible
    without re-exporting. Validation is intentionally loose (just type
    checks) — the Lua loader does its own button-name whitelist before
    applying anything, so junk values can't break the runtime.
    """
    version: int = 2
    active: str = "default"
    profiles: dict


# ── App ───────────────────────────────────────────────────────
app = FastAPI(title="SF6 Overlay Editor")

# CORS open since we only ever bind to 127.0.0.1 — but allow any
# origin so the user could theoretically open the HTML directly
# from disk and still talk to the server.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health():
    fp = get_framedata_path()
    return {
        "ok": True,
        "framedata_path": str(fp),
        "folder_exists": fp.exists(),
    }


@app.get("/api/settings")
def get_settings_api():
    return {"framedata_path": str(get_framedata_path())}


@app.put("/api/settings/folder")
def set_folder(body: FolderIn):
    p = Path(body.path)
    if not p.exists():
        raise HTTPException(400, f"Folder does not exist: {p}")
    s = load_settings()
    s["framedata_path"] = str(p)
    save_settings(s)
    return {"ok": True, "framedata_path": str(p)}


@app.get("/api/roster")
def roster():
    """Return the static roster + per-character existence flags."""
    base = get_framedata_path()
    out = []
    for name in ROSTER:
        folder = base / name
        out.append({
            "name": name,
            "folder_exists": folder.exists(),
            "has_combonotes": (folder / "combonotes.json").exists(),
            "has_notes": (folder / "notes.json").exists(),
        })
    return {"characters": out, "framedata_path": str(base)}


def _safe_mtime(path: Path) -> float:
    """Return the file's mtime, or 0.0 if missing/unreadable.

    Used by the editor's live-refresh polling so it can cheaply detect
    when the Lua overlay (or an external editor) has rewritten one of
    the per-character JSONs and pull the new contents in without a
    full page refresh. 0.0 is a safe sentinel — it sorts before any
    real mtime, so a transient stat error during polling won't trigger
    a spurious refresh.
    """
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


@app.get("/api/character/{name}")
def get_character(name: str):
    if name not in ROSTER:
        raise HTTPException(404, f"Unknown character: {name}")
    folder = char_folder(name)
    # Classic and Modern combos are stored in separate files so per-character
    # scheme switches in the editor don't clobber the other set. The Lua side
    # reads whichever file matches the active control_scheme; the editor needs
    # both so the user can flip schemes without a reload.
    # Pad legacy 10-slot files up to COMBO_MAX_SLOTS so the editor and
    # the Lua side stay aligned on slot count from the first GET — see
    # pad_combonotes() docstring for rationale.
    combos = pad_combonotes(read_json(folder / "combonotes.json", default_combonotes()))
    combos_modern = pad_combonotes(read_json(folder / "moderncombonotes.json", default_combonotes()))
    notes = read_json(folder / "notes.json", default_notes())
    # mtimes ship with the payload so the client's live-refresh poll
    # can compare against /api/character/{name}/mtime later without
    # an extra initial round-trip.
    return {
        "name": name,
        "folder": str(folder),
        "combos": combos,
        "combos_modern": combos_modern,
        "notes": notes,
        "mtime": {
            "combos":        _safe_mtime(folder / "combonotes.json"),
            "combos_modern": _safe_mtime(folder / "moderncombonotes.json"),
            "notes":         _safe_mtime(folder / "notes.json"),
        },
    }


@app.get("/api/character/{name}/mtime")
def get_character_mtime(name: str):
    """Cheap mtime-only endpoint for live-refresh polling.

    The editor polls this every ~1.5s while a character page is open.
    Compared against the mtimes returned by /api/character/{name} on
    initial load (or the last successful refetch) to decide whether
    any underlying JSON has changed on disk. Three stat() calls per
    poll — negligible CPU even with the editor open all day.
    """
    if name not in ROSTER:
        raise HTTPException(404, f"Unknown character: {name}")
    folder = char_folder(name)
    return {
        "combos":        _safe_mtime(folder / "combonotes.json"),
        "combos_modern": _safe_mtime(folder / "moderncombonotes.json"),
        "notes":         _safe_mtime(folder / "notes.json"),
    }


@app.put("/api/character/{name}/notes")
def put_notes(name: str, body: NotesIn):
    if name not in ROSTER:
        raise HTTPException(404, f"Unknown character: {name}")
    write_json(char_folder(name) / "notes.json", body.dict())
    return {"ok": True}


@app.put("/api/character/{name}/combos")
def put_combos(name: str, body: CombosIn):
    if name not in ROSTER:
        raise HTTPException(404, f"Unknown character: {name}")
    write_json(char_folder(name) / "combonotes.json", body.dict())
    return {"ok": True}


@app.put("/api/character/{name}/combos_modern")
def put_combos_modern(name: str, body: CombosIn):
    """Write the Modern-scheme combo set for this character.

    Mirrors put_combos but targets moderncombonotes.json. Same payload
    shape — the Lua side picks which file to load based on the active
    control_scheme stored in the character's profile.
    """
    if name not in ROSTER:
        raise HTTPException(404, f"Unknown character: {name}")
    write_json(char_folder(name) / "moderncombonotes.json", body.dict())
    return {"ok": True}


@app.post("/api/hotkeys")
def save_hotkeys(body: HotkeysIn):
    """Write the per-profile hotkey config to reframework/data/sf6_hotkeys.json.

    The atomic write pattern (write to .tmp, then rename) guards
    against leaving a partial/corrupt file if the process is killed
    mid-write — important here because the Lua loader runs at script
    load time and would silently fall back to defaults on a parse
    error, which would look like a bug to the user.
    """
    target = hotkeys_path()
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        # Use the same encoding rules as write_json — no BOM, indent=2,
        # ensure_ascii=False so any non-ASCII profile names round-trip.
        payload = body.dict()
        tmp = target.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps(payload, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        # os.replace is atomic on POSIX and (since 3.3) on Windows when
        # the destination exists. Path.replace wraps it.
        tmp.replace(target)
        return {"ok": True, "path": str(target)}
    except Exception as e:
        # 500 + structured error — the client's save state machine
        # surfaces the message in the SAVE button's status text.
        return JSONResponse(
            {"ok": False, "error": str(e)},
            status_code=500,
        )


# ── Backup & Restore ──────────────────────────────────────────
# Bundle every user-created file into a single ZIP and reverse the
# operation on import. Atomic-restore discipline: stage all incoming
# files to <framedata>/.restore_tmp/, validate every JSON parses,
# THEN swap into place. A partial failure mid-restore (corrupt file,
# disk full) is the worst-case data-loss scenario, so we never touch
# real files until every staged file is known-good.
BACKUP_VERSION = 1


def _overlay_config_path() -> Path:
    """reframework/data/sf6_overlay_config.json — Lua-side global config.

    Lives one level above the framedata folder (same as sf6_hotkeys.json).
    """
    return get_framedata_path().parent / "sf6_overlay_config.json"


def _safe_relpath(member_name: str) -> bool:
    """Reject zip entries that would escape the staging dir (Zip-Slip).

    A malicious archive could contain a member named '../../foo' which
    on naive extraction writes outside the intended folder. Reject any
    path containing '..', leading slashes, or drive letters.
    """
    if not member_name:
        return False
    if ".." in Path(member_name).parts:
        return False
    if member_name.startswith(("/", "\\")):
        return False
    # Reject Windows drive letters (C:\, D:/, etc.)
    if len(member_name) >= 2 and member_name[1] == ":":
        return False
    return True


def _collect_backup_files() -> list[tuple[str, Path]]:
    """Return list of (zip_arcname, source_path) for everything to back up.

    Only existing files are included — missing files (e.g. no Modern
    combos for a character) just don't end up in the archive. Restore
    treats absence as "leave existing file alone".

    NOT backed up: <Char>-framedata.json reference files. Those are
    read-only data shipped with the installer; the updater script
    regenerates them. Backing them up would risk overwriting fresh
    updater output with stale data.
    """
    out: list[tuple[str, Path]] = []
    base = get_framedata_path()

    # Lua global configs (sit one level above the framedata folder)
    cfg = _overlay_config_path()
    if cfg.exists():
        out.append(("sf6_overlay_config.json", cfg))

    hk = hotkeys_path()
    if hk.exists():
        out.append(("sf6_hotkeys.json", hk))

    # Server's own settings.json (holds the framedata path). Tagged
    # separately so restore can offer it as an opt-in — backups made
    # on one PC have paths that won't exist on another.
    if SETTINGS_PATH.exists():
        out.append(("server_settings.json", SETTINGS_PATH))

    # Per-character user data — combos (both schemes) + notes.
    for name in ROSTER:
        folder = base / name
        for fname in ("combonotes.json", "moderncombonotes.json", "notes.json"):
            src = folder / fname
            if src.exists():
                out.append((f"characters/{name}/{fname}", src))

    return out


def _arcname_to_dest(arcname: str) -> Path:
    """Map a zip entry name back to its destination on disk."""
    base = get_framedata_path()
    if arcname == "sf6_overlay_config.json":
        return _overlay_config_path()
    if arcname == "sf6_hotkeys.json":
        return hotkeys_path()
    if arcname == "server_settings.json":
        return SETTINGS_PATH
    if arcname.startswith("characters/"):
        parts = arcname.split("/")
        if len(parts) == 3:
            return base / parts[1] / parts[2]
    raise ValueError(f"unknown arcname: {arcname}")


@app.get("/api/backup/export")
def export_backup():
    """Build a ZIP of all user-created data and return it as a download.

    Assembled in memory via BytesIO so no stale backup files sit on
    disk between exports. JSON compresses extremely well with DEFLATE
    so the archive is tens of KB for typical installs.
    """
    timestamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
    filename = f"sf6_backup_{timestamp}.zip"

    files = _collect_backup_files()

    manifest = {
        "version": BACKUP_VERSION,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "framedata_path": str(get_framedata_path()),
        "file_count": len(files),
        "files": [arcname for arcname, _ in files],
    }

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        # Manifest first so `unzip -l` shows it at the top
        zf.writestr(
            "manifest.json",
            json.dumps(manifest, indent=2, ensure_ascii=False),
        )
        for arcname, src in files:
            # Read+write rather than zf.write(src) so we don't leak
            # the host filesystem's absolute path into archive metadata
            try:
                data = src.read_bytes()
                zf.writestr(arcname, data)
            except Exception as e:
                # Skip unreadable files but keep going — better to ship
                # a partial backup than fail the whole export
                print(f"[backup] could not read {src}: {e}", flush=True)

    buf.seek(0)
    return Response(
        content=buf.getvalue(),
        media_type="application/zip",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            # Backups should never be cached — every export is fresh
            "Cache-Control": "no-store",
        },
    )


@app.post("/api/backup/import")
async def import_backup(
    file: UploadFile = File(...),
    restore_server_settings: str = Form("false"),
):
    """Restore from a backup ZIP. Atomic-swap each file into place.

    Multipart form fields:
        file: the .zip file (required)
        restore_server_settings: "true" to also restore server_settings.json
            (the framedata path). Default "false" — restoring on a
            different PC than the backup was made would point the
            editor at a non-existent folder.

    Response shape:
        { ok, files_restored, skipped, errors, reload_required, message }
    """
    do_settings = restore_server_settings.lower() in ("true", "1", "yes")

    # Read entire upload into memory. Backups are small (KB scale);
    # streaming would complicate the two-pass validation flow.
    raw = await file.read()
    if not raw:
        return JSONResponse(
            {"ok": False, "error": "empty upload"},
            status_code=400,
        )

    base = get_framedata_path()
    if not base.exists():
        return JSONResponse(
            {"ok": False, "error": f"framedata folder does not exist: {base}"},
            status_code=400,
        )

    staging = base / ".restore_tmp"
    # Clean any leftover staging from a previous failed run
    if staging.exists():
        shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True, exist_ok=True)

    files_restored: list[str] = []
    skipped: list[str] = []
    errors: list[dict] = []

    try:
        try:
            zf = zipfile.ZipFile(io.BytesIO(raw), "r")
        except zipfile.BadZipFile:
            return JSONResponse(
                {"ok": False, "error": "file is not a valid ZIP archive"},
                status_code=400,
            )

        with zf:
            names = zf.namelist()

            if "manifest.json" not in names:
                return JSONResponse(
                    {"ok": False,
                     "error": "not a valid SF6 backup (no manifest.json)"},
                    status_code=400,
                )

            try:
                manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
            except Exception as e:
                return JSONResponse(
                    {"ok": False, "error": f"corrupt manifest.json: {e}"},
                    status_code=400,
                )

            mver = manifest.get("version", 0)
            if mver > BACKUP_VERSION:
                return JSONResponse(
                    {"ok": False,
                     "error": (f"backup version {mver} is newer than this "
                               f"editor supports (max {BACKUP_VERSION}). "
                               "Update the editor.")},
                    status_code=400,
                )

            # ── Pass 1: stage every file, validate JSON parses ──
            # If ANY file fails to parse, abort before touching the
            # real install.
            staged_files: list[tuple[str, Path]] = []
            for arcname in names:
                if arcname == "manifest.json":
                    continue
                if not _safe_relpath(arcname):
                    errors.append({"file": arcname, "error": "unsafe path"})
                    continue

                # Server-settings opt-in gate
                if arcname == "server_settings.json" and not do_settings:
                    skipped.append(arcname)
                    continue

                data = zf.read(arcname)
                try:
                    # Tolerate BOM in older backups
                    text = data.decode("utf-8-sig")
                    json.loads(text)
                except Exception as e:
                    errors.append({"file": arcname, "error": f"invalid JSON: {e}"})
                    continue

                stage_path = staging / arcname
                stage_path.parent.mkdir(parents=True, exist_ok=True)
                # Re-encode without BOM (Lua JSON parser breaks on BOM)
                stage_path.write_text(text, encoding="utf-8")
                staged_files.append((arcname, stage_path))

            if errors:
                # Validation failed — abort. Real files are untouched.
                return JSONResponse(
                    {"ok": False, "errors": errors,
                     "message": "validation failed, no files restored"},
                    status_code=400,
                )

            # ── Pass 2: atomic-swap each staged file into final spot ──
            for arcname, stage_path in staged_files:
                try:
                    dest = _arcname_to_dest(arcname)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    # server_settings.json lives next to the .exe which
                    # may be on a different volume than staging — use
                    # copy+remove instead of replace (which fails
                    # cross-volume on Windows).
                    if arcname == "server_settings.json":
                        shutil.copy2(stage_path, dest)
                    else:
                        # os.replace is atomic on same volume. Staging
                        # lives inside the framedata folder, so this
                        # holds for everything except server_settings.
                        os.replace(stage_path, dest)
                    files_restored.append(arcname)
                except Exception as e:
                    errors.append({"file": arcname, "error": str(e)})

    finally:
        # Always clean up staging — leftover empty dirs would clutter
        # the framedata folder.
        shutil.rmtree(staging, ignore_errors=True)

    return {
        "ok": len(errors) == 0,
        "files_restored": files_restored,
        "skipped": skipped,
        "errors": errors,
        "reload_required": True,
        "message": (
            "Restore complete. Click 'Reload Script' in the in-game "
            "Profiles menu to apply changes."
        ),
    }


# ── Static frontend ───────────────────────────────────────────
# Serve index.html at root; everything else under /static.
# Portraits live at /portraits/<Name>.<ext> and are served from
# bundled_dir()/portraits — see the fallback handler below.
@app.get("/")
def root():
    return FileResponse(bundled_dir() / "index.html")


# Explicit MIME map for image types Windows occasionally misregisters.
# Without these, WebP can ship as application/octet-stream on bare
# Windows installs and the browser refuses to render it.
MEDIA_MIME = {
    ".webp": "image/webp",
    ".png":  "image/png",
    ".jpg":  "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif":  "image/gif",
}


@app.get("/{path:path}")
def fallback(path: str):
    """SPA-style fallback so the React app handles its own routing.

    /portraits/* is special-cased: served from portraits_dir() which
    prefers a folder next to the exe (drop-in art, no rebuild needed).
    Missing portraits return 404 — important so the <img onError>
    fallback chain in index.html actually fires (returning HTML
    would make the browser think the load succeeded).
    """
    if path.startswith("portraits/"):
        rel = path[len("portraits/"):]
        # Strip query strings like ?_=123456 used for cache-busting
        rel = rel.split("?", 1)[0]
        p = portraits_dir() / rel
        if p.exists() and p.is_file():
            ext = p.suffix.lower()
            media_type = MEDIA_MIME.get(ext)
            # Nuclear no-cache: no-store tells the browser to never
            # save the response to disk or memory. Combined with the
            # legacy Pragma/Expires headers, this defeats every cache
            # layer including Brave's stubborn image cache. Trade-off:
            # every hover re-downloads the file. On localhost that's
            # ~5ms for a 4K PNG — negligible. For production, swap
            # to "max-age=300" or similar.
            return FileResponse(
                p,
                media_type=media_type,
                headers={
                    "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
                    "Pragma": "no-cache",
                    "Expires": "0",
                },
            )
        return JSONResponse({"error": "portrait not found"}, status_code=404)

    p = bundled_dir() / path
    if p.exists() and p.is_file():
        ext = p.suffix.lower()
        if ext in MEDIA_MIME:
            return FileResponse(p, media_type=MEDIA_MIME[ext])
        return FileResponse(p)
    return FileResponse(bundled_dir() / "index.html")


# ── Entry point ───────────────────────────────────────────────
def open_browser_delayed():
    """Wait a moment for the server to come up, then open the editor."""
    time.sleep(1.2)
    try:
        webbrowser.open("http://localhost:8765/")
    except Exception:
        pass


def main():
    print("=" * 60)
    print("SF6 Overlay Editor")
    print(f"Settings file: {SETTINGS_PATH}")
    print(f"Frame data folder: {get_framedata_path()}")
    print(f"Open in browser: http://localhost:8765/")
    print("Press Ctrl+C to stop the server.")
    print("=" * 60)
    threading.Thread(target=open_browser_delayed, daemon=True).start()
    uvicorn.run(app, host="127.0.0.1", port=8765, log_level="warning")


if __name__ == "__main__":
    main()
