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

# The validator never needs the user's defaults, but gnustep-base opens the
# defaults database anyway (taking its lock). Give it a throwaway private
# one so the user's real ~/GNUstep/Defaults is never touched.
master=$(gnustep-config --variable=GNUSTEP_CONFIG_FILE 2>/dev/null || true)
[ -r "${master:-}" ] || master=/etc/GNUstep/GNUstep.conf
priv=$(mktemp -d "${TMPDIR:-/tmp}/gts-validate.XXXXXX") || { echo "$0: no temp dir" >&2; exit 2; }
trap 'rm -rf "$priv"' EXIT INT TERM
mkdir -p "$priv/user/Defaults" "$priv/home"
{ grep -v '^GNUSTEP_USER_CONFIG_FILE\|^GNUSTEP_USER_DEFAULTS_DIR\|^GNUSTEP_USER_DIR' "$master" 2>/dev/null || true
  printf 'GNUSTEP_USER_CONFIG_FILE=%s/none.conf\nGNUSTEP_USER_DEFAULTS_DIR=%s/user/Defaults\nGNUSTEP_USER_DIR_LIBRARY=%s/user/Library\n' "$priv" "$priv" "$priv"
} > "$priv/GNUstep.conf"
# gnustep-base silently IGNORES a config file others can write and falls
# back to the real one, so this must be owner-only.
chmod 700 "$priv"; chmod 600 "$priv/GNUstep.conf"
# Fail closed: refuse to run unless the private config is really in use.
root=$(GNUSTEP_CONFIG_FILE="$priv/GNUstep.conf" gnustep-config --variable=GNUSTEP_USER_DEFAULTS_DIR 2>/dev/null || true)
case "$root" in
  "$priv"/*) ;;
  *) echo "$0: could not isolate the validator's defaults (got '${root:-nothing}'); refusing to run" >&2; exit 2 ;;
esac
# gnustep-base ignores HOME; NSHomeDirectory() uses GNUSTEP_HOME, else passwd.
GNUSTEP_HOME="$priv/home" GNUSTEP_CONFIG_FILE="$priv/GNUstep.conf" "$tool" "$@"
