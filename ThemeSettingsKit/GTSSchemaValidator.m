/* GTSSchemaValidator.m - see the header for what is checked and why. */
#import "GTSSchemaValidator.h"
#import "GTSThemeSettingsSchema.h"

@implementation GTSSchemaFinding
+ (id) findingWithSeverity: (GTSFindingSeverity)s where: (NSString*)where message: (NSString*)message
{
  GTSSchemaFinding *f = [[[self alloc] init] autorelease];
  f->_severity = s;
  f->_where = [where copy];
  f->_message = [message copy];
  return f;
}
- (void) dealloc { [_where release]; [_message release]; [super dealloc]; }
- (GTSFindingSeverity) severity { return _severity; }
- (BOOL) isError { return _severity == GTSFindingError; }
- (NSString*) where { return _where; }
- (NSString*) message { return _message; }
- (NSString*) description
{
  return [NSString stringWithFormat: @"%@: %@: %@", _severity == GTSFindingError ? @"ERROR" : @"WARNING",
    _where, _message];
}
@end

/* Collector: keeps the call sites short. */
@interface GTSFindings : NSObject
{
@public
  NSMutableArray *list;
}
- (void) error: (NSString*)where : (NSString*)fmt, ...;
- (void) warn: (NSString*)where : (NSString*)fmt, ...;
@end
@implementation GTSFindings
- (id) init { if ((self = [super init]) != nil) list = [NSMutableArray new]; return self; }
- (void) dealloc { [list release]; [super dealloc]; }
- (void) add: (GTSFindingSeverity)s where: (NSString*)w format: (NSString*)fmt args: (va_list)ap
{
  NSString *m = [[[NSString alloc] initWithFormat: fmt arguments: ap] autorelease];
  [list addObject: [GTSSchemaFinding findingWithSeverity: s where: w message: m]];
}
- (void) error: (NSString*)where : (NSString*)fmt, ...
{
  va_list ap; va_start(ap, fmt); [self add: GTSFindingError where: where format: fmt args: ap]; va_end(ap);
}
- (void) warn: (NSString*)where : (NSString*)fmt, ...
{
  va_list ap; va_start(ap, fmt); [self add: GTSFindingWarning where: where format: fmt args: ap]; va_end(ap);
}
@end

static BOOL isStr(id o) { return [o isKindOfClass: [NSString class]] && [(NSString*)o length] > 0; }
static BOOL isOptStr(id o) { return o == nil || [o isKindOfClass: [NSString class]]; }

/* YES/NO/true/false/1/0 (as the loader's GTSBoolValue). */
static BOOL isBoolSpelling(id v)
{
  NSString *s;
  if ([v isKindOfClass: [NSNumber class]]) return YES;
  if (![v isKindOfClass: [NSString class]]) return NO;
  s = [v lowercaseString];
  return [s isEqual: @"yes"] || [s isEqual: @"no"] || [s isEqual: @"true"] || [s isEqual: @"false"]
    || [s isEqual: @"1"] || [s isEqual: @"0"];
}

static void unknownKeys(GTSFindings *f, NSString *where, NSDictionary *d, NSArray *known, NSString *what)
{
  NSEnumerator *e = [[[d allKeys] sortedArrayUsingSelector: @selector(compare:)] objectEnumerator];
  id k;
  while ((k = [e nextObject]) != nil)
    if (![known containsObject: k])
      [f warn: where : @"unknown %@ key %@ (ignored by v1 readers; a typo?)", what, k];
}

@implementation GTSSchemaValidator

+ (NSUInteger) errorCountInFindings: (NSArray*)findings
{
  NSUInteger n = 0;
  NSEnumerator *e = [findings objectEnumerator];
  GTSSchemaFinding *f;
  while ((f = [e nextObject]) != nil)
    if ([f isError]) n++;
  return n;
}

+ (NSArray*) findingsForFile: (NSString*)path
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
    return [NSArray arrayWithObject: [GTSSchemaFinding findingWithSeverity: GTSFindingError
      where: @"file" message: @"not a readable text property list"]];
  return [self findingsForPropertyList: plist path: path];
}

