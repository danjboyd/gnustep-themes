# Embedding the theme settings editor, and a SystemPreferences plan

Status: 2026-11-10, against local HEAD (see docs/module-map.md). This is a
plan: nothing here is implemented in SystemPreferences, and no existing
pane is replaced or migrated.

## 1. Embedding `GTSThemeSettingsEditor` in an app (in-app pane)

`ThemeSettingsDemo/main.m` already does this (DemoNotes). The rules:

**Ownership**

| Piece | Owned by | Notes |
|---|---|---|
| `ThemeSettingsKit` (model, store, schema, catalog, sidecar) | this repo | Foundation only |
| `ThemeSettingsUI` (`GTSThemeSettingsEditor`, screenshot/script helpers) | this repo | AppKit; renders the model and decides nothing itself |
| The window or panel, menu item and the "all applications" switch | host app | the editor provides a view only |
| ThemeSettings.plist for each theme | theme owners | adwaita, winuitheme, fun-themes |

**Build dependencies:** gnustep-base, gnustep-gui and GnuTLS. Two ways to
build a host:

1. **Against the installed libraries (preferred for a separate project).**
   The top-level `GNUmakefile` builds `libThemeSettingsKit` (Foundation +
   GnuTLS) and `libThemeSettingsUI` (the editor; NEEDED: Kit, gnustep-gui,
   gnustep-base). Both are soname `.so.0` (version 0.1.0). Public headers:
   `<ThemeSettingsKit/ThemeSettingsKit.h>` and
   `<ThemeSettingsUI/ThemeSettingsUI.h>` (umbrella headers). The host links
   `-lThemeSettingsUI -lThemeSettingsKit -lgnustep-gui`; it needs no
   GnuTLS flags of its own. `Tests/ExternalHost` is the minimal example.
   Stage into a scratch prefix only, never a user or system location:
   ```sh
   make install DESTDIR=/path/to/scratch GNUSTEP_INSTALLATION_DOMAIN=LOCAL
   # headers: <scratch>$(gnustep-config --variable=GNUSTEP_LOCAL_HEADERS)
   # libs:    <scratch>$(gnustep-config --variable=GNUSTEP_LOCAL_LIBRARIES)
   make -C <copy of Tests/ExternalHost> GTS_INCLUDE=<headers> GTS_LIB=<libs>
   LD_LIBRARY_PATH=<libs> ./obj/gts-external-host ...
   ```
   `GTS_SHOTS_ONLY=I scripts/screenshots.sh` does exactly this inside its
   scratch root and checks the result (scenario I).
2. **Compiling the sources in (what the standalone app, DemoNotes and the
   host check do).** Include `gts-config.make` so GnuTLS is detected and
   linked explicitly, and compile `ThemeSettingsKit/GTS*.m` and
   `ThemeSettingsUI/GTS*.m`.

`GTSScreenshot` and `GTSScriptRunner` are review/test tooling and are not
part of the library. `performScriptedAction:` on the editor is public but
is meant for tests. The editor's ivars are visible in its header; with the
GCC runtime, ivar layout is fragile, so hosts must not subclass the editor
across library versions. No libobjc2-only features are used.

**Wiring (in this order)**
```objc
GTSDefaultsDomainStore *store = [[GTSDefaultsDomainStore alloc]
  initWithHostDefaults: [NSUserDefaults standardUserDefaults]]; /* synced after commits */
GTSEditorModel *model = [[GTSEditorModel alloc] initWithStore: store
                                                      catalog: [[GTSThemeCatalog alloc] init]];
NSString *me = [[NSBundle mainBundle] bundleIdentifier];
if ([me length] == 0) me = [[NSProcessInfo processInfo] processName];  /* base's own rule */
[model setHostDomain: me];
[model setTargetApplicationDomain: me displayName: @"This application"
                             info: [[NSBundle mainBundle] infoDictionary]];
GTSThemeSettingsEditor *editor = [[GTSThemeSettingsEditor alloc] initWithModel: model];
[editor setDelegate: self];      /* themeSettingsEditorDidApply: */
[[panel contentView] addSubview: [editor view]];
```
* **Default target:** the host's own domain. Editing global settings is an
  explicit host control that calls `setTargetGlobal`; the host asks the user
  first if `hasChanges`.
* **Failures:** `setTarget...` returns NO when the domain can't be read
  reliably. The editor then shows "Unknown" and nothing can be edited, so the
  host must not hide that state.

**Host callbacks and lifecycle receipts**
* **Structured outcome:** `[model lastApplyOutcome]` returns a
  `GTSApplyOutcome` for the most recent Apply attempt. Use it, not the
  display `message`. Its `kind` is one of:
  - `Saved`
  - `NothingToSave`
  - `SavedRefreshFailed`
  - `WriteUnknown`
  - `Conflict` (`conflictKeys` lists the keys)
  - `Refused` (`error` says why: read-only, unreadable, invalid, or needs
    reload)

  `didWrite`, `isOutcomeUnknown` and `needsReload` are convenience flags.
  For the saved kinds, `receipt` is the session's `GTSApplyReceipt`, giving
  the committed changes and their strongest Apply requirement (restart,
  newWindows or live).
