#!/bin/sh
# Builds and runs the ThemeSettingsKit xctest bundle with GNUstep defaults
# isolated in a private scratch directory. Never touches ~/GNUstep/Defaults:
# before any test runs, this script and the tests both verify (read-only)
# that this runtime + config resolve the defaults root inside the scratch
# root, for the test process AND for child tools.
#
# Process ownership: xctest runs under setsid, so it and everything it
# spawns share a session id equal to its pid. A process is ours only if it
# is in that session AND its environment carries GTS_TEST_ROOT=<this root>.
# Only verified processes are signalled, individually; no group or
# name-based kill is used.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "run-tests: $*" >&2; exit 1; }

: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
base=${GTS_SCRATCH:-${TMPDIR:-/tmp}}
root=$(mktemp -d "$base/gts-test.XXXXXX") || fail "cannot create scratch root"
chmod 700 "$root"
root=$(cd "$root" && pwd -P)
sid=""
grace=${GTS_STOP_GRACE:-5}
unknown_file="$root/.unknown-pids"

# Identity of a process: "pid:starttime" (starttime = field 22 of
# /proc/<pid>/stat, so a recycled pid never matches an old record).
proc_start() { sed -n 's/^.*) [A-Za-z] \([^ ]* \)\{18\}\([0-9]*\).*/\2/p' "/proc/$1/stat" 2>/dev/null; }
proc_sid()   { sed -n 's/^.*) [A-Za-z] [0-9]* [0-9]* \([0-9]*\).*/\1/p' "/proc/$1/stat" 2>/dev/null; }
has_marker() { { tr '\0' '\n' < "/proc/$1/environ"; } 2>/dev/null | grep -qxF -- "GTS_TEST_ROOT=$root"; }
is_ours()    { [ "$(proc_sid "$1")" = "$sid" ] && has_marker "$1"; }

# Members of our session: verified ones as "pid:start" on stdout; members
# that cannot be verified are listed in $unknown_file (never signalled).
scan_session() {
  : > "$unknown_file"
  [ -n "$sid" ] || return 0
  ps -eo pid=,sid= | while read -r p s; do
    [ "$s" = "$sid" ] && [ "$p" != "$$" ] || continue
    st=$(proc_start "$p")
    [ -n "$st" ] || continue                     # already gone
    [ "$(sed -n 's/^.*) \([A-Za-z]\).*/\1/p' "/proc/$p/stat" 2>/dev/null)" = Z ] && continue   # exited, awaiting reap
    if has_marker "$p"; then echo "$p:$st"; else echo "$p" >> "$unknown_file"; fi
  done
}

# Signal only processes whose pid, start time, session and marker all
# still match the record taken earlier.
signal_verified() {   # SIG records...
  sig=$1; shift
  for rec in "$@"; do
    p=${rec%%:*}; st=${rec#*:}
    [ "$(proc_start "$p")" = "$st" ] && is_ours "$p" && kill "-$sig" "$p" 2>/dev/null || true
  done
}

wait_gone() {   # seconds
  n=$(( $1 * 10 ))
  while [ "$n" -gt 0 ]; do
    [ -z "$(scan_session)" ] && return 0
    sleep 0.1; n=$((n - 1))
  done
  [ -z "$(scan_session)" ]
}

# 0 = nothing of ours left and nothing unknown in the session; 1 otherwise.
stop_owned() {
  recs=$(scan_session)
  if [ -n "$recs" ]; then
    signal_verified TERM $recs
    if ! wait_gone "$grace"; then
      signal_verified KILL $(scan_session)
      wait_gone 2 || echo "run-tests: residual processes after KILL: $(scan_session | tr '\n' ' ')" >&2
    fi
  fi
  recs=$(scan_session)
  if [ -s "$unknown_file" ]; then
    echo "run-tests: unverifiable processes in the test session (not signalled): $(tr '\n' ' ' < "$unknown_file")" >&2
    return 1
  fi
  [ -z "$recs" ]
}

leader_exited() {   # reapable without blocking: gone or zombie
  [ -n "$sid" ] || return 1
  state=$(sed -n 's/^.*) \([A-Za-z]\).*/\1/p' "/proc/$sid/stat" 2>/dev/null)
  [ -z "$state" ] || [ "$state" = Z ]
}

finish() {
  status=$1
  trap '' INT TERM
  trap - EXIT
  clean=1
  stop_owned || clean=0
  if leader_exited; then wait "$sid" 2>/dev/null || true; fi
  if [ "$clean" -eq 1 ]; then
    if ! rm -rf "$root"; then
      echo "run-tests: could not remove $root" >&2
      [ "$status" -ne 0 ] || status=1
    fi
  else
    # Children may still use this config; deleting it could strand them.
    echo "run-tests: KEEPING $root because processes remain; remove it once they are gone" >&2
    [ "$status" -ne 0 ] || status=1
  fi
  exit "$status"
}
trap 'finish $?' EXIT
trap 'finish 130' INT
trap 'finish 143' TERM

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

# Build first (building writes no defaults), then verify, then run.
make -s -C "$here/Tests/RootProbe" messages=no >/dev/null || fail "root probe build failed"
make -s -C "$here/Tests" messages=no >/dev/null || fail "test build failed"
probe="$here/Tests/RootProbe/obj/gts-root-probe"
defaults_tool=${GTS_DEFAULTS_TOOL:-/usr/bin/defaults}

# Same gnustep-base for the probe and the defaults tool, or the probe proves
# nothing about the tool. Only the verified tool path is handed to the tests.
lib_of() { ldd "$1" | awk '/libgnustep-base/ { print $3 }'; }
plib=$(lib_of "$probe"); dlib=$(lib_of "$defaults_tool")
[ -n "$plib" ] && [ "$plib" = "$dlib" ] || fail "probe ($plib) and defaults tool ($dlib) use different gnustep-base"

resolved=$("$probe") || fail "root probe failed"
case "$resolved" in
  "$root"/*) ;;
  *) fail "defaults root $resolved is not inside $root; refusing to run" ;;
esac
echo "run-tests: defaults root $resolved (isolated; base $plib)"
export GTS_ROOT_PROBE="$probe"
export GTS_VERIFIED_DEFAULTS_TOOL="$defaults_tool"
unset GTS_DEFAULTS_TOOL

xctest=${XCTEST:-$HOME/GNUstep/Tools/xctest}
command -v setsid >/dev/null || fail "setsid is required to contain test child processes"
setsid "$xctest" "$here/Tests/ThemeSettingsKitTests.bundle" "$@" &
sid=$!
st=0
wait "$sid" || st=$?
# The leader is done; descendants it left behind are still ours to stop
# (finish does that), keyed on the session and our marker, not on the leader.
finish "$st"
