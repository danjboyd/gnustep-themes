# Defaults-domain proof (2026-11-10)

Host iep-platform, Debian 13: gnustep-base 1.31.1, gnustep-gui 0.32.0,
gnustep-make 2.9.3, GCC libobjc, tools-xctest (~/GNUstep). Not yet repeated on
the shared base 6479d4483 / gui 9bd1123a1.

Run: `scripts/run-tests.sh` (creates a 0700 scratch root, 0600 config files,
sets `GNUSTEP_CONFIG_FILE`, aborts if `GSDefaultsRootForUser()` is not under
it). External reads/writes go through `/usr/bin/defaults` as a separate
process. Result: 40/40 tests pass, stable over repeated runs.

## Findings

1. **Isolation.** `GNUSTEP_USER_CONFIG_FILE` in the environment is ignored by
   base 1.31.1 here; defaults still resolved to `~/GNUstep/Defaults`. A 0600
   copy of `GNUstep.conf` named by `GNUSTEP_CONFIG_FILE`, with absolute
   `GNUSTEP_USER_CONFIG_FILE` and `GNUSTEP_USER_DEFAULTS_DIR`, isolates
   correctly.
2. **Foreign domains are cached forever.** Once an `NSUserDefaults` instance
   has loaded a domain that is not in its search list, `-synchronize` never
   reloads it (still stale seconds later). A fresh `-initWithUser:` instance +
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

## Limits

* The in-app pane's own `standardUserDefaults` may serve stale values for
  domains it loaded earlier. After a commit it is sent `-synchronize`, which is
  enough for its own domain (in its search list), but live-apply still needs
  proof in a GUI run.
* Distributed notifications are not posted; running apps learn about changes
  on restart, or through live mechanisms a theme declares (`Apply = live`).
* Only Linux/base 1.31.1 so far. Windows (registry-backed defaults?) and macOS
  need separate checks.