* **Who owns it and how long it lasts:** the model owns the outcome, and the
  object is immutable. It is cleared (`nil`) whenever it would be stale: a
  new edit is staged, Cancel, a successful Reload, or a target change. A
  failed Reload keeps it, because it still describes the state.
* **Callbacks:** both are optional.
  - `themeSettingsEditorDidApply:` (legacy) means something was written
    (`Saved` or `SavedRefreshFailed`). It does not prove that the settings
    were re-read or applied live. It is called first.
  - `themeSettingsEditor:didFinishApplyWithOutcome:` is then called for
    EVERY attempt, including one refused before saving because the text
    being typed was invalid (a fresh `Refused` outcome with
    `GTSErrorInvalidArgument`). It is the authority for recovery.
  - The outcome object is captured before either callback runs. A host that
    edits or switches target inside a callback clears
    `[model lastApplyOutcome]`, but not the object it was handed.
  - Apply re-entered from a callback is ignored. A delegate exception
    propagates to the caller; the editor stays usable for a later Apply.
  - Verified in a real AppKit host by `Tests/HostCheck` (scenario H in
    `scripts/screenshots.sh`, private Xvfb, scratch defaults).
  - Example: `ThemeSettingsDemo/main.m` logs kind, write, reload-needed and
    requirement; a real app might offer "Restart now" when the requirement
    is restart.
* Two distinct post-Apply failure outcomes. The current API keeps them
  apart, and hosts must too:
  1. **Write outcome unknown:** `-applyWithConflicts:error:` returns nil
     with `GTSErrorWriteFailed`. The save may or may not have reached disk.
     The edits stay staged and `needsRebase` is YES.
  2. **Saved, but refresh failed:** Apply returns a receipt with
     `refreshFailed` YES. The save succeeded and the edits are unstaged. The
     baseline is the old baseline plus what was written, and `needsRebase`
     is YES.

  In both cases any further Apply is refused with `GTSErrorNeedsReload`
  until `-rebaseWithError:` succeeds. In case 1 the rebase unstages
  whatever did reach disk. The editor's Reload button does that rebase,
  and the host must not re-apply anything on its own.
* Live settings: when the pane edits its own domain, the receipt says it was
  saved and that live application is *unconfirmed*. Whether the host's own
  `standardUserDefaults` reflects the change and the theme redraws has not
  been checked.

**Closing:** if `hasChanges`, ask the user to Apply, Discard or Cancel the
close. Pending text in a free-form field is staged on every keystroke, and
Apply commits it.

## 2. SystemPreferences follow-on plan (not started)

**Shape:** a preference-pane bundle (e.g. `Themes.prefPane`, principal class
an `NSPreferencePane` subclass) whose `mainView` hosts `[editor view]`. The
pane uses a target list like the standalone app's (global, installed apps,
read-only AppImage sidecars). SystemPreferences runs in its own process, so
it is never the "host domain": live application is unconfirmed for every
target.

**Ownership questions to settle before any work**
* Who owns the SystemPreferences app and the GNUstep repository it lives in?
  Any change there needs that owner, and may be upstream (`upstream.propose`,
  Dan's review).
* Whether an existing themes pane is replaced or a new pane is added next to
  it. Replacing one needs Dan's decision; a migration path is out of scope
  until then.

**Prerequisites (each needs evidence first)**
1. Done: `-lastApplyOutcome` on the model, with tests (GTSApplyOutcomeTests).
2. Done: `libThemeSettingsUI` + `libThemeSettingsKit` with public headers,
   staged into a scratch prefix and used by an out-of-tree host (scenario
   I). A pane bundle linking them has not been built.
3. Pane lifecycle: `willUnselect`/`shouldUnselect` mapped to the unsaved-
   changes prompt; GUI test on a private Xvfb with scratch defaults.
4. Target discovery in the pane process: the same `GTSThemeCatalog` roots as
   the standalone app. User-dir shadowing is shown.
5. Theme metadata merged by owners: WinUI (#196) is merged; Adwaita (#138)
   is still a draft; Gumdrop is reviewed but not committed in its repo.
6. Platform gate as in docs/platforms.md: Linux only until the
   Windows/macOS requirements there are met.

**Tests needed before any pane replacement**
* The model and store suites (existing, currently 119 tests, self-run),
  the harness self-test, the callback host check (scenario H) and the
  installed-library smoke (scenario I).
* Pane-hosted GUI scenarios matching A to G in `scripts/screenshots.sh`:
  global, app explicit/inherited/Info.plist, Apply/Cancel/Reset, free-form
  commit, live receipt wording, unreadable target refused, AppImage
  read-only. Each needs read-back checks and verified cleanup.
* A target-switch-with-unsaved-changes test, and a pane-unselect-with-
  unsaved-changes test.
* An independent review of the critical paths, because the current
  evidence is self-run.

**Explicitly out of scope until decided:** previews (rendering a theme in
the pane would load theme code into the SystemPreferences process, which
the framework avoids by design); migrating existing settings; Windows and
macOS.
