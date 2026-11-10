/* GTSThemeSettingsSchema.m */
#import "GTSThemeSettingsSchema.h"

NSString * const GTSErrorDomain = @"GTSErrorDomain";
NSString * const GTSScopeGlobal = @"global";
NSString * const GTSScopeApplication = @"application";
NSString * const GTSSourceArgument = @"argument";
NSString * const GTSSourceApplication = @"application";
NSString * const GTSSourceApplicationInfo = @"applicationInfo";
NSString * const GTSSourceGlobal = @"global";
NSString * const GTSSourceOtherInfo = @"otherInfo";

static NSError *
GTSMakeError(NSInteger code, NSString *message)
{
  return [NSError errorWithDomain: GTSErrorDomain
                             code: code
                         userInfo: [NSDictionary dictionaryWithObject: message
                                                    forKey: NSLocalizedDescriptionKey]];
}

static BOOL
isString(id o)
{
  return [o isKindOfClass: [NSString class]] && [(NSString*)o length] > 0;
}

/* A real number: an NSNumber that is not a bool/char, or a string that
   scans entirely as a double. */
static BOOL
GTSIsNumber(id v)
{
  if ([v isKindOfClass: [NSNumber class]])
    {
      const char *t = [v objCType];   /* bools are char-typed here, as for SchemaVersion */
      return !(t && (*t == 'C' || *t == 'c' || *t == 'B'));
    }
  if ([v isKindOfClass: [NSString class]])
    {
      double dv;
      NSScanner *sc = [NSScanner scannerWithString: v];
      return [sc scanDouble: &dv] && [sc isAtEnd];
    }
  return NO;
}

/* Parses YES/NO/true/false/1/0. Returns -1 if not a bool spelling. */
static int
GTSBoolValue(id v)
{
  if ([v isKindOfClass: [NSNumber class]])
    return [v boolValue] ? 1 : 0;
  if ([v isKindOfClass: [NSString class]])
    {
      NSString *s = [v lowercaseString];
      if ([s isEqual: @"yes"] || [s isEqual: @"true"] || [s isEqual: @"1"])
        return 1;
      if ([s isEqual: @"no"] || [s isEqual: @"false"] || [s isEqual: @"0"])
        return 0;
    }
  return -1;
}

@implementation GTSPrecedenceSource
- (id) initWithSource: (NSString*)source values: (NSArray*)values
{
  if ((self = [super init]) != nil)
    {
      _source = [source copy];
      _values = [values copy];
    }
  return self;
}
- (void) dealloc
{
  [_source release];
  [_values release];
  [super dealloc];
}
- (NSString*) source { return _source; }
- (NSArray*) values { return _values; }
- (NSString*) description
{
  return _values ? [NSString stringWithFormat: @"%@%@", _source, _values] : _source;
}
@end

@implementation GTSSettingDescriptor

static NSArray *knownSources = nil;

+ (void) initialize
{
  if (knownSources == nil)
    knownSources = [[NSArray alloc] initWithObjects: GTSSourceArgument,
      GTSSourceApplication, GTSSourceApplicationInfo, GTSSourceGlobal,
      GTSSourceOtherInfo, nil];
}

