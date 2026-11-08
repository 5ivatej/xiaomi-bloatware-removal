#!/usr/bin/env bash
# xiaomi-debloat.sh — remove bloatware, ads and telemetry from Xiaomi / Redmi / POCO
# phones (MIUI & HyperOS) over ADB. No root required.
#
# Packages are removed with `pm uninstall --user 0`, which hides them for the main
# user only. The originals stay on the read-only system partition, so:
#   * anything can be restored with:   ./xiaomi-debloat.sh --restore
#   * a factory reset brings everything back
#
# Usage:
#   ./xiaomi-debloat.sh                     interactive (asks per group)
#   ./xiaomi-debloat.sh --groups a,t        remove only groups A and T
#   ./xiaomi-debloat.sh --all --yes         remove every group without prompting
#   ./xiaomi-debloat.sh --dry-run --all     show what would be removed
#   ./xiaomi-debloat.sh --list              print all groups and packages
#   ./xiaomi-debloat.sh --restore [logfile] reinstall packages (from a log, or all known)
#   ./xiaomi-debloat.sh --mem               show free RAM and top processes

set -uo pipefail

# ----------------------------------------------------------------------------
# Package groups
# ----------------------------------------------------------------------------

# A — Xiaomi ads, telemetry and system junk (safe for everyone)
GROUP_A=(
  com.miui.msa.global                       # MIUI System Ads (MSA)
  com.miui.analytics                        # Xiaomi analytics / telemetry
  com.miui.misightservice                   # MiSight diagnostics telemetry
  com.miui.bugreport                        # Bug reporter
  com.miui.miservice                        # Services & feedback
  com.mi.globalminusscreen                  # App Vault (swipe-left screen)
  com.xiaomi.aicr                           # HyperOS AI cognition services
  com.xiaomi.mipicks                        # GetApps store
  com.xiaomi.discover                       # System app updater / promo
  com.indus.appstore                        # Indus app store (India)
  com.facebook.appmanager                   # Facebook preinstall updater
  com.facebook.services                     # Facebook services
  com.facebook.system                       # Facebook installer
  com.miui.yellowpage                       # Yellow pages
  com.xiaomi.glgm                           # Games service
  com.mi.appfinder                          # App finder
  com.xiaomi.barrage                        # Notification "barrage" overlay
  com.miui.thirdappassistant                # Third-party app assistant
  com.microsoftsdk.crossdeviceservicebroker # Microsoft cross-device broker
  com.android.egg                           # Android easter egg
  com.miui.hybrid                           # Quick apps (older MIUI)
  com.miui.hybrid.accessory                 # Quick apps accessory
  com.miui.videoplayer                      # Mi Video (older MIUI)
  com.mi.global.bbs                         # Mi Community
  com.miui.contentcatcher                   # Content catcher
  com.miui.personalassistant                # App Vault (older MIUI)
  com.mi.android.globalminusscreen          # App Vault (older MIUI)
  com.miui.newhome                          # Feed (China ROMs)
  com.miui.systemAdSolution                 # System ad solution (China ROMs)
)

# T — Chinese payment / ID / tracking components (useless outside China)
GROUP_T=(
  com.tencent.soter.soterserver             # Tencent SOTER (WeChat biometric pay)
  org.ifaa.aidl.manager                     # IFAA (Alipay biometric pay)
  com.rongcard.eid                          # Chinese digital ID
  com.xiaomi.payment                        # Mi Pay
  com.miui.daemon                           # Background usage-stats collector
  com.miui.audiomonitor                     # Audio monitor
)

