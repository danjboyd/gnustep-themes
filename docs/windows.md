# Windows: portability audit and build recipe (MSYS2 CLANG64)

Status: audited 2026-11-10; **first Windows build 2026-11-11** by winuitheme
at b9939d5 (see section 4). Statements still marked UNTESTED were not covered
by that run. Line numbers are valid at the commit that adds this document
unless noted. See also docs/platforms.md.

## 1. Audit (Kit, UI library, standalone app, validator)

| # | Where | Linux-only assumption | Status |
|---|---|---|---|
| 1 | `ThemeSettingsKit/GTSDefaultsDomainStore.m:6-9, 183-227` | POSIX `lstat`, `S_ISLNK`, `<sys/stat.h>`, and `access(R_OK\|X_OK)`. MinGW has no `lstat`/`S_ISLNK`, and the UCRT `_access` rejects `X_OK`, so **the Kit did not compile with MinGW**. | **Fixed:** the POSIX code is compiled only off Windows. On Windows, `classifyPath`/`canRead` are fail-closed stubs that are never reached, because editing is refused first (#2). |
| 2 | `GTSDefaultsDomainStore.m:170-177` | The exact-domain store assumes GNUstep's *file* defaults backend (`GSDefaultsRootForUser` at :156, a fresh `initWithUser:` at :231). On Windows, gnustep-base may use the registry. | Unchanged by design: `isBackendSupported` is NO on Windows, so every read/write fails with `GTSErrorUnsupportedBackend` and the editor shows targets as unreadable. Enabling needs the platforms.md Windows steps 1-3 on a Windows host. **UNTESTED.** |
| 3 | `GTSDefaultsDomainStore.m:160-168` | Domain names rejected only `/`. On Windows, `\` and `:` are also path syntax, so a crafted domain name could address a file outside the defaults directory. | **Fixed:** `\` is rejected everywhere, and `:` on Windows. Test: `testDomainNamesNeverContainPathSeparators`. |
| 4 | `GTSDefaultsDomainStore.m:516`, `GTSThemeCatalog.m:109-110`, `GTSThemeSettingsSchema.m:447-449` | Relative paths such as `Resources/Info-gnustep.plist` contain `/`. | OK: gnustep-base path methods accept `/` on Windows. Bundle layout is the same. |
| 5 | `GTSThemeCatalog.m:155`, `ThemeSettingsApp/main.m:29` | Theme and app discovery. | OK: `NSSearchPathForDirectoriesInDomains` (Library/Themes, Applications) works on any platform. Shadowing order on Windows layouts is **UNTESTED**. |
| 6 | `GTSThemeCatalog.m:248` | An explicit theme path in `GSTheme`. | OK: `isAbsolutePath` is gnustep-base's (drive letters and UNC paths). |
| 7 | `GTSSHA256.m:62-63`, `gts-config.make:4-7` | GnuTLS via `pkg-config`, file read with `fopen(..., "rb")`. | OK on MSYS2 if the GnuTLS package is installed. Without it the build warns and sidecar binding reports "check unavailable". Only AppImage sidecars use it, and those are Linux-only. |
| 8 | `GTSAppImageSidecar.m` | AppImage sidecars. | Linux-only feature by nature. It compiles everywhere; on Windows it simply has nothing to read. |
| 9 | `ThemeSettingsUI/GNUmakefile:14-16`, `ThemeSettingsKit/GNUmakefile:10` | Shared-library build. | OK in principle: gnustep-make on MinGW builds `obj/<lib>.dll` plus the import library `lib<lib>.dll.a` with `--export-all-symbols`, and our explicit `LIBRARIES_DEPEND_UPON` is exactly what a DLL needs (no undefined symbols). The DLL is installed to `GNUSTEP_TOOLS`, not `Libraries`. **UNTESTED.** |
| 10 | `ThemeSettingsKit/GTSThemeSettingsSchema.h:5-14`, `GTSThemeCatalog.h:10-18` | Exported data constants (`extern NSString * const GTS...`) used across a DLL boundary. | Left as is. MinGW ld/lld auto-import handles data imports, as gnustep-make's library.make notes ("usually not needed"). If the linker complains, mark them `__declspec(dllimport)` unless `BUILD_libThemeSettingsKit_DLL` is defined (gnustep-make defines that when building the DLL). **UNTESTED.** |
| 11 | `ThemeSettingsUI/GTSScreenshot.m:10` | Window capture via `NSBitmapImageRep initWithFocusedViewRect:`. | A review/test helper only, and not in the UI library. Backend-dependent (winlib); **UNTESTED**. |
| 12 | `Tests/GTSTestSupport.m:27-38` (`realpath`), `Tests/ExternalHost/main.m:6,24` (`dladdr`), `scripts/*.sh` (Xvfb, `/proc`, `setsid`, `ldd`, `LD_LIBRARY_PATH`) | Test harness and GUI scenarios. | Linux-only by design. The isolation recipe (`GNUSTEP_CONFIG_FILE`) is file-backend specific. A Windows harness would need its own isolation (see #2). Not ported. |
| 14 | `ThemeSettingsKit/GTSSHA256.m` (file open) | `fopen([path fileSystemRepresentation], ...)`: on Windows that representation is UTF-16, so `fopen` saw only the first character and every hash silently returned nil (found by the Windows build's only compiler warning). | **Fixed:** `_wfopen` on `_WIN32`. Hashing on Windows itself is **UNTESTED** (only AppImage sidecars use it). |
| 13 | `Tools/ValidateSchema/main.m` | Command-line validator. | Portable Foundation code (text plist parsing, no defaults access, no theme code). **The first thing to try on Windows.** |

No `dlopen`, no hard-coded `/usr` or `/home` paths, and no `.so` names
exist in the Kit, the UI library, the app or the validator. `.so` and
`LD_LIBRARY_PATH` appear only in the Linux test scripts and docs.

## 2. What works on Windows (verified 2026-11-11 at 2d1dd10, section 5.1)

* **Builds:** the Kit and UI libraries, the standalone app and the
  validator, with no warnings.
* **Validator:** fully functional.
* **Editor:** reads the file backend and shows the stored values, with
  every row read-only. As soon as a target opens, the message line says
  "this defaults backend is not supported for editing yet", and nothing is
  written. (At c39c935 it read nothing at all, because one gate guarded
  reads and writes; section 4 records that run.)

## 3. Build recipe for winuitheme (MSYS2 CLANG64)

Package names are to be confirmed on the machine; use whatever GNUstep
toolchain winuitheme already builds WinUITheme with. If GNUstep comes from
another prefix, source that prefix's `GNUstep.sh` instead.

```sh
# In an MSYS2 CLANG64 shell. GNUstep make/base/gui/back as already used for
# WinUITheme, plus:
pacman -S --needed mingw-w64-clang-x86_64-gnutls mingw-w64-clang-x86_64-pkgconf
. "$(gnustep-config --variable=GNUSTEP_MAKEFILES)/GNUstep.sh"
cd gnustep-themes        # a checkout at the commit named in the report

# 1. The validator: Foundation only, and touches no defaults.
make -C Tools/ValidateSchema
Tools/ValidateSchema/obj/gts-validate-schema path/to/WinUITheme.theme examples/*.theme
#    expect "0 error(s), 0 warning(s)" for each; exit status 0

# 2. The libraries (DLL + import library in each obj/)
make
ls ThemeSettingsKit/obj ThemeSettingsUI/obj   # expect *.dll and lib*.dll.a

# 3. The standalone app, pointed at the example themes
make -C ThemeSettingsApp
openapp ./ThemeSettingsApp/ThemeSettings.app -GTSExtraThemeRoot "$PWD/examples"
#    expect (section 5, pending rerun): themes and stored values shown, every
#    row read-only; a theme change is refused with "this defaults backend is
#    not supported for editing yet"; stderr shows the defaults root line
```

Do **not** run `make install` into a real GNUstep domain. To try the staged
libraries, use `make install DESTDIR=<scratch dir>
GNUSTEP_INSTALLATION_DOMAIN=LOCAL`. The DLLs land in the staged Tools
directory, which must be on `PATH` (the Windows equivalent of
`LD_LIBRARY_PATH`).

**Please report back:**
1. the exact commit;
2. compiler and linker warnings or errors, especially undefined or imported
   data symbols (#10);
3. validator output and exit status;
4. a screenshot of the app with a theme selected;
5. where gnustep-base keeps defaults on that machine (registry or files).
   For item 5, write a throwaway key to a throwaway domain with the
   `defaults` tool, look for it, then delete it. Do not touch real
   domains.

Item 5 is the input for enabling editing on Windows (platforms.md, Windows
steps 1-3). Editing stays disabled until then.

## 4. First Windows run (winuitheme, 2026-11-11, report #24772)

Windows 11 Home 26300, MSYS2 CLANG64, clang 21.1.8, gnustep-make 2.9.3,
base 1.31.1, gui 0.32.0, GnuTLS 3.8.12. Fresh clone at
b9939d568be30d49e7641e96dd4d1a2d4c4eed49; no `make install`.

* **Build:** the validator, both libraries (`ThemeSettingsKit-0.dll` and
  `ThemeSettingsUI-0.dll`, each with its `lib*.dll.a`) and ThemeSettings.app
  built with exit 0. The linker gave no undefined-symbol or data-import
  messages: the exported string constants (#10) link through auto-import.
  The only compiler warning was #14, now fixed.
* **Validator:** the three example themes give 0 errors and 0 warnings
  (exit 0). The real WinUITheme bundle reports "no ThemeSettings.plist in
  the bundle" (exit 1), which is expected: it doesn't ship one yet.
* **Defaults backend: files, not the registry.** A throwaway domain written
  with `defaults` appeared as `%USERPROFILE%\GNUstep\Defaults\<domain>.plist`
  (lock file `.lck`), and nothing appeared under `HKCU\Software\GNUstep`.
  This matches `GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults` in the MSYS2
  GNUstep.conf. It is the same file-per-domain layout as on Linux, and it
  is the input platforms.md needs for enabling editing.
* **Noise:** under an MSYS2 login whose POSIX user name differs from the
  Windows account, each run printed `NSHomeDirectoryForUser(agent) failed.`
  five times. Something resolves the home directory by user name. The
  store's `GSDefaultsRootForUser(NSUserName())` (#2) is a candidate, and
  it matters before editing is enabled.
* **App run (at c39c935, rebuilt with no warnings).** ThemeSettings.exe
  started in a private GNUstep home with the example themes and exited 0.
  The scripted theme change failed with "this defaults backend is not
  supported for editing yet". The screenshot shows the global target as
  "Unknown (settings could not be read)", Reload enabled, Apply and Cancel
  greyed, and nothing written. So the exported constants resolve at run
  time, and the refusal gate holds. The screenshot itself stays on the
  Windows host; it was not copied here.

**Since the read-only change (section 5), reading is enabled and editing
stays disabled.** What remains before editing on Windows:
1. a verified Windows write path (locking, atomic replace) and its tests
   on a Windows host;
2. a winuitheme rerun of the read-only change (section 5).

## 5. Read-only on Windows (verified at 74884ee, see 5.1)

Reads and writes now have separate gates in `GTSDefaultsDomainStore`.
The Windows rerun is in 5.1.

* `+isBackendReadable`: YES for the file backend on POSIX and Windows. NO
  for a registry configuration (`:REGISTRY:` in the defaults directory)
  and on Cygwin. When NO, reads fail as before.
* `+isBackendWritable`: NO on Windows. Every commit or removal fails with
  `GTSErrorUnsupportedBackend`, "this defaults backend is not supported for
  editing yet", before anything is loaded or written. `+isBackendSupported`
  now means the same as writable.
* The editor model shows the stored values with every row read-only, makes
  no theme or setting change, and the theme note says "Shown read-only:
  settings can be read on this system but not changed here yet".
* Windows file checks use `NSFileManager` (attributes with and without
  following links, readable and executable checks). The policy is the same
  as POSIX: only "does not exist" counts as absent; a dangling link or an
  odd file type is an error.
* **Defaults root.** It comes from `GSDefaultsRootForUser(NSUserName())`,
  the same call this process's `NSUserDefaults` uses, so the editor and the
  process can't disagree. For the current user gnustep-base takes the home
  from `GNUSTEP_HOME`, then `HOMEPATH`/`HOMEDRIVE` or `USERPROFILE`. It does
  not look up another user. The `NSHomeDirectoryForUser(agent) failed`
  noise (section 4) means those variables were empty. The root is then
  relative, and the store refuses any root that is not absolute.
* Diagnostics: `+defaultsRootDescription` gives the root, how it was found
  and the read/write state. The app and the demo log it at startup, and the
  script verb `log` prints it as `script: diagnostics: ...`.
* Linux evidence: `Tests/GTSReadOnlyBackendTests.m` forces "readable, not
  writable" with the store's test switch. The store reads but refuses
  commits and removals, nothing is written, the model shows values
  read-only, and the diagnostics name the isolated root. A negative control
  (the model ignoring the write gate) fails the model test.

### 5.1 Windows rerun at 74884ee (winuitheme, 2026-11-11, report #25867)

Windows 11 26300, MSYS2 CLANG64, run in a private GNUstep home (HOMEDRIVE
and HOMEPATH pointing at a temporary test home); no `make install`.

* **Build:** no compiler warnings, including the `_WIN32` `classifyPath`
  and `canRead`.
* **Defaults root:** the startup line named the private home's
  `GNUstep/Defaults`, "readable, NOT writable (read-only)". GNUstep writes
  the path with forward slashes.
* **Reads:** throwaway keys written with `defaults` into that home's
  NSGlobalDomain showed up: the Theme row read "WinUITheme", greyed out,
  "Set for all applications", with the read-only note. Apply and Cancel
  were greyed out.
* **Nothing written:** NSGlobalDomain.plist kept its size and timestamp
  through a refused theme change; only the `.lck` file was touched. The
  throwaway keys were deleted afterwards.
* **Gap, fixed after this run:** the message line was empty, because the
  theme popup is disabled and a refused change never reaches the model.
  The model now shows "this defaults backend is not supported for editing
  yet" as soon as it loads a target it cannot write to.
* **App fix:** the app's "Target:" label was selectable, so it took
  keyboard focus and the theme drew a text selection on it. It is now
  non-selectable.
* **Both fixes verified on Windows at 2d1dd10** (winuitheme #26214): `log`
  prints "this defaults backend is not supported for editing yet" right
  after launch, the status line shows it, and the "Target:" label is no
  longer highlighted under WinUITheme. The build had no warnings and the
  run had 0 failed steps.
