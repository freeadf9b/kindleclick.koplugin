--[[--
Thin wrapper around Kindle's native Bluetooth interfaces.

On firmware 5.20.x, an official Click is a BLE HID device with Amazon
VID:PID 0171:0443. Its connected input node is created by the native stack;
kindle-input-pt is only a persistent pass-through and is NOT evidence of a
connection. No input node is opened or grabbed by this module.

No background process is created here. Every function runs only when explicitly
called by the UI plugin.
--]]

local Bluetooth = {}

local Log = require("kindleclick_log")

local SERVICE = "com.lab126.btfd"
local PAIRED_DEVICES_FILE = "/var/local/zbluetooth/bt_config.conf"
local INPUT_DEVICES_FILE = "/proc/bus/input/devices"
local CLICK_VENDOR = 0x0171
local CLICK_PRODUCT = 0x0443
local PASSTHROUGH_NAME = "kindle-input-pt"

local function trim(value)
    if not value then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value
end

-- Moon's native Kindle backend uses typed, in-process LIPC calls. Besides
-- avoiding shell overhead, set_int_property is important for BTflightMode:
-- an untyped lipc-set-prop call may not perform the requested integer write.
local function withLipc(callback)
    local ok, lipc = pcall(require, "liblipclua")
    if not ok or type(lipc) ~= "table" or type(lipc.init) ~= "function" then
        return nil
    end
    local opened, handle = pcall(lipc.init, "com.github.koreader.kindleclick.bluetooth")
    if not opened or not handle then return nil end
    local called, result = pcall(callback, handle)
    pcall(handle.close, handle)
    if not called then return nil end
    return result
end

-- Typed, in-process reads keep the UI thread off the shell; the lipc-get-prop
-- fallback only runs on firmware whose liblipclua lacks the typed getter.
local function readProperty(property, numeric, service)
    service = service or SERVICE
    local value = withLipc(function(handle)
        local getter
        if numeric then
            getter = handle.get_int_property
        else
            getter = handle.get_string_property
        end
        if type(getter) ~= "function" then return nil end
        return getter(handle, service, property)
    end)
    if numeric then
        if type(value) == "number" then return tostring(value) end
    elseif type(value) == "string" then
        return value
    end

    local command = string.format(
        "timeout 2 lipc-get-prop %s %s 2>/dev/null", service, property)
    local handle = io.popen(command)
    if not handle then return nil end
    value = trim(handle:read("*a"))
    handle:close()
    return value
end

local function readLipcDeviceName()
    local name = readProperty("BTconnectedDevName")
    if not name then return nil end
    -- Some firmware releases quote string-valued LIPC properties.
    name = name:match('^"(.*)"$') or name
    return trim(name)
end

-- Parse the kernel's input device list without invoking a shell.
function Bluetooth._parseInputDevices(text)
    local devices = {}
    local current

    local function finish()
        if not current then return end
        local event = current.handlers and current.handlers:match("event%d+")
        if event then current.path = "/dev/input/" .. event end
        table.insert(devices, current)
        current = nil
    end

    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        if line:match("^%s*$") then
            finish()
        elseif line:match("^I:") then
            finish()
            current = {}
            current.bus, current.vendor, current.product, current.version =
                line:match("^I:%s*Bus=(%x+)%s+Vendor=(%x+)%s+Product=(%x+)%s+Version=(%x+)")
        elseif current then
            if line:match("^N:") then
                current.name = line:match('^N:%s*Name="(.-)"%s*$')
                    or trim(line:match("^N:%s*Name=(.-)%s*$"))
            elseif line:match("^H:") then
                current.handlers = trim(line:match("^H:%s*Handlers=(.-)%s*$"))
            end
        end
    end
    finish()
    return devices
end

function Bluetooth.getInputDevices()
    local file = io.open(INPUT_DEVICES_FILE, "r")
    if not file then return {} end
    local text = file:read("*a")
    file:close()
    return Bluetooth._parseInputDevices(text)
end

local function findClick(devices)
    for _, device in ipairs(devices) do
        if tonumber(device.vendor or "", 16) == CLICK_VENDOR
            and tonumber(device.product or "", 16) == CLICK_PRODUCT then
            return device
        end
    end
    return nil
end

local function findPassThrough(devices)
    for _, device in ipairs(devices) do
        if device.name == PASSTHROUGH_NAME then return device end
    end
    return nil
end

function Bluetooth.getConnectedKindleClick()
    return findClick(Bluetooth.getInputDevices())
end

function Bluetooth.getPassThroughDevice()
    return findPassThrough(Bluetooth.getInputDevices())
end

