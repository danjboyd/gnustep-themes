/* GTSDefaultsDomainStore.h - exact-domain reads and per-key edits of
   existing GNUstep defaults domains (NSGlobalDomain or a named app domain).

   Concurrency model: OPTIMISTIC conflict detection. Before writing, the store
   re-reads the domain and refuses the commit if any key it is about to change
   differs from the caller's baseline. GNUstep base serialises -synchronize with
   its own defaults lock and (base 1.31, probed) merges per changed key, so
   unrelated keys written by other processes are preserved. The check itself is
   not inside that lock: a same-key write by another process between the check
   and our -synchronize is overwritten (last writer wins). That residual window
   is reported, not hidden. */
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

@interface GTSDefaultsDomainStore : NSObject
{
  NSUserDefaults *_hostDefaults;
  id   _hookTarget;   /* not retained; tests only */
  SEL  _hookSelector;
}
/* Every snapshot and commit uses a dedicated, freshly created
   NSUserDefaults (-initWithUser:) and releases it afterwards. Reason (probed
   on base 1.31.1): once a long-lived instance has loaded a domain that is not
   in its search list, -synchronize never reloads it, so another process'
   writes stay invisible and conflict checks would be blind.

   hostDefaults (optional, e.g. [NSUserDefaults standardUserDefaults] in an
   in-app pane) is only sent -synchronize after a successful commit. */
- (id) init;
- (id) initWithHostDefaults: (NSUserDefaults*)hostDefaults;
- (NSUserDefaults*) hostDefaults;

/* Absolute directory where this process reads/writes defaults. */
+ (NSString*) defaultsRoot;

/* Reads one persistent domain exactly as it is on disk now (fresh
   instance). Never the merged search-list view. */
- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)domainName;

/* Keys in `changes` whose current on-disk value differs from `baseline`. */
- (NSArray*) conflictsForChanges: (NSDictionary*)changes
                        baseline: (GTSDomainSnapshot*)baseline
                         current: (GTSDomainSnapshot*)current;

/* Applies `changes` (key -> value, or GTSRemoveValue) to the exact domain.
   Keys not in `changes` are left exactly as they are on disk at commit time.
   If baseline is non-nil and a changed key moved since baseline, nothing is
   written, *conflicts is set and NO is returned (error code GTSErrorConflict).
   Pass baseline nil to force (still preserves unrelated keys). */
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

/* Defaults domain an application uses: CFBundleIdentifier from its Info
   plist, else its executable/process name. Reads files only. */
+ (NSString*) applicationDomainForBundleAtPath: (NSString*)appPath;
/* The app's Info dictionary (Info-gnustep.plist / Info.plist), or nil. */
+ (NSDictionary*) infoDictionaryForBundleAtPath: (NSString*)appPath;

/* TESTING ONLY: called with the domain name after the conflict check passed
   and before the write, to reproduce interleaving writers. */
- (void) setPreWriteHookTarget: (id)target selector: (SEL)selector;
@end
