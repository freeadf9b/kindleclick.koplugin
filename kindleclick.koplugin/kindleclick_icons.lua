--[[--
Three-state status icons for Kindle Click.

All presets are present in KOReader's bundled nerdfonts/symbols.ttf. Users can
also enter any Unicode codepoint. This module performs no I/O unless a setting
is read or changed; it never starts a timer or a background process.
--]]

local _ = require("kindleclick_gettext")

local DataStorage = require("datastorage")
local logger = require("logger")

local Icons = {}

local FONT_FILE = "kindleclick-icons.kfont"
-- Bump when the bundled font changes; the plugin overwrites the installed copy
-- and asks for a restart, because the old glyphs stay cached otherwise.
local FONT_VERSION = "1.7.20b"
Icons.FONT_VERSION = FONT_VERSION

-- Glyphs shipped in fonts/kindleclick-icons.kfont. They live in the
-- supplementary private use area: a Nerd Fonts footer face (symbols.ttf) also
-- covers U+E900-U+E902 and, being the footer's own face, would win before any
-- fallback. Plane 15 is not covered by those fonts, so the fallback chain
-- reaches ours regardless of which font the footer uses.
Icons.CUSTOM = {
    off = 0xF0000,
    on = 0xF0001,
    click = 0xF0002,
}

-- Older releases stored U+E900-U+E902. Migrate them on startup so users do not
-- have to re-pick their icons after the font update.
Icons.LEGACY_CUSTOM = {
    [0xE900] = 0xF0000,
    [0xE901] = 0xF0001,
    [0xE902] = 0xF0002,
}

Icons.STATES = {
    { id = "off", label = _("Bluetooth off"), key = "kindleclick_icon_off", default = 0xE7B1 },
    { id = "on", label = _("Bluetooth on, Click disconnected"), key = "kindleclick_icon_on", default = 0xE7AE },
    { id = "click", label = _("Kindle Click connected"), key = "kindleclick_icon_click", default = 0xEB53 },
}

-- Names and codepoints checked against the cmap of KOReader's symbols.ttf.
Icons.PRESETS = {
    { code = 0xF0000, label = _("My icon: Bluetooth off") },
    { code = 0xF0001, label = _("My icon: Bluetooth on") },
    { code = 0xF0002, label = _("My icon: connected") },
    { code = 0xE7B1, label = _("Bluetooth off") },
    { code = 0xE7AE, label = _("Bluetooth") },
    { code = 0xE7B0, label = _("Bluetooth connected") },
    { code = 0xEB53, label = _("Remote control") },
    { code = 0xE995, label = _("Gamepad") },
    { code = 0xE7B9, label = _("Book") },
    { code = 0xE28A, label = _("Open book") },
    { code = 0xEA36, label = _("Link") },
    { code = 0xEA37, label = _("Unlink") },
    { code = 0xECDF, label = _("Check mark in circle") },
    { code = 0xEE63, label = _("Filled circle") },
    { code = 0xEE64, label = _("Hollow circle") },
    { code = 0xEC20, label = _("Switch on") },
    { code = 0xEC21, label = _("Switch off") },
    { code = 0xEB24, label = _("Power") },
    { code = 0xF25A, label = _("Legacy tap gesture") },
}