# B — Preinstalled shovelware games, promos and redundant apps
GROUP_B=(
  com.block.juggle
  com.block.puzzle.game.hippo.mi
  com.jewelsblast.ivygames.Adventure.free
  com.logame.eliminateintruder3d
  com.mintgames.triplecrush.tile.fun
  com.mintgames.wordtrip
  com.nf.snake
  com.oakever.tiletrip
  com.ordinaryjoy.woodblast
  com.soulcompany.bubbleshooter.relaxing
  com.sukhavati.gotoplaying.bubble.BubbleShooter.mint
  com.sukhavati.pvp.carrom
  com.vitastudio.mahjong
  com.uniqlo.in.catalogue
  cn.wps.moffice_eng                        # WPS Office
  cn.wps.xiaomi.abroad.lite                 # WPS Office lite
  com.mi.global.shop                        # Mi Store
  com.miui.android.fashiongallery           # Glance / lockscreen wallpaper carousel
  com.bitdefender.antivirus                 # Preinstalled antivirus
  com.symantec.mobilesecurity               # Preinstalled antivirus
  com.netflix.partner.activation            # Netflix partner stub
  com.amazon.appmanager                     # Amazon preinstall manager
)

# C — Optional Xiaomi & Google apps (remove only if you don't use them)
GROUP_C=(
  com.miui.cloudservice                     # Mi Cloud
  com.miui.cloudbackup                      # Mi Cloud backup
  com.miui.micloudsync                      # Mi Cloud sync
  com.miui.player                           # Mi Music
  com.miui.fm                               # FM Radio
  com.miui.fmservice                        # FM Radio service
  com.miui.weather2                         # Weather
  com.google.android.apps.bard              # Gemini
  com.google.android.apps.youtube.music     # YouTube Music
  com.google.android.videos                 # Google TV
  com.google.android.apps.subscriptions.red # Google One
  com.google.android.apps.tachyon           # Google Meet
  com.google.android.projection.gearhead    # Android Auto
  com.google.android.apps.docs              # Google Drive
  com.preff.kb.xm                           # Facemoji keyboard (Gboard is set first)
)

# Never touched, even if passed in a custom list — removing these can bootloop
# or break core functionality.
PROTECTED=(
  android com.android.systemui com.android.settings com.android.phone
  com.android.providers.settings com.android.providers.telephony
  com.miui.securitycenter com.miui.securitycore com.miui.home com.miui.system
  com.miui.rom com.miui.core com.lbe.security.miui com.xiaomi.account
  com.xiaomi.finddevice com.google.android.gms com.google.android.gsf
  com.android.vending com.miui.powerkeeper com.android.htmlviewer
  com.miui.guardprovider com.android.thememanager miui.systemui.plugin
  com.google.android.inputmethod.latin com.google.android.webview
)

GBOARD_IME="com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
c_red=$'\033[31m'; c_grn=$'\033[32m'; c_ylw=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
[ -t 1 ] || { c_red=; c_grn=; c_ylw=; c_dim=; c_off=; }

die()  { echo "${c_red}error:${c_off} $*" >&2; exit 1; }
info() { echo "${c_dim}$*${c_off}"; }

group_desc() {
  case $1 in
    A) echo "Xiaomi ads, telemetry & system junk (recommended)";;
    T) echo "Chinese payment / ID / tracking components (recommended outside China)";;
    B) echo "Preinstalled games, promos & duplicate antivirus apps";;
    C) echo "Optional apps: Mi Cloud, Mi Music, FM, Weather, Google extras, Facemoji keyboard";;
  esac
}

group_pkgs() { eval "printf '%s\n' \"\${GROUP_$1[@]}\""; }

is_protected() { local p; for p in "${PROTECTED[@]}"; do [ "$p" = "$1" ] && return 0; done; return 1; }

