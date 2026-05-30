-- sf6_roster_export.lua
-- ============================================================================
-- Standalone roster exporter for the SF6 Overlay toolchain.
-- Place in: <SF6>/reframework/autorun/sf6_roster_export.lua
--
-- WHAT IT DOES
--   On game launch it reads SF6's live master data and writes the current
--   character roster to  reframework/data/sf6_roster.json . The Python editor
--   (server.py) reads that file, so a newly released character appears in the
--   web editor with ZERO code edits — the game itself is the source of truth.
--
-- DATA PATH (all confirmed via runtime probing):
--   app.TableDataManager
--     .FighterMessageUserDataDict : Dictionary<UInt32, RecordHolder<FighterMessageUserDataRecord>>
--         RecordHolder.RecordData.FighterName.GUID : System.Guid
--         -> via.gui.message.get(GUID) resolves to the display name string
--     .CHARA_IDUserDataDict : Dictionary<UInt32, RecordHolder<CHARA_IDUserDataRecord>>
--         RecordHolder.RecordData.ManageId  : UInt32  (== character index / esf number)
--         RecordHolder.RecordData.forSystem : bool    (true = system/dummy slot)
--
--   A character is considered "real roster" if it has BOTH a CHARA_ID entry
--   (forSystem=false) AND a resolvable FighterName. That intersection drops
--   system slots and nameless NPC ids automatically.
--
-- OUTPUT (sf6_roster.json):
--   {
--     "characters": [
--       { "esf": "esf001", "manage_id": 1, "name": "Ryu" },
--       ...
--     ]
--   }
--   Written only when content changes (idempotent; safe to run every launch).
--
-- SAFETY
--   * Top-level load is NOT a d2d callback, so direct io.open is fine here.
--   * Everything is wrapped so a failure leaves any existing JSON untouched.
--   * Runs once, deferred ~5s after load so master data is populated. A button
--     under "Script Generated UI" lets you force a re-export.
-- ============================================================================

local OUT_PATH = "sf6_roster.json"   -- resolves under reframework/data/

-- ---- safe reflection helpers --------------------------------------------
local function dm(o, m, ...)  -- direct method on userdata (reflection layer)
    if not o then return nil end
    local ok, r = pcall(function(...) return o[m](o, ...) end, ...)
    if ok then return r end
end
local function mc(o, m, ...)  -- managed :call
    if not o then return nil end
    local ok, r = pcall(function(...) return o:call(m, ...) end, ...)
    if ok then return r end
end
local function field_val(obj, fname)
    local td = dm(obj, "get_type_definition"); if not td then return nil end
    local fld = dm(td, "get_field", fname); if not fld then return nil end
    local v; pcall(function() v = fld:get_data(obj) end); return v
end

-- via.gui.message.get(guid) -> name string. Cache the method object.
local _msg_get = nil
local function resolve_message(guid)
    if guid == nil then return nil end
    if not _msg_get then
        local mtd = sdk.find_type_definition("via.gui.message")
        if mtd then _msg_get = dm(mtd, "get_method", "get") end
        if not _msg_get then return nil end
    end
    local ok, res = pcall(function() return _msg_get:call(nil, guid) end)
    if not ok or res == nil then
        ok, res = pcall(function() return _msg_get:call(guid) end)
    end
    if not res then return nil end
    if type(res) == "string" then return res end
    local t = mc(res, "ToString")
    if type(t) == "string" then return t end
    return tostring(res)
end

-- Enumerate a TableDataManager dict field -> array of RecordData objects,
-- paired with their ManageId for keying.
local function each_record(tdm, field_name, fn)
    local td = dm(tdm, "get_type_definition")
    local fld = td and dm(td, "get_field", field_name)
    if not fld then return end
    local dict; pcall(function() dict = fld:get_data(tdm) end)
    if not dict then return end
    local values = mc(dict, "get_Values")
    local enum = mc(values, "GetEnumerator") or mc(dict, "GetEnumerator")
    if not enum then return end
    while mc(enum, "MoveNext") do
        local holder = mc(enum, "get_Current")
        local rec = holder and field_val(holder, "RecordData")
        if rec then fn(rec) end
    end
end

