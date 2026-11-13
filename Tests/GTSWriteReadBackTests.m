/* The Windows write gate (a pure function, testable on any platform) and
   the read-back check that every commit makes: a backend that reports a
   successful -synchronize without storing the change must not count as a
   successful write. */
#import "GTSTestSupport.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"

/* NSUserDefaults that silently drops -setPersistentDomain:forName: but
   still reports success from -synchronize (a silent no-op write). */
@interface GTSDroppingDefaults : NSUserDefaults
@end
@implementation GTSDroppingDefaults
- (void) setPersistentDomain: (NSDictionary*)d forName: (NSString*)n { }
@end

@interface GTSDroppingStore : GTSDefaultsDomainStore
@end
@implementation GTSDroppingStore
- (NSUserDefaults*) newDefaultsInstance
{
  return [[GTSDroppingDefaults alloc] initWithUser: NSUserName()];
}
@end

@interface GTSWriteReadBackTests : XCTestCase
{
  NSString *app;
}
@end

@implementation GTSWriteReadBackTests

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  app = [GTSUniqueDomain(@"readback") retain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Gumdrop", nil]);
}

- (void) tearDown
{
  [app release];
}

- (void) testWindowsGateTruthTable
{
  Class S = [GTSDefaultsDomainStore class];
  NSDictionary *on = [NSDictionary dictionaryWithObject: @"1" forKey: @"GTS_ENABLE_WINDOWS_WRITES"];
  NSDictionary *yes = [NSDictionary dictionaryWithObject: @"YES" forKey: @"GTS_ENABLE_WINDOWS_WRITES"];
  NSDictionary *zero = [NSDictionary dictionaryWithObject: @"0" forKey: @"GTS_ENABLE_WINDOWS_WRITES"];
  NSDictionary *none = [NSDictionary dictionary];
  NSString *root = @"/c/Users/agent/GNUstep/Defaults";

  XCTAssertTrue([S windowsWritesAllowedForRoot: root environment: on]);
  XCTAssertFalse([S windowsWritesAllowedForRoot: root environment: none], @"opt-in required");
  XCTAssertFalse([S windowsWritesAllowedForRoot: root environment: zero]);
  XCTAssertFalse([S windowsWritesAllowedForRoot: root environment: yes], @"only exactly 1");
  XCTAssertFalse([S windowsWritesAllowedForRoot: @":REGISTRY:" environment: on], @"registry never");
  XCTAssertFalse([S windowsWritesAllowedForRoot: @"GNUstep/Defaults" environment: on], @"relative root");
  XCTAssertFalse([S windowsWritesAllowedForRoot: nil environment: on]);
  XCTAssertFalse([S windowsWritesAllowedForRoot: (id)[NSNumber numberWithInt: 1] environment: on]);
}

- (void) testNormalCommitAndRemovalReadBack
{
  GTSDefaultsDomainStore *s = [[[GTSDefaultsDomainStore alloc] init] autorelease];
  NSError *err = nil;
  NSDictionary *c = [NSDictionary dictionaryWithObjectsAndKeys:
    @"Compact", @"GumdropSize", [NSNumber numberWithBool: NO], @"GSBackWindowShadows",
    [NSNumber numberWithDouble: 12.5], @"NSFontSize", nil];
  XCTAssertTrue([s commitChanges: c toDomain: app baseline: nil conflicts: NULL error: &err], @"%@", err);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropSize"), @"Compact");
  XCTAssertTrue([s removeKey: @"GumdropSize" fromDomain: app baseline: nil conflicts: NULL error: &err], @"%@", err);
  XCTAssertNil([[s snapshotForDomain: app error: NULL] objectForKey: @"GumdropSize"]);
}

- (void) testSilentNoOpWriteIsReportedAsFailed
{
  GTSDroppingStore *s = [[[GTSDroppingStore alloc] init] autorelease];
  NSError *err = nil;
  BOOL ok = [s commitChanges: [NSDictionary dictionaryWithObject: @"Compact" forKey: @"GumdropSize"]
                    toDomain: app baseline: nil conflicts: NULL error: &err];
  XCTAssertFalse(ok);
  XCTAssertEqual([err code], (NSInteger)GTSErrorWriteFailed);
  XCTAssertTrue([[err localizedDescription] rangeOfString: @"did not read back"].length > 0, @"%@", err);
  XCTAssertNil([[[[[GTSDefaultsDomainStore alloc] init] autorelease]
    snapshotForDomain: app error: NULL] objectForKey: @"GumdropSize"], @"nothing was stored");
}

- (void) testSilentNoOpRemovalIsReportedAsFailed
{
  GTSDroppingStore *s = [[[GTSDroppingStore alloc] init] autorelease];
  NSError *err = nil;
  XCTAssertFalse([s removeKey: @"GSTheme" fromDomain: app baseline: nil conflicts: NULL error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorWriteFailed);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Gumdrop", @"key still there");
}

@end
