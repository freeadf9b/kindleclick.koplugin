# Kindle Click 蓝牙 v1.7.17 / Kindle Click Bluetooth v1.7.17

## 中文

### 本次更新

- 新增 ZenOS 主屏「Kindle Click」小组件：显示蓝牙关闭 / 蓝牙已开启 / 翻页器已连接三种状态，点击组件会打开快捷菜单（开关蓝牙、连接、重建传输层、检查更新、诊断）。组件默认关闭，到 **Zen Settings → Home → Widgets** 打开即可；未安装 ZenOS 时自动跳过。
- 1.7.16 的「检查更新（带版本号）」、菜单回到 **设置 → 网络**、传输层重建与休眠期不读状态等改动保持不变。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。

---

## English

### Changes

- Adds a **Kindle Click** Home widget for ZenOS that shows one of three states: Bluetooth off, Bluetooth on, or page turner connected. Tapping it opens a quick menu (toggle Bluetooth, connect, rebuild the transport, check for updates, diagnostics). It starts disabled; enable it under **Zen Settings → Home → Widgets**. Plugins without ZenOS skip the registration automatically.
- Everything from 1.7.16 is unchanged: the manual **Check for updates** entry with the current version, the menu under **Settings → Network**, the transport rebuild, and no Bluetooth reads while suspended.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader.
