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
    [NSDictionary dictionaryWithObject: @"org.example.x" forKey: @"Identifier"], @"Provider",
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
  XCTAssertEqualObjects([[p objectAtIndex: 4] source], GTSSourceOtherInfo);
}

- (void) testUnstableSettingsAreHiddenFromPublicList
{
  GTSThemeSettingsSchema *s = example(@"WinUITheme");
  XCTAssertEqual([[s settings] count], (NSUInteger)4);
  XCTAssertEqual([[s publicSettings] count], (NSUInteger)2);
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

- (void) testMissingProviderIsFatal
{
  NSMutableDictionary *p = minimal();
  NSError *err = nil;
  [p removeObjectForKey: @"Provider"];
  XCTAssertNil([GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidSchema);
}
@end
