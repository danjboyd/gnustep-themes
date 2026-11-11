# Theme Settings: user guide

Theme Settings lets you choose a GNUstep theme and change that theme's
settings, for all your applications at once or for one application, without
editing defaults by hand. The screenshots below come from
`scripts/screenshots.sh`: they use the example themes in `examples/` and
scratch settings, never anyone's real ones.

There are two ways to reach the same editor:

* **The Theme Settings app** (`ThemeSettingsApp`), which edits settings for
  all applications or for any application you pick.
* **An application's own preferences**, for applications that embed the
  editor (`ThemeSettingsDemo` shows how). These edit that application's
  settings, with a checkbox to switch to all applications instead.

## Choosing what to change: the target

The **Target** menu at the top of the app picks whose settings you see:

* **All applications**: your global settings (GNUstep's `NSGlobalDomain`).
  Every application uses these unless it has its own value.
* **An application**: the applications the app finds in your standard
  Applications folders are listed by name. **Other application…** opens any
  other `.app`. A value set here applies to that application only.
* **AppImage theme information…**: shows what an AppImage package says
  about its theme. It's read-only; see "AppImages" below.

![All applications](screenshots/A-standalone-global.png)

To open the app on a particular application from a terminal:

```sh
openapp ThemeSettings.app -GTSTargetApp /path/to/Some.app
```

## The theme

The **Theme** row picks the theme, for the current target. The lines under it
say where the current choice comes from, which copy of the theme is used
(and where it's installed), and anything unusual, for example a theme that
is selected but not installed. Whether a theme's code works with your GNUstep
version is never checked here.

## Settings

Below the theme come the settings the selected theme describes. A theme
that describes none says so. Each row has:

* **The control**: a menu of choices, or a text field for a name or number.
  The first menu item (for example "Automatic (…)" or "Default (Off)") means
  "no value of my own": it removes your value, so the application falls back
  to whatever applies next.
* **The state line** (small grey text) says where today's value comes from:

  | State | Meaning |
  |---|---|
  | Set for all applications / Set for this application | You (or someone) stored a value for this target. |
  | Inherited from all applications | Not set for this application; the global value applies. |
  | From the application's Info.plist | Not set anywhere; the application's own preference applies. |
  | Theme default | Not set anywhere; the theme's fixed default applies. |
  | Automatic | Not set anywhere; the theme works it out at run time (the menu item says how). |

* **When it takes effect**, at the end of the help text: "Takes effect when
  the application restarts", or "Applies to windows and panels opened after
  saving". Settings with neither note are applied by the theme while the
  application runs.
* **Reset** removes this target's value, like choosing the first menu item.

![An application target with a staged change](screenshots/B2-app-staged.png)

## Apply, Cancel, Reload

Changes are **staged** until you press **Apply** (or Return). **Cancel**
drops staged changes, and **Reload** re-reads the stored settings.

* Text typed in a field counts, even if you didn't press Tab first.
* Text that isn't valid (a number out of range, for example) is never saved.
  The field keeps what you typed, selected, and the message at the bottom
  says why. Leave the field, or press Reload, to get the stored value back.
* If another program changed the same setting since you opened it, Apply
  refuses and lists the settings that changed; press Reload and try again.
  Nothing is overwritten silently.
* After Apply the message at the bottom says what happened, for example
  "Saved. Restart the affected applications to see every change."

![After Apply: saved, restart needed](screenshots/B3-app-applied-restart-receipt.png)
![Invalid text is not saved](screenshots/F2-invalid-blocked.png)

## When nothing can be changed

Sometimes the editor shows settings but greys everything out. The message
at the bottom says why:

* **The settings can't be read**, for example a damaged or unreadable
  settings file. Nothing is shown or written.

  ![Unreadable settings](screenshots/E-unreadable-refused.png)

* **Windows (for now)**: settings are shown, read-only, with "this defaults
  backend is not supported for editing yet". Editing on Windows will come
  once writing there has been verified.
* **A theme asks for something this version doesn't understand**: its rows
  are shown read-only, with a note.

## AppImages

An AppImage may come with a `.themes.json` file next to it, describing the
theme it uses. Choose **AppImage theme information…** and open that file to
see:

* which theme the package sets by default, and when it writes it;
* what this editor's own settings store holds for that application. An
  AppImage may keep its settings somewhere else, so these values are not
  confirmed as the AppImage's own.

This view never changes anything.

![AppImage theme information](screenshots/G1-appimage-bound-readonly.png)

## For theme authors

To make your theme's settings appear here, add a `ThemeSettings.plist` to
the theme bundle: see the [README](../README.md) and
[schema-v1.md](schema-v1.md), and check it with
`scripts/validate-theme.sh`.
