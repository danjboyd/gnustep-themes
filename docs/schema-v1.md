# ThemeSettings.plist, schema version 1 (draft)

A theme advertises its user-facing settings in a static property list,
`ThemeSettings.plist`, in its bundle's resources (`<Name>.theme/Resources/`
on GNUstep layout; `Contents/Resources/` also accepted). Tools read it by path
and never load theme code. Optional `ThemeSettings.strings` (per `.lproj`)
localizes the `Title`/`Help` keys.

The schema only **describes** keys that the theme already reads. It never
introduces new storage; the defaults domains stay the source of truth.

## Top level

| Key | Type | Req | Meaning |
|---|---|---|---|
| `SchemaVersion` | integer | yes | `1`. Readers reject a higher version. |
| `Theme` | string | yes | The `GSTheme` value that selects this theme (bundle name without `.theme`). |
| `ThemeIdentifier` | string | yes | Logical theme identity, reverse DNS (`org.gnustep.themes.adwaita`). It names the theme, **not an installation**: forks and copies can share it. |
| `RequiredFeatures` | array | no | Features a reader must implement to edit this theme correctly. A reader that lacks any of them shows the whole theme read-only. v1 readers implement none beyond this document. |
| `Groups` | array | no | `{Identifier, Title, Help?}`, in display order. |
| `Settings` | array | yes | Setting descriptors, below. |

Unknown keys are ignored **only** because v1 defines every key that changes
what an editor writes; anything new that does must be declared in
`RequiredFeatures`. Metadata describes keys only: no selectors, scripts or
code references are ever evaluated.

### Identity (three separate things)

| Identity | Source | Distinguishes |
|---|---|---|
| Logical theme | `ThemeIdentifier` (this file) | which theme the settings describe |
| Package | the bundle's Info plist `CFBundleIdentifier` + `CFBundleVersion` (or `CFBundleShortVersionString`) | which build/fork was installed |
| Artifact | path + fingerprint (digest of Info plist, ThemeSettings.plist, executable) | which installed copy, e.g. a USER copy shadowing an AppImage-bundled copy |

None is derived from another; shadowed copies are listed separately with their own package and artifact identity.

## Setting descriptor

| Key | Type | Req | Meaning |
|---|---|---|---|
| `Identifier` | string | yes | Stable ID, unique in this file (`adwaita.color-scheme`). UI state and future migrations key on it, not on `Key`. |
| `Key` | string | yes | Existing defaults key the theme reads. |
| `Type` | `bool` \| `enum` \| `string` \| `number` | yes | Stored value type. Bools are stored the GNUstep way (`YES`/`NO` strings are accepted on read). |
| `Values` | array | enum | `{Value, Title, Help?}`. `Value` is exactly what is stored. A value such as `default` or `auto` is **an explicit stored value** with its own meaning, never a synonym for "absent". |
| `CaseInsensitive` | bool | no | Theme compares enum values case-insensitively (Gumdrop). |
| `Scopes` | array | yes | Subset of `global`, `application`. Where a user may set it. |
| `Group`, `Title`, `Help` | string | no | Presentation; `Title`/`Help` are localization keys with English as the literal. |
| `Unset` | dict | yes | What absence means. `Behavior` = `static` (with `Value`: the value the theme behaves as) or `dynamic` (with `Help`: e.g. "follows GTK_THEME, then GNOME color-scheme"). Dynamic never names a stored token; the UI shows it as "Automatic (…)", and reset removes the key. |
| `Precedence` | array | no | Ordered sources. Default: `(argument, application, global)`. Entries are strings or `{Source, Values?}` where `Source` is `argument`, `application`, `applicationInfo` (target app's Info.plist key of the same name, or `InfoKey`), `global`, `otherInfo`. `Values` restricts which values from that source win (WinUI: only `menubar` from Info outranks global). |
| `InfoKey` | string | no | Info.plist key used for `applicationInfo` if different from `Key`. |
| `Apply` | `live` \| `newWindows` \| `restart` | yes | Weakest guarantee that holds **inside the app's own process**: `live` = the theme reacts when the value changes in that process (e.g. `NSUserDefaultsDidChangeNotification`); `newWindows` = windows, panels and menus created after the change; `restart` = only a relaunch is guaranteed. When unsure, owners pick the stronger one. See "Apply lifecycle" below. |
| `Minimum`, `Maximum` | number | no | Range for `number` settings; values outside are rejected by the editor. |
| `RequiredFeatures` | array | no | As at top level, for this setting only: an unknown feature makes the setting read-only. |
| `DependsOn` | dict | no | `{Setting = <Identifier>; Values = (…)}` setting is only relevant when another setting has one of these effective values. |
| `Overlaps` | array | no | Identifiers of settings that interact (WinUI ColorScheme / PreferDark / PreferLight). UI shows a note; it does not invent a merged control. |
| `Status` | `public` \| `unstable` | no | Default `public`. Unstable entries are hidden unless the user asks. Internal/diagnostic keys are simply not listed. |

## Apply lifecycle

* Saved and applied are different facts. Apply reports what was **saved**,
  plus the strongest `Apply` requirement among the saved keys (a `GSTheme`
  change counts as `restart`).
* `live` is a statement about the theme in its own process. An edit made by
  another process (the standalone configurator) reaches a running app only if
  that app re-reads its defaults; GNUstep posts no cross-process
  notification, and refresh of another process' cache is unproven. The
  standalone editor therefore says "may update; restart guarantees it" for
  `live` settings, and only the in-app pane editing its own domain may call a
  `live` change applied, and only once that is shown in a GUI test.
* Runtime confirmation (the app actually showing the change) is never
  inferred from the save.

## Resolution states (per setting, per target)

* **Explicit**: key present in the target's own domain (app domain, or `NSGlobalDomain` when editing global).
* **Inherited**: target is an app, key absent in app domain, present in `NSGlobalDomain`.
* **Info.plist**: a precedence source from the target app's Info dictionary supplies the value.
* **Default**: nothing set; `Unset.Behavior = static`.
* **Unknown**: nothing set and `Unset.Behavior = dynamic`, or the winning source cannot be known outside the running app (arguments, theme custom code).

Reset = remove that one key from the target domain. Theme selection (`GSTheme`)
resolves the same way, independently of every setting. Values belonging to the
inactive theme are left untouched.