function Bluetooth.isEnabled()
    -- A live Click HID node proves the radio is on, whatever a stale property
    -- says; this also keeps recovery from toggling a working radio.
    if Bluetooth.getConnectedKindleClick() then return true end
    local state = tonumber(readProperty("BTstate", true))
    if state then return state > 0 end
    -- Some builds do not expose the legacy BTstate property; the operating
    -- mode is the next best signal (0 = idle/off).
    local mode = tonumber(readProperty("currentBTOperatingMode", true))
    if mode then return mode > 0 end
    -- Nothing readable: report "unknown" instead of pretending Bluetooth is off.
    return nil
end

-- One activity-driven snapshot, avoiding duplicate procfs reads and shell calls.
function Bluetooth.getStatus()
    local devices = Bluetooth.getInputDevices()
    local click = findClick(devices)
    local passthrough = findPassThrough(devices)
    local enabled = Bluetooth.isEnabled()
    if click then enabled = true end
    local known = enabled ~= nil
    local device_name
    if click then
        device_name = "Kindle Click"
    elseif enabled then
        device_name = readLipcDeviceName()
    end
    return {
        enabled = enabled,
        known = known,
        device_name = device_name,
        click = click,
        native_click = passthrough ~= nil,
        passthrough = passthrough,
    }
end

local function writeProperty(property, value, numeric, service)
    service = service or SERVICE
    local accepted = withLipc(function(handle)
        local setter = numeric and handle.set_int_property or handle.set_string_property
        if type(setter) ~= "function" then return nil end
        setter(handle, service, property, value)
        return true
    end) == true
    if accepted then
        Log.write("lipc", string.format("set %s=%s accepted=true BTstate=%s",
            property, tostring(value), tostring(readProperty("BTstate", true))))
        return true
    end

    -- Keep a compatibility fallback, but preserve the property's native type.
    local flag = numeric and "-i" or "-s"
    local rendered = numeric and tostring(value) or string.format('"%s"', tostring(value))
    local ok, _, code = os.execute(string.format(
        "lipc-set-prop %s %s %s %s >/dev/null 2>&1",
        flag, service, property, rendered))
    local fallback_ok = ok == true or ok == 0 or code == 0
    Log.write("lipc", string.format("set %s=%s accepted=%s BTstate=%s",
        property, tostring(value), tostring(fallback_ok),
        tostring(readProperty("BTstate", true))))
    return fallback_ok
end

-- The master wireless switch lives in com.lab126.cmd: 0 means airplane mode
-- (Wi-Fi off). Bluetooth is independent of it and can be enabled with the
-- airplane mode on, so this value is read for diagnostics only.
local CMD_SERVICE = "com.lab126.cmd"

-- Read-only helper used in the status log: correlating airplane-mode changes
-- with the native Bluetooth recovery is how the recovery trigger is identified.
function Bluetooth.getWirelessState()
    return readProperty("wirelessEnable", true, CMD_SERVICE)
end

-- wirelessEnable (com.lab126.cmd) is read in getDiagnosticProperties only: the
-- user may deliberately keep airplane mode on with Bluetooth on, so the plugin
-- must never write it.

local function shell(command)
    local handle = io.popen(command .. " 2>&1")
    if not handle then return nil end
    local output = handle:read("*a")
    handle:close()
    return output
end

function Bluetooth.isKindleClick(name)
    if not name then return false end
    local normalized = name:lower():gsub("[%s_%-]+", "")
    return normalized:find("kindleclick", 1, true) ~= nil
end

-- Parse Amazon's accessory-type database. Official Clicks may be named
-- "Amazon Fire TV Remote" in bt_config.conf, so their BleHidPageTurner type is
-- the reliable way to find the address without reading any pairing keys.
function Bluetooth._findPageTurnerAddress(text)
    local current_address
    local is_page_turner = false

    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        local section = line:match("^%s*%[([^%]]+)%]%s*$")
        if section then
            if is_page_turner and current_address then return current_address end
            current_address = section:match(
                "^(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)$")
            is_page_turner = false
        elseif current_address then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key == "type" and value == "BleHidPageTurner" then
                is_page_turner = true
            end
        end
    end
    if is_page_turner then return current_address end
    return nil
end

-- The accessory-type path handles native 5.20.x page turners; the older
-- name-based path remains as a fallback for other firmware and remotes.
function Bluetooth.findPairedKindleClick()
    local file = io.open(PAIRED_DEVICES_FILE, "r")
    if file then
        local current_address
        local current_name
        local found_address
        for line in file:lines() do
            local section = line:match("^%s*%[([^%]]+)%]%s*$")
            if section then
                if Bluetooth.isKindleClick(current_name) and current_address then
                    found_address = current_address
                    break
                end
                current_address = section:match(
                    "^(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)$")
                current_name = nil
            elseif current_address then
                local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if key == "Name" then current_name = value end
            end
        end
        file:close()

        if found_address then return found_address end
        if Bluetooth.isKindleClick(current_name) then return current_address end
    end

    file = io.open("/var/local/system/bt_device_types.conf", "r")
    if not file then return nil end
    local address = Bluetooth._findPageTurnerAddress(file:read("*a"))
    file:close()
    return address
