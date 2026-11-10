#import "GTSTestSupport.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSSettingsResolver.h"
#import "GTSDefaultsDomainStore.h"

static GTSDomainSnapshot *
snap(NSString *name, NSDictionary *d)
{
  return [[[GTSDomainSnapshot alloc] initWithDomainName: name values: d] autorelease];
}

static NSDictionary *
D(id v1, ...)
{
  /* D(value, key, ..., nil) */
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  va_list ap;
  id v = v1;
  va_start(ap, v1);
  while (v != nil)
    {
      id k = va_arg(ap, id);
      [d setObject: v forKey: k];
      v = va_arg(ap, id);
    }
  va_end(ap);
  return d;
}

static GTSSettingDescriptor *
setting(NSString *theme, NSString *ident)
{
  NSString *p = [[GTSExamplesDir() stringByAppendingPathComponent: theme]
    stringByAppendingPathExtension: @"theme"];
  return [[GTSThemeSettingsSchema schemaForThemeBundleAtPath: p error: NULL]
    settingWithIdentifier: ident];
}

static GTSResolvedValue *
resolve(GTSSettingDescriptor *s, NSDictionary *global, NSDictionary *app, NSDictionary *info)
{
  GTSSettingsResolver *r = [[[GTSSettingsResolver alloc]
    initWithGlobal: snap(NSGlobalDomain, global)
       application: app ? snap(@"org.example.App", app) : nil
   applicationInfo: info] autorelease];
  return [r resolveSetting: s];
}

@interface GTSCatalogResolverTests : XCTestCase
@end

@implementation GTSCatalogResolverTests

- (NSString*) makeTheme: (NSString*)name in: (NSString*)root
             schemaFrom: (NSString*)example version: (NSString*)version
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *b = [[root stringByAppendingPathComponent: name] stringByAppendingPathExtension: @"theme"];
  NSString *res = [b stringByAppendingPathComponent: @"Resources"];
  [fm createDirectoryAtPath: res withIntermediateDirectories: YES attributes: nil error: NULL];
  if (example != nil)
    {
      NSString *src = [[[GTSExamplesDir() stringByAppendingPathComponent: example]
        stringByAppendingPathExtension: @"theme"] stringByAppendingPathComponent: @"Resources/ThemeSettings.plist"];
      NSMutableDictionary *pl = [[[[NSString stringWithContentsOfFile: src] propertyList] mutableCopy] autorelease];
      [pl writeToFile: [res stringByAppendingPathComponent: @"ThemeSettings.plist"] atomically: YES];
    }
  [[NSDictionary dictionaryWithObjectsAndKeys: [@"org.example.theme." stringByAppendingString: name],
     @"CFBundleIdentifier", (version ? version : @"7"), @"CFBundleVersion", nil]
    writeToFile: [res stringByAppendingPathComponent: @"Info-gnustep.plist"] atomically: YES];
  return b;
}

- (GTSThemeCatalog*) catalog
{
  NSString *base = [GTSTestRoot() stringByAppendingPathComponent: @"catalog"];
  NSString *user = [base stringByAppendingPathComponent: @"user/Themes"];
  NSString *sys = [base stringByAppendingPathComponent: @"system/Themes"];
  NSString *local = [base stringByAppendingPathComponent: @"local/Themes"];
  NSString *broken;
  [self makeTheme: @"Adwaita" in: user schemaFrom: @"Adwaita" version: @"user-copy"];
  [self makeTheme: @"Adwaita" in: sys schemaFrom: @"Adwaita" version: @"bundled"];
  [self makeTheme: @"Gumdrop" in: sys schemaFrom: @"Gumdrop" version: nil];
  [self makeTheme: @"NoMeta" in: local schemaFrom: nil version: nil];
  broken = [self makeTheme: @"Broken" in: local schemaFrom: nil version: nil];
  [@"{ SchemaVersion = 9; }" writeToFile: [broken stringByAppendingPathComponent: @"Resources/ThemeSettings.plist"]
                              atomically: YES];
  return [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObjects:
    [GTSThemeSearchRoot rootWithPath: user origin: GTSOriginUser],
    [GTSThemeSearchRoot rootWithPath: local origin: GTSOriginLocal],
    [GTSThemeSearchRoot rootWithPath: [base stringByAppendingPathComponent: @"missing"] origin: GTSOriginNetwork],
    [GTSThemeSearchRoot rootWithPath: sys origin: GTSOriginSystem], nil]] autorelease];
}

