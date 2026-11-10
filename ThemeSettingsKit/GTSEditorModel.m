/* GTSEditorModel.m */
#import "GTSEditorModel.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSSettingsResolver.h"
#import "GTSEditSession.h"

@interface GTSEditorModel (Private)
- (NSString*) titleForValue: (id)value setting: (GTSSettingDescriptor*)s;
@end

@implementation GTSChoice
+ (id) choiceWithTitle: (NSString*)title value: (id)value
{
  GTSChoice *c = [[[self alloc] init] autorelease];
  c->_title = [title copy];
  c->_value = [value retain];
  return c;
}
- (void) dealloc { [_title release]; [_value release]; [super dealloc]; }
- (NSString*) title { return _title; }
- (id) value { return _value; }
- (NSString*) description { return [NSString stringWithFormat: @"%@=%@", _title, _value]; }
@end

@implementation GTSSettingRow
- (void) dealloc
{
  [_setting release]; [_choices release]; [_title release];
  [_stateText release]; [_note release]; [_text release];
  [super dealloc];
}
- (GTSSettingDescriptor*) setting { return _setting; }
- (NSString*) title { return _title; }
- (NSArray*) choices { return _choices; }
- (NSInteger) selectedIndex { return _selectedIndex; }
- (NSString*) stateText { return _stateText; }
- (NSString*) note { return _note; }
- (BOOL) canReset { return _canReset; }
- (BOOL) isFreeForm { return _isFreeForm; }
- (NSString*) text { return _text; }
- (BOOL) isReadOnly { return _readOnly; }
- (NSString*) description
{
  return [NSString stringWithFormat: @"<row %@ [%@] sel=%ld %@>", _title,
    [[_choices valueForKey: @"title"] componentsJoinedByString: @"|"], (long)_selectedIndex, _stateText];
}
@end

@implementation GTSEditorModel

- (id) initWithStore: (GTSDefaultsDomainStore*)store catalog: (GTSThemeCatalog*)catalog
{
  if ((self = [super init]) != nil)
    {
      _store = [store retain];
      _catalog = [catalog retain];
      [self setTargetGlobal];
    }
  return self;
}

- (void) dealloc
{
  [_store release]; [_catalog release]; [_appDomain release]; [_appName release];
  [_appInfo release]; [_session release]; [_globalBaseline release]; [_message release];
  [_hostDomain release];
  [super dealloc];
}

- (void) setMessage: (NSString*)m { ASSIGN(_message, m); }
- (NSString*) message { return _message; }

- (BOOL) openSessionForDomain: (NSString*)domain
{
  NSError *err = nil;
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: _store domain: domain error: &err] autorelease];
  ASSIGN(_session, s);
  [self setMessage: s ? nil : [err localizedDescription]];
  return s != nil;
}

- (BOOL) setTargetGlobal
{
  DESTROY(_appDomain); DESTROY(_appName); DESTROY(_appInfo); DESTROY(_globalBaseline);
  return [self openSessionForDomain: NSGlobalDomain];
}

- (BOOL) setTargetApplicationDomain: (NSString*)domain
                        displayName: (NSString*)name
                               info: (NSDictionary*)info
{
  NSError *err = nil;
  ASSIGN(_appDomain, domain);
  ASSIGN(_appName, (name ? name : domain));
  ASSIGN(_appInfo, info);
  ASSIGN(_globalBaseline, [_store snapshotForDomain: NSGlobalDomain error: &err]);
  if (_globalBaseline == nil)
    {
      DESTROY(_session);
      [self setMessage: [err localizedDescription]];
      return NO;
    }
  return [self openSessionForDomain: domain];
}

- (void) setHostDomain: (NSString*)domain { ASSIGN(_hostDomain, domain); }
- (BOOL) isEditable { return _session != nil && ![_session needsRebase]; }

- (BOOL) targetIsGlobal { return _appDomain == nil; }
- (GTSEditSession*) session { return _session; }

- (NSString*) targetTitle
{
  if ([self targetIsGlobal]) return @"All applications";
  return [NSString stringWithFormat: @"%@ (%@)", _appName, _appDomain];
}