+ (id) descriptorWithPropertyList: (NSDictionary*)p problems: (NSMutableArray*)problems
{
  GTSSettingDescriptor *d;
  NSString *ident, *type, *where;
  id o;

  if (![p isKindOfClass: [NSDictionary class]])
    {
      [problems addObject: @"setting entry is not a dictionary"];
      return nil;
    }
  ident = [p objectForKey: @"Identifier"];
  where = isString(ident) ? ident : @"<no Identifier>";
  if (!isString(ident))
    {
      [problems addObject: @"setting without Identifier skipped"];
      return nil;
    }
  if (!isString([p objectForKey: @"Key"]))
    {
      [problems addObject: [NSString stringWithFormat: @"%@: missing Key", where]];
      return nil;
    }

  d = [[[self alloc] init] autorelease];
  d->_identifier = [ident copy];
  d->_key = [[p objectForKey: @"Key"] copy];

  type = [p objectForKey: @"Type"];
  if ([type isEqual: @"bool"]) d->_type = GTSSettingTypeBool;
  else if ([type isEqual: @"enum"]) d->_type = GTSSettingTypeEnum;
  else if ([type isEqual: @"string"]) d->_type = GTSSettingTypeString;
  else if ([type isEqual: @"number"]) d->_type = GTSSettingTypeNumber;
  else
    {
      [problems addObject: [NSString stringWithFormat: @"%@: unknown Type %@", where, type]];
      return nil;
    }

  o = [p objectForKey: @"Values"];
  if (d->_type == GTSSettingTypeEnum)
    {
      NSEnumerator *e;
      id v;
      NSMutableArray *vals = [NSMutableArray array];

      if (![o isKindOfClass: [NSArray class]] || [o count] == 0)
        {
          [problems addObject: [NSString stringWithFormat: @"%@: enum without Values", where]];
          return nil;
        }
      e = [o objectEnumerator];
      while ((v = [e nextObject]) != nil)
        {
          if ([v isKindOfClass: [NSString class]])
            v = [NSDictionary dictionaryWithObject: v forKey: @"Value"];
          if (![v isKindOfClass: [NSDictionary class]] || !isString([v objectForKey: @"Value"]))
            {
              [problems addObject: [NSString stringWithFormat: @"%@: bad enum value entry", where]];
              return nil;
            }
          [vals addObject: v];
        }
      d->_values = [vals copy];
    }

  d->_caseInsensitive = GTSBoolValue([p objectForKey: @"CaseInsensitive"]) == 1;

  o = [p objectForKey: @"Scopes"];
  if (![o isKindOfClass: [NSArray class]] || [o count] == 0)
    {
      [problems addObject: [NSString stringWithFormat: @"%@: missing Scopes", where]];
      return nil;
    }
  else
    {
      NSEnumerator *e = [o objectEnumerator];
      id s;
      while ((s = [e nextObject]) != nil)
        if (![s isEqual: GTSScopeGlobal] && ![s isEqual: GTSScopeApplication])
          {
            [problems addObject: [NSString stringWithFormat: @"%@: unknown scope %@", where, s]];
            return nil;
          }
      d->_scopes = [o copy];
    }

  d->_group = [[p objectForKey: @"Group"] copy];
  d->_title = [([p objectForKey: @"Title"] ? [p objectForKey: @"Title"] : ident) copy];
  d->_help = [[p objectForKey: @"Help"] copy];

  o = [p objectForKey: @"Unset"];
  if (![o isKindOfClass: [NSDictionary class]])
    {
      [problems addObject: [NSString stringWithFormat: @"%@: missing Unset", where]];
      return nil;
    }
  if ([[o objectForKey: @"Behavior"] isEqual: @"static"])
    {
      d->_unsetBehavior = GTSUnsetStatic;
      d->_unsetValue = [[o objectForKey: @"Value"] retain];
      if (d->_unsetValue == nil)
        {
          [problems addObject: [NSString stringWithFormat: @"%@: static Unset without Value", where]];
          return nil;
        }
    }
  else if ([[o objectForKey: @"Behavior"] isEqual: @"dynamic"])
    {
      d->_unsetBehavior = GTSUnsetDynamic;
      if ([o objectForKey: @"Value"] != nil)
        {
          /* A dynamic default must not be described by a stored token. */
          [problems addObject: [NSString stringWithFormat: @"%@: dynamic Unset must not carry a Value", where]];
          return nil;
        }
    }
  else
    {
      [problems addObject: [NSString stringWithFormat: @"%@: Unset.Behavior must be static or dynamic", where]];
      return nil;
    }
  d->_unsetHelp = [[o objectForKey: @"Help"] copy];

  o = [p objectForKey: @"Precedence"];
  if (o == nil)
    o = [NSArray arrayWithObjects: GTSSourceArgument, GTSSourceApplication, GTSSourceGlobal, nil];
  if (![o isKindOfClass: [NSArray class]])
    {
      [problems addObject: [NSString stringWithFormat: @"%@: Precedence is not an array", where]];
      return nil;
    }
  else
    {
      NSMutableArray *prec = [NSMutableArray array];
      NSEnumerator *e = [o objectEnumerator];
      id s;
      while ((s = [e nextObject]) != nil)
        {
          NSString *name = s;
          NSArray *vals = nil;
          GTSPrecedenceSource *ps;
          if ([s isKindOfClass: [NSDictionary class]])
            {
              name = [s objectForKey: @"Source"];
              vals = [s objectForKey: @"Values"];
            }
          if (![knownSources containsObject: name])
            {
              [problems addObject: [NSString stringWithFormat: @"%@: unknown precedence source %@", where, s]];
              return nil;
            }
          ps = [[GTSPrecedenceSource alloc] initWithSource: name values: vals];
          [prec addObject: ps];
          [ps release];
        }
      d->_precedence = [prec copy];
    }
  d->_infoKey = [([p objectForKey: @"InfoKey"] ? [p objectForKey: @"InfoKey"] : d->_key) copy];

  o = [p objectForKey: @"Apply"];
  if ([o isEqual: @"live"]) d->_apply = GTSApplyLive;
  else if ([o isEqual: @"newWindows"]) d->_apply = GTSApplyNewWindows;
  else if ([o isEqual: @"restart"]) d->_apply = GTSApplyRestart;
  else
    {
      [problems addObject: [NSString stringWithFormat: @"%@: Apply must be live, newWindows or restart", where]];
      return nil;
    }

  if (d->_type == GTSSettingTypeNumber)
    {
      id mn = [p objectForKey: @"Minimum"], mx = [p objectForKey: @"Maximum"];
      /* Strict: a non-numeric string must not silently become 0 (lead
         decision Q2, #22591). */
      if ((mn && !GTSIsNumber(mn)) || (mx && !GTSIsNumber(mx)))
        {
          [problems addObject: [NSString stringWithFormat: @"%@: Minimum/Maximum must be numbers", where]];
          return nil;
        }
      if (mn && mx && [mn doubleValue] > [mx doubleValue])
        {
          [problems addObject: [NSString stringWithFormat: @"%@: Minimum %@ is greater than Maximum %@", where, mn, mx]];
          return nil;
        }
      if (mn) d->_minimum = [[NSNumber alloc] initWithDouble: [mn doubleValue]];
      if (mx) d->_maximum = [[NSNumber alloc] initWithDouble: [mx doubleValue]];
    }
  o = [p objectForKey: @"RequiredFeatures"];
  if (o != nil && ![o isKindOfClass: [NSArray class]])
    {
      [problems addObject: [NSString stringWithFormat: @"%@: RequiredFeatures must be an array", where]];
      return nil;
    }
  else
    {
      NSMutableArray *missing = [NSMutableArray array];
      NSEnumerator *fe = [o objectEnumerator];
      id f;
      while ((f = [fe nextObject]) != nil)
        if (![[GTSThemeSettingsSchema supportedFeatures] containsObject: f])
          [missing addObject: [f description]];
      d->_unsupportedFeatures = [missing copy];
    }

  d->_dependsOn = [[p objectForKey: @"DependsOn"] copy];
  d->_overlaps = [([p objectForKey: @"Overlaps"] ? [p objectForKey: @"Overlaps"] : [NSArray array]) copy];
  o = [p objectForKey: @"Status"];
  if (o != nil && ![o isEqual: @"public"] && ![o isEqual: @"unstable"])
    {
      /* A typo must not make an unstable entry public (lead decision Q2). */
      [problems addObject: [NSString stringWithFormat: @"%@: Status %@ is not public or unstable", where, o]];
      return nil;
    }
  d->_unstable = [o isEqual: @"unstable"];

  if (d->_unsetBehavior == GTSUnsetStatic && [d problemWithValue: d->_unsetValue] != nil)
    {
      [problems addObject: [NSString stringWithFormat: @"%@: Unset.Value %@ is not a valid value", where, d->_unsetValue]];
      return nil;
    }
  return d;
}

