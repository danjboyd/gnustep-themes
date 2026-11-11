#!/bin/sh
# ci.sh - what CI runs (.github/workflows/ci.yml), also runnable locally.
# Needs gnustep-make/base/gui development packages, GnuTLS headers and
# pkg-config. Builds XCTest (gnustep/tools-xctest at a pinned commit) into a
# private stage unless XCTEST_PREFIX already points at an install, then
# builds everything and runs the unit tests and the schema validator.
# No GUI and no display: the GUI scenarios (scripts/screenshots.sh) need
# Xvfb and are not part of CI.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
work=${GTS_CI_WORK:-$here/.ci}
XCTEST_REPO=${XCTEST_REPO:-https://github.com/gnustep/tools-xctest.git}
XCTEST_REV=${XCTEST_REV:-2aac3e5fc65586bda718aaca7d36b5c33b5ec2e3}
XCTEST_CC=${XCTEST_CC:-clang}
XCTEST_OBJCFLAGS=${XCTEST_OBJCFLAGS:--fobjc-runtime=gcc -I$(gcc -print-file-name=include)}

step() { echo "::group::$*" 2>/dev/null; echo "== ci: $*"; }
done_step() { echo "::endgroup::"; }
fail() { echo "ci: $*" >&2; exit 1; }

: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
mkdir -p "$work"

step "XCTest"
if [ -z "${XCTEST_PREFIX:-}" ]; then
  stage="$work/xctest-stage"
  if [ ! -x "$stage/prefix/Tools/xctest" ]; then
    rm -rf "$work/tools-xctest" "$stage"
    git clone -q "$XCTEST_REPO" "$work/tools-xctest"
    git -C "$work/tools-xctest" checkout -q "$XCTEST_REV"
    # tools-xctest uses @autoreleasepool, which GCC's Objective-C lacks;
    # build it with clang against the same (GCC) runtime, as the local
    # toolchain does. Our own code stays on the default compiler.
    make -s -C "$work/tools-xctest" messages=no CC="$XCTEST_CC" \
      ADDITIONAL_OBJCFLAGS="$XCTEST_OBJCFLAGS"
    # Install below the stage only (DESTDIR + LOCAL domain, as in the
    # installed-library check), never into a real GNUstep domain.
    make -s -C "$work/tools-xctest" install messages=no DESTDIR="$stage/root" \
      GNUSTEP_INSTALLATION_DOMAIN=LOCAL CC="$XCTEST_CC" ADDITIONAL_OBJCFLAGS="$XCTEST_OBJCFLAGS"
    # Present the staged files in the Tools / Library/{Libraries,Headers}
    # layout that Tests/GNUmakefile and run-tests.sh expect.
    mkdir -p "$stage/prefix/Library"
    ln -s "$stage/root$(gnustep-config --variable=GNUSTEP_LOCAL_TOOLS)" "$stage/prefix/Tools"
    ln -s "$stage/root$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)" "$stage/prefix/Library/Libraries"
    ln -s "$stage/root$(gnustep-config --variable=GNUSTEP_LOCAL_HEADERS)" "$stage/prefix/Library/Headers"
  fi
  XCTEST_PREFIX="$stage/prefix"
fi
export XCTEST_PREFIX
[ -x "$XCTEST_PREFIX/Tools/xctest" ] || fail "no xctest under $XCTEST_PREFIX"
echo "xctest: $XCTEST_PREFIX/Tools/xctest (tools-xctest $XCTEST_REV)"
done_step

step "Build"
make -s -C "$here" messages=no
for d in ThemeSettingsApp ThemeSettingsDemo Tools/ValidateSchema Tests/HostCheck; do
  make -s -C "$here/$d" messages=no
done
done_step

step "Unit tests"
log="$work/unit.log"
"$here/scripts/run-tests.sh" >"$log" 2>&1 || { cat "$log"; fail "unit tests failed"; }
grep -E "XCTest: +[A-Za-z]+Tests: [0-9]+ tests" "$log" || true
total=$(grep -E "XCTest: +[A-Za-z]+Tests: [0-9]+ tests PASSED" "$log" | awk '{s += $(NF-2)} END {print s+0}')
failed=$(grep -cE "tests FAILED|: error:" "$log" || true)
echo "unit tests passed: $total; failure lines: $failed"
[ "$failed" -eq 0 ] && [ "$total" -gt 0 ] || { cat "$log"; fail "unit test failures"; }
[ -z "${GTS_CI_MIN_TESTS:-}" ] || [ "$total" -ge "$GTS_CI_MIN_TESTS" ] || fail "only $total tests ran (expected >= $GTS_CI_MIN_TESTS)"
done_step

step "Schema validator"
"$here/scripts/validate-theme.sh" "$here"/examples/*.theme "$here/Tests/Fixtures/Schema/good.plist"
if "$here/scripts/validate-theme.sh" -q "$here"/Tests/Fixtures/Schema/bad-*.plist >/dev/null; then
  fail "validator accepted the bad fixtures"
fi
echo "bad fixtures rejected (exit 1), as expected"
done_step

echo "== ci: all steps passed"
