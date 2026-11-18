# Theme Settings for theme authors

This guide is for people who write a GNUstep theme and want its settings to
show up in Theme Settings, both the app and the editor embedded in other
applications. You add one static file to your theme bundle. The editor reads
that file and never loads your theme's code. It writes the same defaults
keys your theme already reads.

The exact rules, each tied to the code that enforces it, are in
[schema-v1.md](schema-v1.md). This guide covers the usual path.

## 1. Decide what to describe

List the defaults keys your theme already reads that a user might want to
change. For each one, note:

- **Its type.** On/off (`bool`), one of a fixed set of words (`enum`), a
  number (`number`), or free text (`string`).
- **Where it may be set.** For all applications (`global`), for one
  application (`application`), or both.
- **What happens when it isn't set.** Either a fixed value (`static`), or
  something your theme works out at run time (`dynamic`), such as "follows
  GNOME".
- **When a change shows.** Straight away in a running app (`live`), in
  windows opened afterwards (`newWindows`), or only after a restart
  (`restart`).

Describe only keys your theme really reads. The file can't add new
behaviour: it only tells the editor about behaviour that's already there.
Leave out `GSTheme` itself: the editor's Theme row handles it.

## 2. Write `Resources/ThemeSettings.plist`

Put the file at `Resources/ThemeSettings.plist` in the `.theme` bundle. A
text plist, in OpenStep or XML format, works; a binary plist doesn't. A
worked example with three kinds of setting:

```
{
  SchemaVersion = 1;
  Theme = MyTheme;                         /* the GSTheme value that selects it */
  ThemeIdentifier = "org.example.themes.mytheme";
  Settings = (
    {
      Identifier = "mytheme.accent";
      Key = MyThemeAccentColor;
      Type = enum;
      Values = ( { Value = blue; Title = "Blue"; },
                 { Value = green; Title = "Green"; } );
      Scopes = ( global, application );
      Title = "Accent colour";
      Unset = { Behavior = dynamic; Help = "the desktop's accent colour"; };
      Apply = live;
    },
    {
      Identifier = "mytheme.compact";
      Key = MyThemeCompact;
      Type = bool;
      Scopes = ( global, application );
      Title = "Compact controls";
      Help = "Smaller controls and less spacing.";
      Unset = { Behavior = static; Value = NO; };
      /* An app's Info.plist may ask for compact; a user setting still wins. */
      Precedence = ( argument, application, global, applicationInfo );
      Apply = restart;
    },
    {
      Identifier = "mytheme.corner-radius";
      Key = MyThemeCornerRadius;
      Type = number; Minimum = 0; Maximum = 24;
      Scopes = ( global );
      Title = "Window corner radius";
      Unset = { Behavior = static; Value = 8; };
      Apply = newWindows;
    }
  );
}
```

Some things that are easy to get wrong:

- **`Identifier` and `Key` are different things.** `Identifier` names the
  row and must be unique in the file. `Key` is the defaults key, and only
  one setting may describe it.
- **A static `Unset.Value` must be a valid value** for the setting: in the
  enum's `Values`, or within `Minimum`/`Maximum`. Otherwise the setting is
  skipped.
- **A dynamic `Unset` has no `Value`.** Its `Help` finishes the sentence
  "Automatic (…)" in the menu, so write it as a short phrase.
- **A token such as `default` or `auto` in `Values` is a stored value.** It
  isn't the same as "not set". The editor's Reset always removes the key; it
  never writes a token.
- **Spellings are exact.** `Type`, `Apply`, `Scopes` entries and `Status`
  are case-sensitive. A typo skips that one setting, and nothing tells the
  user. That's why the validator (step 4) matters.
- **If unsure about `Apply`, pick the stronger one.** `restart` is always
  true. Say `live` only if your theme really reacts to the change while the
  app runs.

Optional extras, all in [schema-v1.md](schema-v1.md):

