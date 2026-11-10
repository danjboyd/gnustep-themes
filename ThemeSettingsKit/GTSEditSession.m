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

@implementation GTSApplyReceipt
- (void) dealloc
{
  [_committed release]; [_refreshError release];
  [super dealloc];
}
- (NSDictionary*) committedChanges { return _committed; }
- (int) applyRequirement { return _requirement; }
- (BOOL) refreshFailed { return _refreshFailed; }
- (NSError*) refreshError { return _refreshError; }
@end

@implementation GTSEditSession

- (id) initWithStore: (GTSDefaultsDomainStore*)store
              domain: (NSString*)domain
               error: (NSError**)error
{
  GTSDomainSnapshot *b = [store snapshotForDomain: domain error: error];
  if (b == nil)
    {
      [self release];
      return nil;
    }
  if ((self = [super init]) != nil)
    {
      _store = [store retain];
      _domain = [domain copy];
      _staged = [[NSMutableDictionary alloc] init];
      _applyByKey = [[NSMutableDictionary alloc] init];
      _baseline = [b retain];
    }
  return self;
}

- (void) dealloc
{
  [_store release]; [_domain release]; [_baseline release];
  [_staged release]; [_applyByKey release];
  [super dealloc];
}

- (NSString*) domain { return _domain; }
- (GTSDomainSnapshot*) baseline { return _baseline; }
- (NSDictionary*) stagedChanges { return [[_staged copy] autorelease]; }
- (BOOL) hasChanges { return [_staged count] > 0; }
- (BOOL) needsRebase { return _needsRebase; }

- (int) requirementForKeys: (NSArray*)keys
{
  NSEnumerator *e = [keys objectEnumerator];
  NSString *k;
  int req = GTSApplyLive;
  while ((k = [e nextObject]) != nil)
    {
      int r = [[_applyByKey objectForKey: k] intValue];
      if (r > req) req = r;
    }
  return req;
}

- (int) applyRequirement
{
  return [self requirementForKeys: [_staged allKeys]];
}

- (BOOL) needsRestart
{
  return [self applyRequirement] == GTSApplyRestart;
}

static NSDictionary *
applyChanges(NSDictionary *base, NSDictionary *changes)
{
  NSMutableDictionary *d = [[base mutableCopy] autorelease];
  NSEnumerator *e = [changes keyEnumerator];
  NSString *k;
  while ((k = [e nextObject]) != nil)
    {
      id v = [changes objectForKey: k];
      if (v == GTSRemoveValue) [d removeObjectForKey: k];
      else [d setObject: v forKey: k];
    }
  return d;
}

- (GTSDomainSnapshot*) pendingSnapshot
{
  return [[[GTSDomainSnapshot alloc] initWithDomainName: _domain
    values: applyChanges([_baseline values], _staged)] autorelease];
}

- (void) stage: (id)v key: (NSString*)key apply: (int)apply
{
  id base = [_baseline objectForKey: key];
  if ((v == GTSRemoveValue && base == nil) || same(v, base))
    [_staged removeObjectForKey: key];   /* back to baseline: nothing to do */
  else
    [_staged setObject: v forKey: key];
  [_applyByKey setObject: [NSNumber numberWithInt: apply] forKey: key];
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
  [self stage: [s storedFormOfValue: value] key: [s key] apply: [s applyPolicy]];
  return YES;
}

- (void) stageResetForSetting: (GTSSettingDescriptor*)s
{
  [self stage: GTSRemoveValue key: [s key] apply: [s applyPolicy]];
}

- (void) stageThemeSelection: (NSString*)name
{
  [self stage: (name ? (id)name : (id)GTSRemoveValue) key: @"GSTheme" apply: GTSApplyRestart];
}

- (void) discardChanges
{
  [_staged removeAllObjects];
}

- (NSArray*) rebaseWithError: (NSError**)error
{
  GTSDomainSnapshot *fresh = [_store snapshotForDomain: _domain error: error];
  NSMutableSet *keys;
  NSMutableArray *changed = [NSMutableArray array];
  NSEnumerator *e;
  NSString *k;

  if (fresh == nil)
    return nil;                         /* keep baseline + staged */
  keys = [NSMutableSet setWithArray: [[_baseline values] allKeys]];
  [keys addObjectsFromArray: [[fresh values] allKeys]];
  e = [keys objectEnumerator];
  while ((k = [e nextObject]) != nil)
    if (!same([_baseline objectForKey: k], [fresh objectForKey: k]))
      [changed addObject: k];
  ASSIGN(_baseline, fresh);
  _needsRebase = NO;
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

- (GTSApplyReceipt*) applyWithConflicts: (NSArray**)conflicts error: (NSError**)error
{
  GTSApplyReceipt *r;
  GTSDomainSnapshot *fresh;
  NSError *refreshErr = nil;
  NSDictionary *committed;

  if (conflicts) *conflicts = nil;
  if (_needsRebase)
    {
      if (error) *error = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorUnreadableDomain
        userInfo: [NSDictionary dictionaryWithObject:
          @"settings must be reloaded before saving again" forKey: NSLocalizedDescriptionKey]];
      return nil;
    }
  committed = [[_staged copy] autorelease];
  r = [[[GTSApplyReceipt alloc] init] autorelease];
  r->_committed = [committed retain];
  r->_requirement = [self requirementForKeys: [committed allKeys]];
  if ([committed count] == 0)
    return r;
  if (![_store commitChanges: committed toDomain: _domain baseline: _baseline
                   conflicts: conflicts error: error])
    return nil;

  [_staged removeAllObjects];
  fresh = [_store snapshotForDomain: _domain error: &refreshErr];
  if (fresh != nil)
    ASSIGN(_baseline, fresh);
  else
    {
      /* Saved, but we could not re-read: remember what we wrote, refuse
         further applies until a successful rebase. */
      ASSIGN(_baseline, [[[GTSDomainSnapshot alloc] initWithDomainName: _domain
        values: applyChanges([_baseline values], committed)] autorelease]);
      _needsRebase = YES;
      r->_refreshFailed = YES;
      r->_refreshError = [refreshErr retain];
    }
  return r;
}
@end
