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
#   GTS_SHOTS_ONLY=A runs only scenario A (startup/cleanup validation).
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
grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR=' \
  /etc/GNUstep/GNUstep.conf > "$root/GNUstep.conf" || rc=$?
[ "$rc" -le 1 ] || fail "cannot read master config"
printf 'GNUSTEP_USER_CONFIG_FILE=%s/user.conf\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\n' "$root" "$root" >> "$root/GNUstep.conf"
printf 'GNUSTEP_USER_DIR=%s/user\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\n' "$root" "$root" > "$root/user.conf"
chmod 600 "$root/GNUstep.conf" "$root/user.conf"
export GNUSTEP_CONFIG_FILE="$root/GNUstep.conf" GTS_TEST_ROOT="$root"

make -s -C "$here/Tests/RootProbe" messages=no >/dev/null
for d in ThemeSettingsApp ThemeSettingsDemo; do make -s -C "$here/$d" messages=no >/dev/null; done
resolved=$("$here/Tests/RootProbe/obj/gts-root-probe")
case "$resolved" in "$root"/*) ;; *) fail "defaults root $resolved not isolated; refusing" ;; esac
plib=$(ldd "$here/Tests/RootProbe/obj/gts-root-probe" | awk '/libgnustep-base/{print $3}')
[ "$plib" = "$(ldd /usr/bin/defaults | awk '/libgnustep-base/{print $3}')" ] || fail "defaults tool uses another gnustep-base"
echo "screenshots: defaults root $resolved (isolated)"

# Seed a realistic state through the defaults tool (verified above).
D() { /usr/bin/defaults "$@" >/dev/null; }
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
  got=$(/usr/bin/defaults read "$1" "$2" 2>/dev/null | sed "s/^$1 $2 //")
  if [ "$got" = "$3" ]; then echo "CHECK ok: $4 ($1 $2 = ${got:-<absent>})"
  else echo "CHECK FAILED: $4 ($1 $2 = ${got:-<absent>}, want ${3:-<absent>})"; checkfail=1; fi
}
checkfail=0

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
