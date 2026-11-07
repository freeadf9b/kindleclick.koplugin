local status = { enabled = false, known = true, native_click = false }
local enabled_requests = 0
local enable_after = nil
local messages = {}
local scheduled = {}
local Device = {
    input = nil,
    isKindle = function() return true end,
    hasKeys = function() return false end,
}

local Bluetooth = {
    getStatus = function()
        return {
            enabled = status.enabled,
            known = status.known,
            native_click = status.native_click,
            device_name = status.device_name,
        }
    end,
    isKindleClick = function(name)
        return name == "Kindle Click"
    end,
    getPassThroughDevice = function() return nil end,
    requestEnabled = function()
        enabled_requests = enabled_requests + 1
        if enable_after and enabled_requests >= enable_after then
            status.enabled = true
        end
    end,
}

package.preload["device"] = function()
    return Device
end
package.preload["kindleclick_bluetooth"] = function() return Bluetooth end
package.preload["dispatcher"] = function()
    return { registerAction = function() end }
end
package.preload["ui/event"] = function()
    return { new = function(_, name) return name end }
end
package.preload["kindleclick_icons"] = function()
    return { getGlyph = function() return "" end }
end
package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, args) return args end }
end
package.preload["ui/uimanager"] = function()
    return {
        scheduleIn = function(_, delay, callback)
            table.insert(scheduled, { delay = delay, callback = callback })
        end,
        unschedule = function(_, callback)
            for index, item in ipairs(scheduled) do
                if item.callback == callback then
                    table.remove(scheduled, index)
                    return
                end
            end
        end,
        show = function(_, message)
            table.insert(messages, message.text)
        end,
        broadcastEvent = function() end,
    }
end
package.preload["ui/widget/container/widgetcontainer"] = function()
    local WidgetContainer = {}
    function WidgetContainer:extend(definition)
        definition.__index = definition
        return setmetatable(definition, { __index = self })
    end
    return WidgetContainer
end
package.preload["gettext"] = function()
    return function(text) return text end
end

local KindleClick = dofile("kindleclick.koplugin/main.lua")

local function newPlugin()
    return setmetatable({
        state = {
            enabled = status.enabled,
            device_name = status.device_name,
            native_click = status.native_click,
            known = status.known,
            initialized = true,
        },
        _checks = {},
        _last_refresh = os.time(),
        auto_connect = false,
        _closed = false,
    }, KindleClick)
end

local function runNext()
    local item = table.remove(scheduled, 1)
    assert(item, "expected a scheduled callback")
    item.callback()
    return item.delay
end

local plugin = newPlugin()
Device.input = { event_map = { [109] = "existing-page-forward" } }
plugin.ui = {}
plugin:_installInputSupport()
assert(Device.input.event_map[104] == "LPgBack")
assert(Device.input.event_map[109] == "existing-page-forward")
assert(Device.input.event_map[224] == nil)
assert(Device.input.event_map[225] == nil)
assert(Device.input.event_map[116] == nil)
assert(Device:hasKeys() == true)

enable_after = 1
plugin:_scheduleBluetoothRecovery()
assert(runNext() == 2)
assert(enabled_requests == 1)
assert(runNext() == 3)
assert(status.enabled == true)
assert(#scheduled == 0)
assert(#messages == 0)

status.enabled = false
enabled_requests = 0
enable_after = nil
plugin = newPlugin()
plugin:_scheduleBluetoothRecovery()
assert(runNext() == 2)
assert(runNext() == 3)
assert(runNext() == 6)
assert(enabled_requests == 3)
assert(runNext() == 6)
assert(#scheduled == 0)
assert(#messages == 1)
assert(messages[1]:find("无法确认蓝牙已恢复", 1, true))

status.enabled = false
enabled_requests = 0
plugin = newPlugin()
plugin._pre_sleep_enabled = false
plugin:onResume()
assert(#scheduled == 0)
assert(enabled_requests == 0)

plugin._pre_sleep_enabled = true
plugin:onResume()
assert(#scheduled == 1)
assert(scheduled[1].delay == 2)

scheduled = {}
status = { enabled = true, known = true, native_click = false }
plugin = newPlugin()
plugin:_scheduleConnectionChecks()
assert(runNext() == 2)
assert(#messages == 1)
assert(runNext() == 5)
assert(#messages == 1)
assert(runNext() == 10)
assert(#messages == 1)
assert(runNext() == 20)
assert(#messages == 2)
assert(messages[#messages]:find("未能确认 Kindle Click 已连接", 1, true))

status = { enabled = nil, known = false, native_click = false }
enabled_requests = 0
plugin = newPlugin()
assert(plugin:_statusText() == "?")
plugin:onToggleBluetooth()
assert(enabled_requests == 0)
assert(messages[#messages]:find("无法读取蓝牙状态", 1, true))

print("kindleclick_recovery_spec: ok")
