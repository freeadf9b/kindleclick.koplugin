# Kindle Click 蓝牙 v1.7.19 / Kindle Click Bluetooth v1.7.19

## 中文

### 本次更新

- README 重写：英文在前、中文在后，首页只保留功能介绍、安装、状态显示、兼容性与限制；实现原理、固件差异、故障排查移到 `docs/`。
- 首页重点补充「系统蓝牙假死救回」：长时间休眠后原生蓝牙假死时，可一键重建蓝牙传输层，约 40 秒恢复连接。
- 本次不包含功能代码改动，1.7.18 的连接、ZenOS 小组件、检查更新等行为保持不变。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。

---

## English

### Changes

- README rewritten: English first, Chinese second, limited to features, installation, status display, and compatibility; architecture, firmware notes, and troubleshooting moved under `docs/`.
- The homepage now highlights the **frozen Bluetooth stack rescue**: when the native stack wedges after a long sleep, one tap rebuilds the transport and restores the Click in about 40 seconds.
- No functional code changes; connection handling, the ZenOS widget, and the update check are unchanged from 1.7.18.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader.
