-- ============================================================
-- ── _SF6UI GLOBAL NAMESPACE (must precede all _SF6UI.* assignments) ──
-- Holds UI theme/helpers + bundled state tables. Lives on a GLOBAL to
-- avoid the Lua 200-file-scope-locals limit (globals don't count).
_SF6UI = _SF6UI or {}
_SF6UI.THEME = _SF6UI.THEME or {}
_SF6UI.UI    = _SF6UI.UI    or {}
_SF6UI.dbg   = _SF6UI.dbg   or {}
_SF6UI.stick = _SF6UI.stick or {}
_SF6UI.hud   = _SF6UI.hud   or {}
_SF6UI.cncol = _SF6UI.cncol or {}
-- Loaded d2d.Image handles for button glyphs (fist/foot). Populated in the
-- d2d init callback; nil if the PNG files aren't present (code falls back
-- to text labels). Lives on the global table so it doesn't count against
-- the 200-local-per-function limit.
_SF6UI.img   = _SF6UI.img   or {}
-- Menu slide-in animation progress (0=hidden, 1=shown), per menu.
_SF6UI.anim  = _SF6UI.anim  or { display = 0, profiles = 0, combo = 0 }
-- Persistent state for the border "reaching" electric arc. Sequence per
-- strike: build (pre-charge at A) → reach (A→B) → connect (explosion at B) →
-- linger (full bolt held ~1s) → collapse (origin A slides forward to B) →
-- crescendo (explosion peaks then dies) → pause (random, up to ~30s) → repeat
-- from B. `parts` holds explosion particles {x,y,vx,vy,born,life,r}. Survives
-- across frames since _SF6UI is global.
_SF6UI.arc   = _SF6UI.arc   or {
    phase = "pause", t0 = 0, from = 1, to = 2, dur = 0.3,
    pause = 2.0, seed = 901, parts = {}, bursts = {}, strikes = {}, last_hit = nil,
    btn_rects = {}, prev_input = {} }

-- ── Combo Notes window placement ─────────────────────────────
-- Lives on the global table (no chunk-local cost). ORDER drives the
-- Display-menu cycler; LABELS are what the user sees; anchor() resolves a
-- position key + screen/window dims into a top-left (mx,my) at FULL size.
-- A uniform MARGIN keeps the window off the very edge. The zoom entrance
-- anchors its growth to the CENTER of this full-size rect, so the window
-- flies in toward you from wherever it's placed.
_SF6UI.combo_pos = _SF6UI.combo_pos or {
    ORDER  = { "center","top","bottom","left","right",
               "topleft","topright","botleft","botright" },
    LABELS = {
        center="Center", top="Top", bottom="Bottom", left="Left", right="Right",
        topleft="Top-Left", topright="Top-Right",
        botleft="Bottom-Left", botright="Bottom-Right",
    },
    MARGIN = 24,
    -- Top-anchored placements (top / topleft / topright) sit lower than
    -- MARGIN so the window doesn't cover SF6's combo-trial / move-list
    -- tabs that live along the very top of the screen. Tuned as a fraction
    -- of screen height so it scales across resolutions.
    TOP_INSET_FRAC = 0.10,
}
-- Resolve a position key into the full-size window's top-left corner.
function _SF6UI.combo_pos.anchor(key, sw, sh, mw, mh)
    local m  = _SF6UI.combo_pos.MARGIN
    local ti = math.floor(sh * (_SF6UI.combo_pos.TOP_INSET_FRAC or 0.10))
    local cx = math.floor((sw - mw) / 2)   -- horizontally centered
    local cy = math.floor((sh - mh) / 2)   -- vertically centered
    local lx = m                            -- left edge
    local rx = sw - mw - m                  -- right edge
    local ty = ti                           -- top edge (inset to clear tabs)
    local by = sh - mh - m                  -- bottom edge
    local x, y = cx, cy
    if     key == "top"      then x, y = cx, ty
    elseif key == "bottom"   then x, y = cx, by
    elseif key == "left"     then x, y = lx, cy
    elseif key == "right"    then x, y = rx, cy
    elseif key == "topleft"  then x, y = lx, ty
    elseif key == "topright" then x, y = rx, ty
    elseif key == "botleft"  then x, y = lx, by
    elseif key == "botright" then x, y = rx, by
    -- "center" (and any unknown key) falls through to cx,cy
    end
    -- Clamp so a small screen can't push the window off-edge.
    if x < m then x = m end
    if y < m then y = m end
    if x + mw > sw - m then x = math.max(m, sw - mw - m) end
    if y + mh > sh - m then y = math.max(m, sh - mh - m) end
    return x, y
end


--  SF6 Overlay - Phase 2 (d2d version)
--  Requires:
--    - REFramework (dinput8.dll in SF6 game folder)
--    - reframework-d2d plugin (in reframework/plugins/)
--  Drop this file into:  reframework/autorun/SF6_Overlay.lua
--
--  Uses d2d for all rendering which gives real font scaling and
--  crisper text than REFramework's draw.text.
-- ============================================================

if not d2d then
    re.msg("SF6 Overlay: reframework-d2d plugin not loaded! "
        .. "Install it to reframework/plugins/ and restart.")
    return
end

local CONFIG_PATH = "reframework/data/sf6_overlay_config.json"

-- ── ESF → CHARACTER NAME MAPPING (verified roster) ───────────
local ESF_MAP = {
    ["esf001"] = "Ryu",      ["esf002"] = "Luke",
    ["esf003"] = "Kimberly", ["esf004"] = "Chun-Li",
    ["esf005"] = "Manon",    ["esf006"] = "Zangief",
    ["esf007"] = "JP",       ["esf008"] = "Dhalsim",
    ["esf009"] = "Cammy",    ["esf010"] = "Ken",
    ["esf011"] = "Dee Jay",  ["esf012"] = "Lily",
    ["esf013"] = "AKI",      ["esf014"] = "Rashid",
    ["esf015"] = "Blanka",   ["esf016"] = "Juri",
    ["esf017"] = "Marisa",   ["esf018"] = "Guile",
    ["esf019"] = "Ed",       ["esf020"] = "E.Honda",
    ["esf021"] = "Jamie",    ["esf022"] = "Akuma",
    ["esf025"] = "Sagat",    ["esf026"] = "M.Bison",
    ["esf027"] = "Terry",    ["esf028"] = "Mai",
    ["esf029"] = "Elena",    ["esf030"] = "C.Viper",
    ["esf031"] = "Alex",
}

local ROSTER = {
    "AKI","Akuma","Alex","Blanka","C.Viper","Cammy","Chun-Li","Dee Jay",
    "Dhalsim","E.Honda","Ed","Elena","Guile","Jamie","JP","Juri",
    "Ken","Kimberly","Lily","Luke","M.Bison","Mai","Manon","Marisa",
    "Rashid","Ryu","Sagat","Terry","Zangief",
}

-- Quick name→index lookup for auto-sync of profiles menu to detected character
local ROSTER_INDEX = {}
for i, n in ipairs(ROSTER) do ROSTER_INDEX[n] = i end

-- ── DYNAMIC ROSTER MERGE (reads sf6_roster.json from sf6_roster_export.lua) ──
-- Globals (not locals) so they don't consume main-chunk local slots and are
-- resolved by name at call time (no forward-reference nil trap). They close
-- over ESF_MAP/ROSTER/ROSTER_INDEX as upvalues, which are declared above.
_sf6_roster = { last_try = -1e9 }

function _sf6_merge_roster()
    local raw
    for _, p in ipairs({ "sf6_roster.json", "reframework/data/sf6_roster.json" }) do
        local f = io.open(p, "r")
        if f then raw = f:read("*a"); f:close(); break end
    end
    if not raw then return false end
    local ok, parsed = pcall(json.load_string, raw)
    if not (ok and type(parsed) == "table" and type(parsed.characters) == "table") then
        return false
    end
    for _, c in ipairs(parsed.characters) do
        if type(c) == "table" and c.esf and c.name then
            local esf, name = tostring(c.esf), tostring(c.name)
            ESF_MAP[esf] = name                  -- add or override
            if not ROSTER_INDEX[name] then        -- new char -> grow roster
                ROSTER[#ROSTER + 1] = name
                ROSTER_INDEX[name]  = #ROSTER
            end
        end
    end
    return true
end

-- Rate-limited re-read for an unmapped esf seen mid-session (e.g. overlay
-- loaded before the exporter's ~5s-deferred write). Bounded to one small
-- file read per cooldown while an unknown character is on screen.
function _sf6_relookup_esf(esf)
    if ESF_MAP[esf] then return end
    local now = os.clock()
    if (now - _sf6_roster.last_try) < 3.0 then return end  -- 3s cooldown
    _sf6_roster.last_try = now
    pcall(_sf6_merge_roster)
end

_sf6_merge_roster()   -- initial load-time merge

-- ── DEFAULT CONFIG ───────────────────────────────────────────
local cfg = {
    config_version      = 2,       -- bump when a one-time cfg migration is added
    accent_preset       = "violet", -- menu accent palette key (see THEME.ACCENTS)
    show_overlay        = true,
    show_button_bar     = true,
    show_ticks          = true,
    show_profiles_text  = true,
    show_ticker         = true,
    show_p1_profile     = true,
    show_p2_profile     = true,
    font_size           = 36,      -- profile + notes text (single shared size)
    notes_font_size     = 36,      -- kept in sync with font_size (one control)
    ticker_font_size    = 28,      -- combo ticker (largest — glanceable HUD)
    button_font_size    = 18,      -- button-bar labels
    menu_font_size      = 16,      -- settings menu (smallest — dense text)
    font_color          = { 1.0, 1.0, 1.0, 1.0 },
    ticker_text         = "Edit this message in Settings",
    offset_y            = 0,
    offset_x            = 0,
    ticker_scale        = 2.0,   -- combo ticker bar scale: 0.75 to 3.0
    -- Vertical anchor: bottom of ticker sits this fraction of screen
    -- height above the screen bottom. 0.11 = old default (just above
    -- SUPER bar). 0.30–0.35 = above the SF6 frame meter, in the
    -- gameplay safe zone where the bars don't compete with HUD.
    ticker_bottom_pct   = 0.32,
    -- Orientation:
    --   "horizontal" = full-width bars stacked at screen bottom (default)
    --   "vertical"   = trials-mode-style narrow column at screen side,
    --                  one chunk per row, top→bottom reading order.
    ticker_orientation  = "horizontal",
    -- For vertical mode: which side of the screen to anchor to.
    --   "left" / "right". Only used when orientation = "vertical".
    ticker_vertical_side = "left",
    numeric_notation    = true,  -- legacy bool; superseded by notation_mode
                                 -- below. Kept for back-compat migration.
    -- Input display mode (3-state). "numeric" = numpad (236/623/...),
    -- "lettered" = arrow/shorthand (QCF/DP/UF/...), "icon" = PNG glyphs
    -- (loaded from reframework/images/, named after the lettered form,
    -- e.g. UF.png, QCF.png). Falls back to lettered text when a PNG is
    -- missing. Migrated from numeric_notation in load_config.
    notation_mode       = "numeric",
    hud_skin            = "SF6",  -- health bar skin selection (UI only for now)
    -- Global control scheme for the Combo editor, applied to ALL characters
    -- (was per-character). "classic" → LP/MP/HP... + combonotes.json;
    -- "modern" → L/M/H/SP... + moderncombonotes.json. Set in Display options.
    combo_scheme        = "classic",
    -- Where the Combo Notes window opens on screen. One of the keys in
    -- COMBO_POS (see below): "center", "top", "bottom", "left", "right",
    -- "topleft", "topright", "botleft", "botright". The zoom-in entrance
    -- still grows from this anchor, so it flies in toward you wherever it sits.
    combo_notes_pos     = "center",
    profiles            = {},
}

-- ── NOTATION CONVERSION ─────────────────────────────────────
-- Converts numpad motion strings to shorthand or arrow words.
-- Applied at render time only — stored tokens always use numpad.
-- Whole-motion substitutions run first, then per-digit fallback.
local MOTION_NAMES = {
    ["2141236"] = "SPD",    -- 720
    ["41236"]   = "HCF",
    ["63214"]   = "HCB",
    -- 360F/360B/720: raw=true at render site, no entry needed here
    ["623"]     = "DP",
    ["421"]     = "RDP",
    ["236"]     = "QCF",
    ["214"]     = "QCB",
    ["[4]6"]    = "[B]F",   -- charge back→forward
    ["[2]8"]    = "[D]U",   -- charge down→up
    ["46"]      = "[B]F",
    ["28"]      = "[D]U",
    ["22"]      = "DD",
    ["66"]      = "FF",     -- dash forward
    ["44"]      = "BB",     -- dash backward
}
local NUM_TO_ARROW = {
    ["1"]="DB", ["2"]="D",  ["3"]="DF",
    ["4"]="B",  ["5"]="N",  ["6"]="F",
    ["7"]="UB", ["8"]="U",  ["9"]="UF",
}
local function notation(s)
    -- numeric mode → raw numpad string. Both "lettered" and "icon" modes
    -- use the lettered/arrow form for TEXT purposes (icon mode draws a PNG
    -- named after this lettered form, and falls back to this text when the
    -- PNG is missing — so the text path must produce the lettered name).
    if (cfg.notation_mode or "numeric") == "numeric" then return s end
    -- Standalone double-circle motions display literally in both notation
    -- modes — there's no clean arrow equivalent ("UBD0" for "720" or
    -- "DFF0 F" for "360F" reads as broken). These tokens are inserted
    -- raw at the menu render site (raw=true); this pass-through makes
    -- the ticker honor the same intent so arrow mode doesn't garble them.
    if s == "720" or s == "360F" or s == "360B" then return s end
    -- Split into motion prefix + button suffix (e.g. "236LP" → "236","LP")
    -- Button suffix is trailing uppercase letters only.
    local motion, btn = s:match("^(.-)([A-Z][A-Z]?)$")
    if not motion then motion = s; btn = "" end
    -- Whole-motion substitution
    local mapped = MOTION_NAMES[motion]
    if mapped then
        return mapped .. (btn ~= "" and " " .. btn or "")
    end
    -- Per-digit fallback for anything not in the table
    local result = motion:gsub("%d", function(d) return NUM_TO_ARROW[d] or d end)
    return result .. (btn ~= "" and " " .. btn or "")
end

-- Resolve a direction/motion token to its loaded PNG handle when icon
-- mode is active. Returns nil in non-icon modes, for tokens with a button
-- suffix (e.g. "236LP" — icons are pure inputs, drawn as text+button
-- elsewhere), or when the PNG for that name wasn't loaded. The icon is
-- keyed by the lettered name (UF, QCF, ...) which is what the PNG files
-- are titled. Standalone raw motions (720/360F/360B) key by their own
-- string. _SF6UI.img.glyph is the cache populated at d2d init.
local function notation_icon(s)
    if (cfg.notation_mode or "numeric") ~= "icon" then return nil end
    local glyphs = _SF6UI.img.glyph
    if not glyphs then return nil end
    -- Raw standalone motions use their literal name.
    if s == "720" or s == "360F" or s == "360B" then return glyphs[s] end
    -- Only pure inputs (no trailing button) get an icon.
    local motion, btn = s:match("^(.-)([A-Z][A-Z]?)$")
    if btn and btn ~= "" then return nil end
    local name = MOTION_NAMES[s]
    if not name then
        -- single direction digit → arrow name (e.g. "9" → "UF")
        name = NUM_TO_ARROW[s]
    end
    if not name then return nil end
    return glyphs[name]
end

local function default_profile(name)
    return {
        name=name, archetype="Unknown", range="Medium",
        notes="",
        -- Per-character control scheme. Selects which combo notes file
        -- the Combo Notes window reads/writes:
        --   "classic" → <Char>/combonotes.json       (Classic LP/MP/HP/...)
        --   "modern"  → <Char>/moderncombonotes.json (Modern L/M/H/SP/...)
        -- Mirrors the field stored in notes.json by the web editor.
        -- Defaults to "classic" for back-compat with existing profiles.
        combo_scheme = "classic",
    }
end

-- Helper: read the GLOBAL combo scheme (now applied to all characters,
-- set in Display options). char_name is kept for call-site compatibility
-- but ignored. Always returns "classic" | "modern".
local function get_combo_scheme(char_name)
    return (cfg.combo_scheme == "modern") and "modern" or "classic"
end

-- Helper: write the GLOBAL combo scheme. char_name ignored (kept for
-- call-site compatibility). Idempotent.
local function set_combo_scheme(char_name, scheme)
    if scheme ~= "modern" then scheme = "classic" end
    cfg.combo_scheme = scheme
end

-- ── CLASSIC → MODERN BUTTON LABEL TRANSLATION ────────────────────
-- When a character's combo_scheme is "modern", in-game button
-- presses (which SF6's InputManager always reports as Classic labels
-- LP/MP/HP/LK/MK/HK) get rewritten to the Modern equivalent before
-- being inserted into the slot. User-defined mapping:
--
--   LP → L       MP → SP      HP → DP
--   LK → M       MK → H       HK → Auto
--
-- The assignment is NOT the strength-aligned default (LP→L, MP→M,
-- HP→H). It's based on which physical face button the user has
-- chosen to use for each Modern action. OD pairs (PP/KK) have no
-- Modern equivalent and pass through as-is. Throw and DI are
-- typically bound to shoulder buttons (LT/LB) which aren't
-- currently recorded — pending future shoulder button support.
--
-- IMPORTANT: declared EARLY (right after the combo_scheme helpers)
-- because the recording site at re.on_frame references it through
-- the input handler. Lua locals are NOT hoisted — referencing this
-- table before its `local` declaration line is reached resolves to
-- nil, which would cause an index-on-nil crash on every Modern
-- button press and silently halt the entire input handler for that
-- frame (symptoms: directions and attacks both stop working in the
-- Combo Notes window).
local CLASSIC_TO_MODERN_BTN = {
    LP = "L",
    LK = "M",
    MK = "H",
    MP = "SP",
    HP = "DP",
    HK = "Auto",
}

-- ── PERSISTENCE ──────────────────────────────────────────────
local function load_config()
    local f = io.open(CONFIG_PATH, "r")
    if f then
        local raw = f:read("*a"); f:close()
        local ok, parsed = pcall(json.load_string, raw)
        if ok and parsed then
            for k, v in pairs(parsed) do cfg[k] = v end
            -- Migrate legacy 2-state numeric_notation → 3-state
            -- notation_mode, but only if the saved config predates
            -- notation_mode (so we never stomp a user's explicit choice).
            if parsed.notation_mode == nil and parsed.numeric_notation ~= nil then
                cfg.notation_mode = parsed.numeric_notation and "numeric" or "lettered"
            end
            -- Profile and notes text now share one size control. If a saved
            -- config has them mismatched (from when they were separate), fold
            -- notes onto the profile size so the single cycler is consistent.
            if parsed.notes_font_size ~= parsed.font_size and parsed.font_size ~= nil then
                cfg.notes_font_size = cfg.font_size
            end
            -- One-time type-scale migration: pull font sizes onto the
            -- 16/18/24/28 ratio ladder. Gated by config_version so it runs
            -- exactly once and never stomps sizes the user sets afterward.
            if (cfg.config_version or 1) < 2 then
                cfg.menu_font_size   = 16
                cfg.button_font_size = 18
                cfg.notes_font_size  = 36
                cfg.font_size        = 36
                cfg.ticker_font_size = 28
                cfg.config_version   = 2
            end
        end
    end
    for _, name in ipairs(ROSTER) do
        local key = name:lower()
        if not cfg.profiles[key] then
            cfg.profiles[key] = default_profile(name)
        end
    end
end

local function save_config()
    local f = io.open(CONFIG_PATH, "w")
    if f then f:write(json.dump_string(cfg)); f:close() end
end

-- ── HOTKEYS PERSISTENCE ─────────────────────────────────────────
-- The SHIFT modifier feature (hold a button + press another to insert
-- > / xx / backspace / clear / undo) was removed. Attack buttons now
-- always record directly. To insert >, xx, or do edit ops in-game,
-- use the on-screen palette buttons in the Combo Notes window.
-- The web editor's sf6_hotkeys.json file is no longer read.

-- ── COLOR HELPERS (d2d uses 0xAARRGGBB) ──────────────────────
local function argb(r, g, b, a)
    local A = math.floor((a or 1) * 255)
    local R = math.floor(r * 255)
    local G = math.floor(g * 255)
    local B = math.floor(b * 255)
    return A*0x1000000 + R*0x10000 + G*0x100 + B
end

-- Draw text with a dark stroke/outline for readability.
-- Renders the text 8 times offset by `th` pixels in each cardinal
-- and diagonal direction in the stroke color, then once on top
-- in the fill color.
local C_STROKE = 0xFF000000  -- black outline
local function d2d_stroked_text(fnt, str, x, y, color, thickness)
    local th = thickness or 2
    for dx = -th, th, th do
        for dy = -th, th, th do
            if dx ~= 0 or dy ~= 0 then
                d2d.text(fnt, str, x + dx, y + dy, C_STROKE)
            end
        end
    end
    d2d.text(fnt, str, x, y, color)
end

-- Color constants (initialized in d2d init callback)
local C_TICK, C_TICK_BLUE, C_NAME_P1, C_NAME_P2, C_TEXT, C_GOOD, C_BAD, C_DIM
local C_TICKER_TEXT, C_TICKER_BG
local C_BTN_BG, C_BTN_HOVER, C_BTN_ACTIVE, C_BTN_BORDER, C_BTN_TEXT
local C_MENU_BG, C_MENU_BORDER, C_MENU_TITLE_BG, C_MENU_TITLE
local C_ROW_HOVER, C_LABEL, C_VALUE, C_CHECKBOX_BG, C_CHECKBOX_ON

local function init_colors()
    C_TICK         = argb(1.0, 1.0, 0.0, 1.0)
    -- Cyan-leaning blue for retro skins where the bar fill is yellow.
    -- Saturated enough to read against both yellow fill AND darker
    -- segment backplates without bleeding into the SF6 yellow ticks.
    C_TICK_BLUE    = argb(1.0, 0.25, 0.75, 1.0)
    C_NAME_P1      = argb(1.0, 0.8, 0.2, 0.95)
    C_NAME_P2      = argb(0.4, 0.8, 1.0, 0.95)
    C_TEXT         = argb(cfg.font_color[1],cfg.font_color[2],
                          cfg.font_color[3],cfg.font_color[4])
    C_GOOD         = argb(0.3, 1.0, 0.4, 1.0)
    C_BAD          = argb(1.0, 0.4, 0.4, 1.0)
    C_DIM          = argb(0.75, 0.75, 0.75, 0.95)
    C_TICKER_TEXT  = argb(1.0, 1.0, 0.0, 1.0)
    C_TICKER_BG    = argb(0.0, 0.0, 0.0, 0.45)
    C_BTN_BG       = argb(0.12, 0.12, 0.12, 0.88)
    C_BTN_HOVER    = argb(0.25, 0.25, 0.35, 0.95)
    C_BTN_ACTIVE   = argb(0.40, 0.40, 0.55, 0.95)
    C_BTN_BORDER   = argb(0.70, 0.70, 0.85, 0.85)
    C_BTN_TEXT     = argb(1.0, 1.0, 1.0, 1.0)
    C_MENU_BG      = argb(0.08, 0.08, 0.12, 0.95)
    C_MENU_BORDER  = argb(0.70, 0.70, 0.85, 0.90)
    C_MENU_TITLE_BG= argb(0.20, 0.20, 0.30, 1.0)
    C_MENU_TITLE   = argb(1.0, 1.0, 1.0, 1.0)
    C_ROW_HOVER    = argb(0.22, 0.22, 0.28, 1.0)
    C_LABEL        = argb(0.9, 0.9, 0.9, 1.0)
    C_VALUE        = argb(1.0, 1.0, 0.5, 1.0)
    C_CHECKBOX_BG  = argb(0.05, 0.05, 0.05, 1.0)
    C_CHECKBOX_ON  = argb(0.3, 1.0, 0.4, 1.0)
    _SF6UI.THEME.init()   -- build theme palette (kept in sync with C_* colors)
end

-- ── GAME DATA (character detection) ──────────────────────────
local found_core = nil
local players = {
    [1] = { esf="?", name="?", slot=1 },
    [2] = { esf="?", name="?", slot=2 },
}

-- Diagnostic state populated by update_players_inner; rendered in REFramework
-- live-detection panel so we can see WHY P1 is "?" without console digging.
local detect_diag = {
    fighters_obj   = false,  -- did _Fighters resolve?
    fighter_count  = 0,      -- _Fighters.Count
    p1_fobj        = false,  -- did slot 0 give a fighter object?
    p1_name_raw    = "?",    -- raw Name string before esf### regex
    cn_char_name   = "?",    -- what Combo Notes window is showing
    cn_slot1_title = "?",    -- title of slot 1 for that char
    cn_slot1_toks  = 0,      -- token count for slot 1
}

-- Forward-declared because update_players_inner (defined further below) needs
-- to write to them. Without `local` here, writes from update_players_inner
-- create globals that get shadowed by `local` declarations later in the file —
-- the classic Lua declaration-order trap.
local edit_char_idx         = 1
local profile_user_override = false   -- player manually picked a char; suppress auto-sync
local last_p1_idx           = nil     -- tracks game P1's roster idx; lets us detect *transitions*
                                      -- rather than mismatch-with-edit_char_idx (which fires
                                      -- every frame whenever the user has overridden).
local combo_edit_slot       = 1       -- which combo slot is currently being edited
local combo_edit_cursor     = 0       -- insert position within current slot's tokens
                                      -- (0 = before token 1, N = after token N).
                                      -- Reset to end of new slot's tokens whenever
                                      -- the slot or character changes — see *_reset_cursor*.
-- Forward-decl: the controller-input recording block at ~line 1187 reads
-- `show_combo_notes_win` to gate input capture. Without this forward
-- declaration the variable is nil at that line (it's not declared until
-- ~line 1628), which silently disabled all in-game controller recording.
-- The real assignment at 1628 is now `show_combo_notes_win = false`
-- (no `local`) and reuses this slot.
local show_combo_notes_win  = false

-- Forward-decl block: same Lua declaration-order trap as above. The
-- recording logic inside update_current_moves (~line 1187) references
-- these helpers, but they're declared AFTER update_current_moves in
-- the file. Lua captures upvalues at function-definition time, so any
-- local declared later than the function falls back to the global
-- scope (which is nil) — silently disabling the recording. The real
-- declarations below drop the `local` keyword to reuse these slots.
local numcmd_to_tokens
local get_combo_slot
local combo_notes_dirty = {}
-- Combo-edit undo stack helpers. Per-(character, slot) snapshots of
-- the token array, pushed before each modifying action. `pop_combo_undo`
-- returns the most-recent snapshot or nil if the stack is empty.
local push_combo_undo
local pop_combo_undo
local combo_undo_stacks = {}  -- shape: combo_undo_stacks[char][slot] = list of token-array snapshots

-- Forward-decl: the SHIFT hotkey block inside update_current_moves
-- (~line 1505) reads from these tables. They're declared further down
-- in the file (~lines 2095 and 2372), so without forward declaration
-- the upvalues captured at update_current_moves' definition time
-- would resolve to nil, silently aborting the entire on_frame handler
-- (it's pcall-wrapped) and breaking all controller-driven recording.
-- Same trap as combo_notes_dirty above. Real definitions below drop
-- the `local` keyword to reuse these slots.
local combo_slots
local cn_refresh

local function safe_get(obj, field)
    if not obj then return nil end
    local ok, v = pcall(function() return obj:get_field(field) end)
    return ok and v or nil
end
local function safe_call(obj, method, ...)
    if not obj then return nil end
    local a = {...}
    local ok, v = pcall(function() return obj:call(method, table.unpack(a)) end)
    return ok and v or nil
end

-- ── FRAME DATA (loaded from per-character JSON files) ────────
-- Files written by SF6_FrameData_Updater into:
--   reframework/data/sf6_framedata/<CharacterName>/framedata.json
local FRAMEDATA_BASE = "sf6_framedata/"

-- REFramework resolves io.open paths relative to the game exe folder.
-- Full path would be: <SF6>/reframework/data/sf6_framedata/<CharName>/framedata.json
-- If that fails, try the data subfolder variation.
local function open_framedata_file(char_name)
    local paths = {
        FRAMEDATA_BASE .. char_name .. "/framedata.json",
    }
    local logf = io.open("sf6_fd_debug.txt", "w")
    if logf then
        logf:write("char_name: " .. tostring(char_name) .. "\n")
        for _, p in ipairs(paths) do
            local f = io.open(p, "r")
            logf:write("try: " .. p .. " -> " .. (f and "OK" or "FAIL") .. "\n")
            if f then f:close(); logf:close(); return io.open(p, "r") end
        end
        logf:close()
    end
    return nil
end
local fd_cache = {}  -- char name → { moves, by_input, by_name }

local function load_framedata(char_name)
    if fd_cache[char_name] then return fd_cache[char_name] end
    if char_name == "?" then return nil end
    local f = open_framedata_file(char_name)
    if not f then return nil end
    local raw = f:read("*a"); f:close()
    -- Strip UTF-8 BOM if present (PS1 writes BOM by default)
    if raw:sub(1,3) == "\xEF\xBB\xBF" then raw = raw:sub(4) end
    local ok, parsed = pcall(json.load_string, raw)
    if not ok or not parsed then return nil end
    local moves = parsed.moves or {}
    local entry = { moves=moves, by_input={}, by_name={} }
    for _, move in ipairs(moves) do
        local inp = tostring(move.input or ""):lower():gsub("%s+","")
        local nam = tostring(move.name  or ""):lower()
        if inp ~= "" and inp ~= "-" then entry.by_input[inp] = move end
        if nam ~= "" and nam ~= "-" then entry.by_name[nam]  = move end
    end
    fd_cache[char_name] = entry
    return entry
end

-- ============================================================
-- CHARGE MOVE TIMINGS
-- ============================================================
-- Source: SF6_All_Charge_Moves.md (cross-validated JSON + Supercombo wiki).
-- For each charge character, we store:
--   bf  = back-charge (46 motion) timing per strength
--   du  = down-up charge (28 motion) timing per strength
--   Each sub-entry: { charge = frames needed, buffer = frames held after release }
-- Strength keys: LP/MP/HP/PP for punches, LK/MK/HK/KK for kicks.
-- Missing strength → falls back to the "default" key.
-- ============================================================
local CHARGE_TIMINGS = {
    ["Blanka"] = {
        bf = { default = { charge = 40, buffer = 10 } },
        du = { default = { charge = 40, buffer = 12 } },
    },
    ["Chun-Li"] = {
        -- Kikoken: LP/MP/HP = 50F, OD (PP) = 45F (unique asymmetry)
        bf = {
            LP = { charge = 50, buffer = 10 },
            MP = { charge = 50, buffer = 10 },
            HP = { charge = 50, buffer = 10 },
            PP = { charge = 45, buffer = 10 },
            default = { charge = 50, buffer = 10 },
        },
        du = { default = { charge = 30, buffer = 12 } },
    },
    ["Dee Jay"] = {
        bf = { default = { charge = 45, buffer = 10 } },
        du = { default = { charge = 40, buffer = 12 } },
    },
    ["E.Honda"] = {
        bf = { default = { charge = 40, buffer = 10 } },
        du = { default = { charge = 40, buffer = 12 } },
    },
    ["Guile"] = {
        -- Sonic Boom: all 45F, OD has longer 13F buffer
        bf = {
            LP = { charge = 45, buffer = 10 },
            MP = { charge = 45, buffer = 10 },
            HP = { charge = 45, buffer = 10 },
            PP = { charge = 45, buffer = 13 },
            default = { charge = 45, buffer = 10 },
        },
        -- Somersault Kick: all 45F, OD has longer 15F buffer
        du = {
            LK = { charge = 45, buffer = 12 },
            MK = { charge = 45, buffer = 12 },
            HK = { charge = 45, buffer = 12 },
            KK = { charge = 45, buffer = 15 },
            default = { charge = 45, buffer = 12 },
        },
    },
    ["M.Bison"] = {
        -- Psycho Crusher: 45F charge with tight 8F buffer (direction-locked)
        bf = { default = { charge = 45, buffer = 8 } },
        -- Shadow Rise: 40F/10F (generic 28K, no strength variants)
        du = { default = { charge = 40, buffer = 10 } },
    },
}

-- Lookup charge timing for current char + numcmd.
-- numcmd example: "46LP", "28KK". Returns {charge,buffer} or nil if not a charge char.
local function get_charge_timing(char_name, numcmd)
    local ct = CHARGE_TIMINGS[char_name]
    if not ct then return nil end
    local motion = numcmd:sub(1,2)
    local btn = numcmd:sub(3)  -- "LP", "KK", etc.
    local family = (motion == "46") and ct.bf or (motion == "28") and ct.du or nil
    if not family then return nil end
    return family[btn] or family.default
end

-- Is this character a charge character? (used for overlay diagnostics)
local function is_charge_character(char_name)
    return CHARGE_TIMINGS[char_name] ~= nil
end

-- (Runtime charge tracker is defined further below, after btn_flags/BTN/p1_facing_left
-- are declared. Forward-declare here so earlier code can call them if needed.)
local update_charge_state  -- forward decl
local has_valid_charge     -- forward decl
local is_perfect_timing    -- forward decl
local charge_state = {
    back_held = 0, back_buffer = 0, back_peak = 0,
    down_held = 0, down_buffer = 0, down_peak = 0,
}

-- ============================================================
-- STANCE STATE TRACKING
-- ============================================================
-- Some characters have stance moves: an entry input puts them into a
-- state where button presses generate stance-followup specials instead
-- of normal attacks. We track this purely from input state since we
-- can't (yet) read stance flags from game memory.
--
-- Currently implemented:
--   Alex - Prowler Stance (entry: 2PP / d+PP)
--
-- Forward-declared; assigned after btn_flags/BTN are in scope.
-- ============================================================
local stance_state = {
    active = nil,         -- nil if no stance, otherwise stance ID string ("prowler")
    char = nil,           -- which character is in stance ("Alex", etc)
    frames = 0,           -- frames since stance entry
    sub_state = nil,      -- for sub-states (e.g. "sweep1" after first HK in Sweep Combo)
}
local update_stance_state         -- forward decl
local resolve_stance_followup     -- forward decl
local is_in_stance                -- forward decl

-- ── INPUT-BASED MOVE DETECTION ───────────────────────────────
-- Reads app.InputManager._State._GamePads[0]._Buttons[i].Flags
-- Confirmed button mapping from probe:
--   LP=btn6  MP=btn4  HP=btn10  LK=btn5  MK=btn7  HK=btn11
--   Up=btn0  Down=btn1  Left=btn2  Right=btn3

local MOVE_DISPLAY_FRAMES = 180   -- 3 s at 60 fps
local current_move = { p1=nil, p2=nil, p1_frames=0, p2_frames=0,
                       p1_perfect=false, p2_perfect=false }

-- Button index constants (confirmed via probe)
local BTN = { LP=6, MP=4, HP=10, LK=5, MK=7, HK=11,
              UP=0, DOWN=1, LEFT=2, RIGHT=3 }

-- SF6 keyboard defaults → fight button mapping. The game itself
-- exposes a configurable keyboard layout in its options menu, but
-- the SDK exposure of that mapping is opaque (_DisplayKeyToKeyboardKey
-- on _Keyboard is a managed dictionary — extractable but heavy).
-- We instead use the conventional defaults that most people leave in
-- place and read the keys directly via reframework:is_key_down (raw
-- Win32 GetAsyncKeyState, gamepad-free — see notes on the keyboard
-- navigation hotkeys for why imgui.is_key_* doesn't work).
--
-- VK codes are Windows virtual-key constants. Letters use ASCII
-- uppercase: 'A'=0x41, 'D'=0x44, 'I'=0x49, 'J'=0x4A, 'K'=0x4B,
-- 'L'=0x4C, 'O'=0x4F, 'S'=0x53, 'U'=0x55, 'W'=0x57.
-- Multiple VK codes can map to the same fight button to give users
-- redundant access (arrow keys + WASD both drive directions).
local KB_FIGHT_KEYS = {
    -- Directions
    [0x57] = BTN.UP,    -- W
    [0x53] = BTN.DOWN,  -- S
    [0x41] = BTN.LEFT,  -- A
    [0x44] = BTN.RIGHT, -- D
    [0x26] = BTN.UP,    -- Arrow Up (alternate)
    [0x28] = BTN.DOWN,  -- Arrow Down (alternate)
    -- NOTE: Arrow Left/Right are intentionally NOT mapped here —
    -- they're reserved for the cursor-navigation shortcut in the
    -- Combo Notes editor. If the user needs keyboard fight-direction
    -- back/forward they use A/D (or any other key bound to that
    -- direction in SF6's own controls menu — see future config).
    -- Punches: J/K/L
    [0x4A] = BTN.LP,    -- J
    [0x4B] = BTN.MP,    -- K
    [0x4C] = BTN.HP,    -- L
    -- Kicks: U/I/O
    [0x55] = BTN.LK,    -- U
    [0x49] = BTN.MK,    -- I
    [0x4F] = BTN.HK,    -- O
}
-- Inverted map: BTN index → list of VK codes that fire it. Built
-- once at script load so btn_flags doesn't have to walk the whole
-- KB_FIGHT_KEYS table on every call.
local KB_VKS_FOR_BTN = {}
for vk, btn in pairs(KB_FIGHT_KEYS) do
    KB_VKS_FOR_BTN[btn] = KB_VKS_FOR_BTN[btn] or {}
    table.insert(KB_VKS_FOR_BTN[btn], vk)
end

-- InputManager pad state
-- We track up to 4 input device slots from app.InputManager._State._GamePads.
-- SF6 routes physical input from multiple sources (controller + keyboard)
-- into separate slots — keyboard input does NOT automatically merge into
-- _GamePads[0] just because there's a controller plugged in. Reading
-- only slot 0 misses keyboard input entirely. We OR-merge button flags
-- across all populated slots so any device's press registers.
local im_pads = {}    -- array of all populated slots {pad0, pad1, ...}
local im_found = false
-- Walk all populated _GamePads slots so input from any device
-- (controller, keyboard) feeds into btn_flags() / btn_just_pressed().

local function find_input_manager()
    local im = sdk.get_managed_singleton("app.InputManager")
    if not im then return end
    local st = safe_get(im, "_State")
    if not st then return end
    local pa = safe_get(st, "_GamePads")
    if not pa then return end
    -- Walk slots 0..3 — RE Engine's _GamePads is typically a fixed
    -- 4-element array (one per physical device, e.g. pad0=controller,
    -- pad1=keyboard). Empty slots return nil; we collect the populated
    -- ones into im_pads for later merged reads.
    im_pads = {}
    for i = 0, 3 do
        local ok, p = pcall(function() return pa[i] end)
        if ok and p then
            im_pads[#im_pads+1] = p
        end
    end
    if #im_pads > 0 then
        im_found = true
    end
end

-- Read current Flags for a button index (non-zero = pressed).
-- Walks all populated _GamePads slots and returns the first non-zero
-- flag value found, so input from any device (controller, keyboard,
-- etc.) registers. Each physical input source typically owns a
-- separate slot in the array — pad0 might be the controller and pad1
-- the keyboard, or vice versa depending on which device was bound
-- first at the game's input layer.
-- We return the flag value rather than a boolean so any caller that
-- inspects specific bit patterns still works; in practice all callers
-- in this file just test `~= 0`. NOTE: we deliberately avoid the
-- bitwise OR operator here — REFramework runs LuaJIT (5.1-compatible)
-- which doesn't have the `|` operator from Lua 5.3+. The `bit` lib
-- IS available but unnecessary: returning the first non-zero flag is
-- semantically equivalent for the existing `~= 0` callers.
local function btn_flags(idx)
    -- Gamepad path: scan all populated _GamePads slots.
    if #im_pads > 0 then
        for _, pad in ipairs(im_pads) do
            local btns = safe_get(pad, "_Buttons")
            if btns then
                local ok, btn = pcall(function() return btns[idx] end)
                if ok and btn then
                    local f = tonumber(safe_get(btn, "Flags") or 0) or 0
                    if f ~= 0 then
                        return f
                    end
                end
            end
        end
    end
    -- Keyboard path: check whether any VK bound to this BTN is held.
    -- Reads raw Win32 state via reframework:is_key_down so a connected
    -- controller can't pollute the keyboard reads (REF's imgui io
    -- maps gamepad d-pad onto arrow keys, but reframework:is_key_down
    -- bypasses imgui entirely — see kb_impl notes near the editor
    -- navigation shortcuts for the full explanation).
    -- Returns a synthetic non-zero flag (1) on press; consumers only
    -- check `~= 0` so the exact value doesn't matter.
    local vks = KB_VKS_FOR_BTN[idx]
    if vks then
        for _, vk in ipairs(vks) do
            local ok, v = pcall(function() return reframework:is_key_down(vk) end)
            if not ok then
                ok, v = pcall(function() return reframework.is_key_down(vk) end)
            end
            if ok and v == true then
                return 1
            end
        end
    end
    return 0
end



-- Deadzone threshold for the left analog stick. Values past this
-- magnitude on an axis count as a directional press; below it counts
-- as neutral. 0.5 is a deliberately conservative "definitely pushed"
-- threshold — high enough to avoid accidental diagonals from a slight
-- thumb drift, low enough that intentional inputs always register.
-- Diagonal threshold is independent and slightly lower (0.4) so QCF
-- motions on a stick still hit the 3 (down-forward) detent reliably
-- without requiring the player to push it fully into the corner.
_SF6UI.stick.STICK_DEAD     = 0.5
_SF6UI.stick.STICK_DEAD_DIAG = 0.4

-- Y-axis sign: in SF6 / RE Engine the convention has been observed to
-- be positive Y = up (matches OpenGL/3D math convention). If the game
-- reads inverted on your build, flip this to -1 and the directional
-- math below auto-adjusts. Most users won't need to touch this.
_SF6UI.stick.STICK_Y_SIGN = 1

-- Read the left analog stick and return four booleans (up/down/left/
-- right) plus a fifth flag indicating whether any cardinal is strong
-- enough to register as a non-diagonal press. Centralised here so
-- both read_direction() and update_charge_state() can use the same
-- thresholding without duplicating it.
--
-- Returns: up_diag, down_diag, left_diag, right_diag,
--          strong_up, strong_down, strong_left, strong_right
-- "_diag" variants use the lower 0.4 threshold (good for hitting
-- corner detents during QCF/QCB motions on a stick). "strong_"
-- variants use the higher 0.5 threshold so a slight thumb drift
-- doesn't register as a cardinal press.
local function read_stick_cardinals()
    if #im_pads == 0 then return false,false,false,false, false,false,false,false end
    local axis = safe_get(im_pads[1], "_AxisL")
    if not axis then return false,false,false,false, false,false,false,false end
    -- ValueType via.vec2 — safe_get returns a Lua-native struct with
    -- .x and .y fields. pcall the access since older REFramework
    -- builds occasionally return userdata that needs different access
    -- patterns; on failure stick reads as neutral.
    local ok, x, y = pcall(function()
        return axis.x or 0, axis.y or 0
    end)
    if not ok then return false,false,false,false, false,false,false,false end
    local y_eff = (y or 0) * _SF6UI.stick.STICK_Y_SIGN
    local x_eff = x or 0
    return
        y_eff >  _SF6UI.stick.STICK_DEAD_DIAG, y_eff < -_SF6UI.stick.STICK_DEAD_DIAG,
        x_eff < -_SF6UI.stick.STICK_DEAD_DIAG, x_eff >  _SF6UI.stick.STICK_DEAD_DIAG,
        y_eff >  _SF6UI.stick.STICK_DEAD,      y_eff < -_SF6UI.stick.STICK_DEAD,
        x_eff < -_SF6UI.stick.STICK_DEAD,      x_eff >  _SF6UI.stick.STICK_DEAD
end

-- Read the left analog stick as a numpad direction (1-9, or nil if
-- neutral). Diagonal detection uses the lower threshold so partial
-- corner pushes still register; cardinal detection uses the higher
-- threshold so thumb drift doesn't.
local function read_stick_direction()
    local u, d, l, r, su, sd, sl, sr = read_stick_cardinals()
    if    u and l   then return 7
    elseif u and r  then return 9
    elseif d and l  then return 1
    elseif d and r  then return 3
    elseif su       then return 8
    elseif sd       then return 2
    elseif sl       then return 4
    elseif sr       then return 6
    else                 return nil
    end
end

-- Directional state: track stick/dpad. Returns numpad notation for
-- current held direction (5=neutral). Merges D-pad digital input with
-- left analog stick: if either source resolves to a direction, use it.
-- D-pad wins on conflict — players who actively use the D-pad in a
-- fight aren't going to be brushing the stick at the same time, and
-- if they are, the deliberate D-pad press should take precedence.
local function read_direction()
    local up    = btn_flags(BTN.UP)    ~= 0
    local down  = btn_flags(BTN.DOWN)  ~= 0
    local left  = btn_flags(BTN.LEFT)  ~= 0
    local right = btn_flags(BTN.RIGHT) ~= 0
    local dpad_dir = nil
    if    up   and left  then dpad_dir = 7
    elseif up   and right then dpad_dir = 9
    elseif down and left  then dpad_dir = 1
    elseif down and right then dpad_dir = 3
    elseif up             then dpad_dir = 8
    elseif down           then dpad_dir = 2
    elseif left           then dpad_dir = 4
    elseif right          then dpad_dir = 6
    end
    if dpad_dir then return dpad_dir end
    -- D-pad neutral → fall back to analog stick. Returns nil if both
    -- are neutral, which becomes 5 in numpad notation.
    return read_stick_direction() or 5
end

-- Motion input buffer (stores direction history for special moves)
local dir_buffer  = {}
local DIR_BUFFER_WINDOW = 28  -- motion must complete within 28 frames (~470ms)

-- Airborne state tracking
local is_airborne = false
local air_frames_remaining = 0
local AIR_DURATION = 45  -- ~750ms, standard SF6 jump arc length
local AIR_DURATION_DHALSIM = 73  -- Dhalsim's float jump has a longer arc (~1.2s)
local LAND_GRACE = 8  -- frames stick can be off-up before declaring landed (~133ms)
local frames_since_up = 0

-- Side tracking: true when P1 is on the right side (facing left)
local p1_facing_left = false
_SF6UI.dbg.dbg_p1x, _SF6UI.dbg.dbg_p2x = nil, nil
_SF6UI.dbg.dbg_p1y = nil
_SF6UI.dbg.dbg_p1z = nil
_SF6UI.dbg.dbg_fields = {}
local GROUND_Y_THRESHOLD = 0.1  -- Y above this = airborne; tuned after you report values

-- Previous button states for edge detection
local prev_btn = {}

local function btn_just_pressed(idx)
    local cur = btn_flags(idx) ~= 0
    local prev = prev_btn[idx] or false
    return cur and not prev
end

-- ============================================================
-- CHARGE HOLD TRACKER (runtime)
-- ============================================================
-- Forward-declared near top of file (as local vars). Assign bodies here,
-- AFTER btn_flags/BTN/p1_facing_left are in scope.
--
-- Counts how many consecutive frames back (4) or down (2) has been held.
-- After release, a "buffer timer" counts down from BUFFER_MAX so the
-- move is still valid if forward/up + attack is pressed within window.
--   charge_state.back_held    = consecutive frames currently holding back
--   charge_state.back_buffer  = BUFFER_MAX at release, decrements each
--                               frame while not holding. A move is valid
--                               while (BUFFER_MAX - buf) <= timing.buffer
--   charge_state.back_peak    = peak held value at release time
-- BUFFER_MAX is set generously (20) so every char's buffer fits; the
-- per-move validity check inside has_valid_charge enforces the real window.
-- ============================================================
local BUFFER_MAX = 20
update_charge_state = function()
    -- Which physical direction means "back" depends on facing.
    -- IMPORTANT: do NOT use the `(cond and a) or b` ternary pattern here.
    -- It produces the wrong result when both operands can be true/false
    -- in arbitrary combinations. Use explicit if/else.
    --
    -- Merge D-pad with analog stick so charge characters work on stick
    -- too: hold left on either the D-pad LEFT button OR the stick past
    -- the dead-zone and the back-charge counter ticks. Uses the diag-
    -- threshold variants so a relaxed-but-deliberate hold still counts.
    local _u, sd_d, sd_l, sd_r = read_stick_cardinals()
    local left  = (btn_flags(BTN.LEFT)  ~= 0) or sd_l
    local right = (btn_flags(BTN.RIGHT) ~= 0) or sd_r
    local down  = (btn_flags(BTN.DOWN)  ~= 0) or sd_d

    local holding_back
    if p1_facing_left then
        holding_back = right   -- P1 on right side: back is physical right
    else
        holding_back = left    -- P1 on left side: back is physical left
    end
    local holding_down = down

    -- Back-charge tracking
    if holding_back then
        charge_state.back_held = charge_state.back_held + 1
        charge_state.back_buffer = 0
    else
        if charge_state.back_held > 0 then
            charge_state.back_peak = charge_state.back_held
            charge_state.back_buffer = BUFFER_MAX
        elseif charge_state.back_buffer > 0 then
            charge_state.back_buffer = charge_state.back_buffer - 1
            if charge_state.back_buffer == 0 then
                charge_state.back_peak = 0
            end
        end
        charge_state.back_held = 0
    end

    -- Down-charge tracking
    if holding_down then
        charge_state.down_held = charge_state.down_held + 1
        charge_state.down_buffer = 0
    else
        if charge_state.down_held > 0 then
            charge_state.down_peak = charge_state.down_held
            charge_state.down_buffer = BUFFER_MAX
        elseif charge_state.down_buffer > 0 then
            charge_state.down_buffer = charge_state.down_buffer - 1
            if charge_state.down_buffer == 0 then
                charge_state.down_peak = 0
            end
        end
        charge_state.down_held = 0
    end
end

-- Returns true if the player has a valid charge for numcmd (e.g. "46LP").
-- Returns true unconditionally for non-charge chars (lookup returns nil).
--
-- Buffer semantics: on release, back_buffer is set to BUFFER_MAX (20).
-- Each subsequent non-holding frame decrements it. So:
--   frames_since_release = BUFFER_MAX - buf
-- The move is valid while frames_since_release <= timing.buffer, i.e.
--   buf >= BUFFER_MAX - timing.buffer
has_valid_charge = function(char_name, numcmd)
    local timing = get_charge_timing(char_name, numcmd)
    if not timing then return true, nil end
    local motion = numcmd:sub(1,2)
    local held, peak, buf
    if motion == "46" then
        held = charge_state.back_held
        peak = charge_state.back_peak
        buf  = charge_state.back_buffer
    elseif motion == "28" then
        held = charge_state.down_held
        peak = charge_state.down_peak
        buf  = charge_state.down_buffer
    else
        return true, nil
    end
    -- Currently holding enough? (shouldn't normally happen since player needs
    -- to release and press forward, but covers edge cases)
    if held >= timing.charge then return true, nil end
    -- Released with enough charge, still within this move's buffer window?
    if peak >= timing.charge and buf >= (BUFFER_MAX - timing.buffer) then
        return true, buf
    end
    return false, nil
end

-- ── COMBO-NOTES CHARGE DETECTOR ─────────────────────────────
-- A simplified, character-agnostic charge-release check used ONLY by
-- the combo-notes recorder. Returns one of:
--   "[4]6" — back was charged then released, current dir is forward/neutral
--   "[2]8" — down was charged then released, current dir is up/neutral
--   nil    — no charge release detected this frame
--
-- Differs from has_valid_charge() in two ways:
--   1. Uses a single global threshold (CN_CHARGE_FRAMES) instead of
--      character-specific timings. Combo notes are a notation aid for
--      the player, not a move-detection system — there's no need to
--      match the exact frames-per-character that the game uses. A
--      reasonable middle-of-the-road threshold covers everyone.
--   2. Works for non-charge characters too. Any character's combos can
--      include charge-style notation if the player chooses to record
--      one (some practice routines call for it).
--
-- The buffer check piggybacks on the existing charge_state.back_buffer
-- and down_buffer fields (decrementing post-release counters), so the
-- player has the standard ~12-frame window between release and press
-- to land the charge-notation token.
local CN_CHARGE_FRAMES = 30   -- minimum hold frames to register as charge
local CN_CHARGE_BUFFER = 12   -- max frames between release and button press

-- Mirror numpad directions when facing left (1<->3, 4<->6, 7<->9)
-- Declared BEFORE cn_detect_charge_release so that function (and others
-- using DIR_MIRROR) can capture it as an upvalue. A previous version had
-- this declared further down the file; cn_detect_charge_release saw it
-- as a nil global on P2 side, throwing "attempt to index a nil value"
-- at runtime and silently aborting the combo-notes recording path.
local DIR_MIRROR = { [1]=3, [2]=2, [3]=1, [4]=6, [5]=5, [6]=4, [7]=9, [8]=8, [9]=7 }

local function cn_detect_charge_release()
    -- Current direction relative to character facing. read_direction
    -- returns physical numpad; mirror it through DIR_MIRROR if facing
    -- left so "6" always means "toward opponent" here. Matches the
    -- canonical orientation used by charge_state.back_*.
    local phys = read_direction()
    local cur  = phys
    if p1_facing_left then cur = DIR_MIRROR[phys] or phys end

    -- Back→Forward charge: held back long enough, released within the
    -- buffer window, and current direction is forward (6) or neutral
    -- (5 — player released to neutral before pressing). The buffer
    -- field counts UP from 0 to BUFFER_MAX on release then decrements;
    -- a release within the last CN_CHARGE_BUFFER frames means
    -- back_buffer >= (BUFFER_MAX - CN_CHARGE_BUFFER).
    if charge_state.back_peak >= CN_CHARGE_FRAMES
       and charge_state.back_buffer >= (BUFFER_MAX - CN_CHARGE_BUFFER)
       and (cur == 6 or cur == 5) then
        return "[4]6"
    end

    -- Down→Up charge: same logic but for down-held → up-pressed.
    -- Accepts any up-ish direction (7, 8, 9) or neutral.
    if charge_state.down_peak >= CN_CHARGE_FRAMES
       and charge_state.down_buffer >= (BUFFER_MAX - CN_CHARGE_BUFFER)
       and (cur == 7 or cur == 8 or cur == 9 or cur == 5) then
        return "[2]8"
    end

    return nil
end

-- Guile Perfect Timing detector: 3F window from direction release to button press.
is_perfect_timing = function(char_name, numcmd)
    if char_name ~= "Guile" then return false end
    if numcmd:match("PP$") or numcmd:match("KK$") then return false end
    local motion = numcmd:sub(1,2)
    local buf
    if motion == "46" then buf = charge_state.back_buffer
    elseif motion == "28" then buf = charge_state.down_buffer
    else return false end
    -- Buffer initialized at 20; perfect window = first 3F after release
    return buf >= 18
end

-- ============================================================
-- STANCE LOGIC (runtime)
-- ============================================================
-- Forward-declared above. Assign bodies here, AFTER btn_flags/BTN
-- are in scope.
--
-- Stance lifecycle:
--   1. Player inputs the stance entry (e.g. Alex 2PP). update_stance_state
--      detects this from button state and sets stance_state.active.
--   2. While active, button presses inside resolve_numcmd are routed to
--      resolve_stance_followup, which returns a stance-specific numcmd
--      (e.g. "2pp>5lp") to be looked up directly in the JSON's by_input.
--   3. Stance exits when:
--      - Player presses an exit-classified followup (Tactical Hop, throws,
--        manual exit via 7/8/9)
--      - A generous timeout fires (safety net for missed exit detection)
-- ============================================================

local STANCE_TIMEOUT = 180  -- 3s safety net; real stance has no auto-timeout
                            -- but we don't want to be stuck in stance forever
                            -- if we miss the exit input

is_in_stance = function(char_name)
    return stance_state.active ~= nil and stance_state.char == char_name
end

-- Detect stance entry / track stance frames / handle automatic timeout.
-- Called once per frame from update_dir_buffer.
update_stance_state = function(p1_name)
    -- If currently in a stance, increment frame counter; check timeout.
    if stance_state.active then
        stance_state.frames = stance_state.frames + 1
        if stance_state.frames > STANCE_TIMEOUT then
            stance_state.active = nil
            stance_state.char = nil
            stance_state.frames = 0
            stance_state.sub_state = nil
        end
    end
    -- (Stance entry detection happens in resolve_numcmd when the player
    -- actually presses 2+P+P, since we need the OD-press detection logic
    -- that already exists there.)
end

-- Called from resolve_numcmd when player is in a stance and pressed a button.
-- Returns the stance-followup numcmd (e.g. "2pp>5lp") and updates stance state
-- (exits if the followup is an exit type).
--
-- Args:
--   stance_id     : "prowler" (currently the only one)
--   atk_btn_idx   : the button that was just pressed (BTN.LP, BTN.HK, etc.)
--   p_pressed_n   : count of punches pressed this frame (for command-grab detection)
--   k_pressed_n   : count of kicks pressed this frame
--   cur_dir       : current canonical direction (mirrored for facing)
--
-- Returns: numcmd string, or nil if no valid stance followup matched.
resolve_stance_followup = function(stance_id, atk_btn_idx, p_pressed_n, k_pressed_n, cur_dir)
    if stance_id ~= "prowler" then return nil end

    -- Helper: clear stance state (when followup exits the stance)
    local function exit_stance()
        stance_state.active = nil
        stance_state.char = nil
        stance_state.frames = 0
        stance_state.sub_state = nil
    end

    -- Throws (LP+LK simultaneously). Always exit stance.
    if p_pressed_n >= 1 and k_pressed_n >= 1 then
        exit_stance()
        if cur_dir == 2 or cur_dir == 1 or cur_dir == 3 then
            return "2pp>2lplk"   -- Dangerous Armbar (down + LP+LK)
        else
            return "2pp>5lplk"   -- Hyper Takedown (LP+LK)
        end
    end

    -- Map raw button to suffix
    local btn_str
    if     atk_btn_idx == BTN.LP then btn_str = "5lp"
    elseif atk_btn_idx == BTN.MP then btn_str = "5mp"
    elseif atk_btn_idx == BTN.HP then btn_str = "5hp"
    elseif atk_btn_idx == BTN.LK then btn_str = "5lk"
    elseif atk_btn_idx == BTN.MK then btn_str = "5mk"
    elseif atk_btn_idx == BTN.HK then btn_str = "5hk"
    else return nil end

    -- Direction-modified followups (forward + punch -> Slashing Elbow)
    if cur_dir == 6 and (atk_btn_idx == BTN.LP or atk_btn_idx == BTN.MP or atk_btn_idx == BTN.HP) then
        -- 2pp>6p (Slashing Elbow) - stays in stance
        return "2pp>6p"
    end

    -- Sweep Combo chain: HK can be pressed twice
    if atk_btn_idx == BTN.HK then
        if stance_state.sub_state == "sweep1" then
            -- Second HK after first HK -> Sweep Combination 2 (exits stance)
            exit_stance()
            return "2pp>5hk>5hk"
        else
            -- First HK -> Sweep Combination 1 (stays in stance for chain window)
            stance_state.sub_state = "sweep1"
            -- Reset chain window after a few frames if the player doesn't follow up.
            -- (Handled implicitly: stance_state.sub_state resets on next button press.)
            return "2pp>5hk"
        end
    end

    -- Tactical Hop (LK alone) -> exits stance via jump
    if atk_btn_idx == BTN.LK then
        exit_stance()
        return "2pp>5lk"
    end

    -- All other buttons -> stay in stance, return the standard followup key.
    -- Reset sub_state since we did not chain HK->HK.
    stance_state.sub_state = nil
    return "2pp>" .. btn_str
end

-- Update direction buffer each frame
local function update_dir_buffer(frame)
    local dir = read_direction()
    if #dir_buffer == 0 or dir_buffer[#dir_buffer].dir ~= dir then
        table.insert(dir_buffer, { dir=dir, frame=frame })
    end
    if #dir_buffer > 60 then table.remove(dir_buffer, 1) end
    -- Per-frame charge tracking (back-held, down-held, buffer countdown)
    update_charge_state()
    -- Per-frame stance tracking (timeout, frame counter)
    update_stance_state(players[1] and players[1].name or "?")
    -- Track airborne state: prefer Y-position, fall back to input-based tracking
    if _SF6UI.dbg.dbg_p1y then
        is_airborne = (_SF6UI.dbg.dbg_p1y > GROUND_Y_THRESHOLD)
    else
        if dir == 7 or dir == 8 or dir == 9 then
            is_airborne = true
            frames_since_up = 0
            -- Dhalsim's float jump arc is significantly longer than the rest of the roster
            local p1name = players[1] and players[1].name or "?"
            if p1name == "Dhalsim" then
                air_frames_remaining = AIR_DURATION_DHALSIM
            else
                air_frames_remaining = AIR_DURATION
            end
        elseif is_airborne then
            -- Crouching dirs (1,2,3) require pulling stick down past neutral —
            -- impossible mid-jump — so they force-clear airborne immediately.
            if dir == 1 or dir == 2 or dir == 3 then
                is_airborne = false
                air_frames_remaining = 0
                frames_since_up = 0
            else
                -- Stick is off-up (4/5/6). Count frames; once we've been off-up
                -- for LAND_GRACE frames continuously, declare landed. This
                -- handles the case where a forward jump (9) lands with the stick
                -- still resting at 6 — the player has clearly committed away
                -- from up, so they're grounded even if AIR_DURATION hasn't run out.
                -- Grace window (~133ms) absorbs the brief mid-jump dips to 6 or 4
                -- that occur during stick steering without prematurely clearing.
                frames_since_up = frames_since_up + 1
                air_frames_remaining = air_frames_remaining - 1
                if frames_since_up >= LAND_GRACE or air_frames_remaining <= 0 then
                    is_airborne = false
                end
            end
        end
    end
end

-- Strict motion check: sequence must appear in buffer in order,
-- all within DIR_BUFFER_WINDOW frames, and the LAST entry in the
-- buffer must match the last direction in the sequence.
local function motion_in_buffer(seq, current_frame)
    local last_buf = dir_buffer[#dir_buffer]
    if not last_buf then return false end
    if (current_frame - last_buf.frame) > 3 then return false end -- stale
    if last_buf.dir ~= seq[#seq] then return false end
    local si = #seq
    local earliest_frame = current_frame - DIR_BUFFER_WINDOW
    for i = #dir_buffer, 1, -1 do
        local entry = dir_buffer[i]
        if entry.frame < earliest_frame then break end
        if entry.dir == seq[si] then
            si = si - 1
            if si == 0 then return true end
        end
    end
    return false
end

-- Recorder motion check: waypoint-based, no intermediate dirs required.
-- Fast inputs like 214 may skip diagonal frames entirely in dir_buffer,
-- so we only require key waypoints (e.g. for 214: saw "2" then "4" within window).
-- Also tolerates the last dir being neutral (stick released before attack).
-- Waypoint sets: only these dirs must appear in order within the window.
-- Intermediate dirs (like the 1 in 214) are optional.

-- HCF / HCB: dedicated detector with relaxed constraints. The generic
-- motion_in_buffer struggles with half-circles because:
--   1. The buffer only records direction CHANGES (not every frame), so
--      after the player completes 4→1→2→3→6 and just holds 6 for a
--      few frames, last_buf.frame is several frames stale by the time
--      they hit the attack. motion_in_buffer's 3-frame staleness cap
--      rejects this.
--   2. A 5-direction sequence inside the 28F DIR_BUFFER_WINDOW means
--      the player has only ~5.5 frames per direction — borderline
--      even for smooth controller execution and outright impossible
--      on keyboard where transitioning A→S→D goes through unmapped
--      diagonal states.
--   3. Real SF6 itself accepts shortcut HCFs like 4-3-6 (skipping the
--      pure-down 2). The strict 5-element match doesn't allow this.
--
-- Relaxed contract: returns true if within the last HC_WINDOW frames
-- the buffer contains 4 → at-least-one-of(1/2/3) → 6 in order, and
-- the current direction is 6 or recently-was-6. The "recently-was"
-- tolerance is HC_STALE frames — far more generous than the generic
-- 3F window.
--
-- end_dir / start_dir are the canonical ends:
--   HCF: start=4, end=6
--   HCB: start=6, end=4
-- mid_dirs is {1,2,3} for both (the half-circle traverses the bottom).
-- HC tuning. Inlined as literals below — bundling these into a
-- single local table would still consume a chunk-level local slot,
-- and we're at the 200-active-local Lua hard cap. Tweak in-place
-- if half-circles need a different cadence. Current values:
--   window=30 (~500ms) — max span from start_dir to end_dir entry,
--                        matches realistic fight-pace input where
--                        a smooth HCF takes ~2-5 frames per stored
--                        direction transition.
--   stale=5  (~83ms)  — buffer-end may be this old and still count.
--                        Players commit to the attack press right at
--                        motion completion; a longer staleness window
--                        causes stale `6` entries to false-positive
--                        unrelated attacks (e.g. a walk-forward then
--                        an unrelated normal would otherwise register
--                        as HCF if a `4` happened to be in history).

local function hc_in_buffer(start_dir, end_dir, current_frame)
    if #dir_buffer == 0 then return false end
    -- Acceptable current state: either the player is still pressing
    -- end_dir (last_buf.dir == end_dir, possibly stale because they
    -- held it), OR they recently released to neutral after end_dir
    -- (more typical when the attack press also triggers release).
    -- Scan for the most recent entry matching end_dir.
    local end_idx = nil
    local end_frame = nil
    for i = #dir_buffer, 1, -1 do
        local e = dir_buffer[i]
        if (current_frame - e.frame) > 30 then break end  -- HC window
        if e.dir == end_dir then
            end_idx = i
            end_frame = e.frame
            break
        end
    end
    if not end_idx then return false end
    -- end_dir must be recent enough to count as "ending now"
    if (current_frame - end_frame) > 5 then return false end  -- HC stale

    -- Walk back from end_idx looking for a mid-direction (1/2/3),
    -- then for start_dir before that. Must all fit within HC window (30F).
    local earliest_frame = current_frame - 30
    local saw_mid = false
    for i = end_idx - 1, 1, -1 do
        local e = dir_buffer[i]
        if e.frame < earliest_frame then return false end
        if not saw_mid then
            if e.dir == 1 or e.dir == 2 or e.dir == 3 then
                saw_mid = true
            end
        else
            if e.dir == start_dir then
                return true
            end
        end
    end
    return false
end

-- DP: detect 623 (or 421 when facing left) including shortcut variants.
-- Uses physical stick directions and flips pattern based on facing.
local function dp_in_buffer(btn_name, frame)
    local last_buf = dir_buffer[#dir_buffer]
    if not last_buf then return nil end
    -- Choose pattern based on facing:
    --   Facing right: look for 6>2>3 (end on 3 or 6 for shortcut)
    --   Facing left:  look for 4>2>1 (end on 1 or 4 for shortcut)
    local d_fwd_down, d_down, d_fwd
    local end_a, end_b
    if p1_facing_left then
        d_fwd_down, d_down, d_fwd = 1, 2, 4
        end_a, end_b = 1, 4
    else
        d_fwd_down, d_down, d_fwd = 3, 2, 6
        end_a, end_b = 3, 6
    end
    if last_buf.dir ~= end_a and last_buf.dir ~= end_b then return nil end
    if (frame - last_buf.frame) > 6 then return nil end
    local extended_window = DIR_BUFFER_WINDOW * 2
    local earliest = frame - extended_window
    local found_fd, found_d, found_f = false, false, false
    local start_idx = #dir_buffer
    if last_buf.dir == end_b then start_idx = start_idx - 1 end
    for i = start_idx, 1, -1 do
        local e = dir_buffer[i]
        if e.frame < earliest then break end
        if not found_fd and e.dir == d_fwd_down then found_fd = true
        elseif found_fd and not found_d and e.dir == d_down then found_d = true
        elseif found_fd and found_d and not found_f and e.dir == d_fwd then found_f = true; break end
    end
    if found_f then return "623"..btn_name end  -- mirrored to 421 later if facing left
    return nil
end

-- DIR_MIRROR is declared earlier in the file (before cn_detect_charge_release).
-- See note there for why.
local function mirror_numstr(s)
    return (s:gsub("[1-9]", function(c) return tostring(DIR_MIRROR[tonumber(c)] or c) end))
end

-- Build numCmd string from motion + button press
local function resolve_numcmd(atk_btn, frame)
    local btn_name
    if atk_btn == BTN.LP then btn_name = "LP"
    elseif atk_btn == BTN.MP then btn_name = "MP"
    elseif atk_btn == BTN.HP then btn_name = "HP"
    elseif atk_btn == BTN.LK then btn_name = "LK"
    elseif atk_btn == BTN.MK then btn_name = "MK"
    else btn_name = "HK" end

    local letter = (atk_btn == BTN.LP or atk_btn == BTN.MP or atk_btn == BTN.HP) and "P" or "K"

    -- When facing left, check motions using mirrored patterns against raw buffer.
    -- Output is always canonical (236/623/etc) since framedata uses canonical notation.
    local qcf_seq = p1_facing_left and {2,1,4} or {2,3,6}
    local qcb_seq = p1_facing_left and {2,3,6} or {2,1,4}
    -- HCF/HCB no longer use seq tables — dedicated hc_in_buffer takes
    -- raw start/end directions, see the call site below.
    local rdp_seq = p1_facing_left and {6,2,3} or {4,2,1}
    local charge_bf_seq = p1_facing_left and {6,4} or {4,6}

    -- Check motions in order of complexity (most specific first).
    -- HCF/HCB use dedicated waypoint detectors with relaxed timing
    -- (40F window, 10F staleness, single mid-direction required) —
    -- the strict motion_in_buffer is too restrictive for 5-direction
    -- half-circles and was missing most legitimate inputs. See the
    -- hc_in_buffer comments for the rationale.
    -- Facing-aware: when P1 faces left, the input directions for HCF
    -- and HCB are swapped (canonical 41236 in notation is physically
    -- 63214 on the stick, and vice versa). We pass the physical
    -- start/end dirs and let the function check the raw buffer; the
    -- *output* notation (the "41236"/"63214" string returned to the
    -- caller) stays canonical so framedata lookups work consistently.
    local hcf_start = p1_facing_left and 6 or 4
    local hcf_end   = p1_facing_left and 4 or 6
    local hcb_start = p1_facing_left and 4 or 6
    local hcb_end   = p1_facing_left and 6 or 4
    if hc_in_buffer(hcb_start, hcb_end, frame) then return "63214"..btn_name end
    if hc_in_buffer(hcf_start, hcf_end, frame) then return "41236"..btn_name end
    local dp = dp_in_buffer(btn_name, frame)
    if dp then return dp end
    if motion_in_buffer(rdp_seq, frame) then return "421"..btn_name end
    if motion_in_buffer(qcf_seq, frame) then return "236"..btn_name end
    if motion_in_buffer(qcb_seq, frame) then return "214"..btn_name end
    -- Charge motions: the charge tracker (update_charge_state) is authoritative.
    -- We do NOT use motion_in_buffer here — that function requires the back/down
    -- direction entry to be within DIR_BUFFER_WINDOW (28F), but real charges
    -- take 40-50F to build, so motion_in_buffer would ALWAYS fail for a real
    -- charge hold. Instead, we check:
    --   1. The player's CURRENT direction is forward (6) or up (8).
    --   2. has_valid_charge says the required hold time was met.
    -- has_valid_charge returns true for non-charge characters, so this block
    -- only matters for the 6 charge chars.
    local cur_dir_physical = read_direction()
    local cur_dir = cur_dir_physical
    if p1_facing_left then
        cur_dir = DIR_MIRROR[cur_dir_physical] or cur_dir_physical
    end
    local char_name = players[1] and players[1].name or "?"
    if is_charge_character(char_name) then
        -- Back-charge: current direction must be forward (6) or neutral (5)
        -- (player may have released to neutral before pressing button)
        if (cur_dir == 6 or cur_dir == 5) and has_valid_charge(char_name, "46"..btn_name) then
            return "46"..btn_name
        end
        -- Down-up charge: current direction must be up (8/7/9) or neutral (5)
        if (cur_dir == 8 or cur_dir == 7 or cur_dir == 9 or cur_dir == 5)
            and has_valid_charge(char_name, "28"..btn_name) then
            return "28"..btn_name
        end
    end

    -- Airborne specials: check qcf/qcb without requiring last dir to match
    -- (player usually has up/diagonal held when pressing button mid-air)
    if is_airborne then
        local function air_motion(seq)
            local earliest = frame - DIR_BUFFER_WINDOW
            local si = 1
            for i = 1, #dir_buffer do
                local e = dir_buffer[i]
                if e.frame >= earliest and e.dir == seq[si] then
                    si = si + 1
                    if si > #seq then return true end
                end
            end
            return false
        end
        if air_motion(qcf_seq) then return "236"..btn_name end
        if air_motion(qcb_seq) then return "214"..btn_name end
        return "j." .. btn_name
    end

    -- Normals: convert physical direction to canonical notation
    local dir = read_direction()
    if p1_facing_left then dir = DIR_MIRROR[dir] or dir end
    local prefix
    if     dir == 2 then prefix = "2"
    elseif dir == 6 then prefix = "6"
    elseif dir == 3 then prefix = "3"
    elseif dir == 4 then prefix = "4"
    elseif dir == 1 then prefix = "1"
    else   prefix = "5" end

    return prefix .. btn_name
end

-- Lookup move in frame data by numCmd, trying multiple formats
local function lookup_move(fd, numcmd)
    if not fd then return nil end
    local key = numcmd:lower()
    local mv = fd.by_input[key]
    if mv then return mv end
    -- Grounded specials: some moves use generic K/P (e.g. "236K" for Rashid's Whirlwind Shot)
    -- Strip specific button strength: 236lk -> 236k, 623mp -> 623p
    local generic_key = key:gsub("l([pk])$","%1"):gsub("m([pk])$","%1"):gsub("h([pk])$","%1")
    if generic_key ~= key then
        mv = fd.by_input[generic_key]
        if mv then return mv end
    end
    -- Aerial specials: framedata keys are whitespace-stripped, so "214K (air)" is stored as "214k(air)"
    if is_airborne then
        local stripped = key:gsub("^j%.", "")
        mv = fd.by_input[stripped .. "(air)"]
        if mv then return mv end
        -- Also try with generic button (lk->k, mk->k, hk->k)
        local generic = stripped:gsub("lk$","k"):gsub("mk$","k"):gsub("hk$","k")
        mv = fd.by_input[generic .. "(air)"]
        if mv then return mv end
        -- Jump normals: some framedatas use "8LP" instead of "j.LP"
        if key:sub(1,2) == "j." then
            mv = fd.by_input["8" .. key:sub(3)]
            if mv then return mv end
        end
    end
    return nil
end

local frame_counter = 0

local last_numcmd = "none"
local prev_numcmd = "none"   -- used to detect new inputs for combo notes recording

local function update_current_moves()
    frame_counter = frame_counter + 1

    -- Try to find InputManager if not found yet
    if not im_found and frame_counter % 60 == 0 then
        find_input_manager()
    end

    -- Decay display timers
    if current_move.p1_frames > 0 then
        current_move.p1_frames = current_move.p1_frames - 1
        if current_move.p1_frames == 0 then
            current_move.p1 = nil
            current_move.p1_perfect = false
        end
    end
    if current_move.p2_frames > 0 then
        current_move.p2_frames = current_move.p2_frames - 1
        if current_move.p2_frames == 0 then
            current_move.p2 = nil
            current_move.p2_perfect = false
        end
    end

    if not im_found then return end

    -- Update direction buffer
    update_dir_buffer(frame_counter)

    -- Check each attack button for a fresh press on P1
    local attack_btns = { BTN.LP, BTN.MP, BTN.HP, BTN.LK, BTN.MK, BTN.HK }
    local punch_btns = { BTN.LP, BTN.MP, BTN.HP }
    local kick_btns  = { BTN.LK, BTN.MK, BTN.HK }

    -- Count simultaneously-pressed punches/kicks this frame (OD detection)
    local p_pressed, k_pressed = 0, 0
    for _, idx in ipairs(punch_btns) do if btn_just_pressed(idx) then p_pressed = p_pressed + 1 end end
    for _, idx in ipairs(kick_btns)  do if btn_just_pressed(idx) then k_pressed = k_pressed + 1 end end
    -- "Did any attack button rising-edge this frame?" — used by the
    -- combo-notes recorder to allow same-numcmd-twice (LP, LP, LP)
    -- without filtering out repeat presses as duplicates. The original
    -- `last_numcmd ~= prev_numcmd` gate suppresses repeats; this flag
    -- overrides it on a fresh button press.
    local any_attack_pressed_this_frame = (p_pressed + k_pressed) > 0

    local od_suffix = nil
    if p_pressed >= 2 then od_suffix = "PP"
    elseif k_pressed >= 2 then od_suffix = "KK" end

    -- ── CROSS-PAIR DETECTION (Modern compound buttons) ────
    -- SF6 represents Modern's Throw/DI/Drive Parry buttons as the same
    -- bit-combinations a Classic player would produce by pressing the
    -- two underlying buttons simultaneously:
    --   LP+LK → Throw
    --   MP+MK → DP (Drive Parry)
    --   HP+HK → DI (Drive Impact)
    --
    -- This works for BOTH schemes since SF6's input layer collapses the
    -- two paths to the same logical event. We detect rising-edges of the
    -- specific pair within the same frame (humans pressing macro buttons,
    -- or any user pressing a Modern compound button, will hit the same
    -- frame; staggered Classic presses fall through to single-button
    -- detection just like today).
    --
    -- compound_pair stays nil unless one of the three pairs fires. The
    -- recording site below uses it to emit a single compound token
    -- (Modern only) instead of two separate attack tokens.
    local lp_now = btn_just_pressed(BTN.LP)
    local lk_now = btn_just_pressed(BTN.LK)
    local mp_now = btn_just_pressed(BTN.MP)
    local mk_now = btn_just_pressed(BTN.MK)
    local hp_now = btn_just_pressed(BTN.HP)
    local hk_now = btn_just_pressed(BTN.HK)
    local compound_pair = nil
    if     lp_now and lk_now then compound_pair = "Throw"
    elseif mp_now and mk_now then compound_pair = "DP"
    elseif hp_now and hk_now then compound_pair = "DI"
    end

    -- ── STANCE ROUTING ─────────────────────────────────────
    -- If P1 is currently in a stance, route button presses to the stance
    -- followup resolver instead of the normal/OD detection. This keeps stance
    -- followups (e.g. "2pp>5lp") from being misinterpreted as ground normals.
    --
    -- Stance entry detection happens AFTER the normal flow runs - we let the
    -- 2PP move resolve normally first, then flip stance state on if it matched.
    local p1_name = players[1] and players[1].name or "?"
    if is_in_stance(p1_name) then
        -- Compute current canonical direction (mirror for facing)
        local cur_dir_phys = read_direction()
        local cur_dir_canon = cur_dir_phys
        if p1_facing_left then
            cur_dir_canon = DIR_MIRROR[cur_dir_phys] or cur_dir_phys
        end

        -- Track whether we've handled the input this frame, so we don't
        -- double-process. Replaces the earlier `goto stance_done` pattern,
        -- which Lua rejects when the goto would jump into the scope of a
        -- later-declared local.
        local handled = false

        -- Up directions exit the stance manually (Stance Exit)
        if cur_dir_canon == 7 or cur_dir_canon == 8 or cur_dir_canon == 9 then
            local up_now = btn_flags(BTN.UP) ~= 0
            local up_prev = prev_btn[BTN.UP] or false
            if up_now and not up_prev then
                local fd = load_framedata(p1_name)
                local mv = fd and (fd.by_input["2pp>7/8/9"] or fd.by_input["2pp>8"])
                last_numcmd = "2pp>7/8/9"
                if mv then
                    current_move.p1 = mv
                    current_move.p1_frames = MOVE_DISPLAY_FRAMES
                    current_move.p1_perfect = false
                end
                stance_state.active = nil
                stance_state.char = nil
                stance_state.frames = 0
                stance_state.sub_state = nil
                handled = true
            end
        end

        -- Forward / Back direction with NO button = stance movement
        if not handled
            and (cur_dir_canon == 6 or cur_dir_canon == 4)
            and p_pressed == 0 and k_pressed == 0 then
            local relevant_btn = (cur_dir_canon == 6)
                and (p1_facing_left and BTN.LEFT or BTN.RIGHT)
                or (p1_facing_left and BTN.RIGHT or BTN.LEFT)
            local now  = btn_flags(relevant_btn) ~= 0
            local prev = prev_btn[relevant_btn] or false
            if now and not prev then
                local key = (cur_dir_canon == 6) and "2pp>6" or "2pp>4"
                local fd = load_framedata(p1_name)
                local mv = fd and fd.by_input[key]
                last_numcmd = key
                if mv then
                    current_move.p1 = mv
                    current_move.p1_frames = MOVE_DISPLAY_FRAMES
                    current_move.p1_perfect = false
                end
                -- Stays in stance; do not clear stance_state.
                handled = true
            end
        end

        -- Button press while in stance: route to stance followup resolver
        if not handled then
            local pressed_btn_idx = nil
            for _, idx in ipairs(attack_btns) do
                if btn_just_pressed(idx) then pressed_btn_idx = idx; break end
            end
            if pressed_btn_idx then
                local numcmd = resolve_stance_followup("prowler", pressed_btn_idx,
                                                       p_pressed, k_pressed, cur_dir_canon)
                if numcmd then
                    last_numcmd = numcmd
                    local fd = load_framedata(p1_name)
                    local mv = fd and fd.by_input[numcmd]
                    if mv then
                        current_move.p1 = mv
                        current_move.p1_frames = MOVE_DISPLAY_FRAMES
                        current_move.p1_perfect = false
                    end
                end
            end
        end

        -- Update prev_btn state and return early - skip normal detection
        for _, idx in ipairs(attack_btns) do
            prev_btn[idx] = btn_flags(idx) ~= 0
        end
        for _, idx in ipairs({BTN.UP, BTN.DOWN, BTN.LEFT, BTN.RIGHT}) do
            prev_btn[idx] = btn_flags(idx) ~= 0
        end
        return
    end
    -- ── END STANCE ROUTING ─────────────────────────────────

    if od_suffix then
        -- Use first pressed button of that type to build motion, then swap suffix
        local first_idx = (od_suffix == "PP") and BTN.LP or BTN.LK
        for _, idx in ipairs((od_suffix == "PP") and punch_btns or kick_btns) do
            if btn_just_pressed(idx) then first_idx = idx; break end
        end
        local numcmd = resolve_numcmd(first_idx, frame_counter)
        -- Replace trailing button (e.g. "236LP") with OD suffix ("236PP")
        numcmd = numcmd:gsub("[LMH][PK]$", od_suffix)
        last_numcmd = numcmd
        local fd = load_framedata(players[1].name)
        local mv = lookup_move(fd, numcmd)
        if mv then
            current_move.p1 = mv
            current_move.p1_frames = MOVE_DISPLAY_FRAMES
            -- Latch perfect-timing flag at registration. (OD versions never
            -- have perfect timing, so this is_perfect_timing call returns
            -- false here, but kept for symmetry with the regular branch.)
            current_move.p1_perfect = is_perfect_timing(players[1].name, numcmd)
            -- ── STANCE ENTRY DETECTION ─────────────────────
            -- Alex enters Prowler Stance via "2PP" (down + 2 punches).
            -- After the move resolves successfully, flip stance state on.
            if players[1].name == "Alex" and numcmd:lower() == "2pp" then
                stance_state.active = "prowler"
                stance_state.char = "Alex"
                stance_state.frames = 0
                stance_state.sub_state = nil
            end
            -- ── END STANCE ENTRY ────────────────────────────
        end
    else
        for _, idx in ipairs(attack_btns) do
            if btn_just_pressed(idx) then
                local numcmd = resolve_numcmd(idx, frame_counter)
                last_numcmd = numcmd
                local fd = load_framedata(players[1].name)
                local mv = lookup_move(fd, numcmd)
                if mv then
                    current_move.p1 = mv
                    current_move.p1_frames = MOVE_DISPLAY_FRAMES
                    -- Latch perfect-timing flag at the moment of registration,
                    -- so it persists for the full move display duration. The
                    -- charge_state.back_buffer counts down each frame, so
                    -- evaluating is_perfect_timing at draw time gives a
                    -- ~3-frame window before reverting.
                    current_move.p1_perfect = is_perfect_timing(players[1].name, numcmd)
                end
                break
            end
        end
    end

    -- ── COMBO NOTES CONTROLLER INPUT RECORDING ───────────
    -- When Combo Notes window is open, any attack button pressed this

    -- ── KEYBOARD SHORTCUTS ────────────────────────────────────
    -- Editor keys for users who keep one hand on the keyboard:
    --   Backspace : delete the token before the cursor
    --   Left/Right: move cursor by one token
    --   Home/End  : jump cursor to start / end of slot
    --
    -- IMPORTANT: we use `reframework.is_key_down(vk)` here, NOT
    -- `imgui.is_key_*`. The imgui keyboard io is polluted by
    -- gamepad input — REF's imgui binding maps the gamepad d-pad
    -- and left analog stick onto the arrow keys for menu navigation
    -- purposes, so the arrow keys read as "always DOWN" whenever
    -- the player has a controller plugged in (which is always, for
    -- a fighting game). Backspace through imgui also has issues
    -- because the rising-edge detector inside imgui never sees a
    -- clean transition.
    --
    -- reframework.is_key_down reads raw Win32 keyboard state via
    -- GetAsyncKeyState — completely independent of imgui and
    -- gamepad input. We do our own rising-edge math against
    -- cn_refresh.kb_prev[vk] for press-only semantics, and use
    -- a per-key repeat timer so holding a key still chains
    -- (matching OS-style key-repeat at ~30/s after 250ms delay).
    --
    -- Wrapped in pcall so an exotic REF build that doesn't expose
    -- the reframework.is_key_down API silently no-ops instead of
    -- erroring. The on-screen palette + controller SHIFT hotkeys
    -- remain functional as fallbacks.
    if show_combo_notes_win then
        local char_name = ROSTER[edit_char_idx]
        if char_name then
            local slot = get_combo_slot(char_name, combo_edit_slot)
            local toks = slot and slot.tokens
            if toks then
                -- Key repeat parameters (frames at 60fps):
                --   30 frames = ~500ms initial delay before repeat
                --   4  frames = ~66ms between repeats (~15/sec)
                -- Backspace gets repeat (hold to chain-delete);
                -- arrows get repeat (hold to scrub); Home/End
                -- don't need repeat — single fire is correct.
                local REPEAT_DELAY  = 30
                local REPEAT_PERIOD = 4

                local function key_down(vk)
                    local ok, v = pcall(function()
                        return reframework:is_key_down(vk)
                    end)
                    -- Also try the dot-syntax form for builds that
                    -- expose it that way instead of the colon form.
                    if not ok then
                        ok, v = pcall(function()
                            return reframework.is_key_down(vk)
                        end)
                    end
                    return ok and v == true
                end

                -- Edge + repeat detector: returns true on the rising
                -- edge OR while held past REPEAT_DELAY at REPEAT_PERIOD
                -- intervals. Per-key state on cn_refresh.kb_prev (held
                -- count, where 0 = up, N = N frames since press).
                local function key_fire(vk, allow_repeat)
                    local cur = key_down(vk)
                    local prev_count = cn_refresh.kb_prev[vk] or 0
                    if cur then
                        cn_refresh.kb_prev[vk] = prev_count + 1
                        if prev_count == 0 then
                            return true   -- rising edge
                        end
                        if allow_repeat and prev_count >= REPEAT_DELAY then
                            -- Fire every REPEAT_PERIOD frames after delay
                            if (prev_count - REPEAT_DELAY) % REPEAT_PERIOD == 0 then
                                return true
                            end
                        end
                    else
                        cn_refresh.kb_prev[vk] = 0
                    end
                    return false
                end

                -- Backspace (VK_BACK = 0x08) — with repeat
                if key_fire(0x08, true) then
                    if combo_edit_cursor > 0 and #toks > 0 then
                        table.remove(toks, combo_edit_cursor)
                        combo_edit_cursor = combo_edit_cursor - 1
                        combo_notes_dirty[char_name] = true
                    end
                end
                -- Left arrow (VK_LEFT = 0x25) — with repeat
                if key_fire(0x25, true) then
                    if combo_edit_cursor > 0 then
                        combo_edit_cursor = combo_edit_cursor - 1
                    end
                end
                -- Right arrow (VK_RIGHT = 0x27) — with repeat
                if key_fire(0x27, true) then
                    if combo_edit_cursor < #toks then
                        combo_edit_cursor = combo_edit_cursor + 1
                    end
                end
                -- Home (VK_HOME = 0x24) — no repeat
                if key_fire(0x24, false) then
                    combo_edit_cursor = 0
                end
                -- End (VK_END = 0x23) — no repeat
                if key_fire(0x23, false) then
                    combo_edit_cursor = #toks
                end
            end
        end
    end

    -- ── SHIFT MODIFIER (MP+LK) ──────────────────────────────
    -- When the Combo Notes editor is open and the user holds MP+LK
    -- as a chord, the next non-modifier attack press fires a hotkey
    -- action instead of recording as a normal token:
    --   HP → insert ">" separator
    --   LP → backspace (delete previous token)
    -- The modifier is intentionally a two-button chord (not a single
    -- button) so it can't be triggered accidentally during normal
    -- combo recording. MP+LK was chosen because it isn't one of SF6's
    -- recognized compound pairs (LP+LK / MP+MK / HP+HK) — no risk of
    -- emitting a Throw/DP/DI token by accident.
    --
    -- LOCKOUT WINDOW: MP and LK each individually trigger recording,
    -- so a freshly-pressed MP (or LK) lands as a token before the
    -- second button of the chord arrives. To prevent stray tokens
    -- from polluting the slot, we keep a small history of recent
    -- insertions (rec_history). When SHIFT transitions from inactive
    -- → active, we walk back through the last ~5 frames and remove
    -- any tokens added during that window. Adjusted indices are
    -- deleted highest-first so earlier positions stay valid.
    local SHIFT_LOCKOUT_FRAMES = 5
    local shift_mp_held = (btn_flags(BTN.MP) ~= 0)
    local shift_lk_held = (btn_flags(BTN.LK) ~= 0)
    local shift_now     = shift_mp_held and shift_lk_held
    local shift_rising  = shift_now and not cn_refresh.shift_prev
    cn_refresh.shift_prev   = shift_now
    cn_refresh.shift_active = shift_now

    if shift_rising and show_combo_notes_win then
        -- Roll back any recordings inside the lockout window.
        -- Walk newest-first; remove tokens by index in descending
        -- order so earlier indices stay valid as we mutate the array.
        local hist = cn_refresh.rec_history
        local cutoff = frame_counter - SHIFT_LOCKOUT_FRAMES
        local i = #hist
        while i >= 1 do
            local rec = hist[i]
            if rec and rec.frame >= cutoff then
                local cs = combo_slots[rec.char_key]
                local sd = cs and cs[rec.slot]
                local toks = sd and sd.tokens
                if toks and rec.indices then
                    -- Sort descending and delete. Building a fresh
                    -- sorted copy is fine — index list is tiny (1-2
                    -- entries per record).
                    local sorted = {}
                    for k = 1, #rec.indices do sorted[k] = rec.indices[k] end
                    table.sort(sorted, function(a,b) return a > b end)
                    -- Cursor decrement only applies when the rollback
                    -- targets the *currently-edited* slot. If the user
                    -- switched slots between the original recording and
                    -- SHIFT activation, the cursor already moved to the
                    -- new slot's end during the switch — decrementing
                    -- here would push it incorrectly negative.
                    local cur_char = ROSTER[edit_char_idx]
                    local affects_active_slot =
                        cur_char and rec.char_key == cur_char:lower()
                        and rec.slot == combo_edit_slot
                    for _, idx in ipairs(sorted) do
                        if idx >= 1 and idx <= #toks then
                            table.remove(toks, idx)
                            if affects_active_slot and combo_edit_cursor >= idx then
                                combo_edit_cursor = combo_edit_cursor - 1
                            end
                        end
                    end
                    combo_notes_dirty[rec.char_key] = true
                end
                hist[i] = nil  -- consumed; won't roll back twice
            elseif rec and rec.frame < cutoff then
                -- History is roughly chronological; once we cross
                -- the cutoff older entries are also safe.
                break
            end
            i = i - 1
        end
        -- Defensive cursor clamp after rollback
        if combo_edit_cursor < 0 then combo_edit_cursor = 0 end
    end

    -- While SHIFT is held in the editor, run hotkey actions on
    -- third-button rising edges and suppress all normal recording
    -- for this frame.
    if show_combo_notes_win and shift_now then
        local char_name = ROSTER[edit_char_idx]
        if char_name then
            local slot = get_combo_slot(char_name, combo_edit_slot)
            local toks = slot.tokens
            if not toks then toks = {}; slot.tokens = toks end

            -- HP rising-edge → insert ">"
            if btn_just_pressed(BTN.HP) then
                if combo_edit_cursor > #toks then combo_edit_cursor = #toks end
                if combo_edit_cursor < 0       then combo_edit_cursor = 0       end
                table.insert(toks, combo_edit_cursor + 1, {t="sep"})
                combo_edit_cursor = combo_edit_cursor + 1
                combo_notes_dirty[char_name] = true
            end
            -- LP rising-edge → backspace (delete previous token)
            if btn_just_pressed(BTN.LP) then
                if combo_edit_cursor > 0 and #toks > 0 then
                    table.remove(toks, combo_edit_cursor)
                    combo_edit_cursor = combo_edit_cursor - 1
                    combo_notes_dirty[char_name] = true
                end
            end
        end
        -- Suppress normal recording this frame: update prev_btn state
        -- and bail out before the recorder runs.
        for _, idx in ipairs(attack_btns) do
            prev_btn[idx] = btn_flags(idx) ~= 0
        end
        for _, idx in ipairs({BTN.UP, BTN.DOWN, BTN.LEFT, BTN.RIGHT}) do
            prev_btn[idx] = btn_flags(idx) ~= 0
        end
        prev_numcmd = last_numcmd
        return
    end

    -- ── Normal combo-notes recording (gated above by SHIFT) ──
    -- Each frame an attack button just-pressed while the editor is open
    -- frame gets converted to a (dir, btn) token pair and inserted at
    -- the cursor. Gating on `any_attack_pressed_this_frame` rather than
    -- `last_numcmd ~= prev_numcmd` means repeat presses (e.g. LP, LP,
    -- LP) all register — the equality check would suppress duplicates
    -- since the numcmd string doesn't change between identical presses.
    if show_combo_notes_win and any_attack_pressed_this_frame
       and last_numcmd ~= "none" then
        local char_name = ROSTER[edit_char_idx]
        if char_name then
            local slot = get_combo_slot(char_name, combo_edit_slot)
            -- Operate on the real tokens array, not the slot table.
            -- (See insert_at_cursor in the CN window block for the full
            -- explanation of why this is necessary.)
            local toks = slot.tokens
            if not toks then
                toks = {}
                slot.tokens = toks
            end
            local dir, btn = numcmd_to_tokens(last_numcmd)
            if dir and btn then
                -- CHARGE-RELEASE OVERRIDE: if the player just released
                -- a long-held back or down within the buffer window AND
                -- pressed an attack on a forward/up direction, replace
                -- the simple direction token with the canonical charge
                -- notation ([4]6 or [2]8). Works for both schemes and
                -- for any character — the recorder is a notation aid,
                -- not a move-detection system, so we use a single
                -- 30-frame global threshold instead of per-character
                -- timings. See cn_detect_charge_release for details.
                --
                -- Applies to OD pairs too: charge characters with OD
                -- specials use [4]6PP / [2]8KK notation naturally.
                local charge_dir = cn_detect_charge_release()
                if charge_dir then
                    dir = charge_dir
                end
                -- Modern scheme: SF6's InputManager reports Classic
                -- labels (LP/MP/HP/LK/MK/HK) for every physical button
                -- press regardless of the player's chosen control type.
                -- For a Modern-scheme character we translate to the
                -- Modern equivalent (L/M/H/SP/DP/Auto per
                -- CLASSIC_TO_MODERN_BTN) so the saved tokens line up
                -- with the on-screen palette and the moderncombonotes.json
                -- file stays consistent. OD pairs (PP/KK) have no
                -- Modern equivalent and pass through unchanged.
                --
                -- COMPOUND-PAIR OVERRIDE: if the user pressed LP+LK,
                -- MP+MK, or HP+HK simultaneously this frame, that's
                -- either a Classic two-button macro OR a Modern user
                -- pressing their dedicated Throw/Parry/DI button —
                -- SF6 represents both the same way at the input layer.
                -- In Modern scheme we collapse the pair into a single
                -- compound token (Throw / DP / DI). The direction
                -- prefix is preserved, so back+Throw renders as
                -- "4 Throw" (back throw) — meaningful in notation.
                if get_combo_scheme(char_name) == "modern" then
                    if compound_pair then
                        btn = compound_pair
                    else
                        local mapped = CLASSIC_TO_MODERN_BTN[btn]
                        if mapped then btn = mapped end
                    end
                end
                -- Clamp cursor against the real array length.
                if combo_edit_cursor > #toks then combo_edit_cursor = #toks end
                if combo_edit_cursor < 0       then combo_edit_cursor = 0       end
                -- Track the array indices we're about to insert into
                -- so the SHIFT lockout can roll them back if needed.
                local inserted_indices = {}
                if dir ~= "5" then   -- skip neutral-direction prefix
                    table.insert(toks, combo_edit_cursor + 1, {t="dir", v=dir})
                    combo_edit_cursor = combo_edit_cursor + 1
                    inserted_indices[#inserted_indices+1] = combo_edit_cursor
                end
                table.insert(toks, combo_edit_cursor + 1, {t="btn", v=btn})
                combo_edit_cursor = combo_edit_cursor + 1
                inserted_indices[#inserted_indices+1] = combo_edit_cursor
                combo_notes_dirty[char_name] = true

                -- Log to rec_history for the SHIFT lockout window.
                -- Only the trailing few frames are useful; prune the
                -- ring buffer to bound memory.
                local hist = cn_refresh.rec_history
                hist[#hist+1] = {
                    frame     = frame_counter,
                    char_key  = char_name:lower(),
                    slot      = combo_edit_slot,
                    indices   = inserted_indices,
                }
                if #hist > 30 then
                    table.remove(hist, 1)
                end
            end
        end
    end
    prev_numcmd = last_numcmd

    -- Update previous button states
    for _, idx in ipairs(attack_btns) do
        prev_btn[idx] = btn_flags(idx) ~= 0
    end
    for _, idx in ipairs({BTN.UP, BTN.DOWN, BTN.LEFT, BTN.RIGHT}) do
        prev_btn[idx] = btn_flags(idx) ~= 0
    end
end
-- Parses a numcmd string into {dir, btn} token pairs and appends
-- them to the currently-edited combo slot when Combo Notes is open.
-- numcmd formats from resolve_numcmd:
--   "236HP"  "5LP"  "j.MK"  "46LP"  "2[8]KK"  "[4]6HP"
-- numcmd_to_tokens is forward-declared near top of file so
-- update_current_moves can see it (Lua scope rules — see comment there).
numcmd_to_tokens = function(numcmd)
    if not numcmd or numcmd == "none" then return nil, nil end

    -- OD suffix (PP / KK) — check before splitting
    local od = numcmd:match("([PK][PK])$")
    local btn
    if od then
        btn = od
        numcmd = numcmd:sub(1, -(#od+1))
    else
        -- Normal button suffix: LP MP HP LK MK HK
        btn = numcmd:match("([LMH][PK])$")
        if btn then
            numcmd = numcmd:sub(1, -(#btn+1))
        end
    end

    if not btn then return nil, nil end

    -- What's left is the direction/motion prefix
    local dir = numcmd
    if dir == "" then dir = "5" end  -- shouldn't happen but safety net

    return dir, btn
end

-- Hook uBattleCore.update - always refreshes found_core every frame
local td_core = sdk.find_type_definition("app.battle.uBattleCore")
if td_core then
    for _, mn in ipairs({"update","lateUpdate"}) do
        local m = td_core:get_method(mn)
        if m then
            sdk.hook(m, function(args)
                pcall(function()
                    local obj = sdk.to_managed_object(args[2])
                    if obj then found_core = obj end
                end)
            end, nil)
        end
    end
end

local function find_esf(fobj, depth, max_depth)
    if not fobj or depth > max_depth then return nil end
    local name = safe_call(fobj, "get_Name")
    if name then
        local m = tostring(name):lower():match("(esf%d+)")
        if m then return m end
    end
    local transform = safe_call(fobj, "get_Transform")
    if not transform then return nil end
    local cc = safe_call(transform, "get_ChildCount") or 0
    for i = 0, math.min(cc-1, 12) do
        local ct = safe_call(transform, "getChild", i)
        if ct then
            local cg = safe_call(ct, "get_GameObject")
            if cg then
                local esf = find_esf(cg, depth+1, max_depth)
                if esf then return esf end
            end
        end
    end
    return nil
end

local function update_players_inner()
    if not found_core then
        players[1].esf = "?"; players[1].name = "?"
        players[2].esf = "?"; players[2].name = "?"
        detect_diag.fighters_obj   = false
        detect_diag.fighter_count  = 0
        detect_diag.p1_fobj        = false
        detect_diag.p1_name_raw    = "?"
        return
    end
    local fighters = safe_get(found_core, "_Fighters")
    detect_diag.fighters_obj = (fighters ~= nil)
    if not fighters then return end
    local fc = safe_call(fighters, "get_Count") or 0
    detect_diag.fighter_count = fc
    local p1x, p2x = nil, nil
    -- Also get FighterDescs for position access via FighterObj
    local fighter_descs = safe_get(found_core, "_FighterDescs")
    local fd_count = fighter_descs and (safe_call(fighter_descs, "get_Count") or 0) or 0
    for slot = 1, 2 do
        local i = slot - 1
        local fobj = (i < fc) and safe_call(fighters, "get_Item", i) or nil
        if slot == 1 then
            detect_diag.p1_fobj = (fobj ~= nil)
            if fobj then
                local raw = safe_call(fobj, "get_Name")
                detect_diag.p1_name_raw = raw and tostring(raw) or "(no name)"
            else
                detect_diag.p1_name_raw = "(no fobj)"
            end
        end
        local esf  = fobj and find_esf(fobj, 0, 3) or nil
        if esf then
            if not ESF_MAP[esf] then _sf6_relookup_esf(esf) end
            players[slot].esf  = esf
            players[slot].name = ESF_MAP[esf] or ("Unknown " .. esf)
            -- Auto-sync the profiles menu to P1's detected character.
            -- Resets profile_user_override only when game P1 transitions
            -- to a NEW character, not every frame they differ. The
            -- last_p1_idx tracker is what makes this transition-based
            -- rather than state-based — without it, a manual override
            -- would be wiped every frame in any replay where game P1
            -- doesn't match the user's pick.
            if slot == 1 then
                local detected_name = ESF_MAP[esf]
                if detected_name then
                    local idx = ROSTER_INDEX[detected_name]
                    if idx then
                        -- Only clear override on an actual P1 change.
                        if last_p1_idx and last_p1_idx ~= idx then
                            profile_user_override = false
                        end
                        last_p1_idx = idx
                        if not profile_user_override and idx ~= edit_char_idx then
                            edit_char_idx   = idx
                            -- Reset combo notes view to slot 1 of the new char.
                            combo_edit_slot = 1
                            combo_edit_cursor = 0   -- new slot, fresh cursor
                        end
                    end
                end
            end
        else
            players[slot].esf  = "?"
            players[slot].name = "?"
        end
        -- Get fighter object via FighterDesc.FighterObj (more reliable path)
        local desc_obj = (i < fd_count) and safe_call(fighter_descs, "get_Item", i) or nil
        local fighter_obj = desc_obj and safe_get(desc_obj, "FighterObj") or fobj
        -- Try to read world X position (multiple paths because fighter internals vary)
        if fobj then
            local x = nil
            -- Path A: Transform.Position (Vector3 with numeric x)
            local tr = safe_call(fobj, "get_Transform")
            if tr then
                local pos = safe_call(tr, "get_Position")
                if pos then
                    -- Vector3 is a struct; try direct field access via call_vf
                    local ok, v = pcall(function() return pos.x end)
                    if ok and v then x = v end
                    if not x then
                        local ok2, v2 = pcall(function() return pos:get_field("x") end)
                        if ok2 and v2 then x = v2 end
                    end
                end
            end
            if x then
                if slot == 1 then p1x = tonumber(x); _SF6UI.dbg.dbg_p1x = p1x else p2x = tonumber(x); _SF6UI.dbg.dbg_p2x = p2x end
            end
        end
    end
    -- Determine P1's facing direction by X position comparison
    if p1x and p2x then
        p1_facing_left = (p1x > p2x)
    end
end

local function update_players()
    local ok = pcall(update_players_inner)
    if not ok then
        players[1].esf = "?"; players[1].name = "?"
        players[2].esf = "?"; players[2].name = "?"
    end
end

-- ── HUD GEOMETRY (resolution-adaptive) ───────────────────────
-- Two geometries:
--   bar_geo        - STATIC position of the health bars. Used for
--                    tick marks so they stay glued to the actual bars.
--   profile_anchor - bar_geo PLUS the user's offset sliders, used to
--                    nudge profile text placement if needed.
local HUD = {
    bar_y_ratio          = 0.0587,
    bar_h_ratio          = 0.0308,
    bar_w_ratio          = 0.3532,
    p1_x_ratio           = 0.1003,
    p2_x_ratio           = 0.5465,
    -- Sloped-bar baseline: zero offset, slope at inner edge with zero
    -- length = no slope. Skins like SFIV override these to carve the
    -- bar into outer-flat / sloped-section / inner-shifted regions.
    inner_y_offset_ratio = 0.0,
    slope_start_ratio    = 1.0,
    slope_end_ratio      = 1.0,
}

-- HUD skin selection (cosmetic UI only at this stage; geometry not
-- branched yet — adding that step later once the dropdown itself is
-- confirmed working).
_SF6UI.hud.HUD_SKIN_ORDER = { "SF6", "SimSim", "SSF2T", "SFA3", "SF3s", "SFIV", "SFVCE" }

-- Pretty display names for the cycle button. Internal keys stay
-- short for save-file stability and table-key brevity; the UI shows
-- the longer canonical title for each game.
_SF6UI.hud.HUD_SKIN_DISPLAY = {
    SF6    = "SF6",
    SimSim = "SimSim",
    SSF2T  = "SSF2T",
    SFA3   = "SFA3",
    SF3s   = "SF3 3rd Strike",
    SFIV   = "USFIV",
    SFVCE  = "SFV:CE",
}

-- Per-skin GEOMETRY OVERRIDES. Empty table = use HUD defaults.
-- Calibrated via SF6_Calibrate.lua; F12 prints these values.
-- Only fields that actually differ from SF6 baseline need to be set.
_SF6UI.hud.HUD_SKIN_OVERRIDES = {
    SF6    = {},  -- baseline, no overrides
    SimSim = {
        bar_y_ratio = 0.0587,
        bar_h_ratio = 0.0322,
        bar_w_ratio = 0.3649,
        p1_x_ratio  = 0.0969,
        p2_x_ratio  = 0.5382,
    },
    SSF2T  = {
        bar_y_ratio = 0.0619,
        bar_h_ratio = 0.0308,
        bar_w_ratio = 0.3602,
        p1_x_ratio  = 0.1076,
        p2_x_ratio  = 0.5322,
    },
    SFA3   = {
        bar_y_ratio = 0.0615,
        bar_h_ratio = 0.0308,
        bar_w_ratio = 0.3693,
        p1_x_ratio  = 0.1011,
        p2_x_ratio  = 0.5296,
    },
    SF3s   = {
        bar_y_ratio = 0.0712,
        bar_h_ratio = 0.0285,
        bar_w_ratio = 0.3561,
        p1_x_ratio  = 0.1039,
        p2_x_ratio  = 0.5400,
    },
    SFIV   = {
        bar_y_ratio          = 0.0689,
        bar_h_ratio          = 0.0340,
        bar_w_ratio          = 0.3537,
        p1_x_ratio           = 0.0980,
        p2_x_ratio           = 0.5483,
        inner_y_offset_ratio = 0.0102,
        slope_start_ratio    = 0.390,
        slope_end_ratio      = 0.580,
    },
    SFVCE  = {
        bar_y_ratio = 0.0606,
        bar_h_ratio = 0.0271,
        bar_w_ratio = 0.3558,
        p1_x_ratio  = 0.0969,
        p2_x_ratio  = 0.5473,
    },
}

-- Per-skin TICK STYLE: "slanted" (SF6 default) or "vertical".
-- Retro skins use vertical ticks; modern SF6 uses the angled '\' / '/' style.
_SF6UI.hud.HUD_SKIN_TICK_STYLE = {
    SF6    = "slanted",
    SimSim = "vertical",
    SSF2T  = "vertical",
    SFA3   = "vertical",
    SF3s   = "vertical",
    SFIV   = "vertical",
    SFVCE  = "vertical",
}

-- Per-skin TICK COLOR. Retro skins with yellow HP fill need blue ticks
-- to remain readable; SF6 default keeps the established yellow ticks.
-- Values are color-constant NAMES, resolved at draw time via
-- tick_color() so init order doesn't matter.
_SF6UI.hud.HUD_SKIN_TICK_COLOR = {
    SF6    = "yellow",
    SimSim = "blue",
    SSF2T  = "blue",
    SFA3   = "blue",
    SF3s   = "blue",
    SFIV   = "blue",
    SFVCE  = "blue",
}

-- Per-skin TICK LABEL PLACEMENT: "below" (default) or "above".
-- SF3s renders with the percentage labels ABOVE the bars because the
-- bar sits low enough that below-labels would clash with the energy
-- gauge / drive segments underneath.
_SF6UI.hud.HUD_SKIN_TICK_LABEL_POS = {
    SF6    = "below",
    SimSim = "below",
    SSF2T  = "below",
    SFA3   = "below",
    SF3s   = "above",
    SFIV   = "below",
    SFVCE  = "below",
}

-- Returns the active value for one geometry field, falling back to
-- the HUD default when the current skin has no override.
local function hud_field(field)
    local skin = cfg.hud_skin or "SF6"
    local override = _SF6UI.hud.HUD_SKIN_OVERRIDES[skin]
    if override and override[field] ~= nil then return override[field] end
    return HUD[field]
end

local function hud_tick_style()
    return _SF6UI.hud.HUD_SKIN_TICK_STYLE[cfg.hud_skin or "SF6"] or "slanted"
end

-- Resolve to actual color constant (lazy lookup so colors don't have
-- to be initialized before this module runs).
local function tick_color()
    local name = _SF6UI.hud.HUD_SKIN_TICK_COLOR[cfg.hud_skin or "SF6"] or "yellow"
    if name == "blue" then return C_TICK_BLUE end
    return C_TICK
end

local function tick_label_pos()
    return _SF6UI.hud.HUD_SKIN_TICK_LABEL_POS[cfg.hud_skin or "SF6"] or "below"
end

local function hud_skin_index(name)
    for i, n in ipairs(_SF6UI.hud.HUD_SKIN_ORDER) do
        if n == name then return i end
    end
    return 1
end

local function compute_bar_geo(sw, sh)
    local content_w = math.min(sw, math.floor(sh * (16/9)))
    local content_x = math.floor((sw - content_w) / 2)
    return {
        y        = math.floor(sh        * hud_field("bar_y_ratio")),
        h        = math.floor(sh        * hud_field("bar_h_ratio")),
        w        = math.floor(content_w * hud_field("bar_w_ratio")),
        p1_x     = content_x + math.floor(content_w * hud_field("p1_x_ratio")),
        p2_x     = content_x + math.floor(content_w * hud_field("p2_x_ratio")),
        -- Sloped-bar fields. inner_dy is the upward pixel shift applied
        -- to the inner section. s_st and s_end are normalized 0..1
        -- positions of the slope endpoints, measured from the OUTER edge.
        inner_dy = math.floor(sh        * hud_field("inner_y_offset_ratio")),
        s_st     = hud_field("slope_start_ratio"),
        s_end    = hud_field("slope_end_ratio"),
    }
end

-- ── UI STATE (cross-callback) ────────────────────────────────
-- Mouse state is captured at the start of each d2d draw callback.
-- Confirmed via d2d API probe: imgui.get_mouse() and
-- imgui.is_mouse_clicked() work correctly inside d2d draw,
-- so we don't need to bridge state from re.on_frame.
local frame_mouse_x, frame_mouse_y = 0, 0
local frame_click_pending = false

-- UI panel open state
local show_settings_win     = false
local show_display_win      = false
local show_profiles_win     = false
-- show_combo_notes_win is forward-declared at top of file so the
-- controller-input handler at ~line 1187 can read it. Re-using that
-- declaration here without a new `local`.
show_combo_notes_win        = false   -- Combo Notes sub-panel
local combo_notes_open_guard  = false  -- true for one frame after opening, blocks cn_click
local combo_notes_load_pending = nil   -- char name to load on next re.on_frame (set on char switch)

-- edit_char_idx and profile_user_override are forward-declared at top of file
local profile_dropdown_open = false   -- is the char dropdown list visible?
local show_settings_hk      = false   -- is the Settings & Hotkeys popup open?
local profile_dd_scroll     = 0       -- dropdown scroll offset

-- ── COMBO NOTES EDITOR STATE ─────────────────────────────────
-- 10 slots per character. Each slot has:
--   tokens  : list of { t="dir"|"btn"|"xx", v="..." }
--   title   : user-entered string up to 32 chars (default "Slot N")
--   active  : bool — whether this slot shows in the on-screen ticker
-- Up to 5 slots may be active at once.
combo_slots     = {}   -- keyed by char name lowercase
-- combo_edit_slot is forward-declared at top of file

local COMBO_MAX_SLOTS   = 30
local COMBO_MAX_ACTIVE  = 5     -- ticker capacity unchanged: 5 horizontal bars max
local COMBO_MAX_TITLE   = 32
-- Slot-list scroll state lives on `cn_refresh` (see its declaration up
-- near the d2d setup) — that table was already a chunk-level local so
-- we extend it rather than introducing a new chunk-level local. The
-- original file sits at exactly 200 active locals at peak (Lua's hard
-- cap); even one new chunk-level local breaks parsing.

local function default_combo_data(char_name)
    local d = {}
    for i = 1, COMBO_MAX_SLOTS do
        -- Default-active applies only to the first COMBO_MAX_ACTIVE slots
        -- so a fresh character never starts with more than the ticker
        -- can render. Remaining slots start inactive.
        d[i] = { tokens={}, title="Slot "..i, active=(i<=COMBO_MAX_ACTIVE), counter=0 }
    end
    return d
end

-- Forward declarations — bodies defined after COMBO NOTES PERSISTENCE block
local save_combo_notes
local load_combo_notes
-- combo_notes_dirty is forward-declared at top of file (Lua scope rules).
-- Just clearing it here, NOT redeclaring with `local` — that would shadow
-- the upvalue captured by update_current_moves and break recording again.
combo_notes_dirty = {}   -- char keys that need saving

local function get_char_combos(char_name)
    local key = char_name:lower()
    if not combo_slots[key] then
        combo_slots[key] = default_combo_data(char_name)
    end
    return combo_slots[key]
end

-- get_combo_slot is forward-declared at top of file (Lua scope rules).
get_combo_slot = function(char_name, slot)
    return get_char_combos(char_name)[slot]
end
local function set_combo_slot(char_name, slot, tokens)
    get_char_combos(char_name)[slot].tokens = tokens
end

-- ── Combo edit undo stack ──────────────────────────────────────
-- Per-(char, slot) stack of token-array snapshots. push_combo_undo is
-- called BEFORE every modifying action (insert, backspace, clear);
-- pop_combo_undo returns and removes the most recent snapshot.
-- Stack capped at 50 entries to bound memory; older entries drop off
-- the bottom when over. Cleared implicitly per slot/char (different
-- (char,slot) keys → different stacks; nothing to do).
local UNDO_STACK_MAX = 50
push_combo_undo = function(char_name, slot, tokens)
    local key = char_name:lower()
    if not combo_undo_stacks[key] then combo_undo_stacks[key] = {} end
    if not combo_undo_stacks[key][slot] then combo_undo_stacks[key][slot] = {} end
    local stack = combo_undo_stacks[key][slot]
    -- Snapshot = shallow copy of the token list. Tokens themselves
    -- are tables but are immutable once placed (no in-place edits),
    -- so a shallow copy preserves their identity safely.
    local snap = {}
    for i, t in ipairs(tokens) do snap[i] = t end
    stack[#stack + 1] = snap
    if #stack > UNDO_STACK_MAX then
        table.remove(stack, 1)
    end
end
pop_combo_undo = function(char_name, slot)
    local key = char_name:lower()
    if not combo_undo_stacks[key] then return nil end
    local stack = combo_undo_stacks[key][slot]
    if not stack or #stack == 0 then return nil end
    return table.remove(stack)
end

local function count_active(combos)
    local n = 0
    for _, s in ipairs(combos) do if s.active then n=n+1 end end
    return n
end

-- ── COMBO NOTES PERSISTENCE ───────────────────────────────────
-- File: reframework/data/sf6_framedata/<CharName>/{combonotes,moderncombonotes}.json
-- Sits alongside framedata.json in the same per-character folder. The
-- exact filename depends on the per-character control scheme stored
-- on cfg.profiles[key].combo_scheme:
--   "classic" → combonotes.json       (LP/MP/HP/LK/MK/HK + system tokens)
--   "modern"  → moderncombonotes.json (L/M/H/SP/Auto/Throw/DI/DP)
-- The web editor reads/writes the same two files (server.py routes
-- to combos vs combos_modern endpoints). Switching the scheme in the
-- in-game Combo Editor menu queues a reload so the matching file
-- loads on the next frame.
-- JSON structure (identical for both):
--   { slots: [ { title, active, tokens: [{t,v},...] }, ... ] }

local combo_notes_loaded = {}   -- set of char keys already loaded this session

local function combo_notes_path(char_name)
    local scheme = get_combo_scheme(char_name)
    local filename = (scheme == "modern") and "moderncombonotes.json" or "combonotes.json"
    return FRAMEDATA_BASE .. char_name .. "/" .. filename
end

-- Called from d2d draw callbacks — only sets a flag, never does I/O.
-- Actual file write happens in re.on_frame which is safe for I/O.
save_combo_notes = function(char_name)
    combo_notes_dirty[char_name] = true  -- keep original case for correct folder path
end

-- Manual JSON builders — avoids json.dump_string which can hard-crash
-- REFramework's C serializer on nested Lua tables.
local function json_str(s)
    s = tostring(s or "")
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"')
    return '"' .. s .. '"'
end
local function json_bool(b) return b and "true" or "false" end

-- Does the real file write — only called from re.on_frame.
local function flush_combo_notes(char_name)
    local key = char_name:lower()
    local combos = combo_slots[key]
    if not combos then return end

    local slot_strs = {}
    for i = 1, COMBO_MAX_SLOTS do
        local s = combos[i]
        local title  = s.title  or ("Slot " .. i)
        local active = s.active or false
        local toks   = s.tokens or {}

        local tok_strs = {}
        for _, tok in ipairs(toks) do
            local t = tostring(tok.t or "")
            local v = tostring(tok.v or "")
            tok_strs[#tok_strs+1] = '{"t":' .. json_str(t) .. ',"v":' .. json_str(v) .. '}'
        end

        local counter = s.counter or 0
        slot_strs[i] = '{"title":' .. json_str(title)
            .. ',"active":' .. json_bool(active)
            .. ',"counter":' .. tostring(counter)
            .. ',"tokens":[' .. table.concat(tok_strs, ",") .. ']}'
    end

    local out = '{"slots":[' .. table.concat(slot_strs, ",") .. ']}'
    local path = combo_notes_path(char_name)
    local f = io.open(path, "w")
    if f then
        f:write(out); f:close()
        -- Success path is silent — the dirty queue flushes on every
        -- token edit, so popping a modal each time is intolerable.
        -- Failures are still surfaced because they indicate a real
        -- problem (missing folder, permission denied, etc.).
    else
        re.msg("combonotes SAVE FAILED: " .. path .. " (folder missing?)")
    end
end

load_combo_notes = function(char_name)
    local key = char_name:lower()
    -- Use cased name for file path, lowercase for combo_slots key
    if combo_notes_loaded[char_name] then return end
    combo_notes_loaded[char_name] = true

    local f = io.open(combo_notes_path(char_name), "r")
    if not f then
        -- Missing file is a normal state for the OTHER scheme — users
        -- typically have Classic combos saved but no Modern ones (or
        -- vice versa). Silent return; the combo slot table stays at
        -- its defaults so the editor opens cleanly.
        return
    end
    local raw = f:read("*a"); f:close()
    if raw:sub(1,3) == "\xEF\xBB\xBF" then raw = raw:sub(4) end
    local ok, parsed = pcall(json.load_string, raw)
    if not ok or not parsed or not parsed.slots then return end

    -- Ensure slot table exists before writing into it
    if not combo_slots[key] then
        combo_slots[key] = default_combo_data(char_name)
    end
    local combos = combo_slots[key]
    for i, s in ipairs(parsed.slots) do
        if i <= COMBO_MAX_SLOTS and type(s) == "table" then
            if type(s.title)  == "string"  then combos[i].title  = s.title  end
            if type(s.active) == "boolean" then combos[i].active = s.active end
            if type(s.tokens) == "table"   then combos[i].tokens = s.tokens end
            if type(s.counter) == "number"  then combos[i].counter = s.counter end
        end
    end
end

-- ── CHARACTER NOTES PERSISTENCE ───────────────────────────────
-- File: reframework/data/sf6_framedata/<CharName>/notes.json
-- Written by the SF6 Overlay Editor (sf6_editor.exe). Read-only here.
-- JSON: { "notes": "...", "links": [{label,url}, ...] }
local notes_data         = {}     -- [char_key_lower] = { notes=..., links={} }
local notes_loaded       = {}     -- per-session load guard (cased name)
local notes_load_pending = nil    -- char name to (re)load on next on_frame

local function notes_path(char_name)
    return FRAMEDATA_BASE .. char_name .. "/notes.json"
end

local function load_char_notes(char_name)
    if notes_loaded[char_name] then return end
    notes_loaded[char_name] = true

    local path = notes_path(char_name)
    local f = io.open(path, "r")
    if not f then
        -- Silent: most chars won't have notes saved yet. Was a debug
        -- toast during initial wiring — removed now that loading works.
        return
    end
    local raw = f:read("*a"); f:close()
    if raw:sub(1,3) == "\xEF\xBB\xBF" then raw = raw:sub(4) end
    local ok, parsed = pcall(json.load_string, raw)
    if not ok or type(parsed) ~= "table" then
        -- Parse errors are real bugs (corrupt file or BOM regression)
        -- so this stays as a re.msg for visibility.
        re.msg("notes LOAD FAILED (parse): " .. path)
        return
    end

    notes_data[char_name:lower()] = {
        notes = (type(parsed.notes) == "string") and parsed.notes or "",
        links = (type(parsed.links) == "table")  and parsed.links  or {},
    }
end

-- ── CACHE INVALIDATION ────────────────────────────────────────
-- Drops the per-character load guards so the next re.on_frame
-- pass re-reads combonotes.json and notes.json from disk. Used by
-- the "Reload Config" button and the periodic auto-refresh below
-- so edits made in the web editor (or by hand) appear without a
-- script reload.
--
-- IMPORTANT: We deliberately do NOT clear combo_slots or notes_data
-- themselves. The loader overwrites those tables in place, field by
-- field, so the ticker keeps drawing the previous frame's data
-- until the new data lands — no one-frame flash. Clearing them
-- here caused a visible flicker every auto-refresh tick.
local function invalidate_char_caches()
    combo_notes_loaded = {}
    notes_loaded       = {}
end

-- Auto-refresh tick: every N frames we drop the load guards so the
-- on_frame loader re-reads files. Pure-Lua and crash-safe (load
-- functions already pcall'd at call site). 60 = ~1s at 60fps.
-- Bundled into one table to conserve the 200-locals-per-function cap.
-- This table has grown to hold *all* combo-notes-related UI state that
-- otherwise would need separate chunk-level locals — the original file
-- already sits at exactly 200 active locals at peak, so even one new
-- chunk-level local breaks parsing with "too many local variables".
-- Fields:
--   frames, counter             : auto-refresh timer (cn_refresh's original purpose)
--   notes_scroll                : Combo Notes editor scroll offset (rows)
--   notes_last_edit_slot        : last value of combo_edit_slot we auto-scrolled to
--   visible                     : visible row count for the Combo Notes slot list
--   shift_active                : whether MP+LK are currently both held (SHIFT modifier)
--   shift_prev                  : last frame's shift_active value (rising-edge detection)
--   rec_history                 : ring buffer of recent token-insertion records, used by
--                                 the SHIFT lockout-window to retroactively undo MP/LK
--                                 tokens that landed in the brief window before SHIFT
--                                 activation was detected. Each entry:
--                                   { frame=N, char_key="ryu", slot=3, indices={5,6} }
--                                 (indices are the array positions where the new tokens
--                                 were inserted, in insertion order). Capped at 30 entries.
-- notes_last_edit_slot gates the auto-scroll-into-view so it only fires
-- on selection change, not every frame — without that, manual scroll
-- via the ^/v arrows would be undone immediately by the auto-snap.
cn_refresh = {
    frames = 60, counter = 0,
    notes_scroll           = 0,
    notes_last_edit_slot   = -1,
    visible                = 12,
    shift_active           = false,
    shift_prev             = false,
    rec_history            = {},
    -- Keyboard probe state. kb_impl is the cached working
    -- key-pressed function (nil until the probe finds one);
    -- kb_label names the API for the debug panel; kb_prev holds
    -- last-frame held-state per VK for the manual rising-edge
    -- path used when only is_key_down is available.
    kb_impl                = nil,
    kb_label               = "probing...",
    kb_prev                = {},
}

-- Button glyph colors (matching SF6_Combo_Ticker.lua palette)
local CN_BTN_COLORS = {
    LP  = 0xFF1A82DC,   -- blue
    MP  = 0xFFDCAA1E,   -- yellow
    HP  = 0xFFC83232,   -- red
    LK  = 0xFF1A82DC,   -- blue (matches LP)
    MK  = 0xFFDCAA1E,   -- yellow (matches MP)
    HK  = 0xFFC83232,   -- red (matches HP)
    PP  = 0xFF7864DC,   -- blue-purple (OD punch)
    KK  = 0xFF78B478,   -- muted green (OD kick)
    DR  = 0xFF7ED957,   -- light green (Drive Rush)
    DRC = 0xFF7ED957,   -- light green (Drive Rush Cancel)
    MW  = 0xFFD4A017,   -- gold (Micro Walk)
    DRv = 0xFF1A3C82,   -- deep blue (Drive Reversal — Classic aux)
    CH  = 0xFFE6C200,   -- yellow (Counter Hit)
    PC  = 0xFFE08020,   -- orange (Punish Counter)
    SHM = 0xFF3CB44A,   -- green (Shimmy)
    Oki    = 0xFF8C46C8,   -- purple (Oki)
    SA1    = 0xFFB8860B,   -- dark gold
    SA2    = 0xFFB8860B,
    ["SA2-2"] = 0xFFB8860B,
    SA3    = 0xFFB8860B,
    ["SA3-2"] = 0xFFB8860B,
    -- F.Kill: previously hardcoded inline; centralized here so the
    -- legend renderer + button can both reference one source of truth.
    ["F.Kill"] = 0xFF8B1A1A,
    -- Modern controls palette. Mirrors the web editor's BTN_COLORS so
    -- the in-game ticker/preview tints match the web preview. L/M/H
    -- reuse Classic blue/yellow/red so Modern users get the same
    -- light/medium/hard color language as Classic. SP/Auto/Throw/DI/DP
    -- each get distinct hues so they read as their own category in
    -- the palette grid.
    L     = 0xFF1A82DC,   -- blue (Light)
    M     = 0xFFDCAA1E,   -- yellow (Medium)
    H     = 0xFFC83232,   -- red (Hard)
    SP    = 0xFFA855F7,   -- purple (Special)
    Auto  = 0xFF22C55E,   -- green (Auto-combo)
    Throw = 0xFFF97316,   -- orange (Throw)
    DI    = 0xFFC83232,   -- red (Drive Impact) — global override; the Classic
                          -- aux DI button adds a yellow stroke on top
    DP    = 0xFF1A3C82,   -- deep blue (Drive Impact/Parry/reversal)
}
_SF6UI.cncol.CN_BTN_TEXT   = 0xFFFFFFFF
_SF6UI.cncol.CN_DIR_BG     = 0xFF252535
_SF6UI.cncol.CN_DIR_HOVER  = 0xFF3A3A55
_SF6UI.cncol.CN_DIR_BORDER = 0xFF5555AA
_SF6UI.cncol.CN_DIR_TEXT   = 0xFFE0E0E0
_SF6UI.cncol.CN_CANCEL_COL = 0xFFAAAAAA

-- Button bar last positions (set during d2d draw, used for menu anchors)
local btn_x = {0, 0, 0}
local btn_w = {0, 0, 0}
local btn_y = 0
local btn_h = 0

-- Combo ticker fonts (initialized in d2d init callback)
local font_ticker_name, font_ticker_dir, font_ticker_glyph, font_ticker_cancel
local font_ticker_last_scale = -1   -- track when scale changes so fonts rebuild

-- ── FONT RESOURCES ──────────────────────────────────────────
-- See the FONT_SIZES / get_font setup below d2d.register.
-- Fonts are resolved per-frame inside the draw callback, so users
-- can change font size without a script reload.

-- ── UI HELPERS ───────────────────────────────────────────────
local COLOR_PRESETS = {
    { name="White",  rgba={1.0,1.0,1.0,1.0} },
    { name="Yellow", rgba={1.0,1.0,0.0,1.0} },
    { name="Cyan",   rgba={0.2,0.9,1.0,1.0} },
    { name="Green",  rgba={0.2,1.0,0.3,1.0} },
    { name="Red",    rgba={1.0,0.4,0.4,1.0} },
    { name="Orange", rgba={1.0,0.6,0.2,1.0} },
}

local function color_index(rgba_tbl)
    for i, p in ipairs(COLOR_PRESETS) do
        if math.abs(p.rgba[1]-rgba_tbl[1])<0.05
        and math.abs(p.rgba[2]-rgba_tbl[2])<0.05
        and math.abs(p.rgba[3]-rgba_tbl[3])<0.05 then
            return i
        end
    end
    return 1
end

local function next_in_cycle(current, presets)
    for i, v in ipairs(presets) do
        if v == current then
            return presets[(i % #presets) + 1]
        end
    end
    return presets[1]
end

local function hit_rect(x, y, w, h)
    return frame_mouse_x >= x and frame_mouse_x <= x + w
       and frame_mouse_y >= y and frame_mouse_y <= y + h
end

-- Consume a click if the mouse is inside rect this frame.
local function click_in(x, y, w, h)
    if hit_rect(x, y, w, h) and frame_click_pending then
        frame_click_pending = false
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
--  SF6 OVERLAY - UI THEME & HELPERS  (additive; no menu is restyled yet)
--  Inserted after click_in() so hit_rect/click_in are in scope.
--  ZERO file-scope local slots used: the script is at the Lua 200-active-
--  locals limit, so THEME and UI live on a single GLOBAL namespace table
--  (_SF6UI). Globals do not count against the 200 limit.
--  Rollback: delete this block + the one _SF6UI.THEME.init() call added to
--  init_colors(). No existing C_* constant or feature logic is touched.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── ACCENT PRESETS ─────────────────────────────────────────────────────
-- Hand-tuned accent palettes. Each preset overrides ONLY the accent-family
-- keys; structural surfaces (panel_bg, text_*, btn_idle) are shared and set
-- unconditionally in init(). Selected via cfg.accent_preset (a key below).
-- Lives on the _SF6UI global => costs no file-scope local slots.
-- argb(r, g, b, a). To add a preset: copy a block, retune, add its key to
-- ACCENT_ORDER. Menu-only: ticker (TC_*) and P1/P2 colors are NOT touched.
_SF6UI.THEME.ACCENT_ORDER = { "violet", "ocean", "emerald", "crimson", "amber", "neon" }
_SF6UI.THEME.ACCENT_NAMES = {
    violet = "Violet", ocean = "Ocean", emerald = "Emerald",
    crimson = "Crimson", amber = "Amber", neon = "Neon",
}
-- Swatch RGBA shown next to the picker (matches each preset's btn_active hue).
_SF6UI.THEME.ACCENT_SWATCH = {
    violet  = { 0.40, 0.28, 0.74, 1.0 },
    ocean   = { 0.16, 0.44, 0.78, 1.0 },
    emerald = { 0.14, 0.56, 0.38, 1.0 },
    crimson = { 0.62, 0.12, 0.18, 1.0 },
    amber   = { 0.74, 0.46, 0.10, 1.0 },
    neon    = { 0.00, 0.85, 0.85, 1.0 },
}
_SF6UI.THEME.ACCENTS = {
    violet = function(argb) return {
        panel_border  = argb(0.45, 0.40, 0.70, 0.45),
        title_bg      = argb(0.16, 0.12, 0.28, 1.0),
        title_bg_lo   = argb(0.10, 0.08, 0.18, 1.0),
        accent_neutral= argb(0.40, 0.28, 0.74, 1.00),
        accent_neutral2=argb(0.40, 0.62, 0.98, 1.00),
        btn_hover     = argb(0.24, 0.20, 0.40, 0.98),
        btn_active    = argb(0.52, 0.38, 0.92, 1.00),
        btn_border    = argb(0.42, 0.40, 0.62, 0.50),
        btn_border_hi = argb(0.68, 0.58, 0.98, 0.80),
        divider       = argb(0.55, 0.50, 0.75, 0.20),
        divider_strong= argb(0.60, 0.54, 0.82, 0.38),
        toggle_on_bg  = argb(0.55, 0.40, 0.95, 1.00),
        toggle_on_glow= argb(0.55, 0.40, 0.95, 0.30),
        pill_arrow_hi = argb(0.40, 0.30, 0.70, 1.00),
        pill_arrow_txt= argb(0.80, 0.74, 1.00, 1.00),
        row_hover     = argb(0.45, 0.35, 0.80, 0.16),
        row_active_bg = argb(0.40, 0.32, 0.70, 0.14),
    } end,
    ocean = function(argb) return {
        panel_border  = argb(0.30, 0.52, 0.78, 0.45),
        title_bg      = argb(0.10, 0.18, 0.32, 1.0),
        title_bg_lo   = argb(0.06, 0.12, 0.22, 1.0),
        accent_neutral= argb(0.16, 0.44, 0.78, 1.00),
        accent_neutral2=argb(0.30, 0.78, 0.92, 1.00),
        btn_hover     = argb(0.16, 0.28, 0.46, 0.98),
        btn_active    = argb(0.24, 0.55, 0.95, 1.00),
        btn_border    = argb(0.32, 0.46, 0.66, 0.50),
        btn_border_hi = argb(0.48, 0.70, 0.98, 0.80),
        divider       = argb(0.42, 0.58, 0.80, 0.20),
        divider_strong= argb(0.46, 0.62, 0.86, 0.38),
        toggle_on_bg  = argb(0.24, 0.58, 0.96, 1.00),
        toggle_on_glow= argb(0.24, 0.58, 0.96, 0.30),
        pill_arrow_hi = argb(0.24, 0.44, 0.74, 1.00),
        pill_arrow_txt= argb(0.70, 0.86, 1.00, 1.00),
        row_hover     = argb(0.30, 0.55, 0.88, 0.16),
        row_active_bg = argb(0.26, 0.50, 0.80, 0.14),
    } end,
    emerald = function(argb) return {
        panel_border  = argb(0.28, 0.62, 0.48, 0.45),
        title_bg      = argb(0.08, 0.24, 0.18, 1.0),
        title_bg_lo   = argb(0.05, 0.16, 0.12, 1.0),
        accent_neutral= argb(0.14, 0.56, 0.38, 1.00),
        accent_neutral2=argb(0.34, 0.86, 0.62, 1.00),
        btn_hover     = argb(0.14, 0.34, 0.28, 0.98),
        btn_active    = argb(0.20, 0.74, 0.52, 1.00),
        btn_border    = argb(0.30, 0.56, 0.46, 0.50),
        btn_border_hi = argb(0.42, 0.82, 0.62, 0.80),
        divider       = argb(0.40, 0.66, 0.56, 0.20),
        divider_strong= argb(0.44, 0.70, 0.60, 0.38),
        toggle_on_bg  = argb(0.22, 0.78, 0.54, 1.00),
        toggle_on_glow= argb(0.22, 0.78, 0.54, 0.30),
        pill_arrow_hi = argb(0.22, 0.54, 0.42, 1.00),
        pill_arrow_txt= argb(0.74, 1.00, 0.88, 1.00),
        row_hover     = argb(0.28, 0.74, 0.56, 0.16),
        row_active_bg = argb(0.24, 0.66, 0.50, 0.14),
    } end,
    crimson = function(argb) return {
        panel_border  = argb(0.70, 0.34, 0.42, 0.45),
        title_bg      = argb(0.28, 0.10, 0.14, 1.0),
        title_bg_lo   = argb(0.18, 0.06, 0.09, 1.0),
        accent_neutral= argb(0.62, 0.12, 0.18, 1.00),
        accent_neutral2=argb(0.98, 0.48, 0.42, 1.00),
        btn_hover     = argb(0.40, 0.18, 0.24, 0.98),
        btn_active    = argb(0.90, 0.30, 0.42, 1.00),
        btn_border    = argb(0.62, 0.36, 0.42, 0.50),
        btn_border_hi = argb(0.98, 0.52, 0.58, 0.80),
        divider       = argb(0.75, 0.48, 0.52, 0.20),
        divider_strong= argb(0.82, 0.52, 0.56, 0.38),
        toggle_on_bg  = argb(0.92, 0.32, 0.44, 1.00),
        toggle_on_glow= argb(0.92, 0.32, 0.44, 0.30),
        pill_arrow_hi = argb(0.70, 0.26, 0.34, 1.00),
        pill_arrow_txt= argb(1.00, 0.78, 0.80, 1.00),
        row_hover     = argb(0.88, 0.34, 0.44, 0.16),
        row_active_bg = argb(0.80, 0.30, 0.40, 0.14),
    } end,
    amber = function(argb) return {
        panel_border  = argb(0.72, 0.56, 0.26, 0.45),
        title_bg      = argb(0.28, 0.20, 0.06, 1.0),
        title_bg_lo   = argb(0.18, 0.13, 0.04, 1.0),
        accent_neutral= argb(0.74, 0.46, 0.10, 1.00),
        accent_neutral2=argb(0.98, 0.78, 0.30, 1.00),
        btn_hover     = argb(0.40, 0.30, 0.12, 0.98),
        btn_active    = argb(0.95, 0.62, 0.18, 1.00),
        btn_border    = argb(0.64, 0.52, 0.32, 0.50),
        btn_border_hi = argb(0.98, 0.78, 0.46, 0.80),
        divider       = argb(0.76, 0.62, 0.40, 0.20),
        divider_strong= argb(0.82, 0.66, 0.44, 0.38),
        toggle_on_bg  = argb(0.96, 0.64, 0.20, 1.00),
        toggle_on_glow= argb(0.96, 0.64, 0.20, 0.30),
        pill_arrow_hi = argb(0.72, 0.50, 0.20, 1.00),
        pill_arrow_txt= argb(1.00, 0.90, 0.70, 1.00),
        row_hover     = argb(0.92, 0.64, 0.24, 0.16),
        row_active_bg = argb(0.84, 0.58, 0.22, 0.14),
    } end,
    neon = function(argb) return {
        -- Vivid neon cyan with a hint of electric blue. Kept bright/
        -- saturated (unlike the darkened presets) for max neon pop; the
        -- border bloom + bright core make it read as a lit tube.
        panel_border  = argb(0.00, 0.90, 0.95, 0.55),
        title_bg      = argb(0.02, 0.10, 0.12, 1.0),
        title_bg_lo   = argb(0.01, 0.06, 0.08, 1.0),
        accent_neutral= argb(0.00, 0.92, 0.95, 1.00),
        accent_neutral2=argb(0.30, 0.70, 1.00, 1.00),
        btn_hover     = argb(0.04, 0.26, 0.30, 0.98),
        btn_active    = argb(0.00, 0.70, 0.78, 1.00),
        btn_border    = argb(0.10, 0.60, 0.66, 0.55),
        btn_border_hi = argb(0.40, 0.95, 1.00, 0.85),
        divider       = argb(0.20, 0.66, 0.72, 0.22),
        divider_strong= argb(0.30, 0.80, 0.86, 0.40),
        toggle_on_bg  = argb(0.00, 0.80, 0.84, 1.00),
        toggle_on_glow= argb(0.00, 0.92, 0.95, 0.35),
        pill_arrow_hi = argb(0.10, 0.66, 0.72, 1.00),
        pill_arrow_txt= argb(0.80, 1.00, 1.00, 1.00),
        row_hover     = argb(0.06, 0.40, 0.44, 0.18),
        row_active_bg = argb(0.05, 0.34, 0.38, 0.16),
    } end,
}

function _SF6UI.THEME.init()
    local T = _SF6UI.THEME
    -- argb(r, g, b, a) — RED first, ALPHA last. Palette: deep near-black
    -- surfaces with a violet/purple accent, white text, soft white values.
    -- Tuned to read "premium game menu" on a bright SF6 scene.

    -- ── GLASS transparency knob ───────────────────────────────────
    -- Master control for the "glass" look. 1.00 = fully opaque (original),
    -- lower = more see-through. NOTE: d2d can't BLUR what's behind the
    -- panel, so this is tinted/translucent ("smoked acrylic"), not true
    -- frosted glass. Lower it for more transparency; raise toward 1.0 if
    -- the busy fight scene behind makes text hard to read.
    T.GLASS           = 0.40   -- panel opacity (0.40 = mostly transparent glass;
                               -- the gradient bands inherit this alpha so the
                               -- game shows through the gradient as glass)
    local g = T.GLASS

    -- Panel surfaces (r, g, b, a). Alpha scaled by the glass knob so the
    -- whole menu's transparency is controlled from one place. Title bar
    -- kept a touch more opaque (it carries the title text).
    T.panel_bg        = argb(0.05, 0.05, 0.08, g)
    -- Vertical gradient endpoints for the panel body (faked via banded
    -- fills in draw_menu_panel, since d2d has no gradient primitive). Top
    -- is slightly lighter than the base, bottom slightly darker — a subtle
    -- dark-on-dark falloff.
    T.panel_bg_top    = argb(0.16, 0.16, 0.22, g)
    T.panel_bg_bot    = argb(0.02, 0.02, 0.04, g)
    T.panel_bg_inner  = argb(0.09, 0.09, 0.13, 0.96)  -- nearly opaque so the
                              -- hotkey/legend panels fully cover the window
                              -- gradient + anything behind them (prevents the
                              -- "ghost panel" bleed-through seen at low GLASS)
    T.panel_shadow    = argb(0.00, 0.00, 0.00, 0.45 * g)
    T.panel_border    = argb(0.45, 0.40, 0.70, 0.45)   -- faint violet edge
    T.panel_highlight = argb(1.00, 1.00, 1.00, 0.10)   -- top "light catch"
    -- Title bar (gradient faked in draw via 3 stops; these are the ends).
    -- Slightly more opaque than the body for title-text legibility.
    T.title_bg        = argb(0.16, 0.12, 0.28, math.min(1.0, g + 0.10))
    T.title_bg_lo     = argb(0.10, 0.08, 0.18, math.min(1.0, g + 0.10))
    T.title_text      = argb(0.98, 0.98, 1.00, 1.00)
    -- Accent strips
    T.accent_p1       = C_NAME_P1
    T.accent_p2       = C_NAME_P2
    T.accent_neutral  = argb(0.55, 0.42, 0.95, 1.00)   -- violet
    T.accent_neutral2 = argb(0.40, 0.62, 0.98, 1.00)   -- blue (for gradient strip)
    T.accent_warn     = argb(0.98, 0.70, 0.22, 1.00)
    T.accent_ok       = argb(0.40, 0.85, 0.50, 1.00)
    T.accent_bad      = argb(0.95, 0.36, 0.36, 1.00)
    -- Text
    T.text_primary    = argb(0.96, 0.96, 0.99, 1.00)
    T.text_secondary  = argb(0.72, 0.72, 0.82, 1.00)
    T.text_muted      = argb(0.50, 0.50, 0.60, 1.00)
    T.text_label      = argb(0.92, 0.92, 0.97, 1.00)   -- bright label
    T.text_value      = argb(0.97, 0.97, 1.00, 1.00)   -- white value (mockup style)
    -- Buttons
    T.btn_idle        = argb(0.13, 0.13, 0.19, 0.96)
    T.btn_hover       = argb(0.24, 0.20, 0.40, 0.98)
    T.btn_active      = argb(0.52, 0.38, 0.92, 1.00)   -- violet (Save button)
    T.btn_border      = argb(0.42, 0.40, 0.62, 0.50)
    T.btn_border_hi   = argb(0.68, 0.58, 0.98, 0.80)
    T.btn_text        = argb(0.98, 0.98, 1.00, 1.00)
    T.btn_text_dim    = argb(0.72, 0.72, 0.80, 1.00)
    -- Dividers
    T.divider         = argb(0.55, 0.50, 0.75, 0.20)
    T.divider_strong  = argb(0.60, 0.54, 0.82, 0.38)
    -- Layout tokens (UNCHANGED — geometry stays put)
    T.PAD             = 12
    T.PAD_TIGHT       = 6
    T.ROW_H           = 28
    T.BTN_H           = 26
    T.TITLE_H         = 28
    T.ACCENT_H        = 3
    T.SHADOW_OFFSET   = 3
    T.CHAMFER         = 6   -- (legacy, unused now that real rounded rects exist)
    T.RADIUS          = 10  -- real corner radius for fill_rounded_rect
    -- Control tokens
    T.toggle_off_bg   = argb(0.16, 0.16, 0.22, 0.90)   -- track, off
    T.toggle_on_bg    = argb(0.55, 0.40, 0.95, 1.00)   -- track, on (violet)
    T.toggle_on_glow  = argb(0.55, 0.40, 0.95, 0.30)   -- glow halo behind on-track
    T.toggle_knob     = argb(0.99, 0.99, 1.00, 1.00)   -- white knob (on)
    T.toggle_knob_off = argb(0.60, 0.60, 0.70, 1.00)   -- gray knob (off)
    T.pill_arrow_bg   = argb(0.18, 0.16, 0.28, 0.92)   -- ‹ › chip idle
    T.pill_arrow_hi   = argb(0.40, 0.30, 0.70, 1.00)   -- ‹ › chip hovered
    T.pill_arrow_txt  = argb(0.80, 0.74, 1.00, 1.00)   -- arrow glyph (violet-white)
    T.pill_value_bg   = argb(0.11, 0.10, 0.17, 0.94)   -- value chip bg
    T.row_hover       = argb(0.45, 0.35, 0.80, 0.16)   -- subtle violet wash
    T.row_active_bg   = argb(0.40, 0.32, 0.70, 0.14)   -- tint behind an ON row

    -- ── Apply selected accent preset ──────────────────────────────
    -- Overrides the violet defaults above with the chosen palette. Done
    -- last so the preset wins. Falls back to "violet" for an unknown key.
    local key  = cfg.accent_preset or "violet"
    local make = T.ACCENTS[key] or T.ACCENTS.violet
    local p    = make(argb)
    for k, v in pairs(p) do T[k] = v end
    -- Presets give title_bg/_lo at full alpha; reapply the glass knob so
    -- title transparency stays consistent with the rest of the menu.
    local ga = math.min(1.0, g + 0.10)
    if p.title_bg then
        T.title_bg = (p.title_bg & 0x00FFFFFF) | (math.floor(ga * 255) << 24)
    end
    if p.title_bg_lo then
        T.title_bg_lo = (p.title_bg_lo & 0x00FFFFFF) | (math.floor(ga * 255) << 24)
    end
end

-- panel(x,y,w,h, accent|nil): shadow -> body -> accent strip -> sheen -> border
function _SF6UI.UI.panel(x, y, w, h, accent)
    local T = _SF6UI.THEME
    local SH = T.SHADOW_OFFSET
    d2d.fill_rect(x + SH, y + SH, w, h, T.panel_shadow)
    d2d.fill_rect(x, y, w, h, T.panel_bg)
    if accent then d2d.fill_rect(x, y, w, T.ACCENT_H, accent) end
    local hy = y + (accent and T.ACCENT_H or 0)
    d2d.fill_rect(x, hy, w, 1, T.panel_highlight)
    d2d.outline_rect(x, y, w, h, 1, T.panel_border)
end

-- chamfer_body(x,y,w,h, col): opaque body rect with beveled (stepped)
-- corners. d2d can't cut to transparent over the game scene, so the bevel
-- is built from horizontal strips: the top CHAMFER rows and bottom CHAMFER
-- rows are inset by a growing amount, producing a 45° stepped corner.
-- Cost: 1 center rect + 2*CHAMFER thin strips (CHAMFER is small, ~6).
function _SF6UI.UI.chamfer_body(x, y, w, h, col)
    local c = _SF6UI.THEME.CHAMFER
    if c < 1 then d2d.fill_rect(x, y, w, h, col); return end
    -- Center block (full width), spanning everything except the top/bottom
    -- chamfer bands.
    d2d.fill_rect(x, y + c, w, h - 2 * c, col)
    -- Top + bottom bands: each row i (0..c-1) is inset by (c - i) on both
    -- sides, so the corner steps inward toward the top/bottom edge.
    for i = 0, c - 1 do
        local inset = c - i
        -- top band row
        d2d.fill_rect(x + inset, y + i, w - 2 * inset, 1, col)
        -- bottom band row
        d2d.fill_rect(x + inset, y + h - 1 - i, w - 2 * inset, 1, col)
    end
end

-- chamfer_border(x,y,w,h, thick, col): 1px-ish border following the same
-- chamfered outline. Drawn as 4 straight edges (inset by chamfer at their
-- ends) plus 4 short diagonal step runs at the corners.
function _SF6UI.UI.chamfer_border(x, y, w, h, thick, col)
    local c = _SF6UI.THEME.CHAMFER
    thick = thick or 1
    if c < 1 then d2d.outline_rect(x, y, w, h, thick, col); return end
    -- Straight edges (shortened by chamfer at both ends)
    d2d.fill_rect(x + c, y, w - 2 * c, thick, col)                 -- top
    d2d.fill_rect(x + c, y + h - thick, w - 2 * c, thick, col)     -- bottom
    d2d.fill_rect(x, y + c, thick, h - 2 * c, col)                 -- left
    d2d.fill_rect(x + w - thick, y + c, thick, h - 2 * c, col)     -- right
    -- Corner step runs (one short rect per step, 45°)
    for i = 0, c - 1 do
        local d = c - i
        -- top-left
        d2d.fill_rect(x + d - 1, y + i, thick, thick, col)
        -- top-right
        d2d.fill_rect(x + w - d, y + i, thick, thick, col)
        -- bottom-left
        d2d.fill_rect(x + d - 1, y + h - 1 - i, thick, thick, col)
        -- bottom-right
        d2d.fill_rect(x + w - d, y + h - 1 - i, thick, thick, col)
    end
end

-- anim_step(key, open): advance the slide progress for menu `key` toward 1
-- when `open` is true, toward 0 otherwise. Fixed per-frame step (~6 frames
-- to fully open at 60fps). Returns the new progress (0..1). Clamped, so it
-- self-corrects regardless of frame rate. Zero per-frame state beyond the
-- _SF6UI.anim table.
function _SF6UI.UI.anim_step(key, open, step)
    local a = _SF6UI.anim
    local p = a[key] or 0
    local STEP = step or 0.16   -- default ~6 frames; callers may pass a
                                -- smaller value for a longer (slower) ramp
                                -- without affecting other menus' timing.
    if open then
        p = p + STEP; if p > 1 then p = 1 end
    else
        p = p - STEP; if p < 0 then p = 0 end
    end
    a[key] = p
    return p
end

-- Time-based companion to anim_step: advances progress by ELAPSED WALL-CLOCK
-- time instead of a fixed per-frame step, so the animation runs at a constant
-- real-world speed and stays smooth regardless of framerate (frame-based
-- stepping stutters when frame time varies). `dur` is the open/close duration
-- in seconds. State (progress + last timestamp) is kept per key in
-- _SF6UI.anim under key.."_t".
function _SF6UI.UI.anim_time(key, open, dur)
    local a = _SF6UI.anim
    local pk, tk = key, key .. "__last"
    local now = os.clock()
    local p    = a[pk] or 0
    local last = a[tk] or now
    local dt   = now - last
    -- Guard against huge dt (first frame, alt-tab, hitches) so the anim
    -- doesn't jump — clamp a single step to at most ~1/15s of progress.
    if dt < 0 then dt = 0 end
    if dt > 0.066 then dt = 0.066 end
    local rate = (dur and dur > 0) and (1 / dur) or 6
    if open then
        p = p + dt * rate; if p > 1 then p = 1 end
    else
        p = p - dt * rate; if p < 0 then p = 0 end
    end
    a[pk] = p
    a[tk] = now
    return p
end

-- ease_out(t): cubic ease-out for 0..1 → 0..1. Makes the slide decelerate
-- into place instead of moving linearly (feels less mechanical).
function _SF6UI.UI.ease_out(t)
    local inv = 1 - t
    return 1 - inv * inv * inv
end

-- ease_back_out(t, s): ease-out with overshoot ("back" easing). Returns a
-- value that briefly exceeds 1.0 near the end then settles to exactly 1.0
-- at t=1, producing a zoom-in-then-bounce feel. `s` controls overshoot
-- amount (higher = bigger bounce); ~1.70158 is the classic value, we use a
-- slightly punchier default. Standard formula:
--   f(t) = 1 + (s+1)*(t-1)^3 + s*(t-1)^2
function _SF6UI.UI.ease_back_out(t, s)
    s = s or 1.9            -- overshoot strength (bounce intensity knob)
    local p = t - 1
    return 1 + (s + 1) * p * p * p + s * p * p
end

-- brighten(argb_color, amount): lighten an ARGB color by `amount` (0..255)
-- per RGB channel, CLAMPED so channels can't overflow into adjacent bytes
-- (a naive `color + 0x202020` corrupts the color when any channel > 0xFF).
-- Alpha is preserved.
function _SF6UI.UI.brighten(c, amt)
    local a = math.floor(c / 0x1000000) % 0x100
    local r = math.floor(c / 0x10000)   % 0x100
    local g = math.floor(c / 0x100)     % 0x100
    local b = c % 0x100
    r = math.min(255, r + amt)
    g = math.min(255, g + amt)
    b = math.min(255, b + amt)
    return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

-- lightning(x1,y1,x2,y2, opts): draws a jagged electric bolt from (x1,y1) to
-- (x2,y2), composed entirely from d2d.line. d2d has no blur/gradient/glow, so
-- the glow is faked by stacking several translucent wide passes of the same
-- jagged path with a bright near-white thin core on top. The path is built by
-- midpoint displacement for a natural crackle, and a few short child bolts
-- branch off it. Seeded from a time bucket so the bolt is stable within a
-- frame but re-crackles over time (fps-independent flicker).
function _SF6UI.UI.lightning(x1, y1, x2, y2, opts)
    opts = opts or {}
    local color    = opts.color     or 0xFFEAF6FF
    local glow     = opts.glow      or 0xFF40B8FF
    local core_w   = opts.core_w    or 3
    local chaos    = opts.chaos     or 0.42
    local levels   = opts.levels    or 5
    local branches = opts.branches  or 3
    local speed    = opts.speed     or 14
    local seedx    = opts.seed      or 0
    local inten    = opts.intensity or 1
    local phase_off= opts.phase_off or 0
    if inten <= 0 then return end

    -- FLOWING motion: instead of snapping to a new random shape each tick,
    -- the bolt morphs continuously. We compute the jagged displacement using
    -- a seeded value-noise function sampled at a smoothly advancing time `t`;
    -- consecutive frames differ only slightly, so the bolt appears to flow.
    -- phase_off shifts where in the noise this bolt samples, so layered bolts
    -- on the same edge flow independently instead of overlapping identically.
    local t = os.clock() * speed + phase_off

    -- Deterministic hash → 0..1 for a given integer key (per-vertex offsets).
    local function hash(k)
        local s = (k * 374761393 + seedx * 668265263 + 2654435761) % 2147483647
        s = (s * 1103515245 + 12345) % 2147483648
        return s / 2147483648
    end
    -- Smooth value noise in 1-D: interpolate between integer-keyed hashes with
    -- a smoothstep so the result glides (no hard jumps) as `phase` advances.
    local function noise(key, phase)
        local i = math.floor(phase)
        local f = phase - i
        f = f * f * (3 - 2*f)               -- smoothstep ease
        local a = hash(key * 32 + i)
        local b = hash(key * 32 + i + 1)
        return (a + (b - a) * f) * 2 - 1     -- -1..1
    end

    local glow_rgb = glow  % 0x1000000
    local core_rgb = color % 0x1000000

    -- Build the jagged polyline. Each midpoint's perpendicular offset is
    -- driven by smooth noise keyed to that vertex, so the whole shape morphs
    -- fluidly over time rather than re-randomizing.
    local vkey = 0
    local function build(ax, ay, bx, by, lvl, amp, phase)
        local pts = { {ax, ay}, {bx, by} }
        for _ = 1, lvl do
            local np = {}
            for i = 1, #pts - 1 do
                local p, q = pts[i], pts[i+1]
                np[#np+1] = p
                local mx2, my2 = (p[1]+q[1])/2, (p[2]+q[2])/2
                local dx, dy = q[1]-p[1], q[2]-p[2]
                local len = math.sqrt(dx*dx + dy*dy) + 0.0001
                local nx, ny = -dy/len, dx/len
                vkey = vkey + 1
                local off = noise(vkey, phase) * amp
                np[#np+1] = { mx2 + nx*off, my2 + ny*off }
            end
            np[#np+1] = pts[#pts]
            pts = np
            amp = amp * 0.5
        end
        return pts
    end

    -- Soft, gently-pulsing brightness (no harsh flicker) so it reads as a
    -- steady flowing current rather than a strobe.
    local flick = 0.78 + 0.22 * (math.sin(os.clock() * 6.0 + seedx) * 0.5 + 0.5)

    local function stroke(pts, scale, flick)
        local function A(c, f) return (math.floor(0xFF * f * inten * flick) * 0x1000000) + c end
        local passes = {
            { core_w*4*scale, 0.10 },
            { core_w*3*scale, 0.16 },
            { core_w*2*scale, 0.28 },
        }
        for _, pp in ipairs(passes) do
            local w   = math.max(1, math.floor(pp[1]))
            local col = A(glow_rgb, pp[2])
            for i = 1, #pts - 1 do
                d2d.line(pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2], w, col)
            end
        end
        local cw   = math.max(1, math.floor(core_w*scale))
        local ccol = (math.floor(0xFF * inten) * 0x1000000) + core_rgb
        for i = 1, #pts - 1 do
            d2d.line(pts[i][1], pts[i][2], pts[i+1][1], pts[i+1][2], cw, ccol)
        end
    end

    local seg_len = math.sqrt((x2-x1)^2 + (y2-y1)^2)
    local main    = build(x1, y1, x2, y2, levels, seg_len * chaos, t)
    stroke(main, 1.0, flick)

    -- Branches drift smoothly too: their attach point and endpoint are driven
    -- by slow smooth noise (phase t*0.5) so they sway with the main bolt
    -- instead of snapping to new random spots.
    for bi = 1, branches do
        local frac = 0.2 + 0.6 * ((hash(900 + bi) ))      -- stable along the path
        local idx  = 1 + math.floor(frac * (#main - 2))
        local sp   = main[idx]
        local ep   = main[math.min(#main, idx + math.floor(#main/4) + 1)]
        local bx   = ep[1] + noise(700 + bi, t*0.5) * seg_len * 0.22
        local by   = ep[2] + noise(800 + bi, t*0.5) * seg_len * 0.22
        local child = build(sp[1], sp[2], bx, by, levels-1, seg_len * chaos * 0.6, t)
        stroke(child, 0.6, flick * 0.8)
    end
end

-- arcade_button(cx, cy, r, fill, hovered, [gloss_scale]): draws a convex
-- Sanwa-style arcade button as layered circles + an oval gloss + a specular
-- dot. gloss_scale (default 1.0) scales the gloss + specular alpha down —
-- pass a lower value (e.g. 0.4) for buttons with a white icon on top, so the
-- highlight doesn't wash the icon out. Layers:
--   1. drop shadow  2. dark base ring  3. colored dome
--   4. rim light    5. gloss ellipse   6. specular dot
-- The caller draws the label/icon on top afterward. Pure d2d primitives.
function _SF6UI.UI.arcade_button(cx, cy, r, fill, hovered, gloss_scale)
    local UI = _SF6UI.UI
    local gs = gloss_scale or 1.0
    -- hovered may be a boolean (legacy callers) or a 0..1 float (smooth hover
    -- transitions). Coerce: true→1, false/nil→0, number passes through.
    local hv = hovered
    if hv == true then hv = 1.0 elseif not hv then hv = 0.0 end
    local dome = (hv > 0) and UI.brighten(fill, math.floor(26 * hv)) or fill
    local base = UI.darken(fill, 70)        -- dark base ring shade
    -- Radius-proportional metrics so the button looks correct at ANY size
    -- (was fixed 3px inset + (2,3) shadow, which looked disproportionate
    -- once the Combo Notes window started zoom-scaling its buttons down).
    -- At the normal radius (~22) these reproduce the original look; at the
    -- small radii hit during the zoom they shrink in proportion instead of
    -- swallowing the dome. Clamped so they never hit zero.
    local inset = math.max(2, math.floor(r * 0.145))   -- rim thickness
    local sh_x  = math.max(1, math.floor(r * 0.09))     -- shadow x offset
    local sh_y  = math.max(1, math.floor(r * 0.135))    -- shadow y offset
    -- 1. drop shadow
    d2d.fill_circle(cx + sh_x, cy + sh_y, r, 0x66000000)
    -- 2. dark base ring
    d2d.fill_circle(cx, cy, r, base)
    -- 3. colored dome (inset a touch so the base ring shows as a rim)
    d2d.fill_circle(cx, cy, r - inset, dome)
    -- 4. rim light — bright thin ring just inside the dome edge.
    -- Build a semi-transparent bright color: take brightened RGB, force
    -- alpha to ~0xCC (the brighten helper keeps the source's full alpha,
    -- so we strip it and re-apply a softer one for a subtle rim).
    local rim = _SF6UI.UI.brighten(fill, 90) % 0x1000000 + 0xCC000000
    d2d.circle(cx, cy, r - inset, 2, rim)
    -- 5. gloss ellipse — soft highlight near the TOP so it sits above the
    -- centered label rather than washing over it. Alpha scaled by gloss_scale.
    local gloss_a = math.floor(0x38 * gs)
    d2d.fill_oval(cx, cy - math.floor(r * 0.45),
        math.floor(r * 0.55), math.floor(r * 0.30),
        gloss_a * 0x1000000 + 0xFFFFFF)
    -- 6. specular dot — small bright glint, off-center upper-left (near top)
    local spec_a = math.floor(0xAA * gs)
    d2d.fill_oval(cx - math.floor(r * 0.32), cy - math.floor(r * 0.52),
        math.floor(r * 0.18), math.floor(r * 0.11),
        spec_a * 0x1000000 + 0xFFFFFF)
end

-- darken(argb_color, amt): inverse of brighten — clamped at 0.
function _SF6UI.UI.darken(c, amt)
    local a = math.floor(c / 0x1000000) % 0x100
    local r = math.floor(c / 0x10000)   % 0x100
    local g = math.floor(c / 0x100)     % 0x100
    local b = c % 0x100
    r = math.max(0, r - amt)
    g = math.max(0, g - amt)
    b = math.max(0, b - amt)
    return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end


-- panel_with_title(...): like panel() + a title bar; returns content-start Y
function _SF6UI.UI.panel_with_title(x, y, w, h, title, font, accent)
    local T = _SF6UI.THEME
    _SF6UI.UI.panel(x, y, w, h, accent)
    local ty = y + (accent and T.ACCENT_H or 0)
    d2d.fill_rect(x, ty, w, T.TITLE_H, T.title_bg)
    if font and title then
        local _, th = font:measure(title)
        d2d.text(font, title, x + T.PAD, ty + (T.TITLE_H - th) / 2, T.title_text)
    end
    d2d.fill_rect(x, ty + T.TITLE_H, w, 1, T.divider)
    return ty + T.TITLE_H + 1
end

-- button(...): stateless. state = { active=bool, disabled=bool }. returns hovered,clicked
function _SF6UI.UI.button(x, y, w, h, label, font, state)
    local T = _SF6UI.THEME
    state = state or {}
    local hovered = (not state.disabled) and hit_rect(x, y, w, h)
    local clicked = (not state.disabled) and click_in(x, y, w, h)
    local bg, border, text_col
    if state.disabled then
        bg, border, text_col = T.btn_idle, T.btn_border, T.text_muted
    elseif state.active then
        bg, border, text_col = T.btn_active, T.btn_border_hi, T.btn_text
    elseif hovered then
        bg, border, text_col = T.btn_hover, T.btn_border_hi, T.btn_text
    else
        bg, border, text_col = T.btn_idle, T.btn_border, T.btn_text_dim
    end
    d2d.fill_rect(x + 1, y + 1, w, h, T.panel_shadow)
    d2d.fill_rect(x, y, w, h, bg)
    if hovered or state.active then d2d.fill_rect(x, y, w, 1, T.btn_border_hi) end
    d2d.outline_rect(x, y, w, h, 1, border)
    if font and label and label ~= "" then
        local tw, th = font:measure(label)
        d2d.text(font, label, x + (w - tw) / 2, y + (h - th) / 2, text_col)
    end
    return hovered, clicked
end

-- section_label(x,y,w,text,font): small header + hairline rule to the right
function _SF6UI.UI.section_label(x, y, w, text, font)
    local T = _SF6UI.THEME
    if font and text then
        local tw, th = font:measure(text)
        d2d.text(font, text, x, y, T.text_secondary)
        local rule_x = x + tw + 8
        local rule_w = (x + w) - rule_x
        if rule_w > 0 then d2d.fill_rect(rule_x, y + th / 2, rule_w, 1, T.divider) end
    end
end

-- divider(x,y,w,strong?)
function _SF6UI.UI.divider(x, y, w, strong)
    local T = _SF6UI.THEME
    d2d.fill_rect(x, y, w, 1, strong and T.divider_strong or T.divider)
end

-- status_dot(x,y,size,kind): kind = "ok"|"warn"|"bad"|"neutral"
function _SF6UI.UI.status_dot(x, y, size, kind)
    local T = _SF6UI.THEME
    local col = T.accent_neutral
    if     kind == "ok"   then col = T.accent_ok
    elseif kind == "warn" then col = T.accent_warn
    elseif kind == "bad"  then col = T.accent_bad end
    d2d.fill_rect(x, y, size, size, col)
    d2d.outline_rect(x, y, size, size, 1, T.panel_border)
end

-- kv_row(x,y,w,label,value,font): "Label .... Value", value right-aligned
function _SF6UI.UI.kv_row(x, y, w, label, value, font)
    local T = _SF6UI.THEME
    if not font then return end
    d2d.text(font, label or "", x, y, T.text_label)
    if value then
        local vw, _ = font:measure(value)
        d2d.text(font, value, x + w - vw, y, T.text_value)
    end
end
-- ═══════════════════════════════════════════════════════════════════════════
--  END UI THEME & HELPERS
-- ═══════════════════════════════════════════════════════════════════════════


-- Font size presets - shared by profile text AND ticker.
-- ALL sizes get preloaded at startup so switching is instant
-- (no need to Reset Scripts anymore).
local FONT_SIZES = { 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64, 72 }

-- Caches indexed by size -> d2d font object
local fonts_normal = {}   -- regular weight
local fonts_bold   = {}   -- bold weight (used for ticker + menu titles)
-- Legend font cache lives on the global table (no chunk-local cost, same
-- rationale as _SF6UI.img). Clean sans-serif (Segoe UI) bold for the
-- Combo Notes legend. Populated in the d2d init callback below.
_SF6UI.fonts_legend = _SF6UI.fonts_legend or {}

-- Small helper to find the nearest preloaded size if someone sets a
-- weird custom value in the config JSON
local function nearest_font_size(requested)
    local best = FONT_SIZES[1]
    local best_diff = math.abs(best - requested)
    for _, s in ipairs(FONT_SIZES) do
        local d = math.abs(s - requested)
        if d < best_diff then best, best_diff = s, d end
    end
    return best
end

local function get_font(size, bold)
    size = nearest_font_size(size)
    local cache = bold and fonts_bold or fonts_normal
    return cache[size]
end

-- Clean sans-serif (Segoe UI bold) for the Combo Notes legend. Snaps to
-- the nearest preloaded size, like get_font. Falls back to the bold
-- Consolas cache if Segoe UI failed to load for some reason.
local function get_legend_font(size)
    size = nearest_font_size(size)
    return _SF6UI.fonts_legend[size] or fonts_bold[size]
end

-- Largest legend font (<= base_fs) whose rendered width fits max_w. Used
-- by the aux/motion/dir buttons so labels read as large as possible while
-- still fitting inside their domes — proportional Segoe UI varies a lot in
-- width (e.g. "MW" vs "41236"), so a single fixed size can't do both.
-- Returns the font plus the size chosen. Walks FONT_SIZES downward.
local function fit_legend_font(text, max_w, base_fs)
    base_fs = nearest_font_size(base_fs)
    for i = #FONT_SIZES, 1, -1 do
        local s = FONT_SIZES[i]
        if s <= base_fs then
            local f = _SF6UI.fonts_legend[s] or fonts_bold[s]
            local w = f:measure(text)
            if w <= max_w then return f, s end
        end
    end
    -- Nothing fit; return the smallest available.
    local s = FONT_SIZES[1]
    return (_SF6UI.fonts_legend[s] or fonts_bold[s]), s
end

-- ── D2D REGISTER (init + draw) ───────────────────────────────
d2d.register(function()
    init_colors()
    -- Preload every size in both normal and bold weights
    for _, s in ipairs(FONT_SIZES) do
        fonts_normal[s] = d2d.Font.new("Consolas", s, false, false)
        fonts_bold[s]   = d2d.Font.new("Consolas", s, true,  false)
    end
    -- Legend uses a clean sans-serif (Segoe UI) at bold weight so the
    -- modifier definitions stand out and read more easily than the
    -- monospace Consolas used elsewhere. Same size table; cached here so
    -- get_legend_font() is a free lookup per frame.
    for _, s in ipairs(FONT_SIZES) do
        _SF6UI.fonts_legend[s] = d2d.Font.new("Segoe UI", s, true, false)
    end
    -- Combo ticker fonts rebuilt per-frame when scale changes (see draw callback)

    -- Button glyph icons (fist = punch, foot = kick). Loaded from
    -- <gamedir>/reframework/images/. Wrapped in pcall so a missing file
    -- can't break init — if either fails to load it stays nil and the
    -- button drawing falls back to the "P"/"K" text label.
    _SF6UI.img.fist = nil
    _SF6UI.img.foot = nil
    pcall(function() _SF6UI.img.fist = d2d.Image.new("fist.png") end)
    pcall(function() _SF6UI.img.foot = d2d.Image.new("foot.png") end)

    -- Direction/motion input glyphs for "icon" notation mode. Each PNG is
    -- titled after the lettered notation name (e.g. UF.png, QCF.png) and
    -- lives in reframework/images/. Any that fail to load stay absent and
    -- the affected button falls back to lettered text. Cached in
    -- _SF6UI.img.glyph keyed by name.
    _SF6UI.img.glyph = {}
    local GLYPH_NAMES = {
        -- 8 directions + neutral
        "U","D","F","B","UF","UB","DF","DB","N",
        -- motion names (mirror MOTION_NAMES values)
        "QCF","QCB","DP","RDP","HCF","HCB","SPD","DD","FF","BB",
        "[B]F","[D]U",
        -- raw standalone motions (literal)
        "720","360F","360B",
    }
    for _, gname in ipairs(GLYPH_NAMES) do
        pcall(function()
            _SF6UI.img.glyph[gname] = d2d.Image.new(gname .. ".png")
        end)
    end
end,

function()
    local ok = pcall(function()
        local sw, sh = d2d.surface_size()

        -- Resolve the four font roles from cfg each frame
        local font_profile    = get_font(cfg.font_size,        false)
        local font_notes      = get_font(cfg.notes_font_size,  false)
        local font_ticker     = get_font(cfg.ticker_font_size, true)
        local font_button     = get_font(cfg.button_font_size, false)
        local font_menu       = get_font(cfg.menu_font_size,   false)
        local font_menu_title = get_font(cfg.menu_font_size + 2, true)
        -- Display/Settings menu uses the same clean legend font (Segoe UI
        -- bold) as the Combo editor, for visual uniformity. disp_fs is the
        -- size the menu rows render at; row vertical-centering uses it too.
        local disp_fs         = cfg.menu_font_size + 2
        local font_disp       = get_legend_font(disp_fs)

        -- Rebuild ticker fonts whenever scale changes
        local cur_scale = cfg.ticker_scale or 1.0
        if cur_scale ~= font_ticker_last_scale then
            local SC = cur_scale
            font_ticker_name   = d2d.Font.new("Consolas", math.max(8, math.floor(14*SC)), true,  false)
            font_ticker_dir    = d2d.Font.new("Consolas", math.max(8, math.floor(15*SC)), false, false)
            font_ticker_glyph  = d2d.Font.new("Consolas", math.max(6, math.floor(9*SC)),  true,  false)
            font_ticker_cancel = d2d.Font.new("Consolas", math.max(8, math.floor(14*SC)), false, false)
            font_ticker_last_scale = cur_scale
        end

        -- Capture mouse state for this frame's UI hit tests.
        -- Confirmed working inside d2d draw via probe script.
        local mouse = imgui.get_mouse()
        frame_mouse_x = mouse.x
        frame_mouse_y = mouse.y
        frame_click_pending = imgui.is_mouse_clicked(0)

        -- ── Top button bar ───────────────────────────────
        if cfg.show_button_bar then
            local pad_x = 14
            local gap   = 22
            -- Combo Titles button removed — slot labels are edited from
            -- the web editor (index.html) now. Removing the button also
            -- frees the chunk-level locals that backed the in-game
            -- titles editor; see cn_refresh notes for why every freed
            -- local matters near the 200-cap.
            local labels = { "Display", "Combo Editor" }

            local widths = {}
            local total_w = 0
            for i, label in ipairs(labels) do
                local tw, _ = font_button:measure(label)
                widths[i] = tw + pad_x * 2
                total_w = total_w + widths[i]
                if i > 1 then total_w = total_w + gap end
            end

            local h = cfg.button_font_size + 12
            local x = math.floor((sw - total_w) / 2)
            local y = math.max(2, math.floor(sh * HUD.bar_y_ratio) - h - 6)

            btn_y = y; btn_h = h

            local is_open = {
                show_display_win, show_combo_notes_win,
            }

            for i, label in ipairs(labels) do
                local w = widths[i]
                btn_x[i] = x
                btn_w[i] = w

                -- ── Pill tab with accent glow ─────────────────────
                -- Pill-shaped (radius = half height) with a soft glow halo
                -- around it in the active menu-accent color (the same color
                -- the Display "Menu Accent" cycler sets). The glow is built
                -- from a few expanding rounded rects of decreasing alpha;
                -- it's brighter when the tab is open or hovered.
                local hovered = hit_rect(x, y, w, h)
                local active  = is_open[i]
                local pr      = math.floor(h / 2)
                local acc     = _SF6UI.THEME.accent_neutral
                -- Strip alpha from the accent so we can layer our own.
                local acc_rgb = acc % 0x1000000
                -- Glow intensity: strong when active, medium on hover, faint idle.
                local g_base  = active and 0x70 or (hovered and 0x44 or 0x22)
                -- 3-ring halo: outermost faintest. Each ring is a larger
                -- rounded rect drawn before the body (so the body covers the
                -- inner part, leaving a gradient rim).
                for ring = 3, 1, -1 do
                    local grow  = ring * 3
                    local alpha = math.floor(g_base / ring)   -- falls off outward
                    local gcol  = (alpha * 0x1000000) + acc_rgb
                    d2d.fill_rounded_rect(
                        x - grow, y - grow, w + grow*2, h + grow*2,
                        pr + grow, pr + grow, gcol)
                end

                -- Pill body: darker base, accent-tinted when active.
                local body = active
                    and ((0xE6 * 0x1000000) + acc_rgb)        -- accent fill when open
                    or  (hovered and 0xE61E1E2A or 0xCC14141C)
                d2d.fill_rounded_rect(x, y, w, h, pr, pr, body)
                -- Crisp accent border
                d2d.rounded_rect(x, y, w, h, pr, pr, 1,
                    (0xFF * 0x1000000) + acc_rgb)

                -- Label, centered.
                local tw, th = font_button:measure(label)
                d2d.text(font_button, label,
                    x + (w - tw)/2, y + (h - th)/2,
                    active and 0xFFFFFFFF or 0xFFE0E0E0)

                local clicked = click_in(x, y, w, h)

                if clicked then
                    -- Opening either top-level tab closes the Combo Notes
                    -- sub-window so panels never overlap.
                    if i == 1 then
                        show_combo_notes_win = false
                        show_display_win = not show_display_win
                        show_settings_win = false; show_profiles_win = false
                    else
                        -- "Combo Editor" now opens the Combo Notes window
                        -- directly (the intermediate picker pop-up was
                        -- removed; the character picker lives inside the
                        -- Combo Notes window now). Toggle it.
                        local opening = not show_combo_notes_win
                        show_combo_notes_win = opening
                        combo_notes_open_guard = opening
                        show_settings_win = false
                        show_display_win  = false
                        show_profiles_win = false
                    end
                end

                x = x + w + gap
            end
        end

        -- ── Game overlay (ticks + profiles + ticker) ─────
        if cfg.show_overlay then
            -- ── COMBO TICKER BARS ─────────────────────────────
            -- Reads active slots from combo_slots for the detected P1 character.
            -- Falls back to cfg.ticker_text if no character detected or no combos.
            if cfg.show_ticker then
                -- If user has manually picked a char in the editor menu,
                -- honor that selection for the combo ticker too. Otherwise
                -- fall back to the auto-detected P1 character.
                -- Override clears automatically when game P1 changes char
                -- (see uBattleCore update hook ~line 1289).
                local p1_name
                if profile_user_override and ROSTER[edit_char_idx] then
                    p1_name = ROSTER[edit_char_idx]
                else
                    p1_name = players[1] and players[1].name or "?"
                end
                local show_combo_bars = false

                if p1_name ~= "?" and font_ticker_name then
                    local combos = combo_slots[p1_name:lower()]
                    if combos then
                        -- Collect active slots in order
                        local active = {}
                        for i = 1, COMBO_MAX_SLOTS do
                            if combos[i] and combos[i].active
                               and #combos[i].tokens > 0 then
                                active[#active+1] = combos[i]
                                if #active >= COMBO_MAX_ACTIVE then break end
                            end
                        end

                        if #active > 0 then
                            show_combo_bars = true

                            -- Layout constants — all scaled by cfg.ticker_scale
                            local SC        = cfg.ticker_scale or 1.0
                            local TICKER_H    = math.floor(28  * SC)
                            local TICKER_GAP  = math.floor(3   * SC)
                            -- INSET: margin from each screen edge so the ticker reads
                            -- as a floating panel (with real left/right edges for the
                            -- shadow/sheen to work against) instead of a full-bleed
                            -- strip. Set to 0 to restore the original full-width bar.
                            local INSET       = math.floor(24  * SC)
                            local PAD_X       = math.floor(20  * SC)
                            -- NAME_W: width reserved for the slot title column.
                            -- Reduced from 125*SC to 90*SC — titles like
                            -- "DI RESET" / "PUNISH 2" / "ANTI-AIR" fit in <90px
                            -- at the ticker font size; the surplus was just
                            -- pushing inputs to the right and eating combo room.
                            local NAME_W      = math.floor(90  * SC)
                            -- COL_PAD: gap between name column and divider line.
                            -- Halved from 15*SC to 6*SC — the divider was floating
                            -- in dead space, far from both title and inputs.
                            local COL_PAD     = math.floor(6   * SC)
                            local GLYPH_SZ    = math.floor(18  * SC)
                            local CHUNK_PAD_X = math.floor(8   * SC)
                            local CHUNK_PAD_Y = math.floor(3   * SC)
                            -- CHUNK_GAP: space between adjacent chunks (the auto-'>'
                            -- separator sits in the middle of this gap). Tightened
                            -- from 12*SC to 8*SC since the SEP_GAP reduction also
                            -- saves space; 8 still leaves comfortable visual breathing.
                            local CHUNK_GAP   = math.floor(8   * SC)
                            local INNER_GAP   = math.floor(4   * SC)
                            -- SEP_GAP: padding on EACH side of a '>' separator.
                            -- Was 5*SC (10*SC per separator). At SC=2 with ~10 separators
                            -- in a long combo this wasted 200px. Tightened to 2*SC.
                            local SEP_GAP     = math.floor(2   * SC)
                            local BOTTOM_OFF  = math.floor(sh * (cfg.ticker_bottom_pct or 0.11))

                            -- Colors
                            local TC_BG     = 0xC80C0C0E
                            local TC_BORDER = 0x14FFFFFF
                            local TC_SHADOW = 0x50000000   -- soft ambient halo (depth)
                            local TC_TOPHI  = 0x1EFFFFFF   -- 1px top "light catch"
                            local TC_RING   = 0x3CFFFFFF   -- panel border ring (visible)
                            local TC_NAME   = 0xB2FFFFFF
                            local TC_DIR    = 0xB2FFFFFF
                            local TC_DIVIDER= 0x19FFFFFF
                            local TC_CANCEL = 0x4CFFFFFF
                            local TC_CHUNK  = 0x0AFFFFFF
                            local TC_GLYPH  = {
                                LP=0xFF1A82DC, MP=0xFFDCAA1E, HP=0xFFC83232,
                                LK=0xFF1A82DC, MK=0xFFDCAA1E, HK=0xFFC83232,
                                PP=0xFF7864DC, KK=0xFF78B478,
                                DR=0xFF1EB8C8, DRC=0xFF0E7888, MW=0xFFD4A017, Oki=0xFF8C46C8,
                                CH=0xFFE6C200, PC=0xFFE08020, SHM=0xFF3CB44A,
                            }
                            -- Map full button labels to single-letter glyph
                            -- shown inside the colored circle. Strength is
                            -- conveyed entirely by color (TC_GLYPH above), so
                            -- LP/MP/HP collapse to "P" and LK/MK/HK to "K".
                            -- Multi-button & system tokens keep their text.
                            local TC_LETTER = {
                                LP="P", MP="P", HP="P",
                                LK="K", MK="K", HK="K",
                            }

                            -- Convert flat tokens → chunk seq for rendering.
                            -- Rules:
                            --   xx        → close chunk, emit xx separator
                            --   x2        → close chunk, emit x2 marker
                            --   DR / DRC  → close chunk, emit as own standalone chunk
                            --   new dir while chunk open → close old, start new
                            --   everything else → accumulate into current chunk
                            -- DR/DRC stand alone; CH/PC/SHM are post-hit
                            -- annotations and also stand alone (they don't
                            -- belong inside a [dir+button] chunk).
                            -- SAs (Super Arts) are full moves with their own
                            -- motion baked into the move itself, so they also
                            -- emit as their own chunk and get a '>' separator.
                            local STANDALONE_BTNS = { DR=true, DRC=true,
                                                      CH=true, PC=true, SHM=true,
                                                      SA1=true, SA2=true,
                                                      ["SA2-2"]=true, SA3=true,
                                                      ["SA3-2"]=true }
                            -- Base attacks emit an xx separator after themselves
                            -- when entered without a preceding direction.
                            local BASE_ATTACKS = {
                                LP=true, MP=true, HP=true,
                                LK=true, MK=true, HK=true,
                            }
                            local function tokens_to_seq(tokens)
                                local seq   = {}
                                local chunk = nil
                                local function flush()
                                    if chunk and #chunk.parts > 0 then
                                        seq[#seq+1] = chunk
                                    end
                                    chunk = nil
                                end
                                for _, tok in ipairs(tokens) do
                                    if tok.t == "xx" or (tok.t == "btn" and tok.v == "xx") then
                                        -- Cancel marker — close current chunk, emit separator
                                        flush()
                                        seq[#seq+1] = { t="xx" }
                                    elseif tok.t == "sep" then
                                        -- Manual chunk separator (added by user via the
                                        -- editor's '>' button). Behaves like an explicit
                                        -- chain break: close any open chunk and emit a sep
                                        -- marker. The draw_seq path treats this as a forced
                                        -- '>' regardless of last_was_chunk state, so the
                                        -- separator still draws even if no prior chunk
                                        -- existed (e.g. user starts a slot with '>').
                                        flush()
                                        seq[#seq+1] = { t="sep" }
                                    elseif tok.t == "fk" then
                                        -- F.Kill — close current chunk, emit fk marker;
                                        -- next dir/btn will chain immediately after it.
                                        -- Preserve the baked counter (tok.v) so the
                                        -- renderer can display it inside the pill.
                                        flush()
                                        seq[#seq+1] = { t="fk", v=tok.v }
                                    elseif tok.t == "dir" and tok.v == "x2" then
                                        flush()
                                        seq[#seq+1] = { t="x2" }
                                    elseif tok.t == "btn" and STANDALONE_BTNS[tok.v] then
                                        -- DR/DRC never attach to a direction
                                        flush()
                                        seq[#seq+1] = { t="chunk", parts={ tok } }
                                    elseif tok.t == "dir" then
                                        -- New direction closes any open chunk first
                                        flush()
                                        chunk = { t="chunk", parts={ tok } }
                                    elseif tok.t == "btn" then
                                        -- Button attaches to current chunk (the preceding dir).
                                        -- Base attacks (LP/MP/HP/LK/MK/HK) entered alone
                                        -- flush immediately and emit an xx separator so the
                                        -- next input reads as a new move in the sequence.
                                        if not chunk and BASE_ATTACKS[tok.v] then
                                            seq[#seq+1] = { t="chunk", parts={ tok } }
                                            -- No extra token needed — the renderer auto-inserts
                                            -- '>' between consecutive chunks.
                                        else
                                            if not chunk then
                                                chunk = { t="chunk", parts={} }
                                            end
                                            chunk.parts[#chunk.parts+1] = tok
                                        end
                                    end
                                end
                                flush()
                                return seq
                            end

                            -- Measure a chunk width
                            local function measure_chunk_w(chunk)
                                local w = CHUNK_PAD_X * 2
                                local first = true
                                for _, part in ipairs(chunk.parts) do
                                    if not first then w = w + INNER_GAP end
                                    if part.t == "dir" then
                                        -- Icon mode: a dir part with a loaded
                                        -- PNG occupies a square GLYPH_SZ slot
                                        -- (matches the button glyphs and keeps
                                        -- measure/draw widths identical so wrap
                                        -- math stays correct).
                                        if notation_icon(part.v) then
                                            w = w + GLYPH_SZ
                                        else
                                            local tw = font_ticker_dir
                                                and font_ticker_dir:measure(notation(part.v)) or 0
                                            w = w + tw
                                        end
                                    elseif part.t == "btn" then
                                        -- Oki tokens may be wider than standard glyph
                                        if font_ticker_glyph and part.v:match(":Oki]$") then
                                            local tw, _ = font_ticker_glyph:measure(part.v)
                                            w = w + math.max(GLYPH_SZ, tw + 4)
                                        else
                                            w = w + GLYPH_SZ
                                        end
                                    end
                                    first = false
                                end
                                return w
                            end

                            -- Draw one button glyph
                            -- Oki: square with larger font. All others: round circle.
                            local function draw_glyph(x, y, label)
                                local lookup = label:match(":Oki]$") and "Oki" or label
                                local col = TC_GLYPH[lookup] or 0xFF787878
                                local is_oki = lookup == "Oki"
                                local gw = GLYPH_SZ
                                if font_ticker_glyph then
                                    local tw, _ = font_ticker_glyph:measure(label)
                                    gw = math.max(GLYPH_SZ, tw + 6)
                                end

                                if is_oki then
                                    -- Square glyph with larger font for Oki
                                    local oki_font = font_ticker_name  -- bold, bigger
                                    if oki_font then
                                        local tw2, _ = oki_font:measure(label)
                                        gw = math.max(gw, tw2 + 6)
                                    end
                                    d2d.fill_rect(x+1, y+1, gw, GLYPH_SZ, 0x55000000)
                                    d2d.fill_rect(x, y, gw, GLYPH_SZ, col)
                                    d2d.fill_rect(x+1, y, gw-2, 1, 0x33FFFFFF)
                                    d2d.outline_rect(x, y, gw, GLYPH_SZ, 1, 0x55FFFFFF)
                                    if oki_font then
                                        local tw2, th2 = oki_font:measure(label)
                                        d2d.text(oki_font, label,
                                            x+(gw-tw2)/2, y+(GLYPH_SZ-th2)/2, 0xFFFFFFFF)
                                    end
                                else
                                    -- Round circle glyph for all other buttons
                                    local r  = math.floor(GLYPH_SZ / 2)
                                    local cx = x + gw / 2
                                    local cy = y + r
                                    for dy = -r, r do
                                        local hw = math.floor(math.sqrt(math.max(0, r*r - dy*dy)) + 0.5)
                                        if hw > 0 then
                                            d2d.fill_rect(cx-hw+1, cy+dy+1, hw*2, 1, 0x55000000)
                                        end
                                    end
                                    for dy = -r, r do
                                        local hw = math.floor(math.sqrt(math.max(0, r*r - dy*dy)) + 0.5)
                                        if hw > 0 then
                                            d2d.fill_rect(cx-hw, cy+dy, hw*2, 1, col)
                                        end
                                    end
                                    local hr = math.floor(r * 0.5)
                                    for dy = -hr, hr do
                                        local hw = math.floor(math.sqrt(math.max(0, hr*hr - dy*dy)) + 0.5)
                                        if hw > 0 then
                                            d2d.fill_rect(cx-hw, cy-math.floor(r*0.3)+dy, hw*2, 1, 0x22FFFFFF)
                                        end
                                    end
                                    if font_ticker_glyph then
                                        -- Punch/kick buttons show the fist/foot
                                        -- PNG icon (matching the editor), falling
                                        -- back to the "P"/"K" letter when the
                                        -- image isn't loaded. Everything else
                                        -- draws its text label.
                                        local PUNCH = {LP=true,MP=true,HP=true}
                                        local KICK  = {LK=true,MK=true,HK=true}
                                        local icon = (PUNCH[label] and _SF6UI.img.fist)
                                                  or (KICK[label]  and _SF6UI.img.foot)
                                                  or nil
                                        if icon then
                                            local isz = math.floor(GLYPH_SZ * 0.82)
                                            d2d.image(icon, cx - isz/2, cy - isz/2, isz, isz)
                                        else
                                            -- Show "P"/"K" for punches/kicks; full label otherwise
                                            local display = TC_LETTER[label] or label
                                            local tw, th = font_ticker_glyph:measure(display)
                                            d2d.text(font_ticker_glyph, display,
                                                cx-tw/2, cy-th/2, 0xFFFFFFFF)
                                        end
                                    end
                                end
                                return gw
                            end

                            -- Draw input sequence across ticker bar.
                            -- Wraps onto additional lines when content would
                            -- overflow `max_w`, instead of breaking. The
                            -- pre-pass `measure_seq_lines` returns line count
                            -- so the bar background can be drawn at the right
                            -- height before this is called.
                            --
                            -- The two passes share width logic by checking
                            -- `draw_mode`: when false, no d2d calls are made
                            -- and only the cursor advances. This guarantees
                            -- measure and draw agree on every wrap break.
                            local TC_SEP = 0x55FFFFFF  -- dim white separator
                            local function walk_seq(x, y0, max_w, h, seq, draw_mode)
                                local cur     = x
                                local end_x   = x + max_w
                                local line    = 0
                                local y       = y0
                                local last_was_chunk = false

                                -- Helper: try to wrap to next line if `need` px
                                -- of space won't fit on current line. Resets
                                -- last_was_chunk so the next chunk doesn't draw
                                -- a leading '>' on the new line (that '>' would
                                -- have meant "continues from previous chunk on
                                -- the same line" — confusing across lines).
                                local function maybe_wrap(need)
                                    if cur + need > end_x and cur > x then
                                        line = line + 1
                                        y = y0 + line * h
                                        cur = x
                                        last_was_chunk = false
                                    end
                                end

                                for _, tok in ipairs(seq) do
                                    -- Pre-compute width this iteration WILL consume.
                                    -- Includes any leading auto-'>' that fires for chunks.
                                    if tok.t == "chunk" then
                                        local cw = measure_chunk_w(tok)
                                        local sep_w = 0
                                        if last_was_chunk and font_ticker_cancel then
                                            local sw2, _ = font_ticker_cancel:measure(">")
                                            sep_w = sw2 + SEP_GAP*2
                                        end
                                        maybe_wrap(sep_w + cw)

                                        -- Draw leading auto-'>' if room (suppressed
                                        -- when wrap reset last_was_chunk).
                                        if last_was_chunk and font_ticker_cancel then
                                            local sw2, sh2 = font_ticker_cancel:measure(">")
                                            if draw_mode then
                                                d2d.text(font_ticker_cancel, ">",
                                                    cur + SEP_GAP, y+(h-sh2)/2, TC_SEP)
                                            end
                                            cur = cur + sw2 + SEP_GAP*2
                                        end

                                        local pill_h = GLYPH_SZ + CHUNK_PAD_Y*2
                                        local pill_y = y + (h - pill_h)/2
                                        if draw_mode then
                                            d2d.fill_rect(cur, pill_y, cw, pill_h, TC_CHUNK)
                                            local cx = cur + CHUNK_PAD_X
                                            local first = true
                                            for _, part in ipairs(tok.parts) do
                                                if not first then cx = cx + INNER_GAP end
                                                if part.t == "dir" and font_ticker_dir then
                                                    local dicon = notation_icon(part.v)
                                                    if dicon then
                                                        d2d.image(dicon, cx, y+(h-GLYPH_SZ)/2, GLYPH_SZ, GLYPH_SZ)
                                                        cx = cx + GLYPH_SZ
                                                    else
                                                        local dir_label = notation(part.v)
                                                        local tw, th = font_ticker_dir:measure(dir_label)
                                                        d2d.text(font_ticker_dir, dir_label,
                                                            cx, y+(h-th)/2, TC_DIR)
                                                        cx = cx + tw
                                                    end
                                                elseif part.t == "btn" then
                                                    local gw = draw_glyph(cx, y+(h-GLYPH_SZ)/2, part.v)
                                                    cx = cx + (gw or GLYPH_SZ)
                                                end
                                                first = false
                                            end
                                        end
                                        cur = cur + cw + CHUNK_GAP
                                        last_was_chunk = true

                                    elseif tok.t == "xx" and font_ticker_cancel then
                                        local tw, th = font_ticker_cancel:measure("xx")
                                        local XX_GAP = math.floor(2 * SC)
                                        -- xx wants to sit flush against prior chunk.
                                        -- Only pull back if no wrap happens — wrapping
                                        -- means we're at line start, no chunk to hug.
                                        local pull = (last_was_chunk and cur > x) and (CHUNK_GAP - XX_GAP) or 0
                                        maybe_wrap(tw - pull)
                                        if last_was_chunk and cur > x then cur = cur - CHUNK_GAP + XX_GAP end
                                        if draw_mode then
                                            d2d.text(font_ticker_cancel, "xx",
                                                cur, y+(h-th)/2, TC_CANCEL)
                                        end
                                        cur = cur + tw + XX_GAP
                                        last_was_chunk = false

                                    elseif tok.t == "sep" and font_ticker_cancel then
                                        local sw2, sh2 = font_ticker_cancel:measure(">")
                                        maybe_wrap(sw2 + SEP_GAP*2)
                                        if draw_mode then
                                            d2d.text(font_ticker_cancel, ">",
                                                cur + SEP_GAP, y+(h-sh2)/2, TC_SEP)
                                        end
                                        cur = cur + sw2 + SEP_GAP*2
                                        last_was_chunk = false

                                    elseif tok.t == "fk" and font_ticker_cancel then
                                        local label = (tok.v and #tok.v > 0)
                                            and ("F.Kill " .. tok.v)
                                            or  "F.Kill"
                                        local tw, th = font_ticker_cancel:measure(label)
                                        local pill_w = tw + 8
                                        maybe_wrap(pill_w)
                                        local pill_h = th + 4
                                        local pill_y = y + (h - pill_h)/2
                                        if draw_mode then
                                            d2d.fill_rect(cur, pill_y, pill_w, pill_h, 0x668B1A1A)
                                            d2d.outline_rect(cur, pill_y, pill_w, pill_h, 1, 0xFFFF6666)
                                            d2d.text(font_ticker_cancel, label,
                                                cur+4, y+(h-th)/2, 0xFFFF9999)
                                        end
                                        cur = cur + pill_w + CHUNK_GAP
                                        last_was_chunk = false

                                    elseif tok.t == "x2" and font_ticker_cancel then
                                        local label = "x2"
                                        local tw, th = font_ticker_cancel:measure(label)
                                        local pill_w = tw + 8
                                        local X2_GAP = math.floor(2 * SC)
                                        local pull = (last_was_chunk and cur > x) and (CHUNK_GAP - X2_GAP) or 0
                                        maybe_wrap(pill_w - pull)
                                        if last_was_chunk and cur > x then cur = cur - CHUNK_GAP + X2_GAP end
                                        local pill_h = th + 4
                                        local pill_y = y + (h - pill_h)/2
                                        if draw_mode then
                                            d2d.fill_rect(cur, pill_y, pill_w, pill_h, 0x443A2048)
                                            d2d.outline_rect(cur, pill_y, pill_w, pill_h, 1, 0xFF8855BB)
                                            d2d.text(font_ticker_cancel, label,
                                                cur+4, y+(h-th)/2, 0xFFCC88FF)
                                        end
                                        cur = cur + pill_w + X2_GAP
                                        last_was_chunk = false
                                    end
                                end
                                return line + 1  -- total line count (1-indexed)
                            end
                            local function measure_seq_lines(x, max_w, h, seq)
                                return walk_seq(x, 0, max_w, h, seq, false)
                            end
                            local function draw_seq(x, y, max_w, h, seq)
                                walk_seq(x, y, max_w, h, seq, true)
                            end

                            -- Title formatter — shared across both orientations.
                            -- Hoisted outside the orientation if/else so the
                            -- vertical block can use it too. (When local'd
                            -- inside the horizontal branch it became nil in
                            -- the vertical branch, crashing the render.)
                            local title_for = function(slot, i)
                                return ((slot.title and slot.title ~= "") and slot.title or ("Slot " .. i)):upper() .. ":"
                            end

                            if (cfg.ticker_orientation or "horizontal") == "horizontal" then
                            -- ══════════════════════════════════════════════
                            -- HORIZONTAL LAYOUT (default — full-width bars)
                            -- ══════════════════════════════════════════════
                            -- ── Dynamic name column ────────────────────
                            -- Measure each active slot's title (with the
                            -- ':' suffix appended) and take the max width.
                            -- That becomes the title column width — saves
                            -- horizontal space for slots with short titles
                            -- (no over-reservation), while ensuring the
                            -- divider stays aligned across all slots.
                            -- Floor of 40*SC keeps a sane minimum when all
                            -- titles are very short. Cap at 40% of the bar
                            -- so an unusually long title can't crowd inputs
                            -- entirely off-screen.
                            local NAME_PAD = math.floor(8 * SC)  -- gap title→divider
                            local dynamic_name_w = math.floor(40 * SC)
                            if font_ticker_name then
                                for i, slot in ipairs(active) do
                                    local tw, _ = font_ticker_name:measure(title_for(slot, i))
                                    if tw > dynamic_name_w then dynamic_name_w = tw end
                                end
                            end
                            do
                                local cap = math.floor(sw * 0.40) - PAD_X*2
                                if dynamic_name_w > cap then dynamic_name_w = cap end
                            end
                            -- Effective NAME_W for this frame.
                            NAME_W = dynamic_name_w

                            -- Stack bars from bottom upward, slot 1 on top.
                            -- Each slot's bar height is TICKER_H * lines, where
                            -- lines is the wrap count returned by measure_seq_lines.
                            -- Two passes: (1) measure each slot's line count,
                            -- summing total height; (2) draw bottom-up.
                            local slot_lines = {}
                            local slot_seq   = {}
                            local total_h    = 0
                            for i, slot in ipairs(active) do
                                local seq = tokens_to_seq(slot.tokens)
                                slot_seq[i] = seq
                                -- Probe input width — must match input_x below.
                                -- Both derive from the inset bar (BAR_X/BAR_W) so the
                                -- measured wrap-line count matches what draw produces.
                                local probe_bar_x = INSET
                                local probe_bar_w = sw - INSET * 2
                                local probe_x = probe_bar_x + PAD_X + NAME_W + NAME_PAD + 3
                                local probe_w = (probe_bar_x + probe_bar_w) - probe_x - PAD_X
                                local lines = measure_seq_lines(probe_x, probe_w, TICKER_H, seq)
                                slot_lines[i] = lines
                                total_h = total_h + TICKER_H * lines
                            end
                            total_h = total_h + TICKER_GAP * math.max(0, #active - 1)
                            local top_y = sh - BOTTOM_OFF - total_h

                            local cursor_y = top_y
                            for i, slot in ipairs(active) do
                                local lines    = slot_lines[i]
                                local seq      = slot_seq[i]
                                local bar_h    = TICKER_H * lines
                                local ty       = cursor_y

                                -- Inset floating panel with real edges, so the depth
                                -- cues (shadow drop + top sheen) have left/right borders
                                -- to register against. BAR_X/BAR_W define the panel; all
                                -- interior content is offset from BAR_X (was screen 0).
                                local bx = INSET
                                local bw = sw - INSET * 2
                                local rad = math.floor(8 * SC)
                                local sh  = math.max(2, math.floor(3 * SC))
                                -- Layered depth: drop shadow -> border ring -> body -> top sheen.
                                -- Border ring = a slightly larger rounded fill behind the
                                -- body (outline_rounded_rect is unverified in this d2d build;
                                -- fill_rounded_rect is proven, so we composite instead).
                                d2d.fill_rounded_rect(bx + sh, ty + sh, bw, bar_h, rad, rad, TC_SHADOW)
                                d2d.fill_rounded_rect(bx - 1, ty - 1, bw + 2, bar_h + 2, rad + 1, rad + 1, TC_RING)
                                d2d.fill_rounded_rect(bx, ty, bw, bar_h, rad, rad, TC_BG)
                                d2d.fill_rect(bx + rad, ty + 1, bw - rad*2, 1, TC_TOPHI)

                                -- Name column (left). Anchored in the FIRST line
                                -- so it sits at the top when content wraps. The ':'
                                -- suffix acts as the visual separator between title
                                -- and inputs (in addition to the divider line).
                                local name_x = bx + PAD_X
                                local div_l  = name_x + NAME_W + NAME_PAD
                                local title  = title_for(slot, i)
                                if font_ticker_name then
                                    local _, th = font_ticker_name:measure(title)
                                    d2d.text(font_ticker_name, title,
                                        name_x, ty+(TICKER_H-th)/2, TC_NAME)
                                end
                                d2d.fill_rect(div_l, ty+4, 1, bar_h-8, TC_DIVIDER)

                                -- Input sequence (middle, full remaining width).
                                local input_x = div_l + 3
                                local input_w = (bx + bw) - input_x - PAD_X
                                draw_seq(input_x, ty, input_w, TICKER_H, seq)

                                cursor_y = cursor_y + bar_h + TICKER_GAP
                            end

                            else
                            -- ══════════════════════════════════════════════
                            -- VERTICAL LAYOUT (trials-mode style)
                            -- ══════════════════════════════════════════════
                            -- Each slot is its own narrow column anchored to
                            -- one side of the screen. Title at top. Below it,
                            -- one chunk per row, top→bottom. xx/sep/fk markers
                            -- render as inline tiny rows between chunks.
                            -- Slots stack horizontally (slot 1 outermost).

                            -- Column geometry — narrower than horizontal bar
                            -- since we only need to fit one chunk's worth of
                            -- width plus padding. Columns extend nearly the
                            -- full screen height; long combos overflow into
                            -- additional columns adjacent to the first.
                            local V_COL_W      = math.floor(150 * SC)
                            local V_COL_PAD    = math.floor(6   * SC)
                            local V_ROW_H      = math.floor(28  * SC)  -- per chunk row
                            local V_SEP_H      = math.floor(16  * SC)  -- xx/sep/fk row
                            local V_TITLE_H    = math.floor(24  * SC)
                            local V_GAP_BETWEEN = math.floor(6  * SC)  -- between columns
                            -- Top margin: leave room for health bars and
                            -- overlay UI at the top of the screen.
                            local V_TOP_OFF    = math.floor(sh * 0.08)
                            -- Bottom margin: leave clearance for SUPER bar
                            -- and frame meter at the screen bottom.
                            local V_BOT_OFF    = math.floor(sh * 0.12)
                            -- Cap a single column at this many pixels — runs
                            -- top→bottom of the safe zone.
                            local V_COL_H_MAX  = sh - V_TOP_OFF - V_BOT_OFF
                            -- Max columns to allow overflowing into. Beyond
                            -- this, content silently truncates (combo would
                            -- be unreadable spread over more columns anyway).
                            local V_MAX_COLS   = 4

                            -- Pre-measure pixel height per slot for the
                            -- background panel sizing. Token cost varies:
                            --   chunk  → V_ROW_H (full row)
                            --   sep    → ~8*SC (slim phrase break, no chevron)
                            --   others → V_SEP_H (xx / fk / x2 inline marker)
                            local V_BREAK_GAP_M = math.floor(8 * SC)
                            local function token_h(tok)
                                if tok.t == "chunk" then return V_ROW_H
                                elseif tok.t == "sep" then return V_BREAK_GAP_M
                                else return V_SEP_H end
                            end

                            -- Vertical mode shows ONLY the first active slot.
                            local V_SHOW_ALL = false
                            local v_active = active
                            if not V_SHOW_ALL and #active > 1 then
                                v_active = { active[1] }
                            end

                            -- ── Pre-pass: figure column count per slot ─────
                            -- For each slot, walk its token sequence and
                            -- count how many columns are needed (each column
                            -- has the title only on column 1, everywhere
                            -- else is content rows). Returns a list of
                            -- {col_count, breaks} per slot, where `breaks`
                            -- is a list mapping token-index → column number
                            -- so the draw pass can match exactly.
                            local function plan_slot(seq)
                                local title_h = V_TITLE_H + V_COL_PAD*2 + 4
                                local content_capacity_col1 = V_COL_H_MAX - title_h
                                local content_capacity_colN = V_COL_H_MAX - V_COL_PAD*2
                                local cur_col = 1
                                local cur_used = 0
                                local capacity = content_capacity_col1
                                local breaks = {}
                                for ti, tok in ipairs(seq) do
                                    local h = token_h(tok)
                                    if cur_used + h > capacity then
                                        if cur_col >= V_MAX_COLS then
                                            -- Hit cap; bail. Token gets
                                            -- truncated; downstream draw
                                            -- mirrors this break check.
                                            break
                                        end
                                        cur_col = cur_col + 1
                                        cur_used = 0
                                        capacity = content_capacity_colN
                                    end
                                    breaks[ti] = cur_col
                                    cur_used = cur_used + h
                                end
                                return cur_col, breaks
                            end

                            -- Pre-compute each slot's column count + breaks
                            local slot_plans = {}
                            local total_cols = 0
                            for i, slot in ipairs(v_active) do
                                local seq = tokens_to_seq(slot.tokens)
                                local n_cols, breaks = plan_slot(seq)
                                slot_plans[i] = { seq = seq, n_cols = n_cols, breaks = breaks }
                                total_cols = total_cols + n_cols
                            end

                            -- Total horizontal extent for all columns
                            local total_w = V_COL_W * total_cols
                                          + V_GAP_BETWEEN * math.max(0, total_cols - 1)

                            -- Anchor X: leftmost column position
                            local side = cfg.ticker_vertical_side or "left"
                            local anchor_x
                            if side == "right" then
                                anchor_x = sw - PAD_X - total_w
                            else
                                anchor_x = PAD_X
                            end

                            -- ── Draw pass ──────────────────────────────────
                            local global_col_idx = 0  -- column counter across all slots
                            for i, slot in ipairs(v_active) do
                                local plan = slot_plans[i]
                                local seq = plan.seq
                                local n_cols = plan.n_cols
                                local breaks = plan.breaks

                                -- Per-column render state. col_top_y is fixed
                                -- (all columns start at V_TOP_OFF); row_y
                                -- tracks the current draw cursor inside the
                                -- current column.
                                local col_y = V_TOP_OFF
                                local function col_x_for(c)
                                    return anchor_x + (global_col_idx + (c-1))
                                                    * (V_COL_W + V_GAP_BETWEEN)
                                end

                                -- Background panels for all columns this slot
                                -- spans. Title only renders in column 1.
                                for c = 1, n_cols do
                                    local cx = col_x_for(c)
                                    d2d.fill_rect(cx, col_y, V_COL_W, V_COL_H_MAX, TC_BG)
                                    d2d.outline_rect(cx, col_y, V_COL_W, V_COL_H_MAX, 1, TC_BORDER)
                                end

                                -- Title row (column 1 only)
                                local title = title_for(slot, i)
                                if font_ticker_name then
                                    local tw, th = font_ticker_name:measure(title)
                                    -- Left-align title against the column's
                                    -- inner left edge.
                                    d2d.text(font_ticker_name, title,
                                        col_x_for(1) + V_COL_PAD,
                                        col_y + V_COL_PAD + (V_TITLE_H - th)/2,
                                        TC_NAME)
                                end
                                d2d.fill_rect(col_x_for(1) + V_COL_PAD,
                                    col_y + V_COL_PAD + V_TITLE_H,
                                    V_COL_W - V_COL_PAD*2, 1, TC_DIVIDER)

                                -- Content rendering. Switch column when
                                -- breaks[ti] changes, and reset row_y to
                                -- the top of the new column (which has no
                                -- title block on columns ≥ 2, so content
                                -- can start higher).
                                local cur_col = 1
                                local row_y = col_y + V_COL_PAD + V_TITLE_H + 4
                                local function reset_row_y_for_col(c)
                                    if c == 1 then
                                        return col_y + V_COL_PAD + V_TITLE_H + 4
                                    else
                                        return col_y + V_COL_PAD
                                    end
                                end
                                local inner_w = V_COL_W - V_COL_PAD*2
                                local function inner_x_for(c)
                                    return col_x_for(c) + V_COL_PAD
                                end

                                for ti, tok in ipairs(seq) do
                                    local target_col = breaks[ti]
                                    if not target_col then break end  -- truncated
                                    if target_col ~= cur_col then
                                        cur_col = target_col
                                        row_y = reset_row_y_for_col(cur_col)
                                    end
                                    local inner_x = inner_x_for(cur_col)

                                    if tok.t == "chunk" then
                                        local cw = measure_chunk_w(tok)
                                        local pill_h = GLYPH_SZ + CHUNK_PAD_Y*2
                                        -- Left-align: pill's left edge sits
                                        -- at inner_x.
                                        local px = inner_x
                                        local py = row_y + (V_ROW_H - pill_h) / 2
                                        d2d.fill_rect(px, py, cw, pill_h, TC_CHUNK)
                                        local cx = px + CHUNK_PAD_X
                                        local first = true
                                        for _, part in ipairs(tok.parts) do
                                            if not first then cx = cx + INNER_GAP end
                                            if part.t == "dir" and font_ticker_dir then
                                                local dicon = notation_icon(part.v)
                                                if dicon then
                                                    d2d.image(dicon, cx, row_y + (V_ROW_H - GLYPH_SZ)/2, GLYPH_SZ, GLYPH_SZ)
                                                    cx = cx + GLYPH_SZ
                                                else
                                                    local dl = notation(part.v)
                                                    local tw, th = font_ticker_dir:measure(dl)
                                                    d2d.text(font_ticker_dir, dl,
                                                        cx, row_y + (V_ROW_H - th)/2, TC_DIR)
                                                    cx = cx + tw
                                                end
                                            elseif part.t == "btn" then
                                                local gw = draw_glyph(cx, row_y + (V_ROW_H - GLYPH_SZ)/2, part.v)
                                                cx = cx + (gw or GLYPH_SZ)
                                            end
                                            first = false
                                        end
                                        row_y = row_y + V_ROW_H
                                    elseif tok.t == "xx" and font_ticker_cancel then
                                        local tw, th = font_ticker_cancel:measure("xx")
                                        d2d.text(font_ticker_cancel, "xx",
                                            inner_x,
                                            row_y + (V_SEP_H - th)/2, TC_CANCEL)
                                        row_y = row_y + V_SEP_H
                                    elseif tok.t == "sep" then
                                        local V_BREAK_GAP = math.floor(8 * SC)
                                        -- Sep divider line: 60% of column,
                                        -- left-aligned (left edge at inner_x).
                                        local sep_w = math.floor(inner_w * 0.6)
                                        d2d.fill_rect(
                                            inner_x,
                                            row_y + math.floor(V_BREAK_GAP / 2),
                                            sep_w, 1,
                                            TC_DIVIDER)
                                        row_y = row_y + V_BREAK_GAP
                                    elseif tok.t == "fk" and font_ticker_cancel then
                                        local label = (tok.v and #tok.v > 0)
                                            and ("F.Kill " .. tok.v)
                                            or  "F.Kill"
                                        local tw, th = font_ticker_cancel:measure(label)
                                        local pill_w = tw + 8
                                        local pill_h = th + 4
                                        local px = inner_x
                                        local py = row_y + (V_SEP_H - pill_h)/2
                                        d2d.fill_rect(px, py, pill_w, pill_h, 0x668B1A1A)
                                        d2d.outline_rect(px, py, pill_w, pill_h, 1, 0xFFFF6666)
                                        d2d.text(font_ticker_cancel, label,
                                            px+4, row_y + (V_SEP_H - th)/2, 0xFFFF9999)
                                        row_y = row_y + V_SEP_H
                                    elseif tok.t == "x2" and font_ticker_cancel then
                                        local label = "x2"
                                        local tw, th = font_ticker_cancel:measure(label)
                                        local pill_w = tw + 8
                                        local pill_h = th + 4
                                        local px = inner_x
                                        local py = row_y + (V_SEP_H - pill_h)/2
                                        d2d.fill_rect(px, py, pill_w, pill_h, 0x443A2048)
                                        d2d.outline_rect(px, py, pill_w, pill_h, 1, 0xFF8855BB)
                                        d2d.text(font_ticker_cancel, label,
                                            px+4, row_y + (V_SEP_H - th)/2, 0xFFCC88FF)
                                        row_y = row_y + V_SEP_H
                                    end
                                end

                                global_col_idx = global_col_idx + n_cols
                            end
                            end
                        end
                    end
                end


            end

            if found_core then
                local geo = compute_bar_geo(sw, sh)

                -- Tick marks - angled lines with percent labels
                -- Percentages show HP *LOST* (damage taken), so 90% is
                -- near the outer/portrait edge (bar mostly empty when
                -- the fill ever retreats past it) and 10% is near the
                -- center (hasn't lost much yet).
                --
                -- P1 (left bar), reading LEFT → RIGHT: 90%, 80%, ... 10%
                -- P2 (right bar), reading LEFT → RIGHT: 10%, 20%, ... 90%
                --
                -- Slash direction matches user's literal request:
                -- P1: '\' (top-left to bottom-right)
                -- P2: '/' (top-right to bottom-left)
                -- Gate: read uBattleCore.m_is_started — the canonical
                -- "fight is in progress" flag. True only between round
                -- start and KO; false in menus, char select, loading,
                -- pre-round intros, and post-match results screens.
                -- This matches exactly when the live health bars are
                -- on screen and being filled by the engine.
                local fight_active = false
                if found_core then
                    local started = safe_get(found_core, "m_is_started")
                    fight_active = (started == true)
                end
                if cfg.show_ticks and fight_active then
                    local label_size = math.max(12, math.min(20,
                        math.floor(geo.h * 0.55)))
                    local label_font = get_font(label_size, true)

                    local thickness = math.max(2, math.floor(geo.h * 0.08))
                    -- Vertical ticks for retro skins: zero slant offset
                    -- means top_x == bottom_x in slant_line, so the line
                    -- renders straight up/down. SF6 default keeps the
                    -- characteristic angled '\' / '/' look.
                    local slant_dx  = (hud_tick_style() == "vertical") and 0
                                       or math.floor(geo.h * 0.65)
                    -- Tick color also varies per skin (blue for retro
                    -- yellow-bar skins, default yellow for SF6).
                    local tc        = tick_color()
                    local label_gap = 4
                    -- Per-skin label placement: SF3s wants labels above
                    -- the bar (energy gauge sits too close below). For
                    -- "above", subtract label_size + gap from bar top.
                    local label_y
                    if tick_label_pos() == "above" then
                        label_y = geo.y - label_size - label_gap
                    else
                        label_y = geo.y + geo.h + label_gap
                    end

                    local function slant_line(x1, y1, x2, y2, thick, color)
                        local dx, dy = x2 - x1, y2 - y1
                        local len = math.sqrt(dx*dx + dy*dy)
                        local steps = math.max(1, math.floor(len))
                        for i = 0, steps do
                            local t = i / steps
                            local px = x1 + dx * t - thick/2
                            local py = y1 + dy * t - thick/2
                            d2d.fill_rect(px, py, thick, thick, color)
                        end
                    end

                    -- Slope-aware Y resolver. Given an X position along
                    -- a bar, returns (top_y, bot_y) accounting for the
                    -- inner-section translation.
                    --
                    -- frac_from_outer is normalized 0..1 along the bar:
                    --   0 = at the outer edge (bar's outside)
                    --   1 = at the inner edge (bar's center side)
                    --
                    -- - frac < s_st                   → outer flat (no shift)
                    -- - s_st <= frac <= s_end         → linear interp of dy
                    -- - frac > s_end                  → fully shifted by inner_dy
                    local function bar_y_at(frac_from_outer)
                        local dy = geo.inner_dy
                        if dy == 0 or geo.s_st >= geo.s_end then
                            return geo.y, geo.y + geo.h
                        end
                        local lift
                        if frac_from_outer <= geo.s_st then
                            lift = 0
                        elseif frac_from_outer >= geo.s_end then
                            lift = dy
                        else
                            local t = (frac_from_outer - geo.s_st) /
                                      (geo.s_end - geo.s_st)
                            lift = math.floor(dy * t)
                        end
                        return geo.y - lift, geo.y + geo.h - lift
                    end

                    for tick = 1, 9 do
                        local pct_value = tick * 10
                        local pct  = tostring(pct_value) .. "%"
                        local tw, _ = label_font:measure(pct)

                        -- ── P1 bar ────────────────────────────────
                        -- P1 fills LEFT→RIGHT, drains RIGHT→LEFT.
                        -- 90% tick lives near the outer (LEFT) edge
                        -- → frac_from_outer = 1 - tick/10 (0.10)
                        -- 10% tick lives near inner (RIGHT) → frac = 0.90
                        local p1_frac  = 1 - tick/10
                        local p1_bot_x = geo.p1_x + math.floor(geo.w * p1_frac)
                        local p1_top, p1_bot = bar_y_at(p1_frac)
                        local p1_top_x = p1_bot_x - slant_dx
                        slant_line(p1_top_x, p1_top,
                                   p1_bot_x, p1_bot,
                                   thickness, tc)
                        -- Label position depends on tick_label_pos:
                        -- "above" → above the (possibly shifted) top
                        -- "below" → below the (possibly shifted) bottom
                        local lbl_y_p1
                        if tick_label_pos() == "above" then
                            lbl_y_p1 = p1_top - label_size - label_gap
                        else
                            lbl_y_p1 = p1_bot + label_gap
                        end
                        d2d_stroked_text(label_font, pct,
                            p1_bot_x - tw/2, lbl_y_p1, tc)

                        -- ── P2 bar (mirrored) ─────────────────────
                        -- P2 fills RIGHT→LEFT, drains LEFT→RIGHT.
                        -- Outer is the RIGHT edge → frac_from_outer
                        -- measures distance from RIGHT.
                        local p2_frac  = 1 - tick/10
                        local p2_bot_x = geo.p2_x + math.floor(geo.w * (tick/10))
                        local p2_top, p2_bot = bar_y_at(p2_frac)
                        local p2_top_x = p2_bot_x + slant_dx
                        slant_line(p2_top_x, p2_top,
                                   p2_bot_x, p2_bot,
                                   thickness, tc)
                        local lbl_y_p2
                        if tick_label_pos() == "above" then
                            lbl_y_p2 = p2_top - label_size - label_gap
                        else
                            lbl_y_p2 = p2_bot + label_gap
                        end
                        d2d_stroked_text(label_font, pct,
                            p2_bot_x - tw/2, lbl_y_p2, tc)
                    end

                    -- ── 25% minor tick (between 20% and 30%) ──────
                    -- Marks the threshold where Critical Art (Super 3)
                    -- becomes available — always labeled "CA", always
                    -- drawn ABOVE the bar regardless of skin's default
                    -- label position so the major-tick labels (10/20/etc)
                    -- and the CA marker never collide.
                    do
                        local minor_thickness = math.max(1, math.floor(thickness * 0.6))
                        local minor_size      = math.max(10, math.floor(label_size * 0.75))
                        local minor_font      = get_font(minor_size, true)
                        local pct  = "CA"
                        local tw, _ = minor_font:measure(pct)
                        local frac = 0.25

                        -- P1: 25% on bar = 75% of distance from outer
                        local p1_frac  = 1 - frac
                        local p1_bot_x = geo.p1_x + math.floor(geo.w * p1_frac)
                        local p1_top, p1_bot = bar_y_at(p1_frac)
                        local p1_top_x = p1_bot_x - slant_dx
                        slant_line(p1_top_x, p1_top,
                                   p1_bot_x, p1_bot,
                                   minor_thickness, tc)
                        -- Always above the (possibly lifted) bar top
                        local lbl_y_p1 = p1_top - minor_size - label_gap
                        d2d_stroked_text(minor_font, pct,
                            p1_bot_x - tw/2, lbl_y_p1, tc)

                        -- P2 (mirrored)
                        local p2_frac  = 1 - frac
                        local p2_bot_x = geo.p2_x + math.floor(geo.w * frac)
                        local p2_top, p2_bot = bar_y_at(p2_frac)
                        local p2_top_x = p2_bot_x + slant_dx
                        slant_line(p2_top_x, p2_top,
                                   p2_bot_x, p2_bot,
                                   minor_thickness, tc)
                        local lbl_y_p2 = p2_top - minor_size - label_gap
                        d2d_stroked_text(minor_font, pct,
                            p2_bot_x - tw/2, lbl_y_p2, tc)
                    end
                end

                -- Profile text
                -- P1: left-aligned, starts at LEFT (outer) end of P1 bar
                -- P2: right-aligned, ends at RIGHT (outer) end of P2 bar
                -- The user's offset sliders shift the text position but
                -- NOT the ticks (ticks stay glued to the actual bar).
                if cfg.show_profiles_text then
                    local function draw_profile(player, is_p1)
                        local key = player.name:lower()
                        local p = cfg.profiles[key] or default_profile(player.name)

                        local lh = cfg.font_size + 4
                        -- Anchor Y: just below the bar, with user offset
                        local ty = geo.y + geo.h +
                            math.floor(sh * 0.02) + cfg.offset_y

                        local name_col = is_p1 and C_NAME_P1 or C_NAME_P2
                        -- Show stance indicator next to character name when in stance.
                        -- Currently only Alex (Prowler Stance); extends naturally as
                        -- more stance characters are added.
                        local name_line = player.name
                        if is_p1 and is_in_stance(player.name) then
                            if stance_state.active == "prowler" then
                                name_line = name_line .. "  [PROWLER]"
                            end
                        end
                        local lines = {
                            { name_line, name_col },
                        }

                        if p.notes ~= "" then
                            table.insert(lines, { p.notes, C_DIM })
                        end

                        -- Append last-detected move's onHit / onBlock
                        local mv = is_p1 and current_move.p1 or current_move.p2
                        if mv then
                            table.insert(lines, { "---", C_DIM })
                            local move_label = (mv.name or "?")
                            -- If input uses generic K/P, append pressed button to the name
                            if is_p1 and last_numcmd and last_numcmd ~= "none"
                               and mv.input and not mv.input:match("[LMH][PK]") then
                                local btn = last_numcmd:match("([LMH][PK])$")
                                if btn then move_label = move_label .. " " .. btn end
                            end
                            -- Guile Perfect Timing indicator (latched at registration).
                            -- The flag persists for the full move display duration; computing
                            -- it live here would only show for ~3 frames since back_buffer
                            -- decrements each frame after release.
                            local perfect = is_p1 and current_move.p1_perfect
                                                   or current_move.p2_perfect
                            if perfect then
                                move_label = move_label .. "  [PERFECT]"
                            end
                            table.insert(lines, { move_label, name_col })
                            local function frame_col(val)
                                local s = tostring(val or "-")
                                if s:sub(1,1) == "+" then return s, C_GOOD end
                                if s:sub(1,1) == "-" then return s, C_BAD  end
                                return s, C_TEXT
                            end
                            local hs, hc = frame_col(mv.onHit)
                            local bs, bc = frame_col(mv.onBlock)
                            table.insert(lines, { "On Hit:   " .. hs, hc })
                            table.insert(lines, { "On Block: " .. bs, bc })
                        end

                        -- Append per-character notes from notes.json
                        -- (written by the SF6 Overlay Editor). Rendered LAST
                        -- so frame data stays adjacent to the character name
                        -- and notes flow underneath without colliding.
                        local nd = notes_data[player.name:lower()]
                        if nd and nd.notes and nd.notes ~= "" then
                            local WRAP_W = 28   -- chars per line, monospaced
                            local function wrap(s, w)
                                local out = {}
                                for paragraph in (s .. "\n"):gmatch("([^\n]*)\n") do
                                    if #paragraph == 0 then
                                        out[#out+1] = ""
                                    else
                                        local cur = ""
                                        for word in paragraph:gmatch("%S+") do
                                            if #cur == 0 then
                                                cur = word
                                            elseif #cur + 1 + #word <= w then
                                                cur = cur .. " " .. word
                                            else
                                                out[#out+1] = cur
                                                cur = word
                                            end
                                        end
                                        if #cur > 0 then out[#out+1] = cur end
                                    end
                                end
                                return out
                            end
                            -- Visual separator between frame data and notes
                            if mv then
                                table.insert(lines, { "---", C_DIM, is_note = true })
                            end
                            for _, wline in ipairs(wrap(nd.notes, WRAP_W)) do
                                table.insert(lines, { wline, C_DIM, is_note = true })
                            end
                        end

                        if is_p1 then
                            -- Left-aligned under LEFT (outer) end of P1 bar
                            local tx = geo.p1_x + cfg.offset_x
                            local cur_y = ty
                            for i, line in ipairs(lines) do
                                local fnt   = line.is_note and font_notes   or font_profile
                                local lh_i  = line.is_note and (cfg.notes_font_size + 4)
                                                          or  (cfg.font_size + 4)
                                d2d_stroked_text(fnt, line[1],
                                    tx, cur_y, line[2])
                                -- Underline the character name (first line)
                                if i == 1 then
                                    local nw, nh = fnt:measure(line[1])
                                    local ul_thick = math.max(1,
                                        math.floor(cfg.font_size * 0.08))
                                    d2d.fill_rect(tx, cur_y + nh,
                                        nw, ul_thick, line[2])
                                end
                                cur_y = cur_y + lh_i
                            end
                        else
                            -- Right-aligned under RIGHT (outer) end of P2 bar
                            local right_edge = geo.p2_x + geo.w + cfg.offset_x
                            local cur_y = ty
                            for i, line in ipairs(lines) do
                                local fnt   = line.is_note and font_notes   or font_profile
                                local lh_i  = line.is_note and (cfg.notes_font_size + 4)
                                                          or  (cfg.font_size + 4)
                                local lw, lh_text = fnt:measure(line[1])
                                local line_x = right_edge - lw
                                d2d_stroked_text(fnt, line[1],
                                    line_x, cur_y, line[2])
                                -- Underline the character name (first line)
                                if i == 1 then
                                    local ul_thick = math.max(1,
                                        math.floor(cfg.font_size * 0.08))
                                    d2d.fill_rect(line_x, cur_y + lh_text,
                                        lw, ul_thick, line[2])
                                end
                                cur_y = cur_y + lh_i
                            end
                        end
                    end

                    if cfg.show_p1_profile and players[1].esf ~= "?" then
                        draw_profile(players[1], true)
                    end
                    if cfg.show_p2_profile and players[2].esf ~= "?" then
                        draw_profile(players[2], false)
                    end
                end
            end
        end

        -- ── Dropdown menus ───────────────────────────────
        local function menu_anchor(btn_i, menu_w)
            local mx = btn_x[btn_i]
            local my = btn_y + btn_h + 2
            if mx + menu_w > sw - 4 then mx = sw - menu_w - 4 end
            if mx < 4 then mx = 4 end
            return mx, my
        end

        local row_h = cfg.menu_font_size + 8

        -- disp_scale drives the Display window's zoom-in entrance. Read by
        -- the row helpers below so they scale their internal row height +
        -- font with the live zoom factor. Default 1.0 (resting); the Display
        -- block sets it to the eased scale each frame, then restores it to
        -- 1.0 afterward. Defined AFTER row_h so disp_row_h captures it.
        local disp_scale = 1.0
        local function dsc(n) return math.floor(n * disp_scale) end
        local function disp_row_h() return dsc(row_h) end
        local function disp_font()
            return get_legend_font(math.max(8, dsc(disp_fs)))
        end

        local function draw_menu_panel(x, y, w, h, title, pscale)
            local T = _SF6UI.THEME
            -- pscale (default 1.0) lets a caller shrink the frame's internal
            -- metrics (corner radius, shadow, accent strip, title) in step
            -- with a zoom animation. Other callers omit it → unchanged.
            pscale = pscale or 1.0
            local function ps(n) return math.floor(n * pscale) end
            local r = math.max(2, ps(T.RADIUS))
            local shadow_off = ps(T.SHADOW_OFFSET)
            local accent_h   = math.max(1, ps(T.ACCENT_H))
            -- acc_rgb (accent color, alpha stripped) is reused below for the
            -- double border and the background gradient tint.
            local acc_rgb = T.accent_neutral % 0x1000000
            -- Pronounced soft drop shadow: several expanding, offset rounded
            -- rects with decreasing alpha build a soft spread (d2d has no blur).
            -- Offset down-right and growing so it reads as the window floating
            -- above the game. Alpha is NOT tied to panel transparency (g), so
            -- a see-through window still casts a solid shadow.
            local SH_OFF  = ps(10)   -- max down-right offset
            local SH_GROW = ps(6)    -- how far the softest layer spreads
            for s = 4, 1, -1 do
                local t   = s / 4               -- 1.0 (outer/soft) → 0.25 (inner/dark)
                local off = math.floor(SH_OFF * t)
                local gr  = math.floor(SH_GROW * t)
                local a   = math.floor(0x4A * (1 - t) + 0x16)  -- inner darker, outer fainter
                local scol = (a * 0x1000000)   -- black with this alpha
                d2d.fill_rounded_rect(x + off - gr, y + off - gr,
                    w + gr*2, h + gr*2, r + gr, r + gr, scol)
            end
            -- Body — rounded base for clean corners, then a faked vertical
            -- gradient (top lighter → bottom darker) drawn as thin bands on
            -- top. d2d has no gradient primitive, so we interpolate ARGB
            -- across ~40 strips. Inset 1px so the square strips don't poke
            -- past the rounded corners.
            d2d.fill_rounded_rect(x, y, w, h, r, r, T.panel_bg)
            do
                local function comp(c, sh) return math.floor(c / sh) % 256 end
                -- Gradient now tints toward the accent color: the TOP is a
                -- dark accent shade (accent RGB scaled down so it's a deep
                -- tint, not a bright fill), fading to near-black at the
                -- BOTTOM. Derived from accent_neutral so it auto-follows the
                -- "Menu Accent" setting. Alpha matches the panel glass.
                local panel_a = comp(T.panel_bg, 0x1000000)
                local aR = comp(T.accent_neutral, 0x10000)
                local aG = comp(T.accent_neutral, 0x100)
                local aB = T.accent_neutral % 256
                local TOP_MIX = 0.70   -- how strong the accent tint is at top
                                       -- (higher = brighter/more noticeable fade)
                local r1 = math.floor(aR * TOP_MIX)
                local g1 = math.floor(aG * TOP_MIX)
                local b1 = math.floor(aB * TOP_MIX)
                local a1 = panel_a
                local r2, g2, b2 = 5, 5, 8   -- near-black bottom
                local a2 = panel_a
                local gx = x + 1
                local gw = w - 2
                local gy = y + r           -- start below the top corner curve
                local gh = h - r*2         -- end above the bottom corner curve
                local BANDS = 40
                local bh = gh / BANDS
                for i = 0, BANDS - 1 do
                    local t  = i / (BANDS - 1)
                    local a  = math.floor(a1 + (a2-a1)*t)
                    local rr = math.floor(r1 + (r2-r1)*t)
                    local gg = math.floor(g1 + (g2-g1)*t)
                    local bb = math.floor(b1 + (b2-b1)*t)
                    local col = a*0x1000000 + rr*0x10000 + gg*0x100 + bb
                    d2d.fill_rect(gx, gy + i*bh, gw, bh + 1, col)
                end
            end
            -- Top accent strip — gradient violet→blue→violet. Drawn as a
            -- rounded rect so its top corners match the panel; thin height.
            local seg = (w - r*2) / 3
            d2d.fill_rect(x + r,         y, seg+1, accent_h, T.accent_neutral)
            d2d.fill_rect(x + r + seg,   y, seg+1, accent_h, T.accent_neutral2)
            d2d.fill_rect(x + r + seg*2, y, seg+1, accent_h, T.accent_neutral)
            -- Neon-lit double border: each border line gets a tight outward
            -- bloom (a few low-alpha accent rings hugging the line) so it
            -- reads like a glowing neon tube, plus a bright near-white core
            -- highlight on top for the lit-filament look.
            local acc_full = (0xFF * 0x1000000) + acc_rgb
            -- Brighten the accent toward white for the neon core highlight.
            local function brighten(rgb, m)
                local R = math.floor(rgb / 0x10000) % 256
                local G = math.floor(rgb / 0x100) % 256
                local B = rgb % 256
                R = math.floor(R + (255 - R) * m)
                G = math.floor(G + (255 - G) * m)
                B = math.floor(B + (255 - B) * m)
                return R*0x10000 + G*0x100 + B
            end
            local core = (0xFF * 0x1000000) + brighten(acc_rgb, 0.55)

            -- Outer border with bloom: 3 expanding rings (faint→fainter)
            -- hugging the outer edge, then the solid accent line, then a
            -- bright core highlight.
            for b = 3, 1, -1 do
                local grow  = ps(b * 2)
                local alpha = math.floor(0x55 / b)
                local gcol  = (alpha * 0x1000000) + acc_rgb
                d2d.rounded_rect(x - grow, y - grow, w + grow*2, h + grow*2,
                    r + grow, r + grow, ps(2), gcol)
            end
            d2d.rounded_rect(x, y, w, h, r, r, ps(6), acc_full)
            d2d.rounded_rect(x + ps(2), y + ps(2), w - ps(4), h - ps(4),
                math.max(1, r - ps(2)), math.max(1, r - ps(2)), ps(2), core)

            -- Inner border, same neon treatment.
            local inset = ps(11)
            local ix, iy = x + inset, y + inset
            local iw, ih = w - inset*2, h - inset*2
            local ir = math.max(1, r - inset)
            for b = 2, 1, -1 do
                local grow  = ps(b * 2)
                local alpha = math.floor(0x44 / b)
                local gcol  = (alpha * 0x1000000) + acc_rgb
                d2d.rounded_rect(ix - grow, iy - grow, iw + grow*2, ih + grow*2,
                    ir + grow, ir + grow, ps(2), gcol)
            end
            d2d.rounded_rect(ix, iy, iw, ih, ir, ir, ps(6), acc_full)
            d2d.rounded_rect(ix + ps(2), iy + ps(2), iw - ps(4), ih - ps(4),
                math.max(1, ir - ps(2)), math.max(1, ir - ps(2)), ps(2), core)

            -- ── Breathing inner glow ──────────────────────────────
            -- A soft accent glow that lives just INSIDE the inner border and
            -- pulses (breathes) via a sine wave. Built from several rounded-
            -- rect outlines stepping inward from the border, each fainter, so
            -- it reads as light bleeding inward from the frame. Alpha scales
            -- with the pulse so the whole rim gently brightens and dims.
            do
                local pulse = (math.sin(os.clock() * 1.6) + 1) * 0.5   -- 0..1, ~4s cycle
                local gx, gy = ix + ps(3), iy + ps(3)   -- start just inside the inner border
                local gw, gh = iw - ps(6), ih - ps(6)
                local gr = math.max(1, ir - ps(3))
                local LAYERS = 6
                for L = 1, LAYERS do
                    local step  = ps(2) * (L - 1)
                    -- fade inward (L=1 brightest at the edge) and by the pulse
                    local falloff = (LAYERS - L + 1) / LAYERS        -- 1 → ~0.17
                    local a = math.floor(0x3A * falloff * (0.30 + 0.70 * pulse))
                    if a > 0 then
                        local gcol = (a * 0x1000000) + acc_rgb
                        d2d.rounded_rect(gx + step, gy + step,
                            gw - step*2, gh - step*2,
                            math.max(1, gr - step), math.max(1, gr - step),
                            ps(2), gcol)
                    end
                end
            end
            if title then
                -- Title bar: faked vertical gradient (3 bands). Inset by the
                -- radius so it doesn't poke past the rounded corners. Height
                -- scales with pscale so caller row math (which also scales)
                -- stays aligned.
                local th = ps(cfg.menu_font_size + 8)
                local bar_y = y + accent_h
                local bar_h = th - accent_h
                local band = bar_h / 3
                d2d.fill_rect(x + r, bar_y,          w - 2*r, band+1, T.title_bg)
                d2d.fill_rect(x + r, bar_y + band,   w - 2*r, band+1,
                    argb(0.13, 0.10, 0.23, 1.00))
                d2d.fill_rect(x + r, bar_y + band*2, w - 2*r, band+1, T.title_bg_lo)
                local tfont = (pscale == 1.0) and font_menu_title
                              or get_font(math.max(8, ps(cfg.menu_font_size + 2)), true)
                d2d.text(tfont, title,
                    x + ps(T.PAD), y + accent_h + ps(2), T.title_text)
                -- Divider under title (real line, inset to the rounded sides)
                d2d.line(x + r, y + th, x + w - r, y + th, 1, T.divider)
            end
        end

        local function row_checkbox(x, y, w, label, state)
            local T = _SF6UI.THEME
            local rh  = disp_row_h()
            local fnt = disp_font()
            local hovered = hit_rect(x, y, w, rh)
            -- Active-row tint: faint violet wash behind a row whose toggle is
            -- ON (mockup style). Drawn first so hover can layer over it.
            if state then d2d.fill_rect(x, y, w, rh, T.row_active_bg) end
            if hovered then d2d.fill_rect(x, y, w, rh, T.row_hover) end
            -- Toggle switch on the RIGHT — real capsule pill + round knob.
            local sw_h = math.max(14, math.floor(rh * 0.55))
            local sw_w = sw_h * 2                       -- 2:1 switch shape
            local sw_x = x + w - sw_w - dsc(10)
            local sw_y = y + (rh - sw_h) / 2
            local cap  = sw_h / 2                        -- full pill radius
            local track = state and T.toggle_on_bg or T.toggle_off_bg
            -- Glow halo behind the track when ON — real rounded rect, soft.
            if state then
                d2d.fill_rounded_rect(sw_x-4, sw_y-4, sw_w+8, sw_h+8,
                    cap+4, cap+4, T.toggle_on_glow)
            end
            -- Capsule track (radius = half height → true pill ends)
            d2d.fill_rounded_rect(sw_x, sw_y, sw_w, sw_h, cap, cap, track)
            d2d.rounded_rect(sw_x, sw_y, sw_w, sw_h, cap, cap, 1, T.panel_border)
            -- Round knob (real circle), centered vertically, slides L↔R
            local kr = cap - 2
            local kcx = state and (sw_x + sw_w - cap) or (sw_x + cap)
            local kcy = sw_y + cap
            d2d.fill_circle(kcx, kcy, kr,
                state and T.toggle_knob or T.toggle_knob_off)
            -- Label on the LEFT
            local _, lh = fnt:measure(label)
            d2d.text(fnt, label,
                x + dsc(8), y + (rh - lh) / 2, T.text_label)
            if click_in(x, y, w, rh) then return not state, true end
            return state, false
        end

        local function row_cycle(x, y, w, label, value_text, plain_right)
            local T = _SF6UI.THEME
            local rh  = disp_row_h()
            local fnt = disp_font()
            local _, fh = fnt:measure(label)
            local hovered = hit_rect(x, y, w, rh)
            if hovered then d2d.fill_rect(x, y, w, rh, T.row_hover) end
            local ty = y + (rh - fh) / 2
            -- Label left
            d2d.text(fnt, label, x + dsc(8), ty, T.text_label)
            local lw, _ = fnt:measure(label)
            local label_end = x + dsc(8) + lw + dsc(12)   -- right edge of label + gap

            if plain_right then
                -- Caller draws its own right-side widget (color swatch).
                d2d.text(fnt, value_text, label_end, ty, T.text_value)
                return click_in(x, y, w, rh)
            end

            -- Cycle control, right-aligned: ‹  [value]  ›
            -- Whole row is ONE click target; click always advances forward
            -- (contract preserved — arrows are visual affordance only).
            local chip   = math.max(16, math.floor(rh * 0.7))
            local vw, _  = fnt:measure(value_text)
            local valpad = dsc(10)
            local gap    = dsc(5)
            local val_w  = vw + valpad * 2
            local rx     = x + w - dsc(8)
            local rax    = rx - chip                 -- right arrow chip x
            local valx   = rax - gap - val_w         -- value chip x
            local lax    = valx - gap - chip         -- left arrow chip x
            local cy     = y + (rh - chip) / 2

            -- COLLISION GUARD: if the left arrow would overlap the label,
            -- the value is too wide for chip mode → fall back to plain
            -- right-aligned value text (no chips). Prevents the
            -- "Position:Above Frame Meter" overrun seen at 4K.
            if lax < label_end then
                d2d.text(fnt, value_text, rx - vw, ty, T.text_value)
                return click_in(x, y, w, rh)
            end

            local lit = hovered and T.pill_arrow_hi or T.pill_arrow_bg
            local crad = dsc(5)   -- chip corner radius
            -- left ‹
            d2d.fill_rounded_rect(lax, cy, chip, chip, crad, crad, lit)
            d2d.rounded_rect(lax, cy, chip, chip, crad, crad, 1, T.panel_border)
            d2d.text(fnt, "<", lax + chip/2 - dsc(4), ty, T.pill_arrow_txt)
            -- value chip
            d2d.fill_rounded_rect(valx, cy, val_w, chip, crad, crad, T.pill_value_bg)
            d2d.text(fnt, value_text, valx + valpad, ty, T.text_value)
            -- right ›
            d2d.fill_rounded_rect(rax, cy, chip, chip, crad, crad, lit)
            d2d.rounded_rect(rax, cy, chip, chip, crad, crad, 1, T.panel_border)
            d2d.text(fnt, ">", rax + chip/2 - dsc(4), ty, T.pill_arrow_txt)
            return click_in(x, y, w, rh)
        end

        local function row_label(x, y, text, color)
            local fnt = disp_font()
            local _, fh = fnt:measure(text)
            local ty = y + (disp_row_h() - fh) / 2
            d2d.text(fnt, text, x + dsc(6), ty, color or C_DIM)
        end

        -- section_header(x, y, w, text): small uppercase group label with a
        -- divider rule extending to the right. Used to chunk the panel into
        -- named sections (OVERLAY / TICKER / TEXT).
        local function section_header(x, y, w, text)
            local T = _SF6UI.THEME
            local fnt = disp_font()
            local rh  = disp_row_h()
            local tw, fh = fnt:measure(text)
            local ty = y + (rh - fh) / 2
            d2d.text(fnt, text, x + dsc(6), ty, T.accent_neutral)
            local rule_x = x + dsc(6) + tw + dsc(10)
            local rule_w = (x + w) - rule_x - dsc(4)
            if rule_w > 0 then
                d2d.fill_rect(rule_x, y + rh/2, rule_w, 1, T.divider)
            end
        end

        -- menu_button: clickable rect with hover highlight.
        --   color    — optional text color override (default C_BTN_TEXT)
        --   bg_color — optional non-hover background color override
        --              (default C_BTN_BG). Used by toggle pairs (e.g.
        --              Classic / Modern scheme buttons) to highlight
        --              the currently-active option without relying on
        --              hover state.
        local function menu_button(x, y, w, h, label, color, bg_color)
            local T = _SF6UI.THEME
            local hovered = hit_rect(x, y, w, h)
            -- State resolution:
            --   • bg_color passed → primary/active button; use that color,
            --     and BRIGHTEN it on hover so it still gives feedback.
            --   • hovered          → themed hover fill.
            --   • otherwise         → themed idle fill.
            local bg, border
            if bg_color then
                -- Brighten the forced color on hover (clamped per-channel).
                bg     = hovered and _SF6UI.UI.brighten(bg_color, 32) or bg_color
                border = T.btn_border_hi
            elseif hovered then
                bg     = T.btn_hover
                border = T.btn_border_hi
            else
                bg     = T.btn_idle
                border = T.btn_border
            end

            -- Press flash: when this button was clicked recently, overlay a
            -- bright pulse that fades over ~10 frames. Keyed by label so each
            -- button tracks its own flash. State lives on _SF6UI.anim.flash.
            _SF6UI.anim.flash = _SF6UI.anim.flash or {}
            local fl = _SF6UI.anim.flash[label] or 0

            local br = 6
            -- Glow halo for primary/active buttons (toggle-lit language).
            if bg_color then
                d2d.fill_rounded_rect(x-3, y-3, w+6, h+6, br+3, br+3,
                    T.toggle_on_glow)
            end
            d2d.fill_rounded_rect(x + 1, y + 2, w, h, br, br, T.panel_shadow)
            d2d.fill_rounded_rect(x, y, w, h, br, br, bg)
            -- Flash overlay (fades 1→0). White-ish pulse on top of the body.
            if fl > 0 then
                local a = (fl / 10) * 0.55      -- peak ~0.55 alpha
                d2d.fill_rounded_rect(x, y, w, h, br, br,
                    argb(1.0, 1.0, 1.0, a))
                _SF6UI.anim.flash[label] = fl - 1
            end
            d2d.rounded_rect(x, y, w, h, br, br, 1, border)
            local tw, th = font_button:measure(label)
            d2d.text(font_button, label,
                x + (w - tw)/2, y + (h - th)/2,
                color or T.btn_text)
            -- On click, arm the flash for this button.
            if click_in(x, y, w, h) then
                _SF6UI.anim.flash[label] = 10
                return true
            end
            return false
        end

        -- Display & Settings menu (merged)
        -- Display panel: animate slide-in/out. Draw while the flag is on OR
        -- while the close animation is still playing (progress > 0).
        local disp_open = show_display_win and cfg.show_button_bar
        local disp_p = _SF6UI.UI.anim_time("display", disp_open, 0.40)  -- time-based smooth zoom
        if (disp_open or disp_p > 0.001) and cfg.show_button_bar then
            -- ── Full real-zoom entrance (mirrors the Combo Notes window) ──
            -- Every coordinate is multiplied by a live scale S (ease_back_out
            -- overshoot, 0.35→1.0) and the panel is anchored to its center so
            -- it flies toward the screen. sc() scales pixels; disp_scale is
            -- set to S so the row helpers (row_checkbox/cycle/header) scale
            -- their internal row height + font in step. Restored to 1.0 at
            -- the end of the block so nothing else is affected.
            local zoom_e = _SF6UI.UI.ease_back_out(disp_p, 1.2)
            local S = 0.08 + 0.92 * zoom_e
            if S > 1.18 then S = 1.18 end
            local function sc(n) return math.floor(n * S) end
            disp_scale = S

            -- Two-column wide layout. Full-size (S=1) dims match the Combo
            -- editor width (1400). row_pitch is the per-row vertical advance.
            local MW_F = 1440
            local pad_f, col_gap_f = 28, 40
            local col_w_f   = (MW_F - pad_f*2 - col_gap_f) / 2
            local pitch_f   = math.floor((cfg.menu_font_size + 8) * 1.7)
            local max_rows  = 12
            local MH_F = (cfg.menu_font_size + 8) + math.floor(max_rows * pitch_f) + pitch_f + 60
            if MH_F > 926 then MH_F = 926 end

            -- Anchor: grow from the SCREEN CENTER so the window flies in
            -- toward the player from the middle (matching the Combo Notes
            -- "center" behavior), not from the button bar.
            local acx, acy = sw / 2, sh / 2

            local mw = sc(MW_F)
            local mh = sc(MH_F)
            local mx = math.floor(acx - mw/2)
            local my = math.floor(acy - mh/2)
            local pad       = sc(pad_f)
            local col_gap   = sc(col_gap_f)
            local col_w     = sc(col_w_f)
            local row_pitch = sc(pitch_f)

            draw_menu_panel(mx, my, mw, mh, "Display & Settings", S)

            -- Inset the content rect inside the thick double border so the
            -- bottom buttons / right column clear it (matches Combo Notes).
            local DISP_BORDER = sc(14)
            mx = mx + DISP_BORDER
            my = my + DISP_BORDER
            mw = mw - DISP_BORDER * 2
            mh = mh - DISP_BORDER * 2

            local colL_x = mx + pad
            local colR_x = mx + pad + col_w + col_gap
            local top_y  = my + sc(cfg.menu_font_size + 8) + sc(8)
            local ryL = top_y
            local ryR = top_y
            local changed

            -- ════════ LEFT COLUMN ════════
            section_header(colL_x, ryL, col_w, "OVERLAY")
            ryL = ryL + row_pitch

            cfg.show_overlay, changed = row_checkbox(colL_x, ryL, col_w,
                "Master Overlay", cfg.show_overlay)
            ryL = ryL + row_pitch

            cfg.show_ticks, changed = row_checkbox(colL_x, ryL, col_w,
                "Health Bar Ticks", cfg.show_ticks)
            ryL = ryL + row_pitch

            local hsidx = hud_skin_index(cfg.hud_skin)
            local hs_label = _SF6UI.hud.HUD_SKIN_DISPLAY[_SF6UI.hud.HUD_SKIN_ORDER[hsidx]]
                          or _SF6UI.hud.HUD_SKIN_ORDER[hsidx]
            if row_cycle(colL_x, ryL, col_w, "HUD Skin:", hs_label) then
                local next_i = (hsidx % #_SF6UI.hud.HUD_SKIN_ORDER) + 1
                cfg.hud_skin = _SF6UI.hud.HUD_SKIN_ORDER[next_i]
            end
            ryL = ryL + row_pitch

            -- Global control scheme (Classic/Modern) for the Combo editor,
            -- applied to all characters. Switching it drops the in-memory
            -- combo cache + queues a reload so the editor reads the right
            -- file (combonotes.json vs moderncombonotes.json) next open.
            do
                local sch = (cfg.combo_scheme == "modern") and "Modern" or "Classic"
                if row_cycle(colL_x, ryL, col_w, "Control Scheme:", sch) then
                    cfg.combo_scheme = (cfg.combo_scheme == "modern") and "classic" or "modern"
                    save_config()
                    combo_notes_loaded = {}
                    combo_slots = {}
                    local cur = ROSTER[edit_char_idx]
                    if cur and cur ~= "?" then
                        combo_notes_load_pending = cur
                    end
                end
            end
            ryL = ryL + row_pitch

            cfg.show_ticker, changed = row_checkbox(colL_x, ryL, col_w,
                "Combo Ticker Bars", cfg.show_ticker)
            ryL = ryL + row_pitch

            do
                local NM_ORDER  = { "numeric", "lettered", "icon" }
                local NM_LABELS = { numeric="Numeric (236)", lettered="Lettered (QCF)", icon="Icons (PNG)" }
                local nm_cur = cfg.notation_mode or "numeric"
                if row_cycle(colL_x, ryL, col_w, "Input Display:",
                        NM_LABELS[nm_cur] or nm_cur) then
                    local idx = 1
                    for i, k in ipairs(NM_ORDER) do
                        if k == nm_cur then idx = i break end
                    end
                    cfg.notation_mode = NM_ORDER[(idx % #NM_ORDER) + 1]
                    -- Keep the legacy bool roughly in sync for any old code
                    -- path still reading it.
                    cfg.numeric_notation = (cfg.notation_mode == "numeric")
                end
            end
            ryL = ryL + row_pitch

            ryL = ryL + row_pitch/2   -- gap before next section

            section_header(colL_x, ryL, col_w, "PROFILE")
            ryL = ryL + row_pitch

            cfg.show_profiles_text, changed = row_checkbox(colL_x, ryL, col_w,
                "Profile Text (master)", cfg.show_profiles_text)
            ryL = ryL + row_pitch

            cfg.show_p1_profile, changed = row_checkbox(colL_x, ryL, col_w,
                "  Show Player 1", cfg.show_p1_profile)
            ryL = ryL + row_pitch

            cfg.show_p2_profile, changed = row_checkbox(colL_x, ryL, col_w,
                "  Show Player 2", cfg.show_p2_profile)
            ryL = ryL + row_pitch

            -- ════════ RIGHT COLUMN ════════
            section_header(colR_x, ryR, col_w, "TICKER")
            ryR = ryR + row_pitch

            local SCALE_STEPS = { 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0 }
            local scale_labels = { "0.75x", "1.0x", "1.25x", "1.5x", "2.0x", "2.5x", "3.0x" }
            local cur_scale_idx = 2
            for i, v in ipairs(SCALE_STEPS) do
                if math.abs(v - (cfg.ticker_scale or 1.0)) < 0.01 then
                    cur_scale_idx = i; break
                end
            end
            if row_cycle(colR_x, ryR, col_w, "Scale:", scale_labels[cur_scale_idx]) then
                local next_i = (cur_scale_idx % #SCALE_STEPS) + 1
                cfg.ticker_scale = SCALE_STEPS[next_i]
            end
            ryR = ryR + row_pitch

            local POS_STEPS  = { 0.05, 0.11, 0.32, 0.45 }
            local POS_LABELS = { "Bottom", "Default", "Frame Meter", "Mid" }
            local cur_pos_idx = 2
            for i, v in ipairs(POS_STEPS) do
                if math.abs(v - (cfg.ticker_bottom_pct or 0.11)) < 0.01 then
                    cur_pos_idx = i; break
                end
            end
            if row_cycle(colR_x, ryR, col_w, "Position:", POS_LABELS[cur_pos_idx]) then
                local next_i = (cur_pos_idx % #POS_STEPS) + 1
                cfg.ticker_bottom_pct = POS_STEPS[next_i]
            end
            ryR = ryR + row_pitch

            local cur_orient = cfg.ticker_orientation or "horizontal"
            local orient_label = (cur_orient == "vertical") and "Vertical" or "Horizontal"
            if row_cycle(colR_x, ryR, col_w, "Orientation:", orient_label) then
                cfg.ticker_orientation = (cur_orient == "vertical") and "horizontal" or "vertical"
            end
            ryR = ryR + row_pitch

            local cur_side = cfg.ticker_vertical_side or "left"
            local side_label = (cur_side == "right") and "Right" or "Left"
            if row_cycle(colR_x, ryR, col_w, "Vertical Side:", side_label) then
                cfg.ticker_vertical_side = (cur_side == "left") and "right" or "left"
            end
            ryR = ryR + row_pitch

            ryR = ryR + row_pitch/2   -- gap before next section

            section_header(colR_x, ryR, col_w, "TEXT")
            ryR = ryR + row_pitch

            -- Single font-size control for both profile and notes text
            -- (they were separate cyclers; now one keeps them in sync).
            if row_cycle(colR_x, ryR, col_w, "Text Font:",
                tostring(cfg.font_size) .. "px") then
                cfg.font_size = next_in_cycle(cfg.font_size, FONT_SIZES)
                cfg.notes_font_size = cfg.font_size
            end
            ryR = ryR + row_pitch

            -- Menu Accent: cycles the hand-tuned accent palettes. Rebuilds the
            -- THEME on change so the menu recolors live; persisted via Save.
            do
                local order = _SF6UI.THEME.ACCENT_ORDER
                local cur   = cfg.accent_preset or "violet"
                local aidx  = 1
                for i, k in ipairs(order) do if k == cur then aidx = i break end end
                local aname = _SF6UI.THEME.ACCENT_NAMES[cur] or cur
                if row_cycle(colR_x, ryR, col_w, "Menu Accent:", aname, true) then
                    local next_i = (aidx % #order) + 1
                    cfg.accent_preset = order[next_i]
                    _SF6UI.THEME.init()   -- live recolor
                end
                local sw_ac = _SF6UI.THEME.ACCENT_SWATCH[cfg.accent_preset]
                          or _SF6UI.THEME.ACCENT_SWATCH.violet
                local sw_h2 = disp_row_h() - dsc(8)
                local ac_x = colR_x + col_w - dsc(32)
                d2d.fill_rect(ac_x, ryR+dsc(4), dsc(26), sw_h2,
                    argb(sw_ac[1], sw_ac[2], sw_ac[3], sw_ac[4]))
                d2d.outline_rect(ac_x, ryR+dsc(4), dsc(26), sw_h2, 1, C_BTN_BORDER)
            end
            ryR = ryR + row_pitch

            local cidx2 = color_index(cfg.font_color)
            if row_cycle(colR_x, ryR, col_w, "Text Color:",
                COLOR_PRESETS[cidx2].name, true) then
                local next_i = (cidx2 % #COLOR_PRESETS) + 1
                local c = COLOR_PRESETS[next_i].rgba
                cfg.font_color = { c[1], c[2], c[3], c[4] }
                C_TEXT = argb(c[1], c[2], c[3], c[4])
            end
            local sw_h3 = disp_row_h() - dsc(8)
            local sw_x2 = colR_x + col_w - dsc(32)
            d2d.fill_rect(sw_x2, ryR+dsc(4), dsc(26), sw_h3, C_TEXT)
            d2d.outline_rect(sw_x2, ryR+dsc(4), dsc(26), sw_h3, 1, C_BTN_BORDER)
            ryR = ryR + row_pitch

            if row_cycle(colR_x, ryR, col_w, "Vert Offset:",
                tostring(cfg.offset_y) .. "px") then
                cfg.offset_y = cfg.offset_y + 2
                if cfg.offset_y > 20 then cfg.offset_y = -20 end
            end
            ryR = ryR + row_pitch

            if row_cycle(colR_x, ryR, col_w, "Horiz Offset:",
                tostring(cfg.offset_x) .. "px") then
                cfg.offset_x = cfg.offset_x + 4
                if cfg.offset_x > 40 then cfg.offset_x = -40 end
            end
            ryR = ryR + row_pitch

            -- Resolution readout spans bottom of left column
            row_label(colL_x, ryL + sc(cfg.menu_font_size + 8)/2,
                "Resolution: " .. sw .. " x " .. sh)

            -- ════════ BOTTOM BUTTONS ════════
            -- Auto-width each button to its label (+ padding) so text never
            -- overflows, and lay them out left-to-right with a fixed gap.
            -- Close is pinned to the right edge.
            local bh = sc(cfg.menu_font_size + 8) + sc(4)
            local by = my + mh - bh - sc(8)
            local bpad = sc(18)           -- horizontal padding inside each button
            local bgap = sc(10)           -- gap between buttons
            local function btn_w(label)
                local tw, _ = font_button:measure(label)
                return tw + bpad * 2
            end
            local bx = mx + pad
            local w_save   = btn_w("Save")
            local w_reset  = btn_w("Reset Text Pos")
            local w_reload = btn_w("Reload Script")
            local w_close  = btn_w("Close")

            if menu_button(bx, by, w_save, bh, "Save", nil, _SF6UI.THEME.btn_active) then save_config() end
            bx = bx + w_save + bgap
            if menu_button(bx, by, w_reset, bh, "Reset Text Pos") then
                cfg.offset_x = 0; cfg.offset_y = 0; save_config()
            end
            bx = bx + w_reset + bgap
            if menu_button(bx, by, w_reload, bh, "Reload Script") then
                save_config()
                reframework:reset_scripts()
            end
            -- Close pinned to right edge
            if menu_button(mx + mw - pad - w_close, by, w_close, bh, "Close") then
                show_display_win = false
            end
            disp_scale = 1.0   -- restore (helpers default to unscaled elsewhere)
        end

        -- (Combo Editor / Character Profiles pop-up window removed: the
        --  character picker and Combo Notes launch now live inside the
        --  Combo Notes window itself. This avoids a second window opening.)

        -- ── COMBO NOTES INPUT BUILDER ───────────────────────────
        -- Slide-IN only: this window has live keyboard handlers and heavy
        -- per-frame input state, so we keep the draw gate on the real flag
        -- (no drawing/handling during a close-out) and only apply the
        -- entrance slide. Stepping anim here keeps progress in sync.
        local cn_open = show_combo_notes_win and cfg.show_button_bar
        local cn_p = _SF6UI.UI.anim_time("combo", cn_open, 0.40)  -- 0.40s open/close; time-based = smooth at any framerate
        if cn_open then
            local char_name = ROSTER[edit_char_idx]
            local combos    = get_char_combos(char_name)
            local slot_data = combos[combo_edit_slot]
            local tokens    = slot_data.tokens

            -- Clamp cursor — defensive in case tokens shrunk (Backspace,
            -- Clear, or external load). Cursor is 0..#tokens.
            if combo_edit_cursor > #tokens then combo_edit_cursor = #tokens end
            if combo_edit_cursor < 0          then combo_edit_cursor = 0       end

            -- Cursor-aware insert. All token-add sites now route through
            -- this helper so they respect the user's caret position.
            -- Behavior matches a text editor: insert at cursor, then
            -- advance cursor past the new token so consecutive clicks
            -- read left-to-right naturally.
            local function insert_at_cursor(tok)
                -- Spawn a "button strike": a bolt that will fire from the
                -- border arc's last-touched corner to the pressed button. The
                -- press happens at the cursor, so record the cursor position
                -- now; the border-arc draw block renders + expires it (it has
                -- the corner coords, neon color, and particle systems in scope).
                if _SF6UI.arc and _SF6UI.arc.strikes then
                    local st = _SF6UI.arc.strikes
                    local hit = _SF6UI.arc.last_hit   -- rect set by cn_click
                    st[#st+1] = { x = frame_mouse_x, y = frame_mouse_y,
                                  born = os.clock(), fresh = true,
                                  bx = hit and hit.x, by = hit and hit.y,
                                  bw = hit and hit.w, bh = hit and hit.h }
                    if #st > 8 then table.remove(st, 1) end   -- cap
                end
                -- Operate directly on slot_data.tokens (the real array).
                -- The legacy get_combo_slot/set_combo_slot pair returned
                -- the SLOT table itself and relied on a self-reference
                -- (slot.tokens = slot) to make the renderer see writes
                -- to the slot's array part. That self-ref only existed
                -- for combos created from-empty in this session — combos
                -- loaded from JSON had a real `tokens={[1]=..., [2]=...}`
                -- array AND a separate slot table, so #slot was 0 even
                -- when slot.tokens had N entries → table.insert went into
                -- the void.
                local toks = slot_data.tokens
                if not toks then
                    toks = {}
                    slot_data.tokens = toks
                end
                local pos = combo_edit_cursor + 1
                if pos < 1 then pos = 1 end
                if pos > #toks + 1 then pos = #toks + 1 end
                table.insert(toks, pos, tok)
                combo_edit_cursor = pos
                tokens = toks  -- refresh outer local for in-frame readers
                combo_notes_dirty[char_name] = true
            end

            -- DIAG: capture what the Combo Notes window is actually displaying
            detect_diag.cn_char_name  = char_name
            detect_diag.cn_slot1_title = combos[1] and combos[1].title or "?"
            detect_diag.cn_slot1_toks  = combos[1] and #(combos[1].tokens or {}) or 0

            -- ── Full real-zoom entrance ───────────────────────────
            -- The window flies toward the screen: it scales up from a
            -- small size to full size, anchored at the screen center, so
            -- it reads as "coming at you" rather than sliding in.
            --
            -- Because reframework-d2d has no transform/matrix API (only
            -- absolute-coordinate primitives), the zoom is implemented by
            -- multiplying EVERY layout quantity by a live scale factor S
            -- and anchoring positions to the center. The helper sc(n)
            -- scales a pixel count; the derived-position chain (atk_x from
            -- dir_x + dir_pad_w, etc.) then carries the scaling through
            -- automatically. Fonts are fetched at scaled sizes via
            -- get_font(sc(size)).
            --
            -- S uses ease_back_out so it overshoots past 1.0 near the end
            -- then settles to exactly 1.0 (snappy bounce). Start at 0.35
            -- so the grow is dramatic. At cn_p=1, S==1.0 exactly, so the
            -- resting layout is pixel-identical to the unscaled design.
            -- s=1.2 keeps the overshoot small (~3%) so the animation is
            -- dominated by the grow-IN; a larger s (was 3.0) overshot to
            -- ~1.16 and spent most frames shrinking back, which read as the
            -- window starting big and shrinking ("reverse" zoom).
            local zoom_e = _SF6UI.UI.ease_back_out(cn_p, 1.2)
            local S      = 0.08 + 0.92 * zoom_e
            if S > 1.18 then S = 1.18 end
            -- Once the zoom has settled, snap S to exactly 1.0 so the window
            -- is pixel-stable frame to frame. While animating, the per-frame
            -- scale changes by sub-pixel amounts; if the overlay surface ever
            -- retains a prior frame this reads as a faint offset "ghost". A
            -- stable 1.0 eliminates that for the (overwhelmingly common)
            -- settled state.
            if cn_p >= 0.999 then S = 1.0 end
            local function sc(n) return math.floor(n * S) end

            -- Target (full-size) dimensions. The window is taller than the
            -- base layout by PICKER_BAND to make room for the character
            -- picker row that now lives at the top of this window (the
            -- separate Combo Editor pop-up was removed — clicking Combo
            -- Notes opens straight here).
            local PICKER_BAND = 44
            -- Window grown by ~40px each dimension over the base layout so the
            -- thick double border (~17px/side) doesn't clip the edge content
            -- (picker button, slot-list right edge, bottom Close).
            local MW_FULL = 1709
            local MH_FULL = 1031 + PICKER_BAND
            -- Resolve the user-chosen placement (Display menu → "Combo
            -- Notes Pos") into the FULL-size window's top-left, then take
            -- that rect's CENTER as the zoom anchor. The live scaled box is
            -- centered on that anchor point, so it grows from there — the
            -- window flies in toward you from whatever spot is selected,
            -- not always from the middle of the screen.
            local fx, fy = _SF6UI.combo_pos.anchor(
                cfg.combo_notes_pos or "center", sw, sh, MW_FULL, MH_FULL)
            local anchor_cx = fx + MW_FULL / 2
            local anchor_cy = fy + MH_FULL / 2
            local mw  = sc(MW_FULL)
            local mh  = sc(MH_FULL)
            local mx  = math.floor(anchor_cx - mw/2)
            local my  = math.floor(anchor_cy - mh/2)
            local cn_scheme = get_combo_scheme(char_name)
            local cn_scheme_tag = (cn_scheme == "modern") and "  [MODERN]" or "  [CLASSIC]"
            -- Draw the frame at the FULL (outer) rect first.
            -- Header text removed — passing nil draws the panel frame with no
            -- title bar. The character/scheme info lives in the picker row +
            -- title tags inside the window instead.
            draw_menu_panel(mx, my, mw, mh, nil, S)

            -- ── Reaching electric arc with explosion ──────────────────
            -- Per strike: BUILD (pre-charge glow at A) → REACH (bolt grows
            -- A→B) → CONNECT (explosion + particles at B) → LINGER (full bolt
            -- held ~1s) → COLLAPSE (origin A slides along the edge into B, the
            -- bolt shortening forward) → the explosion CRESCENDOS as A arrives,
            -- then dies. Random pause (up to ~30s), then repeat from B. Driven
            -- by the persistent _SF6UI.arc state machine. Suppressed until zoom.
            if cn_p > 0.98 then
                local acc = _SF6UI.THEME.accent_neutral % 0x1000000
                -- Neon version of the accent: push saturation + brightness so
                -- the particles glow like neon rather than the muted UI accent.
                -- Boost the dominant channel toward 255 and lift the others a
                -- little (keeps the hue, intensifies it).
                local neon
                do
                    local r = math.floor(acc / 0x10000) % 0x100
                    local g = math.floor(acc / 0x100)   % 0x100
                    local bl = acc % 0x100
                    local mx_c = math.max(r, g, bl)
                    local function pump(c)
                        if c == mx_c then return 255 end          -- dominant → full
                        return math.min(255, math.floor(c * 1.15 + 40))  -- lift others
                    end
                    neon = pump(r) * 0x10000 + pump(g) * 0x100 + pump(bl)
                end
                local CN = {
                    { mx,      my      },   -- 1 top-left
                    { mx + mw, my      },   -- 2 top-right
                    { mx + mw, my + mh },   -- 3 bottom-right
                    { mx,      my + mh },   -- 4 bottom-left
                }
                local NB  = { {2,4}, {3,1}, {4,2}, {1,3} }   -- corner neighbors
                local A   = _SF6UI.arc
                local now = os.clock()
                A.parts = A.parts or {}
                local function edge_dur(c1, c2)
                    return (CN[c1][2] == CN[c2][2]) and 0.35 or 0.25
                end
                local function rnd()
                    A.seed = ((A.seed or 12345) * 1103515245 + 12345) % 2147483648
                    return A.seed / 2147483648
                end
                -- Phase timings.
                local BUILD_T   = 0.22
                local CONNECT_T = 0.20
                local LINGER_T  = 1.00
                local COLLAPSE_T= 0.45

                -- Spawn an explosion burst of particles at (cx,cy).
                local function spawn(cx, cy, count, power)
                    for _ = 1, count do
                        local ang = rnd() * math.pi * 2
                        -- power is the max initial speed in pixels/second.
                        local spd = (0.35 + rnd()*0.65) * power
                        A.parts[#A.parts+1] = {
                            x = cx, y = cy,
                            vx = math.cos(ang) * spd,
                            vy = math.sin(ang) * spd,
                            born = now,
                            life = 0.45 + rnd()*0.55,
                            r = sc(3 + rnd()*4),
                        }
                    end
                end

                -- Advance the state machine.
                for _ = 1, 6 do
                    local el = now - A.t0
                    if A.phase == "build" then
                        if el >= BUILD_T then A.phase = "reach"; A.t0 = now
                        else break end
                    elseif A.phase == "reach" then
                        if el >= A.dur then
                            A.phase = "connect"; A.t0 = now
                            -- Initial explosion + schedule 1-2 MORE bursts at
                            -- short random delays so it pops 2-3 times total.
                            spawn(CN[A.to][1], CN[A.to][2], 26, sc(620))
                            A.bursts = {}
                            local extra = 1 + math.floor(rnd() * 2)   -- 1 or 2 → 2-3 total
                            local d = 0
                            for n = 1, extra do
                                d = d + 0.10 + rnd() * 0.18           -- stagger
                                A.bursts[#A.bursts+1] = {
                                    at = now + d,
                                    count = 16 + math.floor(rnd()*14),
                                    power = sc(420 + rnd()*320),
                                }
                            end
                        else break end
                    elseif A.phase == "connect" then
                        if el >= CONNECT_T then A.phase = "linger"; A.t0 = now
                        else break end
                    elseif A.phase == "linger" then
                        if el >= LINGER_T then A.phase = "collapse"; A.t0 = now
                        else break end
                    elseif A.phase == "collapse" then
                        if el >= COLLAPSE_T then
                            -- Crescendo burst as the origin arrives at B.
                            spawn(CN[A.to][1], CN[A.to][2], 40, sc(820))
                            A.phase = "pause"; A.t0 = now
                            A.pause = 2.0 + rnd() * 28.0          -- random, ≤~30s
                        else break end
                    else -- pause
                        if el >= (A.pause or 3.0) then
                            -- New strike from the corner we collapsed into (A.to);
                            -- reach to one of its neighbors (avoid bounce-back).
                            local cur  = A.to
                            local nb   = NB[cur]
                            local pick = (rnd() < 0.5) and nb[1] or nb[2]
                            if pick == A.from and rnd() < 0.7 then
                                pick = (nb[1] == A.from) and nb[2] or nb[1]
                            end
                            A.from = cur; A.to = pick
                            A.dur  = edge_dur(A.from, A.to)
                            A.phase = "build"; A.t0 = now
                        else break end
                    end
                end

                local a  = CN[A.from]
                local b  = CN[A.to]
                local el = now - A.t0

                -- flash: stacked translucent circles (charge glow / explosion core).
                local function flash(cx, cy, k, size)
                    if k <= 0 then return end
                    size = size or 1.0
                    local function AL(f) return math.floor(0xFF * f * k) end
                    d2d.fill_circle(cx, cy, sc(46*size), (AL(0.10)*0x1000000) + acc)
                    d2d.fill_circle(cx, cy, sc(28*size), (AL(0.22)*0x1000000) + acc)
                    d2d.fill_circle(cx, cy, sc(14*size), (AL(0.48)*0x1000000) + 0xFFFFFF)
                    d2d.fill_circle(cx, cy, sc(6*size),  (AL(0.92)*0x1000000) + 0xFFFFFF)
                end

                -- Determine the bolt's two endpoints (origin op, head hp) by phase.
                local op, hp = 0, 0    -- fractions along edge A→B (0=A, 1=B)
                local show_bolt = true
                if A.phase == "build" then
                    op, hp = 0, 0
                    show_bolt = false
                    flash(a[1], a[2], 0.3 + 0.7*(el/BUILD_T), 0.5)   -- pre-charge at A
                elseif A.phase == "reach" then
                    local r = math.min(1, el / A.dur); r = r*r*(3-2*r)
                    op, hp = 0, r
                elseif A.phase == "connect" then
                    op, hp = 0, 1
                elseif A.phase == "linger" then
                    op, hp = 0, 1
                elseif A.phase == "collapse" then
                    local c = math.min(1, el / COLLAPSE_T); c = c*c*(3-2*c)
                    op, hp = c, 1                                    -- origin slides to B
                else
                    show_bolt = false
                end

                if show_bolt then
                    local sx = a[1] + (b[1]-a[1]) * op
                    local sy = a[2] + (b[2]-a[2]) * op
                    local hx = a[1] + (b[1]-a[1]) * hp
                    local hy = a[2] + (b[2]-a[2]) * hp
                    _SF6UI.UI.lightning(sx, sy, hx, hy, {
                        glow = acc, core_w = sc(4), speed = 22, chaos = 0.09,
                        levels = 5, branches = 1, intensity = 1.0,
                        seed = A.from*4 + A.to })
                    -- Three thinner companion bolts with extra branches, sharing
                    -- the same endpoints but with their own seeds + higher chaos
                    -- so they fork and weave around the main bolt — chaotic
                    -- crackle. Slightly dimmer than the core bolt.
                    local cbase = A.from*40 + A.to*7
                    _SF6UI.UI.lightning(sx, sy, hx, hy, {
                        glow = acc, core_w = sc(2), speed = 26, chaos = 0.16,
                        levels = 5, branches = 3, intensity = 0.6, seed = cbase+1 })
                    _SF6UI.UI.lightning(sx, sy, hx, hy, {
                        glow = acc, core_w = sc(2), speed = 30, chaos = 0.20,
                        levels = 5, branches = 3, intensity = 0.5, seed = cbase+2 })
                    _SF6UI.UI.lightning(sx, sy, hx, hy, {
                        glow = acc, core_w = sc(1), speed = 34, chaos = 0.24,
                        levels = 5, branches = 4, intensity = 0.45, seed = cbase+3 })
                    if A.phase == "reach" then flash(hx, hy, 0.6, 0.5) end
                end

                -- Explosion flash at B: pops on connect, and CRESCENDOS during
                -- collapse (peaks as the origin arrives), then dies.
                if A.phase == "connect" then
                    local k = 1 - math.min(1, el / CONNECT_T)
                    flash(b[1], b[2], 0.7 + 0.5*k*k, 1.2)
                elseif A.phase == "collapse" then
                    local c = math.min(1, el / COLLAPSE_T)
                    flash(b[1], b[2], 0.4 + 1.0*c*c, 1.0 + 0.6*c)   -- crescendo
                end

                -- Fire any scheduled repeat bursts whose time has arrived
                -- (2-3 total explosions per connection) with a small flash.
                if A.bursts then
                    for bi = #A.bursts, 1, -1 do
                        local bu = A.bursts[bi]
                        if now >= bu.at then
                            local bxp = bu.bx or b[1]
                            local byp = bu.by or b[2]
                            spawn(bxp, byp, bu.count, bu.power)
                            flash(bxp, byp, 0.6, 0.9)
                            A.bursts[bi] = A.bursts[#A.bursts]; A.bursts[#A.bursts] = nil
                        end
                    end
                end
                -- Dripping: as the explosion settles (connect → linger), let a
                -- few slow embers trickle/drip off the corner at random, so it
                -- doesn't cut off abruptly. Rate tapers over the linger window.
                if A.phase == "connect" or A.phase == "linger" then
                    local drip_p = (A.phase == "connect") and 0.5
                                or (1 - math.min(1, el / LINGER_T)) * 0.35
                    if rnd() < drip_p then
                        local ang = (rnd()*0.8 - 0.4) + math.pi/2   -- mostly downward
                        local spd = sc(40 + rnd()*90)               -- slow embers
                        A.parts[#A.parts+1] = {
                            x = b[1] + (rnd()*2-1)*sc(6),
                            y = b[2] + (rnd()*2-1)*sc(6),
                            vx = math.cos(ang) * spd,
                            vy = math.sin(ang) * spd,
                            born = now,
                            life = 0.6 + rnd()*0.7,
                            r = sc(2 + rnd()*2),
                        }
                    end
                end

                -- Update + draw explosion particles (gravity + fade). Iterate
                -- backwards so we can remove dead ones in place.
                for i = #A.parts, 1, -1 do
                    local p   = A.parts[i]
                    local age = now - p.born
                    if age >= p.life then
                        A.parts[i] = A.parts[#A.parts]; A.parts[#A.parts] = nil
                    else
                        local t  = age            -- seconds since spawn
                        -- vx/vy are pixels-per-second; integrate directly.
                        local px = p.x + p.vx * t
                        local py = p.y + p.vy * t + 0.5 * sc(1400) * t * t   -- gravity
                        local kf = 1 - (age / p.life)                        -- fade
                        local col = (math.floor(0xFF * kf) * 0x1000000)
                                  + (kf > 0.6 and 0xFFFFFF or neon)          -- white hot → neon accent
                        d2d.fill_circle(px, py, math.max(1, p.r * (0.4 + 0.6*kf)), col)
                    end
                end

                -- ── Controller / keyboard input → strike ──────────────
                -- Poll the physical inputs; on a fresh press of one that maps
                -- to an on-screen button, spawn a strike at that button's rect
                -- (registered during the button draw, possibly last frame).
                -- Own rising-edge tracking (arc.prev_input) so we don't disturb
                -- the move-detection system's prev_btn state.
                do
                    local pin = A.prev_input
                    local BR  = A.btn_rects
                    -- physical button idx → registry key
                    local INPUT_MAP = {
                        [BTN.LP]="LP", [BTN.MP]="MP", [BTN.HP]="HP",
                        [BTN.LK]="LK", [BTN.MK]="MK", [BTN.HK]="HK",
                        [BTN.LEFT]="dir4", [BTN.RIGHT]="dir6",
                        [BTN.UP]="dir8",   [BTN.DOWN]="dir2",
                    }
                    for idx, key in pairs(INPUT_MAP) do
                        local downv = false
                        local ok2, fl = pcall(btn_flags, idx)
                        if ok2 and fl and fl ~= 0 then downv = true end
                        if downv and not pin[idx] then
                            -- fresh press → strike the matching button if drawn
                            local rect = BR and BR[key]
                            if rect then
                                A.strikes[#A.strikes+1] = {
                                    x = rect.x + rect.w/2, y = rect.y + rect.h/2,
                                    born = now, fresh = true,
                                    bx = rect.x, by = rect.y, bw = rect.w, bh = rect.h }
                                if #A.strikes > 8 then table.remove(A.strikes, 1) end
                            end
                        end
                        pin[idx] = downv
                    end
                end

                -- ── Button-press strikes ──────────────────────────────
                -- When a combo button was pressed, insert_at_cursor() queued a
                -- strike at the cursor. Fire a chaotic bolt from the arc's
                -- last-touched corner (CN[A.to]) to that point, with the same
                -- explosion + particle burst at the button. Short-lived (~0.3s).
                local STRIKE_T = 0.30
                local src = CN[A.to]
                for si = #A.strikes, 1, -1 do
                    local st  = A.strikes[si]
                    local sage = now - st.born
                    if sage >= STRIKE_T then
                        A.strikes[si] = A.strikes[#A.strikes]; A.strikes[#A.strikes] = nil
                    else
                        -- On the first frame: explosion burst at the button.
                        if st.fresh then
                            st.fresh = false
                            spawn(st.x, st.y, 24, sc(560))
                            -- schedule 1-2 repeat pops, same as corner connects
                            local extra = 1 + math.floor(rnd()*2)
                            local d = 0
                            for _ = 1, extra do
                                d = d + 0.08 + rnd()*0.14
                                A.bursts[#A.bursts+1] = {
                                    at = now + d, count = 12 + math.floor(rnd()*12),
                                    power = sc(360 + rnd()*260),
                                    bx = st.x, by = st.y,   -- burst at the button
                                }
                            end
                        end
                        local k = 1 - (sage / STRIKE_T)           -- fade 1→0
                        -- Main bolt + 3 thinner chaotic companions, corner→button.
                        _SF6UI.UI.lightning(src[1], src[2], st.x, st.y, {
                            glow = acc, core_w = sc(4), speed = 24, chaos = 0.12,
                            levels = 6, branches = 2, intensity = math.max(0.3, k),
                            seed = si*13 + A.to })
                        local sb = si*40 + A.to
                        _SF6UI.UI.lightning(src[1], src[2], st.x, st.y, {
                            glow = acc, core_w = sc(2), speed = 28, chaos = 0.18,
                            levels = 6, branches = 3, intensity = math.max(0.2,k)*0.6, seed = sb+1 })
                        _SF6UI.UI.lightning(src[1], src[2], st.x, st.y, {
                            glow = acc, core_w = sc(2), speed = 32, chaos = 0.22,
                            levels = 6, branches = 3, intensity = math.max(0.2,k)*0.5, seed = sb+2 })
                        _SF6UI.UI.lightning(src[1], src[2], st.x, st.y, {
                            glow = acc, core_w = sc(1), speed = 36, chaos = 0.26,
                            levels = 6, branches = 4, intensity = math.max(0.2,k)*0.45, seed = sb+3 })
                        -- Impact flash at the button.
                        flash(st.x, st.y, 0.5 + 0.5*k, 0.9)

                        -- ── Light up + electrify the struck button ──
                        -- If we captured the button's rect, wash it with a
                        -- neon glow and crackle bolts around/across it while
                        -- the strike is alive (fades with k).
                        if st.bx then
                            local bxr, byr, bwr, bhr = st.bx, st.by, st.bw, st.bh
                            local cxr, cyr = bxr + bwr/2, byr + bhr/2
                            -- Neon glow wash over the button (stacked translucent
                            -- rounded rects, brightest core).
                            local rr = math.floor(math.min(bwr,bhr) * 0.5)
                            d2d.fill_rounded_rect(bxr-sc(6), byr-sc(6), bwr+sc(12), bhr+sc(12),
                                rr, rr, (math.floor(0x55*k)*0x1000000) + neon)
                            d2d.fill_rounded_rect(bxr, byr, bwr, bhr, rr, rr,
                                (math.floor(0x66*k)*0x1000000) + neon)
                            d2d.fill_rounded_rect(bxr+sc(3), byr+sc(3), bwr-sc(6), bhr-sc(6),
                                math.max(1,rr-sc(3)), math.max(1,rr-sc(3)),
                                (math.floor(0x44*k)*0x1000000) + 0xFFFFFF)
                            -- Bright neon outline ring.
                            d2d.rounded_rect(bxr-sc(2), byr-sc(2), bwr+sc(4), bhr+sc(4),
                                rr, rr, sc(2), (math.floor(0xFF*k)*0x1000000) + neon)
                            -- Electric arcs crackling across the button: a few
                            -- short bolts darting between random perimeter points.
                            local na = 4
                            for ai = 1, na do
                                local a1 = (ai/na)*math.pi*2 + now*3
                                local a2 = a1 + math.pi + (rnd()-0.5)
                                local r1 = math.max(bwr,bhr)*0.5
                                _SF6UI.UI.lightning(
                                    cxr + math.cos(a1)*r1*0.8, cyr + math.sin(a1)*r1*0.5,
                                    cxr + math.cos(a2)*r1*0.8, cyr + math.sin(a2)*r1*0.5,
                                    { glow=acc, core_w=sc(2), speed=34, chaos=0.30,
                                      levels=4, branches=1, intensity=math.max(0.25,k)*0.8,
                                      seed = ai*7 + si })
                            end
                        end
                    end
                end
            end

            -- ── Corner + random border lens flares (every 15s) ───────
            -- The diagonal shimmer sweep was removed; what remains is the two
            -- corner flares (top-left fades in early + lingers, bottom-right
            -- builds late) plus three extra flares that pop at pseudo-random
            -- spots along the border at staggered times within the cycle.
            -- Wall-clock driven; suppressed until the zoom-in completes.
            do
                local CYCLE = 15.0
                local phase = (cn_p > 0.98) and (os.clock() % CYCLE) or CYCLE

                -- Shared flare renderer (bloom + 4 spokes), intensity 0..1
                -- and a size scale so the random ones can be a touch smaller.
                local function lens_flare(cx, cy, intensity, size)
                    if intensity <= 0 then return end
                    size = size or 1.0
                    local A = function(f) return math.floor(0xFF * f * intensity) end
                    d2d.fill_circle(cx, cy, sc(46*size), (A(0.10) * 0x1000000) + 0xFFFFFF)
                    d2d.fill_circle(cx, cy, sc(28*size), (A(0.18) * 0x1000000) + 0xFFFFFF)
                    d2d.fill_circle(cx, cy, sc(14*size), (A(0.40) * 0x1000000) + 0xFFFFFF)
                    d2d.fill_circle(cx, cy, sc(5*size),  (A(0.85) * 0x1000000) + 0xFFFFFF)
                    local L = sc(60*size)
                    local sa = (A(0.45) * 0x1000000) + 0xFFFFFF
                    local lt = sc(2)
                    d2d.line(cx - L, cy, cx + L, cy, lt, sa)
                    d2d.line(cx, cy - L, cx, cy + L, lt, sa)
                    d2d.line(cx - L*0.7, cy - L*0.7, cx + L*0.7, cy + L*0.7, lt, sa)
                    d2d.line(cx - L*0.7, cy + L*0.7, cx + L*0.7, cy - L*0.7, lt, sa)
                end

                -- Map a perimeter parameter pp (0..1) to an (x,y) point that
                -- walks the border: 0–0.25 top L→R, 0.25–0.5 right T→B,
                -- 0.5–0.75 bottom R→L, 0.75–1 left B→T.
                local function perimeter(pp)
                    pp = pp % 1
                    if pp < 0.25 then
                        return mx + mw * (pp / 0.25), my
                    elseif pp < 0.5 then
                        return mx + mw, my + mh * ((pp - 0.25) / 0.25)
                    elseif pp < 0.75 then
                        return mx + mw * (1 - (pp - 0.5) / 0.25), my + mh
                    else
                        return mx, my + mh * (1 - (pp - 0.75) / 0.25)
                    end
                end

                -- ── All-random border flares ──
                -- Every flare now appears at a random point along the border
                -- at a random time within the cycle (no more fixed corners).
                -- Each has a per-cycle pseudo-random position + start time,
                -- seeded from the cycle number so the pattern shifts each
                -- cycle (varies) but is stable within a frame. Each pops with
                -- a soft triangular fade in/out. Spread across the full cycle.
                local NUM_FLARES = 5
                local cyc_n = math.floor(os.clock() / CYCLE)   -- which cycle #
                for i = 1, NUM_FLARES do
                    local seed = (cyc_n * 7919 + i * 104729) % 100000
                    local rnd  = function(salt)
                        return ((seed * 9301 + salt * 49297 + 233280) % 233280) / 233280
                    end
                    local FLDUR   = 1.0                     -- seconds each lasts
                    -- staggered start anywhere in the cycle (leaving room at
                    -- the end so the flare finishes before the cycle resets).
                    local t_start = rnd(11) * (CYCLE - FLDUR)
                    local pos     = rnd(23)                 -- perimeter location
                    -- slight per-flare size variation (0.7..1.0) for variety
                    local fsize   = 0.7 + rnd(37) * 0.3
                    local fe      = phase - t_start
                    if fe >= 0 and fe < FLDUR then
                        local ft = fe / FLDUR
                        local inten = (ft < 0.5) and (ft / 0.5) or (1 - (ft - 0.5) / 0.5)
                        inten = inten * inten               -- ease the pop
                        local fx, fy = perimeter(pos)
                        lens_flare(fx, fy, inten, fsize)
                    end
                end
            end
            -- Then inset mx/my/mw/mh to the INNER content rect so all the
            -- edge-anchored content (picker, input pad, slot list, Close)
            -- clears the thick double border (~17px/side) instead of
            -- clipping under it. Every content coordinate keys off these.
            local CN_BORDER = sc(18)
            mx = mx + CN_BORDER
            my = my + CN_BORDER
            mw = mw - CN_BORDER * 2
            mh = mh - CN_BORDER * 2
            -- slot list / input pad widths scale with the box so the
            -- right column and left pad keep their proportions.
            local slot_list_w = sc(240)
            local input_w     = mw - slot_list_w - sc(18)

            -- Independent click state for this window so it can't be
            -- starved by frame_click_pending being consumed by other panels.
            -- open_guard is true for exactly one frame after opening,
            -- blocking spurious clicks from the same click that opened the window.
            local cn_raw_click = imgui.is_mouse_clicked(0) and not combo_notes_open_guard
            -- When the character dropdown is open it's modal: the normal
            -- window controls (inputs, slots, Close, etc.) must NOT consume
            -- clicks, or a click on a dropdown item would also hit whatever
            -- input is drawn beneath it. So gate cn_clicked off while open;
            -- the picker button + dropdown use their own raw flag (pk_click).
            local cn_clicked = cn_raw_click and not profile_dropdown_open
                                            and not show_settings_hk
            combo_notes_open_guard = false  -- clear after one frame
            local function cn_hit(x, y, w, h)
                return frame_mouse_x >= x and frame_mouse_x <= x+w
                   and frame_mouse_y >= y and frame_mouse_y <= y+h
            end
            local function cn_click(x, y, w, h)
                if cn_clicked and cn_hit(x, y, w, h) then
                    cn_clicked = false
                    -- Remember the rect of the button just struck so the
                    -- press-strike can light it up + electrify it.
                    if _SF6UI.arc then
                        _SF6UI.arc.last_hit = { x = x, y = y, w = w, h = h }
                    end
                    return true
                end
                return false
            end
            -- Raw (ungated) click for the character picker button + dropdown,
            -- which must work even though cn_clicked is suppressed while the
            -- dropdown is open. Consumes cn_raw_click on hit so a picker
            -- click doesn't also leak elsewhere.
            local function pk_click(x, y, w, h)
                if cn_raw_click and cn_hit(x, y, w, h) then
                    cn_raw_click = false
                    return true
                end
                return false
            end

            -- Smooth hover ramp: returns a 0..1 value per button id that eases
            -- toward 1 while hovered and back to 0 when not, ~20% per frame, so
            -- buttons fade their highlight in/out instead of snapping. State is
            -- kept in cn_refresh.hover keyed by a stable id string.
            cn_refresh.hover = cn_refresh.hover or {}
            local function hover_amt(id, is_hov)
                local cur = cn_refresh.hover[id] or 0
                local target = is_hov and 1 or 0
                cur = cur + (target - cur) * 0.20
                if cur < 0.01 then cur = 0 end
                if cur > 0.99 then cur = 1 end
                cn_refresh.hover[id] = cur
                return cur
            end

            -- ── Layout geometry (left: input pad) ─────────────
            -- Order L→R: numpad → ATTACKS (P/K + modifiers) → motions → SA.
            -- Attacks sit right next to the numpad so direction+button pairs
            -- (the core of every combo, e.g. 2+MK) are visually adjacent.
            -- NOTE: every base size/gap/offset here is wrapped in sc() so
            -- the whole pad scales with the zoom. Derived positions
            -- (dir_pad_w, atk_x, atk_block_w, mot_x, mot_block_w) are
            -- computed from already-scaled values, so they scale for free.
            local row_h      = sc(cfg.menu_font_size + 8)  -- SCALED row pitch; shadows outer row_h for the whole interior so every downstream use scales with the zoom
            -- Scaled fonts: shadow the outer font_menu/font_button with
            -- zoom-scaled versions so all interior d2d.text calls grow with
            -- the window. get_font caches by size (min 8), so the handful
            -- of distinct sizes hit during the ~10 animation frames cost
            -- almost nothing, and at S==1.0 these resolve to the exact
            -- same sizes as the originals. menu_fs is reused by the
            -- preview/hotkey font math below.
            local menu_fs     = math.max(8, sc(cfg.menu_font_size))
            local font_menu   = get_font(menu_fs, false)
            local font_button = get_font(math.max(8, sc(cfg.button_font_size)), false)
            -- Larger, stroked font for the auxiliary buttons (motion/SA
            -- inputs and the DR/DRC/MW/Oki/F.Kill/CH/PC/SHM/xx mechanics).
            -- Bigger than the base button font so those text labels read
            -- clearly; drawn via d2d_stroked_text for a dark outline.
            -- Scaled with the zoom like every other interior size.
            -- Aux/motion/direction button labels use the clean legible
            -- legend font (Segoe UI bold). aux_fs_base is the MAX size;
            -- each button auto-fits down from it so long labels (41236,
            -- F.Kill, SA2-2) shrink to fit their dome while short ones
            -- (MW, Oki) stay large. font_aux is the base-size handle used
            -- where a label is known-short or as a measure fallback.
            local aux_fs_base = math.max(8, sc(cfg.button_font_size + 8))
            local font_aux = get_legend_font(aux_fs_base)
            -- ── Editor field MOVED TO TOP ─────────────────────────
            -- The "build here" editor box now sits at the top (just below
            -- the picker band), and the input pad + counter/aux + legend all
            -- flow beneath it. These positions are computed here so content_y
            -- (the input pad's top) can start below the editor box, and the
            -- later preview-strip draw code reads ed_top/ed_btm.
            -- Editor box height must match the preview font used to draw it
            -- (preview_fs = menu_fs + 12 → preview_lh = that + 6). 1 title
            -- line + PREVIEW_LINES content lines + padding.
            local ed_preview_fs = menu_fs + sc(12)
            local ed_preview_lh = ed_preview_fs + sc(6)
            local PREVIEW_LINES  = 2
            local ed_h    = sc(4) + ed_preview_lh + PREVIEW_LINES * ed_preview_lh + sc(6)
            local ed_top  = my + row_h + sc(10) + sc(PICKER_BAND)
            local ed_btm  = ed_top + ed_h

            -- content_y (input pad top) now starts below the editor box.
            local content_y  = ed_btm + sc(10)
            -- grid_btm (bottom of the tallest input column) is forward-declared
            -- HERE at the combo-block top level, then assigned later once the
            -- cell sizes are known. It must live at this scope (not inside the
            -- slot-list `do` block) because BOTH the counter bar (inside that
            -- block) and the legend (after it closes) reference it — a `local`
            -- inside the block would be nil for the legend.
            local grid_btm

            -- ── Character picker button (top band) ────────────────
            -- Lives above all the editor content. Clicking toggles the
            -- scrollable character dropdown (rendered LAST so it overlays
            -- the inputs). Reuses the same state the old Combo Editor pop-up
            -- used (profile_dropdown_open / profile_dd_scroll / edit_char_idx).
            local pk_h    = sc(row_h + 6)
            local pk_y    = my + row_h + sc(10)
            local pk_x    = mx + sc(10)
            local pk_w    = sc(300)
            do
                local pk_lbl = "Character:  " .. char_name
                    .. (profile_user_override and "" or "  [auto]")
                local hov = cn_hit(pk_x, pk_y, pk_w, pk_h)
                d2d.fill_rounded_rect(pk_x, pk_y, pk_w, pk_h, sc(5), sc(5),
                    hov and C_BTN_ACTIVE or C_BTN_BG)
                d2d.rounded_rect(pk_x, pk_y, pk_w, pk_h, sc(5), sc(5), 1, C_BTN_BORDER)
                local tw, th = font_menu:measure(pk_lbl)
                d2d.text(font_menu, pk_lbl,
                    pk_x + sc(10), pk_y + (pk_h - th)/2,
                    profile_user_override and C_VALUE or C_LABEL)
                -- caret ▾ on the right
                local cw, ch = font_menu:measure(profile_dropdown_open and "^" or "v")
                d2d.text(font_menu, profile_dropdown_open and "^" or "v",
                    pk_x + pk_w - cw - sc(10), pk_y + (pk_h - ch)/2, C_DIM)
                if pk_click(pk_x, pk_y, pk_w, pk_h) then
                    profile_dropdown_open = not profile_dropdown_open
                    if profile_dropdown_open then
                        local max_s = math.max(0, #ROSTER - 12)
                        profile_dd_scroll = math.max(0,
                            math.min(edit_char_idx - 6, max_s))
                    end
                end
            end

            -- ── "Settings and Hotkeys" button (top-RIGHT, opposite the
            -- character picker) — opens a modal popup with the hotkey
            -- reference + Window Pos control (moved out of the main layout).
            do
                local sh_w = sc(300)
                local sh_h = pk_h
                local sh_x = mx + mw - sc(10) - sh_w
                local sh_y = pk_y
                local hov = cn_hit(sh_x, sh_y, sh_w, sh_h)
                d2d.fill_rounded_rect(sh_x, sh_y, sh_w, sh_h, sc(5), sc(5),
                    hov and C_BTN_ACTIVE or C_BTN_BG)
                d2d.rounded_rect(sh_x, sh_y, sh_w, sh_h, sc(5), sc(5), 1, C_BTN_BORDER)
                local lbl = "Settings and Hotkeys"
                local tw, th = font_menu:measure(lbl)
                d2d.text(font_menu, lbl,
                    sh_x + (sh_w - tw)/2, sh_y + (sh_h - th)/2, C_LABEL)
                if pk_click(sh_x, sh_y, sh_w, sh_h) then
                    show_settings_hk = not show_settings_hk
                end
            end
            local dir_x      = mx + sc(10)
            local dir_cell   = sc(83)
            local dir_gap    = sc(10)
            local dir_pad_w  = dir_cell * 3 + dir_gap * 2
            local MOT_GAP    = sc(22)   -- spacing between motion cols
            local GROUP_GAP  = sc(22)   -- spacing between major button groups
            local atk_cell_w = sc(117)
            local atk_cell_h = sc(83)
            local atk_gap    = sc(12)
            -- Extra vertical gap inserted between the P/K block (rows 1-2)
            -- and the modifier rows (3+), so P/K reads as its own section.
            -- A divider line is drawn in this gap. Modifier rows add this to
            -- their cy; P/K rows (1-2) do not.
            local MOD_GAP    = sc(22)
            -- Attack block: 4 columns (P/K in cols 1-3, CH/PC/SHM in col 4),
            -- sits immediately right of the numpad.
            local atk_x      = dir_x + dir_pad_w + GROUP_GAP
            local atk_block_w = atk_cell_w * 4 + atk_gap * 3
            -- Motion block: 3 cols, right of the attack block.
            -- Motion/SA group is 4 columns wide: col0 (66/44/720), colA, colB
            -- (motions), and colC (Super Arts). The block width must span all
            -- four so right-aligning it against the slot list doesn't overlap.
            local mot_block_w = dir_cell*4 + MOT_GAP*3
            -- Motion inputs + Super Arts group sits directly to the RIGHT of
            -- the P/K block (closest to the punch/kick buttons). The aux block
            -- now takes the far-right slot flush against the slots column.
            -- Everything in the motion/SA group derives from mot_x.
            local mot_x      = atk_x + 3*(atk_cell_w + atk_gap) + GROUP_GAP

            -- Native anti-aliased circles. (Previously these faked a circle
            -- with a per-row fill_rect scanline — ~2r+1 draw calls each, hard
            -- stairstepped edges. The plugin provides real d2d.fill_circle /
            -- d2d.circle, so each is now ONE smooth call.)
            local function fill_circle(cx, cy, r, color)
                d2d.fill_circle(cx, cy, r, color)
            end
            local function outline_circle(cx, cy, r, color)
                -- Real ring outline (replaces the old fill-then-punch-hole).
                d2d.circle(cx, cy, r - 1, 2, color)
            end

            -- Helper: draw a round direction button
            local function dir_btn(col, row_i, label, token_val)
                local cx = dir_x + (col-1)*(dir_cell + dir_gap) + dir_cell/2
                local cy = content_y + (row_i-1)*(dir_cell + dir_gap) + dir_cell/2
                local r  = math.floor((math.floor(dir_cell/2) - 4) * 1.10)
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                -- Register rect keyed by the numpad direction (e.g. "4","6")
                -- so a controller d-pad press can strike + light this button.
                if _SF6UI.arc and _SF6UI.arc.btn_rects then
                    _SF6UI.arc.btn_rects["dir"..tostring(token_val)] = { x=cx-r, y=cy-r, w=r*2, h=r*2 }
                end
                local hva = hover_amt("dir" .. tostring(token_val), hov)
                -- Convex arcade dome (direction buttons use the dir base color)
                _SF6UI.UI.arcade_button(cx, cy, r, _SF6UI.cncol.CN_DIR_BG, hva)
                -- Icon mode: draw the PNG glyph if loaded, else fall back to
                -- the lettered/numeric text label.
                local icon = notation_icon(token_val)
                if icon then
                    local isz = math.floor(r * 1.6)
                    d2d.image(icon, cx - isz/2, cy - isz/2, isz, isz)
                else
                    -- Label (auto-fit legend font to the dome width)
                    local f_lbl = fit_legend_font(label, r*2 - sc(8), aux_fs_base)
                    local tw, th = f_lbl:measure(label)
                    d2d_stroked_text(f_lbl, label,
                        cx - tw/2, cy - th/2,
                        _SF6UI.cncol.CN_DIR_TEXT, sc(1))
                end
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="dir", v=token_val})
                end
            end

            -- Helper: draw a round attack button glyph
            local function atk_btn(col, row_i, label, opts)
                -- opts (optional): { fill=ARGB, stroke=ARGB, display="text",
                -- token="v" } — lets specific aux buttons override the
                -- CN_BTN_COLORS lookup (e.g. DI/DP whose labels collide with
                -- the Modern palette) and draw a colored stroke ring.
                opts = opts or {}
                local cx = atk_x + (col-1)*(atk_cell_w + atk_gap) + atk_cell_w/2
                -- Rows 3+ are the modifier section — push them down by MOD_GAP
                -- so they sit below the P/K divider as a distinct group.
                local mod_off = (row_i >= 3) and MOD_GAP or 0
                local cy = content_y + (row_i-1)*(atk_cell_h + atk_gap) + atk_cell_h/2 + mod_off
                local base_r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 6
                -- Single-strength P/K buttons render 15% larger so the
                -- fist/foot icons read clearly (they were barely visible at
                -- the base size). PP/KK and modifiers keep the base size.
                local PUNCH = {LP=true,MP=true,HP=true}
                local KICK  = {LK=true,MK=true,HK=true}
                local is_pk = PUNCH[label] or KICK[label]
                -- Aux mechanics routed through atk_btn (Drive/Walk). These
                -- get a +10% radius and the larger stroked font; P/K, PP/KK
                -- and Modern attack buttons are unaffected.
                -- Any text-label button that isn't a P/K-icon button — i.e.
                -- Modern (L/M/H/SP/DP/DI/Auto/Throw), OD (PP/KK), and the aux
                -- mechanics (DR/DRC/MW) — gets the larger stroked legend font
                -- and a +10% radius, matching the Classic aux-button styling.
                local is_text = not is_pk
                local r  = is_pk   and math.floor(base_r * 1.27)
                        or is_text and math.floor(base_r * 1.10)
                        or              base_r
                local col_fill = opts.fill or CN_BTN_COLORS[label] or 0xFF666666
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                -- Register this button's rect (keyed by label) so a controller
                -- press of the matching input can strike + light up this button.
                if _SF6UI.arc and _SF6UI.arc.btn_rects then
                    _SF6UI.arc.btn_rects[label] = { x=cx-r, y=cy-r, w=r*2, h=r*2 }
                end
                local hva = hover_amt("atk" .. label .. tostring(col) .. tostring(row_i), hov)
                -- Convex arcade-button dome. P/K buttons carry a white icon,
                -- so dim the gloss (0.4) on them to stop the highlight washing
                -- the fist/foot out; other buttons keep full gloss.
                local gloss = is_pk and 0.4 or 1.0
                _SF6UI.UI.arcade_button(cx, cy, r, col_fill, hva, gloss)
                -- Optional colored stroke ring (e.g. DI yellow, DRv/DR red/blue).
                if opts.stroke then
                    d2d.circle(cx, cy, r - sc(1), sc(opts.stroke_w or 3), opts.stroke)
                end
                -- Glyph: single-strength punch (LP/MP/HP) show the fist icon,
                -- single-strength kick (LK/MK/HK) show the foot icon — if the
                -- PNGs loaded. Strength is conveyed by the dome color. PP/KK
                -- (OD) keep their TEXT label since a lone fist/foot would be
                -- ambiguous against the single buttons. Falls back to text if
                -- the image isn't available.
                local icon = (PUNCH[label] and _SF6UI.img.fist)
                          or (KICK[label]  and _SF6UI.img.foot)
                          or nil
                if icon then
                    -- Icon fills ~88% of the dome diameter so it's clearly
                    -- visible (was ~78%).
                    local isz = math.floor(r * 1.75)
                    d2d.image(icon, cx - isz/2, cy - isz/2, isz, isz)
                else
                    local LETTER_MAP = {LP="P",MP="P",HP="P",LK="K",MK="K",HK="K"}
                    local display = opts.display or LETTER_MAP[label] or label
                    -- All text-label buttons (Modern, OD PP/KK, aux DR/DRC/MW)
                    -- use the auto-fit stroked legend font so they match the
                    -- Classic aux-button styling. Auto-fit keeps longer labels
                    -- (Throw, Auto) inside their dome.
                    local f_lbl = fit_legend_font(display, r*2 - sc(8), aux_fs_base)
                    local tw, th = f_lbl:measure(display)
                    d2d_stroked_text(f_lbl, display,
                        cx - tw/2, cy - th/2,
                        _SF6UI.cncol.CN_BTN_TEXT, sc(1))
                end
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="btn", v=opts.token or label})
                end
            end

            -- ── Direction pad: 3x3 numpad only (7-8-9 / 4-5-6 / 1-2-3) ──
            dir_btn(1,1,notation("7"),"7")
            dir_btn(2,1,notation("8"),"8")
            dir_btn(3,1,notation("9"),"9")
            dir_btn(1,2,notation("4"),"4")
            dir_btn(2,2,notation("5"),"5")
            dir_btn(3,2,notation("6"),"6")
            dir_btn(1,3,notation("1"),"1")
            dir_btn(2,3,notation("2"),"2")
            dir_btn(3,3,notation("3"),"3")

            -- ── Chunk separator button ─────────────────────────────
            -- Sits in the empty space below the numpad. Inserts a {t="sep"}
            -- token which renders as " > " in the preview/ticker — used
            -- to manually break the chunked-group pill backgrounds (e.g.
            -- when two separate confirms aren't logically one chunk but
            -- the auto-chunker glues them). Styling matches the `xx`
            -- cancel button (muted background, _SF6UI.cncol.CN_CANCEL_COL label)
            -- because both serve a separator/punctuation role.
            -- Width spans the full numpad (3 cells + 2 gaps); placed one
            -- row below the numpad's bottom row. The legend block starts
            -- at row-5 baseline so this fits with ~50px of breathing room.
            do
                -- Positioned UNDER the kick buttons (P/K block, below row 2),
                -- spanning the 3-column P/K width. Black glossy fill with a
                -- bright yellow stroke + glow so it stands out as the chunk
                -- separator control.
                local pk_w3  = atk_cell_w * 3 + atk_gap * 2   -- 3-col P/K width
                local sep_x  = atk_x
                local sep_y  = content_y + 2*(atk_cell_h + atk_gap) + sc(8)
                local sep_w  = pk_w3
                local sep_h  = atk_cell_h - sc(8)
                local hov    = hit_rect(sep_x, sep_y, sep_w, sep_h)
                local pr     = math.floor(sep_h / 2)
                local YEL    = 0xFFFFE000

                -- Yellow outer glow: a few expanding rings behind the pill.
                for ring = 3, 1, -1 do
                    local grow = sc(ring * 2)
                    local a    = math.floor(0x40 / ring)
                    d2d.rounded_rect(sep_x - grow, sep_y - grow,
                        sep_w + grow*2, sep_h + grow*2,
                        pr + grow, pr + grow, sc(2), (a * 0x1000000) + (YEL % 0x1000000))
                end
                -- Soft drop shadow.
                d2d.fill_rounded_rect(sep_x + sc(3), sep_y + sc(3), sep_w, sep_h, pr, pr, 0x66000000)
                -- Black body.
                d2d.fill_rounded_rect(sep_x, sep_y, sep_w, sep_h, pr, pr,
                    hov and 0xFF1A1A1A or 0xFF050505)
                -- Gloss: a brighter translucent highlight across the top half,
                -- inset and rounded, fading the fill toward light at the top
                -- (fakes a convex glossy dome on a flat pill).
                local gloss_h = math.floor(sep_h * 0.45)
                d2d.fill_rounded_rect(sep_x + sc(3), sep_y + sc(2),
                    sep_w - sc(6), gloss_h,
                    math.floor(gloss_h/2), math.floor(gloss_h/2), 0x22FFFFFF)
                d2d.fill_rounded_rect(sep_x + sc(6), sep_y + sc(3),
                    sep_w - sc(12), math.floor(gloss_h*0.6),
                    math.floor(gloss_h/3), math.floor(gloss_h/3), 0x18FFFFFF)
                -- Bright yellow stroke ring (thick, full alpha) on top.
                d2d.rounded_rect(sep_x, sep_y, sep_w, sep_h, pr, pr, sc(3), YEL)
                -- Label.
                local tw, th = font_menu:measure(">")
                d2d.text(font_menu, ">",
                    sep_x + (sep_w - tw)/2,
                    sep_y + (sep_h - th)/2,
                    YEL)
                if cn_click(sep_x, sep_y, sep_w, sep_h) then
                    insert_at_cursor({t="sep"})
                end
            end

            -- ── Motion buttons: 3 cols x 5 rows, right of numpad ──
            -- col 0 (left): empty except row 5 → 720
            -- col A (mid):  236  623  41236  [4]6  360F
            -- col B (right): 214  x2   63214  [2]8  360B
            -- 360F/360B/720 skip the notation toggle (raw=true).
            do
                local col0_x  = mot_x
                local colA_x  = col0_x + dir_cell + MOT_GAP
                local colB_x  = colA_x + dir_cell + MOT_GAP
                -- SA column sits just right of the last motion column.
                local colC_x  = colB_x + dir_cell + MOT_GAP
                -- col 0: 720 (standalone double-spin motion)
                -- col A/B: standard motion inputs (dir tokens)
                -- col C: SA buttons (btn tokens, gold tint)
                -- { col_x, row, display_label, token_val, raw?, is_sa? }
                local motion_cols = {
                    -- col0: PP/KK (OD) on top, then dashes + 720.
                    -- fields: {x, row, display, token, raw?, is_sa?, fill?, is_btn?}
                    { col0_x, 1, "PP",  "PP",  true, false, CN_BTN_COLORS["PP"], true },
                    { col0_x, 2, "KK",  "KK",  true, false, CN_BTN_COLORS["KK"], true },
                    { col0_x, 3, "66",    "66"          },
                    { col0_x, 4, "44",    "44"          },
                    { col0_x, 5, "720",   "720",  true  },
                    -- colA         colB
                    { colA_x, 1, "236",   "236"         },
                    { colB_x, 1, "214",   "214"         },
                    { colA_x, 2, "623",   "623"         },
                    { colB_x, 2, "x2",    "x2"          },
                    { colA_x, 3, "41236", "41236"       },
                    { colB_x, 3, "63214", "63214"       },
                    { colA_x, 4, "[4]6",  "[4]6"        },
                    { colB_x, 4, "[2]8",  "[2]8"        },
                    { colA_x, 5, "360F",  "360F", true  },
                    { colB_x, 5, "360B",  "360B", true  },
                    -- colC: Super Arts
                    { colC_x, 1, "SA1",   "SA1",  true, true },
                    { colC_x, 2, "SA2",   "SA2",  true, true },
                    { colC_x, 3, "SA2-2", "SA2-2",true, true },
                    { colC_x, 4, "SA3",   "SA3",  true, true },
                    { colC_x, 5, "SA3-2", "SA3-2",true, true },
                }
                for _, me in ipairs(motion_cols) do
                    local bx   = me[1]
                    local by   = content_y + (me[2]-1)*(dir_cell + dir_gap)
                    local bcx  = bx + dir_cell/2
                    local bcy  = by + dir_cell/2
                    local r    = math.floor((math.floor(dir_cell/2) - 1) * 1.10)
                    local hov  = hit_rect(bx, by, dir_cell, dir_cell)
                    local is_x2 = me[4] == "x2"
                    local is_sa = me[6] == true
                    local is_btn = me[8] == true     -- PP/KK: emit btn token
                    -- Base (non-hover) fill per type; arcade_button brightens
                    -- on hover itself, so pass the base color + hov flag.
                    local fill = me[7]                       -- explicit (PP/KK)
                              or is_sa  and 0xFF3D3000
                              or is_x2  and 0xFF3A2048
                              or              _SF6UI.cncol.CN_DIR_BG
                    local tcol  = (me[7] and _SF6UI.cncol.CN_BTN_TEXT)
                               or is_sa  and 0xFFFFDD55
                               or is_x2  and 0xFFCC88FF
                               or              _SF6UI.cncol.CN_DIR_TEXT
                    -- Convex arcade dome (matches the rest of the input pad)
                    local mhva = hover_amt("mot" .. tostring(me[3]), hov)
                    _SF6UI.UI.arcade_button(bcx, bcy, r, fill, mhva)
                    -- Icon mode: motion inputs draw their PNG glyph. SA/x2
                    -- buttons aren't motions, so notation_icon returns nil
                    -- for them and they fall back to text correctly.
                    local micon = (not is_sa and not is_x2 and not is_btn) and notation_icon(me[3]) or nil
                    if micon then
                        local isz = math.floor(r * 1.6)
                        d2d.image(micon, bcx - isz/2, bcy - isz/2, isz, isz)
                    else
                        local disp = (me[5] or is_x2) and me[3] or notation(me[3])
                        local f_lbl = fit_legend_font(disp, r*2 - sc(8), aux_fs_base)
                        local lw, lh = f_lbl:measure(disp)
                        d2d_stroked_text(f_lbl, disp, bcx - lw/2, bcy - lh/2, tcol, sc(1))
                    end
                    if cn_click(bx, by, dir_cell, dir_cell) then
                        -- SA + PP/KK are btn tokens; motions are dir tokens.
                        if is_sa or is_btn then
                            insert_at_cursor({t="btn", v=me[4]})
                        else
                            insert_at_cursor({t="dir", v=me[4]})
                        end
                    end
                end
            end

            -- ── Attack buttons ────────────────────────────────
            -- Scheme-aware grid. Classic shows the traditional
            -- LP/MP/HP/LK/MK/HK/PP/KK 8-button pad. Modern swaps in
            -- Capcom's L/SP/DP/DI on row 1 and M/H/Auto/Throw on
            -- row 2 (8 buttons in 2 rows of 4, matching the web
            -- editor's Modern palette). Both schemes share the same
            -- xx/DR/DRC/MW/Oki/F.Kill/CH/PC/SHM tokens below since
            -- those are scheme-agnostic mechanics.
            local cn_is_modern = (get_combo_scheme(char_name) == "modern")
            if cn_is_modern then
                -- Modern palette — token labels emitted (L/M/H/etc.)
                -- match what the gamepad poller writes for Modern
                -- profiles, so on-screen palette presses and gamepad
                -- presses produce identical tokens.
                --   Row 1: L     SP     DP     DI
                --   Row 2: M     H      Auto   Throw
                atk_btn(1, 1, "L")
                atk_btn(2, 1, "SP")
                atk_btn(3, 1, "DP")
                atk_btn(4, 1, "DI")
                atk_btn(1, 2, "M")
                atk_btn(2, 2, "H")
                atk_btn(3, 2, "Auto")
                atk_btn(4, 2, "Throw")
                -- Row 3 cols 1/2 intentionally empty in Modern (no PP/KK
                -- — OD is implicit in Modern's L/M/H + SP combinations).
            else
                -- Classic palette. P/K is now 3 columns wide (PP/KK moved to
                -- the motion group's col0). The aux mechanics form their own
                -- column block to the right (see aux_btn section below).
                atk_btn(1, 1, "LP")
                atk_btn(2, 1, "MP")
                atk_btn(3, 1, "HP")
                atk_btn(1, 2, "LK")
                atk_btn(2, 2, "MK")
                atk_btn(3, 2, "HK")
            end
            -- ── AUX MECHANICS BLOCK (columns right of the P/K buttons) ──
            -- Layout: a short front column of 2 (bottom-aligned) + two full
            -- columns of 5. The P/K block is now 3 columns wide, so the aux
            -- block is anchored just to its right.
            --   front(2)   colB(5)   colC(5)
            --              DRC       Oki
            --              DI        F.Kill
            --              DP        CH
            --   xx         DRv       PC
            --   DR         MW        SHM
            local AUX_GAP   = sc(14)
            local aux_cell  = atk_cell_h            -- square cells
            local aux_pitch = aux_cell + atk_gap
            -- Aux block is 3 columns wide. Push it RIGHT so it sits flush
            -- against the motion group (one GROUP_GAP), closing the empty
            -- band between the P/K block and the motions. Falls back to just
            -- right of the P/K block if that would push it left of P/K.
            local aux_block_w = 3*aux_pitch - atk_gap
            -- Aux block takes the far-right slot, flush against the slots
            -- column (one GROUP_GAP between them), since the motion/SA group
            -- now sits next to the P/K block. Falls back to just right of the
            -- motion group if right-aligning would collide with it.
            local aux_min_x = mot_x + mot_block_w + GROUP_GAP
            local aux_x     = math.max(aux_min_x,
                                       (mx + input_w + 8) - GROUP_GAP - aux_block_w)
            local aux_top   = content_y            -- aligns with P/K row 1
            local aux_r     = math.floor((math.floor(aux_cell/2) - 6) * 1.10)
            -- Unified aux button renderer. acol/arow are 1-based grid coords
            -- within the aux block. opts: { fill, stroke, stroke_w, token,
            -- text_col }. Counter-baked tokens (Oki/F.Kill) pass token.
            local function aux_btn(acol, arow, label, opts)
                opts = opts or {}
                local cx = aux_x + (acol-1)*aux_pitch + aux_cell/2
                local cy = aux_top + (arow-1)*aux_pitch + aux_cell/2
                local r  = aux_r
                local fill = opts.fill or CN_BTN_COLORS[label] or 0xFF666666
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                _SF6UI.UI.arcade_button(cx, cy, r, fill, hov)
                if opts.stroke then
                    d2d.circle(cx, cy, r - sc(1), sc(opts.stroke_w or 3), opts.stroke)
                end
                local disp = opts.display or label
                local f_lbl = fit_legend_font(disp, r*2 - sc(8), aux_fs_base)
                local tw, th = f_lbl:measure(disp)
                d2d_stroked_text(f_lbl, disp, cx - tw/2, cy - th/2,
                    opts.text_col or _SF6UI.cncol.CN_BTN_TEXT, sc(1))
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t = opts.tok_type or "btn",
                                      v = opts.token or label})
                end
            end

            -- Counter-baked prefix shared by Oki + F.Kill.
            local aux_ctr    = slot_data.counter or 0
            local aux_prefix = aux_ctr > 0 and ("+"..aux_ctr)
                           or  aux_ctr < 0 and (tostring(aux_ctr))
                           or  "0"

            -- Front-short column (acol 1): xx, DR — bottom-aligned (rows 4-5).
            aux_btn(1, 4, "xx", { fill = 0xFF252530,
                                  text_col = _SF6UI.cncol.CN_CANCEL_COL })
            aux_btn(1, 5, "DR", { stroke = 0xFF40B8FF, stroke_w = 4 })
            -- Column B (acol 2): DRC, DI, DP, DRv, MW.
            aux_btn(2, 1, "DRC")
            aux_btn(2, 2, "DI",  { stroke = 0xFFFFE000 })
            aux_btn(2, 3, "DP")
            aux_btn(2, 4, "DRv", { stroke = 0xFFC83232 })
            aux_btn(2, 5, "MW")
            -- Column C (acol 3): Oki, F.Kill, CH, PC, SHM.
            aux_btn(3, 1, "Oki", { token = "[" .. aux_prefix .. ":Oki]" })
            aux_btn(3, 2, "F.Kill", { fill = 0xFF8B1A1A, text_col = 0xFFFF9999,
                                      tok_type = "fk", token = aux_prefix })
            aux_btn(3, 3, "CH")
            aux_btn(3, 4, "PC")
            aux_btn(3, 5, "SHM")

            -- ── RIGHT COLUMN: 30-slot scrollable list ────────
            -- The slot list lives in the right column and is anchored to the
            -- TOP of the window (below the picker band) — independent of the
            -- editor field that now occupies the top of the LEFT side and
            -- pushed content_y down. slot_top restores its original position.
            local slot_top = my + row_h + sc(8) + sc(PICKER_BAND)
            -- Divider line between input pad and slot list
            local list_x = mx + input_w + 8
            d2d.line(list_x - 4, slot_top, list_x - 4, slot_top + mh - row_h - 16,
                1, _SF6UI.THEME.divider)

            local list_item_h = row_h + 2
            local cb_size     = menu_fs - 4   -- checkbox square
            local title_x     = list_x + cb_size + 14    -- text starts after checkbox
            -- Fit as many slots as the column height allows (was a fixed 12).
            -- The list starts at slot_top + 16 and runs down to just above
            -- the bottom-button bar. Show up to COMBO_MAX_SLOTS (30); if the
            -- window is too short for all 30, the scroll logic still applies
            -- for the remainder.
            do
                local list_top_y = slot_top + 16
                local list_btm_y = my + mh - (row_h + 4) - 6 - sc(4)
                local fit = math.floor((list_btm_y - list_top_y) / list_item_h)
                cn_refresh.visible = math.max(1, math.min(COMBO_MAX_SLOTS, fit))
            end
            -- Slot list uses the clean legend font (Segoe UI bold) to match
            -- the legend / aux buttons. Sized to the menu font so row
            -- heights/positions are unchanged.
            local font_slot   = get_legend_font(menu_fs)

            -- Reserve a small strip on the right of the header row for
            -- the scroll arrows so they don't overlap the list itself.
            -- ── Slot list + scroll + counter (scoped do/end) ─────
            -- All slot-list rendering locals live inside this do/end so
            -- they don't accumulate against the main chunk's 200-active-
            -- local budget (Lua hard limit). Without this scoping, the
            -- additions for 30-slot scroll support push the script over
            -- the cap and load() fails with "too many local variables".
            -- The block ends just before the token preview strip below;
            -- nothing past that point reads any locals declared here.
            do
                local arr_w   = 26
                local arr_h   = math.floor(list_item_h * 0.85)
                local hdr_x   = list_x
                local hdr_lbl = "Slots  (check = show)"
                d2d.text(font_slot, hdr_lbl,
                    hdr_x, slot_top - 2, C_DIM)

                -- Scroll geometry. Clamp first so a slot-count regression
                -- (someone trims COMBO_MAX_SLOTS later) can't strand the
                -- scroll past the new end.
                local max_scroll = math.max(0, COMBO_MAX_SLOTS - cn_refresh.visible)
                if cn_refresh.notes_scroll < 0           then cn_refresh.notes_scroll = 0           end
                if cn_refresh.notes_scroll > max_scroll  then cn_refresh.notes_scroll = max_scroll  end

                -- Auto-scroll: only fire when the edited slot CHANGES, so
                -- the user's manual scroll position is preserved frame-to-
                -- frame. Without this gate, the auto-scroll would re-snap
                -- to the edited slot every frame, fighting wheel/arrow input.
                if combo_edit_slot ~= cn_refresh.notes_last_edit_slot then
                    if combo_edit_slot < cn_refresh.notes_scroll + 1 then
                        cn_refresh.notes_scroll = math.max(0, combo_edit_slot - 1)
                    elseif combo_edit_slot > cn_refresh.notes_scroll + cn_refresh.visible then
                        cn_refresh.notes_scroll = math.min(max_scroll, combo_edit_slot - cn_refresh.visible)
                    end
                    cn_refresh.notes_last_edit_slot = combo_edit_slot
                end

                -- Scroll arrows positioned at top-right of the slot column
                local arr_up_x = list_x + slot_list_w - arr_w - 4 - (arr_w + 4)
                local arr_dn_x = list_x + slot_list_w - arr_w - 4
                local arr_y    = slot_top - 4
                -- Up arrow
                -- Scroll arrows are only useful when the list is longer than
                -- the visible window. With all 30 slots showing (max_scroll
                -- == 0) there's nothing to scroll, so skip them entirely.
                if max_scroll > 0 then
                do
                    local can = cn_refresh.notes_scroll > 0
                    local hov = can and hit_rect(arr_up_x, arr_y, arr_w, arr_h)
                    d2d.fill_rounded_rect(arr_up_x, arr_y, arr_w, arr_h, sc(4), sc(4),
                        can and (hov and _SF6UI.THEME.btn_hover or _SF6UI.THEME.btn_idle) or 0xFF0D0D0D)
                    d2d.rounded_rect(arr_up_x, arr_y, arr_w, arr_h, sc(4), sc(4), 1,
                        can and _SF6UI.THEME.panel_border or 0xFF2A2A2A)
                    local lw, lh = font_slot:measure("^")
                    d2d.text(font_slot, "^",
                        arr_up_x + (arr_w - lw)/2,
                        arr_y + (arr_h - lh)/2,
                        can and _SF6UI.THEME.text_value or _SF6UI.THEME.text_muted)
                    if can and cn_clicked and cn_hit(arr_up_x, arr_y, arr_w, arr_h) then
                        cn_clicked = false
                        cn_refresh.notes_scroll = cn_refresh.notes_scroll - 1
                    end
                end
                -- Down arrow
                do
                    local can = cn_refresh.notes_scroll < max_scroll
                    local hov = can and hit_rect(arr_dn_x, arr_y, arr_w, arr_h)
                    d2d.fill_rounded_rect(arr_dn_x, arr_y, arr_w, arr_h, sc(4), sc(4),
                        can and (hov and _SF6UI.THEME.btn_hover or _SF6UI.THEME.btn_idle) or 0xFF0D0D0D)
                    d2d.rounded_rect(arr_dn_x, arr_y, arr_w, arr_h, sc(4), sc(4), 1,
                        can and _SF6UI.THEME.panel_border or 0xFF2A2A2A)
                    local lw, lh = font_slot:measure("v")
                    d2d.text(font_slot, "v",
                        arr_dn_x + (arr_w - lw)/2,
                        arr_y + (arr_h - lh)/2,
                        can and _SF6UI.THEME.text_value or _SF6UI.THEME.text_muted)
                    if can and cn_clicked and cn_hit(arr_dn_x, arr_y, arr_w, arr_h) then
                        cn_clicked = false
                        cn_refresh.notes_scroll = cn_refresh.notes_scroll + 1
                    end
                end
                end  -- close: if max_scroll > 0 (scroll arrows)

                -- Render only the visible window of slots
                local first_slot = cn_refresh.notes_scroll + 1
                local last_slot  = math.min(COMBO_MAX_SLOTS, first_slot + cn_refresh.visible - 1)
                for s = first_slot, last_slot do
                    -- Visible-row index (0..VISIBLE-1) drives the y position;
                    -- the slot's real number `s` drives data lookups.
                    local row_idx = s - first_slot
                    local sy   = slot_top + 16 + row_idx * list_item_h
                    local sdat = combos[s]
                    local is_edit = (s == combo_edit_slot)

                -- Highlight active editing row
                if is_edit then
                    -- Pronounced breathing: a stronger sine pulse drives both
                    -- a glowing accent halo (4 wide rings) AND an accent-tinted
                    -- fill over the row, so the selected slot clearly throbs.
                    local pulse = (math.sin(os.clock() * 3.2) + 1) * 0.5   -- 0..1, ~2s cycle
                    local acc_rgb = _SF6UI.THEME.accent_neutral % 0x1000000
                    -- Base active-row fill, then an accent wash that pulses on
                    -- top of it (alpha 0x20..0x60) so the whole row glows.
                    d2d.fill_rounded_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h, sc(5), sc(5),
                        _SF6UI.THEME.row_active_bg)
                    local wash_a = math.floor(0x20 + 0x40 * pulse)
                    d2d.fill_rounded_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h, sc(5), sc(5),
                        (wash_a * 0x1000000) + acc_rgb)
                    -- Glow halo: 4 expanding rings, brighter + wider than before.
                    for ring = 4, 1, -1 do
                        local grow  = sc(ring * 3)
                        local base  = (0xC0 / ring)            -- inner ring brightest
                        local a     = math.floor(base * (0.45 + 0.55 * pulse))
                        local gcol  = (a * 0x1000000) + acc_rgb
                        d2d.rounded_rect(list_x - grow, sy - 1 - grow,
                            slot_list_w - 4 + grow*2, list_item_h + grow*2,
                            sc(5) + grow, sc(5) + grow, sc(1), gcol)
                    end
                    -- Bright accent border on top, thickness pulses 2→3px.
                    local bt = sc(2) + math.floor(pulse + 0.5)
                    d2d.rounded_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h, sc(5), sc(5), bt,
                        _SF6UI.THEME.accent_neutral)
                elseif hit_rect(list_x, sy, slot_list_w - 4, list_item_h) then
                    d2d.fill_rounded_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h, sc(5), sc(5), _SF6UI.THEME.row_hover)
                end

                -- "Show" toggle (mini capsule, matches the Display toggles).
                -- Hit rect stays exactly cb_x/cb_y/cb_size so click logic below
                -- is unchanged.
                local cb_x = list_x + 4
                local cb_y = sy + (list_item_h - cb_size) / 2
                local trk_h = cb_size
                local trk_w = math.floor(cb_size * 1.6)
                local trk_r = trk_h / 2
                local on    = sdat.active
                d2d.fill_rounded_rect(cb_x, cb_y, trk_w, trk_h, trk_r, trk_r,
                    on and _SF6UI.THEME.toggle_on_bg or _SF6UI.THEME.toggle_off_bg)
                d2d.rounded_rect(cb_x, cb_y, trk_w, trk_h, trk_r, trk_r, 1,
                    _SF6UI.THEME.panel_border)
                local knob_r = trk_r - 2
                local knob_cx = on and (cb_x + trk_w - trk_r) or (cb_x + trk_r)
                d2d.fill_circle(knob_cx, cb_y + trk_r, knob_r,
                    on and _SF6UI.THEME.toggle_knob or _SF6UI.THEME.toggle_knob_off)

                -- Slot number prefix (always shown, not editable)
                local prefix = tostring(s) .. ". "
                local pw, _ = font_slot:measure(prefix)
                d2d.text(font_slot, prefix,
                    title_x, sy + (list_item_h - menu_fs)/2,
                    is_edit and C_VALUE or _SF6UI.cncol.CN_DIR_TEXT)

                -- Title (static d2d text)
                local tx2 = title_x + pw
                local title_label = (sdat.title and #sdat.title > 0)
                    and sdat.title or ("Slot " .. s)
                d2d.text(font_slot, title_label,
                    tx2, sy + (list_item_h - menu_fs)/2,
                    is_edit and C_VALUE or _SF6UI.cncol.CN_DIR_TEXT)

                -- ── Click handler: toggle or row body ──────────
                if cn_clicked and cn_hit(list_x, sy, slot_list_w - 4, list_item_h) then
                    if hit_rect(cb_x, cb_y, trk_w, trk_h) then
                        cn_clicked = false
                        if sdat.active then
                            sdat.active = false
                            combo_notes_dirty[char_name] = true
                        elseif count_active(combos) < COMBO_MAX_ACTIVE then
                            sdat.active = true
                            combo_notes_dirty[char_name] = true
                        end
                    else
                        cn_clicked = false
                        combo_edit_slot = s
                        -- New slot: park cursor at end of its tokens so
                        -- new inputs append (matches old default behavior).
                        local newt = combos[s] and combos[s].tokens or {}
                        combo_edit_cursor = #newt
                    end
                end
            end

            -- Scroll position indicator (e.g. "1-12 / 30"), centered
            -- in the slot column directly under the visible list.
            local visible_end = math.min(COMBO_MAX_SLOTS, first_slot + cn_refresh.visible - 1)
            local list_bottom_y = content_y + 16 + cn_refresh.visible * list_item_h
            -- Scroll position indicator ("1-12 / 30") only matters when the
            -- list is scrolled (not all slots visible). When every slot fits,
            -- it's redundant ("1-30 / 30"), so skip it and let the active-
            -- count hint take its place — this also reclaims the vertical
            -- room the Window Pos cycler needs below the list.
            local hint_y
            if cn_refresh.visible < COMBO_MAX_SLOTS then
                local scroll_lbl = first_slot .. "-" .. visible_end .. " / " .. COMBO_MAX_SLOTS
                local sll, _ = font_slot:measure(scroll_lbl)
                d2d.text(font_slot, scroll_lbl,
                    list_x + (slot_list_w - sll) / 2,
                    list_bottom_y + 2, C_DIM)
                hint_y = list_bottom_y + 4 + menu_fs + 2
            else
                hint_y = list_bottom_y + 2
            end

            -- Active count hint — anchored to the bottom of the
            -- *visible* list window.
            local act_count = count_active(combos)
            local hint = act_count .. "/" .. COMBO_MAX_ACTIVE .. " shown on screen"
            local hl, _ = font_slot:measure(hint)
            d2d.text(font_slot, hint,
                list_x + (slot_list_w - hl) / 2,
                hint_y,
                act_count >= COMBO_MAX_ACTIVE and C_BAD or C_DIM)

            -- ── Shared "chip" button style for the bottom-bar controls ──
            -- A rounded rectangular button that echoes the arcade-button look
            -- (drop shadow + body + top-half gloss highlight + border) so the
            -- counter stepper and Back/Clear read as the same family as the
            -- round input buttons. Returns the click result.
            local CHIP_R   = sc(7)
            -- Chip buttons use the SAME legend font (Segoe UI bold) as the
            -- round input buttons so the bottom bar matches the rest of the
            -- UI typographically. Sized so longer labels ("< Back") fit.
            local chip_fs   = math.max(8, sc(cfg.button_font_size + 2))
            local font_chip = get_legend_font(chip_fs)
            local function chip_btn(bx, by, bw, bh, label, opts)
                opts = opts or {}
                local r   = CHIP_R
                local hov = cn_hit(bx, by, bw, bh)
                local base_fill = opts.fill or C_BTN_BG
                local fill = hov and _SF6UI.UI.brighten(base_fill, 26) or base_fill
                -- 1. soft drop shadow
                d2d.fill_rounded_rect(bx + sc(2), by + sc(3), bw, bh, r, r, 0x55000000)
                -- 2. body
                d2d.fill_rounded_rect(bx, by, bw, bh, r, r, fill)
                -- 3. top-half gloss highlight (fakes the convex sheen)
                local gh = math.floor(bh * 0.46)
                d2d.fill_rounded_rect(bx + sc(2), by + sc(2), bw - sc(4), gh,
                    math.max(1, r - sc(2)), math.max(1, r - sc(2)), 0x1AFFFFFF)
                -- 4. border (accent-tinted, matches the panel borders)
                d2d.rounded_rect(bx, by, bw, bh, r, r, sc(1),
                    opts.border or C_BTN_BORDER)
                -- 5. centered label
                local f = opts.font or font_chip
                local tw, th = f:measure(label)
                d2d.text(f, label, bx + (bw - tw)/2, by + (bh - th)/2,
                    opts.txt_col or C_BTN_TEXT)
                return cn_click(bx, by, bw, bh)
            end
            -- Assign grid_btm (forward-declared at the combo-block top level).
            -- Direction/motion columns are 5 rows of dir_cell; the aux block
            -- (right of P/K) is 5 rows of atk_cell_h. Take whichever reaches
            -- lower. Plain assignment (no `local`) so the legend, which draws
            -- after the enclosing slot-list `do` block closes, still sees it.
            grid_btm = math.max(
                content_y + 5*(dir_cell + dir_gap) + sc(8),
                content_y + 5*(atk_cell_h + atk_gap) + sc(8))

            -- ── Bottom bar: Counter | Backspace | Clear (horizontal) ──
            -- A single flat row along the bottom of the input area: the
            -- counter stepper on the left, then the Backspace and Clear
            -- pills, all on one line just above the legend/window border.
            local bar_h    = row_h + sc(8)
            local bar_y    = grid_btm + sc(6)
            local bar_x    = dir_x
            local arrow_w  = sc(28)
            local arrow_h  = bar_h
            local ctr_val  = slot_data.counter or 0
            -- "Counter:" label inline at the far left of the bar.
            local lbl_txt  = "Counter:"
            local lw_lbl, lh_lbl = font_chip:measure(lbl_txt)
            d2d.text(font_chip, lbl_txt,
                bar_x, bar_y + (bar_h - lh_lbl)/2, C_DIM)
            local ctr_y    = bar_y
            local dec_x    = bar_x + lw_lbl + sc(10)
            local val_w    = sc(60)
            -- [ < ] arrow — chip style to match the bottom-bar buttons.
            if chip_btn(dec_x, ctr_y, arrow_w, arrow_h, "<") then
                slot_data.counter = math.max(-120, ctr_val - 1)
                combo_notes_dirty[char_name] = true
            end

            -- Value display (center). The real counter (ctr_val) changes
            -- instantly on click; the DISPLAYED number rolls toward it for a
            -- smooth tween. cn_refresh.ctr_shown holds the animated value;
            -- it eases ~18% of the remaining distance each frame and snaps
            -- when within 0.5 so it lands exactly on the integer.
            cn_refresh.ctr_shown = cn_refresh.ctr_shown or ctr_val
            do
                local diff = ctr_val - cn_refresh.ctr_shown
                if math.abs(diff) < 0.5 then
                    cn_refresh.ctr_shown = ctr_val
                else
                    cn_refresh.ctr_shown = cn_refresh.ctr_shown + diff * 0.18
                end
            end
            local disp_ctr = math.floor(cn_refresh.ctr_shown + 0.5)
            local val_x = dec_x + arrow_w + sc(4)
            local val_str = tostring(disp_ctr)
            if disp_ctr > 0 then val_str = "+" .. val_str end
            local val_col = disp_ctr > 0 and _SF6UI.THEME.accent_ok
                         or disp_ctr < 0 and _SF6UI.THEME.accent_bad
                         or _SF6UI.THEME.text_value
            -- Value chip: same shadow + body + gloss + border as the arrows,
            -- but with a slightly darker recessed body so it reads as a
            -- display rather than a clickable button.
            do
                local r = CHIP_R
                d2d.fill_rounded_rect(val_x + sc(2), ctr_y + sc(3), val_w, arrow_h, r, r, 0x55000000)
                d2d.fill_rounded_rect(val_x, ctr_y, val_w, arrow_h, r, r, _SF6UI.THEME.pill_value_bg)
                local gh = math.floor(arrow_h * 0.46)
                d2d.fill_rounded_rect(val_x + sc(2), ctr_y + sc(2), val_w - sc(4), gh,
                    math.max(1, r - sc(2)), math.max(1, r - sc(2)), 0x12FFFFFF)
                d2d.rounded_rect(val_x, ctr_y, val_w, arrow_h, r, r, sc(1), C_BTN_BORDER)
            end
            local vl, vh = font_chip:measure(val_str)
            d2d.text(font_chip, val_str,
                val_x + (val_w - vl)/2, ctr_y + (arrow_h - vh)/2, val_col)

            -- [ > ] arrow — chip style.
            local inc_x = val_x + val_w + sc(4)
            if chip_btn(inc_x, ctr_y, arrow_w, arrow_h, ">") then
                slot_data.counter = math.min(120, ctr_val + 1)
                combo_notes_dirty[char_name] = true
            end

            -- Reset to 0 on double-click area (click the value display)
            if cn_click(val_x, ctr_y, val_w, arrow_h) then
                slot_data.counter = 0
                combo_notes_dirty[char_name] = true
            end

            -- ── Backspace / Clear (right of the counter, same bar) ─────
            -- Use the shared chip_btn so they match the counter arrows and
            -- the rest of the button family (rounded, gloss, accent border).
            do
                local cb_gap   = sc(14)
                local cb_y     = bar_y
                local cb_h     = bar_h
                local cb_w     = sc(150)
                local cb_x0    = inc_x + arrow_w + cb_gap*2

                if chip_btn(cb_x0, cb_y, cb_w, cb_h, "< Back") then
                    if combo_edit_cursor > 0 and #tokens > 0 then
                        table.remove(tokens, combo_edit_cursor)
                        combo_edit_cursor = combo_edit_cursor - 1
                        combo_notes_dirty[char_name] = true
                    end
                end
                if chip_btn(cb_x0 + cb_w + cb_gap, cb_y, cb_w, cb_h, "Clear") then
                    combos[combo_edit_slot].tokens = {}
                    combo_edit_cursor = 0
                    combo_notes_dirty[char_name] = true
                end
            end

            -- (Window Pos cycler is rendered inside the Hotkey panel below.)



            -- ── Hotkeys + Window Pos: MOVED to the "Settings and Hotkeys"
            -- popup (modal overlay, drawn later, toggled by the top-right
            -- button). The band between the input grid and the legend is now
            -- free; the legend is pulled up to fill it (see preview-strip).
            end  -- close slot-list + counter do/end block (see scope header above)

            -- ── Token preview strip ───────────────────────────────
            -- Anchored just below the direction pad (the tallest column),
            -- fills the empty space down to the bottom buttons.
            local preview_x0   = mx + 10
            local preview_maxw = input_w - 14
            -- Combo "build here" box uses its own larger font so the
            -- assembled combo is easy to read at a glance, independent of
            -- the global menu font. Derived from menu_font_size (+12) so it
            -- still tracks the user's base size + resolution scaling.
            -- get_font caches by size, so this costs nothing per frame.
            local preview_fs   = menu_fs + sc(12)
            local font_preview = get_legend_font(preview_fs)
            local preview_lh   = preview_fs + 6
            -- Dir pad is 5 rows: content_y + 5*(dir_cell+dir_gap) + small gap
            -- Legend starts below the input grid. Both the direction pad and
            -- the packed aux grid are 5 rows tall, so the dir-pad bottom is
            -- the correct shared baseline.
            -- Legend starts below whichever input column is taller. The dir
            -- pad is 5 rows of dir_cell; the atk grid is 5 rows of atk_cell_h
            -- Legend starts below the tallest input column (grid_btm,
            -- computed earlier — before the bottom Counter bar needs it).
            local bh2_calc     = row_h + 4
            local bot_y_calc   = my + mh - bh2_calc - 6

            -- ── Legend block ──────────────────────────────────────
            -- Sits between the input grid and the token preview. Defines
            -- the opaque modifier abbreviations (DR/DRC/MW/CH/PC/SHM/Oki/F.Kill)
            -- that aren't immediately obvious from the button label alone.
            -- Two-column layout to keep vertical footprint compact.
            -- Each entry is { tag, definition, [continuation] }. If a
            -- third element is present, it renders on a second line
            -- indented under the definition — used when a definition
            -- is too long to fit in a single column-width row. Rows
            -- with a continuation count as 2 rows for height budgeting,
            -- and rows that follow them in the same column shift down
            -- by one extra line.
            -- Legend laid out as the SAME 3×4 grid as the aux buttons, so it
            -- reads as a visual map of the button pad:
            --   xx   DR   DRC  DI
            --   DP   DRv  MW   Oki
            --   FK   CH   PC   SHM
            -- Each entry: { tag, definition }. Order is row-major matching
            -- the button positions above.
            local LEGEND_ROWS = {
                { "xx",     "Cancel" },
                { "DR",     "Drive Rush" },
                { "DRC",    "Drive Rush Cancel" },
                { "DI",     "Drive Impact" },
                { "DP",     "Drive Parry" },
                { "DRv",    "Drive Reversal" },
                { "MW",     "Micro-walk" },
                { "Oki",    "Set Counter, ±frames" },
                { "F.Kill", "Frame Kill" },
                { "CH",     "Counter Hit" },
                { "PC",     "Punish Counter" },
                { "SHM",    "Shimmy" },
            }
            local LEGEND_COLS = 4
            local LEGEND_GRID_ROWS = 3
            local legend_top = grid_btm
            -- Legend font: +50% larger than the menu font, clean bold sans.
            local legend_fs  = math.max(8, sc(math.floor(menu_fs * 1.5)))
            local font_legend = get_legend_font(legend_fs)
            local legend_lh  = legend_fs + sc(6)
            -- 3×4 grid; each cell stacks the colored tag over its definition
            -- (2 lines), plus a header line + padding.
            -- Cell = tag line + definition line + generous gap below so rows
            -- don't crowd each other (reduces visual clutter).
            local legend_cell_h = legend_lh * 2 + sc(12)
            local legend_h    = legend_lh + sc(6) + LEGEND_GRID_ROWS * legend_cell_h + sc(14)

            -- ── Bottom-anchored stacking ──────────────────────────
            -- Lay the editor box flush to the bottom (just above the
            -- Backspace/Clear bar) and the legend flush on top of it, so
            -- both hug the lower portion of the window with no floating
            -- gap. Computed here because preview_lh / bot_y_calc / grid_btm
            -- are all already in scope; the later preview-strip code reads
            -- the preview_top/preview_btm we set now.
            -- ── Stacking (editor now at TOP) ──────────────────────
            -- The editor box was moved to the top of the window (ed_top/
            -- ed_btm, computed near content_y). The legend is now anchored
            -- to the BOTTOM on its own, just above the Close pill. The input
            -- pad + counter/aux + Back/Clear occupy the middle (top-anchored
            -- from content_y, which already sits below the editor box).
            local STACK_GAP    = sc(6)
            -- Editor box position = the top band computed earlier.
            local preview_top  = ed_top
            local preview_btm  = ed_btm
            local preview_h    = ed_h
            -- Legend pulled UP to sit just below the input grid (the hotkey
            -- panel that used to occupy this band moved to the Settings popup).
            local close_reserve = (row_h + sc(8)) + sc(8) + sc(6)
            -- Legend anchored to the BOTTOM, flush above the Close pill.
            local legend_top   = (my + mh) - close_reserve - legend_h
            -- Safety: never let it ride up into the input grid.
            if legend_top < grid_btm + STACK_GAP then
                legend_top = grid_btm + STACK_GAP
            end

            d2d.fill_rounded_rect(preview_x0, legend_top,
                preview_maxw, legend_h, sc(6), sc(6), _SF6UI.THEME.panel_bg_inner)
            d2d.rounded_rect(preview_x0, legend_top,
                preview_maxw, legend_h, sc(6), sc(6), 1, _SF6UI.THEME.panel_border)
            d2d.text(font_legend, "Legend",
                preview_x0 + 6, legend_top + 4, _SF6UI.THEME.accent_neutral)

            do
                local col_w = math.floor((preview_maxw - 12) / LEGEND_COLS)
                local grid_y0 = legend_top + 4 + legend_lh + sc(6)
                for i, entry in ipairs(LEGEND_ROWS) do
                    local col_i = (i - 1) % LEGEND_COLS
                    local row_i = math.floor((i - 1) / LEGEND_COLS)
                    local lx = preview_x0 + 6 + col_i * col_w
                    local ly = grid_y0 + row_i * legend_cell_h
                    local tag = entry[1]
                    local tag_col = CN_BTN_COLORS[tag]
                                 or (tag == "F.Kill" and 0xFFFF9999)
                                 or (tag == "xx"     and _SF6UI.cncol.CN_CANCEL_COL)
                                 or C_LABEL
                    -- Tag (colored) on the top line of the cell.
                    d2d.text(font_legend, tag, lx, ly, tag_col)
                    -- Definition (dim) on the second line, wrapped to the
                    -- cell width if needed (simple: drawn as-is; cells are
                    -- wide enough at the 4-col window width).
                    d2d.text(font_legend, entry[2], lx, ly + legend_lh, C_DIM)
                end
            end

            -- preview_top / preview_btm / preview_h / PREVIEW_LINES are
            -- computed up in the legend block (bottom-anchored stacking),
            -- so the box draws directly here.

            -- Background fill for the preview area (the "build here" box).
            -- Given a THICK BREATHING accent border + soft glow so it's the
            -- clear focal point — the user's eye is drawn to where they build.
            local pv_w = preview_maxw
            local pv_h = preview_btm - preview_top
            d2d.fill_rounded_rect(preview_x0, preview_top,
                pv_w, pv_h, sc(7), sc(7), _SF6UI.THEME.panel_bg_inner)
            do
                local pacc = _SF6UI.THEME.accent_neutral % 0x1000000
                local pulse = (math.sin(os.clock() * 2.2) + 1) * 0.5   -- 0..1, ~3s
                -- Outer breathing glow: rings expanding outward, alpha pulses.
                for ring = 4, 1, -1 do
                    local grow = sc(ring * 2)
                    local a    = math.floor((0x50 / ring) * (0.35 + 0.65 * pulse))
                    local gcol = (a * 0x1000000) + pacc
                    d2d.rounded_rect(preview_x0 - grow, preview_top - grow,
                        pv_w + grow*2, pv_h + grow*2,
                        sc(7) + grow, sc(7) + grow, sc(2), gcol)
                end
                -- Thick accent border, full alpha (always solid + crisp).
                d2d.rounded_rect(preview_x0, preview_top, pv_w, pv_h,
                    sc(7), sc(7), sc(4), (0xFF * 0x1000000) + pacc)
                -- Inner bright core line that brightens with the pulse, so the
                -- border itself appears to breathe (not just the outer glow).
                local cb = _SF6UI.UI.brighten(pacc, math.floor(80 * pulse))
                d2d.rounded_rect(preview_x0 + sc(3), preview_top + sc(3),
                    pv_w - sc(6), pv_h - sc(6),
                    math.max(1, sc(7) - sc(3)), math.max(1, sc(7) - sc(3)),
                    sc(2), (0xFF * 0x1000000) + cb)
            end

            -- Slot label
            local label_y = preview_top + 4
            -- Slot title label. (Was calling row_label(), which is a helper
            -- scoped to the Display window block — nil here in the combo
            -- block, so the call threw and aborted the editor + everything
            -- after it. Draw the text directly with the preview font.)
            d2d.text(font_preview,
                tostring(combo_edit_slot) .. ". " .. slot_data.title .. ":",
                preview_x0 + 6, label_y, C_DIM)

            -- Tokens — wrapping. Each token gets two click hit zones
            -- (left half / right half) so the user can position the
            -- insert cursor before or after it, like a text editor.
            -- Token bounds are also recorded so we can draw the caret
            -- at the right gap after the loop.
            local px2 = preview_x0 + 6
            local py2 = label_y + preview_lh
            -- caret_x/caret_y/caret_h tracks where to draw the vertical bar.
            -- Initially before token 1 (cursor=0) at the start of the line.
            local caret_x = px2 - 2
            local caret_y = py2 + 2
            local caret_h = preview_lh - 4
            local last_tok_right = px2  -- updated each iter; used when cursor==#tokens

            -- Standalone btns (mirrors ticker STANDALONE_BTNS): emit
            -- their own chunk and get a '>' separator before them.
            local PV_STANDALONE = { DR=true, DRC=true, CH=true, PC=true, SHM=true,
                                    SA1=true, SA2=true, ["SA2-2"]=true,
                                    SA3=true, ["SA3-2"]=true }

            -- Track whether the previous token ended a chunk. If so, the
            -- next dir or standalone gets a '>' separator drawn.
            local prev_ended_chunk = false

            for ti, tok in ipairs(tokens) do
                local tlabel
                local is_xx = tok.t == "xx" or (tok.t == "btn" and tok.v == "xx")
                local is_fk = tok.t == "fk"
                local is_sep = tok.t == "sep"
                local is_standalone = tok.t == "btn" and PV_STANDALONE[tok.v]
                local is_dir = tok.t == "dir"
                if is_xx then
                    tlabel = "xx"
                elseif is_fk then
                    -- New tokens carry `v` with the baked counter
                    -- (e.g. "+5"); legacy tokens have no v and render
                    -- as plain "F.Kill".
                    tlabel = (tok.v and #tok.v > 0)
                        and ("F.Kill " .. tok.v)
                        or  "F.Kill"
                elseif is_sep then
                    -- Manual chain separator from editor — just renders as '>'.
                    tlabel = ">"
                elseif tok.t == "dir" then
                    tlabel = notation(tok.v)
                elseif tok.t == "btn" then
                    tlabel = "[" .. tok.v .. "]"
                end

                -- Decide if a '>' separator should be drawn BEFORE this token.
                -- Rules: a new chunk starts on (a) a direction that comes
                -- after a previous chunk ended, or (b) a standalone btn
                -- (DR/DRC/CH/PC/SHM/SA*) that comes after a previous chunk.
                -- xx, fk, and sep markers are themselves separators; nothing
                -- extra needed before them. Also suppress auto-'>' when the
                -- previous token was a manual sep (it already drew its own).
                local prev_was_sep = ti > 1 and tokens[ti-1].t == "sep"
                local needs_sep = prev_ended_chunk and not is_xx and not is_fk
                                  and not is_sep and not prev_was_sep
                                  and (is_dir or is_standalone)

                if tlabel then
                    -- Punch/kick btn tokens (LP/MP/HP/LK/MK/HK) show the
                    -- fist/foot icon instead of the bracketed "[LP]" text,
                    -- matching the editor buttons + ticker. The icon occupies
                    -- a fixed square slot so the wrap/click/caret math (all
                    -- driven by tw2 below) stays consistent.
                    local PV_PUNCH = {LP=true,MP=true,HP=true}
                    local PV_KICK  = {LK=true,MK=true,HK=true}
                    -- Punch/kick btn tokens → fist/foot icon on a colored
                    -- (L/M/H) circle. Direction/motion tokens → the input
                    -- glyph PNG (when icon notation mode is active), drawn
                    -- plain with no colored backing. tok_btn_icon marks the
                    -- colored-circle case; tok_dir_icon the plain case.
                    local tok_btn_icon = (tok.t == "btn")
                        and ((PV_PUNCH[tok.v] and _SF6UI.img.fist)
                          or (PV_KICK[tok.v]  and _SF6UI.img.foot))
                        or nil
                    local tok_dir_icon = (tok.t == "dir") and notation_icon(tok.v) or nil
                    local tok_icon = tok_btn_icon or tok_dir_icon
                    local icon_sz = math.floor(preview_fs * 1.1)

                    -- Pre-measure separator if needed.
                    local sep_w = 0
                    if needs_sep then
                        local sw, _ = font_preview:measure(">")
                        sep_w = sw + 8  -- pad on either side
                    end

                    -- Token width: icon slot for icon tokens, else text.
                    local tw2
                    if tok_icon then
                        tw2 = icon_sz
                    else
                        tw2 = font_preview:measure(tlabel)
                    end
                    if px2 + sep_w + tw2 + 4 > preview_x0 + preview_maxw - 4 then
                        px2 = preview_x0 + 6
                        py2 = py2 + preview_lh
                        if py2 + preview_lh > preview_btm then break end
                    end

                    -- Draw separator (faint, like in the ticker).
                    if needs_sep then
                        d2d.text(font_preview, ">",
                            px2 + 2,
                            py2 + (preview_lh - preview_fs)/2,
                            _SF6UI.cncol.CN_CANCEL_COL)
                        px2 = px2 + sep_w
                    end

                    local tcol = is_xx and _SF6UI.cncol.CN_CANCEL_COL
                             or is_fk and 0xFFFF9999
                             or is_sep and _SF6UI.cncol.CN_CANCEL_COL
                             or (tok.t == "btn") and (CN_BTN_COLORS[tok.v] or C_LABEL)
                             or _SF6UI.cncol.CN_DIR_TEXT

                    -- Highlight token under mouse — visual cue this is clickable.
                    local tok_x, tok_y, tok_w, tok_h = px2 - 2, py2, tw2 + 4, preview_lh
                    if cn_hit(tok_x, tok_y, tok_w, tok_h) then
                        d2d.fill_rect(tok_x, tok_y, tok_w, tok_h, 0x22FFFFFF)
                    end

                    if tok_btn_icon then
                        -- Colored circle behind the fist/foot conveys the
                        -- button strength (L=blue, M=yellow, H=red), matching
                        -- the editor buttons and ticker.
                        local icol = CN_BTN_COLORS[tok.v] or 0xFF666666
                        local ir   = math.floor(icon_sz / 2)
                        local icx  = px2 + ir
                        local icy  = py2 + preview_lh/2
                        d2d.fill_circle(icx, icy, ir, icol)
                        d2d.circle(icx, icy, ir, 1, 0x66000000)
                        local isz = math.floor(icon_sz * 0.82)
                        d2d.image(tok_btn_icon, icx - isz/2, icy - isz/2, isz, isz)
                    elseif tok_dir_icon then
                        -- Direction/motion glyph: drawn plain (no colored
                        -- backing — these aren't strength-coded).
                        d2d.image(tok_dir_icon, px2,
                            py2 + (preview_lh - icon_sz)/2, icon_sz, icon_sz)
                    else
                        d2d.text(font_preview, tlabel, px2,
                            py2 + (preview_lh - preview_fs)/2, tcol)
                    end

                    -- Click zones: left half → cursor before this token (ti-1);
                    -- right half → cursor after this token (ti).
                    local mid = tok_x + math.floor(tok_w / 2)
                    if cn_click(tok_x, tok_y, mid - tok_x, tok_h) then
                        combo_edit_cursor = ti - 1
                    elseif cn_click(mid, tok_y, tok_x + tok_w - mid, tok_h) then
                        combo_edit_cursor = ti
                    end

                    -- Caret position update: if cursor lands before this
                    -- token's index, anchor the caret at this token's left.
                    if combo_edit_cursor == ti - 1 then
                        caret_x = tok_x
                        caret_y = tok_y + 2
                        caret_h = tok_h - 4
                    end

                    px2 = px2 + tw2 + 4
                    last_tok_right = px2

                    -- Update chunk-tracking state for next iteration's
                    -- separator decision:
                    --   - xx / fk / sep: explicit separator already, next chunk
                    --     starts cleanly. Don't draw another '>'.
                    --   - btn (any kind): closes the chunk it ended.
                    --   - dir: opens a new chunk; the chunk only closes
                    --     when a btn or another standalone shows up.
                    if is_xx or is_fk or is_sep then
                        prev_ended_chunk = false  -- separator already drawn
                    elseif tok.t == "btn" then
                        prev_ended_chunk = true
                    else
                        -- dir: still inside a chunk (waiting for the btn)
                        prev_ended_chunk = false
                    end
                end
            end
            -- Cursor at the very end (after last token).
            if combo_edit_cursor >= #tokens and #tokens > 0 then
                caret_x = last_tok_right - 2
                caret_y = py2 + 2
                caret_h = preview_lh - 4
            elseif #tokens == 0 then
                caret_x = preview_x0 + 6
                caret_y = label_y + preview_lh + 2
                caret_h = preview_lh - 4
            end

            -- Draw caret — solid vertical bar, slow blink (frame_counter
            -- is the ambient frame tick declared elsewhere). Half-cycle
            -- ~30 frames = 0.5s on/off at 60 fps.
            if math.floor((frame_counter or 0) / 30) % 2 == 0 then
                d2d.fill_rect(caret_x, caret_y, 2, caret_h, 0xFFE0E0FF)
            end

            -- ── Close button (bottom-right under the editor field) ──
            -- Matches the bottom-bar chip styling (rounded + gloss + border).
            -- chip_btn lives in the slot-list scope (closed above), so draw
            -- the same look inline here.
            do
                local cl_w   = sc(96)
                local cl_h   = row_h + sc(8)
                local cl_x   = (preview_x0 + preview_maxw) - cl_w
                local cl_y   = my + mh - cl_h - sc(8)
                local r      = sc(7)
                local hov    = cn_hit(cl_x, cl_y, cl_w, cl_h)
                local fill   = hov and _SF6UI.UI.brighten(C_BTN_BG, 26) or C_BTN_BG
                -- shadow → body → top gloss → border → label
                d2d.fill_rounded_rect(cl_x + sc(2), cl_y + sc(3), cl_w, cl_h, r, r, 0x55000000)
                d2d.fill_rounded_rect(cl_x, cl_y, cl_w, cl_h, r, r, fill)
                local gh = math.floor(cl_h * 0.46)
                d2d.fill_rounded_rect(cl_x + sc(2), cl_y + sc(2), cl_w - sc(4), gh,
                    math.max(1, r - sc(2)), math.max(1, r - sc(2)), 0x1AFFFFFF)
                d2d.rounded_rect(cl_x, cl_y, cl_w, cl_h, r, r, sc(1), C_BTN_BORDER)
                local cl_font = get_legend_font(math.max(8, sc(cfg.button_font_size + 2)))
                local tw, th = cl_font:measure("Close")
                d2d.text(cl_font, "Close",
                    cl_x + (cl_w - tw)/2, cl_y + (cl_h - th)/2, C_BTN_TEXT)
                if cn_click(cl_x, cl_y, cl_w, cl_h) then
                    show_combo_notes_win = false
                end
            end

            -- ── Character dropdown overlay (drawn LAST → on top) ──
            -- When the picker button (top band) is open, draw the scrollable
            -- list here so it overlays the inputs instead of being painted
            -- under them. Selecting a character queues a notes load.
            if profile_dropdown_open then
                -- Cleaner look: the clean legend font (Segoe UI bold), a bit
                -- larger than the menu font, with taller rows so the names
                -- have breathing room.
                local dd_fs     = menu_fs + sc(4)
                local dd_font   = get_legend_font(dd_fs)
                local dd_vis    = 12
                local dd_item_h = sc(row_h + 12)
                local dd_list_h = dd_vis * dd_item_h
                local lx = pk_x
                local ly = pk_y + pk_h + sc(2)
                local list_w = pk_w
                local arr_w  = sc(28)
                local arr_x  = lx + list_w + sc(4)
                local arr_h  = math.floor(dd_list_h / 2) - sc(2)

                local max_scroll_dd = math.max(0, #ROSTER - dd_vis)
                profile_dd_scroll = math.max(0, math.min(profile_dd_scroll, max_scroll_dd))

                -- List background (rounded for a cleaner frame)
                d2d.fill_rounded_rect(lx, ly, list_w, dd_list_h, sc(6), sc(6), 0xFF1A1A24)
                d2d.rounded_rect(lx, ly, list_w, dd_list_h, sc(6), sc(6), 1, 0xFF8080AA)

                -- ^ up
                local hov_up = cn_hit(arr_x, ly, arr_w, arr_h)
                d2d.fill_rounded_rect(arr_x, ly, arr_w, arr_h, sc(4), sc(4), hov_up and C_BTN_ACTIVE or C_BTN_BG)
                d2d.rounded_rect(arr_x, ly, arr_w, arr_h, sc(4), sc(4), 1, C_BTN_BORDER)
                local ul, uh = dd_font:measure("^")
                d2d.text(dd_font, "^", arr_x+(arr_w-ul)/2, ly+(arr_h-uh)/2, C_BTN_TEXT)
                if pk_click(arr_x, ly, arr_w, arr_h) then
                    profile_dd_scroll = math.max(0, profile_dd_scroll - dd_vis)
                end
                -- v down
                local dn_y = ly + arr_h + sc(4)
                local hov_dn = cn_hit(arr_x, dn_y, arr_w, arr_h)
                d2d.fill_rounded_rect(arr_x, dn_y, arr_w, arr_h, sc(4), sc(4), hov_dn and C_BTN_ACTIVE or C_BTN_BG)
                d2d.rounded_rect(arr_x, dn_y, arr_w, arr_h, sc(4), sc(4), 1, C_BTN_BORDER)
                local dl, dh = dd_font:measure("v")
                d2d.text(dd_font, "v", arr_x+(arr_w-dl)/2, dn_y+(arr_h-dh)/2, C_BTN_TEXT)
                if pk_click(arr_x, dn_y, arr_w, arr_h) then
                    profile_dd_scroll = math.min(max_scroll_dd, profile_dd_scroll + dd_vis)
                end

                -- Items
                for vi = 0, dd_vis - 1 do
                    local i = vi + profile_dd_scroll + 1
                    if i > #ROSTER then break end
                    local n  = ROSTER[i]
                    local iy = ly + vi * dd_item_h
                    local is_sel = (i == edit_char_idx)
                    if is_sel then
                        d2d.fill_rect(lx, iy, list_w, dd_item_h, 0xFF2E2E48)
                    elseif cn_hit(lx, iy, list_w, dd_item_h) then
                        d2d.fill_rect(lx, iy, list_w, dd_item_h, 0xFF252535)
                    end
                    d2d.fill_rect(lx+sc(8), iy + dd_item_h - 1, list_w-sc(16), 1, 0xFF2A2A3A)
                    local _, nh = dd_font:measure(n)
                    d2d.text(dd_font, n, lx + sc(12), iy + (dd_item_h - nh)/2,
                        is_sel and 0xFFFFE066 or 0xFFE0E0E0)
                    if pk_click(lx, iy, list_w, dd_item_h) then
                        edit_char_idx            = i
                        profile_user_override    = true
                        profile_dropdown_open    = false
                        combo_edit_slot          = 1
                        combo_edit_cursor        = 0
                        combo_notes_load_pending = n
                        notes_load_pending       = n
                    end
                end
                -- Click anywhere else (still unconsumed) closes the dropdown
                -- without selecting — standard dismiss behavior.
                if cn_raw_click then
                    profile_dropdown_open = false
                end
            end

            -- ── "Settings and Hotkeys" popup (modal overlay, drawn LAST) ──
            -- Holds the controller/keyboard hotkey reference and the Window
            -- Pos cycler, moved out of the main layout. Toggled by the top-
            -- right button. Click outside the panel to dismiss.
            local sp_p = _SF6UI.UI.anim_time("settings_hk", show_settings_hk, 0.28)
            if show_settings_hk or sp_p > 0.001 then
                -- Dim the rest of the window behind the popup (fades with p).
                local dim_a = math.floor(0xB0 * sp_p)
                d2d.fill_rect(mx, my, mw, mh, (dim_a * 0x1000000))
                -- Zoom-in: panel scales from small → full with a slight
                -- overshoot, anchored at its center. Content draws at full
                -- size but only once the panel has mostly arrived (fades in),
                -- so we don't have to rescale every inner element.
                local sp_zoom = _SF6UI.UI.ease_back_out(sp_p, 1.4)
                local sp_S    = 0.4 + 0.6 * sp_zoom
                if sp_S > 1.12 then sp_S = 1.12 end
                local sp_w_full = sc(640)
                local sp_h_full = sc(360)
                local sp_w = math.floor(sp_w_full * sp_S)
                local sp_h = math.floor(sp_h_full * sp_S)
                local sp_cx = mx + mw/2
                local sp_cy = my + mh/2
                local sp_x = math.floor(sp_cx - sp_w/2)
                local sp_y = math.floor(sp_cy - sp_h/2)
                -- Panel bg + accent border (drawn at the animated size).
                local sp_acc = (0xFF * 0x1000000) + (_SF6UI.THEME.accent_neutral % 0x1000000)
                d2d.fill_rounded_rect(sp_x, sp_y, sp_w, sp_h, sc(8), sc(8), _SF6UI.THEME.panel_bg_inner)
                d2d.rounded_rect(sp_x, sp_y, sp_w, sp_h, sc(8), sc(8), sc(3), sp_acc)

                -- Content fades/draws in only once the panel is ~arrived, and
                -- positions key off the FULL-size rect so nothing jumps when
                -- the zoom settles. While zooming in, skip the inner content.
                if sp_p > 0.55 then
                  sp_w = sp_w_full; sp_h = sp_h_full
                  sp_x = math.floor(sp_cx - sp_w/2)
                  sp_y = math.floor(sp_cy - sp_h/2)
                -- Panel bg + accent border.
                local sp_acc = (0xFF * 0x1000000) + (_SF6UI.THEME.accent_neutral % 0x1000000)
                d2d.fill_rounded_rect(sp_x, sp_y, sp_w, sp_h, sc(8), sc(8), _SF6UI.THEME.panel_bg_inner)
                d2d.rounded_rect(sp_x, sp_y, sp_w, sp_h, sc(8), sc(8), sc(3), sp_acc)

                local sp_fs   = menu_fs + sc(4)
                local sp_font = get_legend_font(sp_fs)
                local sp_lh   = sp_fs + sc(8)
                local sp_pad  = sc(16)
                -- Title
                d2d.text(sp_font, "Settings and Hotkeys",
                    sp_x + sp_pad, sp_y + sp_pad, _SF6UI.THEME.accent_neutral)

                -- Two columns: Hotkeys (left) + Keyboard (right).
                local sp_colL = sp_x + sp_pad
                local sp_colR = sp_x + math.floor(sp_w / 2) + sp_pad/2
                local body_y0 = sp_y + sp_pad + sp_lh + sc(8)

                d2d.text(sp_font, "Hotkeys",  sp_colL, body_y0, _SF6UI.THEME.accent_neutral)
                d2d.text(sp_font, "Keyboard", sp_colR, body_y0, C_DIM)

                local function sp_row(colx, row_idx, tag, tag_col, desc)
                    local ly = body_y0 + sp_lh * row_idx
                    d2d.text(sp_font, tag, colx, ly, tag_col)
                    local tw, _ = sp_font:measure(tag)
                    d2d.text(sp_font, "  " .. desc, colx + tw, ly, C_DIM)
                end

                -- Left: controller modifier
                do
                    local ly = body_y0 + sp_lh * 1
                    local mp_col = CN_BTN_COLORS["MP"] or C_LABEL
                    local lk_col = CN_BTN_COLORS["LK"] or C_LABEL
                    d2d.text(sp_font, "Hold ", sp_colL, ly, C_DIM)
                    local pre_w = sp_font:measure("Hold ")
                    d2d.text(sp_font, "MP", sp_colL + pre_w, ly, mp_col)
                    local mp_w = sp_font:measure("MP")
                    d2d.text(sp_font, "+", sp_colL + pre_w + mp_w, ly, C_DIM)
                    local plus_w = sp_font:measure("+")
                    d2d.text(sp_font, "LK", sp_colL + pre_w + mp_w + plus_w, ly, lk_col)
                end
                sp_row(sp_colL, 2, "HP", CN_BTN_COLORS["HP"] or C_LABEL, "= insert  >")
                sp_row(sp_colL, 3, "LP", CN_BTN_COLORS["LP"] or C_LABEL, "= backspace")
                -- Right: keyboard
                sp_row(sp_colR, 1, "<- ->",    C_LABEL, "= move cursor")
                sp_row(sp_colR, 2, "Home/End", C_LABEL, "= jump")
                sp_row(sp_colR, 3, "Bksp",     C_LABEL, "= delete")

                -- Window Pos cycler (left column, below the hotkeys)
                do
                    local pos_ly = body_y0 + sp_lh * 5
                    d2d.text(sp_font, "Window Pos:", sp_colL, pos_ly, C_DIM)
                    local pos_x = sp_colL + sp_font:measure("Window Pos:  ")
                    local pos_h = sp_lh
                    local pos_w = sc(180)
                    local cp_order = _SF6UI.combo_pos.ORDER
                    local cp_cur   = cfg.combo_notes_pos or "center"
                    local cp_idx   = 1
                    for i, k in ipairs(cp_order) do
                        if k == cp_cur then cp_idx = i break end
                    end
                    local cp_label = _SF6UI.combo_pos.LABELS[cp_cur] or cp_cur
                    local hov_pos = hit_rect(pos_x, pos_ly, pos_w, pos_h)
                    d2d.fill_rounded_rect(pos_x, pos_ly, pos_w, pos_h, sc(5), sc(5),
                        hov_pos and _SF6UI.THEME.btn_hover or _SF6UI.THEME.btn_idle)
                    d2d.rounded_rect(pos_x, pos_ly, pos_w, pos_h, sc(5), sc(5), sc(2), sp_acc)
                    local pl, ph = sp_font:measure(cp_label)
                    d2d.text(sp_font, cp_label,
                        pos_x + (pos_w - pl)/2, pos_ly + (pos_h - ph)/2,
                        _SF6UI.THEME.text_value)
                    if cn_raw_click and hit_rect(pos_x, pos_ly, pos_w, pos_h) then
                        cfg.combo_notes_pos = cp_order[(cp_idx % #cp_order) + 1]
                        save_config()
                    end
                end

                -- Close button (bottom-right of the popup)
                do
                    local cl_w = sc(120)
                    local cl_h = sc(row_h + 8)
                    local cl_x = sp_x + sp_w - sp_pad - cl_w
                    local cl_y = sp_y + sp_h - sp_pad - cl_h
                    local hov = hit_rect(cl_x, cl_y, cl_w, cl_h)
                    d2d.fill_rounded_rect(cl_x, cl_y, cl_w, cl_h, sc(6), sc(6),
                        hov and C_BTN_ACTIVE or C_BTN_BG)
                    d2d.rounded_rect(cl_x, cl_y, cl_w, cl_h, sc(6), sc(6), 1, C_BTN_BORDER)
                    local clt, clth = sp_font:measure("Close")
                    d2d.text(sp_font, "Close",
                        cl_x + (cl_w - clt)/2, cl_y + (cl_h - clth)/2, C_LABEL)
                    if cn_raw_click and hit_rect(cl_x, cl_y, cl_w, cl_h) then
                        show_settings_hk = false
                    end
                end

                end  -- close: content drawn only once panel has arrived

                -- Click outside the panel dismisses it (uses full-size rect).
                if show_settings_hk and cn_raw_click
                   and not hit_rect(sp_x, sp_y, sp_w, sp_h) then
                    show_settings_hk = false
                end
            end
        end

        -- ── COMBO TITLES EDITOR PANEL removed: titles now edited
        --    in the web editor (index.html). Saves ~30 chunk-level
        --    locals' worth of compile-time headroom and ~210 lines.

        -- ── SOFTWARE CURSOR ──────────────────────────────────────
        -- Draw a classic arrow cursor in d2d whenever any menu is open.
        -- REFramework has no API to show the OS cursor without the REF
        -- menu being open, so we own the cursor entirely in d2d here.
        local any_menu = show_display_win or show_profiles_win
                      or show_combo_notes_win
        if any_menu then
            local cx = frame_mouse_x
            local cy = frame_mouse_y
            local S  = 14  -- arrow size
            local BLACK = 0xFF000000
            local WHITE = 0xFFFFFFFF
            -- Draws the arrow shape at offset ox,oy in the given colour.
            -- Classic arrow: vertical shaft + horizontal top + diagonal body.
            local function arrow(ox, oy, col)
                d2d.fill_rect(cx+ox,   cy+oy,   3,    S,    col)  -- shaft
                d2d.fill_rect(cx+ox,   cy+oy,   S,    3,    col)  -- top bar
                d2d.fill_rect(cx+ox+1, cy+oy+1, S-1,  2,    col)  -- diagonal stair 1
                d2d.fill_rect(cx+ox+2, cy+oy+3, S-3,  2,    col)  -- diagonal stair 2
                d2d.fill_rect(cx+ox+3, cy+oy+5, S-5,  2,    col)  -- diagonal stair 3
                d2d.fill_rect(cx+ox+4, cy+oy+7, S-7,  2,    col)  -- diagonal stair 4
                d2d.fill_rect(cx+ox+5, cy+oy+9, S-9,  2,    col)  -- diagonal stair 5
            end
            -- Black outline (4 cardinal offsets), then white fill on top
            for _, o in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                arrow(o[1], o[2], BLACK)
            end
            arrow(0, 0, WHITE)
        end

        -- After all UI drawn, consume any remaining click
        frame_click_pending = false
    end)
    if not ok then frame_click_pending = false end
end)

-- ── re.on_frame: GAME STATE UPDATES ──────────────────────────
-- Mouse state is captured inside the d2d draw callback.
-- This only handles character detection refreshes.
local update_timer = 0
re.on_frame(function()
    pcall(function()
        -- Pump mouse position every frame so hit-tests work even when
        -- the REFramework menu is closed (imgui.get_mouse inside d2d draw
        -- may return stale coords when the REF menu is not open).
        local m = imgui.get_mouse()
        if m then
            frame_mouse_x = m.x
            frame_mouse_y = m.y
        end

        update_timer = update_timer + 1
        if update_timer >= 15 then
            update_players()
            update_timer = 0
        end
        update_current_moves()

        -- Flush any pending combo notes saves (set by Save button in d2d draw)
        -- File I/O is safe here — re.on_frame runs outside the render thread.
        for char_key, _ in pairs(combo_notes_dirty) do
            local ok, err = pcall(flush_combo_notes, char_key)
            if not ok then
                re.msg("combonotes save error [" .. tostring(char_key) .. "]: " .. tostring(err))
            end
            combo_notes_dirty[char_key] = nil
        end

        -- Load combo notes for any character not yet loaded this session.
        -- Done here (not in d2d draw) because io.open is unsafe in draw callbacks.


        -- Flush a pending load triggered by the profile menu character switch.
        if combo_notes_load_pending then
            local name = combo_notes_load_pending
            combo_notes_load_pending = nil
            local key = name:lower()
            combo_notes_loaded[name] = nil
            combo_slots[key] = nil
            local ok2, err2 = pcall(load_combo_notes, name)
            if not ok2 then
                re.msg("combonotes switch-load error [" .. tostring(name) .. "]: " .. tostring(err2))
            end
        end

        -- Mirror combo_notes pattern: reload notes on profile menu char switch.
        if notes_load_pending then
            local name = notes_load_pending
            notes_load_pending = nil
            notes_loaded[name] = nil
            notes_data[name:lower()] = nil
            local okn, errn = pcall(load_char_notes, name)
            if not okn then
                re.msg("notes switch-load error [" .. tostring(name) .. "]: " .. tostring(errn))
            end
        end

        for _, p in ipairs(players) do
            if p.name and p.name ~= "?" then
                local ok, err = pcall(load_combo_notes, p.name)
                if not ok then
                    re.msg("combonotes load error [" .. tostring(p.name) .. "]: " .. tostring(err))
                end
                local okn, errn = pcall(load_char_notes, p.name)
                if not okn then
                    re.msg("notes load error [" .. tostring(p.name) .. "]: " .. tostring(errn))
                end
            end
        end

        -- Auto-refresh: every ~1s, drop the load guards so the next
        -- iteration of the loop above re-reads JSON from disk. This
        -- is what makes web-editor saves appear without a manual
        -- "Reload Config" click. Skipped while the in-game Combo
        -- Notes editor is open to avoid clobbering unsaved in-memory
        -- edits that haven't flushed via combo_notes_dirty yet.
        cn_refresh.counter = cn_refresh.counter + 1
        if cn_refresh.counter >= cn_refresh.frames then
            cn_refresh.counter = 0
            if not show_combo_notes_win and next(combo_notes_dirty) == nil then
                invalidate_char_caches()
            end
        end
    end)
end)

-- ── Airborne state ──────────────────────────
-- Tracked inside update_dir_buffer() each frame. The state variables
-- (is_airborne, air_frames_remaining) and the AIR_DURATION constant
-- are declared up at the top of the file (around line 811) — see
-- there for the canonical source. This section used to redeclare
-- them, which Lua treats as fresh local-slot allocations (eating
-- into the 200-locals-per-function cap), so the redeclarations were
-- removed.

-- ── SCRIPT GENERATED UI ENTRY ────────────────────────────────
-- (cursor keepalive removed; mouse pumped in re.on_frame below)

re.on_draw_ui(function()
    if imgui.tree_node("SF6 Overlay (d2d)") then
        local c, v
        c,v = imgui.checkbox("Show Top Button Bar", cfg.show_button_bar)
        if c then cfg.show_button_bar = v end
        c,v = imgui.checkbox("Show Overlay Elements", cfg.show_overlay)
        if c then cfg.show_overlay = v end

        imgui.separator()
        imgui.text("Live detection:")
        imgui.text("  P1: " .. players[1].name .. "  [" .. players[1].esf .. "]")
        imgui.text("  P2: " .. players[2].name .. "  [" .. players[2].esf .. "]")
        imgui.text("  Core: " .. (found_core and "OK" or "waiting..."))
        imgui.text("  InputManager: " .. (im_found and "OK" or "waiting..."))
        -- Per-pad activity probe. Walks every populated _GamePads
        -- slot and reports whether ANY button on that pad is
        -- currently non-zero. Press keys / buttons while watching
        -- this line to identify which slot the keyboard maps to.
        -- Slot 0 is typically the primary controller; the keyboard
        -- usually lands at slot 1 in SF6 (though it can vary by
        -- device bind order).
        do
            local lines = {}
            for i, pad in ipairs(im_pads) do
                local btns = safe_get(pad, "_Buttons")
                local any_pressed = false
                if btns then
                    -- Scan the 12 known button indices (UP=0..HK=11)
                    for bi = 0, 11 do
                        local ok, b = pcall(function() return btns[bi] end)
                        if ok and b then
                            local f = tonumber(safe_get(b, "Flags") or 0) or 0
                            if f ~= 0 then any_pressed = true; break end
                        end
                    end
                end
                lines[#lines+1] = string.format("pad%d=%s",
                    i-1, any_pressed and "ACTIVE" or "----")
            end
            imgui.text("  Devices: " .. table.concat(lines, "  "))
        end
        -- _Keyboard introspection. The InputState SDK type has a
        -- separate _Keyboard field (distinct from _GamePads) of
        -- type app.InputDeviceStateKeyboard. We don't yet know
        -- which sub-field exposes the key state (could be _Buttons,
        -- _Keys, _ButtonOn, _Flags, etc.) so this probe walks the
        -- managed-type definition and lists field names + types
        -- to the panel. Press keyboard keys while reading the
        -- panel — fields whose values change are the ones we want.
        do
            local im = sdk.get_managed_singleton("app.InputManager")
            local st = im and safe_get(im, "_State")
            local kb = st and safe_get(st, "_Keyboard")
            if kb then
                imgui.text("  _Keyboard: present (type below)")
                local ok_td, td = pcall(function() return kb:get_type_definition() end)
                if ok_td and td then
                    local fields_ok, fields = pcall(function() return td:get_fields() end)
                    if fields_ok and fields then
                        local count = 0
                        for _, f in ipairs(fields) do
                            local name = f:get_name() or "?"
                            -- Try to print a brief preview of the value
                            local val_str = "?"
                            local ok_v, v = pcall(function() return kb:get_field(name) end)
                            if ok_v then
                                if type(v) == "boolean" then val_str = tostring(v)
                                elseif type(v) == "number" then val_str = tostring(v)
                                elseif type(v) == "userdata" then val_str = "<obj>"
                                elseif v == nil then val_str = "nil"
                                else val_str = type(v) end
                            end
                            imgui.text(string.format("    %s = %s", name, val_str))
                            count = count + 1
                            if count >= 15 then
                                imgui.text("    ... (truncated)")
                                break
                            end
                        end
                    else
                        imgui.text("    (no fields method)")
                    end
                else
                    imgui.text("    (no type definition)")
                end
            else
                imgui.text("  _Keyboard: NOT FOUND")
            end
        end
        -- Fighter detection diagnostics
        imgui.text("  _Fighters obj: " .. tostring(detect_diag.fighters_obj))
        imgui.text("  _Fighters count: " .. tostring(detect_diag.fighter_count))
        imgui.text("  P1 fobj: " .. tostring(detect_diag.p1_fobj))
        imgui.text("  P1 raw name: " .. tostring(detect_diag.p1_name_raw))
        imgui.text("  edit_char_idx: " .. tostring(edit_char_idx) ..
                   " (" .. (ROSTER[edit_char_idx] or "?") .. ")")
        imgui.text("  CN window char: " .. tostring(detect_diag.cn_char_name))
        imgui.text("  CN slot1: \"" .. tostring(detect_diag.cn_slot1_title) ..
                   "\" tokens=" .. tostring(detect_diag.cn_slot1_toks))
        -- Keyboard diagnostic. Both rows read raw Win32 state via
        -- reframework:is_key_down — bypasses imgui io entirely so
        -- gamepad input (which REF maps onto imgui arrows) doesn't
        -- pollute the display. Press Backspace / arrows / Home / End
        -- and the live row should flip to DOWN.
        do
            local function rk_held(vk)
                local ok, v = pcall(function() return reframework:is_key_down(vk) end)
                if not ok then
                    ok, v = pcall(function() return reframework.is_key_down(vk) end)
                end
                return (ok and v == true) and "DOWN" or "----"
            end
            -- Probe whether reframework:is_key_down is callable at all
            -- (vs erroring out on this build).
            local probe_ok = pcall(function() return reframework:is_key_down(0x08) end)
            if not probe_ok then
                probe_ok = pcall(function() return reframework.is_key_down(0x08) end)
            end
            imgui.text("  Keyboard API: " ..
                (probe_ok and "reframework:is_key_down (raw Win32)"
                          or "UNAVAILABLE — keyboard input disabled"))
            imgui.text(string.format("  KB held: Bksp=%s  L=%s  R=%s  Home=%s  End=%s",
                rk_held(0x08), rk_held(0x25), rk_held(0x27), rk_held(0x24), rk_held(0x23)))
        end
        -- Framedata debug
        local fd = load_framedata(players[1].name)
        if fd then
            local cnt = 0; for _ in pairs(fd.by_input) do cnt=cnt+1 end
            imgui.text("  P1 FrameData: OK (" .. cnt .. " inputs indexed)")
            -- Show first few input keys
            local keys = {}
            for k in pairs(fd.by_input) do table.insert(keys,k); if #keys>=3 then break end end
            imgui.text("  Sample keys: " .. table.concat(keys, ", "))
        else
            imgui.text("  P1 FrameData: NOT FOUND - run updater!")
        end
        imgui.text("  Last numcmd: " .. last_numcmd)
        -- Combo notes recording diagnostic. Should show:
        --   editor open=true   when you've opened Combo Notes
        --   prev=<value>       the previously-recorded numcmd (info only)
        --   last~=prev=<bool>  was last_numcmd different from prev (info only)
        -- Recording fires on rising-edge of any attack button while the
        -- editor is open — repeat presses (LP, LP, LP) all register.
        imgui.text(string.format(
            "  Combo notes: editor open=%s  prev=%s  last~=prev=%s",
            tostring(show_combo_notes_win),
            tostring(prev_numcmd),
            tostring(last_numcmd ~= prev_numcmd)))
        imgui.text("  P1 facing left: " .. tostring(p1_facing_left))
        -- Charge state diagnostics (only shown for charge characters)
        if is_charge_character(players[1].name) then
            imgui.text(string.format(
                "  Charge [%s]: back held=%d buf=%d | down held=%d buf=%d",
                players[1].name,
                charge_state.back_held, charge_state.back_buffer,
                charge_state.down_held, charge_state.down_buffer))
        end
        -- Stance state diagnostic (shown when in any stance)
        if stance_state.active then
            imgui.text(string.format(
                "  Stance: %s [%s] frames=%d sub=%s",
                stance_state.active, stance_state.char or "?",
                stance_state.frames, tostring(stance_state.sub_state)))
        end
        imgui.text("  P1 X: " .. tostring(_SF6UI.dbg.dbg_p1x) .. "  P2 X: " .. tostring(_SF6UI.dbg.dbg_p2x))
        imgui.text("  P1 Y: " .. tostring(_SF6UI.dbg.dbg_p1y) .. "  Z: " .. tostring(_SF6UI.dbg.dbg_p1z) .. "  airborne: " .. tostring(is_airborne))
        imgui.text("  Fields: " .. (_SF6UI.dbg.dbg_fields and table.concat(_SF6UI.dbg.dbg_fields, " ") or "none"))
        if current_move.p1 then
            imgui.text("  P1 Move: " .. (current_move.p1.name or "?"))
        else
            imgui.text("  P1 Move: none")
        end
        if current_move.p2 then
            imgui.text("  P2 Move: " .. (current_move.p2.name or "?"))
        end

        imgui.separator()
        if imgui.button("Force Core Refresh") then
            found_core = nil
            players[1].esf = "?"; players[1].name = "?"
            players[2].esf = "?"; players[2].name = "?"
        end

        imgui.tree_pop()
    end
end)

-- ── INIT ─────────────────────────────────────────────────────
load_config()
