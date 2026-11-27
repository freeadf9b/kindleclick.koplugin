local gettext = require("gettext")

local CONTEXT = "Kindle Click"
local source = debug.getinfo(1, "S").source
local plugin_dir = source:match("^@(.*)/[^/]+$")
local language = gettext.current_lang or ""

if language:match("^zh_CN") or language:match("^zh_SG") then
    local catalog = plugin_dir
        and (plugin_dir .. "/l10n/zh_CN/LC_MESSAGES/kindleclick.mo")
    if catalog then
        local plural = gettext.getPlural
        -- loadMO is a KOReader internal API; never let a missing or changed
        -- implementation take the whole plugin down with it.
        local ok, loaded = pcall(gettext.loadMO, catalog)
        gettext.getPlural = plural
        if not ok or not loaded then
            require("logger").warn("Kindle Click: failed to load Simplified Chinese translations")
        end
    end
end

return function(message)
    return gettext.pgettext(CONTEXT, message)
end