- `Precedence`, for keys your theme also reads from an app's Info.plist.
- `Overlaps`, to point out two settings that affect each other.
- `Status = unstable`, to hide a setting by default.
- `RequiredFeatures`.
- `Groups` and `DependsOn` are accepted, but the editor doesn't use them
  yet.

## 3. Read the keys in your theme's code

The editor stores values in a fixed form (schema-v1 section 5). Read them in
a way that accepts that form:

| Type | Stored as | Read with |
|---|---|---|
| `bool` | the strings `YES` / `NO` | `[defaults boolForKey: @"MyThemeCompact"]` |
| `enum` | your canonical spelling from `Values` | `[defaults stringForKey: ...]`. Also compare case-insensitively if you set `CaseInsensitive = YES`. |
| `number` | **the string the user typed**, e.g. `"12.5"` | `[defaults floatForKey: ...]` or `doubleValue`. Don't require an `NSNumber`. |
| `string` | the text as typed | `[defaults stringForKey: ...]` |

Use `[NSUserDefaults standardUserDefaults]` as usual. The values come from
the application's own domain first, then `NSGlobalDomain`, which is the
precedence the editor assumes unless you say otherwise. If a stored value is
one your theme doesn't know (an old token, or a value out of range), fall
back to the unset behaviour rather than failing. The editor shows such
values as they are and doesn't rewrite them.

For `Apply = live`, observe `NSUserDefaultsDidChangeNotification` in your
theme and redraw. GNUstep sends that notification only within one process,
so the standalone editor still tells users that a restart guarantees the
change.

## 4. Check the file

From a checkout of this repository:

```sh
scripts/validate-theme.sh path/to/MyTheme.theme
```

- **Exit status 0** means no errors: every editor will load every setting
  as written.
- **Exit status 1** means at least one error. An error means editors skip
  that setting or reject the file.
- **Warnings** are usually typos in key names, or a dynamic `Unset` without
  `Help`. Fix them too.

The validator reads the file just as the editor does and never loads your
theme's code.

To run the same check on every push, copy the ready-made GitHub Actions job
from [theme-ci.md](theme-ci.md). Adwaita runs it in its CI.

## 5. See it in the editor, without touching your own settings

Download the AppImage ([user guide](user-guide.md), "Install and run the
AppImage"). Then point it at your theme and run it with a throwaway GNUstep
home:

```sh
GTS_HOST_THEME_ROOTS=/path/to/folder-containing-MyTheme.theme \
  packaging/try-isolated.sh path/to/ThemeSettings-*.AppImage
```

`try-isolated.sh` refuses to start unless the AppImage's own `defaults` tool
reads the throwaway home. It also checks afterwards that your real defaults
are unchanged. Choose your theme in the Theme row, then check:

- Every setting has a row, with your titles and help text.
- The first menu item reads "Default (…)" or "Automatic (…)" as you
  intended.
- Apply writes the keys you expect. Run `defaults read` with the same
  `GNUSTEP_HOME`; the script prints the path at the end.
- Your theme, in a test app run with that home, shows the change at the
  time `Apply` promises.

Only the last check proves that your theme reads the keys with the meaning
you described. The validator can't check that.

## 6. Translations (optional)

Add `ThemeSettings.strings` files in your bundle's `<language>.lproj`
folders. The English text is the key, and it covers `Title`, `Help`, enum
value titles and `Unset.Help`:

```
"Accent colour" = "Akzentfarbe";
"the desktop's accent colour" = "die Akzentfarbe des Desktops";
```

## 7. Ship it

- Install the plist with the theme. In a gnustep-make theme project, add
  it to the theme's resource files so that it lands in `Resources/`.
- Older installed copies of your theme without the file show "This
  theme does not describe any settings."
- After release, keep the file in step with the code. A key your theme stops
  reading should leave the file in the same commit.

Examples to copy from: [`examples/`](../examples) has the files for
Adwaita, Gumdrop and WinUITheme. They use `Precedence` filters,
`Overlaps`, case-insensitive enums and dynamic defaults.
