# Architecture and behavior

This document explains how the plugin talks to Kindle's Bluetooth stack and why the recovery paths are deliberately conservative. For user-facing steps, see the [README](../README.md).

## Scope

The plugin is Kindle-only. It does not pair devices, does not open the Click's evdev node, and does not replace Kindle's Bluetooth daemon. Everything goes through the native `com.lab126.btfd` LIPC service and `/proc/bus/input/devices`.

## Detecting the Click

- The official Click is a BLE HID device with **VID:PID `0171:0443`**.
- The plugin scans `/proc/bus/input/devices` for that ID. This is the reliable signal; broadcast names are not.
- Kindle may store the underlying name as “Amazon Fire TV Remote”. The menu always shows “Kindle Click”.
- `kindle-input-pt` is a permanent native pass-through node. **Its presence does not mean the Click is connected**, so the plugin never treats it as a connection indicator.
- Bluetooth state comes from `BTstate` (with `currentBTOperatingMode` as fallback). When both fail, the state is *unknown*: the footer shows `?` and the plugin refuses to toggle blindly.

## Sleep and wake

The plugin treats the native stack as the owner of the radio; it only nudges it.

1. **Before sleep** the plugin records whether Bluetooth was enabled. It does not turn Bluetooth off and does not close connections.
2. **On resume**, if Bluetooth was on before sleep:
   - wait 15 seconds for the native stack to settle, then read the state once;
   - if Bluetooth is already back, only reconnect the Click (one `Connect`);
   - if it is still off, send **one** enable request at about 45 seconds (`BTflightMode=0` + `BTenable=1:2`) and then go read-only.
3. **Read-only watch**: checks at 1, 3, 6, 10, 15, 20, 25 and 30 minutes. No Bluetooth commands are sent. If the native stack recovers by itself, the icon updates and the Click is reconnected.
4. When the watch ends, the plugin stops. It does not retry forever.

### Why no automatic service restart

On-device tests showed that restarting only `acsbtfd` / `btmanagerd`:

- resets userspace and produces fresh PIDs and empty stderr;
- does **not** rebuild the WMT transport (`/dev/stpbt` stays unheld, `wmt_cdev_bt` reference count stays 0);
- can delay the native stack's own recovery, which happens minutes after leaving KOReader.

The plugin therefore never restarts services on its own. When Bluetooth is still off about 45 seconds after wake and `wmt_cdev_bt` has a reference count of 0, it offers a **manual** transport rebuild instead.

### Manual transport rebuild (experimental)

The menu item performs:

1. stop `acsbtfd`, `btmanagerd`, `wmt_service`;
2. confirm the `wmt_cdev_bt` reference count drops to 0;
3. start `wmt_service`, then `btmanagerd`, then `acsbtfd` (reverse order);
4. wait for the stack, then send one enable request.

It does not write `BTflightMode`, `BTenable`, or `wirelessEnable`, so airplane mode and Wi-Fi preferences are left alone. Wi-Fi shares the WMT transport and may drop briefly. After a restart of `wmt_service`, the kernel reports `Driver 'mtk_wmt' is already registered`, so this only reopens the STP channel — it is a recovery step, not a permanent fix. In the 2026-11-15 test logs, all four wedges recovered in about 35–40 seconds and the Click reconnected automatically.

## Click buttons

| Action | Key code | Handled by |
|---|---:|---|
| Upper face button: page forward | `KEY_PAGEDOWN` 109 | Native forwards to `kindle-input-pt`; plugin adds the KOReader mapping |
| Lower face button: page back | `KEY_PAGEUP` 104 | Native forwards to `kindle-input-pt`; plugin adds the KOReader mapping |
| Upper side button: brightness up | `KEY_BRIGHTNESSUP` 225 | Native `input_manager` calls `powerd.stepBrightnessWithUI(+1)` |
| Lower side button: brightness down | `KEY_BRIGHTNESSDOWN` 224 | Native `input_manager` calls `powerd.stepBrightnessWithUI(-1)` |
| Long-press both side buttons: sleep | `KEY_POWER` 116 | Click detects the combination; native `input_manager` / `powerd` sleeps |