- (GTSSettingsResolver*) resolver
{
  GTSDomainSnapshot *pending = [_session pendingSnapshot];
  if (_session == nil)
    pending = [[[GTSDomainSnapshot alloc] initWithDomainName: @"" values: nil] autorelease];
  if ([self targetIsGlobal] || _session == nil)
    return [[[GTSSettingsResolver alloc] initWithGlobal: pending application: nil
                                        applicationInfo: nil] autorelease];
  return [[[GTSSettingsResolver alloc] initWithGlobal: _globalBaseline application: pending
                                      applicationInfo: _appInfo] autorelease];
}

static NSString *
stateText(GTSResolvedValue *v, BOOL global)
{
  switch ([v state])
    {
      case GTSValueExplicit: return global ? @"Set for all applications" : @"Set for this application";
      case GTSValueInherited: return @"Inherited from all applications";
      case GTSValueInfoPlist: return @"From the application's Info.plist";
      case GTSValueDefault: return @"Theme default";
      case GTSValueUnknown: return @"Automatic";
    }
  return @"";
}

/* ---- theme selection ---- */

- (NSString*) titleForThemeValue: (NSString*)value
{
  GTSThemeRecord *r = [_catalog recordForSelection: value];
  if (![r isAvailable])
    return [NSString stringWithFormat: @"%@ (not installed)", [r name]];
  if ([r isBuiltIn])
    return @"GNUstep";
  return [r name];
}

- (NSArray*) themeChoices
{
  NSMutableArray *a = [NSMutableArray array];
  if (_session == nil)   /* nothing known: never present a guess as current */
    return [NSArray arrayWithObject: [GTSChoice choiceWithTitle: @"Unknown (settings could not be read)" value: nil]];
  GTSResolvedValue *v = [[self resolver] resolveThemeSelection];
  NSEnumerator *e = [[_catalog themes] objectEnumerator];
  GTSThemeRecord *r;
  id explicitV = [v explicitValue];
  BOOL listed = NO;

  if ([self targetIsGlobal])
    [a addObject: [GTSChoice choiceWithTitle: @"GNUstep (default)" value: nil]];
  else
    [a addObject: [GTSChoice choiceWithTitle: [NSString stringWithFormat:
      @"Same as all applications (%@)", [self titleForThemeValue: [v globalValue]]] value: nil]];
  while ((r = [e nextObject]) != nil)
    {
      [a addObject: [GTSChoice choiceWithTitle: [r name] value: [r name]]];
      if ([[r name] isEqual: explicitV]) listed = YES;
    }
  /* Keep a stored value visible even if it is not installed or is a path. */
  if (explicitV != nil && !listed)
    [a addObject: [GTSChoice choiceWithTitle: [self titleForThemeValue: explicitV] value: explicitV]];
  return a;
}

- (NSInteger) selectedThemeIndex
{
  id ex = [[[self resolver] resolveThemeSelection] explicitValue];
  NSArray *c = [self themeChoices];
  NSUInteger i;
  for (i = 0; i < [c count]; i++)
    {
      id v = [[c objectAtIndex: i] value];
      if ((v == nil && ex == nil) || [v isEqual: ex]) return i;
    }
  return 0;
}

- (NSString*) themeStateText
{
  if (_session == nil) return @"Not available";
  return stateText([[self resolver] resolveThemeSelection], [self targetIsGlobal]);
}

- (GTSThemeRecord*) effectiveTheme
{
  return [_catalog recordForSelection: [[[self resolver] resolveThemeSelection] effectiveValue]];
}

