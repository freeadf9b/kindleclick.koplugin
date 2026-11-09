# Kindle Click 蓝牙 v1.7.7 / Kindle Click Bluetooth v1.7.7

## 中文

### 本次更新

- 删除菜单中的“深度恢复”和“重启蓝牙服务（实验）”两项：自动恢复流程已经覆盖同样的“一次请求 + 只读等待”，而重启作业从未重建 WMT 传输层，只会打断连接；菜单只保留“诊断信息”；
- 唤醒时先停止睡前遗留的只读观察，并立即刷新状态，避免唤醒瞬间短暂显示旧的“蓝牙关闭”图标；
- 唤醒后若原生栈已经自行恢复蓝牙，取消待执行的恢复尝试，只重连一次 Click，避免重复 Connect；
- 其余行为与 1.7.6 相同：只发一次 `BTflightMode=0 + BTenable=1:2`，随后最多 30 分钟只读等待，不自动重试、不重启服务。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 重启 KOReader。字体未变化，不会提示重启字体。

### 验证状态

- 已用 2026-11-09 21:53 的两小时休眠诊断验证：唤醒后原生栈自行把蓝牙打开（`BTstate=1`），插件没有发送开启请求，只重连 Click；
- 菜单精简与唤醒去重是本次的静态修改，**未实机验证**；
- 安装包逐文件 SHA256 与插件目录一致。

### 升级方法

1. 先在 Kindle 原生系统中完成 Kindle Click 配对。
2. 删除旧的 `kindleclick.koplugin` 文件夹。
3. 解压安装包，将新的 `kindleclick.koplugin` 文件夹复制到 `/mnt/us/koreader/plugins/`。
4. 完全退出并重新启动 KOReader。
5. 建议保持“启动 KOReader 时自动连接”开启。

---

## English

### Changes

- Removed **Deep recovery** and **Restart Bluetooth services (experimental)** from the menu: the automatic recovery path already does the same “one request + read-only wait”, while restarting the jobs never rebuilt the WMT transport and only interrupted connections; the menu now keeps **Diagnostics** only;
- on resume, the plugin stops any passive watch left over from before the sleep and refreshes the state immediately, so the footer no longer briefly shows the old “off” icon;
- if the native stack has already brought Bluetooth back during resume, the pending recovery attempt is cancelled and Click is reconnected once, avoiding a duplicate Connect;
- everything else matches 1.7.6: one `BTflightMode=0 + BTenable=1:2` request, then read-only waiting for up to 30 minutes, with no automatic retry and no service restarts.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. restart KOReader. The font is unchanged, so there is no font-restart prompt.

### Verification status

- Verified with the two-hour sleep diagnostic from 2026-11-09 21:53: the native stack restored Bluetooth by itself after wake (`BTstate=1`), and the plugin sent no enable request — it only reconnected Click;
- the menu cleanup and resume de-duplication are static changes in this release and **have not been verified on a device**;
- every packaged file matches the plugin directory by SHA256.

### How to upgrade

1. Pair the Kindle Click in Kindle's native settings first.
2. Delete the old `kindleclick.koplugin` folder.
3. Extract the package and copy the new `kindleclick.koplugin` folder to `/mnt/us/koreader/plugins/`.
4. Fully exit and restart KOReader.
5. Keep “connect automatically when KOReader starts” enabled.
