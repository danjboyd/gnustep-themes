/* A defaults backend that can be read but not written (Windows today),
   simulated on Linux with the store's test switch: values are shown,
   nothing can be staged or written, and the refusal says why. */
#import "GTSTestSupport.h"
#import "GTSEditorModel.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"

@interface GTSReadOnlyBackendTests : XCTestCase
{
  NSString *app;
}
@end

@implementation GTSReadOnlyBackendTests

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  app = [GTSUniqueDomain(@"robackend") retain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GSTheme", @"Gumdrop", nil]);
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", app, @"GumdropMenuStyle", @"menubar", nil]);
  [GTSDefaultsDomainStore setBackendWritableOverrideForTesting: 0];
}

- (void) tearDown
{
  [GTSDefaultsDomainStore setBackendWritableOverrideForTesting: -1];
  [app release];
}

- (GTSEditorModel*) model
{
  GTSThemeCatalog *c = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: GTSExamplesDir() origin: GTSOriginSystem]]] autorelease];
  GTSEditorModel *m = [[[GTSEditorModel alloc] initWithStore:
    [[[GTSDefaultsDomainStore alloc] init] autorelease] catalog: c] autorelease];
  XCTAssertTrue([m setTargetApplicationDomain: app displayName: @"App" info: nil]);
  return m;
}

- (void) testStoreReadsButRefusesWrites
{
  GTSDefaultsDomainStore *store = [[[GTSDefaultsDomainStore alloc] init] autorelease];
  NSError *err = nil;
  GTSDomainSnapshot *snap = [store snapshotForDomain: app error: &err];
  NSArray *conflicts = nil;

  XCTAssertTrue([GTSDefaultsDomainStore isBackendReadable]);
  XCTAssertFalse([GTSDefaultsDomainStore isBackendWritable]);
  XCTAssertFalse([GTSDefaultsDomainStore isBackendSupported], @"kept equal to writable");
  XCTAssertNotNil(snap, @"%@", err);
  XCTAssertEqualObjects([snap objectForKey: @"GumdropMenuStyle"], @"menubar");

  err = nil;
  XCTAssertFalse([store commitChanges: [NSDictionary dictionaryWithObject: @"primary" forKey: @"GumdropMenuStyle"]
                             toDomain: app baseline: snap conflicts: &conflicts error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnsupportedBackend);
  XCTAssertTrue([[err localizedDescription] rangeOfString: @"not supported for editing yet"].location != NSNotFound,
    @"%@", [err localizedDescription]);
  err = nil;
  XCTAssertFalse([store removeKey: @"GumdropMenuStyle" fromDomain: app baseline: snap conflicts: &conflicts error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnsupportedBackend);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar", @"nothing written");
}

- (void) testModelShowsValuesReadOnly
{
  GTSEditorModel *m = [self model];
  NSEnumerator *e;
  GTSSettingRow *row, *menu = nil;

  XCTAssertFalse([m storeIsWritable]);
  XCTAssertFalse([m isEditable]);
  XCTAssertTrue([[m rows] count] > 0, @"values are shown");
  e = [[m rows] objectEnumerator];
  while ((row = [e nextObject]) != nil)
    {
      XCTAssertTrue([row isReadOnly], @"%@", [[row setting] identifier]);
      XCTAssertFalse([row canReset]);
      if ([[[row setting] identifier] isEqual: @"gumdrop.menu-style"]) menu = row;
    }
  XCTAssertNotNil(menu);
  XCTAssertEqualObjects([[[menu choices] objectAtIndex: [menu selectedIndex]] value], @"menubar",
    @"the stored value is read and shown");
  XCTAssertTrue([[m themeNote] rangeOfString: @"can be read on this system but not changed"].location != NSNotFound,
    @"%@", [m themeNote]);

  XCTAssertFalse([m selectChoiceAtIndex: 0 forRow: menu]);
  [m selectThemeChoiceAtIndex: 0];
  XCTAssertEqualObjects([m message], @"this defaults backend is not supported for editing yet");
  XCTAssertFalse([m hasChanges]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GSTheme"), @"Gumdrop");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GumdropMenuStyle"), @"menubar");
}

- (void) testDiagnosticsNameRootAndState
{
  NSString *d = [[self model] diagnostics];
  NSString *root = [GTSDefaultsDomainStore defaultsRoot];
  XCTAssertTrue([root isAbsolutePath], @"%@", root);
  XCTAssertTrue(GTSPathIsInside(root, GTSTestRoot()), @"isolated root %@", root);
  XCTAssertTrue([d rangeOfString: root].location != NSNotFound, @"%@", d);
  XCTAssertTrue([d rangeOfString: @"readable"].location != NSNotFound, @"%@", d);
  XCTAssertTrue([d rangeOfString: @"NOT writable"].location != NSNotFound, @"%@", d);
  [GTSDefaultsDomainStore setBackendWritableOverrideForTesting: -1];
  XCTAssertTrue([[[self model] diagnostics] rangeOfString: @", writable"].location != NSNotFound);
}

@end