The plugin never re-executes the brightness or sleep actions, to avoid double steps. Brightness keys are delivered as `action` entries in Kindle's native `input_manager` configuration, not as events forwarded to KOReader, so KOReader's own brightness UI does not follow them.

## Status output

### KOReader footer

`main.lua` registers an additional footer content function via `footer:addAdditionalFooterContent`. The function returns one glyph based on the current state, so the three states share a single slot.

### Icon font

- Bundled font: `fonts/kindleclick-icons.ttf`, with `U+F0000` (off), `U+F0001` (on), `U+F0002` (connected).
- On first start the font is copied to KOReader's `fonts/` directory and registered in `font_ui_fallbacks`.
- KOReader reads that setting at startup, so a restart is required after the first install or a font update.
- The three codepoints sit in the Supplementary Private Use Area so common UI fonts (including Nerd Fonts' `symbols.ttf`) do not claim them first.
- The plugin also promotes its font to the front of `Font.fallbacks` at runtime and clears cached fallback chains, so the glyphs win over later-registered fonts.

### Bookends

Bookends listens to KOReader's `RefreshAdditionalContent` event. Add `%plugin_content{kindleclick}` to any Bookends line; the brace filter limits output to this plugin.

### ZenOS

- Registers a Home widget through the public `__ZENOS_REGISTER_HOME_ITEM` hook (label “Kindle Click”, size `s`).
- The widget text is one of: `状态未知`, `蓝牙关闭`, `翻页器断开`, `翻页器连通`.
- Tapping it opens a ButtonDialog quick menu: toggle Bluetooth, connect Click, rebuild transport, check for updates, diagnostics.
- The plugin copies `icons/kindleclick.svg` into KOReader's `icons/` directory so it can be selected for the Controls button.
- ZenOS's active-state dark background only applies to its built-in buttons; custom buttons cannot become active, and their labels are static configuration values.

## Update check

- Manual only: **Kindle Click → Check for updates (vX.Y.Z)**.
- Fetches the remote `_meta.lua` from jsDelivr/raw mirrors over LuaSocket, parses `version = "..."`, and compares numerically.
- Downloads the file list from `manifest.txt` (falling back to a bundled list) to `<file>.new`, then renames them into place. A restart applies the update.
- Cache-busting query strings are appended so a fresh push is visible without waiting for the CDN cache.
- Manifest lines are validated as plain relative paths. The check splits each path on `/` and rejects any `.` or `..` segment, absolute paths, backslashes, empty segments (`//`), a trailing slash, and encoded characters; one bad line rejects the **whole** manifest and falls back to the bundled file list. `_meta.lua` and `main.lua` must be present, and the entry count and per-file size are capped. The same check runs again before every file write.
- Nested directories such as `l10n/zh_CN/LC_MESSAGES` are created level by level before the downloaded file is written.
- Transport is HTTPS, but LuaSocket does not verify the peer certificate on Kindle (there is no CA store to point it at), so the update source is trusted by design. The path validation limits a tampered manifest to writing inside the plugin directory.

## Firmware notes

- **5.20.2 vs 5.20.1 (KPW6)**: `btd`, `wmt_service`, `wmt_cdev_bt.ko`, and `btmanagerd` are effectively unchanged; `acsbtfd` grows by ~24 KB (IPC refactor plus a “keep Bluetooth on in flight mode” preference) and `powerd` gains hibernation checks. The Bluetooth transport path is unchanged, so upgrading does not fix the deep-sleep wedge.
- **KS3 vs PW6 (both 5.20.1)**: the Bluetooth userspace binaries (`acsbtfd`, `btd`, `btmanagerd`, `input_manager`, upstart configs) are byte-identical; `powerd`, `wmt_service`, and `libbluetooth.so` contain the same strings. The difference is the platform layer: PW6 uses kernel 5.15 with MT8110 (`soc2_1` firmware), KS3 uses kernel 6.6 with MT8171/MT6631 (`soc2_2` firmware). The wedge therefore lives in the MT8110 WMT transport/power domain, not in the plugin or the application layer.
