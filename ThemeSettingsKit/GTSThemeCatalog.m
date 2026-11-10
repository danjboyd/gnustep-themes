/* GTSThemeCatalog.m */
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSDefaultsDomainStore.h"

@interface GTSThemeRecord (Private)
+ (GTSThemeRecord*) recordWithName: (NSString*)name path: (NSString*)path origin: (NSString*)origin;
- (void) setShadowed: (NSArray*)a;
- (void) setAvailable: (BOOL)f;
- (NSComparisonResult) compareByName: (GTSThemeRecord*)other;
@end

NSString * const GTSOriginUser = @"user";
NSString * const GTSOriginLocal = @"local";
NSString * const GTSOriginNetwork = @"network";
NSString * const GTSOriginSystem = @"system";
NSString * const GTSOriginApplication = @"application";
NSString * const GTSOriginExplicitPath = @"path";
NSString * const GTSDefaultThemeName = @"GNUstep";

@implementation GTSThemeSearchRoot
+ (id) rootWithPath: (NSString*)path origin: (NSString*)origin
{
  GTSThemeSearchRoot *r = [[[self alloc] init] autorelease];
  r->_path = [path copy];
  r->_origin = [origin copy];
  return r;
}
- (void) dealloc { [_path release]; [_origin release]; [super dealloc]; }
- (NSString*) path { return _path; }
- (NSString*) origin { return _origin; }
- (NSString*) description { return [NSString stringWithFormat: @"%@:%@", _origin, _path]; }
@end

@implementation GTSThemeRecord

+ (GTSThemeRecord*) recordWithName: (NSString*)name path: (NSString*)path origin: (NSString*)origin
{
  GTSThemeRecord *r = [[[self alloc] init] autorelease];
  r->_name = [name copy];
  r->_origin = [origin copy];
  r->_shadowed = [[NSArray alloc] init];
  if (path != nil)
    {
      NSError *err = nil;
      r->_path = [path copy];
      r->_available = YES;
      r->_info = [[GTSDefaultsDomainStore infoDictionaryForBundleAtPath: path] retain];
      if ([GTSThemeSettingsSchema schemaPathForThemeBundleAtPath: path] != nil)
        {
          r->_schema = [[GTSThemeSettingsSchema schemaForThemeBundleAtPath: path error: &err] retain];
          r->_schemaError = [err retain];
        }
    }
  return r;
}

- (void) dealloc
{
  [_name release]; [_path release]; [_origin release]; [_info release];
  [_schema release]; [_schemaError release]; [_shadowed release];
  [super dealloc];
}

- (void) setShadowed: (NSArray*)a { ASSIGN(_shadowed, a); }
- (void) setAvailable: (BOOL)f { _available = f; }

- (NSString*) name { return _name; }
- (NSString*) path { return _path; }
- (NSString*) origin { return _origin; }
- (BOOL) isAvailable { return _available; }
- (BOOL) isBuiltIn { return [_name isEqual: GTSDefaultThemeName] && _path == nil && _available; }
- (NSDictionary*) infoDictionary { return _info; }
- (GTSThemeSettingsSchema*) schema { return _schema; }
- (NSError*) schemaError { return _schemaError; }
- (NSArray*) shadowedRecords { return _shadowed; }

- (NSString*) providerIdentifier
{
  if (_schema != nil) return [_schema providerIdentifier];
  return [_info objectForKey: @"CFBundleIdentifier"];
}

- (NSString*) providerVersion
{
  if ([_schema providerVersion] != nil) return [_schema providerVersion];
  return [_info objectForKey: @"CFBundleVersion"];
}

- (NSString*) description
{
  return [NSString stringWithFormat: @"<theme %@ %@ %@%@>", _name, _origin,
    _available ? (_path ? _path : @"built-in") : @"UNAVAILABLE",
    [_shadowed count] ? [NSString stringWithFormat: @" shadows %lu", (unsigned long)[_shadowed count]] : @""];
}
@end

@implementation GTSThemeRecord (Sorting)
- (NSComparisonResult) compareByName: (GTSThemeRecord*)other
{
  return [[self name] compare: [other name]];
}
@end

@implementation GTSThemeCatalog