- (void) dealloc
{
  [_identifier release]; [_key release]; [_values release]; [_scopes release];
  [_group release]; [_title release]; [_help release]; [_unsetValue release];
  [_unsetHelp release]; [_precedence release]; [_infoKey release];
  [_dependsOn release]; [_overlaps release];
  [_minimum release]; [_maximum release]; [_unsupportedFeatures release];
  [super dealloc];
}

- (NSString*) identifier { return _identifier; }
- (NSString*) key { return _key; }
- (GTSSettingType) type { return _type; }
- (NSArray*) values { return _values; }
- (NSArray*) allowedValues { return [_values valueForKey: @"Value"]; }
- (BOOL) isCaseInsensitive { return _caseInsensitive; }
- (NSArray*) scopes { return _scopes; }
- (BOOL) supportsScope: (NSString*)scope { return [_scopes containsObject: scope]; }
- (NSString*) group { return _group; }
- (NSString*) title { return _title; }
- (NSString*) help { return _help; }
- (GTSUnsetBehavior) unsetBehavior { return _unsetBehavior; }
- (id) unsetValue { return _unsetValue; }
- (NSString*) unsetHelp { return _unsetHelp; }
- (NSArray*) precedence { return _precedence; }
- (NSString*) infoKey { return _infoKey; }
- (GTSApplyPolicy) applyPolicy { return _apply; }
- (NSDictionary*) dependsOn { return _dependsOn; }
- (NSArray*) overlaps { return _overlaps; }
- (BOOL) isUnstable { return _unstable; }
- (NSNumber*) minimum { return _minimum; }
- (NSNumber*) maximum { return _maximum; }
- (NSArray*) unsupportedFeatures { return _unsupportedFeatures; }
- (BOOL) isReadOnly { return [_unsupportedFeatures count] > 0; }

