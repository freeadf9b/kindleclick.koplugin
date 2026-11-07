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
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Icons = require("kindleclick_icons")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local IDLE_REFRESH_INTERVAL = 30 -- only while the menu/footer is already being drawn
local KEY_PAGEUP = 104
local KEY_PAGEDOWN = 109

local function yes() return true end

local KindleClick = WidgetContainer:extend{
    name = "kindleclick",
    is_doc_only = false,
}

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
    if not Device:hasKeys() then Device.hasKeys = yes end

    -- On the tested KPW6, the native path applies its orientation swap.
    -- Prevent a second swap for that observed pass-through device.
    local passthrough = Bluetooth.getPassThroughDevice()
    if passthrough and passthrough.path then
        local Input = require("device/input")
        local fd = Input.opened_devices[passthrough.path]
        input.rotation_ignored_fds = input.rotation_ignored_fds or {}
        if fd then input.rotation_ignored_fds[fd] = true end
    end

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
        initialized = false,
    }
    self._checks = {}
    self._last_refresh = 0
    self.show_in_footer = G_reader_settings:nilOrTrue("kindleclick_show_in_footer")
    self.auto_connect = G_reader_settings:nilOrTrue("kindleclick_auto_connect")

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
    if not self.state.known then return "?" end
    local icon_state = "off"
    if self.state.known and self.state.enabled then
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

    local status = Bluetooth.getStatus()
    local changed = not self.state.initialized
        or self.state.known ~= status.known
        or self.state.enabled ~= status.enabled
        or self.state.device_name ~= status.device_name

    self.state.enabled = status.enabled
    self.state.device_name = status.device_name
    self.state.native_click = status.native_click
    self.state.known = status.known
    self.state.status_error = status.status_error
    self.state.initialized = true
    self._last_refresh = os.time()

    if changed then self:_updateFooter() end
    if Bluetooth.isKindleClick(status.device_name) then
        self:_cancelChecks()
    end
end

