#!/bin/sh
# Builds and runs the ThemeSettingsKit xctest bundle with GNUstep defaults
# isolated in a private scratch directory. Never touches ~/GNUstep/Defaults:
# the tests refuse to run unless the defaults root is under GTS_TEST_ROOT.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
base=${GTS_SCRATCH:-${TMPDIR:-/tmp}}
root=$(mktemp -d "$base/gts-test.XXXXXX")
chmod 700 "$root"
trap 'rm -rf "$root"' EXIT INT TERM
mkdir -p "$root/user/Defaults"
sysconf=${GTS_SYSTEM_CONF:-/etc/GNUstep/GNUstep.conf}
grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR=' "$sysconf" > "$root/GNUstep.conf" || true
cat >> "$root/GNUstep.conf" <<CONF
GNUSTEP_USER_CONFIG_FILE=$root/user.conf
GNUSTEP_USER_DEFAULTS_DIR=$root/user/Defaults
CONF
printf 'GNUSTEP_USER_DIR=%s\nGNUSTEP_USER_DEFAULTS_DIR=%s\n' "$root/user" "$root/user/Defaults" > "$root/user.conf"
chmod 600 "$root/GNUstep.conf" "$root/user.conf"
export GNUSTEP_CONFIG_FILE="$root/GNUstep.conf"
export GTS_TEST_ROOT="$root"
export GTS_EXAMPLES="$here/examples"
export LD_LIBRARY_PATH="$HOME/GNUstep/Library/Libraries${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
make -s -C "$here/Tests" messages=no >/dev/null
xctest=${XCTEST:-$HOME/GNUstep/Tools/xctest}
"$xctest" "$here/Tests/ThemeSettingsKitTests.bundle" "$@"