- (NSString*) problemWithValue: (id)value
{
  if (value == nil)
    return @"no value";
  switch (_type)
    {
      case GTSSettingTypeBool:
        return GTSBoolValue(value) < 0 ? @"not a boolean" : nil;
      case GTSSettingTypeNumber:
        {
          double dv = 0;
          BOOL ok = NO;
          if ([value isKindOfClass: [NSNumber class]])
            {
              dv = [value doubleValue];
              ok = YES;
            }
          else if ([value isKindOfClass: [NSString class]])
            {
              NSScanner *sc = [NSScanner scannerWithString: value];
              ok = [sc scanDouble: &dv] && [sc isAtEnd];
            }
          if (!ok) return @"not a number";
          if ((_minimum && dv < [_minimum doubleValue]) || (_maximum && dv > [_maximum doubleValue]))
            return [NSString stringWithFormat: @"%g is outside %@-%@", dv,
              _minimum ? [_minimum description] : @"", _maximum ? [_maximum description] : @""];
          return nil;
        }
      case GTSSettingTypeString:
        return [value isKindOfClass: [NSString class]] ? nil : @"not a string";
      case GTSSettingTypeEnum:
        {
          NSEnumerator *e = [[self allowedValues] objectEnumerator];
          NSString *v;
          if (![value isKindOfClass: [NSString class]]) return @"not a string";
          while ((v = [e nextObject]) != nil)
            if ([self value: v isEqualToValue: value]) return nil;
          return [NSString stringWithFormat: @"%@ is not one of %@", value,
            [[self allowedValues] componentsJoinedByString: @", "]];
        }
    }
  return @"unknown type";
}

- (BOOL) value: (id)a isEqualToValue: (id)b
{
  if (a == nil || b == nil)
    return a == b;
  if (_type == GTSSettingTypeBool)
    {
      int x = GTSBoolValue(a), y = GTSBoolValue(b);
      if (x >= 0 && y >= 0) return x == y;
    }
  if (_type == GTSSettingTypeNumber)
    return [a doubleValue] == [b doubleValue];
  if (_caseInsensitive && [a isKindOfClass: [NSString class]]
    && [b isKindOfClass: [NSString class]])
    return [a caseInsensitiveCompare: b] == NSOrderedSame;
  return [a isEqual: b];
}

- (id) storedFormOfValue: (id)value
{
  if (_type == GTSSettingTypeBool)
    return GTSBoolValue(value) == 1 ? @"YES" : @"NO";
  if (_type == GTSSettingTypeEnum)
    {
      /* Store the canonical spelling from the schema. */
      NSEnumerator *e = [[self allowedValues] objectEnumerator];
      NSString *v;
      while ((v = [e nextObject]) != nil)
        if ([self value: v isEqualToValue: value]) return v;
    }
  return value;
}

- (NSString*) description
{
  return [NSString stringWithFormat: @"<%@ %@ key=%@>", [self class], _identifier, _key];
}
@end

@implementation GTSThemeSettingsSchema

