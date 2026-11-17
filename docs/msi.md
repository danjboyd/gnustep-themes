# Windows MSI: first build (draft)

Status: 2026-11-16. The MSI build is in `packaging/msi/` and the manual
`package-msi` workflow (`.github/workflows/package-msi.yml`). Nothing has
been released.

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
  through them. The steps for winuitheme are in "Windows check of the
  installed MSI" below; running them needs Dan's go (it installs software).
- **Themes:** the MSI bundles none. Which theme folders it lists on Windows
  (the user's `GNUstep\Library\Themes`; WinUITheme installs) is not yet
  confirmed.
- **Not signed.** Windows SmartScreen will warn on first run.
- **No icon of its own:** GNUstep's icon, as in the AppImage.

## Windows check of the installed MSI (for winuitheme; needs Dan's go)

Not run yet. Installing the MSI puts software on the Windows host, so
winuitheme runs this only after Dan says yes. Use the workflow artifact
named above, and check its sha256 first.

1. **Install** `ThemeSettings-*-win64.msi` per-user
   (`msiexec /i <file> /qn /l*v install.log`). Expect
   `%LOCALAPPDATA%\Theme Settings\` with `ThemeSettings.exe` and a Start
   menu shortcut named "Theme Settings", and no administrator prompt.
2. **Isolate before every launch**, as in [windows.md](windows.md) 6.1:
   `HOMEDRIVE`/`HOMEPATH`, `GNUSTEP_HOME` and `GNUSTEP_USER_ROOT` point at a
   private home, with `GNUSTEP_CONFIG_FILE` and `GNUSTEP_PATHLIST` unset.
   Run the MSI's own `runtime\bin\defaults.exe` with that environment and
   confirm it reads the private `GNUstep\Defaults`; stop if it doesn't. The
   MSI carries its own `runtime\bin\GNUstep.conf`, so this probe is what
   proves the isolation, not the variables alone. Record the real
   `GNUstep\Defaults` and `HKCU\Software\GNUstep` before and after.
3. **Startup line.** Start the installed `ThemeSettings.exe` from a shell
   so stderr is visible. The defaults-root line names the private home and
   ends "readable, writable".
4. **Themes listed.** Copy `examples/*.theme` into the private home's
   `GNUstep\Library\Themes`. All three appear in the Theme menu. Note any
   other folders listed (an installed WinUITheme, the MSI's own runtime).
5. **Section 6, steps 2-4,** against the installed app, driven with
   `-GTSScript` on a throwaway domain (DemoNotes, as in 6.1): write, remove,
   conflict. Same pass criteria as 6.1.
6. **Shortcut launch.** Start it once from the Start menu shortcut and close
   it; it opens with the plain GNUstep look.
7. **Uninstall** (`msiexec /x <file> /qn`). `%LOCALAPPDATA%\Theme Settings`
   and the shortcut are gone. The real defaults and registry are unchanged
   from step 2.

Report: the MSI's sha256, Windows build, each step's result, and the
before/after comparison from step 2.

## Proposal for 0.1.2

With `packaging/msi/` and the manual workflow on main, attach the MSI to
the Theme Settings 0.1.2 release next to the AppImage, after the Windows
check above. This would be part of the 0.1.2 release ask; nothing is
published before Dan's go.
