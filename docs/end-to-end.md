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

## Gumdrop (scenarios K and L), gnustep-funthemes 5e76007, 2026-11-11

The editor changed all five settings, and the read-back confirms all five
were saved: menu style menubar, interface font DejaVuSerif, font size 20,
corner radius 0, shadows NO. The theme loaded.

**Interface font and size: visible.** After relaunch, the editor pane's own
controls (pop-up menus, text fields, buttons, the checkbox) are drawn in
DejaVu Serif at 20 points instead of DejaVu Sans. Standard GNUstep cells use
the system font (`NSFont`/`NSFontSize`).

| Before (theme defaults) | After relaunch (DejaVuSerif, 20) |
|---|---|
| ![](screenshots/e2e/K2-gumdrop-pane-before.png) | ![](screenshots/e2e/K5-gumdrop-pane-after-serif-20.png) |

A correction: an earlier version of this page said these rows had no
visible effect. It looked only at DemoNotes' main window, whose text is an
`NSTextView`, and text views use the *user* font (`NSUserFont`), not the
system font.

**Control-content font (scenario L): no visible effect on standard
controls.** With a draft settings file that added `NSControlContentFont`
rows, setting it to DejaVuSerif 20 left the same pane unchanged after
relaunch. Standard cells don't ask for the control-content font, so such a
row would mislead.

| Before | After relaunch (NSControlContentFont DejaVuSerif, 20) |
|---|---|
| ![](screenshots/e2e/L1-gumdrop-pane-before.png) | ![](screenshots/e2e/L3-gumdrop-pane-control-font-after.png) |

**Not demonstrated yet:**

* **Menu style:** the captures cover a window's content only, not menus.
* **Corner radius and shadows:** these need a backend that draws window
  frames (`-GSX11HandlesWindowDecorations NO -GSBackWindowShadows YES`).
  Plain Xvfb here ignores both.

The owner's GNOME Shell `--x11` rig, with full-screen captures, is the plan
for these three. This host lacks gnome-shell, xdotool and ImageMagick.
