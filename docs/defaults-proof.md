# Defaults-domain proof (2026-11-10)

Host iep-platform, Debian 13: gnustep-base 1.31.1, gnustep-gui 0.32.0,
gnustep-make 2.9.3, GCC libobjc, tools-xctest (~/GNUstep). Not yet repeated on
the shared base 6479d4483 / gui 9bd1123a1.

Run: `scripts/run-tests.sh` (creates a 0700 scratch root, 0600 config files,
sets `GNUSTEP_CONFIG_FILE`; checks the master config is readable; builds a
read-only probe with the same gnustep-base as `/usr/bin/defaults` and refuses
unless the probe resolves the defaults root inside the scratch root; runs
xctest in its own process group so cleanup reaps every child before deleting
the scratch config). Each test process repeats the containment check with
symlink-resolved path components before any write. External reads/writes go through `/usr/bin/defaults` as a separate
process. Result: all tests pass (48 at 2026-11-10 late morning), stable over
repeated runs. Self-run only; not yet independently reviewed.

## Findings

1. **Isolation.** `GNUSTEP_USER_CONFIG_FILE` in the environment is ignored by
   base 1.31.1 here; defaults still resolved to `~/GNUstep/Defaults`. A 0600
   copy of `GNUstep.conf` named by `GNUSTEP_CONFIG_FILE`, with absolute
   `GNUSTEP_USER_CONFIG_FILE` and `GNUSTEP_USER_DEFAULTS_DIR`, isolates
   correctly.
2. **Foreign domains stayed stale.** On base 1.31.1, once an
   `NSUserDefaults` instance had loaded a domain that is not in its search
   list, it kept returning the old values under the refresh paths tried
   (`-synchronize`, then re-read immediately and after ~1 s, several
   iterations). This is a finite experiment on one version, not a guarantee
   about every refresh path. A fresh `-initWithUser:` instance +
   `-synchronize` always sees disk. Adding the domain as a suite also refreshes
   it, but would change the editor's own search list. **Decision:** the store
   uses a dedicated fresh instance per snapshot and per commit.
3. **Commit merges per key.** `-setPersistentDomain:forName:` + `-synchronize`
   writes only the keys that instance changed: a key another process added
   inside the window survives, and a key another process removed is not
   resurrected.
4. **Same-key race remains.** If another process writes the same key between
   our conflict check and our `-synchronize`, our value silently wins. The
   check is optimistic conflict detection, not compare-and-swap. No private
   lock was added (other writers would ignore it).
   `testResidualRaceSameKeyLastWriterWins` pins this behaviour.
5. Reset removes exactly one key; unrelated keys and values for inactive themes
   are untouched (tests in `GTSDefaultsDomainStoreTests`, `GTSEditSessionTests`).
6. **Unreadable or damaged domains look empty.** With a domain file at mode
   000, or containing a truncated plist, base 1.31.1 returned an empty domain
   and `-synchronize` returned YES; an unreadable defaults directory looked
   exactly like an absent domain. A write on top would have replaced the
   file. The store therefore checks the file backend itself and fails closed
   (`GTSStoreFailureTests`). This check knows GNUstep's file layout
   (`<defaults root>/<domain>.plist`); a different backend needs its own.
7. "All-or-nothing" applies only to conflicts **observed before commit**: if
   any staged key moved since the baseline, nothing is written. Once the check
   passes, the write is a normal GNUstep `-synchronize`, not a transaction.

Shared base 6479d4483 source review (gnustep owner, msgs 20811/20812) agrees
with finding 1: `GNUSTEP_CONFIG_FILE` is read from the environment;
`GNUSTEP_USER_CONFIG_FILE` comes only from the master config; the config
parser rejects group/other-writable files. The actual resolved-root assertion
remains the safety criterion.

## Harness lifecycle (self-test: scripts/test-runner.sh)

* xctest runs under `setsid`; a process is the runner's only if it is in that
  session AND its environment has `GTS_TEST_ROOT=<this root>`. Only such
  verified PIDs are signalled, individually: TERM, a bounded grace period
  (`GTS_STOP_GRACE`, default 5 s), then KILL, then a final check that reports
  residuals. This also runs after a normal leader exit, so descendants that
  outlive xctest are stopped before the scratch config is deleted.
* Self-test (disposable fake leaders): a lingering descendant after exit 7
  gives status 7, nothing left, root removed; a TERM-resistant leader and
  child with the runner TERMed exit 143 within ~3 s, nothing left.
* In-process guard abort in a disposable subprocess (defaults root outside
  GTS_TEST_ROOT): exit 134 with "REFUSING TO RUN", and no defaults data.
  Finding: gnustep-base in the xctest host created its lock directory
  `<root>/.lck` during startup, before any test code (and so before the
  guard) could run. The in-process guard therefore cannot prevent that
  side effect; the runner's preflight, which verifies the root before
  xctest starts, is the gate that does.

## Limits

* The in-app pane's own `standardUserDefaults` may serve stale values for
  domains it loaded earlier. After a commit it is sent `-synchronize`; whether
  that makes the app's own domain current (and fires
  `NSUserDefaultsDidChangeNotification` for live settings) is UNPROVEN until a
  GUI test shows it.
* Distributed notifications are not posted; running apps learn about changes
  on restart, or through live mechanisms a theme declares (`Apply = live`).
* Only Linux/base 1.31.1 so far. Windows (registry-backed defaults?) and macOS
  need separate checks.