+ (NSArray*) findingsForPropertyList: (id)plist path: (NSString*)path
{
  GTSFindings *f = [[GTSFindings new] autorelease];
  NSError *err = nil;
  GTSThemeSettingsSchema *schema;
  NSArray *settings, *groups;
  NSMutableSet *groupIds = [NSMutableSet set];
  NSMutableDictionary *byId = [NSMutableDictionary dictionary];   /* Identifier -> raw dict */
  NSEnumerator *e;
  id o;

  /* Layer 1: the loader. */
  schema = [GTSThemeSettingsSchema schemaWithPropertyList: plist path: path error: &err];
  if (schema == nil)
    {
      [f error: @"file" : @"rejected by the v1 loader: %@", [err localizedDescription]];
      return [[f->list copy] autorelease];
    }
  e = [[schema warnings] objectEnumerator];
  while ((o = [e nextObject]) != nil)
    [f error: @"loader" : @"%@ (the setting is skipped by every v1 editor)", o];
  if ([[schema unsupportedFeatures] count] > 0)
    [f warn: @"file" : @"RequiredFeatures %@ unknown to v1 readers: the whole theme is read-only",
      [[schema unsupportedFeatures] componentsJoinedByString: @", "]];

  /* Layer 2: strict checks on the raw file. */
  unknownKeys(f, @"file", plist, [NSArray arrayWithObjects: @"SchemaVersion", @"Theme",
    @"ThemeIdentifier", @"RequiredFeatures", @"Groups", @"Settings", nil], @"top-level");
  if ([[plist objectForKey: @"ThemeIdentifier"] rangeOfString: @"."].location == NSNotFound)
    [f warn: @"file" : @"ThemeIdentifier %@ is not reverse-DNS", [plist objectForKey: @"ThemeIdentifier"]];
  e = [[plist objectForKey: @"RequiredFeatures"] objectEnumerator];
  while ((o = [e nextObject]) != nil)
    if (!isStr(o)) [f error: @"file" : @"RequiredFeatures entry %@ is not a string", o];

  groups = [plist objectForKey: @"Groups"];
  if (groups != nil && ![groups isKindOfClass: [NSArray class]])
    [f error: @"Groups" : @"Groups must be an array"];
  else
    {
      e = [groups objectEnumerator];
      while ((o = [e nextObject]) != nil)
        {
          NSString *gid = [o isKindOfClass: [NSDictionary class]] ? [o objectForKey: @"Identifier"] : nil;
          if (!isStr(gid)) { [f error: @"Groups" : @"group entry without an Identifier string: %@", o]; continue; }
          if ([groupIds containsObject: gid]) [f error: @"Groups" : @"duplicate group %@", gid];
          [groupIds addObject: gid];
          if (!isOptStr([o objectForKey: @"Title"]) || !isOptStr([o objectForKey: @"Help"]))
            [f error: @"Groups" : @"group %@: Title/Help must be strings", gid];
          unknownKeys(f, @"Groups", o, [NSArray arrayWithObjects: @"Identifier", @"Title", @"Help", nil],
            [NSString stringWithFormat: @"group %@", gid]);
        }
    }

  settings = [plist objectForKey: @"Settings"];
  if ([settings count] == 0)
    [f warn: @"file" : @"no settings"];
  e = [settings objectEnumerator];
  while ((o = [e nextObject]) != nil)
    if ([o isKindOfClass: [NSDictionary class]] && isStr([o objectForKey: @"Identifier"])
        && [byId objectForKey: [o objectForKey: @"Identifier"]] == nil)
      [byId setObject: o forKey: [o objectForKey: @"Identifier"]];

  e = [settings objectEnumerator];
  while ((o = [e nextObject]) != nil)
    {
      NSDictionary *s = o;
      NSString *ident, *key;
      GTSSettingDescriptor *d;
      id v;
      NSEnumerator *e2;
      id x;

      if (![s isKindOfClass: [NSDictionary class]] || !isStr([s objectForKey: @"Identifier"]))
        continue;                                   /* already a loader error */
      ident = [s objectForKey: @"Identifier"];
      d = [schema settingWithIdentifier: ident];
      if (d == nil || [byId objectForKey: ident] != s)
        continue;                                   /* skipped or duplicate: loader error */
      key = [d key];

      unknownKeys(f, ident, s, [NSArray arrayWithObjects: @"Identifier", @"Key", @"Type", @"Values",
        @"CaseInsensitive", @"Scopes", @"Group", @"Title", @"Help", @"Unset", @"Precedence", @"InfoKey",
        @"Apply", @"Minimum", @"Maximum", @"RequiredFeatures", @"DependsOn", @"Overlaps", @"Status", nil],
        @"setting");

      if ([key isEqual: @"GSTheme"])
        [f error: ident : @"GSTheme is theme selection, not a theme setting"];

      if (!isOptStr([s objectForKey: @"Title"]) || !isOptStr([s objectForKey: @"Help"])
          || !isOptStr([s objectForKey: @"Group"]) || !isOptStr([s objectForKey: @"InfoKey"]))
        [f error: ident : @"Title, Help, Group and InfoKey must be strings"];
      if ([s objectForKey: @"Title"] == nil)
        [f warn: ident : @"no Title (editors show the Identifier)"];
      v = [s objectForKey: @"Group"];
      if (isStr(v) && groups == nil)
        [f warn: ident : @"Group %@ but the file has no Groups", v];
      else if (isStr(v) && ![groupIds containsObject: v])
        [f error: ident : @"Group %@ is not defined in Groups", v];

      v = [s objectForKey: @"CaseInsensitive"];
      if (v != nil && !isBoolSpelling(v))
        [f error: ident : @"CaseInsensitive %@ is not a boolean (read as NO)", v];
      if (v != nil && [d type] != GTSSettingTypeEnum)
        [f warn: ident : @"CaseInsensitive only affects enum settings"];

      if ([s objectForKey: @"Values"] != nil && [d type] != GTSSettingTypeEnum)
        [f warn: ident : @"Values is ignored for Type %@", [s objectForKey: @"Type"]];
      if ([d type] == GTSSettingTypeEnum)
        {
          NSMutableArray *seen = [NSMutableArray array];
          e2 = [[d values] objectEnumerator];
          while ((x = [e2 nextObject]) != nil)
            {
              NSString *val = [x objectForKey: @"Value"];
              NSEnumerator *e3 = [seen objectEnumerator];
              NSString *prev;
              while ((prev = [e3 nextObject]) != nil)
                if ([d value: prev isEqualToValue: val])
                  [f error: ident : @"enum value %@ duplicates %@", val, prev];
              [seen addObject: val];
              if (!isOptStr([x objectForKey: @"Title"]) || !isOptStr([x objectForKey: @"Help"]))
                [f error: ident : @"enum value %@: Title/Help must be strings", val];
              unknownKeys(f, ident, x, [NSArray arrayWithObjects: @"Value", @"Title", @"Help", nil],
                [NSString stringWithFormat: @"enum value %@", val]);
            }
        }

      {
        id mn = [s objectForKey: @"Minimum"], mx = [s objectForKey: @"Maximum"];
        if ((mn || mx) && [d type] != GTSSettingTypeNumber)
          [f warn: ident : @"Minimum/Maximum are ignored for Type %@", [s objectForKey: @"Type"]];
        /* Non-numeric or inverted ranges, Status typos and duplicate Keys
           are loader errors since the Q2/Q4 decisions (#22591). */
      }

      v = [s objectForKey: @"Scopes"];
      if ([[NSSet setWithArray: v] count] != [v count])
        [f warn: ident : @"duplicate Scopes entries"];

      v = [s objectForKey: @"Unset"];
      unknownKeys(f, ident, v, [NSArray arrayWithObjects: @"Behavior", @"Value", @"Help", nil], @"Unset");
      if (!isOptStr([v objectForKey: @"Help"]))
        [f error: ident : @"Unset.Help must be a string"];
      if ([d unsetBehavior] == GTSUnsetDynamic && !isStr([v objectForKey: @"Help"]))
        [f warn: ident : @"dynamic Unset without Help (editors cannot say what Automatic follows)"];

      v = [s objectForKey: @"Precedence"];
      if (v != nil && [v count] == 0)
        [f error: ident : @"empty Precedence: no source can ever supply a value"];
      {
        /* A source may repeat (Adwaita/WinUI: a filtered applicationInfo
           above global, the unfiltered one below it). A repeat is dead only
           after an unfiltered entry for that source, or with the same filter. */
        NSMutableSet *unfiltered = [NSMutableSet set];
        NSMutableArray *seenEntries = [NSMutableArray array];
        e2 = [v objectEnumerator];
        while ((x = [e2 nextObject]) != nil)
          {
            NSString *src = [x isKindOfClass: [NSDictionary class]] ? [x objectForKey: @"Source"] : x;
            id filt = [x isKindOfClass: [NSDictionary class]] ? [x objectForKey: @"Values"] : nil;
            NSArray *entry = [NSArray arrayWithObjects: src, (filt ? filt : (id)[NSNull null]), nil];
            if ([unfiltered containsObject: src])
              [f warn: ident : @"precedence %@ after an unfiltered %@ entry can never apply", x, src];
            else if ([seenEntries containsObject: entry])
              [f warn: ident : @"precedence entry %@ is listed twice", x];
            [seenEntries addObject: entry];
            if (filt == nil) [unfiltered addObject: src];
            if ([x isKindOfClass: [NSDictionary class]])
              unknownKeys(f, ident, x, [NSArray arrayWithObjects: @"Source", @"Values", nil],
                [NSString stringWithFormat: @"precedence %@", src]);
            if (filt != nil && (![filt isKindOfClass: [NSArray class]] || [filt count] == 0))
              [f error: ident : @"precedence %@: Values must be a non-empty array", src];
            else
              {
                NSEnumerator *e3 = [filt objectEnumerator];
                id fv;
                while ((fv = [e3 nextObject]) != nil)
                  if ([d problemWithValue: fv] != nil)
                    [f error: ident : @"precedence %@: Values entry %@: %@", src, fv, [d problemWithValue: fv]];
              }
          }
      }

      e2 = [[s objectForKey: @"RequiredFeatures"] objectEnumerator];
      while ((x = [e2 nextObject]) != nil)
        if (!isStr(x)) [f error: ident : @"RequiredFeatures entry %@ is not a string", x];
      if ([d isReadOnly])
        [f warn: ident : @"RequiredFeatures %@ unknown to v1 readers: read-only",
          [[d unsupportedFeatures] componentsJoinedByString: @", "]];

      v = [s objectForKey: @"DependsOn"];
      if (v != nil)
        {
          NSString *other = [v isKindOfClass: [NSDictionary class]] ? [v objectForKey: @"Setting"] : nil;
          GTSSettingDescriptor *od = isStr(other) ? [schema settingWithIdentifier: other] : nil;
          id vals = [v isKindOfClass: [NSDictionary class]] ? [v objectForKey: @"Values"] : nil;
          if (![v isKindOfClass: [NSDictionary class]])
            [f error: ident : @"DependsOn must be a dictionary"];
          else if (od == nil && isStr(other) && [byId objectForKey: other] != nil)
            [f error: ident : @"DependsOn.Setting %@ was skipped by the loader (see its error)", other];
          else if (od == nil || [other isEqual: ident])
            [f error: ident : @"DependsOn.Setting %@ is not another setting in this file", other];
          else if (![vals isKindOfClass: [NSArray class]] || [vals count] == 0)
            [f error: ident : @"DependsOn.Values must be a non-empty array"];
          else
            {
              NSEnumerator *e3 = [vals objectEnumerator];
              id dv;
              while ((dv = [e3 nextObject]) != nil)
                if ([od problemWithValue: dv] != nil)
                  [f error: ident : @"DependsOn value %@ for %@: %@", dv, other, [od problemWithValue: dv]];
              unknownKeys(f, ident, v, [NSArray arrayWithObjects: @"Setting", @"Values", nil], @"DependsOn");
            }
        }

      v = [s objectForKey: @"Overlaps"];
      if (v != nil && ![v isKindOfClass: [NSArray class]])
        [f error: ident : @"Overlaps must be an array"];
      else
        {
          e2 = [v objectEnumerator];
          while ((x = [e2 nextObject]) != nil)
            if (isStr(x) && [schema settingWithIdentifier: x] == nil && [byId objectForKey: x] != nil)
              [f error: ident : @"Overlaps entry %@ was skipped by the loader (see its error)", x];
            else if (!isStr(x) || [x isEqual: ident] || [schema settingWithIdentifier: x] == nil)
              [f error: ident : @"Overlaps entry %@ is not another setting in this file", x];
        }
    }
  return [[f->list copy] autorelease];
}
@end
