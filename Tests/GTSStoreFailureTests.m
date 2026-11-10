/* Fail-closed behaviour: unreadable/corrupt/unloadable domains, wrong-domain
   baselines, invalid input, and post-commit refresh failure never produce a
   write or a silently replaced baseline. */
#import "GTSTestSupport.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSEditSession.h"
#import "GTSThemeSettingsSchema.h"
#include <sys/stat.h>

/* NSUserDefaults whose -synchronize always reports failure. */
@interface GTSFailingDefaults : NSUserDefaults
@end
@implementation GTSFailingDefaults
- (BOOL) synchronize { return NO; }
@end

@interface GTSFailingLoadStore : GTSDefaultsDomainStore
@end
@implementation GTSFailingLoadStore
- (NSUserDefaults*) newDefaultsInstance
{
  return [[GTSFailingDefaults alloc] initWithUser: NSUserName()];
}
@end

/* Snapshots succeed `okCount` times, then fail (commit reads are unaffected). */
@interface GTSFlakySnapshotStore : GTSDefaultsDomainStore
{
@public
  int okCount;
}
@end
@implementation GTSFlakySnapshotStore
- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)d error: (NSError**)e
{
  if (okCount-- > 0) return [super snapshotForDomain: d error: e];
  if (e) *e = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorUnreadableDomain userInfo: nil];
  return nil;
}
@end

static GTSSettingDescriptor *
gumdropSetting(void)
{
  return [[GTSThemeSettingsSchema schemaForThemeBundleAtPath:
    [GTSExamplesDir() stringByAppendingPathComponent: @"Gumdrop.theme"] error: NULL]
    settingWithIdentifier: @"gumdrop.menu-style"];
}

@interface GTSStoreFailureTests : XCTestCase
{
  GTSDefaultsDomainStore *store;
  NSString *app;
  NSString *file;
}
@end

@implementation GTSStoreFailureTests

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  store = [[GTSDefaultsDomainStore alloc] init];
  app = [GTSUniqueDomain(@"fail") retain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"Unrelated", @"u", nil]);
  file = [[[GTSDefaultsDomainStore defaultsRoot] stringByAppendingPathComponent:
    [app stringByAppendingPathExtension: @"plist"]] retain];
}

- (void) tearDown
{
  chmod([file fileSystemRepresentation], 0600);
  chmod([[GTSDefaultsDomainStore defaultsRoot] fileSystemRepresentation], 0700);
  [store release]; [app release]; [file release];
  store = nil; app = nil; file = nil;
}

- (void) assertCommitRefused: (GTSDefaultsDomainStore*)s code: (NSInteger)code
{
  NSError *err = nil;
  XCTAssertFalse([s commitChanges: [NSDictionary dictionaryWithObject: @"primary" forKey: @"GumdropMenuStyle"]
                         toDomain: app baseline: nil conflicts: NULL error: &err]);
  XCTAssertEqual([err code], code, @"%@", err);
}

- (void) testUnreadableDomainFileFailsClosed
{
  NSData *before = [NSData dataWithContentsOfFile: file];
  NSError *err = nil;
  XCTAssertNotNil(before);
  chmod([file fileSystemRepresentation], 0000);
  XCTAssertNil([store snapshotForDomain: app error: &err], @"must not look like an empty domain");
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnreadableDomain);
  [self assertCommitRefused: store code: GTSErrorUnreadableDomain];
  chmod([file fileSystemRepresentation], 0600);
  XCTAssertEqualObjects([NSData dataWithContentsOfFile: file], before, @"file untouched");
}

