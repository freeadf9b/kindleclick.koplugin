--[[--
On-demand, read-only Kindle Click diagnostics.

This module is loaded only when the user opens the diagnostic menu item. It
never starts a listener, scan, or recurring task.
--]]

local Bluetooth = require("kindleclick_bluetooth")
local Device = require("device")
local Log = require("kindleclick_log")

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
    if value == nil or value == "" then return "(无)" end
    return tostring(value)
end

function Diagnostics.collect()
    local status = Bluetooth.getStatus()
    local input = Device.input or {}
    local event_map = input.event_map or {}
    local lines = {
        "Kindle Click 诊断信息",
        "时间：" .. os.date("%Y-%m-%d %H:%M:%S"),
        "设备：" .. present(Device.model),
        "",
        "插件状态",
        "蓝牙开启：" .. tostring(status.enabled),
        "已连接设备：" .. present(status.device_name),
        "原生 Click 通道：" .. tostring(status.native_click),
        "KOReader hasKeys：" .. tostring(Device:hasKeys()),
        "KEY_PAGEUP (104)：" .. present(event_map[104]),
        "KEY_PAGEDOWN (109)：" .. present(event_map[109]),
        "亮度减 KEY_BRIGHTNESSDOWN (224)：原生 input_manager",
        "亮度增 KEY_BRIGHTNESSUP (225)：原生 input_manager",
        "双侧键休眠 KEY_POWER (116)：原生 input_manager / powerd",
        "说明：上述三个键不由本插件重复映射，避免重复执行。",
        "",
        "Click HID 节点（连接时才应存在）",
    }

    if status.click then
        table.insert(lines, "名称：" .. present(status.click.name))
        table.insert(lines, "VID:PID：" .. present(status.click.vendor)
            .. ":" .. present(status.click.product))
        table.insert(lines, "节点：" .. present(status.click.path))
        table.insert(lines, "Handlers：" .. present(status.click.handlers))
    else
        table.insert(lines, "(未检测到 VID:PID 0171:0443)")
    end

    table.insert(lines, "")
    table.insert(lines, "原生蓝牙 LIPC 属性")
    local properties = Bluetooth.getDiagnosticProperties()
    for _, key in ipairs({
        "BTstate", "BTconnectedDevName",
        "currentBTOperatingMode", "isBtchRunning", "wirelessEnable",
    }) do
        table.insert(lines, key .. " = " .. present(properties[key]))
    end
    table.insert(lines, "BTflightMode = (write-only，不读取)")

    table.insert(lines, "")
    table.insert(lines, "电源状态")
    table.insert(lines, "powerd.state = " .. present(readShell(
        "timeout 2 lipc-get-prop com.lab126.powerd state 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, "蓝牙内核模块")
    table.insert(lines, present(readShell(
        "lsmod 2>/dev/null | grep -i -E 'wmt|bt' 2>/dev/null") or "(lsmod 不可用)"))

    table.insert(lines, "")
    table.insert(lines, "内核日志中的蓝牙/无线记录（尾部）")
    table.insert(lines, present(readShell(
        "dmesg 2>/dev/null | grep -i -E 'wmt|bluetooth|btusb|stpbt' | tail -60 2>/dev/null") or "(无)"))

    table.insert(lines, "")
    table.insert(lines, "BT 相关 upstart 作业")
    table.insert(lines, present(readShell(
        "ls /etc/upstart 2>/dev/null | grep -i -E 'bt|bluetooth' 2>/dev/null") or "(无)"))
    table.insert(lines, present(readShell(
        "PATH=/sbin:/usr/sbin:$PATH; initctl list 2>/dev/null | grep -i -E 'bt|bluetooth' 2>/dev/null")))
    table.insert(lines, "pidof：" .. present(readShell(
        "pidof acsbtfd btmanagerd btfd-acsv2 input_manager 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, "蓝牙守护进程 stderr（/tmp/*.err 尾部）")
    for _, path in ipairs({ "/tmp/btfd-acs.err", "/tmp/btmanagerd.err" }) do
        table.insert(lines, "--- " .. path .. " ---")
        table.insert(lines, present(readFile(path, 8000)))
    end

    table.insert(lines, "")
    table.insert(lines, "WMT 传输层状态")
    table.insert(lines, "设备节点：" .. present(readShell(
        "ls -l /dev/stpbt* 2>/dev/null")))
    table.insert(lines, "模块文件：" .. present(readShell(
        "ls /drivers/*/*/wmt_cdev_bt.ko /lib/modules/*/extra/wmt_cdev_bt.ko 2>/dev/null")))
    table.insert(lines, "acsbtfd 打开的 fd：")
    table.insert(lines, present(readShell(
        "for p in $(pidof acsbtfd 2>/dev/null); do ls -l /proc/$p/fd 2>/dev/null; done | grep -i -E 'stpbt|wmt|bt' ; true")
        or "(无匹配)"))
    table.insert(lines, "btmanagerd 打开的 fd：")
    table.insert(lines, present(readShell(
        "for p in $(pidof btmanagerd 2>/dev/null); do ls -l /proc/$p/fd 2>/dev/null; done | grep -i -E 'stpbt|wmt|bt' ; true")
        or "(无匹配)"))
    table.insert(lines, "系统日志中的 BT/WMT 记录（/var/log/messages 尾部）")
    table.insert(lines, present(readShell(
        "tail -600 /var/log/messages 2>/dev/null | grep -i -E 'btfd|bluetooth|wmt' | tail -40")))
    table.insert(lines, "")
    table.insert(lines, "--- /etc/upstart/wmt.conf ---")
    table.insert(lines, present(readFile("/etc/upstart/wmt.conf", 6000)))
    table.insert(lines, "作业定位（引用 btfd 的 upstart 配置）")
    table.insert(lines, present(readShell(
        "grep -l -i -E 'acsbtfd|btmanager|/usr/bin/btfd' /etc/upstart/*.conf 2>/dev/null") or "(未找到)"))

    table.insert(lines, "")
    table.insert(lines, "BT upstart 作业配置")
    for _, name in ipairs({ "acsbtfd", "btmanagerd", "asr_bt_reboot", "asr_bt_userstore" }) do
        local path = "/etc/upstart/" .. name .. ".conf"
        local text = readFile(path, 6000)
        if text then
            table.insert(lines, "--- " .. path .. " ---")
            table.insert(lines, text)
        end
    end

    table.insert(lines, "")
    table.insert(lines, "相关进程")
    table.insert(lines, present(readShell(
        "ps 2>/dev/null | grep -E 'acsbtfd|btfd|input_manager|bluetooth' 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, "Click 配件类型持久化信息")
    table.insert(lines, present(readFile("/var/local/system/bt_device_types.conf", 20000)))

    table.insert(lines, "")
    table.insert(lines, "相关 LIPC 服务与属性（lipc-probe 摘要）")
    table.insert(lines, present(readShell(
        "timeout 5 lipc-probe -a 2>/dev/null | grep -i -E -A 12 -B 2 'btfd|kindleclick|page.?turner|accessories' 2>/dev/null")))

    table.insert(lines, "")
    table.insert(lines, "/proc/bus/input/devices")
    table.insert(lines, present(readFile("/proc/bus/input/devices", 100000)))

    table.insert(lines, "")
    table.insert(lines, "插件日志（" .. Log.path() .. " 尾部）")
    local tail = Log.tail(80)
    table.insert(lines, present(tail))

    table.insert(lines, "")
    table.insert(lines, "说明：kindle-input-pt 常驻不代表 Click 已连接；")
    table.insert(lines, "真正的连接依据是上方 0171:0443 HID 节点。")
    table.insert(lines, "本诊断不读取或导出蓝牙 LinkKey。")

    local body = table.concat(lines, "\n")
    local file = io.open(DIAGNOSTIC_FILE, "w")
    local saved = false
    if file then
        saved = file:write(body) ~= nil
        file:close()
    end

    local header = saved
        and ("诊断文件已保存到：\n" .. DIAGNOSTIC_FILE .. "\n\n")
        or  ("无法保存诊断文件：\n" .. DIAGNOSTIC_FILE .. "\n\n")
    return header .. body, saved and DIAGNOSTIC_FILE or nil
end

return Diagnostics
