#!/bin/sh
# Renders review screenshots of the standalone configurator and the in-app
# pane on a PRIVATE Xvfb display with ISOLATED defaults.
#   scripts/screenshots.sh <output-dir>
# Safety: the first free display number from :200, accepted only once the
# X lock file names OUR Xvfb pid; the defaults root is verified (read-only
# probe) before any app starts; every process started here carries
# GTS_TEST_ROOT=<scratch>. Cleanup records pid:starttime for marked
# processes and rechecks start time + exact marker right before each
# signal; anything left keeps the scratch config and fails the run.
#   GTS_SHOTS_ONLY=A runs only scenario A (startup/cleanup validation);
#   =F only the free-form scenario; =G only the AppImage-target scenario;
#   =H only the editor callback host check (Tests/HostCheck);
#   =I only the installed-library smoke: Kit/UI staged into a prefix inside
#      the scratch root (make install DESTDIR=...), Tests/ExternalHost built
#      out of tree against it, link/runtime receipts, one Apply on Xvfb.
#   =J end to end with the REAL Adwaita theme: GTS_E2E_THEMES=<dir holding a
#      built Adwaita.theme>, copied into the isolated user's Library/Themes;
#      the demo app is captured before and after changing settings in its
#      own editor pane (relaunched, since these settings apply on restart).
# Another GNUstep (e.g. a clang/libobjc2 toolchain, which Adwaita needs):
#   GTS_MASTER_CONF=<its GNUstep.conf> GTS_DEFAULTS_TOOL=<its defaults>,
#   with that toolchain's GNUstep.sh sourced and the apps built with it.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: screenshots.sh <output-dir>}
mkdir -p "$out"; out=$(cd "$out" && pwd -P)
fail() { echo "screenshots: $*" >&2; exit 1; }

: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
root=$(mktemp -d "${GTS_SCRATCH:-${TMPDIR:-/tmp}}/gts-shots.XXXXXX") || fail "no scratch"
chmod 700 "$root"; root=$(cd "$root" && pwd -P)
xvfb=""

