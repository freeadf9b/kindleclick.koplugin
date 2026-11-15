# Kindle Click 蓝牙 v1.7.18 / Kindle Click Bluetooth v1.7.18

## 中文

### 本次更新

- 新增 ZenOS 主屏「Kindle Click」小组件：显示蓝牙关闭 / 翻页器断开 / 翻页器连通三种状态，点击组件会打开快捷菜单（开关蓝牙、连接、重建传输层、检查更新、诊断）。组件默认关闭，到 **Zen Settings → Home → Widgets** 打开即可；未安装 ZenOS 时自动跳过。
- ZenOS Controls 的按钮图标：插件启动时把 `kindleclick.svg` 复制到 KOReader 的 `icons/`，在按钮图标选择器里选 `kindleclick` 即可。ZenOS 的已激活黑底只作用于内置按钮，自定义按钮无法随 Click 状态变黑底，按钮文字也不能动态变化。
- 连接成功提示：点「连接 Kindle Click」或唤醒后自动重连成功时，会弹出「Kindle Click 已连接」。
- 检查更新修复：不再使用会抛异常的 Turbo HTTP 客户端，改为 LuaSocket 直连；下载源改为 5 个 jsDelivr 镜像 + 3 个 raw 镜像依次回退，失败时日志会记录每个镜像的具体错误，不再只显示 `request_failed`。
- 1.7.16 的「检查更新（带版本号）」、菜单回到 **设置 → 网络**、传输层重建与休眠期不读状态等改动保持不变。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。

---

## English

### Changes

- Adds a **Kindle Click** Home widget for ZenOS that shows one of three states: Bluetooth off, page turner disconnected, or page turner connected. Tapping it opens a quick menu (toggle Bluetooth, connect, rebuild the transport, check for updates, diagnostics). It starts disabled; enable it under **Zen Settings → Home → Widgets**. Plugins without ZenOS skip the registration automatically.
- ZenOS Controls button icon: at startup the plugin copies `kindleclick.svg` into KOReader's `icons/`, so `kindleclick` is directly selectable in the button icon picker. ZenOS's active-state dark background only applies to its built-in buttons; custom buttons cannot turn dark when the Click connects, and their label cannot change dynamically.
- A "Kindle Click connected" message now appears after a manual connect or a successful automatic reconnect after wake.
- Update check fixed: it no longer uses the Turbo HTTP client that threw on some Kindle builds and now connects through LuaSocket; downloads fall back across five jsDelivr mirrors plus three raw mirrors, logging the concrete error per mirror instead of just `request_failed`.
- Everything from 1.7.16 is unchanged: the manual **Check for updates** entry with the current version, the menu under **Settings → Network**, the transport rebuild, and no Bluetooth reads while suspended.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader.
