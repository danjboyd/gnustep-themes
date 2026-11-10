/* Defaults-domain proof. Every external read/write goes through the system
   `defaults` tool in a separate process, so these tests exercise real
   cross-process behaviour of GNUstep defaults, not just this process' cache. */
#import "GTSTestSupport.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeSettingsSchema.h"

@interface GTSDefaultsDomainStoreTests : XCTestCase
{
  GTSDefaultsDomainStore *store;
  NSString *app;
  NSArray *hookArgs;   /* `defaults` arguments run by the pre-write hook */
}
@end

@implementation GTSDefaultsDomainStoreTests

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  store = [[GTSDefaultsDomainStore alloc] initWithHostDefaults:
    [NSUserDefaults standardUserDefaults]];
  app = [GTSUniqueDomain(@"app") retain];
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Adwaita", nil]);
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"AdwaitaColorScheme", @"dark", nil]);
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"Unrelated", @"keep-me", nil]);
  /* A value for a theme that is not selected: must survive every edit. */
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
}

- (void) tearDown
{
  [store release]; store = nil;
  [app release]; app = nil;
  [hookArgs release]; hookArgs = nil;
}

- (void) runHook: (NSString*)domain
{
  GTSRunDefaults(hookArgs);
}

- (void) testDefaultsAreIsolated
{
  XCTAssertTrue([[GTSDefaultsDomainStore defaultsRoot] hasPrefix: GTSTestRoot()]);
}

- (void) testExactAppDomainReadExcludesGlobalAndOwnDomain
{
  NSString *g = GTSUniqueDomain(@"globalkey");
  GTSDomainSnapshot *s;
  GTSRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", g, @"global-only", nil]);

  s = [store snapshotForDomain: app];
  XCTAssertEqualObjects([s objectForKey: @"AdwaitaColorScheme"], @"dark");
  XCTAssertEqualObjects([s objectForKey: @"Unrelated"], @"keep-me");
  XCTAssertNil([s objectForKey: g], @"app snapshot must not include global keys");
  XCTAssertEqual([[s values] count], (NSUInteger)4);

  s = [store snapshotForDomain: NSGlobalDomain];
  XCTAssertEqualObjects([s objectForKey: g], @"global-only");
  XCTAssertNil([s objectForKey: @"AdwaitaColorScheme"]);

  GTSRunDefaults([NSArray arrayWithObjects: @"delete", @"NSGlobalDomain", g, nil]);
}

- (void) testSnapshotSeesLaterExternalWrite
{
  GTSDomainSnapshot *s = [store snapshotForDomain: app];
  XCTAssertEqualObjects([s objectForKey: @"AdwaitaColorScheme"], @"dark");
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"AdwaitaColorScheme", @"light", nil]);
  s = [store snapshotForDomain: app];
  XCTAssertEqualObjects([s objectForKey: @"AdwaitaColorScheme"], @"light",
    @"snapshot must re-read a foreign domain changed by another process");
}

- (void) testMissingDomainIsEmptyNotNil
{
  GTSDomainSnapshot *s = [store snapshotForDomain: GTSUniqueDomain(@"missing")];
  XCTAssertNotNil([s values]);
  XCTAssertEqual([[s values] count], (NSUInteger)0);
}

- (void) testResetRemovesExactlyOneKey
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  NSArray *conflicts = nil;
  NSError *err = nil;
  BOOL ok = [store removeKey: @"AdwaitaColorScheme" fromDomain: app baseline: b
                   conflicts: &conflicts error: &err];
  XCTAssertTrue(ok, @"%@", err);
  XCTAssertNil(GTSExternalRead(app, @"AdwaitaColorScheme"), @"key must be absent, not a fallback value");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Adwaita");
  XCTAssertEqualObjects(GTSExternalRead(app, @"Unrelated"), @"keep-me");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}

- (void) testSetPreservesUnrelatedAndInactiveThemeKeys
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  BOOL ok = [store commitChanges: [NSDictionary dictionaryWithObject: @"light" forKey: @"AdwaitaColorScheme"]
                        toDomain: app baseline: b conflicts: NULL error: NULL];
  XCTAssertTrue(ok);
  XCTAssertEqualObjects(GTSExternalRead(app, @"AdwaitaColorScheme"), @"light");
  XCTAssertEqualObjects(GTSExternalRead(app, @"Unrelated"), @"keep-me");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}

- (void) testGlobalEditPreservesOtherGlobalKeys
{
  NSString *k = GTSUniqueDomain(@"gk"), *other = GTSUniqueDomain(@"go");
  GTSDomainSnapshot *b;
  GTSRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", other, @"x", nil]);
  b = [store snapshotForDomain: NSGlobalDomain];
  XCTAssertTrue([store commitChanges: [NSDictionary dictionaryWithObject: @"v" forKey: k]
                            toDomain: NSGlobalDomain baseline: b conflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", k), @"v");
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", other), @"x");
  b = [store snapshotForDomain: NSGlobalDomain];
  [store commitChanges: [NSDictionary dictionaryWithObjectsAndKeys:
      GTSRemoveValue, k, GTSRemoveValue, other, nil]
    toDomain: NSGlobalDomain baseline: b conflicts: NULL error: NULL];
  XCTAssertNil(GTSExternalRead(@"NSGlobalDomain", k));
}

- (void) testConflictOnSameKeyRefusesWrite
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  NSArray *conflicts = nil;
  NSError *err = nil;
  BOOL ok;
  GTSConflict *c;

  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"AdwaitaColorScheme", @"light", nil]);
  ok = [store commitChanges: [NSDictionary dictionaryWithObjectsAndKeys:
         @"default", @"AdwaitaColorScheme", @"WinUITheme", @"GSTheme", nil]
       toDomain: app baseline: b conflicts: &conflicts error: &err];
  XCTAssertFalse(ok);
  XCTAssertEqual([err code], (NSInteger)GTSErrorConflict);
  XCTAssertEqual([conflicts count], (NSUInteger)1);
  c = [conflicts lastObject];
  XCTAssertEqualObjects([c key], @"AdwaitaColorScheme");
  XCTAssertEqualObjects([c baselineValue], @"dark");
  XCTAssertEqualObjects([c currentValue], @"light");
  XCTAssertEqualObjects([c proposedValue], @"default");
  /* All-or-nothing: the non-conflicting GSTheme change was not written either. */
  XCTAssertEqualObjects(GTSExternalRead(app, @"AdwaitaColorScheme"), @"light");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Adwaita");
}

