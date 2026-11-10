--[[--
Unified, native-only Bluetooth backend for Kindle 5.20.1 and newer.

All operations use Amazon's btfd service. Power and device actions are verified
asynchronously for a bounded period; no daemon or idle polling is created.

Turning Bluetooth back on after a long suspend is deliberately a single
request followed by a read-only wait: on-device evidence shows the native stack
may need minutes to recover, and repeated writes can delay that recovery. The
plugin never restarts btfd's services; recovery is observation only.
--]]

local Bluetooth = require("kindleclick_bluetooth")
local Log = require("kindleclick_log")
local UIManager = require("ui/uimanager")

local Backend = { id = "kindle", display_name = "Kindle 原生蓝牙" }
local WAIT_SECONDS = 15

function Backend.getStatus()
    local status = Bluetooth.getStatus()
    status.backend = Backend.id
    return status
end

-- A newer power request supersedes every older verification loop. Without this
-- token, a stale "enable" loop could reach its fallback seconds later and
-- silently turn the radio back on after the user asked to switch it off.
local power_token = 0

local function waitForPower(enabled, token, seconds, done)
    local deadline = os.time() + seconds
    local unknown_reads = 0

    local function check()
        if token ~= power_token then return end
        local state = Bluetooth.isEnabled()
        if state == enabled then return done(true) end
        if state == nil then
            unknown_reads = unknown_reads + 1
            if unknown_reads >= 3 then
                Log.write("power", "status unavailable: " .. Bluetooth.describe())
                return done(false, "无法读取蓝牙状态，请查看诊断信息")
            end
        else
            unknown_reads = 0
        end
        if os.time() >= deadline then return done(false) end
        UIManager:scheduleIn(1, check)
    end
    check()
end

-- One request, one bounded confirmation. Moon's native Kindle backend does the
-- same and never retries: on-device evidence shows the native stack may need
-- minutes to come back, and repeated writes can reset the controller's own
-- retry backoff instead of helping it.
local function enableOnce(token, done)
    Log.write("power", "enable: BTflightMode=0 + BTenable=1:2")
    local accepted = Bluetooth.requestEnabled(true)
    Log.write("power", "enable accepted=" .. tostring(accepted))
    waitForPower(true, token, WAIT_SECONDS, function(ok)
        if ok then
            Log.write("power", "enabled")
            return done(true)
        end
        Log.write("power", "enable not confirmed: " .. Bluetooth.describe())
        return done(false, "蓝牙状态没有变化，请查看诊断信息")
    end)
end

local function disableWithWait(token, done)
    Log.write("power", "disable: BTflightMode=1 (BTenable=0:1 fallback)")
    Bluetooth.requestEnabled(false)
    waitForPower(false, token, WAIT_SECONDS, function(ok)
        if not ok then
            Log.write("power", "disable timed out: " .. Bluetooth.describe())
            return done(false, "蓝牙状态没有变化，请查看诊断信息")
        end
        return done(true)
    end)
end

function Backend.setEnabled(enabled, done)
    power_token = power_token + 1
    local token = power_token
    UIManager:nextTick(function()
        -- The user may have flipped the switch again before this tick ran.
        if token ~= power_token then return end
        if Bluetooth.isEnabled() == enabled then return done(true) end
        Log.write("power", string.format("%s requested: %s",
            enabled and "enable" or "disable", Bluetooth.describe()))
        if enabled then return enableOnce(token, done) end
        return disableWithWait(token, done)
    end)
end

local function findDevice(devices, address)
    for _, device in ipairs(devices or {}) do
        if device.address and device.address:upper() == address:upper() then
            return device
        end
    end
    return nil
end

-- The HID node in /proc is the evidence the UI itself relies on, so it counts
-- as proof of a connection; btfd's hash lists are unavailable on some builds
-- and would otherwise make every successful connect look like a failure.
-- Verification runs on a bounded, low-frequency schedule (no 1 Hz polling).
local CONNECT_CHECK_DELAYS = { 2, 5, 10, 20 }

local function verifyClickConnected(address, done)
    local index = 0
    local function check()
        index = index + 1
        if Bluetooth.getConnectedKindleClick() then return done(true) end
        local device = findDevice(Bluetooth.getDeviceList(), address)
        if device and device.connected then return done(true) end
        if index >= #CONNECT_CHECK_DELAYS then
            Log.write("connect", "verification timed out for " .. tostring(address))
            return done(false, "设备状态没有变化，请确认设备已开启并在附近")
        end
        UIManager:scheduleIn(CONNECT_CHECK_DELAYS[index + 1] - CONNECT_CHECK_DELAYS[index], check)
    end
    UIManager:scheduleIn(CONNECT_CHECK_DELAYS[1], check)
end

function Backend.connect(device, done)
    if not Bluetooth.connect(device.address) then
        Log.write("connect", "Connect request rejected for " .. tostring(device.address))
        return done(false, "无法发送原生连接请求")
    end
    Log.write("connect", "Connect sent to " .. tostring(device.address))
    verifyClickConnected(device.address, done)
end

function Backend.findPairedKindleClick()
    local address = Bluetooth.findPairedKindleClick()
    if not address then return nil end
    local device = findDevice(Bluetooth.getDeviceList(), address)
    return device or {
        address = address,
        name = "Kindle Click",
        paired = true,
        protocol = "",
    }
end

return Backend
