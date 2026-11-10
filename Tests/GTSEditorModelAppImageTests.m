/* Editor model with an AppImage target (sidecar): always read-only, values
   shown only when the sidecar is bound and names the domain, seeded GSTheme
   described per launch policy, never a misleading reset/inherit choice. */
#import "GTSTestSupport.h"
#import "GTSEditorModel.h"
#import "GTSAppImageSidecar.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSSHA256.h"

@interface GTSEditorModelAppImageTests : XCTestCase
{
  NSString *dir, *appimage, *sidecarPath, *domain;
  GTSEditorModel *model;
}
@end

@implementation GTSEditorModelAppImageTests

- (void) writeSidecarWithSeedDomain: (NSString*)seedDomain
{
  NSString *p = [GTSExamplesDir() stringByAppendingPathComponent: @"Gumdrop.theme/Resources/ThemeSettings.plist"];
  NSDictionary *gumdrop = [NSDictionary dictionaryWithObjectsAndKeys: @"Gumdrop", @"name", @"ok", @"infoStatus",
    [NSDictionary dictionaryWithObjectsAndKeys: @"inline", @"status",
      [[NSString stringWithContentsOfFile: p] propertyList], @"inline", nil], @"settings", nil];
  NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"schema",
    [NSDictionary dictionaryWithObjectsAndKeys: [appimage lastPathComponent], @"fileName",
      GTSSHA256HexOfFile(appimage), @"sha256", nil], @"appimage",
    [NSDictionary dictionaryWithObjectsAndKeys: domain, @"runtimeDomainHint",
      @"bundleIdentifier", @"runtimeDomainHintSource", nil], @"app",
    [NSDictionary dictionaryWithObjectsAndKeys: seedDomain, @"seedDomain",
      [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: @"GSTheme", @"key",
        @"Gumdrop", @"value", @"each-launch-if-absent", @"policy", nil]], @"seeds", nil], @"defaults",
    [NSArray arrayWithObject: gumdrop], @"themes", nil];
  [[NSJSONSerialization dataWithJSONObject: d options: 0 error: NULL] writeToFile: sidecarPath atomically: YES];
}

- (GTSAppImageSidecar*) sidecar
{
  return [GTSAppImageSidecar sidecarWithContentsOfFile: sidecarPath error: NULL];
}

- (void) setUp
{
  GTSThemeCatalog *catalog;
  GTSRequireIsolatedDefaults();
  dir = [[GTSTestRoot() stringByAppendingPathComponent: GTSUniqueDomain(@"appimgmodel")] retain];
  [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                                             attributes: nil error: NULL];
  appimage = [[dir stringByAppendingPathComponent: @"Notes-1.0-x86_64.AppImage"] retain];
  sidecarPath = [[dir stringByAppendingPathComponent: @"Notes-1.0-x86_64.themes.json"] retain];
  domain = [GTSUniqueDomain(@"appimgdom") retain];
  [[@"not really an appimage" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: appimage atomically: YES];
  catalog = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray array]] autorelease];
  model = [[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                        catalog: catalog];
}

- (void) tearDown
{
  [dir release]; [appimage release]; [sidecarPath release]; [domain release]; [model release];
}

- (void) assertNothingEditable
{
  NSEnumerator *e = [[model rows] objectEnumerator];
  GTSSettingRow *r;
  XCTAssertFalse([model isEditable]);
  XCTAssertFalse([model hasChanges]);
  XCTAssertFalse([model apply]);
  while ((r = [e nextObject]) != nil)
    {
      XCTAssertTrue([r isReadOnly]);
      XCTAssertFalse([r canReset]);
      XCTAssertFalse([model selectChoiceAtIndex: 1 forRow: r]);
    }
  XCTAssertEqual([[model themeChoices] count], (NSUInteger)1, @"no inherit/reset choice for the theme");
  XCTAssertFalse([[[[model themeChoices] lastObject] title] hasPrefix: @"Same as all applications"]);
}