-- KOReader reads font_ui_fallbacks only at startup and inserts those fonts
-- after NotoSansCJKsc. Put the icon font first at runtime too, so private-use
-- glyphs are resolved by our font before any other fallback that happens to
-- cover the same codepoint. Face objects cache their fallback chain, so drop
-- those chains as well.
local function promote_runtime_fallback(target)
    local ok, Font = pcall(require, "ui/font")
    if not ok or type(Font) ~= "table" or type(Font.fallbacks) ~= "table" then
        return "no ui/font"
    end
    for i = #Font.fallbacks, 1, -1 do
        local name = Font.fallbacks[i]
        if type(name) == "string" and name:sub(-#FONT_FILE) == FONT_FILE then
            table.remove(Font.fallbacks, i)
        end
    end
    table.insert(Font.fallbacks, 1, target)
    if type(Font.faces) == "table" then
        for _, face in pairs(Font.faces) do
            if type(face) == "table" then face.fallbacks = nil end
        end
    end
    local glyphs = false
    pcall(function()
        local face = Font:getFace(target, 16)
        glyphs = face and face.ftsize
            and face.ftsize:hasGlyph(Icons.CUSTOM.off)
            and face.ftsize:hasGlyph(Icons.CUSTOM.on)
            and face.ftsize:hasGlyph(Icons.CUSTOM.click) or false
    end)
    return string.format("fallback#1 glyphs=%s", glyphs and "ok" or "missing")
end

-- True when KOReader's FreeType can load the icon face and find the three
-- custom glyphs. `name` must be a KOReader font name relative to its fonts/
-- directory (e.g. "kindleclick-icons.kfont"): this build resolves bare names
-- as "./fonts/<name>" but would double-prefix a name that already starts
-- with "./fonts/".
function Icons.fontHasGlyphs(name)
    if type(name) ~= "string" or name == "" then return false end
    local ok, Font = pcall(require, "ui/font")
    if not ok or type(Font) ~= "table" or not Font.getFace then return false end
    local loaded = false
    pcall(function()
        local face = Font:getFace(name, 16)
        loaded = face and face.ftsize
            and face.ftsize:hasGlyph(Icons.CUSTOM.off)
            and face.ftsize:hasGlyph(Icons.CUSTOM.on)
            and face.ftsize:hasGlyph(Icons.CUSTOM.click) or false
    end)
    return loaded and true or false
end

function Icons.faceName()
    -- Font:getFace() prepends its fonts/ directory to names that do not start
    -- with "./" or "/", so the registered name must stay bare.
    return FONT_FILE
end

function Icons.fontPath()
    -- Keep the file inside KOReader's fonts/ directory, which its loader has
    -- always resolved correctly for us, but use a non-font extension: crengine
    -- scans fonts/ for .ttf/.otf at startup and tries to register this
    -- icon-only face as a document font, which fails and fills crash.log.
    -- FreeType loads by file content, not by extension, so .kfont works.
    return DataStorage:getDataDir() .. "/fonts/" .. FONT_FILE
end

-- Result of the most recent runtime fallback reordering, for the [icons] log.
function Icons.describeRuntimeFallback()
    return Icons._runtime_fallback or "unknown"
end

-- Copy the shipped icon font next to KOReader's settings and register it as
-- an additional UI fallback font. Returns "registered" when nothing changed,
-- or "needs_restart" when the font or the fallback list was just updated
-- (KOReader reads both only at startup).
function Icons.ensureFont(plugin_dir)
    local changed = false
    local source = plugin_dir and (plugin_dir .. "/fonts/" .. FONT_FILE)
    local installed = G_reader_settings:readSetting("kindleclick_icon_font_version")
    local function exists(path)
        local handle = io.open(path, "rb")
        if not handle then return false end
        handle:close()
        return true
    end
    local function copy_to(path)
        local src = io.open(source, "rb")
        if not src then return false end
        local data = src:read("*a")
        src:close()
        local dir = path:match("^(.*)/[^/]+$")
        if dir then os.execute(string.format('mkdir -p "%s"', dir)) end
        local dst = io.open(path, "wb")
        if not dst then return false end
        dst:write(data)
        dst:close()
        return true
    end

    Icons.migrateCustom()

    local data_dir = DataStorage:getDataDir()
    local target = Icons.fontPath()
    local face = Icons.faceName()
    -- 1.7.19 and earlier used fonts/kindleclick-icons.ttf; 1.7.20 briefly used
    -- the KOReader root. Remove both once the .kfont copy is verified.
    local legacy_paths = {
        data_dir .. "/fonts/kindleclick-icons.ttf",
        data_dir .. "/kindleclick-icons.ttf",
    }

    local needs_copy = installed ~= FONT_VERSION
        or not exists(target)
        or not Icons.fontHasGlyphs(face)
    if source and needs_copy then
        if not Icons.fontHasGlyphs(face) and copy_to(target) then
            logger.info("KindleClick: icon font written to " .. target)
        end
        if Icons.fontHasGlyphs(face) then
            changed = true
        else
            logger.warn("KindleClick: " .. target .. " did not load")
        end
        G_reader_settings:saveSetting("kindleclick_icon_font_version", FONT_VERSION)
    elseif source and not exists(source) then
        logger.warn("KindleClick: icon font not found at " .. tostring(source))
    end

    -- If this KOReader build refuses the .kfont name, fall back to a .ttf copy
    -- (which costs a crengine warning but keeps the icons visible).
    local register_target = face
    if not Icons.fontHasGlyphs(face) then
        local legacy_ttf = data_dir .. "/fonts/kindleclick-icons.ttf"
        if not exists(legacy_ttf) and source and copy_to(legacy_ttf) then
            logger.warn("KindleClick: .kfont did not load; wrote a .ttf fallback")
        end
        if exists(legacy_ttf) and Icons.fontHasGlyphs("kindleclick-icons.ttf") then
            register_target = "kindleclick-icons.ttf"
            logger.warn("KindleClick: using legacy icon font at " .. legacy_ttf)
        end
    end
    if register_target == face then
        for _, legacy_path in ipairs(legacy_paths) do
            if exists(legacy_path) then
                os.remove(legacy_path)
                logger.info("KindleClick: removed legacy icon font at " .. legacy_path)
            end
        end
    end

    local fallbacks = G_reader_settings:readSetting("font_ui_fallbacks", {})
    if type(fallbacks) ~= "table" then fallbacks = {} end
    local deduped = {}
    local registered = false
    local removed_stale = false
    for _, item in ipairs(fallbacks) do
        local is_ours = type(item) == "string" and (
            item:sub(-#FONT_FILE) == FONT_FILE
            or item:sub(-#"kindleclick-icons.ttf") == "kindleclick-icons.ttf")
        if item == register_target then
            -- Already registered: never insert a second copy.
            registered = true
            table.insert(deduped, item)
        elseif is_ours then
            -- An older copy of this same font at another path: drop it.
            removed_stale = true
        else
            table.insert(deduped, item)
        end
    end
    if not registered then
        table.insert(deduped, 1, register_target)
        logger.info("KindleClick: icon font registered as UI fallback, restart needed")
        changed = true
    elseif removed_stale then
        changed = true
    end
    if removed_stale or not registered then
        G_reader_settings:saveSetting("font_ui_fallbacks", deduped)
    end

    Icons._runtime_fallback = promote_runtime_fallback(register_target)

    return changed and "needs_restart" or "registered"
end

function Icons.useCustom(plugin)
    for _, state in ipairs(Icons.STATES) do
        G_reader_settings:saveSetting(state.key, Icons.CUSTOM[state.id])
    end
    if plugin then plugin:_updateFooter() end
end

function Icons.migrateCustom()
    for _, state in ipairs(Icons.STATES) do
        local codepoint = Icons.parseCodepoint(G_reader_settings:readSetting(state.key))
        local mapped = codepoint and Icons.LEGACY_CUSTOM[codepoint]
        if mapped then
            G_reader_settings:saveSetting(state.key, mapped)
        end
    end
end

function Icons.isCustom(codepoint)
    for _, code in pairs(Icons.CUSTOM) do
        if code == codepoint then return true end
    end
    return false
end

function Icons.parseCodepoint(value)
    if type(value) == "number" then
        local codepoint = math.floor(value)
        if codepoint ~= value then return nil end
        value = codepoint
    elseif type(value) == "string" then
        local text = value:match("^%s*(.-)%s*$"):upper()
        text = text:gsub("^U%+", ""):gsub("^0X", "")
        if not text:match("^%x+$") then return nil end
        value = tonumber(text, 16)
    else
        return nil
    end

    if not value or value < 0x20 or value > 0x10FFFF
        or (value >= 0xD800 and value <= 0xDFFF) then
        return nil
    end
    return value
end

-- LuaJIT on KOReader does not guarantee a standard utf8 library.
function Icons.encode(codepoint)
    codepoint = Icons.parseCodepoint(codepoint)
    if not codepoint then return nil end
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40)
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40)
    end
    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40)
end

function Icons.getState(state_id)
    for _, state in ipairs(Icons.STATES) do
        if state.id == state_id then return state end
    end
    return Icons.STATES[1]
end

function Icons.getCodepoint(state_id)
    local state = Icons.getState(state_id)
    local saved = G_reader_settings:readSetting(state.key, state.default)
    return Icons.parseCodepoint(saved) or state.default
end

function Icons.getGlyph(state_id)
    return Icons.encode(Icons.getCodepoint(state_id))
end

function Icons.isPreset(codepoint)
    for _, preset in ipairs(Icons.PRESETS) do
        if preset.code == codepoint then return true end
    end
    return false
end

local function setIcon(plugin, state, codepoint)
    G_reader_settings:saveSetting(state.key, codepoint)
    plugin:_updateFooter()
end

local function showCustomCodepointDialog(plugin, state, touchmenu)
    local InputDialog = require("ui/widget/inputdialog")
    local UIManager = require("ui/uimanager")
    local dialog
    dialog = InputDialog:new{
        title = state.label .. _(": Custom icon"),
        description = _([[Enter the Unicode codepoint of a glyph in KOReader's nerdfonts/symbols.ttf, such as U+EB53 (remote control). Other Unicode codepoints are also accepted; a missing glyph appears as a box.]]),
        input = string.format("U+%04X", Icons.getCodepoint(state.id)),
        input_hint = "U+EB53",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        local codepoint = Icons.parseCodepoint(dialog:getInputText())
                        if not codepoint then
                            plugin:_showMessage(_("Invalid codepoint. Enter a value such as U+EB53."), 4)
                            return
                        end
                        setIcon(plugin, state, codepoint)
                        if touchmenu then touchmenu:updateItems() end
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Icons.getMenu(plugin)
    local menu = {
        {
            text = _("Use my icons for all three states (off / on / connected)"),
            keep_menu_open = true,
            separator = true,
            callback = function()
                Icons.useCustom(plugin)
                if plugin then
                    plugin:_showMessage(
                        _("Using the icons bundled with the plugin. If they appear as boxes, restart KOReader to load the font."), 6)
                end
            end,
        },
    }
    for state_index, state in ipairs(Icons.STATES) do
        table.insert(menu, {
            text_func = function()
                return state.label .. "：" .. Icons.getGlyph(state.id)
            end,
            sub_item_table_func = function()
                local choices = {}
                for _, preset in ipairs(Icons.PRESETS) do
                    table.insert(choices, {
                        text = Icons.encode(preset.code) .. "  " .. preset.label
                            .. string.format("  U+%04X", preset.code),
                        checked_func = function()
                            return Icons.getCodepoint(state.id) == preset.code
                        end,
                        check_callback_updates_menu = true,
                        keep_menu_open = true,
                        callback = function(touchmenu)
                            setIcon(plugin, state, preset.code)
                            if touchmenu then touchmenu:updateItems() end
                        end,
                    })
                end
                table.insert(choices, {
                    text = _("Custom Unicode codepoint..."),
                    checked_func = function()
                        return not Icons.isPreset(Icons.getCodepoint(state.id))
                    end,
                    separator = true,
                    callback = function(touchmenu)
                        showCustomCodepointDialog(plugin, state, touchmenu)
                    end,
                })
                table.insert(choices, {
                    text = _("Restore this state's default icon"),
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        setIcon(plugin, state, state.default)
                        if touchmenu then touchmenu:updateItems() end
                    end,
                })
                return choices
            end,
        })
    end
    return menu
end

function Icons.deleteSettings()
    for _, state in ipairs(Icons.STATES) do
        G_reader_settings:delSetting(state.key)
    end
end

return Icons
