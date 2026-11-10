# Screenshots (2026-11-10, iep-platform, private Xvfb :200, isolated defaults)

Produced by `scripts/screenshots.sh <dir>`: Debian gnustep-gui 0.32.0 with
the default GNUstep theme drawing the editor itself. Theme metadata comes from
`examples/` (owner-reviewed drafts), and the defaults are seeded only in a
scratch defaults root.

| File | What it shows |
|---|---|
| standalone-global.png | Standalone configurator, target "All applications": no global GSTheme, so the theme is GNUstep's built-in one, which has no settings. |
| standalone-app-adwaita.png | Same app, target Writer (org.example.Writer, a stand-in bundle). GSTheme=Adwaita is set for the app. Style is inherited from the global value force-dark, Accent colour is overridden for the app (Reset enabled), Control sizes come from Writer's Info.plist (compact), Menus is Automatic (dynamic default), Toolbar in header bar is the theme default. |
| inapp-pane-gumdrop.png | DemoNotes app's in-app pane: the same editor class, targeting the host's own domain (org.gnustep.themesettings.DemoNotes) by default, with an explicit "all applications" switch. GSTheme=Gumdrop for the app; Menu style comes from DemoNotes' Info.plist (menubar). |

Not shown or proven yet: Apply from the GUI in a running app, live
propagation to another process, and Windows/macOS.
