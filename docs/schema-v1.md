# ThemeSettings.plist, schema version 1

Status: proposed final, accepted by gnustep-tools-lead at 26e599d (mailbox
#22591, 2026-11-10); decisions in section 11. **Ground truth is the loader:** every rule
below cites the code that enforces it. Where this text and the code
disagree, the code is what every editor does today, and the disagreement is a
bug to report. References:

* `S` = `ThemeSettingsKit/GTSThemeSettingsSchema.m` (loader)
* `V` = `ThemeSettingsKit/GTSSchemaValidator.m` (strict checker)
* `R` = `ThemeSettingsKit/GTSSettingsResolver.m`
* `E` = `ThemeSettingsKit/GTSEditSession.m`
* `M` = `ThemeSettingsKit/GTSEditorModel.m`

Line numbers are valid at commit 31fac26 (the Q2/Q4 loader change) and,
unchanged, at e944135 (no S/V/R/E/M file changed in between).

A theme describes its user-facing settings in a static property list,
`ThemeSettings.plist`. Tools read it by path and never load theme code. The
schema only **describes** defaults keys that the theme already reads; it adds
no storage of its own, and the defaults domains stay the source of truth.

## 1. File and location

* Lookup in the theme bundle, first match wins: `Resources/ThemeSettings.plist`,
  `Contents/Resources/ThemeSettings.plist`, `ThemeSettings.plist` (S:443-458).
* The file is read as text and parsed with `-propertyList`. Both OpenStep
  (old-style) and XML plists work; binary plists do not (S:476-495). A file
  that is not readable or not a property list is `GTSErrorUnreadable`.
* Optional `ThemeSettings.strings` (per `.lproj`) localizes `Title`, `Help`,
  enum value titles and `Unset.Help`. The English text is the key. Resources
  are read through `NSBundle`, and no code is loaded (S:644-651; used at
  M:442, M:455, M:482, M:525).

## 2. Top level

| Key | Type | Required | Rule (code) |
|---|---|---|---|
| `SchemaVersion` | integer | yes | Must be `1`. Accepted forms: an integer `NSNumber`, or a digits-only string (old-style plists store numbers as strings). Booleans (`C`/`c`/`B` objCType), fractions and anything else are rejected as `GTSErrorInvalidSchema`, and any other integer as `GTSErrorUnsupportedVersion` (S:511-532). |
| `Theme` | non-empty string | yes | The `GSTheme` value that selects this theme (S:533-534). |
| `ThemeIdentifier` | non-empty string | yes | The logical theme identity, reverse DNS (S:535-537; the validator warns if it has no `.`, V:135). It names the theme, **not an installation**: forks and copies can share it. |
| `RequiredFeatures` | array | no | Must be an array if present (S:538-540). Each entry not in `+supportedFeatures` makes the **whole theme read-only** (S:574-582, M:360). v1 supports none (S:605-611). |
| `Groups` | array of `{Identifier, Title?, Help?}` | no | Accepted; presentation not guaranteed (section 11). Copied as is (S:583) and not used by the editor today. The validator checks its shape and uniqueness (V:140-157). |
| `Settings` | array | yes | Must be an array (S:541-543); it may be empty. |

A file-level failure means the whole file is rejected and the theme shows no
settings. The editor's theme list still shows the theme.

## 3. Setting descriptor

Each `Settings` entry is parsed on its own (S:100-322). **If an entry is
invalid, that setting is skipped and recorded as a loader warning; the rest
of the file still loads** (S:546-568, 585). The validator turns every such
warning into an ERROR (V:117-130), because the setting silently disappears
from every editor. A second entry with an `Identifier` already seen is also
skipped (S:551-555), and so is a later entry whose `Key` is already
described (S:556-565).

| Key | Type | Required | Rule (code) |
|---|---|---|---|
| `Identifier` | non-empty string | yes | Unique in the file (S:111-117, 551-555). UI state keys on it, not on `Key`. |
| `Key` | non-empty string | yes | The existing defaults key the theme reads (S:118-122). **One descriptor per key: the first loads, and each later descriptor with the same `Key` is skipped and logged** (S:556-565; lead decision Q4). The validator also refuses `GSTheme`, which is theme selection, not a setting (V:191-192). |
| `Type` | `bool` \| `enum` \| `string` \| `number` | yes | Exact, case-sensitive spelling (S:128-137). |
| `Values` | array | enum only | Non-empty. Each entry is `{Value, Title?, Help?}` or a bare string (meaning `{Value = <string>}`); `Value` is a non-empty string (S:139-164). It is ignored for other types (the validator warns). Duplicates under the setting's comparison rule are a validator ERROR (V:214-230). |
| `CaseInsensitive` | bool | no | Any bool spelling (section 5); anything else reads as NO (S:166; validator ERROR, V:205-209). It only affects enum comparison (S:414-416). |
| `Scopes` | array, subset of `global`, `application` | yes | Non-empty; any other entry skips the setting (S:168-185). The editor hides the row when the target's scope is not listed (M:478). |
| `Group` | string | no | Copied (S:187). The validator requires it to name a `Groups` entry when `Groups` exists (V:198-203). **Not used by the editor today.** |
| `Title` | string | no | Defaults to the `Identifier` (S:188). |
| `Help` | string | no | S:189. |
| `Unset` | dict | yes | What absence means; see section 4 (S:191-222). |
| `Precedence` | array | no | See section 6 (S:224-257). |
| `InfoKey` | string | no | The Info.plist key for `applicationInfo`; defaults to `Key` (S:258). |
| `Apply` | `live` \| `newWindows` \| `restart` | yes | Exact spelling (S:260-268); see section 8. |
| `Minimum`, `Maximum` | number | no | Read only for `number` settings (S:270-286). Each must be a real number: an `NSNumber` that is not a bool/char, or a string that scans entirely as a double (S:30-46). Otherwise, or when `Minimum > Maximum`, **the setting is skipped** (S:274-283; lead decision Q2). On other types they are ignored (the validator warns, V:234-238). |
| `RequiredFeatures` | array | no | Must be an array (S:288-293). An unsupported feature makes **this setting** read-only (S:294-303, M:486-490). |
| `DependsOn` | `{Setting, Values}` | no | Copied (S:305). **Not used by the editor today.** The validator requires `Setting` to be another loaded setting and every value to be valid for it (V:296-318). |
| `Overlaps` | array of Identifiers | no | Copied (S:306). The editor shows a note listing them (M:526-528). The validator requires every entry to be another loaded setting (V:321-333). |
| `Status` | `public` \| `unstable` | no | Default `public`. Exactly `unstable` hides the row unless the user asks for unstable settings (S:314, 616-624, M:465). **Any other value, including a typo, skips the setting** (S:307-313; lead decision Q2). |

## 4. Unset, missing and stored tokens

* **Absent key ≠ stored token.** A value such as `default` or `auto` in
  `Values` is an **explicit stored value** with its own meaning, never a
  synonym for absence. Reset removes the key from the target domain
  (E:129-132). It never writes a token.
* `Unset.Behavior = static`: `Value` is required (S:197-206). It must itself
  be valid for the setting (type, enum membership, range), otherwise the
  setting is skipped (S:316-320). The editor shows "Default (<title>)" (M:443),
  and the resolver reports state **Default** with that value (R:122-127).
* `Unset.Behavior = dynamic`: `Value` must be absent (S:207-216). `Help` says
  what the theme follows. The editor shows "Automatic (<Help>)" (M:441-442),
  and the resolver reports state **Unknown** (R:128-131). The validator warns
  when `Help` is missing (V:249-250).
* Any other `Behavior` skips the setting (S:217-221). `Unset.Help` is optional
  for static and is shown as a note (S:222, R:132).

## 5. Value types: validation, comparison, stored form

| Type | Valid input (`problemWithValue:`, S:359-401) | Equality (S:403-418) | Stored as (S:420-433, E:115-127) |
|---|---|---|---|
| `bool` | `NSNumber`, or `YES/NO/true/false/1/0`, case-insensitive (S:48-62) | by bool value | `"YES"` / `"NO"` strings |
| `enum` | a string equal to one of `Values` (case-insensitive if `CaseInsensitive`) | string, optionally case-insensitive | **the schema's canonical spelling** |
| `number` | `NSNumber`, or a string that scans entirely as a double; within `Minimum`/`Maximum` inclusive | `doubleValue` | **the input as given** (the editor stores the typed string, e.g. `"1.25"`) |
| `string` | any `NSString` (the empty string is Reset; see M `setText:`) | `isEqual:` | as given |

Stored values that the schema would reject (an unknown enum token, a number
out of range) are **not** rewritten or hidden. The resolver returns them as
they are (R:92-99), and the editor shows the raw value (M:456).

## 6. Precedence

* The default is `(argument, application, global)` (S:225-226). Entries are a
  source name or `{Source, Values}`. The known sources are `argument`,
  `application`, `applicationInfo`, `global`, `otherInfo` (S:90-98); an
  unknown source skips the setting (S:247-251).
* Resolution walks the list and **the first source that has a value
  passing its `Values` filter wins** (R:73-120, filter at R:53-63):
  * `application`: the target app's domain gives state **Explicit**.
  * `global`: `NSGlobalDomain` gives **Explicit** for a global target and
    **Inherited** for an app target.
  * `applicationInfo`: the target app's Info.plist `InfoKey` gives
    **Info.plist**, for app targets only.
  * `argument` and `otherInfo` cannot be known outside the running app.
    They are reported as caveats ("may be overridden by…") and never win.
* A source may appear more than once: a filtered entry ranked high and an
  unfiltered entry ranked low. Adwaita's `header-bar-toolbar` and WinUI's
  menu settings rely on this. The validator warns only when a repeat can
  never apply, i.e. after an unfiltered entry for the same source, or with
  the same filter (V:256-271).
* An explicitly empty `Precedence` is a validator ERROR (V:253-254): no
  source could ever supply a value.

## 7. Version and compatibility rules

1. **One version, exact match.** v1 readers accept only `SchemaVersion = 1`
   and reject other integers with `GTSErrorUnsupportedVersion` (S:530-532).
   There is no "minimum reader version"; a v2 file is not shown by a v1
   editor.
2. **Additive optional keys stay v1.** Unknown keys, at top level, in a
   setting, in `Unset`, in an enum value or in a precedence entry, are
   ignored by v1 readers (the loader never enumerates keys). The validator
   warns, because unknown keys are usually typos (V:132-134,
   `unknownKeys`).
3. **Anything that would change what an editor writes must not rely on
   being ignored.** A theme that needs such behaviour lists a feature name in
   `RequiredFeatures` (top level or per setting). v1 readers then show the
   theme or the setting read-only (S:574-582, S:294-303) instead of
   writing something wrong.
4. **Breaking changes bump `SchemaVersion`.** Examples: a new `Type`, a new
   `Apply` value, a new `Unset.Behavior`, a new precedence source, or a
   changed meaning for an existing key. All of these are already rejected
   per setting by v1 readers (sections 3 and 6), so a theme can ship a v1
   file today and a v2 file later.
5. **Partial loading is intended.** One bad setting does not hide the others
   (S:546-568). Theme owners must run the validator: an editor never shows
   the loader's warnings to users.

## 8. Apply lifecycle

* Saved and applied are different facts. Apply reports what was **saved**,
  plus the strongest `Apply` requirement among the saved keys
  (`restart` > `newWindows` > `live`). A `GSTheme` change counts as
  `restart` (E:136).
* `live` means the theme reacts inside its **own** process when the value
  changes (e.g. on `NSUserDefaultsDidChangeNotification`). GNUstep posts no
  cross-process notification. The standalone editor therefore says "may
  update; restart guarantees it". Only an in-app pane editing its own domain
  may call a `live` change applied, and only once a GUI test shows it.
* `newWindows`: windows, panels and menus created after the change.
  `restart`: only a relaunch is guaranteed. When unsure, owners pick the
  stronger guarantee.
* Runtime confirmation (the app actually showing the change) is never
  inferred from the save.

## 9. Identity (three separate things)

| Identity | Source | Distinguishes |
|---|---|---|
| Logical theme | `ThemeIdentifier` (this file) | which theme the settings describe |
| Package | the bundle's Info plist `CFBundleIdentifier` + `CFBundleVersion` (or `CFBundleShortVersionString`) | which build or fork was installed |
| Location + descriptor fingerprint | path, plus a digest of Info plist, ThemeSettings.plist and executable | which installed copy (e.g. a USER copy shadowing a bundled one) |

None is derived from another. Compatibility is never inferred from any of
them.

## 10. Validating a file

```sh
make -C Tools/ValidateSchema
Tools/ValidateSchema/obj/gts-validate-schema path/to/Name.theme   # or the plist
```

The output has one line per finding (`ERROR` or `WARNING`) and a summary.
The exit status is 0 when there are no errors in any file, 1 when there are
errors, and 2 on a usage error. The tool reads the file exactly like the
editor does and never loads theme code. Fixtures:
`Tests/Fixtures/Schema/` (generated by `scripts/make-schema-fixtures.py`,
expectations in `Tests/GTSSchemaValidatorTests.m`). "No errors" means v1
editors load every setting as written. It does not prove that the theme
really reads those keys with those meanings: only the theme owner can say
that.

## 11. Decisions (gnustep-tools-lead, mailbox #22591, on 26e599d)

1. **Groups/Group and DependsOn stay in v1**, documented as *accepted;
   presentation not guaranteed*. The validator checks them, and editors may
   ignore them (the current one does).
2. **Status typo, non-numeric or inverted Minimum/Maximum: the loader skips
   the setting.** Implemented at 31fac26 (goal 506, #22814): Status at
   S:307-313, the number rule at S:30-46 and S:274-278, the inverted range
   at S:279-283. Tests: GTSSchemaTests `testStatusTypoSkipsSetting`,
   `testNonNumericMinimumSkipsSetting`, `testInvertedRangeSkipsSetting`,
   plus the cases that must still load (`testExplicitStatusValuesStillLoad`,
   `testNumericMinimumFormsStillLoad`).
3. **Numbers are stored exactly as typed** in v1 (section 5). Themes must
   accept a numeric string.
4. **Duplicate `Key`: the first descriptor loads, and each later one is
   skipped and logged.** Implemented at 31fac26 (S:556-565). Test:
   `testDuplicateKeyKeepsFirstSkipsLater`. Files without duplicates behave as
   before (`settingForKey:` already returned the first, S:635-642).
5. **Text property lists only** in v1 (OpenStep or XML; S:476-495).

Effect on real files (self-run): validator output over all 27 fixtures and
the Adwaita (PR #138 head 2581c19), WinUITheme and Gumdrop plists is
identical before and after, except the wording of the four fixtures these
rules cover (now reported as loader skips). Every valid file still has 0
errors and 0 warnings.
