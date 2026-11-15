# Kindle Click 蓝牙 v1.7.16 / Kindle Click Bluetooth v1.7.16

## 中文

### 本次更新

- 新增手动「检查更新（带当前版本号）」：联网后点击检查，发现新版本可下载替换，重启 KOReader 生效。
- 菜单入口回到 **设置 → 网络 → Kindle Click**，并移除「使用说明」菜单项。
- 「重建蓝牙传输层（实验）」在多次真实断联中验证可用，约 40 秒恢复蓝牙并自动重连 Click。
- 修正重建日志把 `start/running`、`stop/waiting` 误报为失败的问题。
- 休眠期间不再读取蓝牙状态，避免挂起/唤醒过渡中的多余 LIPC 调用。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。

---

## English

### Changes

- Adds a manual **Check for updates** entry that shows the current version: tap it while online, and a new version can be downloaded and installed; restart KOReader afterwards.
- The menu entry is back under **Settings → Network → Kindle Click**, and the **Usage notes** item has been removed.
- **Rebuild Bluetooth transport (experimental)** is now verified across repeated real disconnects: it restores Bluetooth in about 40 seconds and reconnects the Click automatically.
- Rebuild logging no longer reports `start/running` / `stop/waiting` as failures.
- Bluetooth status is no longer read while the device is suspended, avoiding extra LIPC calls around suspend and resume.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader.
