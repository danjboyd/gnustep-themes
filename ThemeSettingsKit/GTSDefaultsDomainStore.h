/* GTSDefaultsDomainStore.h - exact-domain reads and per-key edits of
   existing GNUstep defaults domains (NSGlobalDomain or a named app domain).

   Concurrency model: OPTIMISTIC conflict detection. Before writing, the store
   re-reads the domain and refuses the commit if any key it is about to change
   differs from the caller's baseline. GNUstep base serialises -synchronize with
   its own defaults lock and (base 1.31.1, probed) merges per changed key, so
   unrelated keys written by other processes are preserved. The check itself is
   not inside that lock: a same-key write by another process between the check
   and our -synchronize is overwritten (last writer wins). That residual window
   is reported, not hidden.

   Failure model: FAIL CLOSED. Base 1.31.1 reports an unreadable or corrupt
   domain file as an empty domain with -synchronize == YES, which is
   indistinguishable from "absent" through the NSUserDefaults API, and a write
   on top of it would replace the file. So every read also checks the file
   backend directly (defaults root + <domain>.plist): an existing file that
   cannot be read or parsed, or an unreadable defaults directory, is an error,
   never an empty baseline. This check is specific to GNUstep's file-based
   defaults backend; other backends need their own. */
#import <Foundation/Foundation.h>

/* Marker meaning "remove this key" in a change dictionary. */
#define GTSRemoveValue [NSNull null]

@interface GTSDomainSnapshot : NSObject
{
  NSString     *_domainName;
  NSDictionary *_values;
}
- (id) initWithDomainName: (NSString*)name values: (NSDictionary*)values;
- (NSString*) domainName;
- (NSDictionary*) values;     /* never nil; empty if domain absent */
- (id) objectForKey: (NSString*)key;
@end

@interface GTSConflict : NSObject
{
  NSString *_key;
  id _baselineValue, _currentValue, _proposedValue;
}
- (id) initWithKey: (NSString*)key baseline: (id)b current: (id)c proposed: (id)p;
- (NSString*) key;
- (id) baselineValue;   /* nil = absent */
- (id) currentValue;    /* nil = absent */
- (id) proposedValue;   /* nil = removal */
@end

typedef enum {
  GTSIdentityFromBundleIdentifier,   /* Info CFBundleIdentifier */
  GTSIdentityFromExecutable,         /* Info NSExecutable / CFBundleExecutable */
  GTSIdentityGuessedFromPath         /* no usable Info: bundle file name; NOT established */
} GTSIdentitySource;

/* Which defaults domain an application uses, and how sure we are. */
@interface GTSApplicationIdentity : NSObject
{
@public
  NSString *_domain;
  GTSIdentitySource _source;
  NSDictionary *_info;
  NSArray *_problems;
}
- (NSString*) domain;
- (GTSIdentitySource) source;
- (NSDictionary*) infoDictionary;   /* nil if missing/unreadable */
- (NSArray*) problems;              /* malformed/missing Info details */
/* YES only when read from a well-formed Info plist. A guessed domain must be
   confirmed by the user before anything is written to it. */
- (BOOL) isEstablished;
@end

@interface GTSDefaultsDomainStore : NSObject
{
  NSUserDefaults *_hostDefaults;
  id   _hookTarget;   /* not retained; tests only */
  SEL  _hookSelector;
}
/* Every snapshot and commit uses a dedicated, freshly created
   NSUserDefaults and releases it afterwards. Reason (probed on base 1.31.1,
   refresh paths -synchronize and re-read after 0-1 s): a long-lived instance
   that has loaded a domain outside its search list kept serving the stale
   copy, so another process' writes stayed invisible.

   hostDefaults (optional, e.g. [NSUserDefaults standardUserDefaults] in an
   in-app pane) is only sent -synchronize after a successful commit. */
- (id) init;
- (id) initWithHostDefaults: (NSUserDefaults*)hostDefaults;
- (NSUserDefaults*) hostDefaults;

/* Absolute directory where this process reads/writes defaults. */
+ (NSString*) defaultsRoot;
/* YES only for GNUstep's file-based defaults backend on a POSIX system,
   which is the only one whose failure modes this store checks. Elsewhere
   every read and write fails with GTSErrorUnsupportedBackend (read-only
   until a backend-specific check exists). */
+ (BOOL) isBackendSupported;

/* Valid domain name: non-empty string, no '/', not starting with '.'. */
+ (BOOL) isValidDomainName: (id)name;

/* Reads one persistent domain exactly as it is on disk now (fresh
   instance), or returns nil with an error (GTSErrorUnreadableDomain,
   GTSErrorInvalidArgument). Absent domain => empty snapshot. */
- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)domainName error: (NSError**)error;

/* Keys in `changes` whose value in `current` differs from `baseline`.
   Returns nil if the two snapshots are of different domains. */
- (NSArray*) conflictsForChanges: (NSDictionary*)changes
                        baseline: (GTSDomainSnapshot*)baseline
                         current: (GTSDomainSnapshot*)current;

/* Applies `changes` (key -> property-list value, or GTSRemoveValue) to the
   exact domain. Keys not in `changes` are left as they are on disk at commit
   time. Errors, each with NOTHING written:
   - GTSErrorInvalidArgument: bad domain name, non-string/empty key, value
     that is not a property list, baseline of another domain;
   - GTSErrorUnreadableDomain: the domain could not be read reliably;
   - GTSErrorConflict: a changed key moved since baseline (*conflicts set);
   GTSErrorWriteFailed: -synchronize reported failure (state unknown).
   Pass baseline nil to skip conflict detection (still preserves unrelated
   keys). */
- (BOOL) commitChanges: (NSDictionary*)changes
              toDomain: (NSString*)domainName
              baseline: (GTSDomainSnapshot*)baseline
             conflicts: (NSArray**)conflicts
                 error: (NSError**)error;

/* Convenience: remove exactly one key (reset to inherited/default). */
- (BOOL) removeKey: (NSString*)key
        fromDomain: (NSString*)domainName
          baseline: (GTSDomainSnapshot*)baseline
         conflicts: (NSArray**)conflicts
             error: (NSError**)error;

/* Reads files only; never loads code. */
+ (GTSApplicationIdentity*) applicationIdentityForBundleAtPath: (NSString*)appPath;
/* The app's Info dictionary (Info-gnustep.plist / Info.plist), or nil. */
+ (NSDictionary*) infoDictionaryForBundleAtPath: (NSString*)appPath;

/* Override point (tests): returns a new, retained NSUserDefaults. */
- (NSUserDefaults*) newDefaultsInstance;

/* TESTING ONLY: called with the domain name after the conflict check passed
   and before the write, to reproduce interleaving writers. */
- (void) setPreWriteHookTarget: (id)target selector: (SEL)selector;
@end
