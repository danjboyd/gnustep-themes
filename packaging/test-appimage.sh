#!/bin/sh
# Run a CI-built Theme Settings AppImage on a private
# Xvfb display with a scratch GNUstep home, defaults and theme folder.
# Fail closed: no write happens unless a read-only first launch reports a
# defaults root inside the scratch root.
#   packaging/test-appimage.sh <AppImage> <outdir> <examples dir>
set -eu
img=$1; out=$2; ex=$3
mkdir -p "$out"
root=$(mktemp -d "${TMPDIR:-/tmp}/appimage-test.XXXXXX"); chmod 700 "$root"; root=$(cd "$root" && pwd -P)
xvfb=""
fail() { echo "test-appimage: FAIL: $*" >&2; exit 1; }
has_marker() { { tr '\0' '\n' < "/proc/$1/environ"; } 2>/dev/null | grep -qxF -- "GTS_TEST_ROOT=$root"; }
mine() { for p in $(ps -u "$(id -u)" -o pid=); do [ "$p" = "$$" ] && continue; has_marker "$p" && echo "$p"; done; return 0; }
finish() {
  st=$?; set +e; trap - EXIT
  for p in $(mine); do kill -TERM "$p" 2>/dev/null; done
  [ -n "$xvfb" ] && kill -TERM "$xvfb" 2>/dev/null
  sleep 1
  for p in $(mine); do kill -KILL "$p" 2>/dev/null; done
  echo "test-appimage: scratch root kept at $root (status $st)"
  exit $st
}
trap finish EXIT INT TERM

# Scratch home, themes (plists only; the catalog never loads theme code), config.
H=$root/home
# No Defaults directory yet: a brand-new user. Adwaita in the user theme
# folder; Gumdrop ONLY in a separate "host" root, reachable solely through
# GTS_HOST_THEME_ROOTS.
mkdir -p "$H/GNUstep/Library/Themes" "$root/user" "$root/tmp" "$root/hostthemes"
cp -R "$ex/Adwaita.theme" "$H/GNUstep/Library/Themes/"
cp -R "$ex/Gumdrop.theme" "$root/hostthemes/"
{
  echo "GNUSTEP_USER_CONFIG_FILE=$root/user.conf"
  echo "GNUSTEP_USER_DEFAULTS_DIR=$root/user/Defaults"
  echo "GNUSTEP_USER_DIR=$H/GNUstep"
  for k in APPS:Applications ADMIN_APPS:Applications/Admin WEB_APPS:Library/WebApplications \
           TOOLS:Tools ADMIN_TOOLS:Tools/Admin LIBRARY:Library HEADERS:Library/Headers \
           LIBRARIES:Library/Libraries DOC:Library/Documentation \
           DOC_MAN:Library/Documentation/man DOC_INFO:Library/Documentation/info; do
    printf 'GNUSTEP_USER_DIR_%s=%s/GNUstep/%s\n' "${k%%:*}" "$H" "${k#*:}"
  done
} > "$root/GNUstep.conf"
printf 'GNUSTEP_USER_DIR=%s/GNUstep\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\n' "$H" "$root" > "$root/user.conf"
chmod 600 "$root/GNUstep.conf" "$root/user.conf"
cp "$img" "$root/ThemeSettings.AppImage"; chmod 700 "$root/ThemeSettings.AppImage"

# Private display, never :0/:1/:120.
dpy=200
while [ -e "/tmp/.X11-unix/X$dpy" ] || [ -e "/tmp/.X$dpy-lock" ]; do dpy=$((dpy+1)); [ $dpy -lt 260 ] || fail "no free display"; done
case "$dpy" in 0|1|120) fail "refusing display :$dpy" ;; esac
GTS_TEST_ROOT=$root Xvfb ":$dpy" -screen 0 1280x900x24 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
n=0; while [ $n -lt 50 ]; do [ -S "/tmp/.X11-unix/X$dpy" ] && [ "$({ tr -dc 0-9 < /tmp/.X$dpy-lock; } 2>/dev/null)" = "$xvfb" ] && break; sleep 0.1; n=$((n+1)); done
[ $n -lt 50 ] || fail "Xvfb :$dpy not ready"
echo "test-appimage: private display :$dpy"