+ (NSString*) schemaPathForThemeBundleAtPath: (NSString*)bundlePath
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *cands = [NSArray arrayWithObjects:
    @"Resources/ThemeSettings.plist",
    @"Contents/Resources/ThemeSettings.plist",
    @"ThemeSettings.plist", nil];
  NSEnumerator *e = [cands objectEnumerator];
  NSString *c;
  while ((c = [e nextObject]) != nil)
    {
      NSString *p = [bundlePath stringByAppendingPathComponent: c];
      if ([fm fileExistsAtPath: p]) return p;
    }
  return nil;
}

+ (id) schemaForThemeBundleAtPath: (NSString*)bundlePath error: (NSError**)error
{
  NSString *p = [self schemaPathForThemeBundleAtPath: bundlePath];
  GTSThemeSettingsSchema *s;
  if (p == nil)
    {
      if (error) *error = GTSMakeError(GTSErrorUnreadable,
        [NSString stringWithFormat: @"%@ has no ThemeSettings.plist", bundlePath]);
      return nil;
    }
  s = [self schemaWithContentsOfFile: p error: error];
  if (s != nil)
    ASSIGN(s->_bundlePath, bundlePath);
  return s;
}

+ (id) schemaWithContentsOfFile: (NSString*)path error: (NSError**)error
{
  NSString *text = [NSString stringWithContentsOfFile: path];
  id plist = nil;
  if (text != nil)
    {
      NS_DURING
        plist = [text propertyList];
      NS_HANDLER
        plist = nil;
      NS_ENDHANDLER
    }
  if (plist == nil)
    {
      if (error) *error = GTSMakeError(GTSErrorUnreadable,
        [NSString stringWithFormat: @"%@ is not a readable property list", path]);
      return nil;
    }
  return [self schemaWithPropertyList: plist path: path error: error];
}

+ (id) schemaWithPropertyList: (id)plist path: (NSString*)path error: (NSError**)error
{
  GTSThemeSettingsSchema *s;
  NSMutableArray *problems = [NSMutableArray array];
  NSMutableArray *settings = [NSMutableArray array];
  NSMutableSet *ids = [NSMutableSet set];
  NSMutableDictionary *keyOwners = [NSMutableDictionary dictionary];
  NSEnumerator *e;
  id o, prov;
  NSInteger version;

#define FAIL(c, msg) do { if (error) *error = GTSMakeError((c), [NSString stringWithFormat: @"%@: %@", path, (msg)]); return nil; } while (0)
  if (![plist isKindOfClass: [NSDictionary class]])
    FAIL(GTSErrorInvalidSchema, @"top level is not a dictionary");
  o = [plist objectForKey: @"SchemaVersion"];
  if ([o isKindOfClass: [NSNumber class]])
    {
      /* JSON true/false and fractions are not versions. */
      const char *ty = [o objCType];
      if ((ty && (*ty == 'C' || *ty == 'c' || *ty == 'B')) || [o doubleValue] != (double)[o intValue])
        FAIL(GTSErrorInvalidSchema, @"SchemaVersion is not an integer");
      version = [o intValue];
    }
  else if ([o isKindOfClass: [NSString class]])
    {
      /* Old-style plists store numbers as strings: digits only. */
      NSCharacterSet *nd = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
      if ([o length] == 0 || [o rangeOfCharacterFromSet: nd].location != NSNotFound)
        FAIL(GTSErrorInvalidSchema, @"SchemaVersion is not an integer");
      version = [o intValue];
    }
  else
    FAIL(GTSErrorInvalidSchema, @"missing SchemaVersion");
  if (version != 1)
    FAIL(GTSErrorUnsupportedVersion,
      ([NSString stringWithFormat: @"unsupported SchemaVersion %ld", (long)version]));
  if (!isString([plist objectForKey: @"Theme"]))
    FAIL(GTSErrorInvalidSchema, @"missing Theme");
  prov = [plist objectForKey: @"ThemeIdentifier"];
  if (!isString(prov))
    FAIL(GTSErrorInvalidSchema, @"missing ThemeIdentifier");
  o = [plist objectForKey: @"RequiredFeatures"];
  if (o != nil && ![o isKindOfClass: [NSArray class]])
    FAIL(GTSErrorInvalidSchema, @"RequiredFeatures must be an array");
  o = [plist objectForKey: @"Settings"];
  if (![o isKindOfClass: [NSArray class]])
    FAIL(GTSErrorInvalidSchema, @"missing Settings array");
#undef FAIL

  e = [o objectEnumerator];
  while ((o = [e nextObject]) != nil)
    {
      GTSSettingDescriptor *d = [GTSSettingDescriptor descriptorWithPropertyList: o problems: problems];
      if (d == nil) continue;
      if ([ids containsObject: [d identifier]])
        {
          [problems addObject: [NSString stringWithFormat: @"%@: duplicate Identifier skipped", [d identifier]]];
          continue;
        }
      if ([keyOwners objectForKey: [d key]] != nil)
        {
          /* One descriptor per key; the first wins, later ones are skipped
             (lead decision Q4, #22591). */
          [problems addObject: [NSString stringWithFormat: @"%@: Key %@ is already described by %@; skipped",
            [d identifier], [d key], [keyOwners objectForKey: [d key]]]];
          continue;
        }
      [ids addObject: [d identifier]];
      [keyOwners setObject: [d identifier] forKey: [d key]];
      [settings addObject: d];
    }

  s = [[[self alloc] init] autorelease];
  s->_path = [path copy];
  s->_version = version;
  s->_theme = [[plist objectForKey: @"Theme"] copy];
  s->_themeIdentifier = [prov copy];
  {
    NSMutableArray *missing = [NSMutableArray array];
    NSEnumerator *fe = [[plist objectForKey: @"RequiredFeatures"] objectEnumerator];
    id f;
    while ((f = [fe nextObject]) != nil)
      if (![[self supportedFeatures] containsObject: f])
        [missing addObject: [f description]];
    s->_unsupportedFeatures = [missing copy];
  }
  s->_groups = [([plist objectForKey: @"Groups"] ? [plist objectForKey: @"Groups"] : [NSArray array]) copy];
  s->_settings = [settings copy];
  s->_warnings = [problems copy];
  return s;
}