end

local function setDeviceProperty(property, address)
    if not address or not address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return false
    end
    return writeProperty(property, address, false)
end

function Bluetooth.connect(address)
    return setDeviceProperty("Connect", address)
end

-- Request-only form used by the asynchronous backend; the returned value says
-- whether btfd accepted the request, not whether the radio already switched.
-- On current firmware BTflightMode=1 is the real "off"; BTenable=0:1 only
-- lowers the power mode, so it is kept as a fallback for older btfd builds.
function Bluetooth.requestEnabled(enabled)
    if enabled then
        writeProperty("BTflightMode", 0, true)
        return writeProperty("BTenable", "1:2", false)
    end
    if writeProperty("BTflightMode", 1, true) then return true end
    return writeProperty("BTenable", "0:1", false)
end

local function readHash(property)
    local ok, lipc = pcall(require, "libopenlipclua")
    if not ok or type(lipc) ~= "table" or type(lipc.open_no_name) ~= "function" then
        return nil
    end
    local opened, handle = pcall(lipc.open_no_name)
    if not opened or not handle then return nil end
    local called, values = pcall(function()
        local input = handle:new_hasharray()
        local result = handle:access_hash_property(SERVICE, property, input)
        local converted = result and result:to_table() or {}
        if result then pcall(result.destroy, result) end
        pcall(input.destroy, input)
        return converted
    end)
    pcall(handle.close, handle)
    if not called or type(values) ~= "table" then return nil end
    return values
end

local function normalizeDevice(raw, paired, connected_state)
    if type(raw) ~= "table" then return nil end
    local address = raw.address or raw.Address or raw.addr or raw.mac or raw.MAC
        or raw.bdaddr or raw.BDAddr or raw.bd_address or raw.deviceAddress or raw.macAddress
    if type(address) ~= "string"
        or not address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then return nil end
    local name = raw.name or raw.Name or raw.bd_name or raw.deviceName or raw.friendlyName
    return {
        address = address:upper(),
        name = type(name) == "string" and name ~= "" and name or address:upper(),
        protocol = "",
        paired = raw.is_paired == 1 or raw.is_paired == true or paired or nil,
        connected = raw.is_connected == 1 or raw.is_connected == true or connected_state or nil,
        rssi = tonumber(raw.rssi or raw.RSSI),
    }
end

function Bluetooth.getDeviceList()
    local discovered = readHash("ListDiscovered")
    local paired = readHash("ListPaired")
    local connected_list = readHash("ListConnected")
    if not discovered or not paired or not connected_list then
        return nil, "Unable to read native btfd device lists"
    end
    local devices, by_address = {}, {}
    local function merge(list, is_paired, is_connected)
        for _, raw in ipairs(list) do
            local item = normalizeDevice(raw, is_paired, is_connected)
            if item then
                local key = item.address:upper()
                local existing = by_address[key]
                if not existing then
                    existing = item
                    by_address[key] = item
                    table.insert(devices, existing)
                else
                    existing.paired = existing.paired or item.paired
                    existing.connected = existing.connected or item.connected
                    if existing.name == existing.address and item.name ~= item.address then
                        existing.name = item.name
                    end
                end
            end
        end
    end
    merge(discovered, false, false)
    merge(paired, true, false)
    merge(connected_list, true, true)
    return devices
end

-- Read-only, on-demand values for the diagnostic view.
function Bluetooth.getDiagnosticProperties()
    -- BTflightMode is write-only on this firmware: reading it makes btfd log a
    -- type error and returns nothing, so it is deliberately not in this list.
    return {
        BTstate = readProperty("BTstate", true),
        BTconnectedDevName = readProperty("BTconnectedDevName", false),
        currentBTOperatingMode = readProperty("currentBTOperatingMode", true),
        isBtchRunning = readProperty("isBtchRunning", true),
        wirelessEnable = readProperty("wirelessEnable", true, CMD_SERVICE),
    }
end

-- One compact line for the recovery log.
function Bluetooth.describe()
    local properties = Bluetooth.getDiagnosticProperties()
    return string.format(
        "BTstate=%s mode=%s btch=%s wireless=%s name=%s",
        tostring(properties.BTstate),
        tostring(properties.currentBTOperatingMode), tostring(properties.isBtchRunning),
        tostring(properties.wirelessEnable), tostring(properties.BTconnectedDevName))
end

-- Cheap, LIPC-free summary for lifecycle and wake logging. Property reads can
-- block for seconds while the native stack is initialising, so anything that
-- runs on the resume path must not use describe().
function Bluetooth.quickDescribe()
    local click = findClick(Bluetooth.getInputDevices())
    return "click_input=" .. (click and "yes" or "no")
end

return Bluetooth