-- ---- name normalization --------------------------------------------------
-- The game's display string may differ in case/spacing from the folder &
-- server.py spellings. Map resolved-name -> canonical project name here.
-- Only add an entry when an auto-resolved name doesn't match your folder name.
-- (Left mostly empty by design; fill in if a character mismatches.)
-- Keyed by the EXACT string via.gui.message.get returns (observed in export),
-- value = the canonical project folder/server.py spelling.
local NAME_FIX = {
    ["A.K.I."]       = "AKI",
    ["Edmond Honda"] = "E.Honda",
    ["C. Viper"]     = "C.Viper",
    -- M.Bison already matches; add more here only if a future character's
    -- resolved name differs from its framedata folder name.
}
local function canon(name)
    if not name then return nil end
    return NAME_FIX[name] or name  -- trust the game's spelling unless overridden
end

-- ---- build roster --------------------------------------------------------
local function build_roster()
    local tdm = sdk.get_managed_singleton("app.TableDataManager")
    if not tdm then return nil, "TableDataManager not live yet" end

    -- 1) ManageId -> name via FighterMessage + message resolution
    local names = {}
    each_record(tdm, "FighterMessageUserDataDict", function(rec)
        local id = field_val(rec, "ManageId")
        local fname_obj = field_val(rec, "FighterName")
        local guid = fname_obj and field_val(fname_obj, "GUID")
        local nm = resolve_message(guid)
        if id ~= nil and nm and nm ~= "" then
            names[math.floor(id)] = canon(nm)
        end
    end)

    -- 2) CHARA_ID gives the authoritative id set + system filter
    -- Real fighters are low, contiguous-ish ManageIds. Sentinel/utility slots
    -- like "Random" (id 254) are forSystem=false but not real characters, so
    -- also bound by a ceiling and an explicit exclusion set.
    local MAX_REAL_ID = 200          -- anything above is a sentinel (e.g. Random=254)
    local EXCLUDE = { [254] = true } -- explicit non-fighter slots by ManageId
    local chars = {}
    each_record(tdm, "CHARA_IDUserDataDict", function(rec)
        local id  = field_val(rec, "ManageId")
        local sys = field_val(rec, "forSystem")
        if id ~= nil and sys ~= true then
            id = math.floor(id)
            local nm = names[id]
            if nm and id <= MAX_REAL_ID and not EXCLUDE[id] then
                chars[#chars + 1] = { manage_id = id, name = nm }
            end
        end
    end)

    if #chars == 0 then return nil, "no characters resolved (wrong scene? data not loaded?)" end

    -- sort by manage_id (== esf order) for stable output
    table.sort(chars, function(a, b) return a.manage_id < b.manage_id end)
    return chars
end

-- ---- JSON (manual build; no BOM, matches project convention) ------------
local function build_json(chars)
    local parts = {}
    for _, c in ipairs(chars) do
        parts[#parts + 1] = string.format(
            '    {"esf": "esf%03d", "manage_id": %d, "name": %q}',
            c.manage_id, c.manage_id, c.name)
    end
    return "{\n  \"characters\": [\n" .. table.concat(parts, ",\n") .. "\n  ]\n}\n"
end

-- ---- idempotent write ----------------------------------------------------
local function export(reason)
    local ok, chars_or_err, err = pcall(build_roster)
    if not ok then
        log.warn("[roster_export] build failed: " .. tostring(chars_or_err))
        return false
    end
    local chars = chars_or_err
    if not chars then
        log.info("[roster_export] skip (" .. tostring(err) .. ")")
        return false
    end

    local payload = build_json(chars)

    local existing = nil
    local rf = io.open(OUT_PATH, "r")
    if rf then existing = rf:read("*a"); rf:close() end

    if existing == payload then
        log.info("[roster_export] roster unchanged (" .. #chars .. " chars)")
        return true
    end

    local wf = io.open(OUT_PATH, "w")
    if not wf then log.warn("[roster_export] cannot open " .. OUT_PATH .. " for write"); return false end
    wf:write(payload); wf:close()
    log.info(string.format("[roster_export] wrote %d characters (%s)", #chars, tostring(reason)))
    return true
end

-- ---- triggers ------------------------------------------------------------
local t0, did = os.clock(), false
re.on_frame(function()
    if not did and (os.clock() - t0) > 5.0 then
        did = true
        pcall(export, "auto-5s")
    end
end)

re.on_draw_ui(function()
    if imgui.button("Export SF6 Roster JSON now") then
        pcall(export, "manual")
    end
end)
