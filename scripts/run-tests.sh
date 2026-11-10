#!/bin/sh
# Builds and runs the ThemeSettingsKit xctest bundle with GNUstep defaults
# isolated in a private scratch directory. Never touches ~/GNUstep/Defaults:
# before any test runs, this script and the tests both verify (read-only)
# that this runtime + config resolve the defaults root inside the scratch
# root, for the test process AND for child tools.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "run-tests: $*" >&2; exit 1; }

: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
base=${GTS_SCRATCH:-${TMPDIR:-/tmp}}
root=$(mktemp -d "$base/gts-test.XXXXXX") || fail "cannot create scratch root"
chmod 700 "$root"
root=$(cd "$root" && pwd -P)
child=""

cleanup() {
  status=$1
  if [ -n "$child" ]; then
    # xctest runs in its own process group (setsid): stop it and every
    # defaults tool it spawned before their scratch config disappears.
    kill -TERM -- "-$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    kill -KILL -- "-$child" 2>/dev/null || true
  fi
  rm -rf "$root"
  exit "$status"
}
trap 'cleanup $?' EXIT
trap 'trap - EXIT; cleanup 130' INT
trap 'trap - EXIT; cleanup 143' TERM

sysconf=${GTS_SYSTEM_CONF:-/etc/GNUstep/GNUstep.conf}
[ -r "$sysconf" ] || fail "master config $sysconf is not readable"
mkdir -p "$root/user/Defaults"
# grep: 0 = lines kept, 1 = nothing left (acceptable), >1 = read error.
rc=0
grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR=' \
  "$sysconf" > "$root/GNUstep.conf" || rc=$?
[ "$rc" -le 1 ] || fail "could not read $sysconf (grep status $rc)"
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

make -s -C "$here/Tests/RootProbe" messages=no >/dev/null || fail "root probe build failed"
probe="$here/Tests/RootProbe/obj/gts-root-probe"
export GTS_ROOT_PROBE="$probe"
defaults_tool=${GTS_DEFAULTS_TOOL:-/usr/bin/defaults}

# Same gnustep-base for the probe and the defaults tool, or the probe proves
# nothing about the tool.
lib_of() { ldd "$1" | awk '/libgnustep-base/ { print $3 }'; }
plib=$(lib_of "$probe"); dlib=$(lib_of "$defaults_tool")
[ -n "$plib" ] && [ "$plib" = "$dlib" ] || fail "probe ($plib) and defaults tool ($dlib) use different gnustep-base"

resolved=$("$probe") || fail "root probe failed"
case "$resolved" in
  "$root"/*) ;;
  *) fail "defaults root $resolved is not inside $root; refusing to run" ;;
esac
echo "run-tests: defaults root $resolved (isolated; base $plib)"

make -s -C "$here/Tests" messages=no >/dev/null || fail "test build failed"
xctest=${XCTEST:-$HOME/GNUstep/Tools/xctest}
command -v setsid >/dev/null || fail "setsid is required to contain test child processes"
setsid "$xctest" "$here/Tests/ThemeSettingsKitTests.bundle" "$@" &
child=$!
wait "$child"
st=$?
child=""
exit "$st"