- (NSString*) themeNote
{
  GTSThemeRecord *r = [self effectiveTheme];
  NSMutableArray *parts = [NSMutableArray array];
  if (_session == nil)
    return @"This target's settings could not be read, so nothing here can be shown or changed. "
      @"Nothing has been written. See the message below.";
  if (![r isAvailable])
    return [NSString stringWithFormat: @"%@ is selected but not installed for this target; "
      @"GNUstep falls back to its default theme.", [r name]];
  if ([r isBuiltIn])
    return @"The built-in GNUstep theme has no theme settings.";
  [parts addObject: [NSString stringWithFormat: @"%@%@%@ - %@ copy at %@",
    [r themeIdentifier] ? [r themeIdentifier] : [r name],
    [r bundleVersion] ? @" " : @"", [r bundleVersion] ? [r bundleVersion] : @"",
    [r origin], [r path]]];
  if ([[r schema] isReadOnly])
    [parts addObject: [NSString stringWithFormat: @"Shown read-only: this theme requires %@, "
      @"which this version of the settings editor does not understand.",
      [[[r schema] unsupportedFeatures] componentsJoinedByString: @", "]]];
  /* Metadata says nothing about whether the theme's code was built for this
     app's GNUstep; never imply it was (lead 21062). */
  [parts addObject: @"Whether this theme's code matches the app's GNUstep version is not checked here."];
  if ([[r shadowedRecords] count] > 0)
    [parts addObject: [NSString stringWithFormat: @"Overrides %lu other installed copy(ies): %@",
      (unsigned long)[[r shadowedRecords] count],
      [[[r shadowedRecords] valueForKey: @"path"] componentsJoinedByString: @", "]]];
  if ([r schema] == nil)
    [parts addObject: [r schemaError] ? [NSString stringWithFormat: @"Settings description unreadable: %@",
      [[r schemaError] localizedDescription]] : @"This theme does not describe any settings."];
  return [parts componentsJoinedByString: @"\n"];
}

- (void) selectThemeChoiceAtIndex: (NSInteger)index
{
  NSArray *c = [self themeChoices];
  if (index < 0 || (NSUInteger)index >= [c count]) return;
  [_session stageThemeSelection: [[c objectAtIndex: index] value]];
}

/* ---- settings ---- */

- (void) setShowsUnstableSettings: (BOOL)flag { _showUnstable = flag; }

- (NSString*) unsetTitleFor: (GTSSettingDescriptor*)s resolved: (GTSResolvedValue*)v
{
  GTSThemeSettingsSchema *sc = [[self effectiveTheme] schema];
  if (![self targetIsGlobal] && [v globalValue] != nil)
    return [NSString stringWithFormat: @"Same as all applications (%@)",
      [self titleForValue: [v globalValue] setting: s]];
  if (![self targetIsGlobal] && [v infoValue] != nil)
    return [NSString stringWithFormat: @"Application default (%@)",
      [self titleForValue: [v infoValue] setting: s]];
  if ([s unsetBehavior] == GTSUnsetDynamic)
    return [NSString stringWithFormat: @"Automatic (%@)", [sc localizedString: [s unsetHelp]]];
  return [NSString stringWithFormat: @"Default (%@)", [self titleForValue: [s unsetValue] setting: s]];
}

- (NSString*) titleForValue: (id)value setting: (GTSSettingDescriptor*)s
{
  GTSThemeSettingsSchema *sc = [[self effectiveTheme] schema];
  NSEnumerator *e = [[s values] objectEnumerator];
  NSDictionary *d;
  if ([s type] == GTSSettingTypeBool)
    return [s value: value isEqualToValue: @"YES"] ? @"On" : @"Off";
  while ((d = [e nextObject]) != nil)
    if ([s value: [d objectForKey: @"Value"] isEqualToValue: value])
      return [sc localizedString: [d objectForKey: @"Title"] ? [d objectForKey: @"Title"] : [d objectForKey: @"Value"]];
  return [value description];
}

