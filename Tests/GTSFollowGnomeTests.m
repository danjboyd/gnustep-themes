/* The "Follow GNOME's light/dark and accent" switch (Adwaita only). GNOME's
   settings come from a fixed reader; nothing here runs gsettings. */
#import "GTSTestSupport.h"
#import "GTSEditorModel.h"
#import "GTSThemeCatalog.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSGnomeSettings.h"

@interface GTSFollowGnomeTests : XCTestCase
{
  GTSEditorModel *model;
  NSString *app;
}
@end

@implementation GTSFollowGnomeTests

static void
deleteGlobal(NSString *key)
{
  GTSRunDefaults([NSArray arrayWithObjects: @"delete", @"NSGlobalDomain", key, nil]);
}

- (void) useGnome: (NSDictionary*)values
{
  [model setGnomeSettings: [[[GTSFixedGnomeSettings alloc] initWithValues: values] autorelease]];
}

- (void) setUp
{
  GTSThemeCatalog *catalog;
  GTSRequireIsolatedDefaults();
  catalog = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: GTSExamplesDir() origin: GTSOriginSystem]]] autorelease];
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", @"GSTheme", @"Adwaita", nil]);
  model = [[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                        catalog: catalog];
  app = [GTSUniqueDomain(@"follow") retain];
  [self useGnome: [NSDictionary dictionaryWithObjectsAndKeys:
    @"prefer-dark", @"color-scheme", @"purple", @"accent-color", nil]];
}

- (void) tearDown
{
  deleteGlobal(@"GSTheme");
  deleteGlobal(@"GnomeThemeColorScheme");
  deleteGlobal(@"GnomeThemeAccentColor");
  [model release]; model = nil;
  [app release]; app = nil;
}

- (void) testOfferedOnlyForAdwaita
{
  XCTAssertTrue([model offersFollowSystem]);
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", @"GSTheme", @"Gumdrop", nil]);
  [model reload];
  XCTAssertFalse([model offersFollowSystem]);
  XCTAssertNil([model followSystemNote]);
  XCTAssertFalse([model setFollowsSystem: NO]);
}

- (void) testUnsetMeansFollowingAndNoteNamesGnomeValues
{
  XCTAssertTrue([model followsSystem]);
  XCTAssertTrue([[model followSystemNote] hasPrefix: @"On:"]);
  XCTAssertTrue([[model followSystemNote] rangeOfString: @"GNOME now: Dark, Purple."].location != NSNotFound,
    @"%@", [model followSystemNote]);
}

- (void) testTurningOffPinsGnomeValuesThenOnRemovesThem
{
  XCTAssertTrue([model setFollowsSystem: NO]);
  XCTAssertFalse([model followsSystem], @"staged pins show as off before Apply");
  XCTAssertNil(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"), @"nothing written before Apply");
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"), @"force-dark");
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeAccentColor"), @"purple");
  XCTAssertTrue([[model followSystemNote] hasPrefix: @"Off:"]);

  XCTAssertTrue([model setFollowsSystem: YES]);
  XCTAssertTrue([model followsSystem]);
  XCTAssertTrue([model apply]);
  XCTAssertNil(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"));
  XCTAssertNil(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeAccentColor"));
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GSTheme"), @"Adwaita", @"theme untouched");
}

- (void) testDefaultSchemeIsLightAndUnknownAccentIsBlue
{
  [self useGnome: [NSDictionary dictionaryWithObjectsAndKeys:
    @"default", @"color-scheme", @"mauve", @"accent-color", nil]];
  XCTAssertTrue([model setFollowsSystem: NO]);
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"), @"force-light");
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeAccentColor"), @"blue");
}

- (void) testMissingAccentKeyIsBlue
{
  /* GNOME before 47 has no accent-color key. */
  [self useGnome: [NSDictionary dictionaryWithObject: @"prefer-light" forKey: @"color-scheme"]];
  XCTAssertTrue([model setFollowsSystem: NO]);
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"), @"force-light");
  XCTAssertEqualObjects(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeAccentColor"), @"blue");
}

- (void) testUnreadableGnomeRefusesToPinAndStagesNothing
{
  [self useGnome: [NSDictionary dictionary]];
  XCTAssertFalse([model setFollowsSystem: NO]);
  XCTAssertFalse([model hasChanges]);
  XCTAssertTrue([[model message] rangeOfString: @"can't be read"].location != NSNotFound);
  XCTAssertTrue([[model followSystemNote] rangeOfString: @"can't be read"].location != NSNotFound);
  XCTAssertTrue([model setFollowsSystem: YES], @"turning it on needs no GNOME values");
}

- (void) testAppTargetPinsOnlyTheApplication
{
  XCTAssertTrue([model setTargetApplicationDomain: app displayName: @"Demo" info: nil]);
  XCTAssertTrue([model followsSystem]);
  XCTAssertTrue([model setFollowsSystem: NO]);
  XCTAssertTrue([model apply]);
  XCTAssertEqualObjects(GTSExternalRead(app, @"GnomeThemeColorScheme"), @"force-dark");
  XCTAssertEqualObjects(GTSExternalRead(app, @"GnomeThemeAccentColor"), @"purple");
  XCTAssertNil(GTSExternalRead(@"NSGlobalDomain", @"GnomeThemeColorScheme"), @"global untouched");
  XCTAssertTrue([model setFollowsSystem: YES]);
  XCTAssertTrue([model apply]);
  XCTAssertNil(GTSExternalRead(app, @"GnomeThemeColorScheme"));
}

- (void) testAppTargetCannotFollowWhileGlobalIsPinned
{
  GTSMustRunDefaults([NSArray arrayWithObjects: @"write", @"NSGlobalDomain", @"GnomeThemeAccentColor", @"red", nil]);
  XCTAssertTrue([model setTargetApplicationDomain: app displayName: @"Demo" info: nil]);
  XCTAssertFalse([model followsSystem]);
  XCTAssertTrue([[model followSystemNote] rangeOfString: @"inherits"].location != NSNotFound,
    @"%@", [model followSystemNote]);
  XCTAssertFalse([model setFollowsSystem: YES]);
  XCTAssertFalse([model hasChanges]);
  XCTAssertTrue([[model message] rangeOfString: @"All applications"].location != NSNotFound);
}

@end