- (void) testUserCopyShadowsBundledCopyAndIsReported
{
  GTSThemeCatalog *c = [self catalog];
  GTSThemeRecord *a = [c themeNamed: @"Adwaita"];
  XCTAssertEqualObjects([a origin], GTSOriginUser);
  XCTAssertEqualObjects([a bundleVersion], @"user-copy");
  XCTAssertEqualObjects([a themeIdentifier], @"org.gnustep.themes.adwaita");
  XCTAssertEqual([[a shadowedRecords] count], (NSUInteger)1);
  {
    GTSThemeRecord *sh = [[a shadowedRecords] lastObject];
    XCTAssertEqualObjects([sh bundleVersion], @"bundled");
    XCTAssertEqualObjects([sh origin], GTSOriginSystem);
    XCTAssertEqualObjects([sh themeIdentifier], [a themeIdentifier], @"same logical theme ...");
    XCTAssertFalse([[a descriptorFingerprint] isEqual: [sh descriptorFingerprint]], @"... but distinct installed artifacts");
  }
  XCTAssertEqualObjects([[c themes] valueForKey: @"name"], ([NSArray arrayWithObjects:
    @"Adwaita", @"Broken", @"Gumdrop", @"NoMeta", nil]));
}

- (void) testThemesWithoutOrWithBadMetadata
{
  GTSThemeCatalog *c = [self catalog];
  GTSThemeRecord *n = [c themeNamed: @"NoMeta"], *b = [c themeNamed: @"Broken"];
  XCTAssertTrue([n isAvailable]);
  XCTAssertNil([n schema]);
  XCTAssertNil([n schemaError], @"no file is not an error");
  XCTAssertEqualObjects([n bundleIdentifier], @"org.example.theme.NoMeta");
  XCTAssertNil([n themeIdentifier], @"no logical id is invented from the bundle id");
  XCTAssertNotNil([n descriptorFingerprint]);
  XCTAssertNil([b schema]);
  XCTAssertEqual([[b schemaError] code], (NSInteger)GTSErrorUnsupportedVersion);
}

- (void) testSelectionRecords
{
  GTSThemeCatalog *c = [self catalog];
  GTSThemeRecord *r = [c recordForSelection: @"Vanished"];
  XCTAssertFalse([r isAvailable]);
  XCTAssertEqualObjects([r name], @"Vanished");
  XCTAssertTrue([[c recordForSelection: nil] isBuiltIn]);
  XCTAssertTrue([[c recordForSelection: @"GNUstep"] isBuiltIn]);
  XCTAssertEqualObjects([[c recordForSelection: @"Gumdrop.theme"] origin], GTSOriginSystem);
  r = [c recordForSelection: [[c themeNamed: @"Gumdrop"] path]];
  XCTAssertEqualObjects([r origin], GTSOriginExplicitPath);
  XCTAssertNotNil([r schema]);
}

- (void) testDefaultSearchRootsFollowIsolatedConfig
{
  NSArray *roots = [GTSThemeCatalog defaultSearchRoots];
  XCTAssertTrue([roots count] >= 2);
  XCTAssertEqualObjects([[roots objectAtIndex: 0] origin], GTSOriginUser);
  XCTAssertEqualObjects([[roots lastObject] origin], GTSOriginSystem);
}

/* --- resolver --- */

- (void) testGumdropInfoPlistFallbackOnlyWhenUnset
{
  GTSSettingDescriptor *s = setting(@"Gumdrop", @"gumdrop.menu-style");
  NSDictionary *info = D(@"menubar", @"GumdropMenuStyle", nil);
  GTSResolvedValue *v = resolve(s, D(nil), D(nil), info);
  XCTAssertEqual([v state], GTSValueInfoPlist);
  XCTAssertEqualObjects([v effectiveValue], @"menubar");
  XCTAssertFalse([v hasOverride]);

  v = resolve(s, D(@"primary", @"GumdropMenuStyle", nil), D(nil), info);
  XCTAssertEqual([v state], GTSValueInherited, @"global outranks Info.plist for Gumdrop");
  XCTAssertEqualObjects([v effectiveValue], @"primary");

  v = resolve(s, D(nil), D(nil), nil);
  XCTAssertEqual([v state], GTSValueDefault);
  XCTAssertEqualObjects([v effectiveValue], @"primary");
  XCTAssertFalse([v hasOverride], @"absent is not the same as stored primary");

  v = resolve(s, D(nil), D(@"primary", @"GumdropMenuStyle", nil), nil);
  XCTAssertEqual([v state], GTSValueExplicit);
  XCTAssertTrue([v hasOverride]);
  XCTAssertEqualObjects([v caveats], [NSArray arrayWithObject: GTSSourceArgument]);
}

- (void) testAdwaitaInfoNoBeatsGlobalYes
{
  GTSSettingDescriptor *s = setting(@"Adwaita", @"adwaita.header-bar-toolbar");
  GTSResolvedValue *v = resolve(s, D(@"YES", @"GnomeThemeHeaderBarToolbar", nil), D(nil),
    D(@"NO", @"GnomeThemeHeaderBarToolbar", nil));
  XCTAssertEqual([v state], GTSValueInfoPlist);
  XCTAssertEqualObjects([v effectiveValue], @"NO");

  v = resolve(s, D(@"NO", @"GnomeThemeHeaderBarToolbar", nil), D(nil),
    D(@"YES", @"GnomeThemeHeaderBarToolbar", nil));
  XCTAssertEqual([v state], GTSValueInherited, @"Info YES does not beat global");

  v = resolve(s, D(@"YES", @"GnomeThemeHeaderBarToolbar", nil), D(@"YES", @"GnomeThemeHeaderBarToolbar", nil),
    D(@"NO", @"GnomeThemeHeaderBarToolbar", nil));
  XCTAssertEqual([v state], GTSValueExplicit, @"app override wins over Info");

  /* Editing global: Info.plist of no app applies. */
  v = resolve(s, D(@"YES", @"GnomeThemeHeaderBarToolbar", nil), nil, nil);
  XCTAssertEqual([v state], GTSValueExplicit);
}

