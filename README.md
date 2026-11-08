# Xiaomi Bloatware Removal

Remove ads, telemetry, Chinese tracking components and preinstalled junk from **Xiaomi, Redmi and POCO** phones running **MIUI or HyperOS**, over ADB, with **no root and no unlocked bootloader**.

Tested on a Redmi A7 Pro 5G (HyperOS 3.0, Android 16): free RAM went from **~810 MB to ~1.43 GB** after the cleanup and a reboot.

## How it works

Packages are removed with `pm uninstall --user 0`. This uninstalls the app for your user, but the original stays on the read-only system partition. That means:

- Nothing is permanently deleted. Every change can be undone with `--restore`.
- A factory reset brings everything back.
- Removals **survive reboots**. A major OTA update may occasionally bring an app back; just re-run the script.
- If HyperOS blocks an uninstall (`Failure [-1000]`), the script **disables** the app instead. It won't run or use RAM.

Critical packages (Security Center, launcher, SystemUI, Play Services, Find Device, Xiaomi account, etc.) are on a protected list and are never touched.

## Groups

| Group | What | Default |
|---|---|---|
| **A** | Xiaomi ads (MSA), analytics, MiSight, bug reporter, App Vault, HyperOS AI services, GetApps, Facebook preinstall services, Indus store, etc. | Yes |
| **T** | Chinese payment / ID / tracking: Tencent SOTER, IFAA (Alipay), Rongcard eID, Mi Pay, `miui.daemon` usage collector | Yes |
| **B** | Preinstalled shovelware games, WPS Office, Mi Store, Glance wallpapers, preinstalled antivirus apps | Ask |
| **C** | Optional: Mi Cloud, Mi Music, FM Radio, Weather, Gemini, YouTube Music, Google TV, Google One, Meet, Android Auto, Drive, Facemoji keyboard | Ask |

See the full list with `./xiaomi-debloat.sh --list`. Packages that are not on your device are skipped automatically.

If Facemoji is your active keyboard, the script switches you to Gboard before removing it (or skips it if Gboard isn't installed).

## Setup

1. **Install ADB**
   - macOS: `brew install --cask android-platform-tools`
   - Linux: `sudo apt install adb` (or your distro's package)
   - Windows: install [platform-tools](https://developer.android.com/tools/releases/platform-tools) and run the script from Git Bash or WSL
2. **Enable USB debugging on the phone**
   - Settings → About phone → tap **OS version** (or MIUI version) 7 times
   - Settings → Additional settings → Developer options → enable **USB debugging**
3. Connect with a **data** cable, unlock the phone and tap **Allow** on the USB debugging prompt.

## Usage

```bash
git clone https://github.com/5ivatej/xiaomi-bloatware-removal.git
cd xiaomi-bloatware-removal
chmod +x xiaomi-debloat.sh

./xiaomi-debloat.sh                    # interactive: shows what's on your phone, asks per group
./xiaomi-debloat.sh --dry-run --all    # preview everything, change nothing
./xiaomi-debloat.sh --groups a,t       # just ads/telemetry + Chinese tracking
./xiaomi-debloat.sh --all --yes        # everything, no prompts
./xiaomi-debloat.sh --mem              # free RAM + top memory users
```

Reboot the phone afterwards to see the full RAM gain.

## Undo

Every run writes a log like `debloat-<serial>-<timestamp>.log`.

```bash
./xiaomi-debloat.sh --restore debloat-XXXX-20261108-201500.log   # undo one run
./xiaomi-debloat.sh --restore                                     # restore every package the script knows
```

Or restore a single app manually:

```bash
adb shell cmd package install-existing <package.name>
adb shell pm enable <package.name>        # for apps that were disabled
```

## Notes

- `com.xiaomi.xmsf` (Xiaomi push service) is intentionally **not** removed. It phones home, but HyperOS relies on it for Find Device and some system notifications.
- `com.miui.securitycenter` is protected. Removing it can bootloop the phone.
- Group C includes Mi Cloud. Don't remove it if you back up to Mi Cloud.
- Use at your own risk. The method is reversible, but every ROM is different. Run `--dry-run` first.

## Contributing

Found bloat on your model that isn't listed, or a package that broke something? Open an issue or PR with your device model, ROM version and the package name.

## License

MIT
