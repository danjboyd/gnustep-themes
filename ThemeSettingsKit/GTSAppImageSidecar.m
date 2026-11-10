/* GTSAppImageSidecar.m */
#import "GTSAppImageSidecar.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSSHA256.h"

/* JSON null and wrong types become nil: the file is untrusted. */
static NSString *
str(id o)
{
  return [o isKindOfClass: [NSString class]] ? o : nil;
}

static NSDictionary *
dict(id o)
{
  return [o isKindOfClass: [NSDictionary class]] ? o : nil;
}

static NSArray *
arr(id o)
{
  return [o isKindOfClass: [NSArray class]] ? o : nil;
}

static NSError *
sidecarError(NSInteger code, NSString *msg)
{
  return [NSError errorWithDomain: GTSErrorDomain code: code
    userInfo: [NSDictionary dictionaryWithObject: msg forKey: NSLocalizedDescriptionKey]];
}

/* An integer number exactly equal to n. JSON true/false arrive as NSNumber
   too (objCType C/c/B on gnustep-base), and 1.5 has intValue 1: reject both. */
static BOOL
isInteger(id o, int n)
{
  const char *t;
  if (![o isKindOfClass: [NSNumber class]]) return NO;
  t = [o objCType];
  if (t && (*t == 'C' || *t == 'c' || *t == 'B')) return NO;
  return [o doubleValue] == (double)n;
}

/* A plain file name: no path separators, not "." or "..", no control chars. */
static BOOL
isPlainFileName(NSString *s)
{
  NSUInteger i;
  if ([s length] == 0 || [s isEqual: @"."] || [s isEqual: @".."]) return NO;
  for (i = 0; i < [s length]; i++)
    {
      unichar c = [s characterAtIndex: i];
      if (c == '/' || c == '\\' || c < 0x20 || c == 0x7f) return NO;
    }
  return YES;
}

static BOOL
isHex64(NSString *s)
{
  NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
    @"0123456789abcdefABCDEF"] invertedSet];
  return [s length] == 64 && [s rangeOfCharacterFromSet: bad].location == NSNotFound;
}

@implementation GTSSidecarTheme
- (void) dealloc
{
  [_name release]; [_themeId release]; [_bundleId release]; [_version release];
  [_shortVersion release]; [_origin release]; [_infoStatus release];
  [_bundledPath release]; [_executableStatus release]; [_settingsNote release];
  [_schema release]; [_schemaProblem release];
  [super dealloc];
}
- (NSString*) name { return _name; }
- (NSString*) themeId { return _themeId; }
- (NSString*) bundleId { return _bundleId; }
- (NSString*) version { return _version; }
- (NSString*) shortVersion { return _shortVersion; }
- (NSString*) origin { return _origin; }
- (NSString*) infoStatus { return _infoStatus; }
- (NSString*) bundledPath { return _bundledPath; }
- (NSString*) executableStatus { return _executableStatus; }
- (GTSSidecarSettingsStatus) settingsStatus { return _settingsStatus; }
- (NSString*) settingsNote { return _settingsNote; }
- (GTSThemeSettingsSchema*) schema { return _schema; }
- (NSString*) schemaProblem { return _schemaProblem; }
- (BOOL) isFullyDescribed { return _settingsStatus == GTSSettingsInline && _schema != nil; }
- (BOOL) isCompatibilityKnown { return NO; }
@end

@interface GTSAppImageSidecar (Private)
- (void) checkProducerMatchFlag: (NSMutableArray*)warnings;
@end

@implementation GTSAppImageSidecar

