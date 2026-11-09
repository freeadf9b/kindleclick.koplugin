--[[--
Kindle Click / Bluetooth control for KOReader on Kindle.

This plugin never opens or grabs input devices. Kindle's native input pipeline
handles Click; the plugin only adds PageUp/PageDown mappings missing on
KOReader's touch-only Kindle models.
--]]

local Device = require("device")
if not Device:isKindle() then
    return { disabled = true }
end

local Bluetooth = require("kindleclick_bluetooth")
local Backend = require("kindleclick_backend")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Icons = require("kindleclick_icons")
local InfoMessage = require("ui/widget/infomessage")
local Log = require("kindleclick_log")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local IDLE_REFRESH_INTERVAL = 30 -- only while the menu/footer is already being drawn
local SLEEP_GAP_SECONDS = 600 -- a longer gap means the device was suspended
local WAKE_RECOVERY_DELAY = 3
-- Read-only checks after a failed recovery: the native stack often returns by
-- itself, but only after several minutes. No further Bluetooth commands are
-- sent during this window.
local PASSIVE_WATCH_GAPS = { 60, 120, 180, 240, 300, 300, 300, 300 }
local KEY_PAGEUP = 104
local KEY_PAGEDOWN = 109

-- Directory this plugin was loaded from, used to find fonts/kindleclick-icons.ttf.
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")

