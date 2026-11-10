/* GTSDefaultsDomainStore.m */
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"

@implementation GTSDomainSnapshot
- (id) initWithDomainName: (NSString*)name values: (NSDictionary*)values
{
  if ((self = [super init]) != nil)
    {
      _domainName = [name copy];
      _values = [(values ? values : [NSDictionary dictionary]) copy];
    }
  return self;
}
- (void) dealloc
{
  [_domainName release];
  [_values release];
  [super dealloc];
}
- (NSString*) domainName { return _domainName; }
- (NSDictionary*) values { return _values; }
- (id) objectForKey: (NSString*)key { return [_values objectForKey: key]; }
- (NSString*) description
{
  return [NSString stringWithFormat: @"<snapshot %@ %@>", _domainName, _values];
}
@end

@implementation GTSConflict
- (id) initWithKey: (NSString*)key baseline: (id)b current: (id)c proposed: (id)p
{
  if ((self = [super init]) != nil)
    {
      _key = [key copy];
      _baselineValue = [b retain];
      _currentValue = [c retain];
      _proposedValue = [p retain];
    }
  return self;
}
- (void) dealloc
{
  [_key release];
  [_baselineValue release];
  [_currentValue release];
  [_proposedValue release];
  [super dealloc];
}
- (NSString*) key { return _key; }
- (id) baselineValue { return _baselineValue; }
- (id) currentValue { return _currentValue; }
- (id) proposedValue { return _proposedValue; }
- (NSString*) description
{
  return [NSString stringWithFormat: @"<conflict %@ baseline=%@ current=%@ proposed=%@>",
    _key, _baselineValue, _currentValue, _proposedValue];
}
@end

static BOOL
sameValue(id a, id b)
{
  if (a == nil || b == nil) return a == b;
  return [a isEqual: b];
}

@implementation GTSDefaultsDomainStore

- (id) initWithHostDefaults: (NSUserDefaults*)hostDefaults
{
  if ((self = [super init]) != nil)
    _hostDefaults = [hostDefaults retain];
  return self;
}

- (id) init
{
  return [self initWithHostDefaults: nil];
}

- (void) dealloc
{
  [_hostDefaults release];
  [super dealloc];
}

- (NSUserDefaults*) hostDefaults { return _hostDefaults; }

/* A new instance has no cached domains, so its first -synchronize loads
   the current on-disk state. Caller releases. */
- (NSUserDefaults*) newDedicatedDefaults
{
  NSUserDefaults *d = [[NSUserDefaults alloc] initWithUser: NSUserName()];
  [d synchronize];
  return d;
}

- (GTSDomainSnapshot*) snapshotUsing: (NSUserDefaults*)d domain: (NSString*)domainName
{
  return [[[GTSDomainSnapshot alloc] initWithDomainName: domainName
    values: [d persistentDomainForName: domainName]] autorelease];
}

+ (NSString*) defaultsRoot
{
  return GSDefaultsRootForUser(NSUserName());
}

- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)domainName
{
  NSUserDefaults *d = [self newDedicatedDefaults];
  GTSDomainSnapshot *s = [self snapshotUsing: d domain: domainName];
  [d release];
  return s;
}

- (NSArray*) conflictsForChanges: (NSDictionary*)changes
                        baseline: (GTSDomainSnapshot*)baseline
                         current: (GTSDomainSnapshot*)current
{
  NSMutableArray *out = [NSMutableArray array];
  NSEnumerator *e = [changes keyEnumerator];
  NSString *k;
  while ((k = [e nextObject]) != nil)
    {
      id b = [baseline objectForKey: k], c = [current objectForKey: k];
      if (!sameValue(b, c))
        {
          id p = [changes objectForKey: k];
          GTSConflict *x = [[GTSConflict alloc] initWithKey: k baseline: b current: c
            proposed: (p == GTSRemoveValue ? nil : p)];
          [out addObject: x];
          [x release];
        }
    }
  return out;
}

