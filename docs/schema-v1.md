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

Line numbers are at the commit that adds this document.

A theme describes its user-facing settings in a static property list,
`ThemeSettings.plist`. Tools read it by path and never load theme code. The
schema only **describes** defaults keys that the theme already reads; it adds
no storage of its own, and the defaults domains stay the source of truth.

## 1. File and location

* Lookup in the theme bundle, first match wins: `Resources/ThemeSettings.plist`,
  `Contents/Resources/ThemeSettings.plist`, `ThemeSettings.plist` (S:411-426).
* The file is read as text and parsed with `-propertyList`. Both OpenStep
  (old-style) and XML plists work; binary plists do not (S:444-463). A file
  that is not readable or not a property list is `GTSErrorUnreadable`.
* Optional `ThemeSettings.strings` (per `.lproj`) localizes `Title`, `Help`,
  enum value titles and `Unset.Help`. The English text is the key. Resources
  are read through `NSBundle`, and no code is loaded (S:602-609; used at
  M:442, M:455, M:482, M:525).

## 2. Top level

| Key | Type | Required | Rule (code) |
|---|---|---|---|
| `SchemaVersion` | integer | yes | Must be `1`. Accepted forms: an integer `NSNumber`, or a digits-only string (old-style plists store numbers as strings). Booleans (`C`/`c`/`B` objCType), fractions and anything else are rejected as `GTSErrorInvalidSchema`, and any other integer as `GTSErrorUnsupportedVersion` (S:478-499). |
| `Theme` | non-empty string | yes | The `GSTheme` value that selects this theme (S:500-501). |
| `ThemeIdentifier` | non-empty string | yes | The logical theme identity, reverse DNS (S:502-504; the validator warns if it has no `.`, V:153). It names the theme, **not an installation**: forks and copies can share it. |
| `RequiredFeatures` | array | no | Must be an array if present (S:505-507). Each entry not in `+supportedFeatures` makes the **whole theme read-only** (S:532-540, M:360). v1 supports none (S:563-569). |
| `Groups` | array of `{Identifier, Title?, Help?}` | no | Accepted; presentation not guaranteed (section 11). Copied as is (S:541) and not used by the editor today. The validator checks its shape and uniqueness (V:158-176). |
| `Settings` | array | yes | Must be an array (S:508-510); it may be empty. |

A file-level failure means the whole file is rejected and the theme shows no
settings. The editor's theme list still shows the theme.

## 3. Setting descriptor

Each `Settings` entry is parsed on its own (S:81-290). **If an entry is
invalid, that setting is skipped and recorded as a loader warning; the rest
of the file still loads** (S:513-525, 543). The validator turns every such
warning into an ERROR (V:135-148), because the setting silently disappears
from every editor. A second entry with an `Identifier` already seen is also
skipped (S:518-522).

| Key | Type | Required | Rule (code) |
|---|---|---|---|
| `Identifier` | non-empty string | yes | Unique in the file (S:92-98, 518). UI state keys on it, not on `Key`. |
| `Key` | non-empty string | yes | The existing defaults key the theme reads (S:99-103). The validator requires one descriptor per key (V:209-212) and refuses `GSTheme`, which is theme selection, not a setting (V:213-214). |
| `Type` | `bool` \| `enum` \| `string` \| `number` | yes | Exact, case-sensitive spelling (S:109-118). |
| `Values` | array | enum only | Non-empty. Each entry is `{Value, Title?, Help?}` or a bare string (meaning `{Value = <string>}`); `Value` is a non-empty string (S:120-145). It is ignored for other types (the validator warns). Duplicates under the setting's comparison rule are a validator ERROR (V:240-256). |
| `CaseInsensitive` | bool | no | Any bool spelling (section 5); anything else reads as NO (S:147; validator ERROR, V:231-235). It only affects enum comparison (S:382-384). |
| `Scopes` | array, subset of `global`, `application` | yes | Non-empty; any other entry skips the setting (S:149-166). The editor hides the row when the target's scope is not listed (M:478). |
| `Group` | string | no | Copied (S:168). The validator requires it to name a `Groups` entry when `Groups` exists (V:220-225). **Not used by the editor today.** |
| `Title` | string | no | Defaults to the `Identifier` (S:169). |
| `Help` | string | no | S:170. |
| `Unset` | dict | yes | What absence means; see section 4 (S:172-203). |
| `Precedence` | array | no | See section 6 (S:205-238). |
| `InfoKey` | string | no | The Info.plist key for `applicationInfo`; defaults to `Key` (S:239). |
| `Apply` | `live` \| `newWindows` \| `restart` | yes | Exact spelling (S:241-249); see section 8. |
| `Minimum`, `Maximum` | number | no | Read only for `number` settings (S:251-262). **The loader accepts anything with `-doubleValue`, so a non-numeric string becomes 0**; that is a validator ERROR (V:262-265), as is `Minimum > Maximum` (V:266-267). |
| `RequiredFeatures` | array | no | Must be an array (S:263-268). An unsupported feature makes **this setting** read-only (S:269-278, M:486-490). |
| `DependsOn` | `{Setting, Values}` | no | Copied (S:280). **Not used by the editor today.** The validator requires `Setting` to be another loaded setting and every value to be valid for it (V:326-347). |
| `Overlaps` | array of Identifiers | no | Copied (S:281). The editor shows a note listing them (M:526-528). The validator requires every entry to be another loaded setting (V:350-360). |
| `Status` | `public` \| `unstable` | no | Exactly `unstable` hides the row unless the user asks for unstable settings (S:282, 574-582, M:465). **Any other value, including a typo, is treated as public**, which is a validator ERROR (V:227-229). |

