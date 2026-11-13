/* GTSDefaultsDomainStore.m */
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"
#include <errno.h>
#include <string.h>
#if !defined(_WIN32)
#include <unistd.h>
#include <sys/stat.h>
#endif

static NSError *
storeError(NSInteger code, NSString *fmt, ...)
{
  va_list ap;
  NSString *msg;
  va_start(ap, fmt);
  msg = [[[NSString alloc] initWithFormat: fmt arguments: ap] autorelease];
  va_end(ap);
  return [NSError errorWithDomain: GTSErrorDomain code: code
    userInfo: [NSDictionary dictionaryWithObject: msg forKey: NSLocalizedDescriptionKey]];
}

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

@implementation GTSApplicationIdentity
- (void) dealloc
{
  [_domain release]; [_info release]; [_problems release];
  [super dealloc];
}
- (NSString*) domain { return _domain; }
- (GTSIdentitySource) source { return _source; }
- (NSDictionary*) infoDictionary { return _info; }
- (NSArray*) problems { return _problems; }
- (BOOL) isEstablished { return _source != GTSIdentityGuessedFromPath; }
- (NSString*) description
{
  static const char *s[] = { "bundle-id", "executable", "GUESSED" };
  return [NSString stringWithFormat: @"<app %@ (%s)%@>", _domain, s[_source],
    [_problems count] ? [_problems description] : @""];
}
@end

static BOOL
sameValue(id a, id b)
{
  if (a == nil || b == nil) return a == b;
  return [a isEqual: b];
}

