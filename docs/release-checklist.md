# First tagged release: checklist (DRAFT)

Status: **draft, not approved.** Nothing here has been tagged or released.
Dan approves the release itself, and every step below that tags, publishes
or uploads anything.

Proposed release: **Theme Settings 0.1.0**. It contains the editor app, the
embeddable editor view, `ThemeSettingsKit`, the schema validator and
schema v1, as a source tag plus a Linux x86_64 AppImage.

## 1. Versions agree

Set the same version in all four places, in one commit on main:

- [ ] `ThemeSettingsKit/GNUmakefile` `VERSION` (now 0.1.0; shared library
      version 0).
- [ ] `packaging/package.manifest.json` `package.version` (now 0.1.0).
- [ ] `.github/workflows/package-appimage.yml` `package-version`: now
      `0.1.0-dev`; becomes `0.1.0` for the release build.
- [ ] README "Status" section.

## 2. What must pass, at the exact commit to be tagged

| Check | How | Evidence to record |
|---|---|---|
| Linux CI | GitHub CI on main (Debian 13, unprivileged user): build, unit tests, new-user defaults check, schema validator | run id, test count |
| Local CI | `scripts/ci.sh` | test count |
| GUI scenarios | `scripts/screenshots.sh` on a private Xvfb (A–G) | all CHECK lines ok |
| AppImage build | manual `package-appimage` run at that commit (packager validation and launch smoke test) | run id, AppImage sha256 |
| AppImage test | `packaging/test-appimage.sh` on a private display: new home opens cleanly, themes from `GTS_HOST_THEME_ROOTS` listed (with control), Apply saves into the scratch home | log and screenshots |
| Try-safely launcher | `packaging/try-isolated.sh` with that AppImage: runs; the isolation-removed control refuses (exit 2); the tamper control is caught (exit 3) | exit codes |
| Theme files | `scripts/validate-theme.sh` on every `examples/*.theme`, plus the owners' own files (Adwaita CI already runs it) | 0 errors |
| Windows | winuitheme's run of `docs/windows.md` section 6 (after its 11/15 reset) | report id |

**Windows decision (open):** either
(a) the Windows test passes, and writes become the default on Windows in a
separate tested push before the tag; or
(b) 0.1.0 ships with Windows read-only by default and the opt-in write path
marked experimental. The release notes then say so.
Dan decides which.

## 3. Release notes (to draft at release time)

- What it is: one editor for theme settings, standalone and embeddable,
  writing the GNUstep defaults keys the theme already reads.
- What's in it: schema v1, the validator and its CI snippet, Adwaita and
  Gumdrop proven end to end (`docs/end-to-end.md`), and the AppImage.
- Platforms: Linux tested. Windows as decided above. macOS untested
  (`docs/platforms.md`).
- Known issues:
  - The AppImage launcher's handling of "/" in option values
    (gnustep-packager fix pending).
  - Apply needs an application restart for most settings.
  - Interface version 0, so library interfaces may change.
- How to try it safely: `packaging/try-isolated.sh` (user guide,
  "Install and run the AppImage").

## 4. Who does what

| Step | Who | Needs |
|---|---|---|
| Version commit, checks above, notes draft | gnustep-themes | standing push permission (tested fast-forward) |
| Windows test | winuitheme | its own run, on its Windows host |
| Choice (a) or (b) for Windows | Dan | an ask |
| Release AppImage build (workflow run) | gnustep-themes | Dan's go (an ask) |
| Tag `v0.1.0` and GitHub release with the AppImage attached | gnustep-themes after Dan's go, or Dan | **Dan's explicit go** (an ask with the evidence above) |
| Announcing it anywhere outside Dan's repos | nobody without Dan | upstream proposal rules |

## 5. After the release

- [ ] Point the theme-CI snippet's `GTS_COMMIT` (examples/ci,
      docs/theme-ci.md) at the tag. Tell adwaita, which pins it in its CI.
- [ ] Set `package-version` back to the next `-dev` version.
