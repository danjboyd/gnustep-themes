# Library interfaces before 1.0

Status: a proposal (2026-11-18), against `main` at `a417ac7`; section 2 is
the 1.0 candidate (lead, 2026-11-19). Nothing is frozen yet. Both libraries are interface version 0 (`libThemeSettingsKit.so.0`,
`libThemeSettingsUI.so.0`, version 0.1.2), and the release notes say
interfaces may change. This note says what a `.so.1` should promise, what it
shouldn't, and what has to change in the code first.

## 1. Who calls the libraries today

| Caller | Built how | What it uses |
|---|---|---|
| Theme Settings app (`ThemeSettingsApp`) | sources compiled in | model targets (global, app, AppImage sidecar), catalog, store, `GTSApplicationIdentity`, editor |
| DemoNotes (`ThemeSettingsDemo`) | sources compiled in | the embedding wiring, outcome callbacks, `GTSApplyPolicy` constants |
| Adwaita's ThemeDemo panel (plugins-themes-adwaita PR #150, merged) | **installed libraries** (`-lThemeSettingsUI -lThemeSettingsKit`, built only when the headers are found), so it is the first binary consumer | the embedding wiring: store `initWithHostDefaults:`, catalog, model `setHostDomain:` / `setTargetApplicationDomain:…` / `setTargetGlobal` / `hasChanges` / `targetTitle`, editor `initWithModel:` / `view` / `setDelegate:` / `reloadFromModel`, delegate outcome (`kind`, `didWrite`, `needsReload`), and `performScriptedAction:` for its GUI checks |
| `Tests/ExternalHost` | installed libraries | the same wiring, built out of tree (scenario I) |
| `Tools/ValidateSchema` (`scripts/validate-theme.sh`) | sources compiled in | `GTSSchemaValidator`; theme CI depends on its **exit status and output**, not its classes |

So, in practice, outside code depends on a small part of the libraries:
the embedding wiring in [embedding.md](embedding.md) section 1, and the
validator's command-line behaviour.

## 2. Proposed tiers

### Stable in 1.0 (the embedding contract)

`ThemeSettingsUI`:

- `GTSThemeSettingsEditor`: `-initWithModel:`, `-model`, `-view`,
  `-setDelegate:`, `-reloadFromModel`.
- `GTSThemeSettingsEditorDelegate`: both methods, both optional.

`ThemeSettingsKit`:

- `GTSDefaultsDomainStore`: `-init`, `-initWithHostDefaults:`.
- `GTSThemeCatalog`: `-init`, `-initWithSearchRoots:`;
  `GTSThemeSearchRoot +rootWithPath:origin:` and the `GTSOrigin…`
  constants (hosts add their own theme folders with them).
- `GTSEditorModel`: `-initWithStore:catalog:`, `-setHostDomain:`,
  `-setTargetGlobal`, `-setTargetApplicationDomain:displayName:info:`,
  `-hasChanges`, `-targetTitle`, `-lastApplyOutcome`.
- `GTSApplyOutcome` (all accessors), `GTSApplyOutcomeKind`,
  `GTSApplyReceipt`, `GTSApplyPolicy` (`GTSApplyLive` / `NewWindows` /
  `Restart`).

Promises that go with it:

- **Enums only grow at the end.** A host must handle an outcome kind it
  doesn't know: treat it as `Refused`, which writes nothing.
- **The delegate only gains optional methods.**
- **Display text is not interface.** `message`, `diagnostics`, state lines
  and receipts will change wording and be translated
  ([a11y-l10n.md](a11y-l10n.md)). Hosts decide from outcome kinds, as
  embedding.md already says.

### Separately versioned (not tied to the library version)

- **The ThemeSettings.plist format** is `SchemaVersion = 1`
  ([schema-v1.md](schema-v1.md)). Theme authors rely on it whatever the
  library version.
- **The validator's command line:** exit status 0 for no errors, 1 for
  errors; warnings don't change the status ([theme-ci.md](theme-ci.md)).
  Keep it stable; the text of its findings is not.

### Installed but provisional in 1.0

These are useful and installed, but nobody outside this repository uses
them yet. Ship them with a header comment saying "provisional: may change
in a minor release", rather than freezing them by accident:

`GTSThemeSettingsSchema` and `GTSSettingDescriptor`,
`GTSSchemaValidator`, `GTSSettingsResolver`, `GTSEditSession`,
`GTSThemeRecord` and the rest of `GTSThemeCatalog`, `GTSAppImageSidecar`,
`GTSApplicationIdentity`, the rest of `GTSEditorModel` (rows, choices,
theme and follow-GNOME controls), `GTSGnomeSettings`, and the `GTSSHA256…`
functions.