- (BOOL) commitChanges: (NSDictionary*)changes
              toDomain: (NSString*)domainName
              baseline: (GTSDomainSnapshot*)baseline
             conflicts: (NSArray**)conflicts
                 error: (NSError**)error
{
  GTSDomainSnapshot *current;
  NSMutableDictionary *merged;
  NSEnumerator *e;
  NSString *k;
  NSUserDefaults *d;
  BOOL ok;

  if (conflicts) *conflicts = nil;
  if ([changes count] == 0) return YES;

  d = [[self newDedicatedDefaults] autorelease];
  current = [self snapshotUsing: d domain: domainName];
  if (baseline != nil)
    {
      NSArray *c = [self conflictsForChanges: changes baseline: baseline current: current];
      if ([c count] > 0)
        {
          if (conflicts) *conflicts = c;
          if (error) *error = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorConflict
            userInfo: [NSDictionary dictionaryWithObject:
              [NSString stringWithFormat: @"%lu setting(s) in %@ were changed elsewhere",
                (unsigned long)[c count], domainName] forKey: NSLocalizedDescriptionKey]];
          return NO;
        }
    }

  merged = [[[current values] mutableCopy] autorelease];
  e = [changes keyEnumerator];
  while ((k = [e nextObject]) != nil)
    {
      id v = [changes objectForKey: k];
      if (v == GTSRemoveValue) [merged removeObjectForKey: k];
      else [merged setObject: v forKey: k];
    }
  if ([merged isEqual: [current values]])
    return YES;

  if (_hookTarget != nil)
    [_hookTarget performSelector: _hookSelector withObject: domainName];

  /* GNUstep's -synchronize takes the defaults lock and merges only the keys
     this instance changed into the on-disk domain. */
  [d setPersistentDomain: merged forName: domainName];
  ok = [d synchronize];
  if (ok && _hostDefaults != nil)
    [_hostDefaults synchronize];
  if (!ok)
    {
      if (error) *error = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorWriteFailed
        userInfo: [NSDictionary dictionaryWithObject:
          [NSString stringWithFormat: @"could not write defaults domain %@", domainName]
          forKey: NSLocalizedDescriptionKey]];
      return NO;
    }
  return YES;
}

- (BOOL) removeKey: (NSString*)key
        fromDomain: (NSString*)domainName
          baseline: (GTSDomainSnapshot*)baseline
         conflicts: (NSArray**)conflicts
             error: (NSError**)error
{
  return [self commitChanges: [NSDictionary dictionaryWithObject: GTSRemoveValue forKey: key]
                    toDomain: domainName baseline: baseline conflicts: conflicts error: error];
}

- (void) setPreWriteHookTarget: (id)target selector: (SEL)selector
{
  _hookTarget = target;
  _hookSelector = selector;
}

+ (NSDictionary*) infoDictionaryForBundleAtPath: (NSString*)appPath
{
  NSArray *cands = [NSArray arrayWithObjects:
    @"Resources/Info-gnustep.plist", @"Contents/Info.plist",
    @"Resources/Info.plist", @"Info-gnustep.plist", @"Info.plist", nil];
  NSEnumerator *e = [cands objectEnumerator];
  NSString *c;
  while ((c = [e nextObject]) != nil)
    {
      NSString *p = [appPath stringByAppendingPathComponent: c];
      NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile: p];
      if (d != nil) return d;
    }
  return nil;
}

+ (NSString*) applicationDomainForBundleAtPath: (NSString*)appPath
{
  NSDictionary *info = [self infoDictionaryForBundleAtPath: appPath];
  NSString *s = [info objectForKey: @"CFBundleIdentifier"];
  if ([s length] > 0) return s;
  s = [info objectForKey: @"NSExecutable"];
  if ([s length] == 0) s = [info objectForKey: @"CFBundleExecutable"];
  if ([s length] > 0) return s;
  return [[appPath lastPathComponent] stringByDeletingPathExtension];
}
@end
