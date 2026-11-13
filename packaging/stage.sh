#!/bin/sh
# Stage step for gnustep-packager: lays out dist/stage as app/, runtime/ and
# metadata/. Adapted from gnustep-packager's
# examples/downstream/theme-demos/adwaita/stage-theme-demo.sh (MIT).
# Bundles NO themes: the editor edits settings for the host's themes, which
# it reads as data only (GTS_HOST_THEME_ROOTS in the manifest), and the
# AppImage launches it with -GSTheme GNUstep so it never loads host theme code
# into the bundled runtime.
set -eu
stage_root="${1:-dist/stage}"
app_stage="$stage_root/app/ThemeSettings.app"
runtime_root="$stage_root/runtime"

rm -rf "$stage_root"
mkdir -p "$stage_root/app" "$runtime_root/lib" \
  "$stage_root/metadata/icons" "$stage_root/metadata/licenses"
cp -a ThemeSettingsApp/ThemeSettings.app "$stage_root/app/"

system_library=$(gnustep-config --variable=GNUSTEP_SYSTEM_LIBRARY)
mkdir -p "$runtime_root/System"
cp -a "$system_library" "$runtime_root/System/Library"
local_library=$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARY)
if [ "$local_library" != "$system_library" ] &&
   ls "$local_library"/Libraries/libgnustep-base.so* >/dev/null 2>&1; then
  cp -a "$local_library/." "$runtime_root/System/Library/"
fi
rm -rf "$runtime_root/System/Library/Makefiles" \
  "$runtime_root/System/Library/Themes" \
  "$runtime_root/System/Library/Headers"

system_tools=$(gnustep-config --variable=GNUSTEP_SYSTEM_TOOLS)
mkdir -p "$runtime_root/System/Tools" "$runtime_root/bin"
system_tool() {
  if [ -x "$system_tools/$1" ]; then printf '%s\n' "$system_tools/$1"
  elif command -v "$1" >/dev/null 2>&1; then command -v "$1"
  else printf 'GNUstep tool %s not found\n' "$1" >&2; return 1; fi
}
for tool in gdnc gpbs make_services; do
  cp -L "$(system_tool "$tool")" "$runtime_root/System/Tools/$tool"
done
cp -L "$(system_tool defaults)" "$runtime_root/bin/defaults"

# Shared libraries the app, bundles and tools need (not the C library).
find "$app_stage" "$runtime_root/System/Library/Bundles" "$runtime_root/System/Tools" "$runtime_root/bin" -type f \
    -exec sh -c 'file -b "$1" | grep -q "^ELF" && printf "%s\n" "$1"' _ {} \; |
  while IFS= read -r elf; do
    ldd "$elf" 2>/dev/null | awk '$2 == "=>" && $3 ~ /^\// { print $3 }'
  done | sort -u | while IFS= read -r library; do
    case "$(basename "$library")" in
      libc.so.*|libdl.so.*|libm.so.*|libpthread.so.*|librt.so.*|ld-linux-*) continue ;;
    esac
    cp -L "$library" "$runtime_root/lib/"
  done

# Icon: GNUstep's own, until the app has one.
gnustep_icon=$(find "$runtime_root/System/Library/Images" -name 'GNUstep.tiff' | head -n 1)
[ -n "$gnustep_icon" ] || { echo "no GNUstep.tiff for the icon" >&2; exit 1; }
page=$(identify -format '%p %w\n' "$gnustep_icon" 2>/dev/null | sort -k2 -n | tail -n 1 | cut -d' ' -f1)
convert "$gnustep_icon[${page:-0}]" -resize 256x256 "$stage_root/metadata/icons/ThemeSettings.png"

cp COPYING "$stage_root/metadata/licenses/gnustep-runtime.txt"