+ (id) sidecarWithContentsOfFile: (NSString*)path error: (NSError**)error
{
  NSData *data = [NSData dataWithContentsOfFile: path];
  id json = nil;
  GTSAppImageSidecar *s;
  NSMutableArray *themes = [NSMutableArray array], *warnings = [NSMutableArray array];
  NSDictionary *ai;
  NSEnumerator *e;
  id t;

  if (data == nil)
    {
      if (error) *error = sidecarError(GTSErrorUnreadable,
        [NSString stringWithFormat: @"%@ cannot be read", path]);
      return nil;
    }
  NS_DURING
    json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
  NS_HANDLER
    json = nil;
  NS_ENDHANDLER
  if (dict(json) == nil)
    {
      if (error) *error = sidecarError(GTSErrorInvalidSchema,
        [NSString stringWithFormat: @"%@ is not a JSON object", path]);
      return nil;
    }
  if (!isInteger([json objectForKey: @"schema"], 1))
    {
      if (error) *error = sidecarError(GTSErrorUnsupportedVersion,
        [NSString stringWithFormat: @"%@: unsupported sidecar schema %@", path,
          [json objectForKey: @"schema"]]);
      return nil;
    }
  ai = dict([json objectForKey: @"appimage"]);
  if (!isPlainFileName(str([ai objectForKey: @"fileName"])) || !isHex64(str([ai objectForKey: @"sha256"])))
    {
      /* Without a binding the file can't be tied to any AppImage: reject. */
      if (error) *error = sidecarError(GTSErrorInvalidSchema,
        [NSString stringWithFormat: @"%@: missing or invalid appimage.fileName/sha256", path]);
      return nil;
    }

  if ([json objectForKey: @"themes"] != nil && arr([json objectForKey: @"themes"]) == nil)
    [warnings addObject: @"themes is not a list; no themes read"];
  e = [arr([json objectForKey: @"themes"]) objectEnumerator];
  while ((t = [e nextObject]) != nil)
    {
      NSDictionary *td = dict(t), *inst, *set;
      GTSSidecarTheme *x;
      NSString *status;
      if (str([td objectForKey: @"name"]) == nil)
        {
          [warnings addObject: td ? @"a theme entry without a name was skipped"
                                  : @"a theme entry that is not an object was skipped"];
          continue;
        }
      x = [[[GTSSidecarTheme alloc] init] autorelease];
      x->_name = [[td objectForKey: @"name"] copy];
      x->_themeId = [str([td objectForKey: @"themeId"]) copy];
      x->_bundleId = [str([td objectForKey: @"bundleId"]) copy];
      x->_version = [str([td objectForKey: @"version"]) copy];
      x->_shortVersion = [str([td objectForKey: @"shortVersion"]) copy];
      x->_origin = [str([td objectForKey: @"origin"]) copy];
      x->_infoStatus = [str([td objectForKey: @"infoStatus"]) copy];
      inst = dict([td objectForKey: @"installation"]);
      x->_bundledPath = [str([inst objectForKey: @"bundledPath"]) copy];
      x->_executableStatus = [str([inst objectForKey: @"executableStatus"]) copy];

      set = dict([td objectForKey: @"settings"]);
      status = str([set objectForKey: @"status"]);
      x->_settingsNote = [str([set objectForKey: @"note"]) copy];
      if (set == nil && [td objectForKey: @"settings"] != nil
        && [td objectForKey: @"settings"] != [NSNull null])
        {
          /* Present but not an object: damaged, not "no settings file". */
          x->_settingsStatus = GTSSettingsMalformed;
          [warnings addObject: [NSString stringWithFormat: @"theme %@: settings entry is malformed", x->_name]];
        }
      else if (set == nil) x->_settingsStatus = GTSSettingsNone;
      else if ([status isEqual: @"inline"]) x->_settingsStatus = GTSSettingsInline;
      else if ([status isEqual: @"notInlined"]) x->_settingsStatus = GTSSettingsNotInlined;
      else if ([status isEqual: @"malformed"]) x->_settingsStatus = GTSSettingsMalformed;
      else if ([status isEqual: @"unavailable"]) x->_settingsStatus = GTSSettingsUnavailable;
      else x->_settingsStatus = GTSSettingsUnknownStatus;

      if (x->_settingsStatus == GTSSettingsInline)
        {
          NSError *se = nil;
          id inl = dict([set objectForKey: @"inline"]);
          x->_schema = [[GTSThemeSettingsSchema schemaWithPropertyList: inl
            path: [NSString stringWithFormat: @"%@#%@", path, x->_name] error: &se] retain];
          if (x->_schema == nil)
            x->_schemaProblem = [[se localizedDescription] copy];
          else if (![[x->_schema theme] isEqual: x->_name])
            [warnings addObject: [NSString stringWithFormat:
              @"theme %@: settings describe theme %@", x->_name, [x->_schema theme]]];
        }
      [themes addObject: x];
    }

  s = [[[self alloc] init] autorelease];
  s->_path = [path copy];
  s->_json = [json retain];
  s->_themes = [themes copy];
  [s checkProducerMatchFlag: warnings];
  s->_warnings = [warnings copy];
  return s;
}

