# Kindle Click 蓝牙 v1.7.18 / Kindle Click Bluetooth v1.7.18

## 中文

### 本次更新

- ZenOS 主屏小组件的状态文字改为「蓝牙关闭 / 翻页器断开 / 翻页器连通」，点击小组件可打开 Kindle Click 快捷菜单。
- 插件自带 `kindleclick.svg` 胶囊图标，可在 ZenOS 的图标选择器里选择；移除多余的深色图标。
- 检查更新修复：改用系统 LuaSocket，修正状态码解析，并在 jsDelivr 镜像不可用时自动切换。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。

---

## English

### Changes

- The ZenOS Home widget now shows "Bluetooth off / page turner disconnected / page turner connected"; tapping it opens the Kindle Click quick menu.
- The plugin ships a `kindleclick.svg` capsule icon that can be picked in ZenOS's icon picker; the extra dark icon was removed.
- Update check fixed: it now uses the system LuaSocket, parses the status code correctly, and falls back across jsDelivr mirrors.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader.