-- Version is read from _meta.lua so the menu label and the plugin metadata
-- can never drift apart.
local function read_plugin_version()
    if not plugin_dir then return nil end
    local file = io.open(plugin_dir .. "/_meta.lua", "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return text and text:match('version%s*=%s*"([^"]+)"')
end

local function yes() return true end

local KindleClick = WidgetContainer:extend{
    name = "kindleclick",
    is_doc_only = false,
}

-- Amazon's input_manager has already applied its own orientation swap. Prevent
-- KOReader from swapping the pass-through events a second time. The fd only
-- exists once KOReader has opened the device, so hotplug re-applies this.
function KindleClick:_ignoreRotationForPassthrough()
    local passthrough = Bluetooth.getPassThroughDevice()
    if not passthrough or not passthrough.path then return end
    local Input = require("device/input")
    local fd = Input.opened_devices and Input.opened_devices[passthrough.path]
    if not fd then return end
    local input = Device.input
    if not input then return end
    input.rotation_ignored_fds = input.rotation_ignored_fds or {}
    input.rotation_ignored_fds[fd] = true
end

-- Touch-only Kindles do not map PageUp/PageDown by default. Add only those two
-- mappings; do not open devices, grab EVIOCGRAB, or enable keyboard text input.
function KindleClick:_installInputSupport()
    local input = Device.input
    if not input then return end
    input.event_map = input.event_map or {}
    if input.event_map[KEY_PAGEUP] == nil then
        input.event_map[KEY_PAGEUP] = "LPgBack"
    end
    if input.event_map[KEY_PAGEDOWN] == nil then
        input.event_map[KEY_PAGEDOWN] = "LPgFwd"
    end
    -- Only the "device has keys" flag is set; keyboard text input stays off.
    if not Device:hasKeys() then Device.hasKeys = yes end

    self:_ignoreRotationForPassthrough()

    -- A book may already be open when plugins initialize, so refresh its key
    -- registrations now. Books opened later inherit Device.hasKeys themselves.
    for _, name in ipairs({ "paging", "rolling" }) do
        local module = self.ui[name]
        if module and module.registerKeyEvents then
            module:registerKeyEvents()
        end
    end
end

function KindleClick:init()
    self.state = {
        enabled = false,
        device_name = nil,
        native_click = false,
        known = false,
    }
    self._checks = {}
    self._last_refresh = os.time()
    self._refresh_pending = false
    self._wake_recovery_running = false
    self._passive_watch = false
    self.show_in_footer = G_reader_settings:nilOrTrue("kindleclick_show_in_footer")
    self.auto_connect = G_reader_settings:nilOrTrue("kindleclick_auto_connect")
    self.version = read_plugin_version()
    local icon_font_state = Icons.ensureFont(plugin_dir)

    self._status_content_func = function()
        -- Activity-driven refresh: no timer runs while the reader is idle.
        self:_requestStatusRefresh()
        return self:_statusText()
    end

    self:_installInputSupport()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self:_addFooterSymbol()

    UIManager:nextTick(function()
        if self._closed then return end
        self:_refreshStatus(true)
        if self.auto_connect and not Bluetooth.isKindleClick(self.state.device_name) then
            self:_connectClick(false)
        end
        if icon_font_state == "needs_restart" then
            self:_showMessage(
                _("已安装随插件附带的图标字体，请重启 KOReader 后生效"), 8)
        end
    end)
end

function KindleClick:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindleclick_toggle_bluetooth", {
        category = "none",
        event = "KindleClickToggleBluetooth",
        title = _("Kindle Click：开/关蓝牙"),
        device = true,
    })
    Dispatcher:registerAction("kindleclick_connect", {
        category = "none",
        event = "KindleClickConnect",
        title = _("Kindle Click：连接"),
        device = true,
    })
end

function KindleClick:onKindleClickToggleBluetooth()
    self:onToggleBluetooth()
    return true
end

function KindleClick:onKindleClickConnect()
    self:_connectClick(true)
    return true
end

function KindleClick:_statusText()
    -- "?" means the state could not be read; never show a confident OFF icon.
    if not self.state.known then return "?" end
    local icon_state = "off"
    if self.state.enabled then
        icon_state = Bluetooth.isKindleClick(self.state.device_name) and "click" or "on"
    end
    return Icons.getGlyph(icon_state)
end

function KindleClick:_updateFooter()
    -- Bookends listens to the same event even when KOReader's own bar is hidden.
    UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
end

function KindleClick:_addFooterSymbol()
    if not self.show_in_footer or self._footer_added then return end
    local footer = self.ui.view and self.ui.view.footer
    if not footer then return end
    footer:addAdditionalFooterContent(self._status_content_func)
    self._footer_added = true
    self:_updateFooter()
end

function KindleClick:_removeFooterSymbol()
    if not self._footer_added then return end
    local footer = self.ui.view and self.ui.view.footer
    if footer then
        footer:removeAdditionalFooterContent(self._status_content_func)
    end
    self._footer_added = false
    self:_updateFooter()
    UIManager:broadcastEvent(Event:new("UpdateFooter", true))
end

function KindleClick:_refreshStatus(force)
    if self._closed then return end
    self._refresh_pending = false

    local was_enabled = self.state.known and self.state.enabled
    local gap = os.time() - (self._last_refresh or 0)

    local status = Backend.getStatus()
    local changed = not self.state.known
        or self.state.enabled ~= status.enabled
        or self.state.device_name ~= status.device_name

    self.state.enabled = status.enabled
    self.state.device_name = status.device_name
    self.state.native_click = status.native_click
    self.state.known = status.known
    self._last_refresh = os.time()

    if changed then
        Log.write("status", string.format("enabled=%s device=%s wireless=%s gap=%ss",
            tostring(status.enabled), tostring(status.device_name),
            tostring(Bluetooth.getWirelessState()), tostring(gap)))
        self:_updateFooter()
    end
    if Bluetooth.isKindleClick(status.device_name) then
        self:_cancelChecks()
    end

    -- A long gap means the device was suspended. If Bluetooth was on before
    -- and reads as off now, the controller did not come back by itself; the
    -- Resume event is not guaranteed when the system, not KOReader, suspended.
    if was_enabled and status.known and not status.enabled and gap >= SLEEP_GAP_SECONDS
        and self.auto_connect and not self._wake_recovery_running then
        Log.write("wake", "long idle gap (" .. gap .. "s), Bluetooth came back off")
        self:_startWakeRecovery("gap")
    end
end

function KindleClick:_cancelWakeRecovery()
    if not self._wake_recovery_running then return end
    self._wake_recovery_running = false
    self._wake_started = nil
    Log.write("wake", "recovery cancelled")
end

function KindleClick:_cancelUserOverrides()
    self:_cancelWakeRecovery()
    self:_stopPassiveWatch()
end

-- Give the native stack a moment to finish waking up, then ask once. The
-- backend confirms the request and reports back here; it never retries.
function KindleClick:_wakeRecoveryAttempt()
    if self._closed then
        self._wake_recovery_running = false
        return
    end
    Log.write("wake", "attempt: " .. Bluetooth.describe())
    self:_refreshStatus(true)
    if self.state.enabled then
        self._wake_recovery_running = false
        Log.write("wake", "Bluetooth is back on")
        if not Bluetooth.isKindleClick(self.state.device_name) then
            self:_connectClick(false)
        end
        return
    end
    self:_setEnabled(true, true)
end

function KindleClick:_startWakeRecovery(reason)
    if self._closed then return end
    -- A stuck request must not block recovery forever.
    if self._wake_recovery_running
        and os.time() - (self._wake_started or 0) < 120 then
        return
    end
    self._wake_recovery_running = true
    self._wake_started = os.time()
    Log.write("wake", "recovery scheduled (" .. reason .. "): " .. Bluetooth.describe())
    UIManager:scheduleIn(WAKE_RECOVERY_DELAY, function()
        if not self._closed and self._wake_recovery_running then
            self:_wakeRecoveryAttempt()
        end
    end)
end

-- Called by _setEnabled once a wake-triggered power request has finished.
-- Recovery is one attempt only: repeated requests can delay the native stack's
-- own start-up, so after a failure the plugin only watches read-only.
function KindleClick:_noteWakeRecoveryResult(ok)
    if not self._wake_recovery_running then return end
    self._wake_recovery_running = false
    if ok then
        Log.write("wake", "Bluetooth is back on")
        return
    end
    Log.write("wake", "recovery failed: " .. Bluetooth.describe())
    self:_showMessage(
        _("蓝牙在唤醒后仍未恢复。插件不再自动重试；状态栏会继续自动更新，也可以稍后手动切换蓝牙。"), 8)
    self:_startPassiveWatch("wake failed")
end

-- The native stack can come back on its own several minutes after a failed
-- wake (the framework appears to retry on its own schedule). Keep looking
-- without sending any more Bluetooth commands, and update the UI if it does
-- come back.
function KindleClick:_startPassiveWatch(reason)
    if self._closed or self._passive_watch then return end
    self._passive_watch = true
    Log.write("watch", "passive watch started (" .. reason .. "): " .. Bluetooth.describe())
    local index = 0

    local function check()
        if self._closed or not self._passive_watch then return end
        self:_refreshStatus(true)
        if self.state.enabled then
            self._passive_watch = false
            Log.write("watch", "Bluetooth returned during passive watch")
            if not Bluetooth.isKindleClick(self.state.device_name) then
                self:_connectClick(false)
            end
            return
        end
        index = index + 1
        local gap = PASSIVE_WATCH_GAPS[index]
        if not gap then
            self._passive_watch = false
            Log.write("watch", "passive watch ended, Bluetooth still off")
            return
        end
        UIManager:scheduleIn(gap, check)
    end

    UIManager:scheduleIn(PASSIVE_WATCH_GAPS[1], check)
end

function KindleClick:_stopPassiveWatch()
    if not self._passive_watch then return end
    self._passive_watch = false
    Log.write("watch", "passive watch cancelled")
end

function KindleClick:_requestStatusRefresh()
    if self._closed or self._refresh_pending then return end
    if os.time() - self._last_refresh < IDLE_REFRESH_INTERVAL then return end
    self._refresh_pending = true
    UIManager:nextTick(function()
        -- A forced refresh may already have consumed this queued request.
        if self._closed or not self._refresh_pending then return end
        self:_refreshStatus(false)
    end)
end

function KindleClick:_cancelChecks()
    for _, callback in ipairs(self._checks) do
        UIManager:unschedule(callback)
    end
    self._checks = {}
end

function KindleClick:_scheduleCheck(delay)
    local callback
    callback = function()
        for i, item in ipairs(self._checks) do
            if item == callback then
                table.remove(self._checks, i)
                break
            end
        end
        if not self._closed then self:_refreshStatus(true) end
    end
    table.insert(self._checks, callback)
    UIManager:scheduleIn(delay, callback)
end

-- A short, bounded connection window. Once Click is connected (or after the
-- last check), no timer remains active.
function KindleClick:_scheduleConnectionChecks()
    self:_cancelChecks()
    for _, delay in ipairs({ 2, 5, 10, 20 }) do
        self:_scheduleCheck(delay)
    end
end

function KindleClick:_showMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

function KindleClick:_setEnabled(enabled, quiet)
    self:_cancelChecks()
    self._power_request = (self._power_request or 0) + 1
    local request = self._power_request
    if not quiet then
        self:_showMessage(enabled and _("正在打开蓝牙…") or _("正在关闭蓝牙…"), 2)
    end

    Backend.setEnabled(enabled, function(ok, err)
        if self._closed or request ~= self._power_request then return end
        self:_refreshStatus(true)
        if ok and enabled then
            local device = Backend.findPairedKindleClick()
            if device then
                Backend.connect(device, function()
                    if not self._closed then self:_refreshStatus(true) end
                end)
            end
            self:_scheduleConnectionChecks()
        end

        self:_noteWakeRecoveryResult(ok and enabled)
        if not ok and enabled and not self._wake_recovery_running then
            self:_startPassiveWatch("enable failed")
        end

        if not quiet then
            local message
            if not ok then
                message = enabled and _("蓝牙开启失败") or _("蓝牙关闭失败")
                if err then message = message .. "\n" .. err end
            else
                message = enabled and _("蓝牙已开启，正在连接 Kindle Click")
                                    or  _("蓝牙已关闭")
            end
            self:_showMessage(message, ok and 3 or 5)
        end
    end)
    return true
end

function KindleClick:_connectClick(manual)
    if manual then self:_cancelUserOverrides() end
    self:_refreshStatus(true)
    if Bluetooth.isKindleClick(self.state.device_name) then
        if manual then self:_showMessage(_("Kindle Click 已连接"), 2) end
        return true
    end

    if not self.state.known then
        -- Unreadable state: never toggle blindly; a manual tap may still ask
        -- for an enable, an automatic one just schedules the wake recovery.
        if manual then return self:_setEnabled(true, false) end
        self:_startWakeRecovery("status unknown")
        return false
    end

    if not self.state.enabled then
        return self:_setEnabled(true, not manual)
    end

    local device = Backend.findPairedKindleClick()
    if not device then
        if manual then
            self:_showMessage(_("未找到已配对的 Kindle Click，请先在 Kindle 原生系统中配对"), 5)
        end
        self:_scheduleConnectionChecks()
        return false
    end

    Backend.connect(device, function(ok, err)
        if self._closed then return end
        self:_refreshStatus(true)
        if ok or Bluetooth.isKindleClick(self.state.device_name) then return end
        -- The first native Connect request is sometimes ignored; a single
        -- delayed retry is enough and avoids a request loop.
        if self.state.enabled and not self._connect_retry_pending then
            self._connect_retry_pending = true
            Log.write("connect", "not connected yet, retrying once in 10 s")
            UIManager:scheduleIn(10, function()
                self._connect_retry_pending = false
                if self._closed or not self.state.enabled then return end
                if Bluetooth.isKindleClick(self.state.device_name) then return end
                Backend.connect(device, function(ok2, err2)
                    if self._closed then return end
                    self:_refreshStatus(true)
                    if manual and not ok2
                        and not Bluetooth.isKindleClick(self.state.device_name) then
                        self:_showMessage(err2 or _("连接 Kindle Click 失败"), 4)
                    end
                end)
            end)
            return
        end
        if manual and err then self:_showMessage(err, 4) end
    end)
    self:_scheduleConnectionChecks()
    if manual then self:_showMessage(_("正在连接 Kindle Click…若较久未连上，请按一下 Click"), 3) end
    return true
end

function KindleClick:onToggleBluetooth()
    self:_cancelUserOverrides()
    self:_refreshStatus(true)
    if not self.state.known then
        self:_showMessage(_("无法读取蓝牙状态，请先查看诊断信息"), 5)
        return
    end
    self:_setEnabled(not self.state.enabled, false)
end

function KindleClick:_connectedDeviceText()
    self:_requestStatusRefresh()
    if not self.state.known then return _("已连接设备：蓝牙状态未知") end
    if not self.state.enabled then return _("已连接设备：蓝牙已关闭") end
    return _("已连接设备：") .. (self.state.device_name or _("无"))
end

function KindleClick:_showDiagnostics()
    local Diagnostics = require("kindleclick_diagnostics")
    local TextViewer = require("ui/widget/textviewer")
    local text = Diagnostics.collect()
    UIManager:show(TextViewer:new{
        title = _("Kindle Click 诊断信息"),
        text = text,
        text_type = "code",
        justified = false,
    })
end

function KindleClick:addToMainMenu(menu_items)
    menu_items.kindleclick = {
        text_func = function()
            self:_requestStatusRefresh()
            if not self.state.known then
                return _("Kindle Click（蓝牙状态未知）")
            end
            if Bluetooth.isKindleClick(self.state.device_name) then
                return _("Kindle Click（已连接）")
            elseif self.state.enabled then
                return _("Kindle Click（蓝牙已开启）")
            end
            return _("Kindle Click（蓝牙已关闭）")
        end,
        sorting_hint = "network",
        checked_func = function()
            self:_requestStatusRefresh()
            return self.state.enabled
        end,
        -- Long-press the parent entry for a one-touch switch.
        hold_callback = function() self:onToggleBluetooth() end,
        sub_item_table_func = function()
            self:_refreshStatus(true)
            return {
                {
                    text = _("蓝牙"),
                    checked_func = function() return self.state.enabled end,
                    check_callback_updates_menu = true,
                    callback = function() self:onToggleBluetooth() end,
                },
                {
                    text_func = function() return self:_connectedDeviceText() end,
                    enabled = false,
                    separator = true,
                },
                {
                    text = _("连接 Kindle Click"),
                    keep_menu_open = true,
                    callback = function() self:_connectClick(true) end,
                },
                {
                    text = _("刷新连接状态"),
                    keep_menu_open = true,
                    callback = function(touchmenu)
                        self:_refreshStatus(true)
                        if touchmenu then touchmenu:updateItems() end
                    end,
                    separator = true,
                },
                {
                    text = _("启动 KOReader 时自动连接"),
                    checked_func = function() return self.auto_connect end,
                    callback = function()
                        self.auto_connect = not self.auto_connect
                        G_reader_settings:flipNilOrTrue("kindleclick_auto_connect")
                    end,
                },
                {
                    text = _("状态栏图标（三种状态）"),
                    sub_item_table_func = function() return Icons.getMenu(self) end,
                },
                {
                    text = _("在状态栏显示三态图标（含 Bookends）"),
                    checked_func = function() return self.show_in_footer end,
                    callback = function()
                        self.show_in_footer = not self.show_in_footer
                        G_reader_settings:flipNilOrTrue("kindleclick_show_in_footer")
                        if self.show_in_footer then
                            self:_addFooterSymbol()
                        else
                            self:_removeFooterSymbol()
                        end
                    end,
                    separator = true,
                },
                {
                    text = _("诊断信息"),
                    keep_menu_open = true,
                    callback = function() self:_showDiagnostics() end,
                    separator = true,
                },
                {
                    text_func = function()
                        local label = _("使用说明")
                        if self.version then
                            return label .. "  v" .. self.version
                        end
                        return label
                    end,
                    keep_menu_open = true,
                    callback = function()
                        self:_showMessage(_([[请先在 Kindle 原生系统中配对 Kindle Click。

蓝牙关闭、蓝牙开启但未连接、Click 已连接三种状态共用同一个图标位。可在“状态栏图标”中分别选择预设或输入 symbols.ttf 的 Unicode 码位。

Bookends 请在任意行加入 %plugin_content{kindleclick}，即可只显示本插件状态；不加花括号则会聚合所有插件。

本插件仅使用 Kindle 5.20.1 原生 btfd 与 HID 通道。亮度侧键及双侧键长按休眠仍由原生系统处理；本插件只补充 PageUp/PageDown 翻页映射，不打开或抢占输入节点，也无需启用 ExternalKeyboard。

长按本插件的上一级菜单项可直接开关蓝牙。]]), 12)
                    end,
                },
            }
        end,
    }
end

function KindleClick:onEvdevInputInsert()
    self:_ignoreRotationForPassthrough()
    self:_cancelChecks()
    self:_scheduleCheck(0.75)
end

function KindleClick:onEvdevInputRemove()
    self:_cancelChecks()
    self:_scheduleCheck(0.75)
end

function KindleClick:onSuspend()
    self:_cancelChecks()
    self._power_request = (self._power_request or 0) + 1
    -- Keep a process-local snapshot: deep sleep does not restart KOReader, and
    -- resume must never turn on Bluetooth if the user had explicitly turned it
    -- off before sleeping. Reuse the last activity-driven status instead of
    -- talking to btfd during the suspend transition.
    local status = self.state.known and self.state or Backend.getStatus()
    self._pre_sleep_enabled = status.enabled
    Log.write("lifecycle", "suspend, pre_sleep_enabled=" .. tostring(status.enabled)
        .. ", " .. Bluetooth.describe())

    -- Match Moon: snapshot only and leave the native Bluetooth stack alone.
    -- Disconnecting during the suspend transition can itself disturb btfd.
end

function KindleClick:onResume()
    -- Consume the snapshot so duplicate Resume events cannot repeat recovery.
    local restore = self._pre_sleep_enabled
    self._pre_sleep_enabled = nil
    Log.write("lifecycle", "resume, restore=" .. tostring(restore))
    -- A watch left over from before the sleep is stale: the native stack has
    -- just resumed, so this path is the only one that decides what happens.
    self:_stopPassiveWatch()
    self:_refreshStatus(true)
    if not (self.auto_connect and restore) then return end
    if self.state.enabled then
        -- The native stack may have brought the radio up during resume; do
        -- not let an older scheduled attempt connect a second time.
        self:_cancelWakeRecovery()
        if not Bluetooth.isKindleClick(self.state.device_name) then
            self:_connectClick(false)
        end
        return
    end
    self:_startWakeRecovery("resume")
end

function KindleClick:onCloseWidget()
    self._closed = true
    self._power_request = (self._power_request or 0) + 1
    self._wake_recovery_running = false
    self:_cancelChecks()
    self:_removeFooterSymbol()
end

function KindleClick:deletePluginSettings()
    G_reader_settings:delSetting("kindleclick_auto_connect")
    G_reader_settings:delSetting("kindleclick_show_in_footer")
    Icons.deleteSettings()
end

return KindleClick