- (void) dealloc
{
  [_path release]; [_json release]; [_themes release]; [_warnings release];
  [super dealloc];
}

- (NSString*) path { return _path; }
- (NSArray*) warnings { return _warnings; }
- (NSDictionary*) section: (NSString*)k { return dict([_json objectForKey: k]); }

- (NSString*) appImageFileName { return str([[self section: @"appimage"] objectForKey: @"fileName"]); }
- (NSString*) appImageSha256 { return [str([[self section: @"appimage"] objectForKey: @"sha256"]) lowercaseString]; }

- (GTSSidecarBinding) bindingForAppImageAtPath: (NSString*)p
{
  NSString *digest;
  BOOL isDir = NO;
  if (p == nil)
    p = [[_path stringByDeletingLastPathComponent] stringByAppendingPathComponent: [self appImageFileName]];
  if (![[NSFileManager defaultManager] fileExistsAtPath: p isDirectory: &isDir] || isDir)
    return GTSSidecarArtifactMissing;
  if (![[p lastPathComponent] isEqual: [self appImageFileName]])
    return GTSSidecarNameMismatch;
  if (!GTSSHA256IsAvailable()) return GTSSidecarCheckUnavailable;
  digest = GTSSHA256HexOfFile(p);
  if (digest == nil) return GTSSidecarUnreadable;
  return [digest isEqual: [self appImageSha256]] ? GTSSidecarBound : GTSSidecarHashMismatch;
}

+ (NSString*) descriptionOfBinding: (GTSSidecarBinding)b
{
  switch (b)
    {
      case GTSSidecarBound: return @"Theme information matches this AppImage.";
      case GTSSidecarArtifactMissing: return @"The AppImage this theme information describes is not there.";
      case GTSSidecarNameMismatch: return @"This theme information describes a different AppImage file.";
      case GTSSidecarHashMismatch: return @"The AppImage has changed since its theme information was written; it may be out of date.";
      case GTSSidecarUnreadable: return @"The AppImage could not be read to check its theme information.";
      case GTSSidecarCheckUnavailable: return @"This build cannot check that the theme information matches the AppImage, so it is not used for editing.";
    }
  return @"";
}

- (NSString*) packageId { return str([[self section: @"package"] objectForKey: @"id"]); }

- (NSString*) runtimeDomainHintSource
{
  NSString *s = str([[self section: @"app"] objectForKey: @"runtimeDomainHintSource"]);
  /* Only sources the schema defines; anything else is unknown. */
  return ([s isEqual: @"bundleIdentifier"] || [s isEqual: @"processName"]) ? s : @"unknown";
}

- (NSString*) runtimeDomainHint
{
  if ([[self runtimeDomainHintSource] isEqual: @"unknown"]) return nil;
  return str([[self section: @"app"] objectForKey: @"runtimeDomainHint"]);
}

- (NSString*) seedDomain { return str([[self section: @"defaults"] objectForKey: @"seedDomain"]); }

- (NSNumber*) seedDomainMatchesRuntimeHint
{
  NSString *a = [self seedDomain], *b = [self runtimeDomainHint];
  if (a == nil || b == nil) return nil;
  return [NSNumber numberWithBool: [a isEqual: b]];
}

/* Cross-check the producer's flag against our own derivation. */
- (void) checkProducerMatchFlag: (NSMutableArray*)warnings
{
  id m = [[self section: @"defaults"] objectForKey: @"seedDomainMatchesRuntimeHint"];
  NSNumber *ours = [self seedDomainMatchesRuntimeHint];
  const char *t;
  if (m == nil || m == [NSNull null])
    {
      if (ours != nil)
        [warnings addObject: @"seedDomainMatchesRuntimeHint is missing although both domains are known"];
      return;
    }
  t = [m isKindOfClass: [NSNumber class]] ? [m objCType] : NULL;
  if (t == NULL || !(*t == 'C' || *t == 'c' || *t == 'B'))
    {
      [warnings addObject: @"seedDomainMatchesRuntimeHint is not a boolean; ignored"];
      return;
    }
  if (ours == nil)
    [warnings addObject: @"seedDomainMatchesRuntimeHint is set although a domain is unknown; ignored"];
  else if ([m boolValue] != [ours boolValue])
    [warnings addObject: [NSString stringWithFormat:
      @"seedDomainMatchesRuntimeHint says %@ but the domains %@ and %@ %@; using the domains",
      [m boolValue] ? @"true" : @"false", [self seedDomain], [self runtimeDomainHint],
      [ours boolValue] ? @"match" : @"differ"]];
}

