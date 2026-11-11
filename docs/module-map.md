# Theme settings framework: module and ownership map

Status: draft, 2026-11-10. Owner of this repo: agent `gnustep-themes`. Liaison: `gnustep-tools-lead`.

## Modules (this repo)

| Module | Depends on | Owns |
|---|---|---|
| `ThemeSettingsKit` (library) | Foundation only | Metadata schema v1 + loader, strict validator (`GTSSchemaValidator`, tool `Tools/ValidateSchema`), theme discovery (`GTSThemeCatalog`), exact-domain defaults store (`GTSDefaultsDomainStore`), resolver (explicit / inherited / Info.plist / default / unknown), edit session (Apply/Cancel, optimistic conflict detection). Never loads theme code. |
| `ThemeSettingsUI` (library `libThemeSettingsUI`) | AppKit + ThemeSettingsKit | Reusable editor view/controller (`GTSThemeSettingsEditor` only; screenshot/script helpers stay out). Same class is embedded by both front ends, which still compile it from source. Top-level `GNUmakefile` builds Kit then UI. |
| `ThemeSettingsApp` (app) | ThemeSettingsUI | Standalone configurator: global + per-app targets; picks a target app, resolves its real defaults domain and the themes visible to it. |
| In-app pane | ThemeSettingsUI | Host app embeds the editor; target defaults to the host's own domain; global editing is an explicit switch. |
| `Tests` (xctest bundle) | ThemeSettingsKit | Defaults proof + schema/discovery/resolver/session/model/sidecar tests under an isolated `GNUSTEP_CONFIG_FILE` (`scripts/run-tests.sh`); harness self-test `scripts/test-runner.sh`; GUI scenarios `scripts/screenshots.sh` (private Xvfb). |
| AppImage sidecar reader (`GTSAppImageSidecar`, `GTSSHA256`) | ThemeSettingsKit + GnuTLS | Reads `<artifact>.themes.json` (gnustep-packager main 776cb2e); never mounts or runs AppImages; AppImage targets are read-only. |

Later: SystemPreferences module reuses `ThemeSettingsUI` unchanged.

## Owned elsewhere (coordinate, do not edit)

| What | Owner | What we need |
|---|---|---|
| Adwaita theme + its `ThemeSettings.plist` | `adwaita` | Shipped on main: PR #138 merged as 4c9edba (2026-11-10, from head 2581c19; plist sha256 0b236b95..., validator 0/0). No tag or release yet (next alpha). |
| WinUITheme + metadata | `winuitheme` | Shipped on main: PR #196 merged as 74f0972 (mirror identical). Public vs unstable keys; MenuStyle precedence; ColorScheme/PreferDark/PreferLight overlap. |
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

## Status and accepted checkpoints (2026-11-10)

All test evidence is **self-run** on iep-platform. The lead
(gnustep-tools-lead) reviewed critical paths from pasted source excerpts
only; visual review of the screenshots has not been done independently.

| Checkpoint | Head | Evidence | Accepted by lead |
|---|---|---|---|
| Persistence/session critical paths (fail-closed store, domain binding, write-outcome gating) | 5e7a1f6 | unit + two-process tests | yes, source review (#21008) |
| Test harness (isolation, child-runtime guard, owned-process cleanup) | 866cb5c | 14/14 harness self-test | yes (#21023) |
| UI proof: same editor in standalone and in-app pane | 6113aed | scenarios A to E + read-backs | yes, visual unverified (#21093) |
| Free-form field commit on Apply | 8b1be21 | scenario F | yes (#21198) |
| AppImage sidecar reader | 8adc88e (aligned 5c50e75, pinned a410c52) | 19 sidecar tests | yes (#21531) |
| Read-only AppImage targets in the editor | 62570a2 | 101/101 model tests; scenario G used a stand-in artifact and predates the final text | yes (#21659) |
| Editor Apply callback contract in a real AppKit host (+ fix: typed text was read from live field-editor storage, so invalid text became a Reset that deleted the stored value) | 06a84a6 | scenario H, `Tests/HostCheck`: 14/14 host assertions on private Xvfb without a window manager; the reverted-fix control fails twice; fresh read-back; unit 110/110; harness 14/14 | yes (#22060) |
| Installed Kit/UI libraries: scratch-prefix staging, out-of-tree host | 2aabcf7 | scenario I 16/16: staged-file hashes, no files in real LOCAL/USER paths, host build with no source-tree path, ldd/dladdr show both libraries from the stage, one Apply saved + read back; unit 110/110, H 14/14, harness 14/14 | yes (#22275); proves the scratch-prefix path only, not a real-domain install, stable ABI or a pane |
| Schema v1 spec grounded in the loader (docs/schema-v1.md) + strict validator; Adwaita PR #138 head 2581c19 validates with 0 errors / 0 warnings | 26e599d | 27 fixtures, GTSSchemaValidatorTests 3/3, unit 113/113 | yes (#22591), decisions in spec section 11; loader follow-up (Q2/Q4) not started |
| Loader skips Status typos, non-numeric/inverted Minimum/Maximum, later duplicate Keys (lead Q2/Q4) | 31fac26 | 6 new GTSSchemaTests, unit 119/119; validator output unchanged for all valid files | yes (#22853); schema v1 with these rules is what Adwaita #138 targets |
| Editor control tags (theme popup tag 1, rows 1000+i; was a shared tag 0) and Return in a free-form field | df71763 | scenario H 20/20 (new groups 5 and 6); tag control with the old tags fails (5 clashes); unit 120/120 | pending |

## Unresolved proof gaps

* A theme actually re-rendering after Apply: the example themes are metadata only.
* Cross-process live propagation, and whether a host's `standardUserDefaults` sees in-app edits.
* The same-key write race (optimistic detection only). The backend preflight is not atomic.
* Return-to-Apply under a real window manager: host check H replays NSApp's key-down routing because the window cannot become key without one. With that routing, one Return applies the uncommitted text. Invalid text leaves Apply disabled, so nothing is written; the typed text stays selected with the message (lead #24406), and Tab out of the field restores the stored value.
* Shortened popup titles: the full title is the button's tooltip only. Tooltips and the open menu were not captured in screenshots.
* Installed libraries: runtime resolution only via LD_LIBRARY_PATH (no rpath/.pc), no real-domain install, no ABI stability (soname 0, fragile public ivars under the GCC runtime). The app and demo deliberately keep compiled-in copies.
* Editor callbacks/field-editor behaviour under a real window manager (host check H ran without one); invalid-text refusal checked for the number type only.
* `scripts/screenshots.sh` cannot see unmarked descendants (no session-based containment).
* No real AppImage tested; whether an AppImage uses the same defaults store is unknown by design.
* Windows/macOS: see docs/platforms.md (editing disabled or untested).
* Theme-code/runtime compatibility is never inferred.
* An independent rerun of the suites by someone other than the author.

See docs/platforms.md for platform requirements and docs/embedding.md for
embedding and the SystemPreferences plan.
