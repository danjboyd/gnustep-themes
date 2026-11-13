#!/bin/sh
# try-isolated.sh - try the Theme Settings AppImage without touching your
# real GNUstep settings.
#
#   packaging/try-isolated.sh path/to/ThemeSettings-*.AppImage [app arguments...]
#
# What it does:
#   1. Makes a throwaway folder (mktemp) and extracts the AppImage there, so
#      no FUSE mount is needed.
#   2. Points the app's GNUstep home there: GNUSTEP_HOME and
#      GNUSTEP_USER_ROOT. (gnustep-base ignores HOME; the AppImage's launcher
#      always uses its bundled GNUstep.conf, whose user folders are relative
#      to that home.)
#   3. Fails closed before launching: it plants a token in a probe domain in
#      the throwaway home and reads it back with the AppImage's OWN `defaults`
#      tool, in the same environment the launcher gives the app. If the
#      token does not come back, nothing is launched.
#   4. Records a checksum of every file in your real defaults folder(s), runs
#      the editor (Apply writes only into the throwaway home), and compares
#      afterwards. Any change is reported as a failure (exit 3).
#
# Your installed themes are still listed: GTS_HOST_THEME_ROOTS defaults to
# your real theme folders (read only). The throwaway folder is kept so you
# can look at what Apply wrote; its path is printed at the end. Delete it
# when done.
#
# Exit status: 0 = ran, real settings unchanged; 1 = setup failed;
# 2 = isolation not confirmed (nothing launched); 3 = real settings changed.
set -eu

die() { echo "try-isolated: $*" >&2; exit "${2:-1}"; }
[ $# -ge 1 ] || die "usage: $0 path/to/ThemeSettings-*.AppImage [app arguments...]"
img=$1; shift
[ -f "$img" ] || die "no such file: $img"
case "$img" in /*) ;; *) img="$(pwd)/$img" ;; esac

# Your real defaults folder(s): the usual one, plus whatever your own GNUstep
# configuration names, if gnustep-config is available.
real_home=${GNUSTEP_HOME:-$HOME}
reals="$real_home/GNUstep/Defaults"
if command -v gnustep-config >/dev/null 2>&1; then
  d=$(env -u GNUSTEP_HOME gnustep-config --variable=GNUSTEP_USER_DEFAULTS_DIR 2>/dev/null || true)
  case "$d" in
    "") ;;
    /*) [ "$d" = "$reals" ] || reals="$reals $d" ;;
    *)  [ "$real_home/$d" = "$reals" ] || reals="$reals $real_home/$d" ;;
  esac
fi

snapshot() {   # every regular file's checksum, outside the lock folder
  for r in $reals; do
    if [ -d "$r" ]; then
      echo "dir $r"
      (cd "$r" && find . -path ./.lck -prune -o -type f -print | LC_ALL=C sort | while IFS= read -r f; do
        sha256sum "$f"; done)
    else
      echo "absent $r"
    fi
  done
}

t=$(mktemp -d "${TMPDIR:-/tmp}/themesettings-try.XXXXXX") || die "no temp folder"
chmod 700 "$t"
t=$(cd "$t" && pwd -P)
case "$t" in "$real_home"/GNUstep|"$real_home"/GNUstep/*) die "temp folder $t is inside your GNUstep folder" ;; esac
mkdir -p "$t/home/GNUstep/Defaults"

echo "try-isolated: extracting the AppImage into $t"
(cd "$t" && "$img" --appimage-extract >/dev/null 2>&1) || die "could not extract $img"
x=$t/squashfs-root
[ -x "$x/AppRun" ] && [ -x "$x/usr/runtime/bin/defaults" ] && [ -r "$x/usr/runtime/etc/GNUstep/GNUstep.conf" ] \
  || die "unexpected AppImage layout (no AppRun, bundled defaults or GNUstep.conf)"

# The environment the app will get (the launcher adds the rest itself).
GNUSTEP_HOME=$t/home
GNUSTEP_USER_ROOT=$t/home/GNUstep
export GNUSTEP_HOME GNUSTEP_USER_ROOT
if [ -z "${GTS_HOST_THEME_ROOTS+x}" ]; then
  GTS_HOST_THEME_ROOTS="$real_home/GNUstep/Library/Themes:/usr/local/lib/GNUstep/Themes:/usr/lib/GNUstep/Themes:/usr/GNUstep/Local/Library/Themes:/usr/GNUstep/System/Library/Themes"
  export GTS_HOST_THEME_ROOTS
fi

# 3. Preflight: read a planted token with the AppImage's own defaults tool,
#    exactly as the launcher sets things up (bundled config, bundled libs).
token="isolated-$(date +%s)-$$"
probe=org.gnustep.themesettings.IsolationProbe
printf '{ Token = "%s"; }\n' "$token" > "$t/home/GNUstep/Defaults/$probe.plist"
got=$(GNUSTEP_CONFIG_FILE="$x/usr/runtime/etc/GNUstep/GNUstep.conf" \
      LD_LIBRARY_PATH="$x/usr/runtime/lib:$x/usr/runtime/System/Library/Libraries" \
      "$x/usr/runtime/bin/defaults" read "$probe" Token 2>/dev/null || true)
case "$got" in
  *"$token"*) echo "try-isolated: isolation confirmed: the app's defaults are in $t/home/GNUstep/Defaults" ;;
  *) die "isolation NOT confirmed (the AppImage's defaults tool did not read the throwaway home; got '${got:-nothing}'). Nothing was launched. Folder kept: $t" 2 ;;
esac
rm -f "$t/home/GNUstep/Defaults/$probe.plist"

before=$(snapshot)
echo "try-isolated: real settings checked: $reals"
echo "try-isolated: starting Theme Settings (close its window to finish)"
set +e
"$x/AppRun" "$@" 2>&1 | tee "$t/app.log"
set -e
after=$(snapshot)

grep -m1 'Defaults root:' "$t/app.log" | sed 's/.*\(Defaults root: [^ ]*\).*/try-isolated: app reported \1/' || true
if [ "$before" != "$after" ]; then
  echo "try-isolated: FAILED: your real GNUstep settings changed during the run:" >&2
  printf '%s\n' "$before" > "$t/real-before.txt"; printf '%s\n' "$after" > "$t/real-after.txt"
  diff "$t/real-before.txt" "$t/real-after.txt" >&2 || true
  echo "try-isolated: details in $t" >&2
  exit 3
fi
echo "try-isolated: your real GNUstep settings are unchanged."
echo "try-isolated: what Apply wrote is in $t/home/GNUstep/Defaults (delete $t when done)."
