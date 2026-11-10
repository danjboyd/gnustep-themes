/* Structured Apply outcomes for embedding hosts: one GTSApplyOutcome per
   attempt, kinds kept distinct, stale outcomes cleared. */
#import "GTSTestSupport.h"
#import "GTSEditorModel.h"
#import "GTSEditSession.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"
#include <sys/stat.h>

/* Writes for real, then reports an unknown outcome. */
@interface GTSOutcomeWriteUnknownStore : GTSDefaultsDomainStore
@end
@implementation GTSOutcomeWriteUnknownStore
- (BOOL) commitChanges: (NSDictionary*)c toDomain: (NSString*)d baseline: (GTSDomainSnapshot*)b
             conflicts: (NSArray**)x error: (NSError**)e
{
  [super commitChanges: c toDomain: d baseline: b conflicts: x error: NULL];
  if (e) *e = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorWriteFailed userInfo: nil];
  return NO;
}
@end

/* Snapshots succeed okCount times, then fail (commit reads unaffected). */
@interface GTSOutcomeFlakyStore : GTSDefaultsDomainStore
{
@public
  int okCount;
}
@end
@implementation GTSOutcomeFlakyStore
- (GTSDomainSnapshot*) snapshotForDomain: (NSString*)d error: (NSError**)e
{
  if (okCount-- > 0) return [super snapshotForDomain: d error: e];
  if (e) *e = [NSError errorWithDomain: GTSErrorDomain code: GTSErrorUnreadableDomain userInfo: nil];
  return nil;
}
@end

@interface GTSApplyOutcomeTests : XCTestCase
{
  NSString *app;
}
@end

@implementation GTSApplyOutcomeTests

- (GTSEditorModel*) modelWithStore: (GTSDefaultsDomainStore*)store
{
  GTSThemeCatalog *c = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: GTSExamplesDir() origin: GTSOriginSystem]]] autorelease];
  GTSEditorModel *m = [[[GTSEditorModel alloc] initWithStore: store catalog: c] autorelease];
  [m setTargetApplicationDomain: app displayName: @"App" info: nil];
  return m;
}

- (GTSSettingRow*) menuRow: (GTSEditorModel*)m
{
  return [[m rows] lastObject];   /* Gumdrop has exactly one setting */
}

- (void) choosePrimary: (GTSEditorModel*)m
{
  GTSSettingRow *row = [self menuRow: m];
  XCTAssertTrue([m selectChoiceAtIndex: [[[row choices] valueForKey: @"value"] indexOfObject: @"primary"]
                                forRow: row]);
}

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  app = [GTSUniqueDomain(@"outcome") retain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Gumdrop", nil]);
}

- (void) tearDown
{
  [app release];
}

- (void) testSavedOutcomeCarriesReceipt
{
  GTSEditorModel *m = [self modelWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]];
  GTSApplyOutcome *o;
  XCTAssertNil([m lastApplyOutcome]);
  [self choosePrimary: m];
  XCTAssertTrue([m apply]);
  o = [m lastApplyOutcome];
  XCTAssertEqual([o kind], GTSApplyOutcomeSaved);
  XCTAssertTrue([o didWrite]);
  XCTAssertFalse([o needsReload]);
  XCTAssertNil([o error]);
  XCTAssertEqual([[o receipt] applyRequirement], (int)GTSApplyRestart);
  XCTAssertEqualObjects([[[o receipt] committedChanges] objectForKey: @"GumdropMenuStyle"], @"primary");
}

- (void) testNothingToSave
{
  GTSEditorModel *m = [self modelWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]];
  [m apply];
  XCTAssertEqual([[m lastApplyOutcome] kind], GTSApplyOutcomeNothingToSave);
  XCTAssertFalse([[m lastApplyOutcome] didWrite]);
}

