# Kindle Click 蓝牙 / Kindle Click Bluetooth

[中文说明](#中文说明) | [English](#english)

---

## 中文说明

仅用于 **Kindle** 的独立 KOReader 插件。控制原生蓝牙、识别 Kindle Click、补充翻页键映射，并在菜单、KOReader 阅读状态栏或 Bookends 中显示状态。

### 功能

- 在 **设置 → 网络 → Kindle Click** 中加入蓝牙开关。
- 显示当前蓝牙连接的设备名称。
- 启动 KOReader 或唤醒时让原生系统恢复蓝牙和 Click 连接（可关闭自动连接）。
- 休眠前仅保存蓝牙状态，不干扰原生连接；唤醒后通过原生 btfd 恢复蓝牙，并主动重新连接 Click。
- 深度休眠后若蓝牙没有自行恢复，插件会自动重试：给原生栈留出就绪时间，必要时先复位射频再重新开启，并使用厂商的备用开启模式；每一步都写入 `kindleclick.log`。
- 读不到蓝牙状态时（`BTstate` 与 `currentBTOperatingMode` 都失败），状态栏显示 `?`、菜单标注“蓝牙状态未知”，并且不会把“读不到”误报成“已关闭”，也不会盲目切换。
- 原生系统也开不了蓝牙时，可在菜单里执行“深度恢复”：蓝牙关闭时重启 `acsbtfd` / `btmanagerd` 并最多等待约 4 分钟；蓝牙已开启时不重启服务（那会打断连接），只等待 Click 连上。插件不会改动飞行模式或 Wi-Fi。
- 提供“连接 Kindle Click”“刷新连接状态”和“诊断信息”菜单项。
- 长按“Kindle Click”上一级菜单项，可以直接开关蓝牙。
- 三种状态共用**同一个图标位**，不再用有无图标表示开关：
  - 蓝牙关闭：默认显示“蓝牙关闭”图标。
  - 蓝牙已开启但未连接 Kindle Click：默认显示“蓝牙”图标。
  - 已连接 Kindle Click：默认显示“遥控器”图标。
- 三种状态可分别选择图标。预设及自定义码位均使用 KOReader 自带的 `nerdfonts/symbols.ttf`；也可输入其他 Unicode 符号码位。
- 提供“开/关蓝牙”和“连接”两个动作，可在 KOReader 手势管理中绑定。
- 为触屏版 Kindle 补充 `KEY_PAGEUP` / `KEY_PAGEDOWN` 翻页映射，不启用整套外接键盘文本输入。

### 截图

**菜单与蓝牙控制**

![Kindle Click 菜单与蓝牙控制](screenshots/menu.png)

**三种连接状态共用同一个图标位**

![三种连接状态共用同一个图标位](screenshots/status-icons.png)

**在 Bookends 中配置状态显示**

![在 Bookends 状态栏中显示 Kindle Click](screenshots/bookends.png)

### 安装或升级

1. 先在 Kindle 原生系统中完成 Kindle Click 配对。本插件不提供扫描和配对界面。
2. 升级旧版时，先删除旧的 `kindleclick.koplugin` 文件夹，再将新版完整复制到：

   ```text
   /mnt/us/koreader/plugins/kindleclick.koplugin
   ```

3. 完全退出并重新启动 KOReader，使翻页映射和当前书籍的按键注册重新加载。
4. 打开顶部菜单，进入 **设置 → 网络 → Kindle Click**。

### 自定义状态栏图标

进入 **Kindle Click → 状态栏图标（三种状态）**，分别设置“蓝牙关闭”“蓝牙开启，Click 未连接”“Kindle Click 已连接”。

每个状态都有预设图标和“自定义 Unicode 码位”。例如 `U+E7B1` 是蓝牙关闭、`U+E7AE` 是蓝牙、`U+EB53` 是遥控器。自定义输入支持 `U+EB53`、`0xEB53` 或 `EB53` 三种写法。若所选字形不在字体中，可能显示为空框。

**随插件附带的图标字体**

插件自带 `fonts/kindleclick-icons.ttf`，包含三种状态各一个字形：`U+E900` 蓝牙关闭、`U+E901` 蓝牙开启、`U+E902` 已连接。字形按整字高绘制，三个图标的垂直中心与状态栏时间数字的中心对齐；遥控器保持原始比例、不旋转。首次启动时插件会把它复制到 `koreader/fonts/` 并注册为 KOReader 的额外回退字体，然后提示重启一次 KOReader。重启后在 **状态栏图标（三种状态）** 里点“一键使用我的图标（关 / 开 / 已连接）”即可。字体升级时插件会自动覆盖旧字体并再次提示重启。

需要注意：

- KOReader 的“额外 UI 回退字体”菜单只列出文件名以 Noto Sans 开头的字体，本字体不会出现在该菜单里。如果在该菜单里改动过回退字体列表，本项会被移除，插件下次启动会自动重新注册（再重启一次即可恢复）。
- 字体只包含这三个字形，其它文字仍使用你原来的字体，不会互相影响。
- **重复更新插件不会重复注册**：注册前按绝对路径查重，并会清掉同名（`kindleclick-icons.ttf`）的旧路径，回退字体列表里始终只有一条本字体记录。

“在状态栏显示三态图标（含 Bookends）”是本插件的总开关；关闭后会同时从原生状态栏和 Bookends 移除本插件内容。

### 在 Bookends 中显示

不需要修改 Bookends 源文件。Bookends 会直接读取本插件注册到 KOReader 的状态栏内容，即使 KOReader 自带状态栏已关闭也可以显示。

在 Bookends 希望显示图标的任意一行格式中加入：

```text
%plugin_content{kindleclick}
```

花括号过滤表示只显示本插件，不会混入阅读计时器等其他插件的内容。使用不带过滤条件的 `%plugin_content` 则会聚合所有已注册插件。状态或图标改变时，本插件会发送 Bookends 已支持的 `RefreshAdditionalContent` 事件，无需另装补丁。如果当前 Bookends 不认识 `%plugin_content`，请先升级 Bookends。

### Click 五个按键功能

| 操作 | 按键码 | 5.20.1 上的处理路径 |
|---|---:|---|
| 上方面键：向前翻页 | `KEY_PAGEDOWN` 109 | 原生转发到 `kindle-input-pt`，本插件补充 KOReader 映射 |
| 下方面键：向后翻页 | `KEY_PAGEUP` 104 | 原生转发到 `kindle-input-pt`，本插件补充 KOReader 映射 |
| 上侧键：亮度增加 | `KEY_BRIGHTNESSUP` 225 | 原生 `input_manager` 调用 `powerd.stepBrightnessWithUI(+1)` |
| 下侧键：亮度减少 | `KEY_BRIGHTNESSDOWN` 224 | 原生 `input_manager` 调用 `powerd.stepBrightnessWithUI(-1)` |
| 同时长按两侧键：休眠 | `KEY_POWER` 116 | Click 自身识别组合键，原生 `input_manager` / `powerd` 执行休眠 |

亮度键支持原生按下及长按重复调节。休眠只能在 Kindle 处于活跃状态时触发，Click 不能唤醒设备。上述三个非翻页动作由原生系统直接处理，**本插件不会再执行一次**，以免亮度一次跳两档或重复触发休眠。

### Kindle 5.20.1 / KPW6 说明

- 官方 Click 使用 BLE HID，硬件标识为 **VID:PID `0171:0443`**。插件通过 `/proc/bus/input/devices` 中这个真实 HID 节点判断连接，不再依赖广播名称。
- 原生系统可能把底层设备名称保存为“Amazon Fire TV Remote”，这不妨碍识别；菜单统一显示“Kindle Click”。
- `kindle-input-pt` 是常驻的原生转发节点，**它的存在不代表 Click 已连接**，插件不会用它伪造连接状态。
- 5.20.1 由原生 Bluedroid HID 后台连接列表自动重连 Click。“连接 Kindle Click”会确保蓝牙开启并做有限次状态确认；请按一下 Click 并等待数秒。若曾在原生设置中手动断开，可能仍需在原生的“蓝牙设备”页面点一次“连接”。
- 插件只添加 PageUp/PageDown 两个加法式映射，并刷新当前书籍的翻页键注册；不打开或 `EVIOCGRAB` 抢占原始 Click 节点，不重复转发事件，也无需同时启用 ExternalKeyboard。
- 原生 `input_manager` 已处理方向切换，插件会避免 KOReader 对 `kindle-input-pt` 再做一次方向交换。

### 低功耗设计

- 没有常驻轮询，没有后台守护进程，也不会阻止 Kindle 休眠。
- 状态只在启动、唤醒、菜单访问、状态栏本来就要刷新、设备热插拔或手动操作时读取。
- 菜单标题和状态栏触发的状态读取至少有 30 秒间隔，且仅在已有界面活动时执行；展开子菜单会立即刷新一次。
- 发起连接后会立即确认一次，随后仅在第 2、5、10、20 秒各确认一次；连接成功或确认结束后不再保留定时器。
- 唤醒恢复只在“睡前蓝牙是开的、唤醒后读到的却是关的”时启动；若一次开启失败，恢复阶梯最多约 26 秒，结束后不再保留定时器。
- 所有开启尝试失败后会转入**只读观察**（1、2、4、7、12 分钟各查一次状态，不再发送任何蓝牙命令）；原生栈自行恢复时图标会自动更新并重新连接 Click。
- 每次开关、唤醒、恢复步骤和状态变化只写一行文本日志，不增加轮询。
- 图标选择只读写 KOReader 设置并触发一次界面刷新，不增加定时器或字体扫描。
- 诊断信息仅在手动打开时采集，不启动扫描或监听。
- 退出 KOReader 时不会擅自关闭蓝牙；如需省电，可在菜单中手动关闭。

如果 Click 在静止阅读期间自行断开，图标会在下一次状态栏活动、唤醒或打开菜单时更新，而不是依靠高频后台查询保持实时。

### 诊断与故障排查

1. 保持 Click 在原生系统中已配对，进入 KOReader 后按一下 Click。
2. 打开 **Kindle Click → 诊断信息**。
3. 诊断会同时显示并保存到：

   ```text
   /mnt/us/koreader/kindleclick-diagnostic.txt
   ```

4. 若仍显示“已连接设备：无”、无法翻页、无法开启蓝牙，或亮度/休眠侧键无效，请提供该文件。诊断包含输入节点、相关进程、LIPC 属性、蓝牙内核模块、BT 相关 upstart 作业及其配置（`acsbtfd` / `btmanagerd` 等）、守护进程 stderr（`/tmp/*.err`）、WMT 传输层状态（`/dev/stpbt`、模块文件、`acsbtfd` 打开的 fd）、内核日志与系统日志尾部，以及插件日志 `kindleclick.log` 的尾部；但不读取或导出蓝牙 LinkKey。

**公开分享诊断文件前请先检查并遮盖蓝牙地址等隐私信息。**

### 蓝牙完全无法开启时

先试 **Kindle Click → 蓝牙无法开启？深度恢复…**：蓝牙关闭时，先按 `acsbtfd` → `btmanagerd` 的依赖顺序重启原生蓝牙作业、走一遍开启阶梯，仍未恢复则只读轮询最多 4 分钟；蓝牙已开启时**不重启服务**（重启会打断正在建立的连接），只发一次 Connect 并等待 Click 出现。全过程写入 `kindleclick.log`，必须确认后才会执行，且不会自动运行；不会改动飞行模式或 Wi-Fi。

仅支持 Kindle，不适用于 Kobo、Android 或桌面版 KOReader。根据实机闪退反馈，1.3.1 移除了“蓝牙设备管理”界面及独立一级入口，配对请使用 Kindle 原生设置；1.3.2 修复了关闭蓝牙后可能被残留开启请求重新打开、以及部分固件上连接验证误报失败的问题；1.4.0 加入唤醒恢复阶梯与持久化日志；1.5.1 加入手动深度恢复（重启原生蓝牙作业），并保证不改变飞行模式与 Wi-Fi 状态；1.5.2 按实机诊断把恢复对象确认为 `acsbtfd` / `btmanagerd`，并补充作业配置与内核日志采集；1.5.3 按 `acsbtfd` 由 `btmanagerd` 拉起的依赖关系修正重启顺序，并采集守护进程 stderr；1.5.4 记录 WMT 传输层（`/dev/stpbt`、模块、`acsbtfd` 的 fd）以便判断控制器为何无法重新初始化；1.5.5 加入失败后的只读观察窗口（最长 12 分钟），匹配实机观察到的“原生栈会自行恢复”；1.5.6 不再读取只写的 `BTflightMode`（避免 btfd 日志刷错误），并在状态日志里记录飞行模式开关值；1.5.7 区分“读不到状态”与“蓝牙关闭”（图标 `?`、菜单显示状态未知、不盲目切换）；1.6.0 试过“临时关闭飞行模式 + 等待原生恢复”，但实机日志（`wireless=0` 时 phase 1 直接成功）证明蓝牙本来就可在飞行模式打开时启用，因此 1.6.1 撤销该做法，改为“蓝牙已开启时不重启服务，只等 Click 连上”；1.7.0 加入随插件附带的三态图标字体（`fonts/kindleclick-icons.ttf`，U+E900–U+E902），首次启动自动安装并注册为 KOReader 回退字体；1.7.1 把字形放大到整字高，字体升级会自动覆盖旧文件；1.7.2 让遥控器图标保持原始比例并顺时针倾斜 20°，避免在状态栏里缩成一条竖线；1.7.3 改用 FontCreator 调整后的字体，遥控器恢复不旋转、三态图标的垂直中心与时间数字对齐，并保证重复更新不会重复注册回退字体；1.7.4 替换为你最新一版字体；1.7.5 在菜单“使用说明”后显示插件版本号（直接取自 `_meta.lua`）。蓝牙开启正常时仍是一次 `BTflightMode=0` + `BTenable=1:2`；只有开启失败后才会依次尝试复位射频后重试、以及备用模式 `BTenable=1:1`，每次开启最长约 26 秒。本版仅使用 Kindle 原生 btfd 与 HID 通道，不依赖 KHP 或其他守护进程。插件依赖 KOReader 的状态栏扩展接口（`addAdditionalFooterContent`）与 Bookends 的 `%plugin_content`，请使用较新的 KOReader 版本。仓库未附带自动化测试，当前结论来自代码审查与静态检查；深度休眠恢复仍需实机验证。完整变更见 [RELEASE_NOTES.md](RELEASE_NOTES.md)。

### 文件

```text
kindleclick.koplugin/
├── _meta.lua
├── fonts/
│   └── kindleclick-icons.ttf       # 三态图标字体（U+E900–U+E902）
├── kindleclick_backend.lua         # 原生异步开关与设备状态确认
├── kindleclick_bluetooth.lua       # btfd、设备状态、原生 Click 识别
├── kindleclick_diagnostics.lua     # 手动触发的只读诊断
├── kindleclick_icons.lua           # 三态图标、预设及自定义 Unicode 码位
├── kindleclick_log.lua             # 唤醒恢复日志（kindleclick.log）
├── main.lua                        # 菜单、状态栏、翻页映射和自动恢复
└── README.md
```


图标源文件（SVG、PNG、FontCreator 工程和导出的 TTF）放在仓库的 `assets/icon-src/`，不会打进插件安装包。
---

## English

A standalone KOReader plugin for **Kindle** only. It controls Kindle's native Bluetooth, detects the Kindle Click, adds the missing page-turn mappings, and reports connection status in the menu, KOReader's reading footer, or Bookends.

### Features

- Adds a Bluetooth switch under **Settings → Network → Kindle Click**.
- Shows the name of the currently connected Bluetooth device.
- Lets the native system restore Bluetooth and the Click connection when KOReader starts or the device wakes; automatic connection can be disabled.
- Saves only the Bluetooth state before sleep, then uses bounded asynchronous native btfd recovery and explicitly reconnects Click.
- If Bluetooth does not come back after a deep sleep, the plugin retries on its own: it gives the native stack time to wake up, resets the radio before re-enabling when needed, and falls back to the vendor's alternate enable mode. Every step is written to `kindleclick.log`.
- When the state cannot be read (`BTstate` and `currentBTOperatingMode` both fail), the footer shows `?`, the menu says “Bluetooth state unknown”, and the plugin neither reports a false “off” nor toggles blindly.
- When even the native system cannot enable Bluetooth, **Deep recovery** in the menu restarts the `acsbtfd` / `btmanagerd` jobs when the radio is off and waits up to about four minutes; when Bluetooth is already on it does **not** restart the services (that would drop the session) and only waits for the Click. The plugin never touches airplane mode or Wi-Fi.
- Provides **Connect Kindle Click**, **Refresh connection status**, and **Diagnostics** menu items.
- Long-press the parent **Kindle Click** menu item to toggle Bluetooth directly.
- Uses **one icon position for all three states**, rather than showing or hiding an icon:
  - Bluetooth off: Bluetooth-off icon by default.
  - Bluetooth on, but Kindle Click not connected: Bluetooth icon by default.
  - Kindle Click connected: remote-control icon by default.
- Allows a separate icon for each state. Presets and custom codepoints use KOReader's bundled `nerdfonts/symbols.ttf`; other Unicode symbol codepoints are also accepted.
- Provides **Toggle Bluetooth** and **Connect** actions that can be assigned in KOReader's gesture manager.
- Adds `KEY_PAGEUP` / `KEY_PAGEDOWN` page-turn mappings for touch-only Kindles without enabling the full external-keyboard text-input mode.

### Screenshots

**Menu and Bluetooth controls**

![Kindle Click menu and Bluetooth controls](screenshots/menu.png)

**Three connection states sharing one icon position**

![Three connection states sharing one icon position](screenshots/status-icons.png)

**Configuring the status display in Bookends**

![Kindle Click status displayed by Bookends](screenshots/bookends.png)

### Installation and upgrades

1. Pair the Kindle Click in Kindle's native settings first. This plugin does not provide a scanning or pairing interface.
2. When upgrading, delete the old `kindleclick.koplugin` folder before copying the complete new folder to:

   ```text
   /mnt/us/koreader/plugins/kindleclick.koplugin
   ```

3. Fully exit and restart KOReader so that the page-turn mappings and the current book's key registrations are reloaded.
4. Open the top menu and go to **Settings → Network → Kindle Click**.

### Customizing the status icons

Go to **Kindle Click → Status icons (three states)** and configure **Bluetooth off**, **Bluetooth on, Click not connected**, and **Kindle Click connected** separately.

Each state offers preset icons and a **Custom Unicode codepoint** option. For example, `U+E7B1` is Bluetooth off, `U+E7AE` is Bluetooth, and `U+EB53` is a remote control. Custom input accepts `U+EB53`, `0xEB53`, or `EB53`. A glyph missing from the selected font may appear as an empty box.

**The bundled icon font**

The plugin ships `fonts/kindleclick-icons.ttf` with one glyph per state: `U+E900` Bluetooth off, `U+E901` Bluetooth on, and `U+E902` connected. Glyphs are drawn at full em height and their vertical centres are aligned with the footer digits; the remote glyph keeps its original proportions without rotation. On first start the plugin copies it to `koreader/fonts/`, registers it as an additional KOReader UI fallback font, and asks you to restart KOReader once. After restarting, choose **Use my icons (off / on / connected)** under **Status icons (three states)**. A font update is copied over the old file automatically and asks for another restart.

Two things to know:

- KOReader's “Additional UI fallback fonts” menu only lists fonts whose name starts with Noto Sans, so this font will not appear there. If that fallback list is edited in that menu, this entry is removed and the plugin re-registers it on the next start (one more restart restores it).
- The font contains only these three glyphs; all other text keeps using your normal font.
- **Updating the plugin never registers it twice**: registration checks the exact absolute path and drops any older path ending in `kindleclick-icons.ttf`, so the fallback list always holds a single entry for this font.

**Show three-state icons in the status bar (including Bookends)** is the plugin's display switch. Turning it off removes this plugin's content from both KOReader's stock footer and Bookends.

### Displaying the status in Bookends

No changes to Bookends' source files are required. Bookends reads the content that this plugin registers with KOReader's footer extension API, even when KOReader's own status bar is disabled.

Add the following to any Bookends line where the icon should appear:

```text
%plugin_content{kindleclick}
```

The brace filter selects only this plugin, excluding content from other plugins such as reading timers. The unfiltered `%plugin_content` token aggregates content from all registered plugins. When the status or icon changes, this plugin emits the `RefreshAdditionalContent` event already supported by Bookends; no additional patch is needed. If your Bookends version does not recognize `%plugin_content`, upgrade Bookends first.

### Click button functions

| Action | Key code | Handling path on firmware 5.20.1 |
|---|---:|---|
| Upper face button: page forward | `KEY_PAGEDOWN` 109 | Forwarded by the native system through `kindle-input-pt`; this plugin adds the KOReader mapping |
| Lower face button: page back | `KEY_PAGEUP` 104 | Forwarded by the native system through `kindle-input-pt`; this plugin adds the KOReader mapping |
| Upper side button: brightness up | `KEY_BRIGHTNESSUP` 225 | Native `input_manager` calls `powerd.stepBrightnessWithUI(+1)` |
| Lower side button: brightness down | `KEY_BRIGHTNESSDOWN` 224 | Native `input_manager` calls `powerd.stepBrightnessWithUI(-1)` |
| Long-press both side buttons: sleep | `KEY_POWER` 116 | The Click detects the combination itself; native `input_manager` / `powerd` performs the sleep action |

The brightness buttons support native press-and-hold repetition. Sleep can only be triggered while the Kindle is active; the Click cannot wake the device. The three non-page-turn actions are handled directly by the native system and **are not executed again by this plugin**, preventing double brightness steps or duplicate sleep actions.

### Notes for Kindle 5.20.1 / KPW6

- The official Click uses BLE HID with **VID:PID `0171:0443`**. The plugin detects the real HID node in `/proc/bus/input/devices` rather than relying on its broadcast name.
- The native system may store the underlying device name as “Amazon Fire TV Remote.” This does not affect detection; the plugin menu consistently displays “Kindle Click.”
- `kindle-input-pt` is a persistent native pass-through device. **Its presence does not mean that a Click is connected**, and the plugin never uses it to fabricate a connected state.
- On 5.20.1, the native Bluedroid HID background-connection list reconnects the Click. **Connect Kindle Click** ensures that Bluetooth is enabled and performs a bounded series of status checks. Press the Click once and wait a few seconds. If it was manually disconnected in the native settings, you may still need to tap **Connect** once on Kindle's native **Bluetooth devices** page.
- The plugin only adds the PageUp/PageDown mappings and refreshes the current book's key registrations. It does not open or `EVIOCGRAB`-grab the raw Click device, duplicate event forwarding, or require ExternalKeyboard.
- Kindle's native `input_manager` already handles orientation changes. The plugin prevents KOReader from applying a second orientation swap to `kindle-input-pt`.

### Low-power design

- No persistent polling, no background daemon, and no interference with Kindle sleep.
- Status is read only at startup, resume, menu access, an already-occurring footer redraw, input-device hotplug, or a manual action.
- Menu-title and footer-triggered status reads are at least 30 seconds apart and run only when there is already UI activity; expanding the submenu refreshes immediately.
- After initiating a connection, status is confirmed once immediately and then only at 2, 5, 10, and 20 seconds. No timer remains after the connection succeeds or the final check finishes.
- Wake recovery runs only when Bluetooth was on before sleep and reads as off after waking. If one enable attempt fails, the recovery ladder takes at most about 26 seconds and leaves no timer behind.
- After every failed attempt the plugin switches to a **read-only watch** (checks at 1, 2, 4, 7 and 12 minutes without sending any Bluetooth command); if the native stack recovers by itself, the icon updates and the Click is reconnected.
- Every power request, resume, recovery step, and status change writes one line of text to the log; no polling is added.
- Icon selection only reads or writes KOReader settings and triggers one UI refresh; it adds no timer or font scanning.
- Diagnostics are collected only when explicitly opened and do not start scanning or listening.
- Exiting KOReader does not turn off Bluetooth without permission. Turn Bluetooth off manually when needed to save power.

If the Click disconnects while you are reading without interacting with the device, the icon updates on the next status-bar activity, resume, or menu visit rather than relying on high-frequency background queries.

### Diagnostics and troubleshooting

1. Keep the Click paired in Kindle's native settings, enter KOReader, and press the Click once.
2. Open **Kindle Click → Diagnostics**.
3. The diagnostic report is displayed and saved to:

   ```text
   /mnt/us/koreader/kindleclick-diagnostic.txt
   ```

4. If the plugin still shows “Connected device: None,” page turning does not work, Bluetooth cannot be enabled, or the brightness/sleep side buttons are unresponsive, provide this file. Diagnostics include input devices, relevant processes, LIPC properties, Bluetooth kernel modules, BT-related upstart jobs and their configs (`acsbtfd` / `btmanagerd`, …), daemon stderr (`/tmp/*.err`), WMT transport state (`/dev/stpbt`, module files, the fds held by `acsbtfd`), the tails of the kernel and system logs, and the tail of the plugin log `kindleclick.log`; they do not read or export Bluetooth LinkKeys.

**Before sharing a diagnostic report publicly, review it and redact private information such as Bluetooth addresses.**

### When Bluetooth cannot be enabled at all

Try **Kindle Click → Bluetooth won't turn on? Deep recovery…** first. When the radio is off it restarts the native Bluetooth jobs in dependency order (`acsbtfd` is started by `btmanagerd`), runs the enable ladder, and polls read-only for up to four minutes if needed. When Bluetooth is already on it does **not** restart the services (that would drop the session); it sends one Connect and waits for the Click. Everything is logged to `kindleclick.log`; it always asks for confirmation and never runs on its own, and it never changes airplane mode or Wi-Fi.

Kindle only; Kobo, Android, and desktop KOReader are not supported. Following an on-device crash report, version 1.3.1 removed the Bluetooth Device Manager interface and its separate first-level Network entry; use Kindle's native settings for pairing. Version 1.3.2 fixed a stale enable request that could turn Bluetooth back on after it had been switched off, and a false connect-verification failure on some firmware builds. Version 1.4.0 added the wake-recovery ladder and a persistent log for the “Bluetooth shows off and cannot be enabled after a long sleep” problem. Version 1.5.1 added the manual deep recovery for the case where the native system cannot enable Bluetooth either, without ever changing airplane mode or Wi-Fi. Version 1.5.2 pins the recovery targets to `acsbtfd` / `btmanagerd` based on an on-device diagnostic, and adds job-config and kernel-log capture. Version 1.5.3 fixes the restart order to match the `acsbtfd` → started by `btmanagerd` dependency and captures daemon stderr. Version 1.5.4 records the WMT transport state (`/dev/stpbt`, module files, the fds held by `acsbtfd`) to determine why the controller cannot be re-initialised. Version 1.5.5 adds the post-failure read-only watch (up to 12 minutes) to match the observed behaviour that the native stack recovers on its own. Version 1.5.6 stops reading the write-only `BTflightMode` property (which made btfd log type errors) and records the airplane-mode switch value in the status log. Version 1.5.7 distinguishes “cannot read the state” from “Bluetooth is off” (`?` icon, unknown state in the menu, no blind toggling). Version 1.6.0 tried “turn airplane mode off temporarily + wait”, but on-device logs show that phase 1 succeeds with `wireless=0`, i.e. Bluetooth can be enabled while airplane mode is on, so 1.6.1 drops that approach and instead never restarts the services while Bluetooth is already on — it just waits for the Click. Version 1.7.0 adds the bundled three-state icon font (`fonts/kindleclick-icons.ttf`, U+E900–U+E902), installed and registered as a KOReader fallback font on first start; version 1.7.1 draws the glyphs at full em height and replaces an outdated installed font automatically; version 1.7.2 keeps the remote icon's original aspect ratio and rotates it 20° clockwise so it no longer collapses into a vertical line; version 1.7.3 ships the FontCreator-tuned font, with the remote upright again, all three glyphs vertically centred on the footer digits, and duplicate-free fallback registration; version 1.7.4 replaces it with your latest revision; version 1.7.5 shows the plugin version next to the **Usage notes** menu item, read straight from `_meta.lua`. A normal enable is still one `BTflightMode=0` + `BTenable=1:2`; only after that fails does the plugin reset the radio and retry, and then try the alternate `BTenable=1:1` mode, for at most about 26 seconds per enable. This version uses only Kindle's native btfd and HID path and does not depend on KHP or any other daemon. The plugin relies on KOReader's footer extension API (`addAdditionalFooterContent`) and Bookends' `%plugin_content`, so use a reasonably recent KOReader. The repository ships no automated test suite; the current statement is based on code review and static checks, and deep-sleep recovery still requires on-device verification. See [RELEASE_NOTES.md](RELEASE_NOTES.md) for the full changelog.

### Files

```text
kindleclick.koplugin/
├── _meta.lua
├── fonts/
│   └── kindleclick-icons.ttf       # Three-state icon font (U+E900–U+E902)
├── kindleclick_backend.lua         # Native asynchronous power and device verification
├── kindleclick_bluetooth.lua       # btfd, device status, and native Click detection
├── kindleclick_diagnostics.lua     # Read-only diagnostics triggered manually
├── kindleclick_icons.lua           # Three-state icons and custom Unicode codepoints
├── kindleclick_log.lua             # Wake-recovery log (kindleclick.log)
├── main.lua                        # Menus, footer status, mappings, and recovery
└── README.md
```

Icon source files (SVG, PNG, the FontCreator project and the exported TTF) live in `assets/icon-src/` and are not part of the plugin package.