- (NSArray*) rows
{
  GTSThemeRecord *theme = [self effectiveTheme];
  GTSThemeSettingsSchema *sc = [theme schema];
  NSString *scope = [self targetIsGlobal] ? GTSScopeGlobal : GTSScopeApplication;
  GTSSettingsResolver *res = [self resolver];
  NSMutableArray *rows = [NSMutableArray array];
  NSEnumerator *e = [(_showUnstable ? [sc settings] : [sc publicSettings]) objectEnumerator];
  GTSSettingDescriptor *s;

  if (_session == nil) return rows;

  while ((s = [e nextObject]) != nil)
    {
      GTSResolvedValue *v;
      GTSSettingRow *row;
      NSMutableArray *choices = [NSMutableArray array];
      NSMutableArray *notes = [NSMutableArray array];
      NSUInteger i;

      if (![s supportsScope: scope]) continue;
      v = [res resolveSetting: s];
      row = [[[GTSSettingRow alloc] init] autorelease];
      row->_setting = [s retain];
      row->_title = [[sc localizedString: [s title]] copy];
      row->_stateText = [stateText(v, [self targetIsGlobal]) copy];
      row->_readOnly = [s isReadOnly] || [sc isReadOnly];
      row->_canReset = [v hasOverride] && !row->_readOnly;
      if ([s isReadOnly])
        [notes addObject: [NSString stringWithFormat: @"Read-only: needs %@.",
          [[s unsupportedFeatures] componentsJoinedByString: @", "]]];

      [choices addObject: [GTSChoice choiceWithTitle: [self unsetTitleFor: s resolved: v] value: nil]];
      if ([s type] == GTSSettingTypeBool)
        {
          [choices addObject: [GTSChoice choiceWithTitle: @"On" value: @"YES"]];
          [choices addObject: [GTSChoice choiceWithTitle: @"Off" value: @"NO"]];
        }
      else if ([s type] == GTSSettingTypeEnum)
        {
          NSEnumerator *ve = [[s values] objectEnumerator];
          NSDictionary *d;
          while ((d = [ve nextObject]) != nil)
            [choices addObject: [GTSChoice choiceWithTitle: [self titleForValue: [d objectForKey: @"Value"] setting: s]
                                                     value: [d objectForKey: @"Value"]]];
        }
      else
        {
          row->_isFreeForm = YES;
          row->_text = [[[v explicitValue] description] copy];
        }
      row->_choices = [choices copy];
      row->_selectedIndex = 0;
      if ([v explicitValue] != nil)
        {
          for (i = 1; i < [choices count]; i++)
            if ([s value: [[choices objectAtIndex: i] value] isEqualToValue: [v explicitValue]])
              row->_selectedIndex = i;
          if (row->_selectedIndex == 0 && !row->_isFreeForm)
            [notes addObject: [NSString stringWithFormat: @"Stored value \"%@\" is not one this theme lists.",
              [v explicitValue]]];
        }

      if ([s help]) [notes addObject: [sc localizedString: [s help]]];
      if ([[s overlaps] count] > 0)
        [notes addObject: [NSString stringWithFormat: @"Interacts with: %@",
          [[s overlaps] componentsJoinedByString: @", "]]];
      if ([s applyPolicy] == GTSApplyRestart)
        [notes addObject: @"Takes effect when the application restarts."];
      else if ([s applyPolicy] == GTSApplyNewWindows)
        [notes addObject: @"Applies to windows and panels opened after saving."];
      if ([[v caveats] containsObject: GTSSourceOtherInfo])
        [notes addObject: @"Another bundle's Info.plist may also decide this at run time."];
      row->_note = [[notes componentsJoinedByString: @" "] copy];
      [rows addObject: row];
    }
  return rows;
}

- (BOOL) refuseReadOnly: (GTSSettingRow*)row
{
  if (![row isReadOnly]) return NO;
  [self setMessage: [NSString stringWithFormat: @"%@ is read-only in this version of the editor.", [row title]]];
  return YES;
}

- (BOOL) selectChoiceAtIndex: (NSInteger)index forRow: (GTSSettingRow*)row
{
  id value;
  NSString *problem = nil;
  if ([self refuseReadOnly: row]) return NO;
  if (index < 0 || (NSUInteger)index >= [[row choices] count]) return NO;
  value = [[[row choices] objectAtIndex: index] value];
  if (value == nil)
    {
      [_session stageResetForSetting: [row setting]];
      return YES;
    }
  if (![_session stageValue: value forSetting: [row setting] problem: &problem])
    {
      [self setMessage: problem];
      return NO;
    }
  return YES;
}

- (BOOL) setText: (NSString*)text forRow: (GTSSettingRow*)row
{
  NSString *problem = nil;
  if ([self refuseReadOnly: row]) return NO;
  if ([text length] == 0)
    {
      [_session stageResetForSetting: [row setting]];
      return YES;
    }
  if (![_session stageValue: text forSetting: [row setting] problem: &problem])
    {
      [self setMessage: problem];
      return NO;
    }
  return YES;
}

