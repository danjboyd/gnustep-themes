#!/bin/sh
# Renders review screenshots of the standalone configurator and the in-app
# pane on a PRIVATE Xvfb display with ISOLATED defaults.
#   scripts/screenshots.sh <output-dir>
# Safety: a fresh display number chosen by Xvfb itself (-displayfd); the
# defaults root is verified (read-only probe) before any app starts; every
# process started here carries GTS_TEST_ROOT=<scratch> and only processes
# that carry it (and started after this script) are stopped afterwards.
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

mine() {   # pids carrying our marker (any session: helpers such as gdnc daemonize)
  for p in $(ps -u "$(id -u)" -o pid=); do
    [ "$p" = "$$" ] && continue
    if { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qxF -- "GTS_TEST_ROOT=$root"; then
      echo "$p"
    fi
  done
  return 0
}
finish() {
  st=$1; set +e; trap '' INT TERM; trap - EXIT
  pids=$(mine); [ -n "$pids" ] && kill -TERM $pids 2>/dev/null
  [ -n "$xvfb" ] && kill -TERM "$xvfb" 2>/dev/null
  sleep 1
  pids=$(mine); [ -n "$pids" ] && kill -KILL $pids 2>/dev/null
  [ -n "$xvfb" ] && { kill -KILL "$xvfb" 2>/dev/null; wait "$xvfb" 2>/dev/null; }
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
n=0; while [ ! -e "/tmp/.X11-unix/X$dpy" ] && [ $n -lt 50 ]; do sleep 0.1; n=$((n+1)); done
kill -0 "$xvfb" 2>/dev/null && [ -e "/tmp/.X11-unix/X$dpy" ] || fail "Xvfb did not start on :$dpy"
echo "screenshots: private display :$dpy"
export DISPLAY=":$dpy"

run() {   # app-binary args...
  timeout 60 "$@" >>"$root/apps.log" 2>&1 || echo "screenshots: $1 exited $?" >&2
}
run "$here/ThemeSettingsApp/ThemeSettings.app/ThemeSettings" -GTSExtraThemeRoot "$here/examples" \
  -GTSScreenshot "$out/standalone-global.png"
run "$here/ThemeSettingsApp/ThemeSettings.app/ThemeSettings" -GTSExtraThemeRoot "$here/examples" \
  -GTSTargetApp "$root/apps/Writer.app" -GTSScreenshot "$out/standalone-app-adwaita.png"
run "$here/ThemeSettingsDemo/DemoNotes.app/DemoNotes" -GTSExtraThemeRoot "$here/examples" \
  -GTSOpenSettings YES -GTSScreenshot "$out/inapp-pane-gumdrop.png"
grep -h "screenshot" "$root/apps.log" || true
ls -l "$out"
