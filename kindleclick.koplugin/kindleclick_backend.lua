--[[--
Unified, native-only Bluetooth backend for Kindle 5.20.1 and newer.

All operations use Amazon's btfd service. Power and device actions are verified
asynchronously for a bounded period; no daemon or idle polling is created.

Turning Bluetooth back on after a long suspend is the one path that is not a
single request: the controller may still be starting up, or btfd may be holding
a half-initialised state. Enable therefore runs a short ladder (normal request,
clean reset and retry, alternate enable mode) and logs every phase.
--]]

local Bluetooth = require("kindleclick_bluetooth")
local Log = require("kindleclick_log")
local UIManager = require("ui/uimanager")

local Backend = { id = "kindle", display_name = "Kindle 原生蓝牙" }
local WAIT_SECONDS = 15
local ENABLE_PHASE_SECONDS = 8

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

-- Phase 1 is the normal request. Phase 2 clears a half-initialised state by
-- turning the radio off and requesting it again. Phase 3 asks for the
-- alternate native enable mode used by some firmware builds.
local function enableWithRecovery(token, done)
    local phase = 0
    local run

    local function finish(ok)
        if ok then
            Log.write("power", "enabled in phase " .. phase)
            return done(true)
        end
        if phase >= 3 then
            Log.write("power", "enable failed after phase 3: " .. Bluetooth.describe())
            return done(false, "蓝牙状态没有变化，请查看诊断信息")
        end
        return run()
    end

    run = function()
        if token ~= power_token then return end
        phase = phase + 1
        if phase == 1 then
            Log.write("power", "phase 1: BTflightMode=0 + BTenable=1:2")
            local accepted = Bluetooth.requestEnabled(true)
            Log.write("power", "phase 1 accepted=" .. tostring(accepted))
            return waitForPower(true, token, ENABLE_PHASE_SECONDS, finish)
        end
        if phase == 2 then
            Log.write("power", "phase 2: reset radio, then BTenable=1:2")
            Bluetooth.requestEnabled(false)
            UIManager:scheduleIn(2, function()
                if token ~= power_token then return end
                Bluetooth.requestEnabled(true)
                waitForPower(true, token, ENABLE_PHASE_SECONDS, finish)
            end)
            return
        end
        Log.write("power", "phase 3: BTenable=1:1")
        Bluetooth.requestAlternateEnabled()
        waitForPower(true, token, ENABLE_PHASE_SECONDS, finish)
    end

    run()
end

local function disableWithWait(token, done)
    Log.write("power", "disable: BTflightMode=1 + BTenable=0:1")
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
        if enabled then return enableWithRecovery(token, done) end
        return disableWithWait(token, done)
    end)
end

-- Manual recovery for a Bluetooth that does not come back after sleep.
-- On-device evidence (2026-11-07 23:00): enabling works with airplane mode on,
-- and a Click connection can take minutes. Therefore:
--   * if the radio is already on, leave the services alone (restarting them
--     would only drop the session) and wait for the Click HID node;
--   * if it is off, restart the BT jobs, run the ladder, then poll read-only
--     for up to four minutes.
local RECOVERY_POLL_STEP = 15
local RECOVERY_POLL_TOTAL = 240

function Backend.deepRecover(done)
    power_token = power_token + 1
    local token = power_token
    Log.write("recover", "deep recovery start: " .. Bluetooth.describe())
    Bluetooth.logKernelTail()

    local function finish(ok, err)
        Log.write("recover", "deep recovery result: " .. tostring(ok)
            .. ", " .. Bluetooth.describe())
        Bluetooth.logDaemonLogs("after")
        Bluetooth.logKernelTail()
        done(ok, err)
    end

    local function poll(elapsed, check, timeout_message)
        if token ~= power_token then return end
        if check() then return finish(true) end
        if elapsed >= RECOVERY_POLL_TOTAL then return finish(false, timeout_message) end
        UIManager:scheduleIn(RECOVERY_POLL_STEP, function()
            if token ~= power_token then return end
            Log.write("recover", "waiting for the native stack ("
                .. (elapsed + RECOVERY_POLL_STEP) .. "s)")
            poll(elapsed + RECOVERY_POLL_STEP, check, timeout_message)
        end)
    end

    UIManager:nextTick(function()
        if token ~= power_token then return end
        if Bluetooth.isEnabled() then
            -- Services are up; restarting them would only drop the session.
            Log.write("recover", "Bluetooth already on; leaving services alone")
            local device = Backend.findPairedKindleClick()
            if device then Bluetooth.connect(device.address) end
            return poll(0, function()
                return Bluetooth.getConnectedKindleClick() ~= nil
            end, "Kindle Click 仍未连接，请按一下 Click 或检查原生配对")
        end

        local jobs = Bluetooth.restartService()
        Log.write("recover", "restarted jobs: " .. table.concat(jobs, ","))
        UIManager:scheduleIn(#jobs > 0 and 4 or 1, function()
            if token ~= power_token then return end
            enableWithRecovery(token, function(ok, err)
                if ok then return finish(true) end
                Log.write("recover", "ladder failed; waiting for the native stack")
                poll(0, function()
                    return Bluetooth.isEnabled() == true
                end, "蓝牙状态没有变化，请查看诊断信息")
            end)
        end)
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