static BOOL
isPropertyList(id v, int depth)
{
  NSEnumerator *e;
  id o;
  if (depth > 32) return NO;
  if ([v isKindOfClass: [NSString class]] || [v isKindOfClass: [NSNumber class]]
    || [v isKindOfClass: [NSData class]] || [v isKindOfClass: [NSDate class]])
    return YES;
  if ([v isKindOfClass: [NSArray class]])
    {
      e = [v objectEnumerator];
      while ((o = [e nextObject]) != nil)
        if (!isPropertyList(o, depth + 1)) return NO;
      return YES;
    }
  if ([v isKindOfClass: [NSDictionary class]])
    {
      e = [v keyEnumerator];
      while ((o = [e nextObject]) != nil)
        if (![o isKindOfClass: [NSString class]]
          || !isPropertyList([v objectForKey: o], depth + 1)) return NO;
      return YES;
    }
  return NO;
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

+ (NSString*) defaultsRoot
{
  return GSDefaultsRootForUser(NSUserName());
}

+ (BOOL) isValidDomainName: (id)name
{
  return [name isKindOfClass: [NSString class]] && [name length] > 0
    && [name rangeOfString: @"/"].location == NSNotFound
    && [name rangeOfString: @"\\"].location == NSNotFound   /* a separator on Windows */
#if defined(_WIN32)
    && [name rangeOfString: @":"].location == NSNotFound      /* drive letters, streams */
#endif
    && ![name hasPrefix: @"."];
}

/* Test switch: -1 = real platform answer; 0/1 force writable NO/YES. */
static int gWritableOverride = -1;

+ (void) setBackendWritableOverrideForTesting: (int)value
{
  gWritableOverride = value;
}

+ (BOOL) isBackendReadable
{
#if defined(_WIN32)
  /* GNUstep's file backend keeps one plist per domain, as on POSIX
     (winuitheme, docs/windows.md section 4). A GNUSTEP_USER_DEFAULTS_DIR
     of ":REGISTRY:" selects the registry instead, which this store
     cannot read. PENDING winuitheme rerun. */
  return [[self defaultsRoot] rangeOfString: @":REGISTRY:"].length == 0;
#elif defined(__CYGWIN__)
  return NO;
#else
  return YES;
#endif
}

+ (BOOL) windowsWritesAllowedForRoot: (NSString*)root environment: (NSDictionary*)env
{
  /* Locking and the atomic file replace are gnustep-base's own (the same
     -synchronize as on POSIX); the store adds the read-back check. Opt-in
     until winuitheme's rerun verifies base's behaviour on Windows. */
  return [root isKindOfClass: [NSString class]] && [root isAbsolutePath]
    && [root rangeOfString: @":REGISTRY:"].length == 0
    && [[env objectForKey: @"GTS_ENABLE_WINDOWS_WRITES"] isEqual: @"1"];
}

+ (BOOL) isBackendWritable
{
  if (gWritableOverride >= 0) return gWritableOverride ? YES : NO;
#if defined(__CYGWIN__)
  return NO;
#elif defined(_WIN32)
  return [self isBackendReadable]
    && [self windowsWritesAllowedForRoot: [self defaultsRoot]
                             environment: [[NSProcessInfo processInfo] environment]];
#else
  return YES;
#endif
}

+ (BOOL) isBackendSupported
{
  return [self isBackendWritable];
}

+ (NSString*) defaultsRootDescription
{
  NSString *root = [self defaultsRoot];
  return [NSString stringWithFormat:
    @"Defaults root: %@ (the same lookup as this process's NSUserDefaults: "
    @"GSDefaultsRootForUser(NSUserName()); the current user's home comes from "
#if defined(_WIN32)
    @"GNUSTEP_HOME, HOMEPATH or USERPROFILE"
#else
    @"GNUSTEP_HOME or the password database"
#endif
    @", not a lookup of another user)%@%@.", root ? root : @"(none)",
    [self isBackendReadable] ? @"; readable" : @"; NOT readable",
    [self isBackendWritable] ? @", writable" : @", NOT writable (read-only)"];
}

/* lstat-based classification. Only ENOENT counts as "absent"; any other
   error, a dangling symlink, or an unexpected file type is an error. */
typedef enum { GTSPathAbsent, GTSPathFile, GTSPathDirectory, GTSPathError } GTSPathKind;

#if defined(_WIN32)
/* NSFileManager-based classification (no lstat/S_ISLNK on MinGW, and
   UCRT _access rejects X_OK). Same policy as POSIX: only "does not exist"
   counts as absent; a link whose target is missing, or an unexpected file
   type, is an error. PENDING winuitheme rerun. */
static GTSPathKind
classifyPath(NSString *path, NSString **why)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *own = [fm fileAttributesAtPath: path traverseLink: NO];
  NSDictionary *target;
  NSString *type;
  if (own == nil)
    return GTSPathAbsent;
  target = [fm fileAttributesAtPath: path traverseLink: YES];
  if (target == nil)
    {
      if (why) *why = [NSString stringWithFormat: @"%@: %@", path,
        [[own fileType] isEqual: NSFileTypeSymbolicLink] ? @"dangling link" : @"cannot be examined"];
      return GTSPathError;
    }
  type = [target fileType];
  if ([type isEqual: NSFileTypeDirectory]) return GTSPathDirectory;
  if ([type isEqual: NSFileTypeRegular]) return GTSPathFile;
  if (why) *why = [NSString stringWithFormat: @"%@ is not a regular file or directory", path];
  return GTSPathError;
}
static BOOL
canRead(NSString *path, BOOL isDirectory)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  if (!isDirectory) return [fm isReadableFileAtPath: path];
  return [fm isReadableFileAtPath: path] && [fm isExecutableFileAtPath: path];
}
#else
static BOOL
canRead(NSString *path, BOOL isDirectory)
{
  return access([path fileSystemRepresentation], isDirectory ? (R_OK | X_OK) : R_OK) == 0;
}

static GTSPathKind
classifyPath(NSString *path, NSString **why)
{
  struct stat ls, st;
  const char *p = [path fileSystemRepresentation];
  if (lstat(p, &ls) != 0)
    {
      if (errno == ENOENT) return GTSPathAbsent;
      if (why) *why = [NSString stringWithFormat: @"%@: %s", path, strerror(errno)];
      return GTSPathError;
    }
  if (stat(p, &st) != 0)
    {
      if (why) *why = [NSString stringWithFormat: @"%@: %s (%s)", path, strerror(errno),
        S_ISLNK(ls.st_mode) ? "dangling symlink" : "stat failed"];
      return GTSPathError;
    }
  if (S_ISDIR(st.st_mode)) return GTSPathDirectory;
  if (S_ISREG(st.st_mode)) return GTSPathFile;
  if (why) *why = [NSString stringWithFormat: @"%@ is not a regular file or directory", path];
  return GTSPathError;
}
#endif

