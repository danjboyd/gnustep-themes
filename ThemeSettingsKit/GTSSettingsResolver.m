/* GTSSettingsResolver.m */
#import "GTSSettingsResolver.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSThemeCatalog.h"

@implementation GTSResolvedValue
- (void) dealloc
{
  [_effectiveValue release]; [_explicitValue release]; [_globalValue release];
  [_infoValue release]; [_note release]; [_caveats release];
  [super dealloc];
}
- (GTSValueState) state { return _state; }
- (id) effectiveValue { return _effectiveValue; }
- (id) explicitValue { return _explicitValue; }
- (id) globalValue { return _globalValue; }
- (id) infoValue { return _infoValue; }
- (NSString*) note { return _note; }
- (NSArray*) caveats { return _caveats; }
- (BOOL) hasOverride { return _explicitValue != nil; }
- (NSString*) description
{
  static const char *names[] = { "explicit", "inherited", "info-plist", "default", "unknown" };
  return [NSString stringWithFormat: @"<%s %@%@>", names[_state],
    _effectiveValue, [_caveats count] ? [NSString stringWithFormat: @" caveats=%@", _caveats] : @""];
}
@end

@implementation GTSSettingsResolver

- (id) initWithGlobal: (GTSDomainSnapshot*)global
          application: (GTSDomainSnapshot*)application
      applicationInfo: (NSDictionary*)appInfo
{
  if ((self = [super init]) != nil)
    {
      _global = [global retain];
      _application = [application retain];
      _appInfo = [appInfo copy];
    }
  return self;
}

- (void) dealloc
{
  [_global release]; [_application release]; [_appInfo release];
  [super dealloc];
}

- (BOOL) targetIsGlobal { return _application == nil; }

static BOOL
valueAllowed(GTSSettingDescriptor *s, NSArray *filter, id v)
{
  NSEnumerator *e;
  id f;
  if (filter == nil) return YES;
  e = [filter objectEnumerator];
  while ((f = [e nextObject]) != nil)
    if ([s value: f isEqualToValue: v]) return YES;
  return NO;
}

- (GTSResolvedValue*) resolveSetting: (GTSSettingDescriptor*)s
{
  GTSResolvedValue *r = [[[GTSResolvedValue alloc] init] autorelease];
  NSMutableArray *caveats = [NSMutableArray array];
  NSString *key = [s key];
  id appV = [_application objectForKey: key];
  id globalV = [_global objectForKey: key];
  id infoV = [_appInfo objectForKey: [s infoKey]];
  NSEnumerator *e = [[s precedence] objectEnumerator];
  GTSPrecedenceSource *src;
  BOOL found = NO;

  r->_explicitValue = [([self targetIsGlobal] ? globalV : appV) retain];
  r->_globalValue = [globalV retain];
  r->_infoValue = [infoV retain];

  while (!found && (src = [e nextObject]) != nil)
    {
      NSString *name = [src source];
      if ([name isEqual: GTSSourceArgument])
        {
          [caveats addObject: GTSSourceArgument];
        }
      else if ([name isEqual: GTSSourceOtherInfo])
        {
          [caveats addObject: GTSSourceOtherInfo];
        }
      else if ([name isEqual: GTSSourceApplication])
        {
          if (appV != nil && valueAllowed(s, [src values], appV))
            {
              r->_state = GTSValueExplicit;
              r->_effectiveValue = [appV retain];
              found = YES;
            }
        }
      else if ([name isEqual: GTSSourceGlobal])
        {
          if (globalV != nil && valueAllowed(s, [src values], globalV))
            {
              r->_state = [self targetIsGlobal] ? GTSValueExplicit : GTSValueInherited;
              r->_effectiveValue = [globalV retain];
              found = YES;
            }
        }
      else if ([name isEqual: GTSSourceApplicationInfo])
        {
          /* Only meaningful for an application target. */
          if (![self targetIsGlobal] && infoV != nil && valueAllowed(s, [src values], infoV))
            {
              r->_state = GTSValueInfoPlist;
              r->_effectiveValue = [infoV retain];
              found = YES;
            }
        }
    }

  if (!found)
    {
      if ([s unsetBehavior] == GTSUnsetStatic)
        {
          r->_state = GTSValueDefault;
          r->_effectiveValue = [[s unsetValue] retain];
        }
      else
        {
          r->_state = GTSValueUnknown;
        }
      r->_note = [[s unsetHelp] copy];
    }
  /* Only sources ranked above the winner can still override it. */
  r->_caveats = [caveats copy];
  return r;
}

- (GTSResolvedValue*) resolveThemeSelection
{
  GTSResolvedValue *r = [[[GTSResolvedValue alloc] init] autorelease];
  id appV = [_application objectForKey: @"GSTheme"];
  id globalV = [_global objectForKey: @"GSTheme"];

  r->_explicitValue = [([self targetIsGlobal] ? globalV : appV) retain];
  r->_globalValue = [globalV retain];
  r->_caveats = [[NSArray alloc] initWithObjects: GTSSourceArgument, nil];
  if (![self targetIsGlobal] && appV != nil)
    {
      r->_state = GTSValueExplicit;
      r->_effectiveValue = [appV retain];
    }
  else if (globalV != nil)
    {
      r->_state = [self targetIsGlobal] ? GTSValueExplicit : GTSValueInherited;
      r->_effectiveValue = [globalV retain];
    }
  else
    {
      r->_state = GTSValueDefault;
      r->_effectiveValue = [GTSDefaultThemeName retain];
    }
  return r;
}
@end