## 4. Unset, missing and stored tokens

* **Absent key ≠ stored token.** A value such as `default` or `auto` in
  `Values` is an **explicit stored value** with its own meaning, never a
  synonym for absence. Reset removes the key from the target domain
  (E:129-132). It never writes a token.
* `Unset.Behavior = static`: `Value` is required (S:178-187). It must itself
  be valid for the setting (type, enum membership, range), otherwise the
  setting is skipped (S:284-288). The editor shows "Default (<title>)" (M:443),
  and the resolver reports state **Default** with that value (R:122-127).
* `Unset.Behavior = dynamic`: `Value` must be absent (S:188-197). `Help` says
  what the theme follows. The editor shows "Automatic (<Help>)" (M:441-442),
  and the resolver reports state **Unknown** (R:128-131). The validator warns
  when `Help` is missing (V:278-279).
* Any other `Behavior` skips the setting (S:198-202). `Unset.Help` is optional
  for static and is shown as a note (S:203, R:132).

## 5. Value types: validation, comparison, stored form

| Type | Valid input (`problemWithValue:`, S:327-369) | Equality (S:371-386) | Stored as (S:388-401, E:115-127) |
|---|---|---|---|
| `bool` | `NSNumber`, or `YES/NO/true/false/1/0`, case-insensitive (S:29-43) | by bool value | `"YES"` / `"NO"` strings |
| `enum` | a string equal to one of `Values` (case-insensitive if `CaseInsensitive`) | string, optionally case-insensitive | **the schema's canonical spelling** |
| `number` | `NSNumber`, or a string that scans entirely as a double; within `Minimum`/`Maximum` inclusive | `doubleValue` | **the input as given** (the editor stores the typed string, e.g. `"1.25"`) |
| `string` | any `NSString` (the empty string is Reset; see M `setText:`) | `isEqual:` | as given |

Stored values that the schema would reject (an unknown enum token, a number
out of range) are **not** rewritten or hidden. The resolver returns them as
they are (R:92-99), and the editor shows the raw value (M:456).

## 6. Precedence

* The default is `(argument, application, global)` (S:206-207). Entries are a
  source name or `{Source, Values}`. The known sources are `argument`,
  `application`, `applicationInfo`, `global`, `otherInfo` (S:71-79); an
  unknown source skips the setting (S:228-232).
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
  the same filter (V:285-300).
* An explicitly empty `Precedence` is a validator ERROR (V:282-283): no
  source could ever supply a value.

## 7. Version and compatibility rules

1. **One version, exact match.** v1 readers accept only `SchemaVersion = 1`
   and reject other integers with `GTSErrorUnsupportedVersion` (S:497-499).
   There is no "minimum reader version"; a v2 file is not shown by a v1
   editor.
2. **Additive optional keys stay v1.** Unknown keys, at top level, in a
   setting, in `Unset`, in an enum value or in a precedence entry, are
   ignored by v1 readers (the loader never enumerates keys). The validator
   warns, because unknown keys are usually typos (V:150-152,
   `unknownKeys`).
3. **Anything that would change what an editor writes must not rely on
   being ignored.** A theme that needs such behaviour lists a feature name in
   `RequiredFeatures` (top level or per setting). v1 readers then show the
   theme or the setting read-only (S:532-540, S:269-278) instead of
   writing something wrong.
4. **Breaking changes bump `SchemaVersion`.** Examples: a new `Type`, a new
   `Apply` value, a new `Unset.Behavior`, a new precedence source, or a
   changed meaning for an existing key. All of these are already rejected
   per setting by v1 readers (sections 3 and 6), so a theme can ship a v1
   file today and a v2 file later.
5. **Partial loading is intended.** One bad setting does not hide the others
   (S:513-525). Theme owners must run the validator: an editor never shows
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
2. **Status typo, non-numeric or inverted Minimum/Maximum:** the loader
   will skip the setting, with tests. This is a follow-up and **not yet
   implemented**. Today only the validator reports these (V:227-229,
   V:262-267).
3. **Numbers are stored exactly as typed** in v1 (section 5). Themes must
   accept a numeric string.
4. **Duplicate `Key` across descriptors:** the loader will skip the
   duplicate, in the same follow-up as 2 (**not yet implemented**; today
   `settingForKey:` returns the first, S:593-600, and the validator reports
   an ERROR).
5. **Text property lists only** in v1 (OpenStep or XML; S:444-463).