- (NSUserDefaults*) newDefaultsInstance
{
  return [[NSUserDefaults alloc] initWithUser: NSUserName()];
}

/* Checks GNUstep's file backend so that "unreadable" or "corrupt" never
   turns into an empty, writable baseline. Returns NO + error if the domain
   cannot be read reliably. *fileValues gets the parsed file (or nil if no
   file exists). */
- (BOOL) checkBackendForDomain: (NSString*)domainName
                    fileValues: (NSDictionary**)fileValues
                         error: (NSError**)error
{
  NSString *root = [[self class] defaultsRoot];
  NSString *file, *why = nil;
  id parsed;

  *fileValues = nil;
  if (![[self class] isBackendReadable])
    {
      if (error) *error = storeError(GTSErrorUnsupportedBackend,
        @"this defaults backend is not supported for editing yet");
      return NO;
    }
  if (![root isKindOfClass: [NSString class]] || ![root isAbsolutePath])
    {
      if (error) *error = storeError(GTSErrorUnsupportedBackend,
        @"defaults root %@ is not an absolute path", root);
      return NO;
    }
  switch (classifyPath(root, &why))
    {
      case GTSPathAbsent:
        return YES;                      /* confirmed: nothing stored yet */
      case GTSPathDirectory:
        if (canRead(root, YES)) break;
        why = [NSString stringWithFormat: @"%@ is not readable", root];
        /* fall through */
      default:
        if (why == nil) why = [NSString stringWithFormat: @"%@ is not a directory", root];
        if (error) *error = storeError(GTSErrorUnreadableDomain,
          @"defaults directory cannot be used: %@", why);
        return NO;
    }
  file = [root stringByAppendingPathComponent:
    [domainName stringByAppendingPathExtension: @"plist"]];
  switch (classifyPath(file, &why))
    {
      case GTSPathAbsent:
        return YES;                      /* confirmed: absent domain */
      case GTSPathFile:
        if (canRead(file, NO)) break;
        why = [NSString stringWithFormat: @"%@ is not readable", file];
        /* fall through */
      default:
        if (why == nil) why = [NSString stringWithFormat: @"%@ is not a regular file", file];
        if (error) *error = storeError(GTSErrorUnreadableDomain,
          @"defaults for %@ exist but cannot be read: %@", domainName, why);
        return NO;
    }
  parsed = nil;
  NS_DURING
    parsed = [[NSString stringWithContentsOfFile: file] propertyList];
  NS_HANDLER
    parsed = nil;
  NS_ENDHANDLER
  if (parsed == nil)
    {
      NSData *raw = [NSData dataWithContentsOfFile: file];
      if (raw != nil)
        parsed = [NSPropertyListSerialization propertyListFromData: raw
          mutabilityOption: NSPropertyListImmutable format: NULL errorDescription: NULL];
    }
  if (![parsed isKindOfClass: [NSDictionary class]])
    {
      if (error) *error = storeError(GTSErrorUnreadableDomain,
        @"defaults for %@ are damaged and were left untouched (%@)", domainName, file);
      return NO;
    }
  *fileValues = parsed;
  return YES;
}

