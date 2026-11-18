# Live apply: design note

Status: design note. Option A (section 3) is drafted locally for
gnustep-tools-lead's review (#40600). B, C and D are not started. The question: can a running application pick up a setting saved
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
| `GSTheme` | "Restart …" | **libs-gui may switch the theme live.** `+[GSTheme defaultsDidChange:]` observes the notification and calls `+setTheme:` when the name differs (libs-gui `Source/GSTheme.m`). The observer is added only inside `+setTheme:`, though, so it is registered only once the app has activated a theme other than the default. An app that started with the plain GNUstep look doesn't switch; an app already using a theme does, within about 30 s (scenario M, section 2a). A live switch can be incomplete: some views keep old metrics until they're redrawn or reopened. "Restart" is still the right promise. |
| Theme key, `Apply = live` | "may update; a restart is the guaranteed way" | True if the theme observes the notification and redraws. That's up to each theme and unproven for each one. |
| `Apply = newWindows` | "Windows and panels opened from now on" | True only after the next tick. A window opened within 30 s of Apply may still use the old value. |
| `Apply = restart` | "Restart …" | Unchanged. |

**The editor's own window.** A ThemeSettings.app built from source didn't
pin its own `GSTheme`; the AppImage and MSI launchers pass `-GSTheme
GNUstep`. Scenario M's control run (pin removed) showed the consequence.
The source-built app started under the user's global theme (Gumdrop), not
the plain GNUstep look. 30 s after a global change it switched again, to
WinUITheme. The Debian package's launcher still needs checking.

### 2a. Scenario M (2026-11-18)

`GTS_SHOTS_ONLY=M scripts/screenshots.sh` on this host (Debian
gnustep-base 1.31.1-3, gnustep-gui 0.32.0-3+b1, GCC). It runs on a private
Xvfb, with the defaults root and the user Library both checked inside the
scratch root before anything starts. Both apps start with `GSTheme Gumdrop`
for all applications. 5 s in, `GSTheme WinUITheme` is written to
NSGlobalDomain from outside:

| Run | Control app (pins nothing) | Theme Settings |
|---|---|---|
| With the pin (the draft) | started Gumdrop, switched to WinUITheme | started GNUstep, stayed GNUstep: **ok** |
| Pin removed (control) | started Gumdrop, switched to WinUITheme | started **Gumdrop**, switched to WinUITheme 30 s later: check fails as it should |

An earlier run, with both apps starting under the default theme, showed no
switch in either app. That is how the observer rule above was found.

These results are for this GNUstep version. Other libs-gui versions may
register the observer differently. Settings other than `GSTheme` keep their
own `Apply` requirement: most still need a restart.

### 2b. Test notes: the slip during the first experiment

The first Foundation-tool run (section 1) used a scratch `GNUstep.conf`
with mode 0664. gnustep-base refused it ("writable by someone other than
its owner … Ignoring it") and fell back to the real configuration. One
`defaults write NSGlobalDomain LiveKey one` therefore landed in the agent
host account's real `~/GNUstep/Defaults`. That is the iep agent host, not
Dan's laptop. It was found straight away:

- The file held only that key.
- It was removed with `defaults delete NSGlobalDomain LiveKey`.
  `NSGlobalDomain.plist` no longer exists, and no other key was touched.
- The test process was stopped.

The rerun used mode 644 and refused to write unless `gnustep-config`
resolved inside the scratch root. Since then, all of this work has used
`scripts/screenshots.sh`, which checks the effective defaults root and
(from this change) the user Library before starting anything.

## 3. Options

**A. Wording, plus pinning the app's own theme (drafted).**

- After a change that includes `GSTheme`, the receipt still says to
  restart. It adds: "Running applications that already use a theme may
  switch to the new theme by themselves, usually within about 30 seconds,
  but may not redraw everything until they restart." Unit test:
  `testThemeChangeReceiptMentionsLiveSwitchOnlyForTheme`.
- `ThemeSettingsApp/main.m` pins `GSTheme GNUstep` in its argument domain
  unless `-GSTheme` was given, and logs its window's theme. Scenario M
  checks this.
- `newWindows` wording is unchanged. The 30 s tick applies there too, but
  that hasn't been measured with a real theme.

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

1. **A**, drafted locally (section 3). It's waiting for the lead's review
   before it's pushed.
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
