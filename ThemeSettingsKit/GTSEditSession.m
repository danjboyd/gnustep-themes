/* GTSEditSession.m */
#import "GTSEditSession.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"

static BOOL
same(id a, id b)
{
  if (a == nil || b == nil) return a == b;
  return [a isEqual: b];
}

@implementation GTSEditSession

- (id) initWithStore: (GTSDefaultsDomainStore*)store domain: (NSString*)domain
{
  if ((self = [super init]) != nil)
    {
      _store = [store retain];
      _domain = [domain copy];
      _staged = [[NSMutableDictionary alloc] init];
      _restartKeys = [[NSMutableSet alloc] init];
      _baseline = [[store snapshotForDomain: domain] retain];
    }
  return self;
}

- (void) dealloc
{
  [_store release]; [_domain release]; [_baseline release];
  [_staged release]; [_restartKeys release];
  [super dealloc];
}

- (NSString*) domain { return _domain; }
- (GTSDomainSnapshot*) baseline { return _baseline; }
- (NSDictionary*) stagedChanges { return [[_staged copy] autorelease]; }
- (BOOL) hasChanges { return [_staged count] > 0; }

- (BOOL) needsRestart
{
  NSEnumerator *e = [_staged keyEnumerator];
  NSString *k;
  while ((k = [e nextObject]) != nil)
    if ([_restartKeys containsObject: k]) return YES;
  return NO;
}

- (GTSDomainSnapshot*) pendingSnapshot
{
  NSMutableDictionary *d = [[[_baseline values] mutableCopy] autorelease];
  NSEnumerator *e = [_staged keyEnumerator];
  NSString *k;
  while ((k = [e nextObject]) != nil)
    {
      id v = [_staged objectForKey: k];
      if (v == GTSRemoveValue) [d removeObjectForKey: k];
      else [d setObject: v forKey: k];
    }
  return [[[GTSDomainSnapshot alloc] initWithDomainName: _domain values: d] autorelease];
}

- (void) stage: (id)v key: (NSString*)key restart: (BOOL)restart
{
  id base = [_baseline objectForKey: key];
  if ((v == GTSRemoveValue && base == nil) || same(v, base))
    [_staged removeObjectForKey: key];   /* back to baseline: nothing to do */
  else
    [_staged setObject: v forKey: key];
  if (restart) [_restartKeys addObject: key];
}

- (BOOL) stageValue: (id)value
         forSetting: (GTSSettingDescriptor*)s
            problem: (NSString**)problem
{
  NSString *p = [s problemWithValue: value];
  if (p != nil)
    {
      if (problem) *problem = p;
      return NO;
    }
  [self stage: [s storedFormOfValue: value] key: [s key]
      restart: [s applyPolicy] == GTSApplyRestart];
  return YES;
}

- (void) stageResetForSetting: (GTSSettingDescriptor*)s
{
  [self stage: GTSRemoveValue key: [s key] restart: [s applyPolicy] == GTSApplyRestart];
}

- (void) stageThemeSelection: (NSString*)name
{
  [self stage: (name ? (id)name : (id)GTSRemoveValue) key: @"GSTheme" restart: YES];
}

- (void) discardChanges
{
  [_staged removeAllObjects];
}

- (NSArray*) rebase
{
  GTSDomainSnapshot *fresh = [_store snapshotForDomain: _domain];
  NSMutableSet *keys = [NSMutableSet setWithArray: [[_baseline values] allKeys]];
  NSMutableArray *changed = [NSMutableArray array];
  NSEnumerator *e;
  NSString *k;
  [keys addObjectsFromArray: [[fresh values] allKeys]];
  e = [keys objectEnumerator];
  while ((k = [e nextObject]) != nil)
    if (!same([_baseline objectForKey: k], [fresh objectForKey: k]))
      [changed addObject: k];
  ASSIGN(_baseline, fresh);
  /* Drop staged entries that now equal the on-disk state. */
  e = [[_staged allKeys] objectEnumerator];
  while ((k = [e nextObject]) != nil)
    {
      id v = [_staged objectForKey: k];
      if ((v == GTSRemoveValue && [fresh objectForKey: k] == nil) || same(v, [fresh objectForKey: k]))
        [_staged removeObjectForKey: k];
    }
  return [changed sortedArrayUsingSelector: @selector(compare:)];
}

- (BOOL) applyWithConflicts: (NSArray**)conflicts error: (NSError**)error
{
  if ([_staged count] == 0)
    {
      if (conflicts) *conflicts = nil;
      return YES;
    }
  if (![_store commitChanges: _staged toDomain: _domain baseline: _baseline
                   conflicts: conflicts error: error])
    return NO;
  [_staged removeAllObjects];
  ASSIGN(_baseline, [_store snapshotForDomain: _domain]);
  return YES;
}
@end