/* Fresh instance + backend check. Returns retained defaults via *out. */
- (GTSDomainSnapshot*) loadDomain: (NSString*)domainName
                         defaults: (NSUserDefaults**)outDefaults
                            error: (NSError**)error
{
  NSUserDefaults *d;
  NSDictionary *apiValues, *fileValues = nil;
  GTSDomainSnapshot *snap;
  BOOL rootWasAbsent;

  if (outDefaults) *outDefaults = nil;
  if (![[self class] isValidDomainName: domainName])
    {
      if (error) *error = storeError(GTSErrorInvalidArgument, @"invalid domain name %@", domainName);
      return nil;
    }
  if (![self checkBackendForDomain: domainName fileValues: &fileValues error: error])
    return nil;
  /* gnustep-base's first -synchronize when the defaults directory does not
     exist yet (a new user, no ~/GNUstep/Defaults) reports NO; the next one
     succeeds (seen with Debian's 1.31.1 and the clang toolchain's base).
     Retry once, and only in that case; any other failure still refuses. */
  rootWasAbsent = (classifyPath([[self class] defaultsRoot], NULL) == GTSPathAbsent);
  d = [self newDefaultsInstance];
  if (d != nil && ![d synchronize] && !(rootWasAbsent && [d synchronize]))
    {
      [d release];
      d = nil;
    }
  if (d == nil)
    {
      [d release];
      if (error) *error = storeError(GTSErrorUnreadableDomain,
        @"could not load defaults to read %@", domainName);
      return nil;
    }
  apiValues = [d persistentDomainForName: domainName];
  if (apiValues != nil && ![apiValues isKindOfClass: [NSDictionary class]])
    {
      [d release];
      if (error) *error = storeError(GTSErrorUnreadableDomain, @"%@ is not a dictionary", domainName);
      return nil;
    }
  /* The API saying "empty" while the file holds values means the API view
     is not trustworthy for this domain: refuse. */
  if ([apiValues count] == 0 && [fileValues count] > 0)
    {
      [d release];
      if (error) *error = storeError(GTSErrorUnreadableDomain,
        @"defaults for %@ could not be loaded consistently", domainName);
      return nil;
    }
  /* Build (copy) the snapshot while d is alive. gnustep-base returns a copy
     here (gnustep owner, msg 20394), but this does not depend on it. */
  snap = [[[GTSDomainSnapshot alloc] initWithDomainName: domainName values: apiValues] autorelease];
  if (outDefaults) *outDefaults = d; else [d release];
  return snap;
}

- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)domainName error: (NSError**)error
{
  return [self loadDomain: domainName defaults: NULL error: error];
}

