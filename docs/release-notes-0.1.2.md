# Theme Settings 0.1.2: release notes (draft)

Draft, not released: nothing is tagged or published before Dan's go. Checks
run at the tagged commit will be recorded in
[release-checklist.md](release-checklist.md).

## What changed since 0.1.1

- **Windows installer (preview).** A per-user MSI for Windows x86_64, built
  by the manual `package-msi` workflow with gnustep-packager v0.1.11. It
  carries its own GNUstep runtime (MSYS2 CLANG64). What it has been checked
  for is in [msi.md](msi.md). It is not code-signed, so Windows SmartScreen
  warns on first run.
- **Debian packages.** `gnustep-clang-themesettings`, its libraries and a
  `-dev` package, for Debian trixie on amd64 and arm64, built with clang (user
  guide, "Install from apt"). They were first published at 0.1.1-1; a
  0.1.2 build is a separate step in that repository.
- **Docs.** The user guide's target heading names the defaults domain; a
  theme needs its own `ThemeSettings.plist` to show settings (Adwaita
  0.1.0-alpha24 and later); new sections on apt and Windows.

The editor, `ThemeSettingsKit`, schema v1 and the validator are unchanged
from 0.1.1. The library interface version stays 0.

## Known issues

- **Restart needed.** Most settings take effect when the application
  restarts. Each row says when its setting applies.
- **Interfaces may change.** The library interface version is 0.
- **Window style.** The editor window always uses the plain GNUstep look.
- **Themes need their settings file** (Adwaita alpha24 or later).
- **Windows MSI:** not signed; no icon of its own (GNUstep's); registry-backed
  defaults are shown read-only, as in a source build.

## Platforms

- Linux: tested (AppImage, Debian packages, source).
- Windows: built and tested from source; the MSI as recorded in msi.md.
- macOS: untested ([platforms.md](platforms.md)).

## Downloads

- Source: tag `v0.1.2`.
- `ThemeSettings-0.1.2-x86_64.AppImage` and `ThemeSettings-0.1.2-win64.msi`,
  attached to the GitHub release with their sha256 in the description.