- (void) testAdwaitaDynamicDefaultIsUnknownAndExplicitDefaultIsExplicit
{
  GTSSettingDescriptor *s = setting(@"Adwaita", @"adwaita.color-scheme");
  GTSResolvedValue *v = resolve(s, D(nil), D(nil), nil);
  XCTAssertEqual([v state], GTSValueUnknown);
  XCTAssertNil([v effectiveValue]);
  XCTAssertNotNil([v note]);

  v = resolve(s, D(nil), D(@"default", @"GnomeThemeColorScheme", nil), nil);
  XCTAssertEqual([v state], GTSValueExplicit);
  XCTAssertEqualObjects([v effectiveValue], @"default");
}

- (void) testWinUIMenuStyleCustomPrecedence
{
  GTSSettingDescriptor *s = setting(@"WinUITheme", @"winui.menu-style");
  GTSResolvedValue *v = resolve(s, D(@"more", @"WinUIThemeMenuStyle", nil), D(nil),
    D(@"menubar", @"WinUIThemeMenuStyle", nil));
  XCTAssertEqual([v state], GTSValueInfoPlist, @"Info menubar outranks global");

  v = resolve(s, D(@"menubar", @"WinUIThemeMenuStyle", nil), D(nil),
    D(@"more", @"WinUIThemeMenuStyle", nil));
  XCTAssertEqual([v state], GTSValueInherited, @"Info 'more' ranks below global");

  v = resolve(s, D(nil), D(nil), D(@"more", @"WinUIThemeMenuStyle", nil));
  XCTAssertEqual([v state], GTSValueInfoPlist);
  XCTAssertEqualObjects([v effectiveValue], @"more");

  v = resolve(s, D(nil), D(nil), nil);
  XCTAssertEqual([v state], GTSValueDefault);
  XCTAssertEqualObjects([v effectiveValue], @"menubar");
}

- (void) testGumdropUppercaseInfoMenubarWinsAndResetInherits
{
  GTSSettingDescriptor *s = setting(@"Gumdrop", @"gumdrop.menu-style");
  NSDictionary *info = D(@"MENUBAR", @"GumdropMenuStyle", nil);
  GTSResolvedValue *v = resolve(s, D(nil), D(nil), info);
  XCTAssertEqual([v state], GTSValueInfoPlist, @"value filter is case-insensitive like the theme");
  /* App override, then reset: the next source shows through, never a write of primary. */
  v = resolve(s, D(@"primary", @"GumdropMenuStyle", nil), D(@"menubar", @"GumdropMenuStyle", nil), info);
  XCTAssertEqual([v state], GTSValueExplicit);
  v = resolve(s, D(@"primary", @"GumdropMenuStyle", nil), D(nil), info);
  XCTAssertEqual([v state], GTSValueInherited, @"after app reset: global");
  v = resolve(s, D(nil), D(nil), info);
  XCTAssertEqual([v state], GTSValueInfoPlist, @"after global reset too: app Info.plist");
}

- (void) testGumdropInvalidInfoValueEndsAsPrimary
{
  GTSResolvedValue *v = resolve(setting(@"Gumdrop", @"gumdrop.menu-style"), D(nil), D(nil),
    D(@"sideways", @"GumdropMenuStyle", nil));
  XCTAssertEqual([v state], GTSValueDefault);
  XCTAssertEqualObjects([v effectiveValue], @"primary");
}

- (void) testThemeSelectionIndependentOfSettings
{
  GTSSettingsResolver *r;
  GTSResolvedValue *v;
  r = [[[GTSSettingsResolver alloc] initWithGlobal: snap(NSGlobalDomain, D(@"WinUITheme", @"GSTheme", nil))
    application: snap(@"a", D(@"dark", @"GnomeThemeColorScheme", nil)) applicationInfo: nil] autorelease];
  v = [r resolveThemeSelection];
  XCTAssertEqual([v state], GTSValueInherited);
  XCTAssertEqualObjects([v effectiveValue], @"WinUITheme");
  /* The inactive Adwaita value is still resolvable and untouched. */
  XCTAssertEqual([[r resolveSetting: setting(@"Adwaita", @"adwaita.color-scheme")] state], GTSValueExplicit);

  r = [[[GTSSettingsResolver alloc] initWithGlobal: snap(NSGlobalDomain, D(nil))
    application: snap(@"a", D(nil)) applicationInfo: nil] autorelease];
  v = [r resolveThemeSelection];
  XCTAssertEqual([v state], GTSValueDefault);
  XCTAssertEqualObjects([v effectiveValue], GTSDefaultThemeName);
}
@end
