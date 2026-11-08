# Kindle Click 蓝牙 v1.7.5 / Kindle Click Bluetooth v1.7.5

## 中文

### 本次更新

- 菜单里的 **使用说明** 后面现在显示插件版本号（例如“使用说明 v1.7.5”）。版本号直接从 `_meta.lua` 读取，不会与插件自身版本脱节；
- 仓库整理：图标源文件（SVG、PNG、FontCreator 工程和导出的 TTF）统一移到 `assets/icon-src/`，插件目录与安装包内容不变。

### 升级

1. 退出 KOReader，覆盖 `plugins/kindleclick.koplugin` 文件夹；
2. 启动 KOReader 即可，无需额外操作（字体未变化，不会提示重启）。

### 验证状态

- 插件侧只做了结构静态检查，**未实机运行**；
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

- The **Usage notes** menu item now shows the plugin version (for example “Usage notes v1.7.5”). The value is read from `_meta.lua`, so it cannot drift from the plugin metadata;
- repository tidy-up: icon sources (SVG, PNG, the FontCreator project and the exported TTF) moved to `assets/icon-src/`; the plugin folder and package contents are unchanged.

### Upgrade

1. Exit KOReader and replace the `plugins/kindleclick.koplugin` folder;
2. start KOReader; nothing else is needed (the font is unchanged, so no restart prompt).

### Verification status

- The plugin side passed structural static checks only and **has not run on a device**;
- the package's per-file SHA256 matches the plugin directory.

### Upgrade instructions

1. Pair the Kindle Click in Kindle's native settings first.
2. Delete the old `kindleclick.koplugin` folder.
3. Extract the package and copy the new `kindleclick.koplugin` folder to `/mnt/us/koreader/plugins/`.
4. Fully exit and restart KOReader.
5. Keep **Automatically connect when KOReader starts** enabled for the recovery test.
