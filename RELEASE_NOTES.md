# Kindle Click 蓝牙 v1.7.21 / Kindle Click Bluetooth v1.7.21

## 中文

### 本次更新

- 修复菜单复选框与实际蓝牙状态不同步的问题：分类条目不再显示勾选，开关项改为显示「开启蓝牙 / 关闭蓝牙」。
- 界面跟随 KOReader 语言：中文界面显示中文，英文界面显示英文；插件更名为「Kindle蓝牙和翻页器」（英文界面：Bluetooth and Kindle Click Controller）。
- 内置更新更稳妥：更新清单的路径会严格校验，拒绝任何越出插件目录的条目，并限制条目数量与单个文件大小。
- 修复从旧版本升级时无法创建 `l10n/` 子目录、导致内置更新失败的问题。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹（或在菜单里使用「检查更新」）；
2. 重启 KOReader。

---

## English

### Changes

- Fixed the menu checkbox getting out of sync with the real Bluetooth state: the category entry no longer shows a tick, and the switch item now reads "Turn Bluetooth on / Turn Bluetooth off".
- The UI now follows KOReader's language: Chinese in a Chinese UI, English otherwise. The plugin is now named "Bluetooth and Kindle Click Controller" (Chinese UI: Kindle蓝牙和翻页器).
- Hardened the built-in updater: manifest paths are validated and anything escaping the plugin directory is rejected, with limits on entry count and file size.
- Fixed in-app updates failing from older versions because the `l10n/` subdirectory could not be created.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder (or use "Check for updates" in the menu);
2. restart KOReader.
