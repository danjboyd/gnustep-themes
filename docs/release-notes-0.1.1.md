# Theme Settings 0.1.1: release notes

Tag `v0.1.1`. A small follow-up to [0.1.0](release-notes-0.1.0.md). Checks
run at the tagged commit are recorded in
[release-checklist.md](release-checklist.md).

## What changed

- **AppImage launcher fix.** The AppImage is now built with gnustep-packager
  v0.1.11. Its launcher no longer prefixes the current folder to a
  command-line option value that contains "/" but doesn't start with it (in
  0.1.0, `-Key text/plain` arrived as `-Key $PWD/text/plain`). Such a value is
  left alone unless it names a folder that exists in the current folder.
  This was 0.1.0's only AppImage-specific known issue.
- **Docs** updated for the new packager pin and this release.

The editor, `ThemeSettingsKit`, schema v1 and the validator are unchanged
from 0.1.0. The library interface version stays 0.

## Known issues

- **Restart needed.** Most settings take effect when the application
  restarts. Each row says when its setting applies.
- **Interfaces may change.** The library interface version is 0, so
  `ThemeSettingsKit` interfaces may change before 1.0. Schema v1 is settled.
- **Window style.** The editor window always uses the plain GNUstep look,
  whichever theme you choose.
- **Themes need their settings file.** A theme shows settings only if its
  installed bundle includes `Resources/ThemeSettings.plist`. An Adwaita built
  from 0.1.0-alpha23 or earlier doesn't include it, so no Adwaita settings
  appear until Adwaita is rebuilt from a later version.

## Platforms

As in 0.1.0: Linux tested; Windows built and tested from source (file
defaults backend); macOS untested ([platforms.md](platforms.md)).

## Downloads

- Source: tag `v0.1.1`.
- `ThemeSettings-0.1.1-x86_64.AppImage`, attached to the GitHub release,
  with its sha256 in the release description.
