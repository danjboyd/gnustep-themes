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

## Gaps

- **Themes:** the MSI bundles none. It lists the user's
  `GNUstep\Library\Themes` (checked on Windows, below).
- **Launcher output.** The top-level `ThemeSettings.exe` is the packager's
  launcher: it starts the app detached and exits, so nothing reaches its
  stdout or stderr. Arguments do pass through.
- **Not signed.** Windows SmartScreen will warn on first run.
- **No icon of its own:** GNUstep's icon, as in the AppImage.

## Windows check of the installed MSI (for winuitheme; needs Dan's go)

Passed 7 of 7 on 2026-11-17 (results below). Installing the MSI puts
software on the Windows host, so winuitheme runs this only after Dan says
yes. Use the workflow artifact of the build being checked, and check its
sha256 first.

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
3. **Startup line.** The top-level `ThemeSettings.exe` is a launcher that
   detaches, so for steps 3-5 start `app\ThemeSettings.app\ThemeSettings.exe`
   directly with the launcher's environment (`runtime\bin` first on PATH,
   `GNUSTEP_PATHPREFIX_LIST=<install>\runtime`, `-GSTheme GNUstep`), so
   stderr is visible. The defaults-root line names the private home and
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

### Results (winuitheme, 2026-11-17)

MSI from `package-msi` run 44136582495 at `f363602`, sha256 `999ed99b…7a182`;
Windows 11 build 26300, MSYS2 off PATH.

| Step | Result |
|---|---|
| 1. Install | PASS: exit 0, no administrator prompt; `%LOCALAPPDATA%\Theme Settings\` and the Start menu shortcut |
| 2. Isolate | PASS: before each of 6 launches, the MSI's `defaults.exe` read a marker domain that exists only in the private home |
| 3. Startup line | PASS: private `GNUstep/Defaults`, "readable, writable" |
| 4. Themes | PASS: Adwaita, Gumdrop and WinUITheme from the private `Library\Themes`; an unknown theme refused; no other folders listed |
| 5. Write, remove, conflict | PASS, as in [windows.md](windows.md) 6.1; `.lck` empty and no partial file each time |
| 6. Shortcut | PASS: opened from the isolated shell, plain GNUstep look, closed cleanly |
| 7. Uninstall | PASS: exit 0; folder, shortcut and uninstall entry gone |

The real `%USERPROFILE%\GNUstep\Defaults` (names, sizes, timestamps) and
`HKCU\Software\GNUstep` (absent) were unchanged from before step 1 to
after step 7. As any GNUstep app does, Theme Settings saves its own window
state in its own domain (`org.gnustep.ThemeSettings`); in normal use that
goes to the user's real defaults.

## Proposal for 0.1.2

With `packaging/msi/` and the manual workflow on main, attach the MSI to
the Theme Settings 0.1.2 release next to the AppImage, after the Windows
check above. This would be part of the 0.1.2 release ask; nothing is
published before Dan's go.
