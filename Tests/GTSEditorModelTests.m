/* Behaviour of the shared editor model, as every front end will see it. */
#import "GTSTestSupport.h"
#import "GTSEditorModel.h"
#import "GTSEditSession.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSDefaultsDomainStore.h"

@interface GTSEditorModelTests : XCTestCase
{
  GTSEditorModel *model;
  NSString *app;
}
@end

@implementation GTSEditorModelTests

- (void) setUp
{
  GTSThemeCatalog *catalog;
  GTSRequireIsolatedDefaults();
  catalog = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: GTSExamplesDir() origin: GTSOriginSystem]]] autorelease];
  model = [[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                        catalog: catalog];
  app = [GTSUniqueDomain(@"editor") retain];
  GTSRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", @"GSTheme", @"Gumdrop", nil]);
  [model setTargetApplicationDomain: app displayName: @"Demo"
    info: [NSDictionary dictionaryWithObject: @"menubar" forKey: @"GumdropMenuStyle"]];
}

- (void) tearDown
{
  GTSRunDefaults([NSArray arrayWithObjects: @"delete", @"NSGlobalDomain", @"GSTheme", nil]);
  [model release]; model = nil;
  [app release]; app = nil;
}

- (GTSSettingRow*) rowNamed: (NSString*)ident
{
  NSEnumerator *e = [[model rows] objectEnumerator];
  GTSSettingRow *r;
  while ((r = [e nextObject]) != nil)
    if ([[[r setting] identifier] isEqual: ident]) return r;
  return nil;
}

- (void) testAppTargetInheritsGlobalThemeAndShowsItsSettings
{
  GTSSettingRow *row;
  XCTAssertEqual([model selectedThemeIndex], (NSInteger)0);
  XCTAssertEqualObjects([[[model themeChoices] objectAtIndex: 0] title], @"Same as all applications (Gumdrop)");
  XCTAssertEqualObjects([model themeStateText], @"Inherited from all applications");
  XCTAssertEqualObjects([[model effectiveTheme] name], @"Gumdrop");

  row = [self rowNamed: @"gumdrop.menu-style"];
  XCTAssertNotNil(row);
  XCTAssertEqual([row selectedIndex], (NSInteger)0, @"no override stored");
  XCTAssertFalse([row canReset]);
  XCTAssertEqualObjects([row stateText], @"From the application's Info.plist");
  XCTAssertEqualObjects([[[row choices] objectAtIndex: 0] title], @"Application default (Menu bar)");
  XCTAssertTrue([[row note] rangeOfString: @"restarts"].location != NSNotFound);
}

- (void) testChooseApplyResetRoundTrip
{
  GTSSettingRow *row = [self rowNamed: @"gumdrop.menu-style"];
  NSUInteger primary = [[[row choices] valueForKey: @"value"] indexOfObject: @"primary"];
  XCTAssertTrue([model selectChoiceAtIndex: primary forRow: row]);
  XCTAssertTrue([model hasChanges]);
  XCTAssertNil(GTSExternalRead(app, @"GumdropMenuStyle"), @"nothing written before Apply");
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"primary");
  XCTAssertTrue([[model message] rangeOfString: @"Restart"].location != NSNotFound);

  row = [self rowNamed: @"gumdrop.menu-style"];
  XCTAssertEqualObjects([row stateText], @"Set for this application");
  XCTAssertTrue([row canReset]);
  [model resetRow: row];
  XCTAssertTrue([model apply]);
  XCTAssertNil(GTSExternalRead(app, @"GumdropMenuStyle"));
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GSTheme"), @"Gumdrop",
    @"editing an app never touches global");
}

- (void) testCancelDropsEverything
{
  [model selectThemeChoiceAtIndex: [[[model themeChoices] valueForKey: @"value"] indexOfObject: @"Adwaita"]];
  XCTAssertEqualObjects([[model effectiveTheme] name], @"Adwaita", @"preview shows pending theme's settings");
  XCTAssertNotNil([self rowNamed: @"adwaita.color-scheme"]);
  [model cancel];
  XCTAssertFalse([model hasChanges]);
  XCTAssertEqualObjects([[model effectiveTheme] name], @"Gumdrop");
  XCTAssertNil(GTSExternalRead(app, @"GSTheme"));
}