check_device() {
  command -v adb >/dev/null || die "adb not found. Install it:
  macOS:  brew install --cask android-platform-tools
  Linux:  sudo apt install adb   (or your distro's equivalent)
  Windows: use WSL/Git Bash with platform-tools on PATH"

  local state
  state=$(adb get-state 2>&1 || true)
  case $state in
    device) ;;
    *unauthorized*) die "Device unauthorized — unlock the phone and tap 'Allow' on the USB debugging prompt.";;
    *) die "No device found. Enable USB debugging (Settings > About phone > tap OS version 7x,
  then Additional settings > Developer options > USB debugging) and connect with a data cable.";;
  esac

  local brand model os
  brand=$(adb shell getprop ro.product.brand | tr -d '\r')
  model=$(adb shell getprop ro.product.model | tr -d '\r')
  os=$(adb shell getprop ro.mi.os.version.name | tr -d '\r')
  [ -z "$os" ] && os="MIUI $(adb shell getprop ro.miui.ui.version.name | tr -d '\r')"
  echo "Device: ${c_grn}$brand $model${c_off}  (Android $(adb shell getprop ro.build.version.release | tr -d '\r'), $os)"
  case $(echo "$brand" | tr '[:upper:]' '[:lower:]') in
    xiaomi|redmi|poco) ;;
    *) echo "${c_ylw}warning:${c_off} this does not look like a Xiaomi device ($brand)."
       [ "$ASSUME_YES" = 1 ] || { read -r -p "Continue anyway? [y/N] " a; [[ $a =~ ^[Yy] ]] || exit 1; };;
  esac
  SERIAL=$(adb get-serialno | tr -d '\r')
}

installed_pkgs() { adb shell pm list packages -e 2>/dev/null | sed 's/^package://' | tr -d '\r'; }

mem_report() {
  adb shell cat /proc/meminfo | tr -d '\r' | awk '/MemTotal|MemAvailable/ {printf "  %-14s %6d MB\n", $1, $2/1024}'
}

