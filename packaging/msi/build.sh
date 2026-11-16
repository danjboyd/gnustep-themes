#!/usr/bin/env bash
# gnustep-packager's build step for the Windows MSI (packaging/msi/
# package.manifest.json), in the msys2-bash (CLANG64) shell of the
# gnustep-cli-new toolchain. Builds the standalone editor with the Kit and UI
# sources compiled in, as packaging/build.sh does on Linux. DRAFT: not yet
# run on a Windows runner.
set -euo pipefail

if [ -z "${GNUSTEP_MAKEFILES:-}" ]; then
  GNUSTEP_MAKEFILES=$(gnustep-config --variable=GNUSTEP_MAKEFILES)
fi
GNUSTEP_MAKEFILES=$(cygpath -u "$GNUSTEP_MAKEFILES")
set +u
. "$GNUSTEP_MAKEFILES/GNUstep.sh"
set -u

# MSYS2's libdispatch headers define mode_t unless HAVE_MODE_T is set (as in
# tools-xctest's packaged example).
export ADDITIONAL_CPPFLAGS="${ADDITIONAL_CPPFLAGS:-} -DHAVE_MODE_T"

# GnuTLS (SHA-256 for AppImage sidecars) comes from the workflow's
# msys2-packages; without it the build warns and only that check is off.
pkg-config --exists gnutls || echo "build.sh: GnuTLS not found; sidecar checks will be unavailable" >&2

make -C ThemeSettingsApp
test -f ThemeSettingsApp/ThemeSettings.app/ThemeSettings.exe
