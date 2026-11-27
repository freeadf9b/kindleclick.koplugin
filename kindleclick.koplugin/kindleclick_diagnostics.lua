--[[--
On-demand, read-only Kindle Click diagnostics.

This module is loaded only when the user opens the diagnostic menu item. It
never starts a listener, scan, or recurring task.
--]]

local Bluetooth = require("kindleclick_bluetooth")
local Device = require("device")
local Log = require("kindleclick_log")
local _ = require("kindleclick_gettext")

local Diagnostics = {}
local DIAGNOSTIC_FILE = (Device.home_dir or "/mnt/us")
    .. "/koreader/kindleclick-diagnostic.txt"

local function readFile(path, limit)
    local file = io.open(path, "r")
    if not file then return nil end
    local text = file:read(limit or 100000)
    file:close()
    return text
end

local function readShell(command)
    local handle = io.popen(command)
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

local function present(value)
    if value == nil or value == "" then return _("(none)") end
    return tostring(value)
end

function Diagnostics.collect()
    local status = Bluetooth.getStatus()
    local input = Device.input or {}
    local event_map = input.event_map or {}
    local lines = {
        _("Kindle Click Diagnostics"),
        _("Time: ") .. os.date("%Y-%m-%d %H:%M:%S"),
        _("Device: ") .. present(Device.model),
        "",
        _("Plugin status"),
        _("Bluetooth enabled: ") .. tostring(status.enabled),
        _("Connected device: ") .. present(status.device_name),
        _("Native Click pass-through: ") .. tostring(status.native_click),
        "KOReader hasKeys：" .. tostring(Device:hasKeys()),
        "KEY_PAGEUP (104)：" .. present(event_map[104]),
        "KEY_PAGEDOWN (109)：" .. present(event_map[109]),
        _("Brightness down KEY_BRIGHTNESSDOWN (224): handled by native input_manager"),
        _("Brightness up KEY_BRIGHTNESSUP (225): handled by native input_manager"),
        _("Both side buttons sleep KEY_POWER (116): handled by native input_manager / powerd"),
        _("The plugin does not remap these three actions, to avoid duplicate execution."),
        "",
        _("Click HID node (present only while connected)"),
    }

    if status.click then
        table.insert(lines, _("Name: ") .. present(status.click.name))
        table.insert(lines, "VID:PID: " .. present(status.click.vendor)
            .. ":" .. present(status.click.product))
        table.insert(lines, _("Node: ") .. present(status.click.path))
        table.insert(lines, _("Handlers: ") .. present(status.click.handlers))
    else
        table.insert(lines, _("(VID:PID 0171:0443 not detected)"))
    end

    table.insert(lines, "")
    table.insert(lines, _("Native Bluetooth LIPC properties"))
    local properties = Bluetooth.getDiagnosticProperties()
    for _, key in ipairs({
        "BTstate", "BTconnectedDevName",
        "currentBTOperatingMode", "isBtchRunning", "wirelessEnable",
    }) do
        table.insert(lines, key .. " = " .. present(properties[key]))
    end
    table.insert(lines, "BTflightMode = " .. _("(write-only; not read)"))

    table.insert(lines, "")
    table.insert(lines, _("Power status"))
    table.insert(lines, "powerd.state = " .. present(readShell(
        "timeout 2 lipc-get-prop com.lab126.powerd state 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, _("Bluetooth kernel modules"))
    table.insert(lines, present(readShell(
        "lsmod 2>/dev/null | grep -i -E 'wmt|bt' 2>/dev/null") or _("(lsmod unavailable)")))

    table.insert(lines, "")
    table.insert(lines, _("Bluetooth/wireless entries from the end of the kernel log"))
    table.insert(lines, present(readShell(
        "dmesg 2>/dev/null | grep -i -E 'wmt|bluetooth|btusb|stpbt' | tail -60 2>/dev/null") or _("(none)")))

    table.insert(lines, "")
    table.insert(lines, _("Bluetooth-related upstart jobs"))
    table.insert(lines, present(readShell(
        "ls /etc/upstart 2>/dev/null | grep -i -E 'bt|bluetooth' 2>/dev/null") or _("(none)")))
    table.insert(lines, present(readShell(
        "PATH=/sbin:/usr/sbin:$PATH; initctl list 2>/dev/null | grep -i -E 'bt|bluetooth' 2>/dev/null")))
    table.insert(lines, "pidof：" .. present(readShell(
        "pidof acsbtfd btmanagerd btfd-acsv2 input_manager 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, _("Bluetooth daemon stderr (end of /tmp/*.err)"))
    for _, path in ipairs({ "/tmp/btfd-acs.err", "/tmp/btmanagerd.err" }) do
        table.insert(lines, "--- " .. path .. " ---")
        table.insert(lines, present(readFile(path, 8000)))
    end

    table.insert(lines, "")
    table.insert(lines, _("WMT transport status"))
    table.insert(lines, _("Device nodes: ") .. present(readShell(
        "ls -l /dev/stpbt* 2>/dev/null")))
    table.insert(lines, _("Module files: ") .. present(readShell(
        "ls /drivers/*/*/wmt_cdev_bt.ko /lib/modules/*/extra/wmt_cdev_bt.ko 2>/dev/null")))
    table.insert(lines, _("File descriptors opened by acsbtfd:"))
    table.insert(lines, present(readShell(
        "for p in $(pidof acsbtfd 2>/dev/null); do ls -l /proc/$p/fd 2>/dev/null; done | grep -i -E 'stpbt|wmt|bt' ; true")
        or _("(no matches)")))
    table.insert(lines, _("File descriptors opened by btmanagerd:"))
    table.insert(lines, present(readShell(
        "for p in $(pidof btmanagerd 2>/dev/null); do ls -l /proc/$p/fd 2>/dev/null; done | grep -i -E 'stpbt|wmt|bt' ; true")
        or _("(no matches)")))
    table.insert(lines, _("Bluetooth/WMT entries from the end of /var/log/messages"))
    table.insert(lines, present(readShell(
        "tail -600 /var/log/messages 2>/dev/null | grep -i -E 'btfd|bluetooth|wmt' | tail -40")))
    table.insert(lines, "")
    table.insert(lines, "--- /etc/upstart/wmt.conf ---")
    table.insert(lines, present(readFile("/etc/upstart/wmt.conf", 6000)))
    table.insert(lines, _("Job lookup (upstart configuration referencing btfd)"))
    table.insert(lines, present(readShell(
        "grep -l -i -E 'acsbtfd|btmanager|/usr/bin/btfd' /etc/upstart/*.conf 2>/dev/null") or _("(not found)")))

    table.insert(lines, "")
    table.insert(lines, _("Bluetooth upstart job configuration"))
    for _, name in ipairs({ "acsbtfd", "btmanagerd", "asr_bt_reboot", "asr_bt_userstore" }) do
        local path = "/etc/upstart/" .. name .. ".conf"
        local text = readFile(path, 6000)
        if text then
            table.insert(lines, "--- " .. path .. " ---")
            table.insert(lines, text)
        end
    end

    table.insert(lines, "")
    table.insert(lines, _("Related processes"))
    table.insert(lines, present(readShell(
        "ps 2>/dev/null | grep -E 'acsbtfd|btfd|input_manager|bluetooth' 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, _("Persisted Click accessory type"))
    table.insert(lines, present(readFile("/var/local/system/bt_device_types.conf", 20000)))

    table.insert(lines, "")
    table.insert(lines, _("Related LIPC services and properties (lipc-probe summary)"))
    table.insert(lines, present(readShell(
        "timeout 5 lipc-probe -a 2>/dev/null | grep -i -E -A 12 -B 2 'btfd|kindleclick|page.?turner|accessories' 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, "/proc/bus/input/devices")
    table.insert(lines, present(readFile("/proc/bus/input/devices", 100000)))

    table.insert(lines, "")
    table.insert(lines, _("Plugin log (") .. Log.path() .. _("; end)"))
    local tail = Log.tail(80)
    table.insert(lines, present(tail))

    table.insert(lines, "")
    table.insert(lines, _("The persistent kindle-input-pt node does not mean the Click is connected;"))
    table.insert(lines, _("the 0171:0443 HID node above is the connection indicator."))
    table.insert(lines, _("This report does not read or export Bluetooth link keys."))

    local body = table.concat(lines, "\n")
    local file = io.open(DIAGNOSTIC_FILE, "w")
    local saved = false
    if file then
        saved = file:write(body) ~= nil
        file:close()
    end

    local header = saved
        and (_("Diagnostics saved to:") .. "\n" .. DIAGNOSTIC_FILE .. "\n\n")
        or  (_("Could not save diagnostics to:") .. "\n" .. DIAGNOSTIC_FILE .. "\n\n")
    return header .. body, saved and DIAGNOSTIC_FILE or nil
end

return Diagnostics
