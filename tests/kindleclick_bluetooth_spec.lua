local original_open = io.open
local original_popen = io.popen
local original_execute = os.execute
local properties = {}
local input_devices = ""
local commands = {}
local popen_success = true

io.open = function(path, mode)
    if path == "/proc/bus/input/devices" and mode == "r" then
        return {
            read = function() return input_devices end,
            close = function() end,
        }
    end
    return nil
end

io.popen = function(command)
    local property = command:match("lipc%-get%-prop%s+%S+%s+(%S+)")
    local value = property and properties[property] or ""
    return {
        read = function() return value end,
        close = function() return popen_success end,
    }
end

os.execute = function(command)
    table.insert(commands, command)
    return 0
end

local Bluetooth = dofile("kindleclick.koplugin/kindleclick_bluetooth.lua")

properties.BTstate = nil
local status = Bluetooth.getStatus()
assert(status.known == false)
assert(status.enabled == nil)
assert(status.status_error ~= nil)

input_devices = [[
I: Bus=0005 Vendor=0171 Product=0443 Version=0001
N: Name="Amazon Fire TV Remote"
H: Handlers=event7

I: Bus=0003 Vendor=0000 Product=0000 Version=0000
N: Name="kindle-input-pt"
H: Handlers=event8
]]
status = Bluetooth.getStatus()
assert(status.known == true)
assert(status.enabled == true)
assert(status.device_name == "Kindle Click")
assert(status.click.path == "/dev/input/event7")
assert(status.native_click == true)
assert(Bluetooth.setEnabled(true) == true)
commands = {}

input_devices = ""
properties.BTstate = "0"
status = Bluetooth.getStatus()
assert(status.known == true)
assert(status.enabled == false)

popen_success = false
status = Bluetooth.getStatus()
assert(status.known == false)
assert(status.enabled == nil)
popen_success = true

properties.BTstate = "1"
assert(Bluetooth.setEnabled(true) == true)
assert(commands[1]:find("BTflightMode 0", 1, true))
assert(commands[2]:find("BTenable 1:2", 1, true))

properties.BTstate = "0"
assert(Bluetooth.setEnabled(false) == true)
assert(commands[3]:find("BTflightMode 1", 1, true))

properties.BTstate = nil
local before_unknown_off = #commands
local off_ok, off_error = Bluetooth.setEnabled(false)
assert(off_ok == false)
assert(off_error == "status-unavailable")
assert(#commands == before_unknown_off + 1)

io.open = original_open
io.popen = original_popen
os.execute = original_execute
print("kindleclick_bluetooth_spec: ok")
