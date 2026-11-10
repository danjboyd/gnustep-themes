#import "GTSTestSupport.h"
#import "GTSThemeSettingsSchema.h"

@interface GTSSchemaTests : XCTestCase
@end

static GTSThemeSettingsSchema *
example(NSString *name)
{
  NSString *p = [GTSExamplesDir() stringByAppendingPathComponent:
    [name stringByAppendingPathExtension: @"theme"]];
  NSError *err = nil;
  GTSThemeSettingsSchema *s = [GTSThemeSettingsSchema schemaForThemeBundleAtPath: p error: &err];
  if (s == nil) NSLog(@"%@: %@", name, err);
  return s;
}

static NSMutableDictionary *
minimal(void)
{
  NSMutableDictionary *setting = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"x.flag", @"Identifier", @"XFlag", @"Key", @"bool", @"Type",
    [NSArray arrayWithObject: @"global"], @"Scopes",
    [NSDictionary dictionaryWithObjectsAndKeys: @"static", @"Behavior", @"NO", @"Value", nil], @"Unset",
    @"restart", @"Apply", nil];
  return [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"1", @"SchemaVersion", @"X", @"Theme",
    @"org.example.x", @"ThemeIdentifier",
    [NSMutableArray arrayWithObject: setting], @"Settings", nil];
}

@implementation GTSSchemaTests

- (void) testExamplesLoadWithoutWarnings
{
  NSEnumerator *e = [[NSArray arrayWithObjects: @"Gumdrop", @"Adwaita", @"WinUITheme", nil] objectEnumerator];
  NSString *n;
  while ((n = [e nextObject]) != nil)
    {
      GTSThemeSettingsSchema *s = example(n);
      XCTAssertNotNil(s, @"%@", n);
      XCTAssertEqualObjects([s theme], n);
      XCTAssertEqual([[s warnings] count], (NSUInteger)0, @"%@ %@", n, [s warnings]);
      XCTAssertTrue([[s settings] count] > 0);
    }
}

- (void) testGumdropCaseInsensitiveEnumStoresCanonicalSpelling
{
  GTSSettingDescriptor *d = [example(@"Gumdrop") settingWithIdentifier: @"gumdrop.menu-style"];
  XCTAssertEqualObjects([d key], @"GumdropMenuStyle");
  XCTAssertNil([d problemWithValue: @"MenuBar"]);
  XCTAssertEqualObjects([d storedFormOfValue: @"MenuBar"], @"menubar");
  XCTAssertNotNil([d problemWithValue: @"sideways"]);
  XCTAssertEqual([d applyPolicy], GTSApplyRestart);
  /* Absent is a distinct state from stored "primary". */
  XCTAssertEqual([d unsetBehavior], GTSUnsetStatic);
  XCTAssertEqualObjects([d unsetValue], @"primary");
}

- (void) testAdwaitaExplicitDefaultIsAValueAndUnsetIsDynamic
{
  GTSSettingDescriptor *d = [example(@"Adwaita") settingWithIdentifier: @"adwaita.color-scheme"];
  XCTAssertNil([d problemWithValue: @"default"], @"'default' is an explicit stored value");
  XCTAssertEqual([d unsetBehavior], GTSUnsetDynamic);
  XCTAssertNil([d unsetValue], @"dynamic defaults never name a stored token");
  XCTAssertNotNil([d unsetHelp]);
}

- (void) testCustomPrecedenceParsesValueFilters
{
  GTSSettingDescriptor *d = [example(@"WinUITheme") settingWithIdentifier: @"winui.menu-style"];
  NSArray *p = [d precedence];
  XCTAssertEqual([p count], (NSUInteger)5);
  XCTAssertEqualObjects([[p objectAtIndex: 2] source], GTSSourceApplicationInfo);
  XCTAssertEqualObjects([[p objectAtIndex: 2] values], [NSArray arrayWithObject: @"menubar"]);
  XCTAssertNil([[p objectAtIndex: 3] values]);
  XCTAssertEqualObjects([[p objectAtIndex: 4] values], [NSArray arrayWithObject: @"more"]);
}

- (void) testUnstableSettingsAreHiddenFromPublicList
{
  NSMutableDictionary *p = minimal();
  NSMutableDictionary *u = [[[[p objectForKey: @"Settings"] lastObject] mutableCopy] autorelease];
  GTSThemeSettingsSchema *s;
  [u setObject: @"x.unstable" forKey: @"Identifier"];
  [u setObject: @"XUnstable" forKey: @"Key"];      /* one descriptor per key (Q4) */
  [u setObject: @"unstable" forKey: @"Status"];
  [[p objectForKey: @"Settings"] addObject: u];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertEqual([[s settings] count], (NSUInteger)2);
  XCTAssertEqual([[s publicSettings] count], (NSUInteger)1);
}

