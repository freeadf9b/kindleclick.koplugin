# Troubleshooting and diagnostics

## Quick checks

1. Pair the Click in Kindle's native Bluetooth settings and confirm it works there (page turns should advance a native book).
2. In KOReader, open **Kindle Click → Diagnostics** and check that **Connected device** is not empty.
3. Press a Click page button. If pages turn natively but not in KOReader, restart KOReader once so the current book reloads its key registrations.
4. Make sure the plugin is the only thing handling Click keys (do not enable ExternalKeyboard).

## Collecting a diagnostic report

1. Keep the Click paired in Kindle's native settings, enter KOReader, and press the Click once.
2. Open **Kindle Click → Diagnostics**.
3. The report is shown and saved to:

   ```text
   /mnt/us/koreader/kindleclick-diagnostic.txt
   ```

The report includes input devices, relevant processes, LIPC properties, Bluetooth kernel modules, BT-related upstart jobs and their configs (`acsbtfd`, `btmanagerd`, …), daemon stderr (`/tmp/*.err`), WMT transport state (`/dev/stpbt`, module files, the fds held by `acsbtfd`), kernel/system log tails, and the tail of `kindleclick.log`. It does not read or export Bluetooth link keys.

**Before sharing the report publicly, review it and redact Bluetooth addresses or other private data.**

## Bluetooth cannot be enabled at all

The native Bluetooth stack occasionally wedges after a long sleep: `BTstate` reads 0, the LIPC writes are accepted, but nobody holds `/dev/stpbt`, so the requests never reach the controller.

What to try, in order:

1. **Wake and wait.** The plugin sends at most one enable request at about 45 seconds and then watches read-only for up to 30 minutes. The native stack often recovers by itself.
2. **Close the cover for a minute.** A short sleep usually reloads the WMT firmware and clears the wedge.
3. **Kindle Click → Rebuild Bluetooth transport (experimental).** A confirmation dialog appears first. It stops `acsbtfd`, `btmanagerd`, and `wmt_service`, confirms the `wmt_cdev_bt` reference count is 0, then restarts them in reverse order. Wi-Fi shares the WMT transport and may drop briefly; in the worst case a device restart is required. It never changes airplane mode or the Wi-Fi switch.
4. **Restart the Kindle** if the rebuild fails.

The plugin deliberately does **not** restart services automatically: tests showed that restarting only `acsbtfd` / `btmanagerd` resets userspace without rebuilding the transport, and can delay the native recovery.

## Click connects but page turns do not work

- Restart KOReader after installing or upgrading; key registrations are loaded per book.
- Check **Diagnostics → Connected device**. If empty, the Click is not connected — press a Click button and wait a few seconds.
- Make sure another plugin (for example ExternalKeyboard or a page-turner plugin) is not claiming the same input node.
- The plugin only adds PageUp/PageDown mappings; it does not grab the raw device or forward duplicates.

## Check for updates fails

- The check needs an existing network connection; it never turns Wi-Fi on by itself.
- It tries jsDelivr mirrors first, then raw GitHub mirrors. A failure is logged as `[update] mirror failed: <url> -> <err>` in `kindleclick.log`, followed by `[update] check failed: <err>`.
- If every mirror is blocked on your network, download the new folder manually and replace the plugin directory.
- The remote version comes from `_meta.lua`. If a new release exists but the check says up to date, wait for the CDN cache to expire or check again later.

## Logs

| File | Purpose |
|---|---|
| `/mnt/us/koreader/kindleclick.log` | Plugin events (wake recovery, jobs, updates, icons) |
| `/mnt/us/koreader/kindleclick-diagnostic.txt` | Snapshot produced by **Diagnostics** |

Both are regenerated as needed. Deleting `kindleclick.log` while KOReader is running is safe; delete `kindleclick.log.1` too if you want a clean slate. `crash.log` belongs to KOReader and can also be removed when KOReader is closed.

## Known limitations

- No scanning or pairing UI; pair in Kindle's native settings.
- Brightness side buttons are handled by Kindle's native system; KOReader's brightness widget does not follow them.
- ZenOS Controls buttons have static labels and cannot become “active”; use the Home widget's `翻页器连通 / 翻页器断开` text instead.
- The plugin reads Click status on demand rather than polling continuously; while reading without interacting, the icon may lag until the next footer activity, resume, or menu visit.

## Reporting an issue

Please include:

1. `kindleclick-diagnostic.txt` (redacted as needed).
2. The tail of `kindleclick.log` covering the failed wake or action.
3. Kindle model, firmware version, and whether the Click works in the native system.
