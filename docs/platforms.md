# Platform capabilities and boundaries

Status: 2026-11-10, written from evidence collected on **one** host
(Debian 13, gnustep-base 1.31.1, gnustep-gui 0.32.0, GCC
libobjc, GnuTLS 3.8.9). Anything not run there is marked **UNTESTED**.
Nothing in this document enables editing anywhere it is not already enabled.

## Summary

| Capability | Linux (Debian, base 1.31.1) | Windows (MSYS2) | macOS |
|---|---|---|---|
| Exact-domain read (fresh `NSUserDefaults` instance + file-backend preflight) | Tested (unit + two-process) | Works, read-only (verified at 2d1dd10, windows.md section 5) | UNTESTED; see note below |
| Exact-domain write (per-key merge, optimistic conflict check) | Tested; same-key race documented | Disabled (UnsupportedBackend); `isBackendWritable` = NO | UNTESTED |
| Fail-closed on unreadable/corrupt domain | Tested (mode 000, truncated plist, dir 000, dangling link, EACCES ancestor) | n/a (disabled) | UNTESTED |
| Defaults-store identity (`GSDefaultsRootForUser`) | Tested; isolation via `GNUSTEP_CONFIG_FILE` only (env `GNUSTEP_USER_CONFIG_FILE` ignored) | Files under `%USERPROFILE%\GNUstep\Defaults`, not the registry (verified, windows.md section 4); the startup diagnostics line names the root | UNTESTED |
| Theme discovery (search order user > local > network > system; shadowing) | Tested (synthetic roots) | UNTESTED (path layout differs) | UNTESTED |
| ThemeSettings.plist loading (no theme code loaded) | Tested | Expected to be portable Foundation code; UNTESTED | Same; UNTESTED |
| AppImage sidecar reading | Tested (stand-in artifacts); spec = packager main 776cb2e | n/a (AppImage is Linux-only) | n/a |
| SHA-256 for sidecar binding | GnuTLS via `gts-config.make` (explicit pkg-config detect + link) | GnuTLS is in MSYS2 CLANG64 and the code builds without warnings since the `_wfopen` fix (c39c935); hashing itself not exercised | UNTESTED; GnuTLS not assumed |
| AppKit editor rendering | Tested on private Xvfb, default GNUstep theme | UNTESTED | UNTESTED |

## Linux: what is established

* **Domain naming:** gnustep-base uses the main bundle's `CFBundleIdentifier`,
  else the process name (gnustep owner source review, base 6479d4483).
  `applicationIdentityForBundleAtPath:` reports whether the domain was read or
  guessed, and a guessed domain has to be confirmed by the user.
* **Reading:**
  - A dedicated, freshly created `NSUserDefaults` is used for every snapshot,
    because a long-lived instance kept serving stale foreign domains under the
    refresh paths we tried.
  - The file backend is checked first: only `ENOENT` means absent; any other
    error, an unreadable file, a corrupt file or a dangling link fails closed.
    base 1.31.1 reports such domains as *empty*, both empirically and from
    source.
* **Writing:**
  - `setPersistentDomain:forName:` + `-synchronize` writes only the changed
    keys (probed).
  - The conflict check is optimistic, not a compare-and-swap: a same-key
    write by another process inside the window is overwritten, and a test
    pins that.
  - Two separate outcomes. A `-synchronize` failure leaves the outcome
    unknown (`GTSErrorWriteFailed`; the edits stay staged). A save that
    succeeded but could not be re-read gives a receipt with `refreshFailed`
    (the edits are unstaged). Both set `needsRebase`, and further Applies
    are refused with `GTSErrorNeedsReload` until a successful rebase.
* **Live apply:** the supported design scope of `Apply = live` is a theme
  reacting inside its own process, as declared by the theme owner. That is a
  scope, not a result: no theme redraw has been demonstrated (the example
  themes are metadata only). No cross-process notification is posted, and
  propagation to other running apps is unproven.
* **Header/runtime pairing:** apps and tests are built against, and run on,
  the same Debian packages. A theme binary built for a different libs-gui
  (e.g. the NSTextAlignment renumbering the adwaita owner attributes to
  libs-gui 3237efda) is not detected. The editor states that compatibility
  is unknown and never infers it from names, ids or hashes.

## Windows (MSYS2): requirements before enabling

Audit, build recipe and Windows runs: docs/windows.md. Reading works on
Windows (read-only, verified at 2d1dd10); these steps are what remains
before editing there.

1. **Answered:** the MSYS2 gnustep-base keeps defaults as files under
   `%USERPROFILE%\GNUstep\Defaults`, not the registry (winuitheme #24772,
   windows.md section 4).
2. Implement a backend-specific preflight equivalent to the Linux one
   (absent vs unreadable vs corrupt), or keep the platform read-only. The
   file-layout check must not be reused blindly.
3. Repeat the two-process proof: per-key merge, stale caching, unreadable
   domain behaviour.
4. **Answered:** GnuTLS is available in MSYS2 CLANG64, and GTSSHA256 builds
   cleanly there since the `_wfopen` fix (c39c935). (Sidecars are
   AppImage-only, so hashing on Windows matters only if another packaging
   format adopts the same scheme.)
5. Theme search roots: confirm `NSSearchPathForDirectoriesInDomains` results
   and user-over-system shadowing on Windows layouts.
6. WinUITheme's native-dialog keys only do anything on Windows. The
   editor already shows the owner's help text; whether it applies there is
   not verified.
Until all of this is done: `isBackendSupported` returns NO on
`_WIN32`/`__MINGW32__`/`__CYGWIN__`, so every read and write fails with
`GTSErrorUnsupportedBackend`.

## macOS: requirements before enabling

* **Which Foundation:** GNUstep on macOS (gnustep-base) and Apple Foundation
  behave differently. Decide which one the editor targets, because Apple's
  `NSUserDefaults` uses cfprefsd and an exact-domain file write is wrong
  there.
* **With gnustep-base:** repeat the Linux proof; the file backend is
  expected but UNTESTED.
* **With Apple Foundation:** use `CFPreferences` per-app/any-app APIs and
  drop the file preflight. Never write the plist files directly.
* **Bundle layout:** `Contents/Resources/ThemeSettings.plist` is already
  accepted by the loader. Discovery roots: UNTESTED.
* **Hashing:** CommonCrypto would be the natural backend; it is not wired in.

## Not checked anywhere

- A running theme actually re-rendering after Apply.
- An app's own `standardUserDefaults` seeing an edit made by the in-app pane,
  beyond `-synchronize` being called.
- A real AppImage (only stand-in files were hashed), or AppImages whose
  GNUstep configuration selects another defaults store. The editor says
  values come from *this editor's* store.
- Locales other than English (ThemeSettings.strings lookup exists; no
  localized themes tested).