- (void) testWriteUnknownIsDistinctAndGatesUntilReload
{
  GTSEditorModel *m = [self modelWithStore: [[[GTSOutcomeWriteUnknownStore alloc] init] autorelease]];
  GTSApplyOutcome *o;
  [self choosePrimary: m];
  XCTAssertFalse([m apply]);
  o = [m lastApplyOutcome];
  XCTAssertEqual([o kind], GTSApplyOutcomeWriteUnknown);
  XCTAssertTrue([o isOutcomeUnknown]);
  XCTAssertFalse([o didWrite], @"not claimed as written");
  XCTAssertNil([o receipt]);
  XCTAssertTrue([o needsReload]);
  XCTAssertEqual([[o error] code], (NSInteger)GTSErrorWriteFailed);
  /* A second Apply is refused (no blind re-apply). */
  XCTAssertFalse([m apply]);
  XCTAssertEqual([[m lastApplyOutcome] kind], GTSApplyOutcomeRefused);
  XCTAssertEqual([[[m lastApplyOutcome] error] code], (NSInteger)GTSErrorNeedsReload);
  /* Successful reload clears the stale outcome. */
  XCTAssertTrue([m reload]);
  XCTAssertNil([m lastApplyOutcome]);
}

- (void) testSavedRefreshFailedIsDistinct
{
  GTSOutcomeFlakyStore *s = [[[GTSOutcomeFlakyStore alloc] init] autorelease];
  GTSEditorModel *m;
  GTSApplyOutcome *o;
  s->okCount = 3;   /* model init (global session), app target: global baseline + session; the refresh fails */
  m = [self modelWithStore: s];
  [self choosePrimary: m];
  XCTAssertTrue([m apply], @"the write itself succeeded");
  o = [m lastApplyOutcome];
  XCTAssertEqual([o kind], GTSApplyOutcomeSavedRefreshFailed);
  XCTAssertTrue([o didWrite]);
  XCTAssertTrue([o needsReload]);
  XCTAssertTrue([[o receipt] refreshFailed]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"primary");
  /* A failed reload keeps the outcome (it still describes the state). */
  XCTAssertFalse([m reload]);
  XCTAssertEqual([[m lastApplyOutcome] kind], GTSApplyOutcomeSavedRefreshFailed);
}

- (void) testConflictOutcomeListsKeys
{
  GTSEditorModel *m = [self modelWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]];
  [self choosePrimary: m];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
  XCTAssertFalse([m apply]);
  XCTAssertEqual([[m lastApplyOutcome] kind], GTSApplyOutcomeConflict);
  XCTAssertEqualObjects([[m lastApplyOutcome] conflictKeys], [NSArray arrayWithObject: @"GumdropMenuStyle"]);
  XCTAssertFalse([[m lastApplyOutcome] didWrite]);
}

- (void) testRefusedWhenTargetCannotBeChanged
{
  NSString *locked = GTSUniqueDomain(@"outlocked");
  NSString *file;
  GTSEditorModel *m;
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", locked, @"GSTheme", @"Gumdrop", nil]);
  file = [[GTSDefaultsDomainStore defaultsRoot] stringByAppendingPathComponent:
    [locked stringByAppendingPathExtension: @"plist"]];
  chmod([file fileSystemRepresentation], 0000);
  m = [self modelWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]];
  [m setTargetApplicationDomain: locked displayName: @"L" info: nil];
  chmod([file fileSystemRepresentation], 0600);
  XCTAssertFalse([m apply]);
  XCTAssertEqual([[m lastApplyOutcome] kind], GTSApplyOutcomeRefused);
}

- (void) testStaleOutcomeClearedByEditCancelAndTargetSwitch
{
  GTSEditorModel *m = [self modelWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]];
  [self choosePrimary: m];
  [m apply];
  XCTAssertNotNil([m lastApplyOutcome]);
  [m resetRow: [self menuRow: m]];                       /* new edit */
  XCTAssertNil([m lastApplyOutcome], @"a new edit makes the outcome stale");

  [m apply];
  XCTAssertNotNil([m lastApplyOutcome]);
  [m cancel];
  XCTAssertNil([m lastApplyOutcome]);

  [m apply];
  XCTAssertNotNil([m lastApplyOutcome]);
  [m setTargetGlobal];
  XCTAssertNil([m lastApplyOutcome], @"target switch");

  [m apply];
  XCTAssertNotNil([m lastApplyOutcome]);
  XCTAssertTrue([m reload]);
  XCTAssertNil([m lastApplyOutcome], @"successful reload");
}
@end
