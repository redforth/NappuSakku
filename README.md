# NappuSakku — SF6 Overlay

An enhanced UI and integrated web app for combo notation in Street Fighter 6.

Real-time training and match overlay for Street Fighter 6.

---

## What's New in This Release

- **Automatic roster updates.** New characters are added to both the overlay and the web app automatically as Capcom releases them — no code update required from me. (See [Automatic Roster Updates](#automatic-roster-updates) for how it works.)
- **Reorganized icon layout.** Icons in both the web app and the in-game overlay have been rearranged to flow better and read more clearly.
- **New overlay hotkeys.** A set of `LK + MP` chord shortcuts for driving the Combo Editor without the keyboard. (See [Overlay Hotkeys](#overlay-hotkeys).)
- **Input icons in the web app.** Combo inputs can now be displayed as icons in the web app. Toggle this in the overlay's in-game **Display** settings, or at the top of the web app page.
- **New input glyphs.** Added graphic icons for 360F and 360B motions — for the loyal fans — plus scaled `PP` / `KK` and `3×P` / `3×K` icons for characters whose OD moves correspond to different button strengths, and for characters like Ingrid who use three punch or kick buttons in their movesets.

---

## TL;DR — Quick Install

For the impatient. Each step is detailed later in this guide.

1. Unzip `NappuSakku-main.zip` anywhere convenient (Desktop, Downloads, Documents).
2. Double-click `install.bat`. Everything is installed automatically: REFramework, the d2d plugin, the overlay, and frame data from FAT.
3. Launch SF6. Press **Insert** in-game to confirm the overlay loaded — look for the **Display** and **Combo Editor** tabs.
4. Launch the editor from your desktop shortcut (created by the installer) or by double-clicking `editor\run_editor.bat`. Your browser opens at `http://localhost:8765`.

---

## What You're Installing

The SF6 Overlay is a REFramework-based mod that adds a real-time training overlay to Street Fighter 6. After install you get:

- **On-screen combo ticker** showing combos you've authored, displayed during matches and training.
- **In-game combo editor** so you can tweak combos without leaving the game.
- **Web app editor** for authoring combos, notes, and video references (runs locally in your browser). Edits made here update the in-game ticker bar.
- **YouTube-based video player.** Load a video with combos and follow along, building a combo directly into the ticker as it plays. Supports rewind, fast-forward, and timestamp saving so you can replay from a specific point.
- **Character profile text** under each fighter's name for personal play notes.
- **Health-bar tick marks** at 10% intervals so you can see exact damage thresholds and CA timing.
- **Modern control scheme supported.**
- ...and more.

---

## Automatic Roster Updates

As of this release, new characters are picked up automatically — you don't need a code update from me when a new fighter drops.

Here's the flow:

1. On game launch, the overlay script reads the current roster and writes it to a JSON file in `<SF6>\reframework\data\`.
2. `server.py` and `index.html` read that roster on startup and adjust the Combo Editor and the web app's character page for any new characters.
3. **Launch order matters:** start the game first, then start the web app, so the roster file is written before the web app reads it.
4. Saving a combo in either the web app or the in-game editor creates the character's folder under `<SF6>\reframework\data\sf6_framedata\`.

**Frame data is the one exception.** Because it comes from an external source (FAT), it won't populate automatically for a brand-new character. Run `tools\SF6_FrameData_Updater.ps1` to pull the latest data. Barring future REFramework or d2d updates that break compatibility, the roster code shouldn't need to be touched again.

New character art is bundled with future web app updates, but you're free to drop in your own art at any time.

---

## Overlay Hotkeys

While holding **`LK + MP`**, press:

| Key | Action |
| --- | --- |
| **MK** | Open / close the Combo Editor |
| **HK** | Enable / disable input recording — turn it off to practice with the editor open |
| **Left / Right** | Move the cursor back / forward |
| **LP** | Backspace in the input field |
| **HP** | Insert a spacer icon (`>`) in the input field |

---

## What the Installer Does Automatically

The installer is a single-click experience. Here's everything it handles for you, in order:

### 1. SF6 detection

Reads the Steam registry and scans `libraryfolders.vdf` to find your SF6 install — even on secondary drives. If auto-detection fails, you'll be prompted to enter the path manually.

### 2. Existing-install detection

If you already have a previous version of the overlay installed, the installer detects it and offers to back up your existing frame data folder. The backup is saved as a timestamped zip inside your installer folder (e.g. `sf6_framedata_backup_2026-05-18_15-30-45.zip`). Your combo notes and customizations are preserved. If backup creation fails, the installer aborts to avoid data loss.

### 3. REFramework auto-install

Downloads REFramework v1.5.9.1 directly from praydog's GitHub (with automatic fallback to the latest version if the pinned URL is unavailable). Extracts **only** `dinput8.dll` into the SF6 folder, and pre-creates the `reframework\autorun\`, `plugins\`, `data\`, and `scripts\` subfolders.

> **TECH NOTE:** praydog's release notes explicitly warn that only `dinput8.dll` should be extracted from `SF6.zip` — extracting the rest can crash the game. The installer enforces this rule strictly. REFramework uses DLL injection via `dinput8`: Windows loads `dinput8.dll` from the game folder before falling back to the system copy, which gives REFramework the hook it needs to attach.

### 4. reframework-d2d plugin auto-install

Downloads the latest `reframework-d2d` release from cursey's GitHub. Extracts the plugin DLL into `<SF6>\reframework\plugins\` and any included helper Lua into `<SF6>\reframework\autorun\`. The d2d plugin gives REFramework Lua scripts access to Direct2D drawing — the overlay uses this for the combo ticker and HUD elements.

### 5. Overlay script copy

Copies the overlay into `<SF6>\reframework\autorun\SF6_Overlay.lua`. This is the actual mod file.

### 6. Frame data download

Runs the frame data updater to pull the current frame data from FAT (Frame Assistant Tool) on GitHub. Creates `<SF6>\reframework\data\sf6_framedata\<CharacterName>\framedata.json` for each character (one folder per character). If the download fails (no internet, GitHub down, corporate firewall), the installer automatically falls back to bundled offline frame data, current as of the package's release date.

### 7. Desktop shortcut (opt-in)

At the end, you're asked whether to create a desktop shortcut for the SF6 Overlay Editor. The shortcut points at `editor\run_editor.bat` inside your unzipped folder, and launches without a visible console window.

> **TECH NOTE:** What gets written to your SF6 folder:
> - `<SF6>\dinput8.dll` (REFramework)
> - `<SF6>\reframework\plugins\reframework-d2d.dll` (d2d plugin)
> - `<SF6>\reframework\autorun\SF6_Overlay.lua` (the overlay)
> - `<SF6>\reframework\data\sf6_framedata\<CharacterName>\framedata.json` (frame data, one folder per character)
>
> The installer does **not** touch game files, save data, or anything outside the `reframework\` subfolder.

---

## Installation Steps

1. **Unzip** `NappuSakku-main.zip` somewhere convenient. Your Desktop, Downloads, or Documents folder is fine — but **do not delete this folder after install** if you create a desktop shortcut, because the shortcut points back at the `editor\` subfolder inside it.
2. **Double-click** `install.bat`.
3. **Watch the progress.** You'll see five steps run sequentially:

   ```
   Step 1/5: REFramework
   Step 2/5: reframework-d2d plugin
   Step 3/5: Overlay script
   Step 4/5: Frame data
   Step 5/5: Desktop shortcut
   ```

4. **Answer Y/N to the shortcut prompt** at the end. Press `Y` (recommended) to get a desktop shortcut, or `N` to skip.
5. When you see `Install complete.`, close the window.

> **TECH NOTE:** Windows SmartScreen may briefly flash a warning when `install.bat` runs PowerShell helpers — this is expected for unsigned scripts and does not indicate malware. The installer uses `-ExecutionPolicy Bypass` for the duration of its own helpers, which does not modify your system-wide PowerShell policy.

---

## Verifying the Install

1. Launch Street Fighter 6 normally through Steam.
2. Once at the main menu, press **Insert** on your keyboard to open the REFramework menu.
3. Look for the overlay's menu items: you should see the **Display** and **Combo Editor** tabs. If they're there, the overlay loaded successfully.

If the overlay does not appear, open the REFramework **Script Runner** (in the REFramework menu) and check whether `SF6_Overlay.lua` loaded or threw an error.

> **TECH NOTE:** REFramework auto-unloads Lua scripts during online ranked matches. This is intentional anti-cheat safety built into REFramework itself — the overlay package does not override it. The overlay will go dark in ranked and reappear automatically in training, casual, replays, and offline modes.

---

## Launching the Web Editor

The editor lets you author combos while watching a linked video, write play notes, and save resource links for each character. You can run the overlay without ever opening the editor, but the editor bridges the gap between research and training. **Combos authored in the editor appear in the in-game overlay without requiring a game restart** (you may need to re-select the combo in SF6 if you've edited it).

Remember the launch order from [Automatic Roster Updates](#automatic-roster-updates): start the game first, then the web app.

### Easy way

Double-click the **SF6 Overlay Editor** shortcut on your desktop (created during install, if you opted in).

### Manual way

1. In the unzipped `NappuSakku-main` folder, open the `editor` subfolder.
2. Double-click `run_editor.bat`.

### What happens on launch

- On **first launch**, `run_editor.bat` checks for a bundled Python at `editor\python\python.exe`. If present (the default), it launches the editor immediately. If absent (slim package), it falls back to system Python and auto-creates an isolated virtual environment with the required packages.
- Your browser opens automatically to `http://localhost:8765`. If it doesn't, open that URL manually.
- On **very first launch**, the editor asks where your frame-data folder lives. The correct default is:

  ```
  <your SF6 folder>\reframework\data\sf6_framedata
  ```

  This is the folder `install.bat` created. The editor saves this path to `editor\source\settings.json`, so you only set it once.

> **TECH NOTE:** The editor runs a local FastAPI server on port 8765. It only listens on `localhost` — nothing is exposed to the internet. Closing the `run_editor` console window stops the server. If port 8765 is already in use, edit the port number near the bottom of `editor\source\server.py`.

---

## Optional — Python (Only If the Bundle Was Removed)

The overlay package includes a self-contained Python runtime in `editor\python\`, so you do not need Python installed on your system. However, if you received a slim version of the package without the embedded Python folder, run `build_embedded.bat` to download and compile the necessary Python requirements and dependencies. This is a fairly short process and should not interfere with any Python projects or environments already on your machine.

---

## Refreshing Frame Data After SF6 Patches

Capcom adjusts frame data with every balance patch. To pull the latest numbers without reinstalling everything:

1. In the unzipped `NappuSakku-main` folder, open the `tools` subfolder.
2. Right-click `SF6_FrameData_Updater.ps1` and choose **Run with PowerShell**.
3. If Windows blocks PowerShell execution, open a Command Prompt in the `tools` folder and run:

   ```
   powershell -ExecutionPolicy Bypass -File SF6_FrameData_Updater.ps1
   ```

4. The script downloads `SF6FrameData.json` from the FAT GitHub repo and overwrites the per-character `framedata.json` files. **Your combos, notes, and SHIFT bindings are stored separately and are not affected.**

### Alternative: re-run install.bat

You can also just re-run `install.bat`. It detects your existing install, offers to back up your current frame data to a timestamped zip, then proceeds with a clean reinstall pulling the latest from FAT.

---

## Reinstalling / Updating

If a new version of the overlay is released, or you want a clean reinstall:

1. Download and unzip the new `NappuSakku-main.zip` (overwrite the old folder, or extract to a new location).
2. Double-click `install.bat`.
3. When prompted with **"Existing SF6 Overlay install detected. Proceed with reinstall (recommended) [Y,N]?"**, press `Y`.
4. The installer creates a timestamped backup zip of your existing frame data inside the unzipped folder (e.g. `sf6_framedata_backup_2026-05-18_15-30-45.zip`).
5. Reinstall proceeds normally.

If you change your mind, press `N` at the prompt to cancel safely — nothing is touched.

---

## Uninstalling

To completely remove the overlay:

1. Delete `<SF6>\reframework\autorun\SF6_Overlay.lua`.
2. Delete the entire folder `<SF6>\reframework\data\sf6_framedata\`.
3. Delete your unzipped `NappuSakku-main` folder.
4. Delete the desktop shortcut, if you created one.

REFramework itself and the d2d plugin are untouched and remain usable for other RE Engine games. To also remove those:

- Delete `<SF6>\dinput8.dll` (removes REFramework).
- Delete `<SF6>\reframework\plugins\reframework-d2d.dll` (removes the d2d plugin).
- Optionally, delete the entire `<SF6>\reframework\` folder.

---

## Troubleshooting

### Installer says "StreetFighter6.exe not found"

Auto-detection failed. The installer falls back to a manual prompt — enter the full path to your SF6 folder (the folder containing `StreetFighter6.exe`), not a parent folder. Example:

```
D:\SteamLibrary\steamapps\common\Street Fighter 6
```

### Installer says "REFramework auto-install reported errorlevel N"

The download failed (network issue, GitHub down, antivirus blocking). The installer continues but warns you. To recover:

1. Manually download `SF6.zip` from https://github.com/praydog/REFramework/releases.
2. Extract **only** `dinput8.dll` into your SF6 folder.
3. Re-run `install.bat` — it will skip the REFramework step (already present) and continue with the rest.

### Installer says "reframework-d2d auto-install reported errorlevel N"

Same kind of network issue. To recover:

1. Manually download the latest `.zip` from https://github.com/cursey/reframework-d2d/releases.
2. Extract its `reframework\plugins\reframework-d2d.dll` into `<SF6>\reframework\plugins\`.
3. Re-run `install.bat` if you want to verify the rest.

### Overlay doesn't load in-game

- Check that `dinput8.dll` is in the SF6 folder (REFramework installed).
- Check that `reframework-d2d.dll` is in `<SF6>\reframework\plugins\`.
- Press **Insert** in-game, open REFramework's **Script Runner**, find `SF6_Overlay.lua`, and check for error messages.
- Verify that `<SF6>\reframework\data\sf6_framedata\Ryu\framedata.json` exists (any character folder works for this check).

### Editor says "No Python found" or fails to launch

The bundled Python at `editor\python\` may be missing. Either:

- Run `build_embedded.bat` to rebuild it (requires internet access), or
- Install Python 3.10+ from https://python.org and re-run `run_editor.bat` — it will fall back to system Python and create a venv automatically.

### Editor can't save to the folder

Check that the folder option at the top of the screen is set to `Street Fighter 6\reframework\data\sf6_framedata`.

### Port 8765 is already in use

Some other application is using that port. The easiest fix is to stop the other application. Otherwise, edit `editor\source\server.py`, find the `8765` value near the bottom of the file, and change it to a different port (e.g. `8766`).

### Frame data updater fails to download

The FAT GitHub repository structure occasionally changes. The updater tries multiple URL paths before giving up. If all attempts fail, the installer falls back to the bundled offline frame data (current as of the package's release date). Check https://github.com/D4RKONION/FAT for the current file path if you want to pull the latest data manually.

### Desktop shortcut points to a missing file

You moved or deleted the unzipped `NappuSakku-main` folder after creating the shortcut. To fix:

- Move the folder back to its original location, **or**
- Re-run `install.bat` from the new location and choose `Y` at the desktop shortcut prompt — the shortcut will be updated to point at the new path.

### Antivirus flags w32.exe inside the editor's Python folder

This is a false positive on a legitimate file shipped with pip (a Windows launcher stub used when pip installs console-script packages). If your AV quarantines it, the editor still works because the overlay doesn't use pip at runtime. To silence the warning permanently, the slim version of the package strips pip out entirely — use `build_embedded.bat` to recreate the Python folder cleanly.

---

## Credits

- **FAT (Frame Assistant Tool)** frame data by D4RKONION — https://github.com/D4RKONION/FAT
- **REFramework** by praydog — https://github.com/praydog/REFramework
- **reframework-d2d** by cursey — https://github.com/cursey/reframework-d2d