- (void) testConflictWhenKeyRemovedElsewhere
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  NSArray *conflicts = nil;
  GTSRunDefaults([NSArray arrayWithObjects: @"delete", app, @"AdwaitaColorScheme", nil]);
  XCTAssertFalse([store commitChanges: [NSDictionary dictionaryWithObject: @"light" forKey: @"AdwaitaColorScheme"]
                             toDomain: app baseline: b conflicts: &conflicts error: NULL]);
  XCTAssertNil([[conflicts lastObject] currentValue]);
}

- (void) testExternalUnrelatedWriteAfterBaselineIsNotAConflictAndSurvives
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  GTSRunDefaults([NSArray arrayWithObjects: @"write", app, @"OtherApp", @"external", nil]);
  XCTAssertTrue([store removeKey: @"AdwaitaColorScheme" fromDomain: app baseline: b
                       conflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"OtherApp"), @"external");
  XCTAssertNil(GTSExternalRead(app, @"AdwaitaColorScheme"));
}

/* Interleaving: another process writes between our check and our write. */

- (void) testInterleavedUnrelatedWriteSurvives
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  hookArgs = [[NSArray alloc] initWithObjects: @"write", app, @"Interleaved", @"yes", nil];
  [store setPreWriteHookTarget: self selector: @selector(runHook:)];
  XCTAssertTrue([store commitChanges: [NSDictionary dictionaryWithObject: @"light" forKey: @"AdwaitaColorScheme"]
                            toDomain: app baseline: b conflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"Interleaved"), @"yes");
  XCTAssertEqualObjects(GTSExternalRead(app, @"AdwaitaColorScheme"), @"light");
}

- (void) testInterleavedRemovalIsNotResurrected
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  hookArgs = [[NSArray alloc] initWithObjects: @"delete", app, @"Unrelated", nil];
  [store setPreWriteHookTarget: self selector: @selector(runHook:)];
  XCTAssertTrue([store commitChanges: [NSDictionary dictionaryWithObject: @"light" forKey: @"AdwaitaColorScheme"]
                            toDomain: app baseline: b conflicts: NULL error: NULL]);
  XCTAssertNil(GTSExternalRead(app, @"Unrelated"),
    @"a key removed by another process inside the window must stay removed");
}

/* Documents the residual race: same key written by another process inside
   the check->write window is overwritten. Optimistic detection, not CAS. */
- (void) testResidualRaceSameKeyLastWriterWins
{
  GTSDomainSnapshot *b = [store snapshotForDomain: app];
  hookArgs = [[NSArray alloc] initWithObjects: @"write", app, @"AdwaitaColorScheme", @"external", nil];
  [store setPreWriteHookTarget: self selector: @selector(runHook:)];
  XCTAssertTrue([store commitChanges: [NSDictionary dictionaryWithObject: @"light" forKey: @"AdwaitaColorScheme"]
                            toDomain: app baseline: b conflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"AdwaitaColorScheme"), @"light",
    @"if this changes, base gained stronger semantics; update docs");
}

- (void) testApplicationDomainName
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [GTSTestRoot() stringByAppendingPathComponent: @"apps"];
  NSString *a = [dir stringByAppendingPathComponent: @"WithId.app"];
  NSString *b = [dir stringByAppendingPathComponent: @"WithExe.app"];
  NSString *c = [dir stringByAppendingPathComponent: @"Bare.app"];
  [fm createDirectoryAtPath: [a stringByAppendingPathComponent: @"Resources"]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: [b stringByAppendingPathComponent: @"Resources"]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: c withIntermediateDirectories: YES attributes: nil error: NULL];
  [[NSDictionary dictionaryWithObjectsAndKeys: @"org.example.WithId", @"CFBundleIdentifier",
     @"withid", @"NSExecutable", nil]
    writeToFile: [a stringByAppendingPathComponent: @"Resources/Info-gnustep.plist"] atomically: YES];
  [[NSDictionary dictionaryWithObject: @"withexe" forKey: @"NSExecutable"]
    writeToFile: [b stringByAppendingPathComponent: @"Resources/Info-gnustep.plist"] atomically: YES];
  XCTAssertEqualObjects([GTSDefaultsDomainStore applicationDomainForBundleAtPath: a], @"org.example.WithId");
  XCTAssertEqualObjects([GTSDefaultsDomainStore applicationDomainForBundleAtPath: b], @"withexe");
  XCTAssertEqualObjects([GTSDefaultsDomainStore applicationDomainForBundleAtPath: c], @"Bare");
}
@end