run() {  # log-file args...   (HOSTROOTS, if set, becomes GTS_HOST_THEME_ROOTS)
  lg=$1; shift
  env -i ${HOSTROOTS:+GTS_HOST_THEME_ROOTS="$HOSTROOTS"} PATH=/usr/bin:/bin DISPLAY=":$dpy" HOME="$H" GNUSTEP_HOME="$H" USER="$(id -un)" LOGNAME="$(id -un)" \
    GNUSTEP_CONFIG_FILE="$root/GNUstep.conf" TMPDIR="$root/tmp" APPIMAGE_EXTRACT_AND_RUN=1 \
    GDK_BACKEND=x11 NO_AT_BRIDGE=1 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent GTS_TEST_ROOT="$root" \
    timeout 120 "$root/ThemeSettings.AppImage" "$@" > "$lg" 2>&1 || echo "test-appimage: launch exited $? (see $lg)"
}

# 1. Read-only launch: diagnostics must name a defaults root inside $root.
# The first step is an absolute path: the AppImage launcher absolutizes a
# leading relative word of an argument (seen: "log; ..." -> "$PWD/log; ...").
# "nop" absorbs that rewrite (it fails; the remaining steps run normally).
run "$out/1-readonly.log" -GTSScript "nop; shot $out/AI1-initial-global.png; log"
line=$(grep -m1 'Defaults root:' "$out/1-readonly.log" || true)
echo "test-appimage: $line"
case "$line" in
  *"Defaults root: $root/"*) ;;   # (resolves via GNUSTEP_HOME; the bundled base ignores GNUSTEP_CONFIG_FILE)
  *) fail "defaults root not inside the scratch root; nothing written" ;;
esac
droot=$(echo "$line" | sed 's/.*Defaults root: \([^ ]*\) .*/\1/')
echo "test-appimage: defaults root $droot"
ls -A "$droot" 2>/dev/null | grep -v '^\.lck$' && fail "a defaults file appeared during the read-only launch" || true
if grep -q 'script: message: could not load' "$out/1-readonly.log"; then
  echo "test-appimage: FIRST-LAUNCH: FAILED (could not load defaults in a new home)"
else
  echo "test-appimage: FIRST-LAUNCH: ok (no load error in a new home)"
fi

# 2. Themes from the host theme roots: both scratch-installed themes offered;
#    set the global theme to Adwaita and the accent to purple; Apply.
run "$out/2-apply.log" -GTSScript "nop; theme Adwaita; shot $out/AI2-adwaita-chosen.png; choose adwaita.accent-color purple; shot $out/AI3-staged.png; apply; log; shot $out/AI4-applied.png"
HOSTROOTS="$root/hostthemes" run "$out/3-gumdrop.log" -GTSScript "nop; theme Gumdrop; shot $out/AI5-gumdrop-from-host-root.png; cancel; log"
HOSTROOTS="" run "$out/4-no-hostroot.log" -GTSScript "nop; theme Gumdrop; log"
grep -q 'script: theme Gumdrop -> ok' "$out/3-gumdrop.log" && echo "test-appimage: HOST-ROOT: ok (Gumdrop offered only via GTS_HOST_THEME_ROOTS)" || echo "test-appimage: HOST-ROOT: FAILED"
grep -q 'script: theme Gumdrop -> FAILED' "$out/4-no-hostroot.log" && echo "test-appimage: HOST-ROOT control: ok (not offered without it)" || echo "test-appimage: HOST-ROOT control: FAILED"
echo "--- stored NSGlobalDomain (scratch) ---"
cat "$droot/NSGlobalDomain.plist" 2>/dev/null || echo "(none)"
ls -la "$droot"
grep -h 'script:' "$out"/*.log
