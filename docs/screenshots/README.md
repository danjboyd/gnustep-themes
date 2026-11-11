# Screenshots (2026-11-11, Debian 13, private Xvfb :200, isolated defaults)

Produced by `scripts/screenshots.sh <dir>`. Apps built against, and run on,
the same Debian packages: gnustep-gui 0.32.0-3+b1 headers and runtime,
gnustep-base 1.31.1-3, GCC libobjc (no header/runtime mix, per the lead's
NSTextAlignment note). The editor itself is drawn by the default GNUstep theme.
Theme metadata comes from `examples/` (owner-reviewed drafts), and every value
lives in a scratch defaults root that a read-only probe checks before any app
starts. Each scenario drives the editor's real controls (`-GTSScript`) and
is checked afterwards by reading the value back with `/usr/bin/defaults`.

| File | Host | What it shows |
|---|---|---|
| A-standalone-global.png | standalone | Target "All applications". No global GSTheme, so the built-in theme applies, which has no settings. |
| B1-app-initial.png | standalone | Target Writer (org.example.Writer). Adwaita is set for the app. Style is inherited from global force-dark, Accent colour is set for the app, Control sizes come from Writer's Info.plist, Menus is Automatic, Toolbar is the theme default. |
| B2-app-staged.png | standalone | Accent colour changed to Purple: staged only, so Apply and Cancel are enabled and nothing is written yet. |
| B3-app-applied-restart-receipt.png | standalone | After Apply: the receipt "Saved. Restart the affected applications..." Read-back: Writer GnomeThemeAccentColor = purple, global unchanged. |
| C1-pane-initial.png | in-app pane | The same editor class, on the host's own domain. Gumdrop is set for the app; Menu style comes from DemoNotes' Info.plist. |
| C2-pane-applied.png | in-app pane | Menu style set to the title-bar button and applied (restart receipt). |
| C3-pane-reset-staged.png | in-app pane | Reset staged: the row shows what removing the key reveals (the app's Info.plist value). |
| C4-pane-cancelled.png | in-app pane | Cancel: back to the saved state. Read-back: GumdropMenuStyle = primary (the reset was not written). |
| D-pane-live-receipt.png | in-app pane | Adwaita "Toolbar in header bar" is declared live. The receipt says it was saved and that live application has NOT been confirmed for this app. |
| E-unreadable-refused.png | standalone | The target's domain file is unreadable (mode 000). Nothing is shown as current, nothing is editable, and the error names the file. Read-back: the file is byte-identical afterwards. The scripted "theme Gumdrop" step fails because the control is disabled, which is the expected refusal. |

Not shown or proven: a running theme actually re-rendering (the example
themes are metadata only, not loadable themes), cross-process live
propagation, AppImage/sidecar targets, Windows/macOS.

## AppImage targets (read-only), scenario G (`GTS_SHOTS_ONLY=G`)

| File | What it shows |
|---|---|
| G1-appimage-bound-readonly.png | Sidecar bound to its (stand-in) AppImage by name + sha256. Settings domain from the app's bundle identifier; GSTheme absent, so "Gumdrop (packaged default)" and when AppRun sets it again; bundled theme's settings are described; compatibility not known. Menu style shows the stored value, read-only (the scripted change attempt fails: control disabled). Read-back: nothing written, no GSTheme written, defaults directory listing unchanged. |
| G2-appimage-missing.png | Sidecar whose AppImage is not there: "Not known", no values, nothing editable. |