function KindleClick:_requestStatusRefresh()
    if self._closed or self._refresh_pending then return end
    if os.time() - self._last_refresh < IDLE_REFRESH_INTERVAL then return end
    self._refresh_pending = true
    UIManager:nextTick(function()
        if not self._closed then self:_refreshStatus(false) end
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
    local delays = { 2, 5, 10, 20 }
    local function scheduleCheck(attempt, delay)
        local callback
        callback = function()
            for i, item in ipairs(self._checks) do
                if item == callback then
                    table.remove(self._checks, i)
                    break
                end
            end
            if self._closed then return end

            self:_refreshStatus(true)
            if attempt == #delays
                and not Bluetooth.isKindleClick(self.state.device_name) then
                local message = not self.state.known
                    and _("无法读取蓝牙状态，请查看诊断信息")
                    or  _("未能确认 Kindle Click 已连接，请检查原生配对状态")
                self:_showMessage(message, 5)
            end
        end
        table.insert(self._checks, callback)
        UIManager:scheduleIn(delay, callback)
    end
    for attempt, delay in ipairs(delays) do
        scheduleCheck(attempt, delay)
    end
end

function KindleClick:_scheduleBluetoothRecoveryCheck(delay, attempts)
    local callback
    callback = function()
        for i, item in ipairs(self._checks) do
            if item == callback then
                table.remove(self._checks, i)
                break
            end
        end
        if self._closed then return end

        self:_refreshStatus(true)
        if self.state.enabled == true then
            if self.auto_connect
                and not Bluetooth.isKindleClick(self.state.device_name) then
                self:_connectClick(false)
            end
            return
        end

        if attempts >= 3 then
            self:_showMessage(_([[启动或唤醒后无法确认蓝牙已恢复。
请打开“诊断信息”检查 btfd 状态；插件不会重启系统蓝牙服务或修改配对数据。]]), 6)
            return
        end

        -- Reassert only the saved/explicitly requested on state. Do not restart
        -- btfd or manipulate the radio outside Kindle's native LIPC API.
        Bluetooth.requestEnabled(true)
        self:_scheduleBluetoothRecoveryCheck(attempts == 0 and 3 or 6, attempts + 1)
    end
    table.insert(self._checks, callback)
    UIManager:scheduleIn(delay, callback)
end

function KindleClick:_scheduleBluetoothRecovery()
    self:_cancelChecks()
    self:_scheduleBluetoothRecoveryCheck(2, 0)
end

function KindleClick:_showMessage(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

function KindleClick:_setEnabled(enabled, quiet)
    self:_cancelChecks()
    if not quiet then
        self:_showMessage(enabled and _("正在打开蓝牙…") or _("正在关闭蓝牙…"), 1)
    end

    -- Request release of a stale Click session before asking the native
    -- service to enable Bluetooth; this does not guarantee hardware recovery.
    if enabled then Bluetooth.releaseClick() end
    local ok, reason = Bluetooth.setEnabled(enabled)
    self:_refreshStatus(true)

    if ok and enabled then
        -- Ask the native service to connect only when the native HID path is
        -- absent; firmware-specific automatic reconnection is not assumed.
        if not self.state.native_click then
            local address = Bluetooth.findPairedKindleClick()
            if address then Bluetooth.connect(address) end
        end
        self:_scheduleConnectionChecks()
    elseif enabled then
        self:_scheduleBluetoothRecovery()
    end

    if not quiet then
        local message
        if not ok then
            if reason == "status-unavailable" then
                message = _("无法读取蓝牙状态，正在有限重试；仍失败请查看诊断信息")
            else
                message = enabled
                    and _("蓝牙开启未确认，正在有限重试")
                    or  _("蓝牙关闭失败，请在 Kindle 原生设置中检查")
            end
        elseif enabled and self.state.native_click then
            message = _("蓝牙已开启，等待 Kindle Click 自动重连")
        else
            message = enabled and _("蓝牙已开启，正在连接 Kindle Click")
                                or  _("蓝牙已关闭")
        end
        self:_showMessage(message, ok and 3 or 4)
    end
    return ok
end

function KindleClick:_connectClick(manual)
    self:_refreshStatus(true)
    if Bluetooth.isKindleClick(self.state.device_name) then
        if manual then self:_showMessage(_("Kindle Click 已连接"), 2) end
        return true
    end

    if not self.state.known then
        if manual then return self:_setEnabled(true, false) end
        self:_scheduleBluetoothRecovery()
        return true
    end

    if not self.state.enabled then
        return self:_setEnabled(true, not manual)
    end

    if self.state.native_click then
        self:_scheduleConnectionChecks()
        if manual then
            self:_showMessage(_([[原生系统正在自动重连。请按一下 Kindle Click 并等待几秒。
若仍未连接，请在 Kindle 原生“蓝牙设备”设置中检查配对并手动连接。]]), 6)
        end
        return true
    end

    local address = Bluetooth.findPairedKindleClick()
    if not address then
        if manual then
            self:_showMessage(_("未找到已配对的 Kindle Click，请先在 Kindle 原生设置中配对"), 5)
        end
        return false
    end

    Bluetooth.connect(address)
    self:_scheduleConnectionChecks()
    if manual then self:_showMessage(_("正在连接 Kindle Click…"), 2) end
    return true
end

function KindleClick:onToggleBluetooth()
    self:_refreshStatus(true)
    if not self.state.known then
        self:_showMessage(_("无法读取蓝牙状态；为避免错误切换，请先查看诊断信息"), 5)
        return
    end
    self:_setEnabled(not self.state.enabled, false)
end

function KindleClick:_connectedDeviceText()
    self:_requestStatusRefresh()
    if not self.state.known then return _("已连接设备：蓝牙状态未知") end
    if self.state.enabled == false then return _("已连接设备：蓝牙已关闭") end
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
            if not self.state.known then return _("Kindle Click（蓝牙状态未知）") end
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
            if not self.state.known then return nil end
            return self.state.enabled
        end,
        -- Long-press the parent entry for a one-touch switch.
        hold_callback = function() self:onToggleBluetooth() end,
        sub_item_table_func = function()
            self:_refreshStatus(true)
            return {
                {
                    text = _("蓝牙"),
                    checked_func = function()
                        if not self.state.known then return nil end
                        return self.state.enabled
                    end,
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
                },
                {
                    text = _("使用说明"),
                    keep_menu_open = true,
                    callback = function()
                        self:_showMessage(_([[首次使用请先在 Kindle 原生设置中配对 Kindle Click。

蓝牙关闭、蓝牙开启但未连接、Click 已连接三种状态共用同一个图标位。可在“状态栏图标”中分别选择预设或输入 symbols.ttf 的 Unicode 码位。

Bookends 请在任意行加入 %plugin_content{kindleclick}，即可只显示本插件状态；不加花括号则会聚合所有插件。

5.20.1 由原生系统自动重连 Click，并直接处理亮度侧键及双侧键长按休眠。本插件只补充 PageUp/PageDown 翻页映射，不重复执行原生动作，不打开或抢占输入节点，也无需启用 ExternalKeyboard。

长按本插件的上一级菜单项可直接开关蓝牙。]]), 12)
                    end,
                },
            }
        end,
    }
end

function KindleClick:onEvdevInputInsert()
    self:_cancelChecks()
    self:_scheduleCheck(0.75)
end

function KindleClick:onEvdevInputRemove()
    self:_cancelChecks()
    self:_scheduleCheck(0.75)
end

function KindleClick:onSuspend()
    self:_cancelChecks()
    -- Keep a process-local snapshot: deep sleep does not restart KOReader, and
    -- resume must never turn on Bluetooth if the user had explicitly turned it
    -- off before sleeping.
    local status = Bluetooth.getStatus()
    self._pre_sleep_enabled = status.enabled

    -- Release Click through the native service on suspend. Event ordering and
    -- deep-sleep behavior vary by firmware and are not assumed here.
    if status.click then Bluetooth.releaseClick() end
end

function KindleClick:onResume()
    -- Consume the snapshot so duplicate Resume events cannot repeat recovery.
    local restore = self._pre_sleep_enabled
    self._pre_sleep_enabled = nil
    self:_refreshStatus(true)
    if restore == true then
        self:_scheduleBluetoothRecovery()
    end
end

function KindleClick:onCloseWidget()
    self._closed = true
    self:_cancelChecks()
    self:_removeFooterSymbol()
end

function KindleClick:deletePluginSettings()
    G_reader_settings:delSetting("kindleclick_auto_connect")
    G_reader_settings:delSetting("kindleclick_show_in_footer")
    Icons.deleteSettings()
end

return KindleClick
