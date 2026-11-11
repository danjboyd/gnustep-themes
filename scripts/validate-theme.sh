#!/bin/sh
# validate-theme.sh - check ThemeSettings.plist files (schema v1) for theme
# owners and CI. Builds the validator from this checkout if needed, then runs
# it on every argument (a .theme bundle or a .plist file).
#
#   scripts/validate-theme.sh [-q] path/to/My.theme [more.theme|file.plist ...]
#
# Exit status: 0 = no errors (warnings allowed), 1 = at least one error,
# 2 = usage or build problem. Touches no defaults and loads no theme code.
set -eu

here=$(cd "$(dirname "$0")/.." && pwd)
tool="$here/Tools/ValidateSchema/obj/gts-validate-schema"

if [ $# -eq 0 ]; then
  echo "usage: $0 [-q] <Theme.theme|ThemeSettings.plist>..." >&2
  exit 2
fi

if [ -z "${GNUSTEP_MAKEFILES:-}" ]; then
  GNUSTEP_MAKEFILES=$(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null) || {
    echo "$0: gnustep-config not found; source GNUstep.sh first" >&2; exit 2; }
  export GNUSTEP_MAKEFILES
fi

# Rebuild whenever a source is newer than the tool (make decides).
if ! make -s -C "$here/Tools/ValidateSchema" >/dev/null 2>"${TMPDIR:-/tmp}/gts-validate-build.$$"; then
  cat "${TMPDIR:-/tmp}/gts-validate-build.$$" >&2
  rm -f "${TMPDIR:-/tmp}/gts-validate-build.$$"
  echo "$0: building the validator failed" >&2
  exit 2
fi
rm -f "${TMPDIR:-/tmp}/gts-validate-build.$$"

exec "$tool" "$@"
