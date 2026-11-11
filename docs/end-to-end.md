# End-to-end checks with real themes

These runs check that a change made in the editor really changes how an
application looks, not just the stored value. They run on a private Xvfb
with scratch defaults and theme folders, and never install anything.

Both themes need the clang/libobjc2 GNUstep runtime (Adwaita uses
associated objects), so the apps and themes were built with a clang GNUstep
toolchain, and `scripts/screenshots.sh` was pointed at that toolchain:

```sh
. <toolchain>/System/Library/Makefiles/GNUstep.sh      # plus its libs on LD_LIBRARY_PATH
GTS_MASTER_CONF=<toolchain>/etc/GNUstep/GNUstep.conf \
GTS_DEFAULTS_TOOL=<toolchain>/Local/Tools/defaults \
GTS_E2E_THEMES=<dir with the built .theme> GTS_SHOTS_ONLY=J scripts/screenshots.sh <out>
```

## Adwaita (scenario J), plugins-themes-Adwaita 4c9edba, 2026-11-11

DemoNotes runs under the built Adwaita theme. The pane's theme note names
the isolated user copy of `Adwaita.theme`. In DemoNotes' own editor pane, the
colour scheme went from Light to Dark and the accent from Blue to Red, and
Apply saved both (checked by reading the defaults back).

| Before (light, blue) | After relaunch (dark, red) |
|---|---|
| ![](screenshots/e2e/J1-adwaita-before-light-blue.png) | ![](screenshots/e2e/J4-adwaita-after-dark-red.png) |
| ![](screenshots/e2e/J2-pane-before-blue.png) | ![](screenshots/e2e/J5-pane-after-dark-red.png) |

To show the accent colour, the pane captures stage a throwaway change, which
enables Apply, the default button that Adwaita draws in the accent colour.
That change is cancelled each time, and the run checks it was never saved.

**Restart needed, and the UI says so.** Right after Apply the same running
app is still light and blue, with "Saved. Restart the affected applications
to see every change." Both rows also say "Takes effect when the application
restarts".

![Same app right after Apply](screenshots/e2e/J3-pane-applied.png)

## Gumdrop (scenario K), gnustep-funthemes 5e76007, 2026-11-11

The editor changed all five settings, and the read-back confirms all five
were saved: menu style menubar, interface font DejaVuSerif, font size 20,
corner radius 0, shadows NO. The theme loaded (its striped bar is visible).
**No visible effect was demonstrated** with this harness:

* **Interface font and size** (`NSFont`, `NSFontSize`): DemoNotes' text did
  not change. Gumdrop's theme domain sets the role fonts (control content,
  labels and so on) explicitly, and controls use those, so the general
  interface font rarely shows. The rows' help text says role fonts keep
  their own defaults; in practice that makes these two rows weak. Reported
  to the theme owner.
* **Menu style**: the capture covers a window's content only, not menus,
  and this host has no full-screen capture tool. Not shown.
* **Corner radius and shadows**: applied by display backends that draw the
  window frame. The plain Xvfb backend here ignores both, as the help text
  says. Not shown.

Gumdrop still needs a capture of the whole screen, on a backend that draws
window frames, with a demo that uses the role fonts.
