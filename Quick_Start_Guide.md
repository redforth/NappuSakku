# SF6 Overlay — Quick Start Guide

Here's how to get up and running in under 2 minutes.

If you haven't installed yet, see the **Installation Guide** first. For full reference, see the **User Manual**.

\---

## 1\. Launch the Editor

Double-click the **SF6 Overlay Editor** shortcut on your desktop (or `editor\\run\_editor.bat` inside your install folder). Your browser opens at `http://localhost:8765`.

\---

## 2\. Set Your Notation Preference

Top-right of the home screen, you'll see a **NUMPAD / LETTERS** toggle.

* **NUMPAD** — `236 LP` for Hadoken (1–9 directions)
* **LETTERS** — `QCF LP` for Hadoken (D/F/B/U notation + shorthand like QCF, DP, HCB)

\---

## 3\. Configure Your Controller

Click **SETTINGS** (top-right), then scroll down to **GAMEPAD INPUT** and click **ADD CONTROLLER / KEYBOARD**.

> \*\*A quick note about controller detection\*\*
> If you don't see your controller, press any direction/button on it, they go to sleep fast.
> Many fight sticks and pads will show up as "Xbox 360 Controller" regardless of what they actually are. This is normal — browsers report controllers through a generic Xbox 360 mapping. As long as the device appears in the list and the dot next to it is green, you're good. The calibration step below maps your physical buttons individually, so the reported name doesn't matter.

Pick your device from the list. The editor walks you through pressing each input.



### Phase 1 — Classic Calibration

Configure your standard buttons on your controller - **UP, DOWN, LEFT, RIGHT, LP, MP, HP, LK, MK, HK**.

Press each input as prompted, hold briefly, then release. Inputs are recorded on release.

Steps 11–13 are optional editor-only bindings:

* **BACKSPACE** — deletes the previous token while building combos
* **CLEAR** — wipes the current slot
* **SHIFT** — chord modifier for editor hotkeys

Skip these (button at the bottom of each step) if you don't want them — your setup still works.

Click **SAVE MAPPING** when you see "✓ CALIBRATION COMPLETE".

### Phase 2 — Modern Calibration

Immediately after you save Classic, you'll be prompted to calibrate Modern controls.

Modern has 8 action buttons instead of 6: **LIGHT, MEDIUM, HARD, SP, AUTO, THROW, DI, DP**.

If you only play Classic, click **SKIP MODERN** at the top-right of the instruction banner. Your setup is complete with just Classic.

\---

## 4\. Optional — Set Up Editor Hotkeys (SHIFT Config)

If you bound a SHIFT button during calibration, click **SHIFT CONFIG** on your controller profile to assign actions:

* **Insert `>`** — chunk separator (ex. 236lp > DR > 5HP)
* **Insert `xx`** — cancel marker
* **Backspace** — delete last token
* **Clear All** — wipe slot
* **Undo** — revert last edit
* Plus annotation tokens (CH, DR, DRC, MW, PC, F.Kill, SHM)

Click an action slot, press the button you want to bind to it. Click **SAVE**.

Skip this entirely if you're fine clicking the palette with a mouse.

\---

## 5\. Note Your First Combo

1. Go back to the home screen and click any character card.
2. Click an empty slot in the right-side slot list (e.g. Slot 1).
3. Build the combo two ways:

   * Click the palette buttons at the bottom (directions, motions, attacks)
   * Press inputs on your controller — they're recorded automatically
4. Click the slot title to rename it (e.g. "Punish Counter").
5. Check the **SHOW IN GAME** checkbox to make it appear on the in-game ticker.
6. Click **SAVE CHANGES**.

You can have up to **5 slots live** on the ticker per character, out of **30 total slots**.

\---

## 6\. Launch SF6 and Verify

1. Start Street Fighter 6 through Steam.
2. Look for the **Display** and **Combo Editor** tabs at the top of the screen — they're always visible during gameplay and clickable directly with your mouse. No menu key needed.
3. Enter Training mode. You should see:

   * Combo ticker bars at the bottom showing your slots
   * Health bar tick marks at 10% intervals and 25% for CA awarenes
   * Character profile text under each player's name (if you wrote any)

If nothing appears, click the **Display** tab and check the relevant master toggle is on.

> Only relevant for troubleshooting: pressing \*\*Insert\*\* opens REFramework's underlying menu (Script Runner, plugin loader, etc). You don't need it for normal use.

\---

## 7\. Edit On the Fly

Already in a training session and want to tweak a combo?

1. Click the **Combo Editor** tab at the top of the screen.
2. Pick a slot from the right-side list, edit the sequence, check/uncheck to enable/disable visibility as needed.
3. Changes save automatically for in game editor, changes should appear automatically in Web-App — no reload required.

For changes made in the web editor while SF6 is running, close the editor window and they should appear int he visible combo tickers

## Where to Go Next

* **User Manual** — Reference for editor features and in-game settings
* **VIDEO tab** on any character — link YouTube guides with timestamps to your slots, edit combos while watching videos
* **PROFILE tab** — write play notes that show up under the player name in-game
* Background Music - Go to settings an select your own music to play in the background and just enjoy my dank menus

