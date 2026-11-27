-- ZenOS home-page widget for Kindle Click.
--
-- ZenOS exposes a small integration API: a plugin registers a widget id with a
-- builder function, and ZenOS shows it on Home once the user enables it under
-- Zen Settings > Home > Widgets. The builder must return a KOReader widget that
-- fits the size ZenOS passes in. Registration is optional: every call is a
-- no-op when ZenOS is not installed.

local Geom = require("ui/geometry")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Icons = require("kindleclick_icons")
local Bluetooth = require("kindleclick_bluetooth")
local _ = require("kindleclick_gettext")

local ZenOS = {}

ZenOS.ID = "kindleclick.status"

local function status_label(plugin)
    local state = plugin and plugin.state
    if not state or not state.known then return _("Status unknown") end
    if not state.enabled then return _("Bluetooth off") end
    if Bluetooth.isKindleClick(state.device_name) then return _("Click connected") end
    return _("Click disconnected")
end

local function home_state_text(plugin)
    local state = plugin and plugin.state
    if not state or not state.known then
        return "? " .. _("Status unknown")
    end
    if not state.enabled then
        return Icons.getGlyph("off") .. " " .. _("Bluetooth off")
    end
    if Bluetooth.isKindleClick(state.device_name) then
        return Icons.getGlyph("click") .. " " .. _("Click connected")
    end
    return Icons.getGlyph("on") .. " " .. _("Click disconnected")
end

function ZenOS.statusLabel(plugin)
    return status_label(plugin)
end

function ZenOS.statusText(plugin)
    return home_state_text(plugin)
end

local function make_builder(plugin)
    return function(ctx)
        ctx = ctx or {}
        local width = math.max(1, math.floor(tonumber(ctx.width) or 200))
        local height = math.max(1, math.floor(tonumber(ctx.height) or 60))
        -- Keep the label on one line; the widget is a status line, not a card.
        local font_size = math.max(10, math.min(20, math.floor(height * 0.36)))
        -- A Button (rather than a bare TextWidget) is what gives the home item a
        -- tap target: tapping it opens the plugin's quick menu.
        local button = Button:new{
            text = home_state_text(plugin),
            text_font_face = "cfont",
            text_font_size = font_size,
            max_width = math.max(1, width - 8),
            padding = 0,
            padding_h = 0,
            padding_v = 0,
            margin = 0,
            bordersize = 0,
            callback = function()
                if plugin and plugin._showQuickMenu then
                    plugin:_showQuickMenu()
                end
            end,
        }
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            button,
        }
    end
end

local function register_fn()
    return rawget(_G, "__ZENOS_REGISTER_HOME_ITEM")
end

-- ZenOS resolves custom button icons from <koreader>/icons by file name. Copy
-- our capsule there so the icon picker lists it without the user having to
-- convert anything.
local ICON_FILES = { "kindleclick.svg" }

local function ensure_icons(plugin_dir)
    if ZenOS._icons_ready or not plugin_dir then return end
    local ok_storage, DataStorage = pcall(require, "datastorage")
    if not ok_storage or not DataStorage then return end
    local dir = DataStorage:getDataDir() .. "/icons"
    pcall(function()
        require("libs/libkoreader-lfs").mkdir(dir)
    end)
    for _i, name in ipairs(ICON_FILES) do
        local src = plugin_dir .. "/icons/" .. name
        local dst = dir .. "/" .. name
        local input = io.open(src, "rb")
        if input then
            local body = input:read("*a")
            input:close()
            local existing = io.open(dst, "rb")
            local same = false
            if existing then
                local current = existing:read("*a")
                existing:close()
                same = current == body
            end
            if not same then
                local output = io.open(dst, "wb")
                if output then
                    output:write(body)
                    output:close()
                end
            end
        end
    end
    ZenOS._icons_ready = true
    require("kindleclick_log").write("zenos", "control icons copied to " .. dir)
end

function ZenOS.icons_dir()
    local ok_storage, DataStorage = pcall(require, "datastorage")
    if not ok_storage or not DataStorage then return nil end
    return DataStorage:getDataDir() .. "/icons"
end

local function unregister_fn()
    local fn = rawget(_G, "__ZENOS_UNREGISTER_HOME_ITEM")
    if type(fn) ~= "function" then
        fn = rawget(_G, "__ZEN_UI_UNREGISTER_HOME_ITEM")
    end
    return fn
end

function ZenOS.attach(plugin)
    ZenOS._plugin = plugin
    ensure_icons(plugin and plugin.path)
    local register = register_fn()
    if type(register) ~= "function" then
        -- ZenOS may load after us; main.lua forwards its ZenOSReady event here.
        return false
    end
    local ok = register(ZenOS.ID, make_builder(plugin), {
        label = _("Kindle Click"),
        size = "s",
    })
    ZenOS._registered = ok and true or false
    if ZenOS._registered then
        require("kindleclick_log").write("zenos", "home widget registered")
    end
    return ZenOS._registered
end

function ZenOS.detach()
    local unregister = unregister_fn()
    if type(unregister) == "function" and ZenOS._registered then
        pcall(unregister, ZenOS.ID)
    end
    ZenOS._registered = false
end

-- Re-registering replaces the item and makes ZenOS rebuild Home, which is how
-- the widget picks up a new Bluetooth state without a full redraw of its own.
function ZenOS.refresh()
    if not ZenOS._registered or not ZenOS._plugin then return end
    local register = register_fn()
    if type(register) ~= "function" then return end
    register(ZenOS.ID, make_builder(ZenOS._plugin), {
        label = _("Kindle Click"),
        size = "s",
    })
end

return ZenOS