- (NSDictionary*) gsThemeSeed
{
  NSEnumerator *e = [arr([[self section: @"defaults"] objectForKey: @"seeds"]) objectEnumerator];
  id d;
  while ((d = [e nextObject]) != nil)
    if ([str([dict(d) objectForKey: @"key"]) isEqual: @"GSTheme"]) return d;
  return nil;
}

- (NSString*) seededTheme { return str([[self gsThemeSeed] objectForKey: @"value"]); }
- (NSString*) seedPolicy { return str([[self gsThemeSeed] objectForKey: @"policy"]); }
- (NSString*) globalDefaultsTheme
{
  return str([dict([[self section: @"defaults"] objectForKey: @"globalDefaultsTheme"]) objectForKey: @"value"]);
}
- (NSArray*) envEntries
{
  NSArray *a = arr([[self section: @"defaults"] objectForKey: @"env"]);
  return a ? a : [NSArray array];
}
- (NSDictionary*) searchPolicy { return [self section: @"search"]; }
- (NSArray*) themes { return _themes; }

- (GTSSidecarTheme*) themeNamed: (NSString*)name
{
  NSEnumerator *e = [_themes objectEnumerator];
  GTSSidecarTheme *t;
  while ((t = [e nextObject]) != nil)
    if ([[t name] isEqual: name]) return t;
  return nil;
}

- (GTSSeededThemeState) seededThemeStateForStoredValue: (id)stored inDomain: (NSString*)domain
{
  NSString *seed = [self seededTheme];
  if (seed == nil || [self seedDomain] == nil) return GTSSeedNone;
  if (![[self seedDomain] isEqual: domain]) return GTSSeedWrongDomain;
  if (![[self seedPolicy] isEqual: @"each-launch-if-absent"]) return GTSSeedPolicyUnknown;
  if (stored == nil) return GTSSeedAbsentWillApply;
  return [stored isEqual: seed] ? GTSSeedInEffect : GTSSeedOverriddenByUser;
}

- (NSString*) descriptionOfSeededThemeState: (GTSSeededThemeState)s
{
  NSString *seed = [self seededTheme];
  switch (s)
    {
      case GTSSeedNone:
        return @"This package does not set a default theme.";
      case GTSSeedAbsentWillApply:
        return [NSString stringWithFormat: @"Packaged default %@ will be set again the next time "
          @"the app starts. To use another theme, choose it.", seed];
      case GTSSeedInEffect:
        return [NSString stringWithFormat: @"Packaged default (%@). Removing it has no lasting effect: "
          @"the app sets it again at each launch. Choose another theme instead.", seed];
      case GTSSeedOverriddenByUser:
        return [NSString stringWithFormat: @"Chosen for this app; it stays. If it is removed, "
          @"the packaged default %@ comes back at the next launch.", seed];
      case GTSSeedPolicyUnknown:
        return [NSString stringWithFormat: @"The package mentions a default theme %@, but not how "
          @"it is applied; its effect is unknown.", seed];
      case GTSSeedWrongDomain:
        return [NSString stringWithFormat: @"The package sets %@ in %@, which is not the settings "
          @"domain shown here; that default may not apply to this app.", seed, [self seedDomain]];
    }
  return @"";
}

- (BOOL) isRemovalMeaningfulForKey: (NSString*)key
{
  NSEnumerator *e = [arr([[self section: @"defaults"] objectForKey: @"seeds"]) objectEnumerator];
  id d;
  while ((d = [e nextObject]) != nil)
    if ([str([dict(d) objectForKey: @"key"]) isEqual: key]
      && [str([dict(d) objectForKey: @"policy"]) isEqual: @"each-launch-if-absent"])
      return NO;
  return YES;
}
@end
