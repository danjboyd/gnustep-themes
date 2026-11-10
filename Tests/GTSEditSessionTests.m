#import "GTSTestSupport.h"
#import "GTSEditSession.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"

static GTSSettingDescriptor *
gumdrop(void)
{
  NSString *p = [GTSExamplesDir() stringByAppendingPathComponent: @"Gumdrop.theme"];
  return [[GTSThemeSettingsSchema schemaForThemeBundleAtPath: p error: NULL]
    settingWithIdentifier: @"gumdrop.menu-style"];
}

@interface GTSEditSessionTests : XCTestCase
{
  GTSDefaultsDomainStore *store;
  NSString *app;
}
@end

@implementation GTSEditSessionTests

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  store = [[GTSDefaultsDomainStore alloc] init];
  app = [GTSUniqueDomain(@"session") retain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Gumdrop", nil]);
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"Unrelated", @"u", nil]);
}

- (void) tearDown
{
  [store release]; store = nil;
  [app release]; app = nil;
}

- (void) testCancelWritesNothing
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  XCTAssertTrue([s stageValue: @"MENUBAR" forSetting: gumdrop() problem: NULL]);
  XCTAssertTrue([s hasChanges]);
  XCTAssertTrue([s needsRestart]);
  XCTAssertEqualObjects([[s pendingSnapshot] objectForKey: @"GumdropMenuStyle"], @"menubar");
  XCTAssertNil(GTSExternalRead(app, @"GumdropMenuStyle"), @"staging must not touch disk");
  [s discardChanges];
  XCTAssertFalse([s hasChanges]);
  XCTAssertNotNil([s applyWithConflicts: NULL error: NULL]);
  XCTAssertNil(GTSExternalRead(app, @"GumdropMenuStyle"));
}

- (void) testApplyWritesCanonicalValueAndRebaselines
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  XCTAssertTrue([s stageValue: @"MenuBar" forSetting: gumdrop() problem: NULL]);
  XCTAssertNotNil([s applyWithConflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
  XCTAssertEqualObjects(GTSExternalRead(app, @"Unrelated"), @"u");
  XCTAssertFalse([s hasChanges]);
  XCTAssertEqualObjects([[s baseline] objectForKey: @"GumdropMenuStyle"], @"menubar");

  [s stageResetForSetting: gumdrop()];
  XCTAssertNotNil([s applyWithConflicts: NULL error: NULL]);
  XCTAssertNil(GTSExternalRead(app, @"GumdropMenuStyle"), @"reset removes the key");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Gumdrop");
}

- (void) testInvalidValueRejected
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  NSString *problem = nil;
  XCTAssertFalse([s stageValue: @"sideways" forSetting: gumdrop() problem: &problem]);
  XCTAssertNotNil(problem);
  XCTAssertFalse([s hasChanges]);
}

- (void) testStagingBaselineValueUnstages
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  [s stageThemeSelection: @"Adwaita"];
  XCTAssertTrue([s hasChanges]);
  [s stageThemeSelection: @"Gumdrop"];
  XCTAssertFalse([s hasChanges]);
  [s stageResetForSetting: gumdrop()];   /* key absent already */
  XCTAssertFalse([s hasChanges]);
}

- (void) testConflictKeepsStagedChangesAndRebaseResolves
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  NSArray *conflicts = nil, *changed;
  [s stageThemeSelection: @"Adwaita"];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"WinUITheme", nil]);
  XCTAssertNil([s applyWithConflicts: &conflicts error: NULL]);
  XCTAssertEqualObjects([[conflicts lastObject] currentValue], @"WinUITheme");
  XCTAssertTrue([s hasChanges]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"WinUITheme");

  changed = [s rebaseWithError: NULL];
  XCTAssertEqualObjects(changed, [NSArray arrayWithObject: @"GSTheme"]);
  XCTAssertTrue([s hasChanges], @"user's choice survives rebase");
  XCTAssertNotNil([s applyWithConflicts: &conflicts error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Adwaita");
}

- (void) testThemeSwitchLeavesInactiveThemeValues
{
  GTSEditSession *s;
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
  s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  [s stageThemeSelection: nil];   /* inherit theme from global */
  XCTAssertNotNil([s applyWithConflicts: NULL error: NULL]);
  XCTAssertNil(GTSExternalRead(app, @"GSTheme"));
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}
@end