- (void) testDynamicDefaultShownAsAutomaticWithoutStoredToken
{
  GTSSettingRow *row;
  [model selectThemeChoiceAtIndex: [[[model themeChoices] valueForKey: @"value"] indexOfObject: @"Adwaita"]];
  row = [self rowNamed: @"adwaita.color-scheme"];
  XCTAssertTrue([[[[row choices] objectAtIndex: 0] title] hasPrefix: @"Automatic ("]);
  XCTAssertNil([[[row choices] objectAtIndex: 0] value]);
  XCTAssertEqualObjects([row stateText], @"Automatic");
  XCTAssertTrue([[[row choices] valueForKey: @"value"] containsObject: @"default"],
    @"explicit 'default' stays a separate, storable choice");
}

- (void) testUnavailableSelectedThemeStaysVisible
{
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Vanished", nil]);
  [model reload];
  XCTAssertEqualObjects([[[model themeChoices] objectAtIndex: [model selectedThemeIndex]] title],
    @"Vanished (not installed)");
  XCTAssertFalse([[model effectiveTheme] isAvailable]);
  XCTAssertTrue([[model themeNote] rangeOfString: @"not installed"].location != NSNotFound);
  XCTAssertEqual([[model rows] count], (NSUInteger)0);
}

- (void) testConflictIsReportedThenSecondApplyWins
{
  GTSSettingRow *row = [self rowNamed: @"gumdrop.menu-style"];
  NSUInteger primary = [[[row choices] valueForKey: @"value"] indexOfObject: @"primary"];
  [model selectChoiceAtIndex: primary forRow: row];
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
  XCTAssertFalse([model apply]);
  XCTAssertTrue([[model message] rangeOfString: @"GumdropMenuStyle"].location != NSNotFound);
  XCTAssertTrue([model hasChanges], @"user's choice kept");
  XCTAssertEqualObjects([[self rowNamed: @"gumdrop.menu-style"] stateText], @"Set for this application");
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"primary");
}

- (void) testGlobalTarget
{
  [model setTargetGlobal];
  XCTAssertEqualObjects([model targetTitle], @"All applications");
  XCTAssertEqualObjects([model themeStateText], @"Set for all applications");
  XCTAssertEqualObjects([[[model themeChoices] objectAtIndex: 0] title], @"GNUstep (default)");
  XCTAssertTrue([[[[[self rowNamed: @"gumdrop.menu-style"] choices] objectAtIndex: 0] title]
    hasPrefix: @"Default (In window"], @"no app Info.plist when editing global");
}

- (void) testApplyRequirementIsStrongestStaged
{
  NSMutableDictionary *p = [NSMutableDictionary dictionaryWithObjectsAndKeys: @"1", @"SchemaVersion",
    @"T", @"Theme", [NSDictionary dictionaryWithObject: @"org.example.t" forKey: @"Identifier"], @"Provider", nil];
  NSDictionary *base = [NSDictionary dictionaryWithObjectsAndKeys: @"bool", @"Type",
    [NSArray arrayWithObject: @"application"], @"Scopes",
    [NSDictionary dictionaryWithObjectsAndKeys: @"static", @"Behavior", @"NO", @"Value", nil], @"Unset", nil];
  NSMutableDictionary *a = [[base mutableCopy] autorelease], *b = [[base mutableCopy] autorelease];
  GTSThemeSettingsSchema *s;
  GTSEditSession *session;
  [a setObject: @"t.a" forKey: @"Identifier"]; [a setObject: @"TA" forKey: @"Key"]; [a setObject: @"live" forKey: @"Apply"];
  [b setObject: @"t.b" forKey: @"Identifier"]; [b setObject: @"TB" forKey: @"Key"]; [b setObject: @"newWindows" forKey: @"Apply"];
  [p setObject: [NSArray arrayWithObjects: a, b, nil] forKey: @"Settings"];
  s = [GTSThemeSettingsSchema schemaWithPropertyList: p path: @"mem" error: NULL];
  XCTAssertEqual([[s settingWithIdentifier: @"t.b"] applyPolicy], GTSApplyNewWindows);

  session = [[[GTSEditSession alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                            domain: app] autorelease];
  XCTAssertEqual([session applyRequirement], (int)GTSApplyLive);
  [session stageValue: @"YES" forSetting: [s settingWithIdentifier: @"t.a"] problem: NULL];
  XCTAssertEqual([session applyRequirement], (int)GTSApplyLive);
  [session stageValue: @"YES" forSetting: [s settingWithIdentifier: @"t.b"] problem: NULL];
  XCTAssertEqual([session applyRequirement], (int)GTSApplyNewWindows);
  [session stageThemeSelection: @"Adwaita"];
  XCTAssertEqual([session applyRequirement], (int)GTSApplyRestart);
}
@end
