-- ============================================================
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

-- ── DEFAULT CONFIG ───────────────────────────────────────────
local cfg = {
    show_overlay        = true,
    show_button_bar     = true,
    show_ticks          = true,
    show_profiles_text  = true,
    show_ticker         = true,
    show_p1_profile     = true,
    show_p2_profile     = true,
    font_size           = 24,      -- profile text
    notes_font_size     = 20,      -- notes.json text under profile
    ticker_font_size    = 28,
    button_font_size    = 20,
    menu_font_size      = 20,
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
    numeric_notation    = true,  -- true = numpad (default); false = arrow/shorthand
    hud_skin            = "SF6",  -- health bar skin selection (UI only for now)
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
    if cfg.numeric_notation then return s end
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

-- Helper: read the saved combo scheme for a character, defaulting to
-- "classic" for characters with no profile yet or older profiles that
-- predate this field. Always returns one of "classic" | "modern".
local function get_combo_scheme(char_name)
    if not char_name or char_name == "?" then return "classic" end
    local p = cfg.profiles[char_name:lower()]
    if p and p.combo_scheme == "modern" then return "modern" end
    return "classic"
end

-- Helper: write the combo scheme onto the profile and persist. Creates
-- the profile entry if missing. Idempotent — no-op when the value
-- already matches.
local function set_combo_scheme(char_name, scheme)
    if not char_name or char_name == "?" then return end
    if scheme ~= "modern" then scheme = "classic" end
    local key = char_name:lower()
    local p = cfg.profiles[key]
    if not p then
        p = default_profile(char_name)
        cfg.profiles[key] = p
    end
    if p.combo_scheme == scheme then return end
    p.combo_scheme = scheme
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
local STICK_DEAD     = 0.5
local STICK_DEAD_DIAG = 0.4

-- Y-axis sign: in SF6 / RE Engine the convention has been observed to
-- be positive Y = up (matches OpenGL/3D math convention). If the game
-- reads inverted on your build, flip this to -1 and the directional
-- math below auto-adjusts. Most users won't need to touch this.
local STICK_Y_SIGN = 1

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
    local y_eff = (y or 0) * STICK_Y_SIGN
    local x_eff = x or 0
    return
        y_eff >  STICK_DEAD_DIAG, y_eff < -STICK_DEAD_DIAG,
        x_eff < -STICK_DEAD_DIAG, x_eff >  STICK_DEAD_DIAG,
        y_eff >  STICK_DEAD,      y_eff < -STICK_DEAD,
        x_eff < -STICK_DEAD,      x_eff >  STICK_DEAD
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
local dbg_p1x, dbg_p2x = nil, nil
local dbg_p1y = nil
local dbg_p1z = nil
local dbg_fields = {}
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
    if dbg_p1y then
        is_airborne = (dbg_p1y > GROUND_Y_THRESHOLD)
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
                if slot == 1 then p1x = tonumber(x); dbg_p1x = p1x else p2x = tonumber(x); dbg_p2x = p2x end
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
local HUD_SKIN_ORDER = { "SF6", "SimSim", "SSF2T", "SFA3", "SF3s", "SFIV", "SFVCE" }

-- Pretty display names for the cycle button. Internal keys stay
-- short for save-file stability and table-key brevity; the UI shows
-- the longer canonical title for each game.
local HUD_SKIN_DISPLAY = {
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
local HUD_SKIN_OVERRIDES = {
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
local HUD_SKIN_TICK_STYLE = {
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
local HUD_SKIN_TICK_COLOR = {
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
local HUD_SKIN_TICK_LABEL_POS = {
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
    local override = HUD_SKIN_OVERRIDES[skin]
    if override and override[field] ~= nil then return override[field] end
    return HUD[field]
end

local function hud_tick_style()
    return HUD_SKIN_TICK_STYLE[cfg.hud_skin or "SF6"] or "slanted"
end

-- Resolve to actual color constant (lazy lookup so colors don't have
-- to be initialized before this module runs).
local function tick_color()
    local name = HUD_SKIN_TICK_COLOR[cfg.hud_skin or "SF6"] or "yellow"
    if name == "blue" then return C_TICK_BLUE end
    return C_TICK
end

local function tick_label_pos()
    return HUD_SKIN_TICK_LABEL_POS[cfg.hud_skin or "SF6"] or "below"
end

local function hud_skin_index(name)
    for i, n in ipairs(HUD_SKIN_ORDER) do
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
    DR  = 0xFF1EB8C8,   -- cyan (Drive Rush)
    DRC = 0xFF0E7888,   -- darker cyan (Drive Rush Cancel)
    MW  = 0xFFD4A017,   -- gold (Micro Walk)
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
    DI    = 0xFFEC4899,   -- magenta (Drive Impact)
    DP    = 0xFF06B6D4,   -- teal (Drive Parry)
}
local CN_BTN_TEXT   = 0xFFFFFFFF
local CN_DIR_BG     = 0xFF252535
local CN_DIR_HOVER  = 0xFF3A3A55
local CN_DIR_BORDER = 0xFF5555AA
local CN_DIR_TEXT   = 0xFFE0E0E0
local CN_CANCEL_COL = 0xFFAAAAAA

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

-- Font size presets - shared by profile text AND ticker.
-- ALL sizes get preloaded at startup so switching is instant
-- (no need to Reset Scripts anymore).
local FONT_SIZES = { 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64, 72 }

-- Caches indexed by size -> d2d font object
local fonts_normal = {}   -- regular weight
local fonts_bold   = {}   -- bold weight (used for ticker + menu titles)

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

-- ── D2D REGISTER (init + draw) ───────────────────────────────
d2d.register(function()
    init_colors()
    -- Preload every size in both normal and bold weights
    for _, s in ipairs(FONT_SIZES) do
        fonts_normal[s] = d2d.Font.new("Consolas", s, false, false)
        fonts_bold[s]   = d2d.Font.new("Consolas", s, true,  false)
    end
    -- Combo ticker fonts rebuilt per-frame when scale changes (see draw callback)
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
            local gap   = 6
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
                show_display_win, show_profiles_win,
            }

            for i, label in ipairs(labels) do
                local w = widths[i]
                btn_x[i] = x
                btn_w[i] = w
                local hovered = hit_rect(x, y, w, h)
                local bg = C_BTN_BG
                if is_open[i]   then bg = C_BTN_ACTIVE
                elseif hovered  then bg = C_BTN_HOVER end
                d2d.fill_rect(x, y, w, h, bg)
                d2d.outline_rect(x, y, w, h, 1, C_BTN_BORDER)
                local tw, th = font_button:measure(label)
                d2d.text(font_button, label,
                    x + (w - tw)/2, y + (h - th)/2, C_BTN_TEXT)

                if click_in(x, y, w, h) then
                    if i == 1 then
                        show_display_win = not show_display_win
                        show_settings_win = false; show_profiles_win = false
                    else
                        show_profiles_win = not show_profiles_win
                        show_settings_win = false; show_display_win = false
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
                                        local tw = font_ticker_dir
                                            and font_ticker_dir:measure(notation(part.v)) or 0
                                        w = w + tw
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
                                        -- Show "P"/"K" for punches/kicks; full label otherwise
                                        local display = TC_LETTER[label] or label
                                        local tw, th = font_ticker_glyph:measure(display)
                                        d2d.text(font_ticker_glyph, display,
                                            cx-tw/2, cy-th/2, 0xFFFFFFFF)
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
                                                    local dir_label = notation(part.v)
                                                    local tw, th = font_ticker_dir:measure(dir_label)
                                                    d2d.text(font_ticker_dir, dir_label,
                                                        cx, y+(h-th)/2, TC_DIR)
                                                    cx = cx + tw
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
                                local probe_x = PAD_X + NAME_W + NAME_PAD + 3
                                local probe_w = sw - probe_x - PAD_X
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

                                d2d.fill_rect(0, ty, sw, bar_h, TC_BG)
                                d2d.outline_rect(0, ty, sw, bar_h, 1, TC_BORDER)

                                -- Name column (left). Anchored in the FIRST line
                                -- so it sits at the top when content wraps. The ':'
                                -- suffix acts as the visual separator between title
                                -- and inputs (in addition to the divider line).
                                local name_x = PAD_X
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
                                local input_w = sw - input_x - PAD_X
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
                                                local dl = notation(part.v)
                                                local tw, th = font_ticker_dir:measure(dl)
                                                d2d.text(font_ticker_dir, dl,
                                                    cx, row_y + (V_ROW_H - th)/2, TC_DIR)
                                                cx = cx + tw
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

        local function draw_menu_panel(x, y, w, h, title)
            d2d.fill_rect(x, y, w, h, C_MENU_BG)
            d2d.outline_rect(x, y, w, h, 1, C_MENU_BORDER)
            if title then
                local th = cfg.menu_font_size + 8
                d2d.fill_rect(x, y, w, th, C_MENU_TITLE_BG)
                d2d.text(font_menu_title, title,
                    x + 8, y + 2, C_MENU_TITLE)
            end
        end

        local function row_checkbox(x, y, w, label, state)
            local hovered = hit_rect(x, y, w, row_h)
            if hovered then d2d.fill_rect(x, y, w, row_h, C_ROW_HOVER) end
            local bs = cfg.menu_font_size - 2
            local bx = x + 6
            local by = y + (row_h - bs) / 2
            d2d.fill_rect(bx, by, bs, bs, C_CHECKBOX_BG)
            d2d.outline_rect(bx, by, bs, bs, 1, C_BTN_BORDER)
            if state then
                d2d.fill_rect(bx+3, by+3, bs-6, bs-6, C_CHECKBOX_ON)
            end
            d2d.text(font_menu, label,
                bx + bs + 8, y + (row_h - cfg.menu_font_size) / 2, C_LABEL)
            if click_in(x, y, w, row_h) then return not state, true end
            return state, false
        end

        local function row_cycle(x, y, w, label, value_text)
            local hovered = hit_rect(x, y, w, row_h)
            if hovered then d2d.fill_rect(x, y, w, row_h, C_ROW_HOVER) end
            local ty = y + (row_h - cfg.menu_font_size) / 2
            d2d.text(font_menu, label, x + 6, ty, C_LABEL)
            local lw, _ = font_menu:measure(label)
            d2d.text(font_menu, value_text, x + 6 + lw + 10, ty, C_VALUE)
            return click_in(x, y, w, row_h)
        end

        local function row_label(x, y, text, color)
            local ty = y + (row_h - cfg.menu_font_size) / 2
            d2d.text(font_menu, text, x + 6, ty, color or C_DIM)
        end

        -- menu_button: clickable rect with hover highlight.
        --   color    — optional text color override (default C_BTN_TEXT)
        --   bg_color — optional non-hover background color override
        --              (default C_BTN_BG). Used by toggle pairs (e.g.
        --              Classic / Modern scheme buttons) to highlight
        --              the currently-active option without relying on
        --              hover state.
        local function menu_button(x, y, w, h, label, color, bg_color)
            local hovered = hit_rect(x, y, w, h)
            local bg = bg_color or C_BTN_BG
            d2d.fill_rect(x, y, w, h, hovered and C_BTN_ACTIVE or bg)
            d2d.outline_rect(x, y, w, h, 1, C_BTN_BORDER)
            local tw, th = font_button:measure(label)
            d2d.text(font_button, label,
                x + (w - tw)/2, y + (h - th)/2,
                color or C_BTN_TEXT)
            return click_in(x, y, w, h)
        end

        -- Display & Settings menu (merged)
        if show_display_win and cfg.show_button_bar then
            local mw = 420
            local mh = row_h * 22 + 60
            local mx, my = menu_anchor(1, mw)
            draw_menu_panel(mx, my, mw, mh, "Display & Settings")

            local ry = my + row_h + 4
            local changed

            -- ── Display toggles ───────────────────────────────
            cfg.show_overlay, changed = row_checkbox(mx+4, ry, mw-8,
                "Master Overlay (ticks+profiles+ticker)", cfg.show_overlay)
            ry = ry + row_h

            cfg.show_ticks, changed = row_checkbox(mx+4, ry, mw-8,
                "Health Bar Tick Marks (10%)", cfg.show_ticks)
            ry = ry + row_h

            local hsidx = hud_skin_index(cfg.hud_skin)
            local hs_label = HUD_SKIN_DISPLAY[HUD_SKIN_ORDER[hsidx]]
                          or HUD_SKIN_ORDER[hsidx]
            if row_cycle(mx+4, ry, mw-8, "HUD Skin:", hs_label) then
                local next_i = (hsidx % #HUD_SKIN_ORDER) + 1
                cfg.hud_skin = HUD_SKIN_ORDER[next_i]
            end
            ry = ry + row_h

            cfg.show_profiles_text, changed = row_checkbox(mx+4, ry, mw-8,
                "Character Profile Text (master)", cfg.show_profiles_text)
            ry = ry + row_h

            cfg.show_p1_profile, changed = row_checkbox(mx+4, ry, mw-8,
                "  Show Player 1 Profile", cfg.show_p1_profile)
            ry = ry + row_h

            cfg.show_p2_profile, changed = row_checkbox(mx+4, ry, mw-8,
                "  Show Player 2 Profile", cfg.show_p2_profile)
            ry = ry + row_h

            cfg.show_ticker, changed = row_checkbox(mx+4, ry, mw-8,
                "Combo Ticker Bars", cfg.show_ticker)
            ry = ry + row_h

            cfg.numeric_notation, changed = row_checkbox(mx+4, ry, mw-8,
                "Numeric Notation", cfg.numeric_notation)
            ry = ry + row_h

            -- Ticker scale cycle: 0.75 → 1.0 → 1.25 → 1.5 → 2.0 → 2.5 → 3.0
            local SCALE_STEPS = { 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0 }
            local scale_labels = { "Small (0.75x)", "Normal (1.0x)", "Large (1.25x)", "XL (1.5x)", "2K (2.0x)", "2.5x", "4K (3.0x)" }
            local cur_scale_idx = 2
            for i, v in ipairs(SCALE_STEPS) do
                if math.abs(v - (cfg.ticker_scale or 1.0)) < 0.01 then
                    cur_scale_idx = i; break
                end
            end
            if row_cycle(mx+4, ry, mw-8, "Ticker Scale:", scale_labels[cur_scale_idx]) then
                local next_i = (cur_scale_idx % #SCALE_STEPS) + 1
                cfg.ticker_scale = SCALE_STEPS[next_i]
            end
            ry = ry + row_h

            -- Ticker vertical position. Cycle 4 named anchor points so
            -- users don't fight a continuous slider. Each value is the
            -- fraction of screen height from the bottom edge to the
            -- bottom of the ticker stack.
            --   Bottom (0.05): hugs the bottom of the screen
            --   Default (0.11): just above the SUPER bar (original)
            --   Above Frame Meter (0.32): clear of SF6's frame meter
            --   Mid Screen (0.45): higher, away from gameplay HUD
            local POS_STEPS  = { 0.05, 0.11, 0.32, 0.45 }
            local POS_LABELS = { "Bottom", "Default", "Above Frame Meter", "Mid Screen" }
            local cur_pos_idx = 2  -- default to "Default" (0.11)
            for i, v in ipairs(POS_STEPS) do
                if math.abs(v - (cfg.ticker_bottom_pct or 0.11)) < 0.01 then
                    cur_pos_idx = i; break
                end
            end
            if row_cycle(mx+4, ry, mw-8, "Ticker Position:", POS_LABELS[cur_pos_idx]) then
                local next_i = (cur_pos_idx % #POS_STEPS) + 1
                cfg.ticker_bottom_pct = POS_STEPS[next_i]
            end
            ry = ry + row_h

            -- Orientation toggle: horizontal full-width bars vs vertical
            -- trials-mode columns. When vertical, ticker_bottom_pct is
            -- ignored (vertical anchors to top of screen instead).
            local cur_orient = cfg.ticker_orientation or "horizontal"
            local orient_label = (cur_orient == "vertical") and "Vertical (Trials)" or "Horizontal"
            if row_cycle(mx+4, ry, mw-8, "Ticker Orientation:", orient_label) then
                cfg.ticker_orientation = (cur_orient == "vertical") and "horizontal" or "vertical"
            end
            ry = ry + row_h

            -- Vertical-mode side anchor (Left/Right). Only meaningful when
            -- orientation=vertical, but always shown so users can pre-set it.
            local cur_side = cfg.ticker_vertical_side or "left"
            local side_label = (cur_side == "right") and "Right" or "Left"
            if row_cycle(mx+4, ry, mw-8, "Vertical Side:", side_label) then
                cfg.ticker_vertical_side = (cur_side == "left") and "right" or "left"
            end
            ry = ry + row_h

            -- ── Profile / font settings ───────────────────────
            if row_cycle(mx+4, ry, mw-8, "Profile Font Size:",
                tostring(cfg.font_size) .. "px") then
                cfg.font_size = next_in_cycle(cfg.font_size, FONT_SIZES)
            end
            ry = ry + row_h

            if row_cycle(mx+4, ry, mw-8, "Notes Font Size:",
                tostring(cfg.notes_font_size) .. "px") then
                cfg.notes_font_size = next_in_cycle(cfg.notes_font_size, FONT_SIZES)
            end
            ry = ry + row_h

            local cidx2 = color_index(cfg.font_color)
            if row_cycle(mx+4, ry, mw-8, "Profile Text Color:",
                COLOR_PRESETS[cidx2].name) then
                local next_i = (cidx2 % #COLOR_PRESETS) + 1
                local c = COLOR_PRESETS[next_i].rgba
                cfg.font_color = { c[1], c[2], c[3], c[4] }
                C_TEXT = argb(c[1], c[2], c[3], c[4])
            end
            local sw_x2 = mx + mw - 36
            d2d.fill_rect(sw_x2, ry+4, 28, row_h-8, C_TEXT)
            d2d.outline_rect(sw_x2, ry+4, 28, row_h-8, 1, C_BTN_BORDER)
            ry = ry + row_h

            if row_cycle(mx+4, ry, mw-8, "Profile Text Vertical Offset:",
                tostring(cfg.offset_y) .. "px") then
                cfg.offset_y = cfg.offset_y + 2
                if cfg.offset_y > 20 then cfg.offset_y = -20 end
            end
            ry = ry + row_h

            if row_cycle(mx+4, ry, mw-8, "Profile Text Horizontal Offset:",
                tostring(cfg.offset_x) .. "px") then
                cfg.offset_x = cfg.offset_x + 4
                if cfg.offset_x > 40 then cfg.offset_x = -40 end
            end
            ry = ry + row_h

            row_label(mx+4, ry, "Resolution: " .. sw .. " x " .. sh)
            ry = ry + row_h

            local bh = row_h + 4
            ry = my + mh - bh - 6
            if menu_button(mx+6, ry, 80, bh, "Save") then save_config() end
            if menu_button(mx+102, ry, 120, bh, "Reset Align") then
                cfg.offset_x = 0; cfg.offset_y = 0; save_config()
            end
            -- Reload script: re-runs all autorun Lua, which clears the
            -- in-memory notes/combonotes caches and re-reads from disk.
            -- Use after editing notes/combos in the web editor so the
            -- overlay picks up changes without restarting the game.
            if menu_button(mx+228, ry, 110, bh, "Reload Script") then
                save_config()
                reframework:reset_scripts()
            end
            if menu_button(mx+mw-86, ry, 80, bh, "Close") then
                show_display_win = false
            end
        end

        -- Combo Editor menu (formerly Character Profiles)
        if show_profiles_win and not show_combo_notes_win and cfg.show_button_bar then
            local mw = 460
            local dd_item_h  = cfg.menu_font_size + 8
            local dd_visible = 12   -- max visible rows in dropdown
            local dd_list_h  = dd_visible * dd_item_h
            -- Expand panel height to contain open dropdown
            local mh = profile_dropdown_open
                and (row_h * 3 + 50 + dd_list_h)
                or  (row_h * 13 + 50)
            local mx, my = menu_anchor(2, mw)
            local char_name = ROSTER[edit_char_idx]
            draw_menu_panel(mx, my, mw, mh,
                "Combo Editor  [" .. char_name .. "]")

            local ry = my + row_h + 4

            -- ── Character select dropdown button ──────────────
            local dd_h   = row_h + 2
            -- Yellow when auto-synced from game, white when player manually chose
            local dd_col = profile_user_override and C_LABEL or C_VALUE
            if menu_button(mx+6, ry, mw-12, dd_h,
                char_name .. (profile_user_override and "" or "  [auto]"), dd_col)
            then
                profile_dropdown_open = not profile_dropdown_open
                if profile_dropdown_open then
                    -- Scroll to show selected character when opening
                    local max_s = math.max(0, #ROSTER - dd_visible)
                    profile_dd_scroll = math.max(0, math.min(edit_char_idx - math.floor(dd_visible/2), max_s))
                end
            end
            ry = ry + dd_h + 4

            if profile_dropdown_open then
                -- ── Scrollable dropdown (12 visible, ^ v arrows to scroll) ──
                local lx, ly = mx + 6, ry
                local C_DD_BG      = 0xFF1A1A24
                local C_DD_BORDER  = 0xFF8080AA
                local C_DD_SEL     = 0xFF2E2E48
                local C_DD_HOVER   = 0xFF252535
                local C_DD_TEXT    = 0xFFE0E0E0
                local C_DD_SEL_TXT = 0xFFFFE066

                local max_scroll_dd = math.max(0, #ROSTER - dd_visible)
                profile_dd_scroll = math.max(0, math.min(profile_dd_scroll, max_scroll_dd))

                -- Arrow button dimensions — sit to the right of the list
                local arr_w = 28
                local arr_h = math.floor(dd_list_h / 2) - 2
                local arr_x = lx + mw - 18 - arr_w
                local list_w2 = mw - 12 - arr_w - 4  -- list narrower to make room

                d2d.fill_rect(lx, ly, list_w2, dd_list_h, C_DD_BG)
                d2d.outline_rect(lx, ly, list_w2, dd_list_h, 1, C_DD_BORDER)

                -- ^ scroll up button
                local hov_up = hit_rect(arr_x, ly, arr_w, arr_h)
                d2d.fill_rect(arr_x, ly, arr_w, arr_h,
                    hov_up and C_BTN_ACTIVE or C_BTN_BG)
                d2d.outline_rect(arr_x, ly, arr_w, arr_h, 1, C_BTN_BORDER)
                local ul, uh = font_menu:measure("^")
                d2d.text(font_menu, "^",
                    arr_x+(arr_w-ul)/2, ly+(arr_h-uh)/2, C_BTN_TEXT)
                if click_in(arr_x, ly, arr_w, arr_h) then
                    profile_dd_scroll = math.max(0, profile_dd_scroll - 1)
                end

                -- v scroll down button
                local dn_y = ly + arr_h + 4
                local hov_dn = hit_rect(arr_x, dn_y, arr_w, arr_h)
                d2d.fill_rect(arr_x, dn_y, arr_w, arr_h,
                    hov_dn and C_BTN_ACTIVE or C_BTN_BG)
                d2d.outline_rect(arr_x, dn_y, arr_w, arr_h, 1, C_BTN_BORDER)
                local dl, dh = font_menu:measure("v")
                d2d.text(font_menu, "v",
                    arr_x+(arr_w-dl)/2, dn_y+(arr_h-dh)/2, C_BTN_TEXT)
                if click_in(arr_x, dn_y, arr_w, arr_h) then
                    profile_dd_scroll = math.min(max_scroll_dd, profile_dd_scroll + 1)
                end

                -- Scroll position label between arrows
                local sp = tostring(profile_dd_scroll + 1) .. "/" .. (#ROSTER - dd_visible + 1)
                local sl, _ = font_menu:measure(sp)
                d2d.text(font_menu, sp,
                    arr_x + (arr_w-sl)/2, ly + arr_h*2 - uh, C_DIM)

                -- Draw the visible items
                for vi = 0, dd_visible - 1 do
                    local i = vi + profile_dd_scroll + 1
                    if i > #ROSTER then break end
                    local n = ROSTER[i]
                    local iy = ly + vi * dd_item_h
                    local is_sel = (i == edit_char_idx)
                    if is_sel then
                        d2d.fill_rect(lx, iy, list_w2, dd_item_h, C_DD_SEL)
                    elseif hit_rect(lx, iy, list_w2, dd_item_h) then
                        d2d.fill_rect(lx, iy, list_w2, dd_item_h, C_DD_HOVER)
                    end
                    d2d.fill_rect(lx+8, iy + dd_item_h - 1, list_w2-16, 1, 0xFF2A2A3A)
                    d2d.text(font_menu, n,
                        lx + 12, iy + (dd_item_h - cfg.menu_font_size)/2,
                        is_sel and C_DD_SEL_TXT or C_DD_TEXT)
                    if click_in(lx, iy, list_w2, dd_item_h) then
                        edit_char_idx            = i
                        profile_user_override    = true
                        profile_dropdown_open    = false
                        combo_edit_slot          = 1
                        combo_edit_cursor        = 0   -- new char, fresh cursor
                        -- Queue a notes load for the newly selected character.
                        -- Actual io.open happens in re.on_frame (safe for I/O).
                        combo_notes_load_pending = n
                        notes_load_pending       = n
                    end
                end
                -- Click outside list = close without selecting
                if frame_click_pending then
                    profile_dropdown_open = false
                    frame_click_pending   = false
                end
            else
                -- ── Profile data (shown when dropdown is closed) ───
                local key = char_name:lower()
                local p   = cfg.profiles[key]
                if not p then
                    p = default_profile(char_name); cfg.profiles[key] = p
                end

                if p.notes ~= "" then
                    row_label(mx+4, ry, "Notes: " .. p.notes, C_DIM)
                    ry = ry + row_h
                end
                row_label(mx+4, ry,
                    "(Edit profiles in sf6_overlay_config.json)",
                    argb(0.6, 0.6, 0.6, 1.0))
                ry = ry + row_h

                -- ── Control scheme toggle ──────────────────────
                -- Selects which combo notes file (Classic or Modern)
                -- the Combo Notes button below opens for this character.
                -- Persists to sf6_overlay_config.json so the choice
                -- survives script reloads. When flipped, queues a
                -- reload + invalidates the in-memory slot cache so
                -- the next Combo Notes open shows the right file's
                -- contents. The web editor stores the same per-character
                -- setting in notes.json (control_scheme field); the two
                -- aren't synced — the Lua and the web editor each
                -- maintain their own scheme selection for now.
                local cur_scheme = get_combo_scheme(char_name)
                local sch_label_x = mx + 6
                local sch_label_w = 110
                local sch_btn_w   = (mw - 12 - sch_label_w - 8) / 2  -- two equal buttons
                row_label(sch_label_x, ry + 4, "Combo Scheme:", C_LABEL)
                -- Classic button (active = highlighted)
                local cls_x = sch_label_x + sch_label_w + 4
                local cls_active = (cur_scheme == "classic")
                if menu_button(cls_x, ry, sch_btn_w, dd_h, "Classic",
                    cls_active and C_BTN_TEXT or C_DIM,
                    cls_active and C_BTN_ACTIVE or nil)
                then
                    if cur_scheme ~= "classic" then
                        set_combo_scheme(char_name, "classic")
                        save_config()
                        -- Drop the in-memory cache + queue a reload so
                        -- the Combo Notes window will show the Classic
                        -- file when next opened (or refresh in place
                        -- if already open).
                        combo_notes_loaded[char_name] = nil
                        combo_slots[char_name:lower()] = nil
                        combo_notes_load_pending = char_name
                    end
                end
                -- Modern button (active = highlighted)
                local mod_x = cls_x + sch_btn_w + 4
                local mod_active = (cur_scheme == "modern")
                if menu_button(mod_x, ry, sch_btn_w, dd_h, "Modern",
                    mod_active and C_BTN_TEXT or C_DIM,
                    mod_active and C_BTN_ACTIVE or nil)
                then
                    if cur_scheme ~= "modern" then
                        set_combo_scheme(char_name, "modern")
                        save_config()
                        combo_notes_loaded[char_name] = nil
                        combo_slots[char_name:lower()] = nil
                        combo_notes_load_pending = char_name
                    end
                end
                ry = ry + dd_h + 4

                -- ── Combo Notes button ────────────────────────
                if menu_button(mx+6, ry, mw-12, dd_h, "Combo Notes") then
                    show_combo_notes_win    = true
                    combo_notes_open_guard  = true
                    profile_dropdown_open   = false
                end
                ry = ry + dd_h + 4

            end

            local bh = row_h + 4
            ry = my + mh - bh - 6
            if menu_button(mx+6, ry, 130, bh, "Reload Config") then
                load_config()
                invalidate_char_caches()
                re.msg("Config + combo notes reloaded from disk.")
            end
            -- Reloads all autorun scripts; clears notes/combonotes caches
            -- so freshly-saved web editor data appears without restart.
            if menu_button(mx+142, ry, 130, bh, "Reload Script") then
                local ok, err = pcall(function() reframework:reset_scripts() end)
                if not ok then
                    -- Older REFramework builds expose this as a static
                    -- function rather than a method, or not at all.
                    -- Fall back to cache invalidation, which covers
                    -- 95% of why people press this button.
                    invalidate_char_caches()
                    re.msg("reset_scripts unavailable on this REFramework build — caches invalidated instead.")
                end
            end
            if menu_button(mx+mw-86, ry, 80, bh, "Close") then
                show_profiles_win     = false
                profile_dropdown_open = false
            end
        end

        -- ── COMBO NOTES INPUT BUILDER ───────────────────────────
        if show_combo_notes_win and cfg.show_button_bar then
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

            -- Panel dimensions — wider to fit slot list on right
            local mw  = 1100  -- bumped from 1020 to fit new col 4 (CH/PC/SHM)
            local mh  = 760   -- taller for more preview/notes space
            local mx  = math.floor((sw - mw) / 2)
            local my  = math.floor(sh * 0.06)   -- near top to fit everything
            local slot_list_w = 240   -- right column: slot list
            local input_w     = mw - slot_list_w - 18  -- left column: input pad
            local cn_scheme = get_combo_scheme(char_name)
            local cn_scheme_tag = (cn_scheme == "modern") and "  [MODERN]" or "  [CLASSIC]"
            draw_menu_panel(mx, my, mw, mh,
                "Combo Notes  [" .. char_name .. "]" .. cn_scheme_tag .. "  Editing: " ..
                combo_edit_slot .. ". " .. slot_data.title)

            -- Independent click state for this window so it can't be
            -- starved by frame_click_pending being consumed by other panels.
            -- open_guard is true for exactly one frame after opening,
            -- blocking spurious clicks from the same click that opened the window.
            local cn_clicked = imgui.is_mouse_clicked(0) and not combo_notes_open_guard
            combo_notes_open_guard = false  -- clear after one frame
            local function cn_hit(x, y, w, h)
                return frame_mouse_x >= x and frame_mouse_x <= x+w
                   and frame_mouse_y >= y and frame_mouse_y <= y+h
            end
            local function cn_click(x, y, w, h)
                if cn_clicked and cn_hit(x, y, w, h) then
                    cn_clicked = false
                    return true
                end
                return false
            end

            -- ── Layout geometry (left: input pad) ─────────────
            -- Order L→R: numpad → motions (2 cols) → attacks (3 cols) → SAs (1 col)
            local content_y  = my + row_h + 8
            local dir_x      = mx + 10
            local dir_cell   = 48
            local dir_gap    = 5
            local dir_pad_w  = dir_cell * 3 + dir_gap * 2
            local MOT_GAP    = 16   -- spacing between motion cols
            -- Motion block sits right of numpad; 3 cols wide. Col 0 is
            -- reserved for 720 on row 5 (only); cols 1/2 hold the
            -- traditional motion palette. This avoids wasting a 6th row
            -- of the grid (which would push the 720 button under the
            -- input/legend area below) while keeping the layout
            -- visually grouped — 720 sits next to 360F/360B which is
            -- where the user expects double-circle motions to live.
            local mot_x      = dir_x + dir_pad_w + 18
            local mot_block_w = dir_cell + MOT_GAP + dir_cell + MOT_GAP + dir_cell  -- 3 cols
            -- Attacks sit right of motions.
            local atk_x      = mot_x + mot_block_w + 18
            local atk_cell_w = 72
            local atk_cell_h = 48
            local atk_gap    = 6

            -- Fake-circle helper: fill a circle using concentric inset rects.
            -- d2d has no native circle primitive; this tiles a close approximation.
            local function fill_circle(cx, cy, r, color)
                for dy = -r, r do
                    local hw = math.floor(math.sqrt(math.max(0, r*r - dy*dy)) + 0.5)
                    if hw > 0 then
                        d2d.fill_rect(cx - hw, cy + dy, hw*2, 1, color)
                    end
                end
            end
            local function outline_circle(cx, cy, r, color)
                fill_circle(cx, cy, r, color)
                fill_circle(cx, cy, r-2, 0xFF000000)  -- punch hole; caller draws content after
            end

            -- Helper: draw a round direction button
            local function dir_btn(col, row_i, label, token_val)
                local cx = dir_x + (col-1)*(dir_cell + dir_gap) + dir_cell/2
                local cy = content_y + (row_i-1)*(dir_cell + dir_gap) + dir_cell/2
                local r  = math.floor(dir_cell/2) - 1
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                -- Shadow
                fill_circle(cx+2, cy+2, r, 0x66000000)
                -- Fill
                fill_circle(cx, cy, r, hov and CN_DIR_HOVER or CN_DIR_BG)
                -- Border ring (draw ring by filling outer then punching inner)
                -- Simple approach: outline_rect on bounding box looks fine at this size
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, CN_DIR_BORDER)
                -- Label
                local tw, th = font_menu:measure(label)
                d2d.text(font_menu, label,
                    cx - tw/2, cy - th/2,
                    CN_DIR_TEXT)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="dir", v=token_val})
                end
            end

            -- Helper: draw a round attack button glyph
            local function atk_btn(col, row_i, label)
                local cx = atk_x + (col-1)*(atk_cell_w + atk_gap) + atk_cell_w/2
                local cy = content_y + (row_i-1)*(atk_cell_h + atk_gap) + atk_cell_h/2
                local r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 2
                local col_fill = CN_BTN_COLORS[label] or 0xFF666666
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                -- Shadow
                fill_circle(cx+2, cy+2, r, 0x66000000)
                -- Main fill
                fill_circle(cx, cy, r, hov and (col_fill + 0x00181818) or col_fill)
                -- Top highlight arc (small bright strip near top)
                fill_circle(cx, cy - math.floor(r*0.35), math.floor(r*0.55), 0x22FFFFFF)
                -- Border
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, 0x88FFFFFF)
                -- Label — collapse LP/MP/HP→"P" and LK/MK/HK→"K" so the
                -- glyph matches SF6's fist/foot button HUD style. Strength
                -- is conveyed by color (col_fill above). Other buttons
                -- (PP/KK/DR/DRC/MW) keep their original text label.
                local LETTER_MAP = {LP="P",MP="P",HP="P",LK="K",MK="K",HK="K"}
                local display = LETTER_MAP[label] or label
                local tw, th = font_button:measure(display)
                d2d.text(font_button, display,
                    cx - tw/2, cy - th/2,
                    CN_BTN_TEXT)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="btn", v=label})
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
            -- cancel button (muted background, CN_CANCEL_COL label)
            -- because both serve a separator/punctuation role.
            -- Width spans the full numpad (3 cells + 2 gaps); placed one
            -- row below the numpad's bottom row. The legend block starts
            -- at row-5 baseline so this fits with ~50px of breathing room.
            do
                local sep_x = dir_x
                local sep_y = content_y + 3*(dir_cell + dir_gap)
                local sep_w = dir_pad_w
                local sep_h = dir_cell - 8                  -- a bit shorter than a dir circle
                local hov   = hit_rect(sep_x, sep_y, sep_w, sep_h)
                d2d.fill_rect(sep_x+2, sep_y+2, sep_w, sep_h, 0x66000000)   -- shadow
                d2d.fill_rect(sep_x, sep_y, sep_w, sep_h,
                    hov and 0xFF3A3A4A or 0xFF252530)
                d2d.outline_rect(sep_x, sep_y, sep_w, sep_h, 1, 0x88AAAACC)
                local tw, th = font_button:measure(">")
                d2d.text(font_button, ">",
                    sep_x + (sep_w - tw)/2,
                    sep_y + (sep_h - th)/2,
                    CN_CANCEL_COL)
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
                local atk_right = atk_x + 4*(atk_cell_w + atk_gap) - atk_gap
                local col0_x  = mot_x
                local colA_x  = col0_x + dir_cell + MOT_GAP
                local colB_x  = colA_x + dir_cell + MOT_GAP
                local colC_x  = atk_right + 14
                -- col 0: 720 (standalone double-spin motion)
                -- col A/B: standard motion inputs (dir tokens)
                -- col C: SA buttons (btn tokens, gold tint)
                -- { col_x, row, display_label, token_val, raw?, is_sa? }
                local motion_cols = {
                    -- col0 (only rows 3-5 populated: dashes + 720)
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
                    local r    = math.floor(dir_cell/2) - 1
                    local hov  = hit_rect(bx, by, dir_cell, dir_cell)
                    local is_x2 = me[4] == "x2"
                    local is_sa = me[6] == true
                    local fill = is_sa  and (hov and 0xFF6A5500 or 0xFF3D3000)
                              or is_x2  and (hov and 0xFF5A3A6A or 0xFF3A2048)
                              or              (hov and CN_DIR_HOVER or CN_DIR_BG)
                    local border = is_sa  and 0xFFCCAA00
                                or is_x2  and 0xFF8855BB
                                or              CN_DIR_BORDER
                    local tcol  = is_sa  and 0xFFFFDD55
                               or is_x2  and 0xFFCC88FF
                               or              CN_DIR_TEXT
                    fill_circle(bcx+2, bcy+2, r, 0x66000000)
                    fill_circle(bcx, bcy, r, fill)
                    d2d.outline_rect(bx, by, dir_cell, dir_cell, 1, border)
                    local disp = (me[5] or is_x2) and me[3] or notation(me[3])
                    local lw, lh = font_menu:measure(disp)
                    d2d.text(font_menu, disp, bcx - lw/2, bcy - lh/2, tcol)
                    if cn_click(bx, by, dir_cell, dir_cell) then
                        -- SA buttons are btn tokens; everything else is dir
                        if is_sa then
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
                -- Classic palette — unchanged.
                -- Row 1: LP  MP  HP
                atk_btn(1, 1, "LP")
                atk_btn(2, 1, "MP")
                atk_btn(3, 1, "HP")
                -- Row 2: LK  MK  HK
                atk_btn(1, 2, "LK")
                atk_btn(2, 2, "MK")
                atk_btn(3, 2, "HK")
                -- Row 3: OD buttons
                atk_btn(1, 3, "PP")
                atk_btn(2, 3, "KK")
            end
            -- Row 3 col 3: xx cancel
            do
                local cx = atk_x + 2*(atk_cell_w + atk_gap) + atk_cell_w/2
                local cy = content_y + 2*(atk_cell_h + atk_gap) + atk_cell_h/2
                local r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 2
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                fill_circle(cx+2, cy+2, r, 0x66000000)
                fill_circle(cx, cy, r, hov and 0xFF3A3A4A or 0xFF252530)
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, 0x88AAAACC)
                local tw, th = font_button:measure("xx")
                d2d.text(font_button, "xx", cx - tw/2, cy - th/2, CN_CANCEL_COL)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="btn", v="xx"})
                end
            end
            -- Row 4: Drive / Walk mechanics
            atk_btn(1, 4, "DR")
            atk_btn(2, 4, "DRC")
            atk_btn(3, 4, "MW")
            -- Row 5: Oki
            do
                local oki_ctr    = slot_data.counter or 0
                local oki_prefix = oki_ctr > 0 and ("+"..oki_ctr)
                               or  oki_ctr < 0 and (tostring(oki_ctr))
                               or  "0"
                local oki_token  = "[" .. oki_prefix .. ":Oki]"
                local cx = atk_x + 0*(atk_cell_w + atk_gap) + atk_cell_w/2
                local cy = content_y + 4*(atk_cell_h + atk_gap) + atk_cell_h/2
                local r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 2
                local col_fill = CN_BTN_COLORS["Oki"] or 0xFF666666
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                fill_circle(cx+2, cy+2, r, 0x66000000)
                fill_circle(cx, cy, r, hov and (col_fill + 0x00181818) or col_fill)
                fill_circle(cx, cy - math.floor(r*0.35), math.floor(r*0.55), 0x22FFFFFF)
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, 0x88FFFFFF)
                local tw, th = font_button:measure("Oki")
                d2d.text(font_button, "Oki", cx - tw/2, cy - th/2, CN_BTN_TEXT)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="btn", v=oki_token})
                end
            end
            -- Row 5 col 2: F.Kill
            -- Mirrors Oki: bakes the slot counter into the token at
            -- insert time. Stored as `{t="fk", v="+5"}` (or "-3" / "0").
            -- Legacy tokens with no `v` field render as plain "F.Kill"
            -- — back-compat with combos saved before this change.
            do
                local fk_ctr    = slot_data.counter or 0
                local fk_prefix = fk_ctr > 0 and ("+"..fk_ctr)
                              or  fk_ctr < 0 and (tostring(fk_ctr))
                              or  "0"
                local cx = atk_x + 1*(atk_cell_w + atk_gap) + atk_cell_w/2
                local cy = content_y + 4*(atk_cell_h + atk_gap) + atk_cell_h/2
                local r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 2
                local col_fill = 0xFF8B1A1A
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                fill_circle(cx+2, cy+2, r, 0x66000000)
                fill_circle(cx, cy, r, hov and 0xFFAA2222 or col_fill)
                fill_circle(cx, cy - math.floor(r*0.35), math.floor(r*0.55), 0x22FFFFFF)
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, 0xAAFF6666)
                local tw, th = font_button:measure("F.Kill")
                d2d.text(font_button, "F.Kill", cx - tw/2, cy - th/2, 0xFFFF9999)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="fk", v=fk_prefix})
                end
            end
            -- Col 4, Rows 3/4/5: CH (Counter Hit), PC (Punish Counter),
            -- SHM (Shimmy). These are post-hit annotations — stored as
            -- standalone btn tokens (see STANDALONE_BTNS in tokens_to_seq).
            -- Shares the same circle look as the standard atk_btn so it
            -- visually groups with the rest of the attack pad.
            for _, info in ipairs({
                { row=3, label="CH"  },
                { row=4, label="PC"  },
                { row=5, label="SHM" },
            }) do
                local cx = atk_x + 3*(atk_cell_w + atk_gap) + atk_cell_w/2
                local cy = content_y + (info.row-1)*(atk_cell_h + atk_gap) + atk_cell_h/2
                local r  = math.floor(math.min(atk_cell_w, atk_cell_h)/2) - 2
                local col_fill = CN_BTN_COLORS[info.label] or 0xFF666666
                local hov = hit_rect(cx-r, cy-r, r*2, r*2)
                fill_circle(cx+2, cy+2, r, 0x66000000)
                fill_circle(cx, cy, r, hov and (col_fill + 0x00181818) or col_fill)
                fill_circle(cx, cy - math.floor(r*0.35), math.floor(r*0.55), 0x22FFFFFF)
                d2d.outline_rect(cx-r, cy-r, r*2, r*2, 1, 0x88FFFFFF)
                local tw, th = font_button:measure(info.label)
                d2d.text(font_button, info.label,
                    cx - tw/2, cy - th/2, CN_BTN_TEXT)
                if cn_click(cx-r, cy-r, r*2, r*2) then
                    insert_at_cursor({t="btn", v=info.label})
                end
            end

            -- ── RIGHT COLUMN: 30-slot scrollable list ────────
            -- Divider line between input pad and slot list
            local list_x = mx + input_w + 8
            d2d.fill_rect(list_x - 4, content_y, 1, mh - row_h - 16,
                0xFF3A3A55)

            local list_item_h = row_h + 2
            local cb_size     = cfg.menu_font_size - 4   -- checkbox square
            local title_x     = list_x + cb_size + 14    -- text starts after checkbox

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
                d2d.text(font_menu, hdr_lbl,
                    hdr_x, content_y - 2, C_DIM)

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
                local arr_y    = content_y - 4
                -- Up arrow
                do
                    local can = cn_refresh.notes_scroll > 0
                    local hov = can and hit_rect(arr_up_x, arr_y, arr_w, arr_h)
                    d2d.fill_rect(arr_up_x, arr_y, arr_w, arr_h,
                        can and (hov and C_BTN_ACTIVE or C_BTN_BG) or 0xFF0D0D0D)
                    d2d.outline_rect(arr_up_x, arr_y, arr_w, arr_h, 1,
                        can and C_BTN_BORDER or 0xFF2A2A2A)
                    local lw, lh = font_menu:measure("^")
                    d2d.text(font_menu, "^",
                        arr_up_x + (arr_w - lw)/2,
                        arr_y + (arr_h - lh)/2,
                        can and C_VALUE or C_DIM)
                    if can and cn_clicked and cn_hit(arr_up_x, arr_y, arr_w, arr_h) then
                        cn_clicked = false
                        cn_refresh.notes_scroll = cn_refresh.notes_scroll - 1
                    end
                end
                -- Down arrow
                do
                    local can = cn_refresh.notes_scroll < max_scroll
                    local hov = can and hit_rect(arr_dn_x, arr_y, arr_w, arr_h)
                    d2d.fill_rect(arr_dn_x, arr_y, arr_w, arr_h,
                        can and (hov and C_BTN_ACTIVE or C_BTN_BG) or 0xFF0D0D0D)
                    d2d.outline_rect(arr_dn_x, arr_y, arr_w, arr_h, 1,
                        can and C_BTN_BORDER or 0xFF2A2A2A)
                    local lw, lh = font_menu:measure("v")
                    d2d.text(font_menu, "v",
                        arr_dn_x + (arr_w - lw)/2,
                        arr_y + (arr_h - lh)/2,
                        can and C_VALUE or C_DIM)
                    if can and cn_clicked and cn_hit(arr_dn_x, arr_y, arr_w, arr_h) then
                        cn_clicked = false
                        cn_refresh.notes_scroll = cn_refresh.notes_scroll + 1
                    end
                end

                -- Render only the visible window of slots
                local first_slot = cn_refresh.notes_scroll + 1
                local last_slot  = math.min(COMBO_MAX_SLOTS, first_slot + cn_refresh.visible - 1)
                for s = first_slot, last_slot do
                    -- Visible-row index (0..VISIBLE-1) drives the y position;
                    -- the slot's real number `s` drives data lookups.
                    local row_idx = s - first_slot
                    local sy   = content_y + 16 + row_idx * list_item_h
                    local sdat = combos[s]
                    local is_edit = (s == combo_edit_slot)

                -- Highlight active editing row
                if is_edit then
                    d2d.fill_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h,
                        0xFF1E1E30)
                elseif hit_rect(list_x, sy, slot_list_w - 4, list_item_h) then
                    d2d.fill_rect(list_x, sy - 1,
                        slot_list_w - 4, list_item_h, 0xFF252535)
                end

                -- Checkbox (drawn; click handled by unified dispatcher below)
                local cb_x = list_x + 4
                local cb_y = sy + (list_item_h - cb_size) / 2
                d2d.fill_rect(cb_x, cb_y, cb_size, cb_size, 0xFF111118)
                d2d.outline_rect(cb_x, cb_y, cb_size, cb_size, 1, CN_DIR_BORDER)
                if sdat.active then
                    d2d.fill_rect(cb_x+2, cb_y+2, cb_size-4, cb_size-4, 0xFF32B46E)
                end

                -- Slot number prefix (always shown, not editable)
                local prefix = tostring(s) .. ". "
                local pw, _ = font_menu:measure(prefix)
                d2d.text(font_menu, prefix,
                    title_x, sy + (list_item_h - cfg.menu_font_size)/2,
                    is_edit and C_VALUE or CN_DIR_TEXT)

                -- Title (static d2d text)
                local tx2 = title_x + pw
                local title_label = (sdat.title and #sdat.title > 0)
                    and sdat.title or ("Slot " .. s)
                d2d.text(font_menu, title_label,
                    tx2, sy + (list_item_h - cfg.menu_font_size)/2,
                    is_edit and C_VALUE or CN_DIR_TEXT)

                -- ── Click handler: checkbox or row body ──────────
                if cn_clicked and cn_hit(list_x, sy, slot_list_w - 4, list_item_h) then
                    if hit_rect(cb_x, cb_y, cb_size, cb_size) then
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
            local scroll_lbl = first_slot .. "-" .. visible_end .. " / " .. COMBO_MAX_SLOTS
            local sll, _ = font_menu:measure(scroll_lbl)
            local list_bottom_y = content_y + 16 + cn_refresh.visible * list_item_h
            d2d.text(font_menu, scroll_lbl,
                list_x + (slot_list_w - sll) / 2,
                list_bottom_y + 2, C_DIM)

            -- Active count hint — anchored to the bottom of the
            -- *visible* list window, not the full slot count. With 30
            -- slots * 30px = 900px, anchoring to the full count would
            -- push this off the bottom of the 760px panel.
            local act_count = count_active(combos)
            local hint = act_count .. "/" .. COMBO_MAX_ACTIVE .. " shown on screen"
            local hl, _ = font_menu:measure(hint)
            d2d.text(font_menu, hint,
                list_x + (slot_list_w - hl) / 2,
                list_bottom_y + 4 + cfg.menu_font_size + 2,
                act_count >= COMBO_MAX_ACTIVE and C_BAD or C_DIM)

            -- ── Counter widget ────────────────────────────────
            -- Per-slot counter: -120 to +120, default 0.
            -- Useful for tracking frame advantage, oki distance etc.
            -- Anchor below the visible-window bottom (not full slot count).
            local ctr_y    = list_bottom_y + (cfg.menu_font_size + 4) * 2 + 6
            local ctr_val  = slot_data.counter or 0
            local ctr_w    = slot_list_w - 8
            local ctr_x    = list_x + 4
            local arrow_w  = 28
            local arrow_h  = row_h + 4
            local val_w    = ctr_w - arrow_w*2 - 4

            -- Label
            d2d.text(font_menu, "Counter:",
                ctr_x, ctr_y, C_DIM)
            ctr_y = ctr_y + row_h - 2

            -- [ < ] arrow
            local dec_x = ctr_x
            local hov_dec = hit_rect(dec_x, ctr_y, arrow_w, arrow_h)
            d2d.fill_rect(dec_x, ctr_y, arrow_w, arrow_h,
                hov_dec and C_BTN_ACTIVE or C_BTN_BG)
            d2d.outline_rect(dec_x, ctr_y, arrow_w, arrow_h, 1, C_BTN_BORDER)
            local al, ah = font_menu:measure("<")
            d2d.text(font_menu, "<",
                dec_x + (arrow_w-al)/2, ctr_y + (arrow_h-ah)/2, C_BTN_TEXT)
            if cn_click(dec_x, ctr_y, arrow_w, arrow_h) then
                slot_data.counter = math.max(-120, ctr_val - 1)
                combo_notes_dirty[char_name] = true
            end

            -- Value display (center)
            local val_x = dec_x + arrow_w + 2
            local val_str = tostring(ctr_val)
            if ctr_val > 0 then val_str = "+" .. val_str end
            local val_col = ctr_val > 0 and C_GOOD
                         or ctr_val < 0 and C_BAD
                         or C_DIM
            d2d.fill_rect(val_x, ctr_y, val_w, arrow_h, 0xFF0D0D18)
            d2d.outline_rect(val_x, ctr_y, val_w, arrow_h, 1, 0xFF2A2A3A)
            local vl, vh = font_menu:measure(val_str)
            d2d.text(font_menu, val_str,
                val_x + (val_w - vl)/2, ctr_y + (arrow_h - vh)/2, val_col)

            -- [ > ] arrow
            local inc_x = val_x + val_w + 2
            local hov_inc = hit_rect(inc_x, ctr_y, arrow_w, arrow_h)
            d2d.fill_rect(inc_x, ctr_y, arrow_w, arrow_h,
                hov_inc and C_BTN_ACTIVE or C_BTN_BG)
            d2d.outline_rect(inc_x, ctr_y, arrow_w, arrow_h, 1, C_BTN_BORDER)
            local al2, ah2 = font_menu:measure(">")
            d2d.text(font_menu, ">",
                inc_x + (arrow_w-al2)/2, ctr_y + (arrow_h-ah2)/2, C_BTN_TEXT)
            if cn_click(inc_x, ctr_y, arrow_w, arrow_h) then
                slot_data.counter = math.min(120, ctr_val + 1)
                combo_notes_dirty[char_name] = true
            end

            -- Reset to 0 on double-click area (click the value display)
            if cn_click(val_x, ctr_y, val_w, arrow_h) then
                slot_data.counter = 0
                combo_notes_dirty[char_name] = true
            end

            -- ── Hotkey legend ─────────────────────────────────
            -- Documents both the controller SHIFT modifier (MP+LK held
            -- with HP → ">" and LP → backspace) and the keyboard
            -- shortcuts (Backspace, arrow keys, Home/End). Lives in
            -- the empty space below the counter widget in the slot
            -- column. Mirrors the styling of the left-side Legend block
            -- (panel fill + outline + header label + colored tags).
            -- All helper locals are scoped inside an inner do/end so
            -- they don't leak; the outer do-block this section sits
            -- inside is the slot-list/counter scope (see comment at
            -- top of that block) so even without the inner do/end
            -- these locals wouldn't accumulate against the chunk cap.
            do
                local hk_top = ctr_y + arrow_h + 12
                local hk_x   = list_x + 4
                local hk_w   = slot_list_w - 8
                local hk_lh  = cfg.menu_font_size + 4
                -- Rows: header + modifier + 2 controller actions
                --     + keyboard subheader + 3 keyboard rows = 7 lines.
                -- The original 8-row version (with a blank spacer
                -- separating controller from keyboard) overflowed the
                -- panel's bottom action bar (~787px) by ~10px. Skipping
                -- the spacer keeps the legend visually clean while
                -- staying inside the panel — the "Keyboard" subheader
                -- text alone is enough of a visual break.
                local hk_h   = hk_lh * 7 + 10

                d2d.fill_rect(hk_x, hk_top, hk_w, hk_h, 0xFF101020)
                d2d.outline_rect(hk_x, hk_top, hk_w, hk_h, 1, 0xFF2A2A3A)
                d2d.text(font_menu, "Hotkeys", hk_x + 6, hk_top + 4, C_DIM)

                -- Helper: draw a "TAG  description" row with TAG in
                -- a button-color and the description dimmed. The
                -- description rendered as separate text after measuring
                -- the tag width so it lines up cleanly across rows.
                local function hk_row(row_idx, tag, tag_col, desc)
                    local ly = hk_top + 4 + hk_lh * row_idx
                    d2d.text(font_menu, tag, hk_x + 8, ly, tag_col)
                    local tw, _ = font_menu:measure(tag)
                    d2d.text(font_menu, "  " .. desc,
                        hk_x + 8 + tw, ly, C_DIM)
                end

                -- Row 1: the modifier itself. MP gets its yellow, LK
                -- gets blue (matching the button-bar coloring). Render
                -- as two short colored tags separated by " + ".
                do
                    local ly = hk_top + 4 + hk_lh * 1
                    local mp_col = CN_BTN_COLORS["MP"] or C_LABEL
                    local lk_col = CN_BTN_COLORS["LK"] or C_LABEL
                    d2d.text(font_menu, "Hold ", hk_x + 8, ly, C_DIM)
                    local pre_w, _ = font_menu:measure("Hold ")
                    d2d.text(font_menu, "MP", hk_x + 8 + pre_w, ly, mp_col)
                    local mp_w, _ = font_menu:measure("MP")
                    d2d.text(font_menu, "+", hk_x + 8 + pre_w + mp_w, ly, C_DIM)
                    local plus_w, _ = font_menu:measure("+")
                    d2d.text(font_menu, "LK",
                        hk_x + 8 + pre_w + mp_w + plus_w, ly, lk_col)
                end

                -- Row 2: HP → insert ">"
                hk_row(2, "HP",
                    CN_BTN_COLORS["HP"] or C_LABEL,
                    "= insert  >")
                -- Row 3: LP → backspace
                hk_row(3, "LP",
                    CN_BTN_COLORS["LP"] or C_LABEL,
                    "= backspace")

                -- Row 4: "Keyboard" subheader (immediately after the
                -- controller-action rows — no blank spacer between).
                d2d.text(font_menu, "Keyboard",
                    hk_x + 6, hk_top + 4 + hk_lh * 4, C_DIM)
                -- Row 5: arrows
                hk_row(5, "<- ->",
                    C_LABEL,
                    "= move cursor")
                -- Row 6: Home/End
                hk_row(6, "Home/End",
                    C_LABEL,
                    "= jump")
                -- Row 7: Backspace
                hk_row(7, "Bksp",
                    C_LABEL,
                    "= delete")
            end
            end  -- close slot-list + counter do/end block (see scope header above)

            -- ── Token preview strip ───────────────────────────────
            -- Anchored just below the direction pad (the tallest column),
            -- fills the empty space down to the bottom buttons.
            local preview_x0   = mx + 10
            local preview_maxw = input_w - 14
            local preview_lh   = cfg.menu_font_size + 6
            -- Dir pad is 5 rows: content_y + 5*(dir_cell+dir_gap) + small gap
            local grid_btm     = content_y + 5*(dir_cell + dir_gap) + 8
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
            local LEGEND_ROWS = {
                { "DR",     "Drive Rush" },
                { "DRC",    "Drive Rush Cancel" },
                { "MW",     "Micro-walk" },
                { "CH",     "Counter Hit" },
                { "PC",     "Punish Counter" },
                { "SHM",    "Shimmy" },
                { "F.Kill", "Frame Kill" },
                { "Oki",    "Set Counter, then press",
                            "Oki for +/- frames" },
                { "xx",     "Cancel" },
            }
            local legend_top = grid_btm
            local legend_lh  = cfg.menu_font_size + 4
            local legend_cols = 2
            local legend_rows_per_col = math.ceil(#LEGEND_ROWS / legend_cols)
            -- Add an extra line of height for each entry with a wrap
            -- continuation so the block fits both the wrapped row and
            -- any row that follows it in the same column.
            local extra_lines = 0
            for _, entry in ipairs(LEGEND_ROWS) do
                if entry[3] then extra_lines = extra_lines + 1 end
            end
            local legend_h    = (legend_rows_per_col + extra_lines) * legend_lh + 22

            d2d.fill_rect(preview_x0, legend_top,
                preview_maxw, legend_h, 0xFF101020)
            d2d.outline_rect(preview_x0, legend_top,
                preview_maxw, legend_h, 1, 0xFF2A2A3A)
            d2d.text(font_menu, "Legend",
                preview_x0 + 6, legend_top + 4, C_DIM)

            do
                local col_w = math.floor((preview_maxw - 12) / legend_cols)
                local row_y0 = legend_top + 4 + legend_lh
                -- Per-column line-offset accumulator: tracks how many
                -- extra lines wrap-continuations have inserted into
                -- this column so rows after the wrap render at the
                -- right y. Indexed by col_i (0-based).
                local col_offset = { [0] = 0, [1] = 0 }
                for i, entry in ipairs(LEGEND_ROWS) do
                    local col_i = math.floor((i - 1) / legend_rows_per_col)
                    local row_i = (i - 1) % legend_rows_per_col
                    local lx = preview_x0 + 6 + col_i * col_w
                    local ly = row_y0 + (row_i + col_offset[col_i]) * legend_lh
                    -- Tag (colored) + " = " + definition (dim)
                    local tag = entry[1]
                    local def = " = " .. entry[2]
                    -- Pick color from button color tables; fall back to dim.
                    local tag_col = CN_BTN_COLORS[tag]
                                 or (tag == "F.Kill" and 0xFFFF9999)
                                 or (tag == "xx"     and CN_CANCEL_COL)
                                 or C_LABEL
                    d2d.text(font_menu, tag, lx, ly, tag_col)
                    local tw_tag, _ = font_menu:measure(tag)
                    d2d.text(font_menu, def, lx + tw_tag, ly, C_DIM)
                    -- Wrap continuation: if entry[3] is set, render
                    -- it indented under the definition (aligned with
                    -- the start of the description text, not the tag)
                    -- and bump the column's offset so subsequent rows
                    -- in this column shift down by one line.
                    if entry[3] then
                        d2d.text(font_menu, "   " .. entry[3],
                            lx + tw_tag, ly + legend_lh, C_DIM)
                        col_offset[col_i] = col_offset[col_i] + 1
                    end
                end
            end

            -- Preview block now starts BELOW the legend.
            local preview_top  = legend_top + legend_h + 6
            local preview_btm  = bot_y_calc - 6  -- stops just above bottom buttons

            -- Background fill for the preview area
            d2d.fill_rect(preview_x0, preview_top,
                preview_maxw, preview_btm - preview_top, 0xFF0D0D18)
            d2d.outline_rect(preview_x0, preview_top,
                preview_maxw, preview_btm - preview_top, 1, 0xFF2A2A3A)

            -- Slot label
            local label_y = preview_top + 4
            row_label(preview_x0 + 6, label_y,
                tostring(combo_edit_slot) .. ". " .. slot_data.title .. ":",
                C_DIM)

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
                    -- Pre-measure separator if needed.
                    local sep_w = 0
                    if needs_sep then
                        local sw, _ = font_menu:measure(">")
                        sep_w = sw + 8  -- pad on either side
                    end

                    local tw2, _ = font_menu:measure(tlabel)
                    if px2 + sep_w + tw2 + 4 > preview_x0 + preview_maxw - 4 then
                        px2 = preview_x0 + 6
                        py2 = py2 + preview_lh
                        if py2 + preview_lh > preview_btm then break end
                    end

                    -- Draw separator (faint, like in the ticker).
                    if needs_sep then
                        d2d.text(font_menu, ">",
                            px2 + 2,
                            py2 + (preview_lh - cfg.menu_font_size)/2,
                            CN_CANCEL_COL)
                        px2 = px2 + sep_w
                    end

                    local tcol = is_xx and CN_CANCEL_COL
                             or is_fk and 0xFFFF9999
                             or is_sep and CN_CANCEL_COL
                             or (tok.t == "btn") and (CN_BTN_COLORS[tok.v] or C_LABEL)
                             or CN_DIR_TEXT

                    -- Highlight token under mouse — visual cue this is clickable.
                    local tok_x, tok_y, tok_w, tok_h = px2 - 2, py2, tw2 + 4, preview_lh
                    if cn_hit(tok_x, tok_y, tok_w, tok_h) then
                        d2d.fill_rect(tok_x, tok_y, tok_w, tok_h, 0x22FFFFFF)
                    end

                    d2d.text(font_menu, tlabel, px2,
                        py2 + (preview_lh - cfg.menu_font_size)/2, tcol)

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

            -- ── Bottom buttons ────────────────────────────────────
            local bh2   = row_h + 4
            local bot_y = my + mh - bh2 - 6

            local function cn_btn(bx, by, bw, bh, label)
                local hov = cn_hit(bx, by, bw, bh)
                d2d.fill_rect(bx, by, bw, bh, hov and C_BTN_ACTIVE or C_BTN_BG)
                d2d.outline_rect(bx, by, bw, bh, 1, C_BTN_BORDER)
                local tw, th = font_button:measure(label)
                d2d.text(font_button, label,
                    bx+(bw-tw)/2, by+(bh-th)/2, C_BTN_TEXT)
                return cn_click(bx, by, bw, bh)
            end

            if cn_btn(mx+10, bot_y, 110, bh2, "< Backspace") then
                -- Delete the token immediately before the cursor, then
                -- shift cursor left — exactly like a keyboard backspace.
                if combo_edit_cursor > 0 and #tokens > 0 then
                    table.remove(tokens, combo_edit_cursor)
                    combo_edit_cursor = combo_edit_cursor - 1
                    combo_notes_dirty[char_name] = true
                end
            end
            if cn_btn(mx+130, bot_y, 80, bh2, "Clear") then
                combos[combo_edit_slot].tokens = {}
                combo_edit_cursor = 0
                combo_notes_dirty[char_name] = true
            end

            -- SHIFT modifier feature was removed; the legend pill that
            -- previously showed "HOLD <btn> | > LP | xx MP | ..." is no
            -- longer rendered. Use the on-screen palette buttons in the
            -- editor (>, xx, Backspace, Clear) to insert those tokens.



            -- Save button removed — every edit marks the slot dirty and
            -- the dirty queue auto-flushes via re.on_frame. Close still
            -- here so the user can dismiss the panel.
            if cn_btn(mx+mw-90, bot_y, 80, bh2, "Close") then
                show_combo_notes_win = false
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
        imgui.text("  P1 X: " .. tostring(dbg_p1x) .. "  P2 X: " .. tostring(dbg_p2x))
        imgui.text("  P1 Y: " .. tostring(dbg_p1y) .. "  Z: " .. tostring(dbg_p1z) .. "  airborne: " .. tostring(is_airborne))
        imgui.text("  Fields: " .. (dbg_fields and table.concat(dbg_fields, " ") or "none"))
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
