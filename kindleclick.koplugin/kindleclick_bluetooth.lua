--[[--
Thin wrapper around Kindle's native Bluetooth interfaces.

On the tested KPW6 / 5.20.x setup, the Click input node was observed with
VID:PID 0171:0443. The connected input node is created by the native stack;
kindle-input-pt is a pass-through and is NOT evidence of a connection. These
device observations are not a public Amazon firmware specification. No input
node is opened or grabbed by this module.

No background process is created here. Every function runs only when explicitly
called by the UI plugin.
--]]

local Bluetooth = {}

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

local function readProperty(property)
    local command = string.format(
        "timeout 2 lipc-get-prop %s %s 2>/dev/null", SERVICE, property)
    local handle = io.popen(command)
    if not handle then return nil end
    local value = trim(handle:read("*a"))
    if handle:close() ~= true then return nil end
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

function Bluetooth.hasNativeClickSupport()
    return findPassThrough(Bluetooth.getInputDevices()) ~= nil
end

function Bluetooth.getPassThroughDevice()
    return findPassThrough(Bluetooth.getInputDevices())
end

function Bluetooth.isEnabled()
    local state = tonumber(readProperty("BTstate"))
    if state == nil then return nil end
    return state > 0
end

function Bluetooth.getConnectedDeviceName()
    if Bluetooth.getConnectedKindleClick() then return "Kindle Click" end
    return readLipcDeviceName()
end

-- One activity-driven snapshot, avoiding duplicate procfs reads and shell calls.
function Bluetooth.getStatus()
    local devices = Bluetooth.getInputDevices()
    local click = findClick(devices)
    local passthrough = findPassThrough(devices)
    local enabled = Bluetooth.isEnabled()
    -- A live Click HID node also proves that the radio is on, even if an
    -- unfamiliar firmware does not expose the legacy BTstate property.
    if click then enabled = true end
    local device_name
    if click then
        device_name = "Kindle Click"
    elseif enabled then
        device_name = readLipcDeviceName()
    end
    return {
        enabled = enabled,
        known = enabled ~= nil,
        status_error = enabled == nil and "Unable to read btfd BTstate" or nil,
        device_name = device_name,
        click = click,
        native_click = passthrough ~= nil,
        passthrough = passthrough,
    }
end

local function waitForEnabled(enabled)
    for _ = 1, 10 do
        local state = Bluetooth.getStatus().enabled
        if state == enabled then return true end
        if state == nil then return false, "status-unavailable" end
        os.execute("usleep 200000 2>/dev/null")
    end
    return false, enabled and "enable-not-confirmed" or "disable-not-confirmed"
end

local function setBluetoothProperty(property, value)
    os.execute(string.format(
        "timeout 2 lipc-set-prop %s %s %s >/dev/null 2>&1",
        SERVICE, property, value))
end

function Bluetooth.requestEnabled(enabled)
    if enabled then
        -- Reuse the established compatibility writes. Public documentation
        -- does not fully specify these properties; success is verified below.
        setBluetoothProperty("BTflightMode", "0")
        setBluetoothProperty("BTenable", "1:2")
        return
    end

    -- Request off through the native flight-mode property. setEnabled retains
    -- the older BTenable fallback if the requested state cannot be verified.
    setBluetoothProperty("BTflightMode", "1")
end

function Bluetooth.setEnabled(enabled)
    Bluetooth.requestEnabled(enabled)
    if enabled then
        local ok, reason = waitForEnabled(true)
        if ok then return true end
        return false, reason
    end
    local ok, reason = waitForEnabled(false)
    if ok then return true end
    if reason == "status-unavailable" then return false, reason end
    setBluetoothProperty("BTenable", "0:1")
    ok, reason = waitForEnabled(false)
    if ok then return true end
    return false, reason
end

function Bluetooth.isKindleClick(name)
    if not name then return false end
    local normalized = name:lower():gsub("[%s_%-]+", "")
    return normalized:find("kindleclick", 1, true) ~= nil
end

-- Parse the observed accessory-type database. Some tested Click entries use
-- BleHidPageTurner even when their saved name is generic. The format is not
-- fully documented; this reads no pairing keys.
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

-- Prefer the observed page-turner type and retain the name-based fallback.
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
    -- address is strictly validated above, so it is safe to pass to the shell.
    os.execute(string.format(
        'lipc-set-prop %s %s "%s" >/dev/null 2>&1',
        SERVICE, property, address))
    return true
end

function Bluetooth.connect(address)
    return setDeviceProperty("Connect", address)
end

-- Request release of only the paired Click through the native API. This does
-- not unpair it, stop input_manager, power off Bluetooth, or affect other
-- Bluetooth devices. Firmware-specific reconnect behavior is not assumed.
function Bluetooth.releaseClick()
    return setDeviceProperty("Disconnect", Bluetooth.findPairedKindleClick())
end

-- Read-only, on-demand values for the diagnostic view.
function Bluetooth.getDiagnosticProperties()
    return {
        BTstate = readProperty("BTstate"),
        BTflightMode = readProperty("BTflightMode"),
        BTconnectedDevName = readProperty("BTconnectedDevName"),
    }
end

return Bluetooth
