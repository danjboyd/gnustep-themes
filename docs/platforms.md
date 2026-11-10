# Platform capabilities and boundaries

Status: 2026-11-10, written from evidence collected on **one** host
(iep-platform, Debian 13, gnustep-base 1.31.1, gnustep-gui 0.32.0, GCC
libobjc, GnuTLS 3.8.9). Anything not run there is marked **UNTESTED**.
Nothing in this document enables editing anywhere it is not already enabled.

## Summary

| Capability | Linux (Debian, base 1.31.1) | Windows (MSYS2) | macOS |
|---|---|---|---|
| Exact-domain read (fresh `NSUserDefaults` instance + file-backend preflight) | Tested (unit + two-process) | UNTESTED; store refuses: `isBackendSupported` = NO | UNTESTED; see note below |
| Exact-domain write (per-key merge, optimistic conflict check) | Tested; same-key race documented | Disabled (UnsupportedBackend) | UNTESTED |
| Fail-closed on unreadable/corrupt domain | Tested (mode 000, truncated plist, dir 000, dangling link, EACCES ancestor) | n/a (disabled) | UNTESTED |
| Defaults-store identity (`GSDefaultsRootForUser`) | Tested; isolation via `GNUSTEP_CONFIG_FILE` only (env `GNUSTEP_USER_CONFIG_FILE` ignored) | UNTESTED; base may use the registry | UNTESTED |
| Theme discovery (search order user > local > network > system; shadowing) | Tested (synthetic roots) | UNTESTED (path layout differs) | UNTESTED |
| ThemeSettings.plist loading (no theme code loaded) | Tested | Expected to be portable Foundation code; UNTESTED | Same; UNTESTED |
| AppImage sidecar reading | Tested (stand-in artifacts); spec = packager main 776cb2e | n/a (AppImage is Linux-only) | n/a |
| SHA-256 for sidecar binding | GnuTLS via `gts-config.make` (explicit pkg-config detect + link) | UNTESTED; GnuTLS availability in the MSYS2 base not checked | UNTESTED; GnuTLS not assumed |
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
  - A `-synchronize` failure means the outcome is unknown. The edit session
    then requires a reload before any further Apply (`GTSErrorNeedsReload`).
* **Live apply:** `Apply = live` only describes what a theme does *in its
  own process*. No cross-process notification is posted, and propagation to
  other running apps is unproven.
* **Header/runtime pairing:** apps and tests are built against, and run on,
  the same Debian packages. A theme binary built for a different libs-gui
  (e.g. the NSTextAlignment renumbering the adwaita owner attributes to
  libs-gui 3237efda) is not detected. The editor states that compatibility
  is unknown and never infers it from names, ids or hashes.

## Windows (MSYS2): requirements before enabling

1. Find out which defaults backend the target gnustep-base build uses:
   the registry, or files under the user's GNUstep defaults directory. Do this
   from source and from a sandboxed test on a Windows runner.
2. Implement a backend-specific preflight equivalent to the Linux one
   (absent vs unreadable vs corrupt), or keep the platform read-only. The
   file-layout check must not be reused blindly.
3. Repeat the two-process proof: per-key merge, stale caching, unreadable
   domain behaviour.
4. Pick the SHA-256 backend: GnuTLS if the MSYS2 base carries it, or
   Windows CNG. Detect it explicitly. The binding stays "unchecked" while
   none is available. (Sidecars are AppImage-only, so this matters only if
   another packaging format adopts the same scheme.)
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