- (void) testCorruptDomainFileFailsClosed
{
  NSData *garbage = [@"{ GumdropMenuStyle = " dataUsingEncoding: NSUTF8StringEncoding];
  NSError *err = nil;
  [garbage writeToFile: file atomically: NO];
  XCTAssertNil([store snapshotForDomain: app error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnreadableDomain);
  [self assertCommitRefused: store code: GTSErrorUnreadableDomain];
  XCTAssertEqualObjects([NSData dataWithContentsOfFile: file], garbage, @"damaged file left for the user");
}

- (void) testUnreadableDefaultsDirectoryFailsClosed
{
  NSError *err = nil;
  chmod([[GTSDefaultsDomainStore defaultsRoot] fileSystemRepresentation], 0000);
  XCTAssertNil([store snapshotForDomain: app error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnreadableDomain);
  [self assertCommitRefused: store code: GTSErrorUnreadableDomain];
  chmod([[GTSDefaultsDomainStore defaultsRoot] fileSystemRepresentation], 0700);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}

- (void) testInjectedSynchronizeFailureFailsClosed
{
  GTSFailingLoadStore *bad = [[[GTSFailingLoadStore alloc] init] autorelease];
  NSError *err = nil;
  XCTAssertNil([bad snapshotForDomain: app error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnreadableDomain);
  [self assertCommitRefused: bad code: GTSErrorUnreadableDomain];
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar", @"zero writes");
  XCTAssertNil([[[GTSEditSession alloc] initWithStore: bad domain: app error: NULL] autorelease]);
}

- (void) testBaselineFromAnotherDomainIsRejected
{
  NSString *other = GTSUniqueDomain(@"other");
  GTSDomainSnapshot *lookalike;
  NSError *err = nil;
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", other, @"GumdropMenuStyle", @"menubar", nil]);
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", other, @"Unrelated", @"u", nil]);
  lookalike = [store snapshotForDomain: other error: NULL];
  XCTAssertEqualObjects([lookalike values], [[store snapshotForDomain: app error: NULL] values],
    @"precondition: same-looking values");
  XCTAssertFalse([store commitChanges: [NSDictionary dictionaryWithObject: @"primary" forKey: @"GumdropMenuStyle"]
                             toDomain: app baseline: lookalike conflicts: NULL error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidArgument);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
  XCTAssertNil([store conflictsForChanges: [NSDictionary dictionaryWithObject: @"x" forKey: @"GumdropMenuStyle"]
                                 baseline: lookalike current: [store snapshotForDomain: app error: NULL]]);
}

- (void) testInvalidInputIsAnErrorNotAWrite
{
  NSArray *badDomains = [NSArray arrayWithObjects: @"", @"a/b", @"../escape", @".hidden",
    [NSNumber numberWithInt: 3], nil];
  NSEnumerator *e = [badDomains objectEnumerator];
  id d;
  NSError *err;
  NSDictionary *badChanges[4];
  int i;

  while ((d = [e nextObject]) != nil)
    {
      err = nil;
      XCTAssertFalse([store commitChanges: [NSDictionary dictionaryWithObject: @"v" forKey: @"K"]
                                 toDomain: d baseline: nil conflicts: NULL error: &err], @"%@", d);
      XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidArgument, @"%@", d);
      err = nil;
      XCTAssertNil([store snapshotForDomain: d error: &err], @"%@", d);
    }
  XCTAssertFalse([store commitChanges: [NSDictionary dictionaryWithObject: @"v" forKey: @"K"]
                             toDomain: nil baseline: nil conflicts: NULL error: NULL]);

  badChanges[0] = [NSDictionary dictionaryWithObject: @"v" forKey: [NSNumber numberWithInt: 1]];
  badChanges[1] = [NSDictionary dictionaryWithObject: @"v" forKey: @""];
  badChanges[2] = [NSDictionary dictionaryWithObject: [[NSObject new] autorelease] forKey: @"K"];
  badChanges[3] = [NSDictionary dictionaryWithObject:
    [NSArray arrayWithObject: [[NSObject new] autorelease]] forKey: @"K"];
  for (i = 0; i < 4; i++)
    {
      err = nil;
      XCTAssertFalse([store commitChanges: badChanges[i] toDomain: app baseline: nil
                                conflicts: NULL error: &err], @"case %d", i);
      XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidArgument, @"case %d", i);
    }
  XCTAssertFalse([store commitChanges: (id)@"not a dictionary" toDomain: app baseline: nil
                            conflicts: NULL error: NULL]);
  XCTAssertNil(GTSExternalRead(app, @"K"));
  XCTAssertEqualObjects(GTSExternalRead(app, @"Unrelated"), @"u");
}

- (void) testMalformedOrMissingInfoIsNotEstablished
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [GTSTestRoot() stringByAppendingPathComponent: @"badapps"];
  NSString *a = [dir stringByAppendingPathComponent: @"NumberId.app"];
  NSString *b = [dir stringByAppendingPathComponent: @"NoInfo.app"];
  NSString *c = [dir stringByAppendingPathComponent: @"SlashId.app"];
  GTSApplicationIdentity *i;
  [fm createDirectoryAtPath: [a stringByAppendingPathComponent: @"Resources"]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: b withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: [c stringByAppendingPathComponent: @"Resources"]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [@"{ CFBundleIdentifier = <0102>; NSExecutable = (a, b); }"
    writeToFile: [a stringByAppendingPathComponent: @"Resources/Info-gnustep.plist"] atomically: YES];
  [@"{ CFBundleIdentifier = \"../../etc\"; }"
    writeToFile: [c stringByAppendingPathComponent: @"Resources/Info-gnustep.plist"] atomically: YES];

  i = [GTSDefaultsDomainStore applicationIdentityForBundleAtPath: a];
  XCTAssertFalse([i isEstablished]);
  XCTAssertEqual([i source], GTSIdentityGuessedFromPath);
  XCTAssertTrue([[i problems] count] >= 2, @"%@", [i problems]);

  i = [GTSDefaultsDomainStore applicationIdentityForBundleAtPath: b];
  XCTAssertFalse([i isEstablished]);
  XCTAssertNil([i infoDictionary]);

  i = [GTSDefaultsDomainStore applicationIdentityForBundleAtPath: c];
  XCTAssertFalse([i isEstablished], @"unsafe identifier rejected: %@", [i domain]);
}

/* --- session failure states --- */

- (void) testRebaseFailureKeepsBaselineAndStagedEdits
{
  GTSFlakySnapshotStore *flaky = [[[GTSFlakySnapshotStore alloc] init] autorelease];
  GTSEditSession *s;
  GTSDomainSnapshot *before;
  NSError *err = nil;
  flaky->okCount = 1;
  s = [[[GTSEditSession alloc] initWithStore: flaky domain: app error: NULL] autorelease];
  before = [s baseline];
  [s stageValue: @"primary" forSetting: gumdropSetting() problem: NULL];
  XCTAssertNil([s rebaseWithError: &err]);
  XCTAssertNotNil(err);
  XCTAssertTrue([s baseline] == before, @"baseline not replaced");
  XCTAssertTrue([s hasChanges], @"staged edit kept");
}

- (void) testReceiptKeepsRestartRequirementAfterStagedCleared
{
  GTSEditSession *s = [[[GTSEditSession alloc] initWithStore: store domain: app error: NULL] autorelease];
  GTSApplyReceipt *r;
  [s stageValue: @"primary" forSetting: gumdropSetting() problem: NULL];
  r = [s applyWithConflicts: NULL error: NULL];
  XCTAssertNotNil(r);
  XCTAssertEqual([r applyRequirement], (int)GTSApplyRestart);
  XCTAssertFalse([r refreshFailed]);
  XCTAssertEqual([s applyRequirement], (int)GTSApplyLive, @"nothing staged any more");
  XCTAssertEqualObjects([[r committedChanges] objectForKey: @"GumdropMenuStyle"], @"primary");
}

- (void) testRefreshFailureAfterSaveIsReportedAndBlocksDuplicateApply
{
  GTSFlakySnapshotStore *flaky = [[[GTSFlakySnapshotStore alloc] init] autorelease];
  GTSEditSession *s;
  GTSApplyReceipt *r;
  NSError *err = nil;
  flaky->okCount = 1;               /* init ok, post-commit refresh fails */
  s = [[[GTSEditSession alloc] initWithStore: flaky domain: app error: NULL] autorelease];
  [s stageValue: @"primary" forSetting: gumdropSetting() problem: NULL];
  r = [s applyWithConflicts: NULL error: NULL];
  XCTAssertNotNil(r, @"the write itself succeeded");
  XCTAssertTrue([r refreshFailed]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"primary");
  XCTAssertTrue([s needsRebase]);
  XCTAssertFalse([s hasChanges], @"saved edits are not re-staged");
  XCTAssertEqualObjects([[s baseline] objectForKey: @"GumdropMenuStyle"], @"primary",
    @"baseline = old baseline + what we wrote");
  [s stageValue: @"menubar" forSetting: gumdropSetting() problem: NULL];
  XCTAssertNil([s applyWithConflicts: NULL error: &err], @"refused until reload");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"primary");
  flaky->okCount = 1;
  XCTAssertNotNil([s rebaseWithError: NULL]);
  XCTAssertFalse([s needsRebase]);
  XCTAssertNotNil([s applyWithConflicts: NULL error: NULL]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}

- (void) testSessionInitFailsOnUnreadableDomain
{
  NSError *err = nil;
  chmod([file fileSystemRepresentation], 0000);
  XCTAssertNil([[[GTSEditSession alloc] initWithStore: store domain: app error: &err] autorelease]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnreadableDomain);
}
@end
