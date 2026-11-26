# Kindle Click 蓝牙 v1.7.20 / Kindle Click Bluetooth v1.7.20

## 中文

### 本次更新

- 连接验证窗口从 20 秒延长到 40 秒：唤醒后原生栈较慢时不再提前判失败，减少无意义的重复 Connect。
- 图标字体仍放在 `fonts/` 目录，但改用 `.kfont` 扩展名，crengine 不再把它当作文档字体扫描；旧的 `.ttf` 副本（包括 1.7.20 放在 KOReader 根目录的那份）会自动删除。
- 日志降噪：状态只记录实际变化，字体信息每个进程只记一次；排查时更容易看到蓝牙事件。
- 快捷菜单去掉已弃用的标题控件。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader（字体路径已变更，需要重启一次生效）。

---

## English

### Changes

- Connection verification now waits up to 40 seconds instead of 20, so a slow native stack after wake is not reported as a failure and fewer duplicate Connect requests are sent.
- The icon font now stays in `fonts/` but uses a `.kfont` extension, so crengine no longer scans it as a document font; the old `.ttf` copies (including the one 1.7.20 placed in KOReader's root) are removed automatically.
- Quieter log: state lines are written only on real transitions, and font information is recorded once per process.
- The quick menu no longer uses the deprecated title widget.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader (the font path changed, so one restart is required).