### Not interface (tests and tooling)

- `-performScriptedAction:` on the editor (its verbs, including `fonts`,
  exist for GUI checks). Adwaita's panel uses it for the same purpose. Keep
  it working, but say it may change.
- `-[GTSEditorModel setGnomeSettings:]`, `GTSFixedGnomeSettings`,
  `+[GTSDefaultsDomainStore setBackendWritableOverrideForTesting:]`, the
  store's `NSUserDefaults` override point and `_hookTarget`,
  `GTSSHA256SetDisabledForTesting()`.
- `GTSScreenshot` and `GTSScriptRunner`, which are already left out of the
  installed headers.

## 3. What has to change before `.so.1`

These matter because the GCC runtime has fragile instance variables: a
class's ivar layout is compiled into every binary that subclasses it or
reads its `@public` ivars.

1. **Hide instance variables of the stable classes.** All the headers
   declare their ivars; six classes mark them `@public`
   (`GTSApplyOutcome`, `GTSSettingRow`, `GTSApplyReceipt`,
   `GTSResolvedValue`, `GTSApplicationIdentity`, `GTSSidecarTheme`). For the
   stable tier, replace the ivars with a single private pointer, so later
   versions can add state without breaking binaries. Remove `@public`;
   the code inside the library can use the private struct.
2. **Say in the headers that the stable classes are not for
   subclassing.** embedding.md says it; the headers don't.
3. **Move the test hooks out of the installed headers** into
   `…+Testing.h` headers that aren't installed. The tests already compile
   the sources, so they don't need the installed headers.
4. **Mark the provisional headers**, or stop installing them. Either is
   fine; marking keeps the validator and resolver usable from outside.
5. **Export only what's public.** Nothing sets symbol visibility today,
   so every function and class in the library is exported. At least the
   C functions (`GTSSHA256…`) should be checked.
6. **Check the ABI in CI.** Neither `abidiff` (libabigail) nor
   abi-compliance-checker is installed on the build host. Add one to CI,
   comparing each release with the previous one, before promising
   compatibility.
7. **Installation pieces** that module-map.md still lists as missing: a
   pkg-config file or gnustep-make snippet for hosts, and no reliance on
   `LD_LIBRARY_PATH`.
8. **Then** set `…_INTERFACE_VERSION = 1` in both GNUmakefiles, and say in
   the release notes what 1.0 promises (section 2).

Steps 1, 3 and 5 change no behaviour, and the unit tests and scenario I
cover them. Step 6 needs a CI change, so it needs Dan's go.

## 4. Decisions so far, and what's open

**Decided (gnustep-tools-lead, 2026-11-19):**

- The stable tier in section 2 is the **1.0 candidate**.
- `GTSSchemaValidator` **stays provisional** until a binary consumer needs
  it. Theme authors use the command line.
- The stable tier grows only from **recorded requirements**: ThemeDemo now,
  and SystemPreferences once its needs are written down.

**ThemeDemo against the candidate (source check, 2026-11-19).** Adwaita's
`Examples/ThemeDemo/ThemeDemoSettingsPanel.m` (plugins-themes-adwaita at
`c6aeff2`) calls only:

- `GTSDefaultsDomainStore -initWithHostDefaults:`;
- `GTSThemeCatalog -init`;
- `GTSEditorModel -initWithStore:catalog:`, `-setHostDomain:`,
  `-setTargetApplicationDomain:displayName:info:`, `-setTargetGlobal`,
  `-hasChanges`, `-targetTitle`;
- `GTSThemeSettingsEditor -initWithModel:`, `-view`, `-setDelegate:`,
  `-reloadFromModel`;
- both delegate methods, and `GTSApplyOutcome -kind`, `-didWrite`,
  `-needsReload`;
- `-performScriptedAction:`, for its own GUI checks only.

Everything except `-performScriptedAction:` is in the stable tier, and
ThemeDemo uses that one the way section 2 describes (tests). So the
candidate covers ThemeDemo without growing. One gap: `GTSThemeCatalog`
doesn't declare `-init` in its header (it's inherited from `NSObject`, and
overridden in the `.m`). The stable header should declare it. This was a
source check; a run of ThemeDemo against a rebuilt library is still to
come.

**Open:**

- **SystemPreferences requirements.** Nothing is written yet
  (embedding.md section 2 is a plan, with no pane). Record what a pane
  needs before adding anything to the stable tier for it.
- **Debian packaging:** a `.so.1` means a new binary package name
  (`libthemesettingskit1`). Coordinate the timing with whoever owns the
  Debian packages.