- (NSArray*) conflictsForChanges: (NSDictionary*)changes
                        baseline: (GTSDomainSnapshot*)baseline
                         current: (GTSDomainSnapshot*)current
{
  NSMutableArray *out = [NSMutableArray array];
  NSEnumerator *e = [changes keyEnumerator];
  NSString *k;
  if (![[baseline domainName] isEqual: [current domainName]])
    return nil;
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

- (BOOL) validateChanges: (NSDictionary*)changes error: (NSError**)error
{
  NSEnumerator *e;
  id k;
  if (![changes isKindOfClass: [NSDictionary class]])
    {
      if (error) *error = storeError(GTSErrorInvalidArgument, @"changes must be a dictionary");
      return NO;
    }
  e = [changes keyEnumerator];
  while ((k = [e nextObject]) != nil)
    {
      id v = [changes objectForKey: k];
      if (![k isKindOfClass: [NSString class]] || [k length] == 0)
        {
          if (error) *error = storeError(GTSErrorInvalidArgument, @"invalid defaults key %@", k);
          return NO;
        }
      if (v != GTSRemoveValue && !isPropertyList(v, 0))
        {
          if (error) *error = storeError(GTSErrorInvalidArgument,
            @"value for %@ is not a property list (%@)", k, [v class]);
          return NO;
        }
    }
  return YES;
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
  NSUserDefaults *d = nil;
  BOOL ok;

  if (conflicts) *conflicts = nil;
  if (![[self class] isValidDomainName: domainName])
    {
      if (error) *error = storeError(GTSErrorInvalidArgument, @"invalid domain name %@", domainName);
      return NO;
    }
  if (![self validateChanges: changes error: error])
    return NO;
  if (baseline != nil && ![[baseline domainName] isEqual: domainName])
    {
      if (error) *error = storeError(GTSErrorInvalidArgument,
        @"baseline is for %@, not %@", [baseline domainName], domainName);
      return NO;
    }
  if ([changes count] == 0) return YES;
  if (![[self class] isBackendWritable])
    {
      if (error) *error = storeError(GTSErrorUnsupportedBackend,
        @"this defaults backend is not supported for editing yet");
      return NO;
    }

  current = [self loadDomain: domainName defaults: &d error: error];
  if (current == nil)
    return NO;
  [d autorelease];
  if (baseline != nil)
    {
      NSArray *c = [self conflictsForChanges: changes baseline: baseline current: current];
      if (c == nil || [c count] > 0)
        {
          if (conflicts) *conflicts = c;
          if (error) *error = storeError(GTSErrorConflict,
            @"%lu setting(s) in %@ were changed elsewhere", (unsigned long)[c count], domainName);
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
      if (error) *error = storeError(GTSErrorWriteFailed,
        @"could not write defaults domain %@; its state is unknown, reload before retrying",
        domainName);
      return NO;
    }
  /* Read the file back with the same strict checks as a load: every changed
     key must hold its new value and every removed key must be gone. A
     backend that reports success without writing (or writes elsewhere) is
     caught here on any platform. */
  {
    NSDictionary *onDisk = nil;
    NSError *why = nil;
    NSString *bad = nil;
    if (![self checkBackendForDomain: domainName fileValues: &onDisk error: &why])
      bad = [why localizedDescription];
    else
      {
        e = [changes keyEnumerator];
        while (bad == nil && (k = [e nextObject]) != nil)
          {
            id v = [changes objectForKey: k];
            id got = [onDisk objectForKey: k];
            if (v == GTSRemoveValue ? (got != nil) : !sameValue(v, got))
              bad = [NSString stringWithFormat: @"%@ reads back as %@", k, got ? got : @"(unset)"];
          }
      }
    if (bad != nil)
      {
        if (error) *error = storeError(GTSErrorWriteFailed,
          @"defaults domain %@ did not read back as written (%@); its state is unknown, reload before retrying",
          domainName, bad);
        return NO;
      }
  }
  return YES;
}

- (BOOL) removeKey: (NSString*)key
        fromDomain: (NSString*)domainName
          baseline: (GTSDomainSnapshot*)baseline
         conflicts: (NSArray**)conflicts
             error: (NSError**)error
{
  if (![key isKindOfClass: [NSString class]] || [key length] == 0)
    {
      if (error) *error = storeError(GTSErrorInvalidArgument, @"invalid defaults key %@", key);
      return NO;
    }
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
      NSDictionary *d = nil;
      NS_DURING
        d = [NSDictionary dictionaryWithContentsOfFile: p];
      NS_HANDLER
        d = nil;
      NS_ENDHANDLER
      if ([d isKindOfClass: [NSDictionary class]]) return d;
    }
  return nil;
}

+ (GTSApplicationIdentity*) applicationIdentityForBundleAtPath: (NSString*)appPath
{
  GTSApplicationIdentity *ident = [[[GTSApplicationIdentity alloc] init] autorelease];
  NSMutableArray *problems = [NSMutableArray array];
  NSDictionary *info = [self infoDictionaryForBundleAtPath: appPath];
  NSArray *keys = [NSArray arrayWithObjects: @"CFBundleIdentifier", @"NSExecutable",
    @"CFBundleExecutable", nil];
  NSEnumerator *e = [keys objectEnumerator];
  NSString *k;

  ident->_info = [info retain];
  if (info == nil)
    [problems addObject: @"no readable Info plist"];
  while (info != nil && (k = [e nextObject]) != nil)
    {
      id v = [info objectForKey: k];
      if (v == nil) continue;
      if (![v isKindOfClass: [NSString class]] || [v length] == 0)
        {
          [problems addObject: [NSString stringWithFormat: @"%@ is not a non-empty string", k]];
          continue;
        }
      if (![self isValidDomainName: v])
        {
          [problems addObject: [NSString stringWithFormat: @"%@ \"%@\" is not usable as a domain", k, v]];
          continue;
        }
      ident->_domain = [v copy];
      ident->_source = [k isEqual: @"CFBundleIdentifier"]
        ? GTSIdentityFromBundleIdentifier : GTSIdentityFromExecutable;
      break;
    }
  if (ident->_domain == nil)
    {
      ident->_domain = [[[appPath lastPathComponent] stringByDeletingPathExtension] copy];
      ident->_source = GTSIdentityGuessedFromPath;
      [problems addObject: @"domain guessed from the bundle name; confirm before editing"];
    }
  ident->_problems = [problems copy];
  return ident;
}
@end
