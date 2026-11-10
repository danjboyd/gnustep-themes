#!/bin/sh
# Self-test for the harness itself (run-tests.sh lifecycle + in-process
# guard). Uses disposable fake "xctest" programs; never the real suite.
#   1. leader exits normally but leaves a descendant  -> descendant stopped,
#      exit status preserved, scratch root removed
#   2. TERM-resistant leader and descendant, runner gets TERM -> bounded
#      exit 143 via KILL escalation, nothing left
#   3. guard: test bundle started with a defaults root OUTSIDE GTS_TEST_ROOT
#      -> aborts (non-zero) with zero writes to that defaults root
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${GTS_SCRATCH:-${TMPDIR:-/tmp}}/gts-selftest.XXXXXX") || exit 1
work=$(cd "$work" && pwd -P)
pass=0; failn=0
ok()  { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*"; failn=$((failn + 1)); }

# Any process whose environment points GTS_TEST_ROOT into $work.
leftovers() {
  for p in $(ps -eo pid=); do
    { tr "\0" "\n" < "/proc/$p/environ"; } 2>/dev/null | grep -q "^GTS_TEST_ROOT=$work/" && echo "$p"
  done
}

mkfake() {   # name body
  printf '#!/bin/sh\n%s\n' "$2" > "$work/$1"; chmod +x "$work/$1"
}

# 1. normal exit leaving a descendant
mkfake linger 'sh -c "trap \"\" HUP; exec sleep 300" & exit 7'
start=$(date +%s)
GTS_SCRATCH="$work" XCTEST="$work/linger" "$here/scripts/run-tests.sh" >/dev/null 2>"$work/1.err"
st=$?
took=$(( $(date +%s) - start ))
[ "$st" -eq 7 ] && ok "1 status preserved ($st)" || bad "1 status $st (want 7)"
[ -z "$(leftovers)" ] && ok "1 lingering descendant stopped" || bad "1 leftovers: $(leftovers)"
[ -z "$(ls -d "$work"/gts-test.* 2>/dev/null)" ] && ok "1 scratch root removed" || bad "1 scratch root left"

# 2. TERM-resistant leader + descendant
mkfake stubborn 'trap "" TERM; sh -c "trap \"\" TERM; exec sleep 300" & while :; do sleep 1; done'
GTS_SCRATCH="$work" GTS_STOP_GRACE=2 XCTEST="$work/stubborn" "$here/scripts/run-tests.sh" >/dev/null 2>"$work/2.err" &
runner=$!
sleep 3
start=$(date +%s)
kill -TERM "$runner"
wait "$runner"; st=$?
took=$(( $(date +%s) - start ))
[ "$st" -eq 143 ] && ok "2 TERM status 143" || bad "2 status $st (want 143)"
[ "$took" -le 10 ] && ok "2 bounded exit (${took}s)" || bad "2 took ${took}s"
[ -z "$(leftovers)" ] && ok "2 nothing left after KILL escalation" || bad "2 leftovers: $(leftovers)"
[ -z "$(ls -d "$work"/gts-test.* 2>/dev/null)" ] && ok "2 scratch root removed" || bad "2 scratch root left"

# 3. guard aborts before any write when the defaults root is outside GTS_TEST_ROOT
mkdir -p "$work/A" "$work/B/user/Defaults"
grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR=' /etc/GNUstep/GNUstep.conf > "$work/B/GNUstep.conf"
printf 'GNUSTEP_USER_CONFIG_FILE=%s/B/user.conf\nGNUSTEP_USER_DEFAULTS_DIR=%s/B/user/Defaults\n' "$work" "$work" >> "$work/B/GNUstep.conf"
printf 'GNUSTEP_USER_DIR=%s/B/user\nGNUSTEP_USER_DEFAULTS_DIR=%s/B/user/Defaults\n' "$work" "$work" > "$work/B/user.conf"
chmod 600 "$work/B/GNUstep.conf" "$work/B/user.conf"
make -s -C "$here/Tests/RootProbe" messages=no >/dev/null 2>&1
make -s -C "$here/Tests" messages=no >/dev/null 2>&1
GNUSTEP_CONFIG_FILE="$work/B/GNUstep.conf" GTS_TEST_ROOT="$work/A" GTS_EXAMPLES="$here/examples" \
  GTS_ROOT_PROBE="$here/Tests/RootProbe/obj/gts-root-probe" GTS_VERIFIED_DEFAULTS_TOOL=/usr/bin/defaults \
  LD_LIBRARY_PATH="$HOME/GNUstep/Library/Libraries" \
  timeout 60 "$HOME/GNUstep/Tools/xctest" "$here/Tests/ThemeSettingsKitTests.bundle" >"$work/3.out" 2>&1
st=$?
[ "$st" -ne 0 ] && ok "3 guard aborted (status $st)" || bad "3 guard did not abort"
grep -q "REFUSING TO RUN" "$work/3.out" && ok "3 refusal reported" || bad "3 no refusal message"
# Known and reported: gnustep-base in the xctest host creates its lock
# directory (.lck) while starting up, before any test code (and so before
# the in-process guard) runs. That is why run-tests.sh verifies the root
# BEFORE launching xctest. What must never appear is defaults data.
extra=$(ls -A "$work/B/user/Defaults" | grep -vx '.lck')
data=$(find "$work/B/user/Defaults" -type f | head -5)
[ -z "$extra" ] && [ -z "$data" ] && ok "3 no defaults data written outside (lock dir only: $(ls -A "$work/B/user/Defaults" | tr '\n' ' '))" \
  || bad "3 data written: $extra $data"

rm -rf "$work"
echo "test-runner: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
