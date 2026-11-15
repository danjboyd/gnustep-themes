# Theme Settings 0.1.0: release notes (DRAFT)

Status: **draft, not released.** No tag exists. Dan approves the release;
see [release-checklist.md](release-checklist.md). This version of the notes
assumes his Windows choice (a), editing on by default.

## What it is

Theme Settings is one editor for GNUstep theme settings. It lets you pick a
theme and change the theme's own settings, for all your applications or for
one, without editing defaults by hand. It writes the same GNUstep defaults
keys the theme already reads, so there is no separate settings file and
nothing new for themes to load.

It comes in two forms that share the same editor:

- **Theme Settings app** (`ThemeSettings.app`): all applications, or any
  application you pick.
- **Embeddable editor view** (`ThemeSettingsKit`): an application can put the
  editor in its own preferences. `ThemeSettingsDemo` shows how
  ([embedding.md](embedding.md)).

## What's in 0.1.0

- **Schema v1** ([schema-v1.md](schema-v1.md)). A theme describes its
  settings in a static `Resources/ThemeSettings.plist`: keys, types, choices,
  scopes, what applies when unset, and when a change takes effect. The editor
  never loads theme code.
- **Validator and theme CI.** `scripts/validate-theme.sh`, and a copy-ready
  GitHub Actions job for theme repositories ([theme-ci.md](theme-ci.md)).
  Adwaita's CI already runs it.
- **Safe editing.**
  - Changes are staged until you press Apply.
  - Text that isn't valid is never saved.
  - A setting someone else changed since you opened it is never overwritten
    silently.
  - Every write is read back and checked.
  - An unreadable settings file is shown as refused, never rewritten.
- **Proven end to end** with Adwaita and Gumdrop. Changing a setting in the
  editor changes how the theme draws ([end-to-end.md](end-to-end.md)).
- **AppImage** for Linux x86_64, with its own GNUstep runtime. It lists the
  themes installed on your system and reads only their `ThemeSettings.plist`.
- **Trying it safely.** `packaging/try-isolated.sh` runs the AppImage with a
  throwaway GNUstep home. It refuses to start unless it can prove that home
  is used, and it checks that your real settings are unchanged afterwards
  (user guide, "Install and run the AppImage").

## Platforms

- **Linux:** tested. CI runs on Debian 13 as an unprivileged user: build,
  137 unit tests, a new-user check and the schema validator. The GUI is also
  tested on a private display.
- **Windows:** built and tested on Windows 11 (MSYS2 CLANG64) on
  2026-11-15: reading, saving, removing and the conflict check all passed
  ([windows.md](windows.md) 6.1). Editing works with GNUstep's file
  defaults backend; a registry-backed configuration is shown read-only.
  `GTS_ENABLE_WINDOWS_WRITES=0` turns editing off. No Windows package is
  provided: build from source with the recipe in windows.md.
- **macOS:** untested ([platforms.md](platforms.md)).

## Known issues

- **Launcher and "/".** The AppImage launcher prefixes the current folder to
  a command-line option value that contains "/" but doesn't start with it.
  For example, `-Key text/plain` arrives as `-Key $PWD/text/plain`. A fix is
  planned in gnustep-packager. Normal use passes no such options.
- **Restart needed.** Most settings take effect when the application
  restarts. Each row says when its setting applies.
- **Interfaces may change.** The library interface version is 0, so
  `ThemeSettingsKit` interfaces may change before 1.0. Schema v1 is settled.
- **Window style.** The editor window always uses the plain GNUstep look,
  whichever theme you choose.

## Downloads

- Source: tag `v0.1.0` (after Dan's go).
- `ThemeSettings-0.1.0-x86_64.AppImage`, attached to the GitHub release.
  sha256: *(from the release build)*.

## Thanks

Theme owners described their own settings: Adwaita, Gumdrop (fun-themes) and
WinUITheme. gnustep-packager provided the AppImage tooling.