proc_start() { sed -n 's/^.*) [A-Za-z] \([^ ]* \)\{18\}\([0-9]*\).*/\2/p' "/proc/$1/stat" 2>/dev/null; }
proc_state() { sed -n 's/^.*) \([A-Za-z]\).*/\1/p' "/proc/$1/stat" 2>/dev/null; }
has_marker() { { tr '\0' '\n' < "/proc/$1/environ"; } 2>/dev/null | grep -qxF -- "GTS_TEST_ROOT=$root"; }
mine() {   # "pid:start" of live processes carrying our marker (helpers such as gdnc daemonize)
  for p in $(ps -u "$(id -u)" -o pid=); do
    [ "$p" = "$$" ] && continue
    [ "$(proc_state "$p")" = Z ] && continue
    has_marker "$p" || continue
    ps0=$(proc_start "$p"); [ -n "$ps0" ] && echo "$p:$ps0"
  done
  return 0
}
signal_verified() {   # SIG records... ; re-check identity right before each signal
  sig=$1; shift
  for rec in "$@"; do
    p=${rec%%:*}; ps0=${rec#*:}
    [ "$(proc_start "$p")" = "$ps0" ] && has_marker "$p" && kill "-$sig" "$p" 2>/dev/null
  done
  return 0
}
finish() {
  st=$1; set +e; trap '' INT TERM; trap - EXIT
  signal_verified TERM $(mine)          # includes Xvfb: it carries the marker too
  n=0; while [ -n "$(mine)" ] && [ $n -lt 30 ]; do sleep 0.1; n=$((n+1)); done
  signal_verified KILL $(mine)
  sleep 0.5
  if [ -n "$xvfb" ] && [ "$(proc_state "$xvfb")" = Z -o -z "$(proc_state "$xvfb")" ]; then
    wait "$xvfb" 2>/dev/null
  fi
  if [ -n "$(mine)" ]; then
    echo "screenshots: KEEPING $root, processes remain: $(mine | tr '\n' ' ')" >&2; st=1
  else
    rm -rf "$root"
  fi
  exit "$st"
}
trap 'finish $?' EXIT; trap 'finish 130' INT; trap 'finish 143' TERM

# Isolated defaults (same recipe as run-tests.sh).
mkdir -p "$root/user/Defaults"
rc=0
grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR' \
  "${GTS_MASTER_CONF:-/etc/GNUstep/GNUstep.conf}" > "$root/GNUstep.conf" || rc=$?
[ "$rc" -le 1 ] || fail "cannot read master config"
printf 'GNUSTEP_USER_CONFIG_FILE=%s/user.conf\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\n' "$root" "$root" >> "$root/GNUstep.conf"
# Every user path absolute inside the scratch root: a config with
# home-relative user dirs (GNUSTEP_USER_DIR_LIBRARY=GNUstep/Library) would
# otherwise look at the real ~/GNUstep (themes, applications).
for k in APPS:Applications ADMIN_APPS:Applications/Admin WEB_APPS:Library/WebApplications \
         TOOLS:Tools ADMIN_TOOLS:Tools/Admin LIBRARY:Library HEADERS:Library/Headers \
         LIBRARIES:Library/Libraries DOC:Library/Documentation \
         DOC_MAN:Library/Documentation/man DOC_INFO:Library/Documentation/info; do
  printf 'GNUSTEP_USER_DIR_%s=%s/user/%s\n' "${k%%:*}" "$root" "${k#*:}" >> "$root/GNUstep.conf"
done
printf 'GNUSTEP_USER_DIR=%s/user\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\n' "$root" "$root" > "$root/user.conf"
chmod 600 "$root/GNUstep.conf" "$root/user.conf"
export GNUSTEP_CONFIG_FILE="$root/GNUstep.conf" GTS_TEST_ROOT="$root"

make -s -C "$here/Tests/RootProbe" messages=no >/dev/null
for d in ThemeSettingsApp ThemeSettingsDemo; do make -s -C "$here/$d" messages=no >/dev/null; done
resolved=$("$here/Tests/RootProbe/obj/gts-root-probe")
case "$resolved" in "$root"/*) ;; *) fail "defaults root $resolved not isolated; refusing" ;; esac
plib=$(ldd "$here/Tests/RootProbe/obj/gts-root-probe" | awk '/libgnustep-base/{print $3}')
DEFAULTS=${GTS_DEFAULTS_TOOL:-/usr/bin/defaults}
[ "$plib" = "$(ldd "$DEFAULTS" | awk '/libgnustep-base/{print $3}')" ] || fail "defaults tool uses another gnustep-base"
echo "screenshots: defaults root $resolved (isolated)"

# Seed a realistic state through the defaults tool (verified above).
D() { "$DEFAULTS" "$@" >/dev/null; }
D write NSGlobalDomain GnomeThemeColorScheme force-dark          # global explicit
D write org.example.Writer GSTheme Adwaita                        # app picks Adwaita
D write org.example.Writer GnomeThemeAccentColor teal            # app override
D write org.example.Writer GnomeThemeOverlayScrollbars NO
D write org.gnustep.themesettings.DemoNotes GSTheme Gumdrop       # host app picks Gumdrop
mkdir -p "$root/apps/Writer.app/Resources"
cat > "$root/apps/Writer.app/Resources/Info-gnustep.plist" <<'EOF'
{ CFBundleIdentifier = "org.example.Writer"; NSExecutable = Writer;
  NSMainNibFile = "Writer.gorm"; GnomeThemeMetrics = compact; }
EOF

# Private display: the first free number from 200 up (never :0, never
# a display with a socket or lock file), owned by this run.
dpy=200
while [ -e "/tmp/.X11-unix/X$dpy" ] || [ -e "/tmp/.X$dpy-lock" ]; do
  dpy=$((dpy + 1)); [ "$dpy" -lt 260 ] || fail "no free display number"
done
Xvfb ":$dpy" -screen 0 1280x900x24 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
# Ready = our Xvfb is alive AND the display lock names our pid AND the
# socket exists. A racing server on the same number fails the lock check.
n=0; ready=0
while [ $n -lt 50 ]; do
  [ -n "$(proc_state "$xvfb")" ] && [ "$(proc_state "$xvfb")" != Z ] || fail "Xvfb exited during startup on :$dpy"
  lockpid=$({ tr -dc '0-9' < "/tmp/.X$dpy-lock"; } 2>/dev/null || true)
  if [ "$lockpid" = "$xvfb" ] && [ -S "/tmp/.X11-unix/X$dpy" ]; then ready=1; break; fi
  sleep 0.1; n=$((n+1))
done
[ "$ready" -eq 1 ] || fail "Xvfb :$dpy not ready (lock pid ${lockpid:-none}, ours $xvfb)"
echo "screenshots: private display :$dpy"
export DISPLAY=":$dpy"

run() {   # app-binary args...
  timeout 90 "$@" >>"$root/apps.log" 2>&1 || echo "screenshots: $1 exited $?" >&2
}
APP="$here/ThemeSettingsApp/ThemeSettings.app/ThemeSettings"
DEMO="$here/ThemeSettingsDemo/DemoNotes.app/DemoNotes"
X="-GTSExtraThemeRoot $here/examples"
check() {   # domain key expected label
  got=$("$DEFAULTS" read "$1" "$2" 2>/dev/null | sed "s/^$1 $2 //")
  if [ "$got" = "$3" ]; then echo "CHECK ok: $4 ($1 $2 = ${got:-<absent>})"
  else echo "CHECK FAILED: $4 ($1 $2 = ${got:-<absent>}, want ${3:-<absent>})"; checkfail=1; fi
}
checkfail=0

# I. Installed-library smoke. Stage Kit/UI into $root/stage only, build the
#    external host from a copy in $root/host against the staged interface,
#    check its link/runtime dependencies, run one Apply. Removed with $root.
# J. End to end with the REAL Adwaita theme (built elsewhere; see header).
#    Before: DemoNotes under Adwaita, light + blue. Change both settings in
#    DemoNotes' own editor pane, Apply, check the stored values, relaunch
#    (both settings say "Takes effect when the application restarts") and
#    capture again. Pixels are compared by eye in the report (the pane's
#    theme note names the isolated user copy of Adwaita.theme, so the real
#    built theme is the one loaded); the checks here are the stored values.
if [ "${GTS_SHOTS_ONLY:-}" = J ]; then
  themes=${GTS_E2E_THEMES:?set GTS_E2E_THEMES to a dir holding a built Adwaita.theme}
  [ -d "$themes/Adwaita.theme" ] || fail "no Adwaita.theme in $themes"
  mkdir -p "$root/user/Library/Themes"
  cp -R "$themes/Adwaita.theme" "$root/user/Library/Themes/"
  dn=org.gnustep.themesettings.DemoNotes
  D write $dn GSTheme Adwaita
  D write $dn GnomeThemeColorScheme force-light
  D write $dn GnomeThemeAccentColor blue
  run "$DEMO" -GTSScreenshot "$out/J1-adwaita-before-light-blue.png"
  # A throwaway staged change enables Apply, the default button, which is
  # drawn in the accent colour; it is cancelled before the real change.
  run "$DEMO" -GTSOpenSettings YES -GTSScript \
    "choose adwaita.menu-style menubar; shot $out/J2-pane-before-blue.png; cancel; choose adwaita.color-scheme force-dark; choose adwaita.accent-color red; apply; log; shot $out/J3-pane-applied.png"
  check $dn GnomeThemeColorScheme force-dark "J color scheme saved by the editor"
  check $dn GnomeThemeAccentColor red "J accent saved by the editor"
  run "$DEMO" -GTSScreenshot "$out/J4-adwaita-after-dark-red.png"
  run "$DEMO" -GTSOpenSettings YES -GTSScript \
    "choose adwaita.menu-style menubar; shot $out/J5-pane-after-dark-red.png; cancel"
  check $dn GnomeThemeMenuStyle "" "J throwaway menu-style change was cancelled, never saved"
  grep -h "^script:" "$root/apps.log" || true
  ls "$out"
  [ "$checkfail" -eq 0 ] || fail "read-back checks failed"
  exit 0
fi

# K. End to end with the REAL Gumdrop theme (GTS_E2E_THEMES holds a built
#    Gumdrop.theme). Before: DemoNotes under Gumdrop with nothing set. Then
#    all five settings are changed in DemoNotes' own editor pane, saved,
#    checked, and the app relaunched (font/menu apply on restart; corner
#    radius and shadows on new windows, and only where the display backend
#    draws them -- a plain Xvfb backend may ignore both).
if [ "${GTS_SHOTS_ONLY:-}" = K ]; then
  themes=${GTS_E2E_THEMES:?set GTS_E2E_THEMES to a dir holding a built Gumdrop.theme}
  [ -d "$themes/Gumdrop.theme" ] || fail "no Gumdrop.theme in $themes"
  mkdir -p "$root/user/Library/Themes"
  cp -R "$themes/Gumdrop.theme" "$root/user/Library/Themes/"
  dn=org.gnustep.themesettings.DemoNotes
  D write $dn GSTheme Gumdrop
  run "$DEMO" -GTSScreenshot "$out/K1-gumdrop-before.png"
  run "$DEMO" -GTSOpenSettings YES -GTSScript \
    "shot $out/K2-pane-before.png; choose gumdrop.menu-style menubar; type gumdrop.font DejaVuSerif; type gumdrop.font-size 20; type gumdrop.window-corner-radius 0; choose gumdrop.window-shadows NO; apply; log; shot $out/K3-pane-applied.png"
  check $dn GumdropMenuStyle menubar "K menu style saved"
  check $dn NSFont DejaVuSerif "K font saved"
  check $dn NSFontSize 20 "K font size saved"
  check $dn GSBackWindowCornerRadius 0 "K corner radius saved"
  check $dn GSBackWindowShadows NO "K shadows saved"
  run "$DEMO" -GTSScreenshot "$out/K4-gumdrop-after.png"
  run "$DEMO" -GTSOpenSettings YES -GTSScript "shot $out/K5-pane-after.png"
  grep -h "^script:" "$root/apps.log" || true
  ls "$out"
  [ "$checkfail" -eq 0 ] || fail "read-back checks failed"
  exit 0
fi

# L. Gumdrop's control font, end to end. Like K, but GTS_E2E_PLIST may
#    replace the scratch copy's ThemeSettings.plist with a draft (e.g. the
#    nine-setting version with control/label font rows). DemoNotes' text is
#    an NSTextView (user font), so the probe is the editor pane itself: its
#    pop-up menus and buttons set no font and use the control font.
if [ "${GTS_SHOTS_ONLY:-}" = L ]; then
  themes=${GTS_E2E_THEMES:?set GTS_E2E_THEMES to a dir holding a built Gumdrop.theme}
  [ -d "$themes/Gumdrop.theme" ] || fail "no Gumdrop.theme in $themes"
  mkdir -p "$root/user/Library/Themes"
  cp -R "$themes/Gumdrop.theme" "$root/user/Library/Themes/"
  [ -z "${GTS_E2E_PLIST:-}" ] || cp "$GTS_E2E_PLIST" "$root/user/Library/Themes/Gumdrop.theme/Resources/ThemeSettings.plist"
  dn=org.gnustep.themesettings.DemoNotes
  D write $dn GSTheme Gumdrop
  run "$DEMO" -GTSOpenSettings YES -GTSScript \
    "shot $out/L1-pane-before.png; type gumdrop.control-font DejaVuSerif; type gumdrop.control-font-size 20; apply; log; shot $out/L2-pane-applied.png"
  check $dn NSControlContentFont DejaVuSerif "L control font saved"
  check $dn NSControlContentFontSize 20 "L control font size saved"
  run "$DEMO" -GTSOpenSettings YES -GTSScript "shot $out/L3-pane-after-relaunch.png"
  grep -h "^script:" "$root/apps.log" || true
  ls "$out"
  [ "$checkfail" -eq 0 ] || fail "read-back checks failed"
  exit 0
fi

if [ "${GTS_SHOTS_ONLY:-}" = I ]; then
  stage="$root/stage"; mkdir -p "$stage" "$root/host"
  inc="$stage$(gnustep-config --variable=GNUSTEP_LOCAL_HEADERS)"
  lib="$stage$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)"
  make -s -C "$here" messages=no >/dev/null || fail "library build failed"
  make -s -C "$here" install messages=no DESTDIR="$stage" GNUSTEP_INSTALLATION_DOMAIN=LOCAL >/dev/null \
    || fail "staged install failed"
  echo "screenshots: staged files (sha256, relative to $stage):"
  (cd "$stage" && find . -type f | sort | xargs sha256sum | sed 's/^\(.\{16\}\)[0-9a-f]*/\1/')
  (cd "$stage" && find . -type l | sort | while read -r l; do echo "  link $l -> $(readlink "$l")"; done)
  # Nothing may land in the real install locations.
  leaked=$(ls -d "$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)"/libThemeSettings* \
    "$(gnustep-config --variable=GNUSTEP_LOCAL_HEADERS)"/ThemeSettings* \
    "$HOME"/GNUstep/Library/Libraries/libThemeSettings* "$HOME"/GNUstep/Library/Headers/ThemeSettings* 2>/dev/null || true)
  [ -z "$leaked" ] && echo "CHECK ok: I nothing installed in the real LOCAL/USER locations" \
    || { echo "CHECK FAILED: I found installed files: $leaked"; checkfail=1; }
  cp "$here/Tests/ExternalHost/GNUmakefile" "$here/Tests/ExternalHost/main.m" "$root/host/"
  make -C "$root/host" messages=yes GTS_INCLUDE="$inc" GTS_LIB="$lib" >"$root/host-build.log" 2>&1 \
    || { cat "$root/host-build.log"; fail "external host build failed"; }
  hb="$root/host/obj/gts-external-host"
  grep -q -- "$here" "$root/host-build.log" && { echo "CHECK FAILED: I host build referenced the source tree"; checkfail=1; } \
    || echo "CHECK ok: I host build used no source-tree path (only $inc, $lib)"
  nm "$hb" | grep -q " [TDB] __objc_class_name_GTS" && { echo "CHECK FAILED: I host binary defines GTS classes"; checkfail=1; } \
    || echo "CHECK ok: I host binary defines no GTS classes (all from the libraries)"
  echo "screenshots: host NEEDED: $(objdump -p "$hb" | awk '/NEEDED/{printf "%s ", $2}')"
  deps=$(LD_LIBRARY_PATH="$lib" ldd "$hb")
  echo "$deps" | grep -i "themesettings\|gnustep\|gnutls\|not found" | sed 's/^/  ldd: /'
  for so in libThemeSettingsUI.so.0 libThemeSettingsKit.so.0; do
    p=$(echo "$deps" | awk -v s="$so" '$1==s{print $3}')
    [ "$p" = "$lib/$so" ] && echo "CHECK ok: I $so resolves to the staged prefix" \
      || { echo "CHECK FAILED: I $so resolves to ${p:-nothing}"; checkfail=1; }
  done
  echo "$deps" | grep -q "not found" && { echo "CHECK FAILED: I unresolved dependency"; checkfail=1; } \
    || echo "CHECK ok: I no unresolved dependencies"
  [ "$(echo "$deps" | awk '/libgnustep-base/{print $3}')" = "$(ldd "$DEFAULTS" | awk '/libgnustep-base/{print $3}')" ] \
    && echo "CHECK ok: I same libgnustep-base as the defaults tool" || { echo "CHECK FAILED: I other libgnustep-base"; checkfail=1; }
  ldd "$hb" | grep -q "libThemeSettingsUI.so.0 => not found" \
    && echo "CHECK ok: I without the staged path the libraries are not found (no fallback copy)" \
    || { echo "CHECK FAILED: I libraries found outside the stage"; checkfail=1; }
  D write org.example.ExternalHost GSTheme Adwaita
  ehs=0
  LD_LIBRARY_PATH="$lib" timeout 90 "$hb" $X -GTSHostDomain org.example.ExternalHost -GTSStageLib "$lib" \
    >>"$root/apps.log" 2>&1 || ehs=$?
  grep -h "^CHECK\|^external-host:" "$root/apps.log"
  echo "screenshots: external host exit status $ehs"
  [ "$ehs" -eq 0 ] || checkfail=1
  check org.example.ExternalHost GnomeThemeAccentColor purple "I defaults tool read-back"
  [ "$checkfail" -eq 0 ] || fail "installed-library smoke failed"
  exit 0
fi

# H. Callback contract of the real editor in a disposable AppKit host
#    (Tests/HostCheck): capture, order, nested Apply, exception reset,
#    invalid pending text. Checks only; no screenshots.
if [ "${GTS_SHOTS_ONLY:-}" = H ]; then
  make -s -C "$here/Tests/HostCheck" messages=no >/dev/null || fail "host check build failed"
  D write org.example.HostCheck GSTheme Adwaita
  hst=0
  timeout 90 "$here/Tests/HostCheck/obj/gts-host-check" $X -GTSHostDomain org.example.HostCheck \
    >>"$root/apps.log" 2>&1 || hst=$?
  grep -h "^CHECK\|^host-check:" "$root/apps.log"
  echo "screenshots: host check exit status $hst"
  [ "$hst" -eq 0 ] || fail "host check failed"
  exit 0
fi

# G. AppImage targets (read-only): a bound sidecar and one whose AppImage is
#    missing. The "AppImage" is a plain file: it is only hashed, never run.
if [ "${GTS_SHOTS_ONLY:-}" = G ]; then
  mkdir -p "$root/appimages"
  printf 'stand-in bytes, not an AppImage\n' > "$root/appimages/Notes-1.0-x86_64.AppImage"
  sha=$(sha256sum "$root/appimages/Notes-1.0-x86_64.AppImage" | cut -d' ' -f1)
  gum='{"SchemaVersion":1,"Theme":"Gumdrop","ThemeIdentifier":"org.gnustep.themes.gumdrop","Settings":[{"Identifier":"gumdrop.menu-style","Key":"GumdropMenuStyle","Type":"enum","CaseInsensitive":"YES","Values":[{"Value":"primary","Title":"Title-bar menu button"},{"Value":"menubar","Title":"In-window menu bar"}],"Scopes":["global","application"],"Title":"Menu style","Unset":{"Behavior":"static","Value":"primary"},"Precedence":["argument","application","global",{"Source":"applicationInfo","Values":["menubar"]}],"Apply":"restart"}]}'
  side() {   # file appimage-name sha
    printf '{"schema":1,"appimage":{"fileName":"%s","sha256":"%s"},"package":{"id":"org.example.NotesImg"},"app":{"executable":"Notes","bundleIdentifier":"org.example.NotesImg","runtimeDomainHint":"org.example.NotesImg","runtimeDomainHintSource":"bundleIdentifier"},"defaults":{"seedDomain":"org.example.NotesImg","seedDomainMatchesRuntimeHint":true,"seeds":[{"key":"GSTheme","value":"Gumdrop","policy":"each-launch-if-absent","rank":1}],"env":[]},"themes":[{"name":"Gumdrop","themeId":"org.gnustep.themes.gumdrop","infoStatus":"ok","origin":"themeInputs","installation":{"bundledPath":"usr/GNUstep/System/Library/Themes/Gumdrop.theme","executableStatus":"ok"},"settings":{"status":"inline","schemaVersion":1,"inline":%s}},{"name":"Big","infoStatus":"ok","settings":{"status":"notInlined","inline":null,"note":"over 256 KiB"}}]}\n' "$2" "$3" "$gum" > "$1"
  }
  side "$root/appimages/Notes-1.0-x86_64.themes.json" Notes-1.0-x86_64.AppImage "$sha"
  side "$root/appimages/Gone-2.0-x86_64.themes.json" Gone-2.0-x86_64.AppImage "$sha"
  D write org.example.NotesImg GumdropMenuStyle menubar
  before=$(ls "$root/user/Defaults" | tr '\n' ' ')
  run "$APP" $X -GTSSidecar "$root/appimages/Notes-1.0-x86_64.themes.json" -GTSScript \
    "log; shot $out/G1-appimage-bound-readonly.png; choose gumdrop.menu-style primary"
  run "$APP" $X -GTSSidecar "$root/appimages/Gone-2.0-x86_64.themes.json" -GTSScript \
    "log; shot $out/G2-appimage-missing.png"
  check org.example.NotesImg GumdropMenuStyle menubar "G read-only: nothing written"
  check org.example.NotesImg GSTheme "" "G no GSTheme written (seed is AppRun's job)"
  after=$(ls "$root/user/Defaults" | tr '\n' ' ')
  [ "$before" = "$after" ] && echo "CHECK ok: G defaults directory unchanged ($after)" || { echo "CHECK FAILED: G defaults changed"; checkfail=1; }
  grep -h "^script:" "$root/apps.log"
  [ "$checkfail" -eq 0 ] || fail "read-back checks failed"
  exit 0
fi

if [ "${GTS_SHOTS_ONLY:-}" != F ]; then
# A. standalone, global target
run "$APP" $X -GTSScreenshot "$out/A-standalone-global.png"

[ "${GTS_SHOTS_ONLY:-}" = A ] && { ls "$out"; exit 0; }

# B. standalone, app target: explicit vs inherited vs Info.plist; stage, Apply, receipt
run "$APP" $X -GTSTargetApp "$root/apps/Writer.app" -GTSScript \
  "shot $out/B1-app-initial.png; choose adwaita.accent-color purple; shot $out/B2-app-staged.png; apply; log; shot $out/B3-app-applied-restart-receipt.png"
check org.example.Writer GnomeThemeAccentColor purple "B Apply wrote the app domain"
check NSGlobalDomain GnomeThemeColorScheme force-dark "B global untouched"

# C. in-app pane (same editor class): Apply, then Reset staged and Cancelled
run "$DEMO" $X -GTSOpenSettings YES -GTSScript \
  "shot $out/C1-pane-initial.png; choose gumdrop.menu-style primary; apply; log; shot $out/C2-pane-applied.png; reset gumdrop.menu-style; shot $out/C3-pane-reset-staged.png; cancel; shot $out/C4-pane-cancelled.png"
check org.gnustep.themesettings.DemoNotes GumdropMenuStyle primary "C Apply wrote, Reset was cancelled"

# D. in-app pane, live setting: honest receipt (saved; live not confirmed)
D write org.gnustep.themesettings.DemoNotes GSTheme Adwaita
run "$DEMO" $X -GTSOpenSettings YES -GTSScript \
  "choose adwaita.header-bar-toolbar YES; apply; log; shot $out/D-pane-live-receipt.png"
check org.gnustep.themesettings.DemoNotes GnomeThemeHeaderBarToolbar YES "D Apply wrote a live setting"

fi
# F. free-form field: text typed but not committed must be saved by Apply;
#    invalid text must block the save (Apply enabled by typing alone).
fpane() { run "$DEMO" $X -GTSOpenSettings YES -GTSScript "$1"; }
D write org.gnustep.themesettings.DemoNotes GSTheme Adwaita
fpane "type adwaita.font-scale 1.25; shot $out/F1-typed-uncommitted.png; apply; log"
check org.gnustep.themesettings.DemoNotes GnomeFontScale 1.25 "F typed text committed by Apply"
fpane "type adwaita.font-scale 3; apply; log; shot $out/F2-invalid-blocked.png"
check org.gnustep.themesettings.DemoNotes GnomeFontScale 1.25 "F invalid text did not save"
[ "${GTS_SHOTS_ONLY:-}" = F ] && { grep -h "^script:" "$root/apps.log"; [ "$checkfail" -eq 0 ] || fail "read-back checks failed"; exit 0; }

# E. unreadable target domain: refused, nothing editable, file untouched
mkdir -p "$root/apps/Locked.app/Resources"
echo '{ CFBundleIdentifier = "org.example.Locked"; }' > "$root/apps/Locked.app/Resources/Info-gnustep.plist"
D write org.example.Locked GSTheme Adwaita
before=$(sha256sum "$root/user/Defaults/org.example.Locked.plist" | cut -d' ' -f1)
chmod 000 "$root/user/Defaults/org.example.Locked.plist"
run "$APP" $X -GTSTargetApp "$root/apps/Locked.app" -GTSScript \
  "log; shot $out/E-unreadable-refused.png; theme Gumdrop"
chmod 600 "$root/user/Defaults/org.example.Locked.plist"
after=$(sha256sum "$root/user/Defaults/org.example.Locked.plist" | cut -d' ' -f1)
[ "$before" = "$after" ] && echo "CHECK ok: E unreadable domain file unchanged" || { echo "CHECK FAILED: E file changed"; checkfail=1; }

grep -h "^script:\|screenshot" "$root/apps.log" || true
ls "$out"
[ "$checkfail" -eq 0 ] || fail "read-back checks failed"