ensure_keyboard_safe() {
  # Don't remove the active keyboard unless we can switch to Gboard first.
  local cur
  cur=$(adb shell settings get secure default_input_method | tr -d '\r')
  [[ $cur == com.preff.kb.xm/* ]] || return 0
  if echo "$INSTALLED" | grep -qx com.google.android.inputmethod.latin; then
    if [ "$DRY_RUN" = 1 ]; then echo "  would switch keyboard to Gboard"; return 0; fi
    adb shell ime enable "$GBOARD_IME" >/dev/null 2>&1
    adb shell ime set "$GBOARD_IME" >/dev/null 2>&1 && echo "  switched default keyboard to Gboard"
  else
    echo "  ${c_ylw}skipping Facemoji keyboard${c_off}: it is your only keyboard (install Gboard first)"
    SKIP_PKGS+=(com.preff.kb.xm)
  fi
}

remove_pkg() {
  local p=$1 out
  if is_protected "$p"; then echo "  ${c_ylw}protected${c_off}  $p"; return; fi
  local s; for s in "${SKIP_PKGS[@]:-}"; do [ "$s" = "$p" ] && return; done
  echo "$INSTALLED" | grep -qx "$p" || return 0   # not on this device
  if [ "$DRY_RUN" = 1 ]; then echo "  would remove $p"; return; fi

  out=$(adb shell pm uninstall --user 0 "$p" 2>&1 | tr -d '\r')
  if [[ $out == *Success* ]]; then
    echo "  ${c_grn}removed${c_off}    $p"; echo "uninstall $p" >> "$LOG"; ((REMOVED++))
  else
    # Some apps are blocked from uninstall on HyperOS (Failure [-1000]); disable instead.
    out=$(adb shell pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')
    if [[ $out == *disabled* ]]; then
      echo "  ${c_ylw}disabled${c_off}   $p  (uninstall blocked by OS)"; echo "disable $p" >> "$LOG"; ((DISABLED++))
    else
      echo "  ${c_red}failed${c_off}     $p  ($out)"; ((FAILED++))
    fi
  fi
}

restore() {
  local file=${1:-} line action p
  check_device
  if [ -n "$file" ]; then
    [ -f "$file" ] || die "log file not found: $file"
    while read -r action p; do
      [ -z "${p:-}" ] && continue
      if [ "$action" = disable ]; then adb shell pm enable "$p" >/dev/null 2>&1 && echo "  enabled   $p"
      else adb shell cmd package install-existing "$p" 2>&1 | grep -q -i -e installed -e success && echo "  restored  $p"; fi
    done < "$file"
  else
    echo "Restoring every package known to this script (those still present in /system)..."
    for g in A T B C; do for p in $(group_pkgs $g); do
      adb shell pm enable "$p" >/dev/null 2>&1
      adb shell cmd package install-existing "$p" 2>&1 | grep -q -i -e installed -e success && echo "  restored  $p"
    done; done
  fi
  echo "Done. Reboot the phone to finish."
}

list_groups() {
  for g in A T B C; do
    echo; echo "${c_grn}Group $g${c_off} — $(group_desc $g)"
    group_pkgs $g | sed 's/^/  /'
  done
}

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
DRY_RUN=0; ASSUME_YES=0; GROUPS_SEL=""; SKIP_PKGS=(); REMOVED=0; DISABLED=0; FAILED=0

while [ $# -gt 0 ]; do
  case $1 in
    -n|--dry-run) DRY_RUN=1;;
    -y|--yes)     ASSUME_YES=1;;
    -a|--all)     GROUPS_SEL="A,T,B,C";;
    -g|--groups)  shift; GROUPS_SEL=$(echo "${1:-}" | tr '[:lower:]' '[:upper:]');;
    -l|--list)    list_groups; exit 0;;
    -r|--restore) shift; restore "${1:-}"; exit 0;;
    -m|--mem)     check_device; mem_report; adb shell dumpsys meminfo | sed -n '/Total RSS by process/,/Total RSS by OOM/p' | sed -n '2,16p'; exit 0;;
    -h|--help)    usage;;
    *) die "unknown option: $1 (see --help)";;
  esac
  shift
done

check_device
INSTALLED=$(installed_pkgs)
LOG="debloat-${SERIAL}-$(date +%Y%m%d-%H%M%S).log"

echo; echo "Memory before:"; mem_report

SELECTED=()
if [ -n "$GROUPS_SEL" ]; then
  IFS=',' read -r -a SELECTED <<< "$GROUPS_SEL"
else
  for g in A T B C; do
    present=$(group_pkgs $g | while read -r p; do echo "$INSTALLED" | grep -qx "$p" && echo "$p"; done)
    n=$(printf '%s' "$present" | grep -c . || true)
    echo; echo "${c_grn}Group $g${c_off} — $(group_desc $g)  [$n present on this device]"
    [ "$n" -eq 0 ] && continue
    echo "$present" | sed 's/^/    /'
    if [ "$ASSUME_YES" = 1 ]; then SELECTED+=("$g"); continue; fi
    default=$([ "$g" = A ] || [ "$g" = T ] && echo Y || echo N)
    read -r -p "Remove group $g? [$( [ $default = Y ] && echo Y/n || echo y/N )] " a
    a=${a:-$default}
    [[ $a =~ ^[Yy] ]] && SELECTED+=("$g")
  done
fi

[ ${#SELECTED[@]} -eq 0 ] && { echo "Nothing selected."; exit 0; }

echo
for g in "${SELECTED[@]}"; do
  case $g in A|T|B|C) ;; *) die "unknown group: $g";; esac
  echo "== Group $g: $(group_desc $g)"
  [ "$g" = C ] && ensure_keyboard_safe
  for p in $(group_pkgs "$g"); do remove_pkg "$p"; done
done

echo
if [ "$DRY_RUN" = 1 ]; then echo "Dry run — nothing was changed."; exit 0; fi
echo "Removed: $REMOVED   Disabled: $DISABLED   Failed: $FAILED"
[ -f "$LOG" ] && echo "Log saved to $LOG  (undo with: $0 --restore $LOG)"
echo; echo "Memory now (reboot for the full effect):"; mem_report