- (void) dealloc
{
  [_path release]; [_bundlePath release]; [_theme release];
  [_themeIdentifier release]; [_unsupportedFeatures release];
  [_groups release]; [_settings release]; [_warnings release];
  [super dealloc];
}

- (NSString*) path { return _path; }
- (NSString*) bundlePath { return _bundlePath; }
- (NSInteger) version { return _version; }
- (NSString*) theme { return _theme; }
- (NSString*) themeIdentifier { return _themeIdentifier; }
- (NSArray*) unsupportedFeatures { return _unsupportedFeatures; }
- (BOOL) isReadOnly { return [_unsupportedFeatures count] > 0; }

+ (NSArray*) supportedFeatures
{
  /* v1 readers implement everything described in docs/schema-v1.md and
     nothing else. Themes list a feature here only when ignoring it would
     make an editor write something wrong. */
  return [NSArray array];
}
- (NSArray*) groups { return _groups; }
- (NSArray*) settings { return _settings; }
- (NSArray*) warnings { return _warnings; }

- (NSArray*) publicSettings
{
  NSMutableArray *a = [NSMutableArray array];
  NSEnumerator *e = [_settings objectEnumerator];
  GTSSettingDescriptor *d;
  while ((d = [e nextObject]) != nil)
    if (![d isUnstable]) [a addObject: d];
  return a;
}

- (GTSSettingDescriptor*) settingWithIdentifier: (NSString*)identifier
{
  NSEnumerator *e = [_settings objectEnumerator];
  GTSSettingDescriptor *d;
  while ((d = [e nextObject]) != nil)
    if ([[d identifier] isEqual: identifier]) return d;
  return nil;
}

- (GTSSettingDescriptor*) settingForKey: (NSString*)key
{
  NSEnumerator *e = [_settings objectEnumerator];
  GTSSettingDescriptor *d;
  while ((d = [e nextObject]) != nil)
    if ([[d key] isEqual: key]) return d;
  return nil;
}

- (NSString*) localizedString: (NSString*)string
{
  NSBundle *b;
  if (string == nil || _bundlePath == nil) return string;
  /* NSBundle only loads code on -load / -principalClass; resources are safe. */
  b = [NSBundle bundleWithPath: _bundlePath];
  return b ? [b localizedStringForKey: string value: string table: @"ThemeSettings"] : string;
}
@end