- (void) testOwnerInventoriesLoadCompletely
{
  XCTAssertEqual([[example(@"Adwaita") settings] count], (NSUInteger)9);
  XCTAssertEqual([[example(@"WinUITheme") settings] count], (NSUInteger)9);
  XCTAssertEqualObjects([[example(@"Adwaita") settingWithIdentifier: @"adwaita.color-scheme"] key],
    @"GnomeThemeColorScheme");
}

- (void) testNumberRange
{
  GTSSettingDescriptor *d = [example(@"Adwaita") settingWithIdentifier: @"adwaita.font-scale"];
  XCTAssertNil([d problemWithValue: @"1.25"]);
  XCTAssertNil([d problemWithValue: [NSNumber numberWithDouble: 2.0]]);
  XCTAssertNotNil([d problemWithValue: @"2.5"]);
  XCTAssertNotNil([d problemWithValue: @"0.5"]);
  XCTAssertNotNil([d problemWithValue: @"big"]);
}

- (void) testUnknownRequiredFeatureMakesSettingReadOnly
{
  NSMutableDictionary *p = minimal();
  NSMutableDictionary *st = [[p objectForKey: @"Settings"] lastObject];
  GTSThemeSettingsSchema *s;
  [st setObject: [NSArray arrayWithObject: @"conditional-values"] forKey: @"RequiredFeatures"];
  [st setObject: @"presentation-only, ignored" forKey: @"SomeFutureHint"];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertTrue([[[s settings] lastObject] isReadOnly]);
  XCTAssertFalse([s isReadOnly]);
  [p setObject: [NSArray arrayWithObject: @"whole-theme-feature"] forKey: @"RequiredFeatures"];
  [st removeObjectForKey: @"RequiredFeatures"];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertTrue([s isReadOnly]);
  XCTAssertEqualObjects([s unsupportedFeatures], [NSArray arrayWithObject: @"whole-theme-feature"]);
}

- (void) testBoolNormalisation
{
  GTSSettingDescriptor *d = [example(@"Adwaita") settingWithIdentifier: @"adwaita.header-bar-toolbar"];
  XCTAssertTrue([d value: @"YES" isEqualToValue: [NSNumber numberWithBool: YES]]);
  XCTAssertTrue([d value: @"no" isEqualToValue: @"NO"]);
  XCTAssertEqualObjects([d storedFormOfValue: @"true"], @"YES");
  XCTAssertNotNil([d problemWithValue: @"maybe"]);
}

- (void) testDefaultPrecedence
{
  GTSThemeSettingsSchema *s = [GTSThemeSettingsSchema schemaWithPropertyList: minimal() path: @"mem" error: NULL];
  NSArray *p = [[[s settings] lastObject] precedence];
  XCTAssertEqualObjects([p valueForKey: @"source"], ([NSArray arrayWithObjects:
    GTSSourceArgument, GTSSourceApplication, GTSSourceGlobal, nil]));
}

- (void) testDynamicUnsetWithStoredTokenIsRejected
{
  NSMutableDictionary *p = minimal();
  NSMutableDictionary *st = [[p objectForKey: @"Settings"] lastObject];
  GTSThemeSettingsSchema *s;
  [st setObject: [NSDictionary dictionaryWithObjectsAndKeys: @"dynamic", @"Behavior", @"system", @"Value", nil]
         forKey: @"Unset"];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertNotNil(s, @"file still loads");
  XCTAssertEqual([[s settings] count], (NSUInteger)0, @"bad setting skipped");
  XCTAssertEqual([[s warnings] count], (NSUInteger)1);
}

