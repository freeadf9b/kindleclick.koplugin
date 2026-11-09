--[[--
Three-state status icons for Kindle Click.

All presets are present in KOReader's bundled nerdfonts/symbols.ttf. Users can
also enter any Unicode codepoint. This module performs no I/O unless a setting
is read or changed; it never starts a timer or a background process.
--]]

local _ = require("gettext")

local DataStorage = require("datastorage")
local logger = require("logger")

local Icons = {}

local FONT_FILE = "kindleclick-icons.ttf"
-- Bump when the bundled font changes; the plugin overwrites the installed copy
-- and asks for a restart, because the old glyphs stay cached otherwise.
local FONT_VERSION = "1.7.4"
Icons.FONT_VERSION = FONT_VERSION

-- Glyphs shipped in fonts/kindleclick-icons.ttf (private-use area).
Icons.CUSTOM = {
    off = 0xE900,
    on = 0xE901,
    click = 0xE902,
}

Icons.STATES = {
    { id = "off", label = _("蓝牙关闭"), key = "kindleclick_icon_off", default = 0xE7B1 },
    { id = "on", label = _("蓝牙开启，Click 未连接"), key = "kindleclick_icon_on", default = 0xE7AE },
    { id = "click", label = _("Kindle Click 已连接"), key = "kindleclick_icon_click", default = 0xEB53 },
}

-- Names and codepoints checked against the cmap of KOReader's symbols.ttf.
Icons.PRESETS = {
    { code = 0xE900, label = _("我的图标：蓝牙关闭") },
    { code = 0xE901, label = _("我的图标：蓝牙开启") },
    { code = 0xE902, label = _("我的图标：已连接") },
    { code = 0xE7B1, label = _("蓝牙关闭") },
    { code = 0xE7AE, label = _("蓝牙") },
    { code = 0xE7B0, label = _("蓝牙已连接") },
    { code = 0xEB53, label = _("遥控器") },
    { code = 0xE995, label = _("游戏手柄") },
    { code = 0xE7B9, label = _("书本") },
    { code = 0xE28A, label = _("打开的书") },
    { code = 0xEA36, label = _("链接") },
    { code = 0xEA37, label = _("断开链接") },
    { code = 0xECDF, label = _("圆形对勾") },
    { code = 0xEE63, label = _("实心圆") },
    { code = 0xEE64, label = _("空心圆") },
    { code = 0xEC20, label = _("开关开启") },
    { code = 0xEC21, label = _("开关关闭") },
    { code = 0xEB24, label = _("电源") },
    { code = 0xF25A, label = _("旧版点击手势") },
}

function Icons.fontPath()
    return DataStorage:getDataDir() .. "/fonts/" .. FONT_FILE
end

-- Copy the shipped icon font into KOReader's font directory and register it
-- as an additional UI fallback font. Returns "registered" when nothing
-- changed, or "needs_restart" when the font or the fallback list was just
-- updated (KOReader reads both only at startup).
function Icons.ensureFont(plugin_dir)
    local changed = false
    local target = Icons.fontPath()
    local source = plugin_dir and (plugin_dir .. "/fonts/" .. FONT_FILE)
    local installed = G_reader_settings:readSetting("kindleclick_icon_font_version")

    if source and installed ~= FONT_VERSION then
        local src = io.open(source, "rb")
        if src then
            local data = src:read("*a")
            src:close()
            local dir = target:match("^(.*)/[^/]+$")
            if dir then os.execute(string.format('mkdir -p "%s"', dir)) end
            local dst = io.open(target, "wb")
            if dst then
                dst:write(data)
                dst:close()
                G_reader_settings:saveSetting("kindleclick_icon_font_version", FONT_VERSION)
                logger.info("KindleClick: icon font updated to " .. FONT_VERSION)
                changed = true
            end
        else
            logger.warn("KindleClick: icon font not found at " .. tostring(source))
        end
    end

    local fallbacks = G_reader_settings:readSetting("font_ui_fallbacks", {})
    if type(fallbacks) ~= "table" then fallbacks = {} end
    local deduped = {}
    local registered = false
    local removed_stale = false
    for _, item in ipairs(fallbacks) do
        if item == target then
            -- Already registered: never insert a second copy.
            registered = true
            table.insert(deduped, item)
        elseif type(item) == "string" and item:sub(-#FONT_FILE) == FONT_FILE then
            -- An older copy of this same font at another path: drop it.
            removed_stale = true
        else
            table.insert(deduped, item)
        end
    end
    if not registered then
        table.insert(deduped, 1, target)
        logger.info("KindleClick: icon font registered as UI fallback, restart needed")
        changed = true
    end
    if removed_stale or not registered then
        G_reader_settings:saveSetting("font_ui_fallbacks", deduped)
    end

    return changed and "needs_restart" or "registered"
end

function Icons.useCustom(plugin)
    for _, state in ipairs(Icons.STATES) do
        G_reader_settings:saveSetting(state.key, Icons.CUSTOM[state.id])
    end
    if plugin then plugin:_updateFooter() end
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

local function showCustomCodepointDialog(plugin, state)
    local InputDialog = require("ui/widget/inputdialog")
    local UIManager = require("ui/uimanager")
    local dialog
    dialog = InputDialog:new{
        title = state.label .. _("：自定义图标"),
        description = _([[输入 KOReader 自带 nerdfonts/symbols.ttf 中字形的 Unicode 码位，例如 U+EB53（遥控器）。也可输入其他 Unicode 符号码位；字体缺少该字形时会显示为空框。]]),
        input = string.format("U+%04X", Icons.getCodepoint(state.id)),
        input_hint = "U+EB53",
        buttons = {
            {
                {
                    text = _("取消"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("保存"),
                    callback = function()
                        local codepoint = Icons.parseCodepoint(dialog:getInputText())
                        if not codepoint then
                            plugin:_showMessage(_("码位无效，请输入例如 U+EB53"), 4)
                            return
                        end
                        setIcon(plugin, state, codepoint)
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
            text = _("一键使用我的图标（关 / 开 / 已连接）"),
            keep_menu_open = true,
            separator = true,
            callback = function()
                Icons.useCustom(plugin)
                if plugin then
                    plugin:_showMessage(
                        _("已切换为随插件附带的图标；若显示为空框，请重启 KOReader 让字体生效"), 6)
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
                        callback = function() setIcon(plugin, state, preset.code) end,
                    })
                end
                table.insert(choices, {
                    text = _("自定义 Unicode 码位…"),
                    checked_func = function()
                        return not Icons.isPreset(Icons.getCodepoint(state.id))
                    end,
                    separator = true,
                    callback = function() showCustomCodepointDialog(plugin, state) end,
                })
                table.insert(choices, {
                    text = _("恢复此状态默认图标"),
                    keep_menu_open = true,
                    callback = function() setIcon(plugin, state, state.default) end,
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
