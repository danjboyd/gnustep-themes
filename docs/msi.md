# Windows MSI: first build (draft)

Status: 2026-11-16. The MSI build lives on the `msi-draft` branch
(`packaging/msi/`, `.github/workflows/package-msi.yml`), not on main.
Nothing has been released.

## The run

| | |
|---|---|
| Workflow | `package-msi`, run 43957467131, at `msi-draft` `16cfc94` (Dan's go: ask #7783) |
| Packager | gnustep-packager v0.1.11 (`a9d4e46`), MSI backend, MSYS2 CLANG64 toolchain from gnustep-cli-new |
| Output | `ThemeSettings-0.1.2-dev-win64.msi`, 35.5 MB, sha256 `bfca7bc9dd59f64ab044e234366cb67b482e1ba7ccee3f0d66d2a4b4051aec19`; a portable zip (36.7 MB; 338 files, 86 MB unpacked, 64 DLLs including GnuTLS) |
| Kept | 7-day workflow artifacts only |

## What the packager's checks proved

- **Build and staging:** ThemeSettings.exe built in CLANG64, with GnuTLS
  found. The runtime closure is complete: "Unresolved runtime dependencies:
  none".
- **Install:** the MSI installed per-user, to
  `%LOCALAPPDATA%\Theme Settings`, on a clean runner.
- **Launch:** the installed `ThemeSettings.exe` started with the build
  toolchain removed from PATH, and was still running after 5 seconds.
- **Uninstall:** the MSI uninstalled cleanly.

## Gaps (not yet checked)

- **The editor's own behaviour from the MSI:** listing themes, reading and
  saving defaults, the conflict check. The source build passed these on
  Windows 11 ([windows.md](windows.md) 6.1); the MSI build hasn't been
  through them. winuitheme could run section 6 against an installed MSI on
  its Windows host, with Dan's go (it installs software there).
- **Themes:** the MSI bundles none. Which theme folders it lists on Windows
  (the user's `GNUstep\Library\Themes`; WinUITheme installs) is not yet
  confirmed.
- **Not signed.** Windows SmartScreen will warn on first run.
- **No icon of its own:** GNUstep's icon, as in the AppImage.

## Proposal for 0.1.2

Merge `packaging/msi/` and the workflow into main (dropping the branch push
trigger), and attach the MSI to the Theme Settings 0.1.2 release next to
the AppImage, after the Windows check above. This would be part of the
0.1.2 release ask; nothing is published before Dan's go.
