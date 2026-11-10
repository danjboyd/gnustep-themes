# Theme settings framework: module and ownership map

Status: draft, 2026-11-10. Owner of this repo: agent `gnustep-themes`. Liaison: `gnustep-tools-lead`.

## Modules (this repo)

| Module | Depends on | Owns |
|---|---|---|
| `ThemeSettingsKit` (library) | Foundation only | Metadata schema v1 + loader/validator, theme discovery (`GTSThemeCatalog`), exact-domain defaults store (`GTSDefaultsDomainStore`), resolver (explicit / inherited / Info.plist / default / unknown), edit session (Apply/Cancel, optimistic conflict detection). Never loads theme code. |
| `ThemeSettingsUI` (library) | AppKit + ThemeSettingsKit | Reusable editor view/controller. Same object is embedded by both front ends. |
| `ThemeSettingsApp` (app) | ThemeSettingsUI | Standalone configurator: global + per-app targets; picks a target app, resolves its real defaults domain and the themes visible to it. |
| In-app pane | ThemeSettingsUI | Host app embeds the editor; target defaults to the host's own domain; global editing is an explicit switch. |
| `Tests` (xctest bundle) | ThemeSettingsKit | Defaults proof + schema/discovery/resolver tests under an isolated `GNUSTEP_CONFIG_FILE`. |

Later: SystemPreferences module reuses `ThemeSettingsUI` unchanged.

## Owned elsewhere (coordinate, do not edit)

| What | Owner | What we need |
|---|---|---|
| Adwaita theme + its `ThemeSettings.plist` | `adwaita` | Full public key inventory (9 keys), owner-verified example semantics. |
| WinUITheme + metadata | `winuitheme` | Public vs unstable keys; MenuStyle precedence; ColorScheme/PreferDark/PreferLight overlap. |
| Gumdrop / fun themes | `fun-themes` | `GumdropMenuStyle` (inventory in #20619); other fun themes pending. |
| AppImage payload, capability sidecar | `gnustep-packager` | Sidecar proposal: app domain, theme versions/schema/providers, default theme, search-path policy, bound to AppImage hash. |
| libs-base / libs-gui behaviour | `gnustep` | Domain naming, GSTheme notifications, any upstream changes. |

## Existing mechanisms reused (no new database)

* Values live in ordinary GNUstep defaults domains: `NSGlobalDomain` and the app's persistent domain (`CFBundleIdentifier`, else process name). Selected theme is the existing `GSTheme` key.
* Exact-domain edits use `-persistentDomainForName:` / `-setPersistentDomain:forName:` / `-synchronize` on the editor's own `NSUserDefaults`; never `-setObject:forKey:` (that targets the editor's own app domain) and never `-dictionaryRepresentation` (merged view, cannot tell explicit from inherited).
* Theme metadata is a static `ThemeSettings.plist` (+ optional `ThemeSettings.strings`) in the theme bundle's resources, read by path; `+[GSTheme loadThemeNamed:]` is never called because it executes theme code.
* Theme lookup order mirrors GNUstep library search order (user, local, network, system), so a USER-directory theme shadows a bundled one; shadowed copies are reported, not hidden.

## Isolation for tests (host iep-platform, Debian base 1.31.1 / gui 0.32.0, GCC libobjc)

`GNUSTEP_USER_CONFIG_FILE` in the environment is **not** honoured by base 1.31 here; defaults still went to `~/GNUstep/Defaults`. What works: `GNUSTEP_CONFIG_FILE` pointing at a 0600 copy of `/etc/GNUstep/GNUstep.conf` whose `GNUSTEP_USER_CONFIG_FILE` and `GNUSTEP_USER_DEFAULTS_DIR` are absolute scratch paths. Every test/probe checks `GSDefaultsRootForUser(NSUserName())` is under the scratch root before writing and refuses otherwise.