- (void) testFutureVersionRejected
{
  NSMutableDictionary *p = minimal();
  NSError *err = nil;
  [p setObject: @"2" forKey: @"SchemaVersion"];
  XCTAssertNil([GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnsupportedVersion);
}

- (void) testSchemaVersionMustBeAnInteger
{
  NSArray *bad = [NSArray arrayWithObjects: [NSNumber numberWithBool: YES],
    [NSNumber numberWithDouble: 1.5], @"1x", @"", nil];
  NSEnumerator *e = [bad objectEnumerator];
  id v;
  while ((v = [e nextObject]) != nil)
    {
      NSMutableDictionary *p = minimal();
      [p setObject: v forKey: @"SchemaVersion"];
      XCTAssertNil([GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL], @"%@", v);
    }
  {
    NSMutableDictionary *p = minimal();
    [p setObject: [NSNumber numberWithInt: 1] forKey: @"SchemaVersion"];
    XCTAssertNotNil([GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL]);
  }
}

- (void) testDuplicateIdentifierSkipped
{
  NSMutableDictionary *p = minimal();
  NSMutableArray *a = [p objectForKey: @"Settings"];
  GTSThemeSettingsSchema *s;
  [a addObject: [a lastObject]];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertEqual([[s settings] count], (NSUInteger)1);
  XCTAssertEqual([[s warnings] count], (NSUInteger)1);
}

- (void) testMissingThemeIdentifierIsFatal
{
  NSMutableDictionary *p = minimal();
  NSError *err = nil;
  [p removeObjectForKey: @"ThemeIdentifier"];
  XCTAssertNil([GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidSchema);
}
/* Lead decisions Q2/Q4 (#22591): the loader skips settings it used to accept
   silently. Each case: the bad setting is skipped with one warning naming it,
   and a valid neighbour still loads. */
static GTSThemeSettingsSchema *
withSecondSetting(NSDictionary *changes, NSString *removeKey)
{
  NSMutableDictionary *p = minimal();
  NSMutableArray *a = [p objectForKey: @"Settings"];
  NSMutableDictionary *n = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"x.scale", @"Identifier", @"XScale", @"Key", @"number", @"Type",
    [NSArray arrayWithObject: @"global"], @"Scopes",
    [NSDictionary dictionaryWithObjectsAndKeys: @"static", @"Behavior", @"1.0", @"Value", nil], @"Unset",
    @"restart", @"Apply", nil];
  [n addEntriesFromDictionary: changes];
  if (removeKey) [n removeObjectForKey: removeKey];
  [a addObject: n];
  return [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
}

static BOOL
skipped(GTSThemeSettingsSchema *s, NSString *needle)
{
  return s != nil && [[s settings] count] == 1 && [s settingWithIdentifier: @"x.flag"] != nil
    && [[s warnings] count] == 1
    && [[[s warnings] objectAtIndex: 0] rangeOfString: needle].location != NSNotFound;
}

- (void) testStatusTypoSkipsSetting
{
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObject: @"Unstable" forKey: @"Status"], nil);
  XCTAssertTrue(skipped(s, @"x.scale: Status Unstable is not public or unstable"), @"%@", [s warnings]);
}

- (void) testExplicitStatusValuesStillLoad
{
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObject: @"public" forKey: @"Status"], nil);
  XCTAssertEqual([[s settings] count], (NSUInteger)2);
  XCTAssertFalse([[s settingWithIdentifier: @"x.scale"] isUnstable]);
  s = withSecondSetting([NSDictionary dictionaryWithObject: @"unstable" forKey: @"Status"], nil);
  XCTAssertTrue([[s settingWithIdentifier: @"x.scale"] isUnstable]);
  XCTAssertEqual([[s warnings] count], (NSUInteger)0);
}

- (void) testNonNumericMinimumSkipsSetting
{
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObject: @"small" forKey: @"Minimum"], nil);
  XCTAssertTrue(skipped(s, @"x.scale: Minimum/Maximum must be numbers"), @"%@", [s warnings]);
  s = withSecondSetting([NSDictionary dictionaryWithObject: @"2.0x" forKey: @"Maximum"], nil);
  XCTAssertTrue(skipped(s, @"Minimum/Maximum must be numbers"), @"trailing junk: %@", [s warnings]);
  s = withSecondSetting([NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES] forKey: @"Maximum"], nil);
  XCTAssertTrue(skipped(s, @"Minimum/Maximum must be numbers"), @"bool: %@", [s warnings]);
}

- (void) testNumericMinimumFormsStillLoad
{
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObjectsAndKeys:
    @"0.8", @"Minimum", [NSNumber numberWithDouble: 2.0], @"Maximum", nil], nil);
  GTSSettingDescriptor *d = [s settingWithIdentifier: @"x.scale"];
  XCTAssertNotNil(d, @"%@", [s warnings]);
  XCTAssertEqual([[d minimum] doubleValue], 0.8);
  XCTAssertEqual([[d maximum] doubleValue], 2.0);
}

- (void) testInvertedRangeSkipsSetting
{
  /* dynamic Unset, so the Unset.Value range check cannot catch it first */
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObjectsAndKeys:
    @"2.5", @"Minimum", @"2.0", @"Maximum",
    [NSDictionary dictionaryWithObjectsAndKeys: @"dynamic", @"Behavior", @"follows the desktop", @"Help", nil], @"Unset",
    nil], nil);
  XCTAssertTrue(skipped(s, @"x.scale: Minimum 2.5 is greater than Maximum 2.0"), @"%@", [s warnings]);
}

- (void) testDuplicateKeyKeepsFirstSkipsLater
{
  GTSThemeSettingsSchema *s = withSecondSetting([NSDictionary dictionaryWithObjectsAndKeys:
    @"XFlag", @"Key", @"bool", @"Type",
    [NSDictionary dictionaryWithObjectsAndKeys: @"static", @"Behavior", @"YES", @"Value", nil], @"Unset", nil], nil);
  XCTAssertTrue(skipped(s, @"x.scale: Key XFlag is already described by x.flag; skipped"), @"%@", [s warnings]);
  XCTAssertEqualObjects([[s settingForKey: @"XFlag"] identifier], @"x.flag", @"the first descriptor wins");
}
@end
