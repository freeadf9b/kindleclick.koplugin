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

function Bluetooth.hasNativeClickSupport()
    return findPassThrough(Bluetooth.getInputDevices()) ~= nil
end

function Bluetooth.getPassThroughDevice()
    return findPassThrough(Bluetooth.getInputDevices())
end

function Bluetooth.isEnabled()
    return (tonumber(readProperty("BTstate")) or 0) > 0
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
    -- A live Click HID node also proves that the radio is on, even if an
    -- unfamiliar firmware does not expose the legacy BTstate property.
    local enabled = Bluetooth.isEnabled() or click ~= nil
    local device_name
    if click then
        device_name = "Kindle Click"
    elseif enabled then
        device_name = readLipcDeviceName()
    end
    return {
        enabled = enabled,
        device_name = device_name,
        click = click,
        native_click = passthrough ~= nil,
        passthrough = passthrough,
    }
end

function Bluetooth.setEnabled(enabled)
    local flight_mode = enabled and 0 or 1
    os.execute(string.format(
        "lipc-set-prop %s BTflightMode %d >/dev/null 2>&1",
        SERVICE, flight_mode))

    -- The radio changes state asynchronously. This bounded wait only runs after
    -- a user action (or startup auto-connect), never in a recurring timer.
    for _ = 1, 10 do
        if Bluetooth.isEnabled() == enabled then return true end
        os.execute("usleep 200000 2>/dev/null")
    end
    return false
end

function Bluetooth.isKindleClick(name)
    if not name then return false end
    local normalized = name:lower():gsub("[%s_%-]+", "")
    return normalized:find("kindleclick", 1, true) ~= nil
end

-- Legacy fallback only. Firmware 5.20.x reconnects official Clicks through its
-- native HID background-connection list, not through this name-based path.
function Bluetooth.findPairedKindleClick()
    local file = io.open(PAIRED_DEVICES_FILE, "r")
    if not file then return nil end

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
    return nil
end

function Bluetooth.connect(address)
    if not address or not address:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
        return false
    end
    -- address is strictly validated above, so it is safe to pass to the shell.
    os.execute(string.format(
        'lipc-set-prop %s Connect "%s" >/dev/null 2>&1', SERVICE, address))
    return true
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