+ (NSArray*) defaultSearchRoots
{
  NSMutableArray *roots = [NSMutableArray array];
  NSSearchPathDomainMask masks[] = { NSUserDomainMask, NSLocalDomainMask,
    NSNetworkDomainMask, NSSystemDomainMask };
  NSString *origins[] = { GTSOriginUser, GTSOriginLocal, GTSOriginNetwork, GTSOriginSystem };
  NSMutableSet *seen = [NSMutableSet set];
  int i;
  for (i = 0; i < 4; i++)
    {
      NSEnumerator *e = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
        masks[i], YES) objectEnumerator];
      NSString *lib;
      while ((lib = [e nextObject]) != nil)
        {
          NSString *p = [lib stringByAppendingPathComponent: @"Themes"];
          if ([seen containsObject: p]) continue;   /* layouts may alias domains */
          [seen addObject: p];
          [roots addObject: [GTSThemeSearchRoot rootWithPath: p origin: origins[i]]];
        }
    }
  return roots;
}

- (id) initWithSearchRoots: (NSArray*)roots
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableDictionary *copies = [NSMutableDictionary dictionary];  /* name -> array */
  NSMutableArray *names = [NSMutableArray array];
  NSMutableDictionary *byName = [NSMutableDictionary dictionary];
  NSEnumerator *re, *ne;
  GTSThemeSearchRoot *root;
  NSString *name;

  if ((self = [super init]) == nil) return nil;
  _roots = [roots copy];

  re = [roots objectEnumerator];
  while ((root = [re nextObject]) != nil)
    {
      NSArray *entries = [[fm directoryContentsAtPath: [root path]]
        sortedArrayUsingSelector: @selector(compare:)];
      NSEnumerator *ee = [entries objectEnumerator];
      NSString *entry;
      while ((entry = [ee nextObject]) != nil)
        {
          NSString *full;
          BOOL isDir = NO;
          GTSThemeRecord *r;
          NSMutableArray *list;
          if (![[entry pathExtension] isEqual: @"theme"]) continue;
          full = [[root path] stringByAppendingPathComponent: entry];
          if (![fm fileExistsAtPath: full isDirectory: &isDir] || !isDir) continue;
          name = [entry stringByDeletingPathExtension];
          r = [GTSThemeRecord recordWithName: name path: full origin: [root origin]];
          list = [copies objectForKey: name];
          if (list == nil)
            {
              list = [NSMutableArray array];
              [copies setObject: list forKey: name];
              [names addObject: name];
            }
          [list addObject: r];
        }
    }

  ne = [[names sortedArrayUsingSelector: @selector(compare:)] objectEnumerator];
  while ((name = [ne nextObject]) != nil)
    {
      NSArray *list = [copies objectForKey: name];
      GTSThemeRecord *winner = [list objectAtIndex: 0];
      [winner setShadowed: [list subarrayWithRange: NSMakeRange(1, [list count] - 1)]];
      [byName setObject: winner forKey: name];
    }
  _byName = [byName copy];
  _themes = [[[byName allValues] sortedArrayUsingSelector: @selector(compareByName:)] retain];
  return self;
}

- (id) init
{
  return [self initWithSearchRoots: [[self class] defaultSearchRoots]];
}

- (void) dealloc
{
  [_roots release]; [_themes release]; [_byName release];
  [super dealloc];
}

- (NSArray*) searchRoots { return _roots; }
- (NSArray*) themes { return _themes; }
- (GTSThemeRecord*) themeNamed: (NSString*)name { return [_byName objectForKey: name]; }

- (GTSThemeRecord*) recordForSelection: (NSString*)value
{
  GTSThemeRecord *r;
  if ([value length] == 0 || [value isEqual: GTSDefaultThemeName])
    {
      r = [GTSThemeRecord recordWithName: GTSDefaultThemeName path: nil origin: GTSOriginSystem];
      [r setAvailable: YES];
      return r;
    }
  if ([value isAbsolutePath])
    {
      BOOL isDir = NO;
      NSString *n = [[value lastPathComponent] stringByDeletingPathExtension];
      if ([[NSFileManager defaultManager] fileExistsAtPath: value isDirectory: &isDir] && isDir)
        return [GTSThemeRecord recordWithName: n path: value origin: GTSOriginExplicitPath];
      return [GTSThemeRecord recordWithName: n path: nil origin: GTSOriginExplicitPath];
    }
  /* GSTheme values are usually bare names; tolerate a ".theme" suffix. */
  if ([[value pathExtension] isEqual: @"theme"])
    value = [value stringByDeletingPathExtension];
  r = [self themeNamed: value];
  if (r != nil) return r;
  return [GTSThemeRecord recordWithName: value path: nil origin: nil];
}
@end