- (void) testBoundTargetShowsValuesReadOnlyAndSeedState
{
  [self writeSidecarWithSeedDomain: domain];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", domain, @"GumdropMenuStyle", @"menubar", nil]);
  XCTAssertTrue([model setTargetAppImageSidecar: [self sidecar] appImage: nil]);
  XCTAssertTrue([model targetIsAppImage]);
  XCTAssertTrue([[model targetTitle] hasSuffix: @"(AppImage, read-only)"]);
  /* The running AppImage's theme is never presented as known; the package's
     prediction and this editor's local snapshot are separate lines. */
  XCTAssertEqualObjects([[[model themeChoices] lastObject] title], @"Not known for the running AppImage");
  XCTAssertTrue([[model themeStateText] rangeOfString: @"Package default: Gumdrop"].location != NSNotFound, @"%@", [model themeStateText]);
  XCTAssertTrue([[model themeStateText] rangeOfString: @"This editor's settings store: theme not set"].location != NSNotFound);
  XCTAssertTrue([[model themeStateText] rangeOfString: @"cannot change settings"].location != NSNotFound);
  XCTAssertTrue([[model themeNote] rangeOfString: @"not confirmed as the AppImage's current settings"].location != NSNotFound);
  XCTAssertTrue([[model themeNote] rangeOfString: @"matches this AppImage"].location != NSNotFound);
  XCTAssertTrue([[model themeNote] rangeOfString: @"is not known"].location != NSNotFound, @"compatibility unknown");
  XCTAssertEqual([[model rows] count], (NSUInteger)1);
  XCTAssertEqualObjects([[[model rows] lastObject] stateText], @"In this editor's store: set for this application");
  [self assertNothingEditable];
  XCTAssertEqualObjects(GTSExternalRead(domain, @"GumdropMenuStyle"), @"menubar", @"nothing written");

  /* A GSTheme in this editor's store is reported as local only. */
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", domain, @"GSTheme", @"Gumdrop", nil]);
  [model setTargetAppImageSidecar: [self sidecar] appImage: nil];
  XCTAssertTrue([[model themeStateText] rangeOfString: @"This editor's settings store: theme Gumdrop"].location != NSNotFound);
  XCTAssertEqualObjects([[[model themeChoices] lastObject] title], @"Not known for the running AppImage",
    @"a local value is still not the AppImage's confirmed state");
}

- (void) testMissingArtifactShowsNoValues
{
  [self writeSidecarWithSeedDomain: domain];
  [[NSFileManager defaultManager] removeFileAtPath: appimage handler: nil];
  XCTAssertFalse([model setTargetAppImageSidecar: [self sidecar] appImage: nil]);
  XCTAssertTrue([[model themeNote] rangeOfString: @"is not there"].location != NSNotFound, @"%@", [model themeNote]);
  XCTAssertEqual([[model rows] count], (NSUInteger)0);
  XCTAssertEqualObjects([[[model themeChoices] lastObject] title], @"Not known for the running AppImage");
  [self assertNothingEditable];
}

- (void) testChangedArtifactShowsNoValues
{
  [self writeSidecarWithSeedDomain: domain];
  [[@"rebuilt" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: appimage atomically: YES];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", domain, @"GSTheme", @"Gumdrop", nil]);
  XCTAssertFalse([model setTargetAppImageSidecar: [self sidecar] appImage: nil]);
  XCTAssertTrue([[model themeNote] rangeOfString: @"has changed"].location != NSNotFound);
  XCTAssertTrue([[model themeStateText] rangeOfString: @"Package default"].location == NSNotFound,
    @"no prediction from metadata that doesn't match the AppImage");
  XCTAssertEqual([[model rows] count], (NSUInteger)0, @"stale metadata is not used for values");
  XCTAssertEqualObjects([[[model themeChoices] lastObject] title], @"Not known for the running AppImage");
  [self assertNothingEditable];
}

- (void) testWrongDomainSeedIsWarnedAndNotPromised
{
  [self writeSidecarWithSeedDomain: @"org.example.SomewhereElse"];
  XCTAssertTrue([model setTargetAppImageSidecar: [self sidecar] appImage: nil]);
  XCTAssertTrue([[model themeNote] rangeOfString: @"not in the domain the app reads"].location != NSNotFound,
    @"%@", [model themeNote]);
  XCTAssertTrue([[model themeStateText] rangeOfString: @"may not apply"].location != NSNotFound, @"%@", [model themeStateText]);
  XCTAssertTrue([[model themeStateText] rangeOfString: @"written by the AppImage at each launch"].location == NSNotFound,
    @"no each-launch promise for a seed in the wrong domain");
  XCTAssertEqualObjects([[[model themeChoices] lastObject] title], @"Not known for the running AppImage");
  [self assertNothingEditable];
}

- (void) testSwitchingBackToANormalTargetIsEditable
{
  [self writeSidecarWithSeedDomain: domain];
  [model setTargetAppImageSidecar: [self sidecar] appImage: nil];
  XCTAssertTrue([model setTargetGlobal]);
  XCTAssertFalse([model targetIsAppImage]);
  XCTAssertTrue([model isEditable]);
}
@end
