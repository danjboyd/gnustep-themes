#!/usr/bin/env bash
# gnustep-packager's stage step for the Windows MSI: ThemeSettings.app and the
# GNUstep runtime it needs, from the toolchain's CLANG64 tree. Adapted from
# tools-xctest's Examples/PackagedAppTests/packaging/stage.sh. Bundles no
# themes (see packaging/stage.sh). DRAFT: not yet run on a Windows runner.
#
#   packaging/msi/stage.sh [stage-root]   (default dist/stage)
set -euo pipefail

stage=${1:-dist/stage}
clang64=/clang64
runtime=$stage/runtime

rm -rf "$stage"
mkdir -p "$stage/app" "$runtime/bin" "$runtime/System/Library" \
  "$runtime/System/Tools" "$stage/metadata/licenses" "$stage/metadata/icons"

cp -R ThemeSettingsApp/ThemeSettings.app "$stage/app/"

for name in Bundles Images KeyBindings Fonts ColorPickers PostScript DTDs \
            Services Sounds; do
  if [ -d "$clang64/lib/GNUstep/$name" ]; then
    cp -R "$clang64/lib/GNUstep/$name" "$runtime/System/Library/"
  fi
done
if [ -d "$clang64/etc/fonts" ]; then
  mkdir -p "$runtime/etc"
  cp -R "$clang64/etc/fonts" "$runtime/etc/"
fi

for tool in gdnc.exe gpbs.exe make_services.exe; do
  cp "$clang64/bin/$tool" "$runtime/System/Tools/"
done
cp "$clang64/bin/defaults.exe" "$runtime/bin/"

# DLL closure: everything staged imports, recursively; names not in CLANG64
# are Windows' own (gnustep-packager's closure check catches misses).
queue=()
while IFS= read -r -d '' file; do
  queue+=("$file")
done < <(find "$stage" -type f \( -iname '*.exe' -o -iname '*.dll' \) -print0)
declare -A seen=()
i=0
while [ "$i" -lt "${#queue[@]}" ]; do
  file=${queue[$i]}
  i=$((i + 1))
  [ -n "${seen[$file]:-}" ] && continue
  seen[$file]=1
  while IFS= read -r dll; do
    dll=${dll%$'\r'}
    if [ -f "$clang64/bin/$dll" ] && [ ! -f "$runtime/bin/$dll" ]; then
      cp "$clang64/bin/$dll" "$runtime/bin/"
      queue+=("$runtime/bin/$dll")
    fi
  done < <(llvm-objdump -p "$file" | sed -n 's/^ *DLL Name: *//p')
done

# Every GNUstep domain except the user's points into the package, so the
# user's own defaults and ~/GNUstep/Library/Themes are what get edited/listed.
cat > "$runtime/bin/GNUstep.conf" <<'CONF'
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_SYSTEM_ROOT=../System
GNUSTEP_LOCAL_ROOT=../System
GNUSTEP_NETWORK_ROOT=../System
GNUSTEP_SYSTEM_LIBRARY=../System/Library
GNUSTEP_SYSTEM_TOOLS=../System/Tools
GNUSTEP_NETWORK_LIBRARY=../System/Library
GNUSTEP_NETWORK_TOOLS=../System/Tools
GNUSTEP_LOCAL_LIBRARY=../lib/GNUstep
GNUSTEP_LOCAL_TOOLS=../System/Tools
CONF

cat > "$stage/metadata/licenses/gnustep-runtime.txt" <<'TXT'
This package includes the GNUstep Base and GUI libraries, and GnuTLS, under
the GNU Lesser General Public License, version 2.1 or later:
https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
TXT

# Icon: GNUstep's own, as in the AppImage, if ImageMagick is available.
icon=$(find "$runtime/System/Library/Images" -iname 'GNUstep.tiff' | head -n 1)
if [ -n "$icon" ] && command -v magick >/dev/null 2>&1; then
  magick "$icon[0]" -resize 256x256 "$stage/metadata/icons/ThemeSettings.png"
fi
