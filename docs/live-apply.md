# Live apply: design note

Status: **design only, nothing implemented.** It's written to help scope
the work. The question: can a running application pick up a setting saved
in Theme Settings without a restart, and what would it take to say so
truthfully?

## 1. What GNUstep already does (measured)

gnustep-base re-reads the defaults database on a timer and tells the
process when something changed:

- The main thread's run loop posts `GSHousekeeping` every 30 seconds
  (libs-base `Source/NSRunLoop.m`, the housekeeping timer).
- `NSUserDefaults` observes it and calls `-synchronize`
  (`Source/NSUserDefaults.m`, `-init…`). `-synchronize` re-reads the
  database if its modification date is newer than the last sync
  (`-wantToReadDefaultsSince:`), and posts
  `NSUserDefaultsDidChangeNotification` if anything changed.

**Experiment (2026-11-18, this host, Debian gnustep-base 1.31.1, GCC).** A
Foundation tool ran its main run loop and logged each
`NSUserDefaultsDidChangeNotification`. It ran against a scratch defaults
root, and I checked that `defaults` resolved to that root before any
write. A second process ran `defaults write NSGlobalDomain LiveKey …`
twice, at 3 s and at 43 s:

```
start LiveKey=(null)
30.0s notification; LiveKey=one
60.0s notification; LiveKey=two
```

So a write from another process **does reach a running app**, as a normal
`NSUserDefaultsDidChangeNotification`, at the next housekeeping tick: within
30 seconds, with no editor-side change. The libs-base source quoted above is
the tree gnustep-cli builds (`0703fa4a6`, 2026-03-30); the 1.31.1 run shows
the same behaviour.

Limits of the experiment:

- It used one Foundation tool, not a GUI app. A GUI app's main loop is an
  `NSRunLoop` too, but a modal loop or a busy main thread delays the tick.
- It used the file backend only. On Windows the registry backend has its
  own code, and the editor refuses to edit that backend anyway.
- It wasn't run against the clang/libobjc2 build. It's expected to behave
  the same, but that hasn't been run.

## 2. What that means for each kind of setting

| Setting | Today's receipt | What really happens in a running app |
|---|---|---|
| `GSTheme` | "Restart …" | **libs-gui switches the theme live.** `+[GSTheme defaultsDidChange:]` observes the notification and calls `+setTheme:` when the name differs (libs-gui `Source/GSTheme.m`). So within about 30 s, every running app that doesn't set its own `GSTheme` changes theme. A live switch is known to be imperfect: some views keep old metrics until they're redrawn or reopened. "Restart" is still the right promise; the receipt should also warn that apps may switch on their own. |
| Theme key, `Apply = live` | "may update; a restart is the guaranteed way" | True if the theme observes the notification and redraws. That's up to each theme and unproven for each one. |
| `Apply = newWindows` | "Windows and panels opened from now on" | True only after the next tick. A window opened within 30 s of Apply may still use the old value. |
| `Apply = restart` | "Restart …" | Unchanged. |

**One consequence to check now:** a ThemeSettings.app built from source
doesn't pin its own `GSTheme`. The AppImage and MSI launchers pass
`-GSTheme GNUstep`. So an app built from source that applies a global
theme change may restyle its own window within 30 s. The Debian package
needs the same check. This is a correctness issue in today's code, separate
from live apply.

## 3. Options

**A. Wording only (smallest).** Change the receipts to what is now known:

- After a global `GSTheme` change, running applications may switch within
  about 30 seconds, and restart them for a clean result.
- `newWindows` applies to windows opened after the next update, within
  30 s.

Pin `-GSTheme GNUstep` for the app itself in its Info.plist or `main.m`,
not only in the launchers. No new mechanism. The risk is low, and it needs
a GUI test of the GSTheme case.

**B. Faster pickup, from the editor's side only.** Nothing in another
process can be made to re-read sooner without that process's cooperation.
`NSDistributedNotificationCenter` needs `gdnc` to be running. Nothing
listens for a theme-settings notification today, and the AppImage, MSI and
Windows setups don't guarantee `gdnc`. On its own this buys nothing.

**C. A cooperative signal (bigger).** The editor posts a distributed
notification after Apply, for example
`org.gnustep.ThemeSettings.DidApply` with the domain and keys in userInfo.
A theme, or libs-gui, observes it and calls
`[[NSUserDefaults standardUserDefaults] synchronize]`, so pickup is
immediate. This needs:

- agreement from theme owners, or from libs-gui upstream, which falls under
  the upstream rules;
- `gdnc` to be running;
- a fallback to the 30 s tick when it isn't.

It adds a protocol that has to be kept stable. It's worth doing only if
30 s turns out to be too slow in practice.

**D. In-process host (already possible).** An app embedding the editor
for its own domain writes through its own `NSUserDefaults`. The change is
then immediate in that process, with no tick to wait for. The receipt
already treats this case separately (`editsHostProcess`). What's missing
is the GUI proof per theme, which embedding.md already lists as
unconfirmed.

## 4. Recommendation

1. **Do A now.** Correct the wording and pin the app's own theme. Add a
   GUI check: on a private Xvfb with a scratch home, a running test app
   switches theme within about 35 s of a global `GSTheme` Apply, and the
   ThemeSettings window doesn't.
2. **Prove `live` for Adwaita** (its accent and style keys) in a running
   ThemeDemo, both from Theme Settings (the tick path) and from the PR #150
   panel (the in-process path, D). Only then can a receipt say "applied"
   for `live` settings, and only for that combination. adwaita owns
   ThemeDemo.
3. **Park C.** Revisit it only if users find 30 s too slow, and then as an
   upstream proposal, not as something private to this project.

## 5. Risks

- **Live theme switching in libs-gui is imperfect.** Users may see a
  half-switched app and blame the editor. Mitigation: the receipt names the
  behaviour, and recommends a restart.
- **Ticks are per process, and a busy app is late.** Never promise a
  time, only "usually within about 30 seconds".
- **Per-app domains.** An app with its own `GSTheme`, or its own value for
  a key, ignores a global change. That's correct; the editor's state lines
  already show it.
- **Proof stays per theme.** The schema's `live` is the theme's claim. The
  editor still mustn't report a live change as confirmed without a GUI
  check (schema-v1 section 8).