- (void) resetRow: (GTSSettingRow*)row
{
  if ([self refuseReadOnly: row]) return;
  [_session stageResetForSetting: [row setting]];
}

/* ---- apply/cancel ---- */

- (BOOL) hasChanges { return [_session hasChanges]; }
- (BOOL) needsRestart { return [_session needsRestart]; }

- (BOOL) editsHostProcess
{
  return _hostDomain != nil && [[_session domain] isEqual: _hostDomain];
}

- (BOOL) apply
{
  NSArray *conflicts = nil;
  NSError *err = nil;
  GTSApplyReceipt *r;
  int req;

  if (_session == nil) return NO;
  r = [_session applyWithConflicts: &conflicts error: &err];
  if (r != nil)
    {
      NSString *m;
      req = [r applyRequirement];
      if ([[r committedChanges] count] == 0)
        m = @"Nothing to save.";
      else if (req == GTSApplyRestart)
        m = @"Saved. Restart the affected applications to see every change.";
      else if (req == GTSApplyNewWindows)
        m = @"Saved. Windows and panels opened from now on use the new settings.";
      else if ([self editsHostProcess])
        m = @"Saved. The theme says it applies these settings while the app runs; "
            @"that has not been confirmed for this app. Restarting always applies them.";
      else
        m = @"Saved. Running applications that watch these settings may update; "
            @"a restart is the guaranteed way to see them.";
      if ([r refreshFailed])
        m = [m stringByAppendingFormat: @" However, the settings could not be re-read (%@); "
          @"reload before changing anything else. Do not save the same change again.",
          [[r refreshError] localizedDescription]];
      [self setMessage: m];
      if (![self targetIsGlobal])
        {
          GTSDomainSnapshot *g = [_store snapshotForDomain: NSGlobalDomain error: NULL];
          if (g != nil) ASSIGN(_globalBaseline, g);
        }
      return YES;
    }
  if ([conflicts count] > 0)
    {
      NSError *rebaseErr = nil;
      if ([_session rebaseWithError: &rebaseErr] != nil)
        [self setMessage: [NSString stringWithFormat:
          @"Not saved: %@ changed elsewhere since you opened this. The current values are now shown "
          @"with your changes kept; press Apply again to overwrite.",
          [[conflicts valueForKey: @"key"] componentsJoinedByString: @", "]]];
      else
        [self setMessage: [NSString stringWithFormat:
          @"Not saved: %@ changed elsewhere, and the current values could not be read (%@).",
          [[conflicts valueForKey: @"key"] componentsJoinedByString: @", "],
          [rebaseErr localizedDescription]]];
    }
  else if ([err code] == GTSErrorWriteFailed)
    [self setMessage: [NSString stringWithFormat:
      @"The save may not have completed (%@). Reload to see what is stored now; "
      @"your changes stay listed until they are confirmed.", [err localizedDescription]]];
  else if ([err code] == GTSErrorNeedsReload)
    [self setMessage: @"Reload first: the result of the previous save has not been confirmed."];
  else
    [self setMessage: [NSString stringWithFormat: @"Not saved: %@", [err localizedDescription]]];
  return NO;
}

- (void) cancel
{
  [_session discardChanges];
  [self setMessage: nil];
}

- (BOOL) reload
{
  NSError *err = nil;
  if (_session == nil)
    return [self targetIsGlobal] ? [self setTargetGlobal]
      : [self setTargetApplicationDomain: _appDomain displayName: _appName info: _appInfo];
  if ([_session rebaseWithError: &err] == nil)
    {
      [self setMessage: [NSString stringWithFormat: @"Could not reload: %@", [err localizedDescription]]];
      return NO;
    }
  if (![self targetIsGlobal])
    {
      GTSDomainSnapshot *g = [_store snapshotForDomain: NSGlobalDomain error: &err];
      if (g == nil)
        {
          [self setMessage: [NSString stringWithFormat: @"Could not reload: %@", [err localizedDescription]]];
          return NO;
        }
      ASSIGN(_globalBaseline, g);
    }
  return YES;
}
@end
