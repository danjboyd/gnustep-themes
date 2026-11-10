/* Sidecar reader (schema 1, provisional per packager draft PR #127). */
#import "GTSTestSupport.h"
#import "GTSAppImageSidecar.h"
#import "GTSSHA256.h"
#import "GTSThemeSettingsSchema.h"
#import "GTSDefaultsDomainStore.h"

@interface GTSAppImageSidecarTests : XCTestCase
{
  NSString *dir, *appimage, *sidecar;
}
@end

static NSDictionary *
inlineGumdrop(void)
{
  NSString *p = [GTSExamplesDir() stringByAppendingPathComponent: @"Gumdrop.theme/Resources/ThemeSettings.plist"];
  return [[NSString stringWithContentsOfFile: p] propertyList];
}

@implementation GTSAppImageSidecarTests

- (NSMutableDictionary*) sidecarFor: (NSString*)fileName sha: (NSString*)sha
{
  NSMutableDictionary *settingsInline = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    @"inline", @"status", [NSNumber numberWithInt: 1], @"schemaVersion", inlineGumdrop(), @"inline",
    [NSNull null], @"note", nil];
  NSArray *themes = [NSArray arrayWithObjects:
    [NSDictionary dictionaryWithObjectsAndKeys: @"Gumdrop", @"name", @"org.gnustep.themes.gumdrop", @"themeId",
      @"ok", @"infoStatus", @"themeInputs", @"origin",
      [NSDictionary dictionaryWithObjectsAndKeys: @"usr/GNUstep/System/Library/Themes/Gumdrop.theme", @"bundledPath",
        @"ok", @"executableStatus", nil], @"installation",
      settingsInline, @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Big", @"name", [NSNull null], @"themeId", @"ok", @"infoStatus",
      [NSDictionary dictionaryWithObjectsAndKeys: @"notInlined", @"status", [NSNull null], @"inline",
        @"over 256 KiB; contents unavailable without reading the AppImage", @"note", nil], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Broken", @"name", @"ok", @"infoStatus",
      [NSDictionary dictionaryWithObjectsAndKeys: @"malformed", @"status", @"parse error at line 3", @"note", nil], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Linked", @"name", @"unavailable", @"infoStatus",
      [NSDictionary dictionaryWithObjectsAndKeys: @"unavailable", @"status", nil], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Plain", @"name", @"ok", @"infoStatus", [NSNull null], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Gone", @"name", @"missing", @"infoStatus",
      [NSNull null], @"installation", [NSNull null], @"settings", nil],
    nil];
  return [NSMutableDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"schema",
    [NSDictionary dictionaryWithObjectsAndKeys: fileName, @"fileName", sha, @"sha256", nil], @"appimage",
    [NSDictionary dictionaryWithObjectsAndKeys: @"org.example.App", @"id", nil], @"package",
    [NSMutableDictionary dictionaryWithObjectsAndKeys: @"org.example.App", @"runtimeDomainHint",
      @"bundleIdentifier", @"runtimeDomainHintSource", nil], @"app",
    [NSMutableDictionary dictionaryWithObjectsAndKeys: @"org.example.App", @"seedDomain",
      [NSNumber numberWithBool: YES], @"seedDomainMatchesRuntimeHint",
      [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: @"GSTheme", @"key", @"Gumdrop", @"value",
        @"each-launch-if-absent", @"policy", [NSNumber numberWithInt: 1], @"rank", nil]], @"seeds",
      [NSArray arrayWithObject: [NSDictionary dictionaryWithObjectsAndKeys: @"GSTheme", @"key", @"Gumdrop", @"value",
        @"ifUnset", @"policy", [NSNull null], @"rank", @"not read by gnustep-base/gui; informational only", @"effect", nil]], @"env",
      nil], @"defaults",
    themes, @"themes", nil];
}

- (NSString*) writeSidecar: (NSDictionary*)d
{
  NSData *j = [NSJSONSerialization dataWithJSONObject: d options: 0 error: NULL];
  [j writeToFile: sidecar atomically: YES];
  return sidecar;
}

- (void) setUp
{
  GTSRequireIsolatedDefaults();
  dir = [[GTSTestRoot() stringByAppendingPathComponent: GTSUniqueDomain(@"appimage")] retain];
  [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                                             attributes: nil error: NULL];
  appimage = [[dir stringByAppendingPathComponent: @"App-1.2.3-x86_64.AppImage"] retain];
  sidecar = [[dir stringByAppendingPathComponent: @"App-1.2.3-x86_64.themes.json"] retain];
  /* Not a real AppImage: only its bytes are hashed, it is never run. */
  [[@"fake appimage bytes" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: appimage atomically: YES];
}

- (void) tearDown
{
  [dir release]; [appimage release]; [sidecar release];
}

- (GTSAppImageSidecar*) loadBound
{
  [self writeSidecar: [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)]];
  return [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
}

- (void) testSHA256KnownVectors
{
  XCTAssertEqualObjects(GTSSHA256HexOfData([NSData data]),
    @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  XCTAssertEqualObjects(GTSSHA256HexOfData([@"abc" dataUsingEncoding: NSUTF8StringEncoding]),
    @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  XCTAssertEqualObjects(GTSSHA256HexOfData([@"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    dataUsingEncoding: NSUTF8StringEncoding]),
    @"248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
}

- (void) testBoundSidecarFields
{
  GTSAppImageSidecar *s = [self loadBound];
  XCTAssertNotNil(s);
  XCTAssertEqual([s bindingForAppImageAtPath: nil], GTSSidecarBound);
  XCTAssertEqualObjects([s runtimeDomainHint], @"org.example.App");
  XCTAssertEqualObjects([s seedDomainMatchesRuntimeHint], [NSNumber numberWithBool: YES]);
  XCTAssertEqualObjects([s seededTheme], @"Gumdrop");
  XCTAssertEqualObjects([[[s envEntries] lastObject] objectForKey: @"effect"],
    @"not read by gnustep-base/gui; informational only");
  XCTAssertEqual([[s themes] count], (NSUInteger)6);
}

- (void) testSettingsStatusesAreExplicit
{
  GTSAppImageSidecar *s = [self loadBound];
  GTSSidecarTheme *g = [s themeNamed: @"Gumdrop"];
  XCTAssertEqual([g settingsStatus], GTSSettingsInline);
  XCTAssertTrue([g isFullyDescribed]);
  XCTAssertEqualObjects([[g schema] themeIdentifier], @"org.gnustep.themes.gumdrop");
  XCTAssertEqual([[s themeNamed: @"Big"] settingsStatus], GTSSettingsNotInlined);
  XCTAssertFalse([[s themeNamed: @"Big"] isFullyDescribed], @"too-large settings must not look complete");
  XCTAssertNotNil([[s themeNamed: @"Big"] settingsNote]);
  XCTAssertEqual([[s themeNamed: @"Broken"] settingsStatus], GTSSettingsMalformed);
  XCTAssertEqual([[s themeNamed: @"Linked"] settingsStatus], GTSSettingsUnavailable);
  XCTAssertEqual([[s themeNamed: @"Plain"] settingsStatus], GTSSettingsNone);
  XCTAssertEqualObjects([[s themeNamed: @"Gone"] infoStatus], @"missing");
  XCTAssertNil([[s themeNamed: @"Gone"] bundledPath]);
  XCTAssertFalse([g isCompatibilityKnown], @"compatibility is never inferred from metadata");
}

- (void) testAvailabilityStatusesAreKeptAsGiven
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  NSArray *cases = [NSArray arrayWithObjects:
    [NSDictionary dictionaryWithObjectsAndKeys: @"OutsideLink", @"name", @"unavailable", @"infoStatus",
      [NSDictionary dictionaryWithObjectsAndKeys: @"usr/x/OutsideLink.theme", @"bundledPath",
        @"unavailable", @"executableStatus", [NSNull null], @"executableSha256", nil], @"installation",
      [NSDictionary dictionaryWithObjectsAndKeys: @"unavailable", @"status", nil], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"NoCode", @"name", @"ok", @"infoStatus",
      [NSDictionary dictionaryWithObjectsAndKeys: @"usr/x/NoCode.theme", @"bundledPath",
        @"absent", @"executableStatus", nil], @"installation", [NSNull null], @"settings", nil],
    [NSDictionary dictionaryWithObjectsAndKeys: @"Unstated", @"name",
      [NSDictionary dictionaryWithObjectsAndKeys: @"usr/x/Unstated.theme", @"bundledPath", nil], @"installation", nil],
    nil];
  GTSAppImageSidecar *s;
  [d setObject: cases forKey: @"themes"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertEqualObjects([[s themeNamed: @"OutsideLink"] infoStatus], @"unavailable");
  XCTAssertEqualObjects([[s themeNamed: @"OutsideLink"] executableStatus], @"unavailable");
  XCTAssertEqual([[s themeNamed: @"OutsideLink"] settingsStatus], GTSSettingsUnavailable);
  XCTAssertFalse([[s themeNamed: @"OutsideLink"] isFullyDescribed]);
  XCTAssertEqualObjects([[s themeNamed: @"NoCode"] executableStatus], @"absent");
  XCTAssertNil([[s themeNamed: @"Unstated"] infoStatus], @"not stated is not 'ok'");
  XCTAssertNil([[s themeNamed: @"Unstated"] executableStatus]);
}

- (void) testInvalidInlineSettingsAreNotDescribed
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  NSMutableDictionary *t0 = [[[[d objectForKey: @"themes"] objectAtIndex: 0] mutableCopy] autorelease];
  NSMutableDictionary *st = [[[t0 objectForKey: @"settings"] mutableCopy] autorelease];
  GTSAppImageSidecar *s;
  [st setObject: [NSDictionary dictionaryWithObject: @"7" forKey: @"SchemaVersion"] forKey: @"inline"];
  [t0 setObject: st forKey: @"settings"];
  [d setObject: [NSArray arrayWithObject: t0] forKey: @"themes"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertFalse([[s themeNamed: @"Gumdrop"] isFullyDescribed]);
  XCTAssertNotNil([[s themeNamed: @"Gumdrop"] schemaProblem]);
}

- (void) testChangedArtifactIsAHashMismatch
{
  GTSAppImageSidecar *s = [self loadBound];
  [[@"rebuilt appimage" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: appimage atomically: YES];
  XCTAssertEqual([s bindingForAppImageAtPath: nil], GTSSidecarHashMismatch);
  XCTAssertTrue([[GTSAppImageSidecar descriptionOfBinding: GTSSidecarHashMismatch]
    rangeOfString: @"changed"].location != NSNotFound);
}

- (void) testMissingAndRenamedArtifacts
{
  GTSAppImageSidecar *s = [self loadBound];
  NSString *other = [dir stringByAppendingPathComponent: @"Other.AppImage"];
  [[NSData dataWithContentsOfFile: appimage] writeToFile: other atomically: YES];
  XCTAssertEqual([s bindingForAppImageAtPath: other], GTSSidecarNameMismatch,
    @"same bytes under another name are not bound");
  [[NSFileManager defaultManager] removeFileAtPath: appimage handler: nil];
  XCTAssertEqual([s bindingForAppImageAtPath: nil], GTSSidecarArtifactMissing);
}

- (void) testRejectsUnboundOrFutureSidecars
{
  NSError *err = nil;
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  [d setObject: [NSNumber numberWithInt: 2] forKey: @"schema"];
  [self writeSidecar: d];
  XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorUnsupportedVersion);

  d = [self sidecarFor: @"../escape.AppImage" sha: GTSSHA256HexOfFile(appimage)];
  [self writeSidecar: d];
  XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL], @"path in fileName");

  d = [self sidecarFor: [appimage lastPathComponent] sha: @"not-a-hash"];
  [self writeSidecar: d];
  XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL]);

  [@"{ not json" writeToFile: sidecar atomically: YES];
  XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: &err]);
  XCTAssertEqual([err code], (NSInteger)GTSErrorInvalidSchema);
}

- (void) testSchemaMustBeTheInteger1
{
  NSArray *bad = [NSArray arrayWithObjects: [NSNumber numberWithBool: YES],
    [NSNumber numberWithDouble: 1.5], @"1", [NSNumber numberWithInt: 0], [NSNull null], nil];
  NSEnumerator *e = [bad objectEnumerator];
  id v;
  while ((v = [e nextObject]) != nil)
    {
      NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
      [d setObject: v forKey: @"schema"];
      [self writeSidecar: d];
      XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL], @"schema %@", v);
    }
}

- (void) testPathLikeFileNamesRejected
{
  NSArray *bad = [NSArray arrayWithObjects: @"", @".", @"..", @"a/b.AppImage", @"a\\b.AppImage",
    @"x\n.AppImage", nil];
  NSEnumerator *e = [bad objectEnumerator];
  NSString *n;
  while ((n = [e nextObject]) != nil)
    {
      [self writeSidecar: [self sidecarFor: n sha: GTSSHA256HexOfFile(appimage)]];
      XCTAssertNil([GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL], @"name %@", n);
    }
}

- (void) testMalformedNestedTypesReadAsAbsent
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  GTSAppImageSidecar *s;
  [d setObject: @"not an object" forKey: @"app"];
  [d setObject: [NSArray arrayWithObject: @"x"] forKey: @"defaults"];
  [d setObject: [NSArray arrayWithObjects: @"just a string",
    [NSDictionary dictionaryWithObjectsAndKeys: @"T", @"name", @"oops", @"installation",
      [NSNumber numberWithInt: 3], @"themeId", @"also wrong", @"settings", nil], nil] forKey: @"themes"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertNotNil(s, @"still bound to its AppImage");
  XCTAssertNil([s runtimeDomainHint]);
  XCTAssertEqualObjects([s runtimeDomainHintSource], @"unknown");
  XCTAssertNil([s seededTheme]);
  XCTAssertEqual([[s themes] count], (NSUInteger)1);
  XCTAssertNil([[s themeNamed: @"T"] themeId], @"number is not an id");
  XCTAssertNil([[s themeNamed: @"T"] bundledPath]);
  XCTAssertEqual([[s themeNamed: @"T"] settingsStatus], GTSSettingsMalformed,
    @"a wrong-typed settings entry is damaged, not absent");
  XCTAssertTrue([[s warnings] count] >= 1);

  [d setObject: @"not a list" forKey: @"themes"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertEqual([[s themes] count], (NSUInteger)0);
  XCTAssertTrue([[s warnings] count] >= 1, @"a non-list is reported, not silently empty");
}

/* Streaming/final-block handling: compare against the system sha256sum
   for sizes around the 64-byte block, the 56-byte padding limit and the
   64 KiB read buffer. */
- (void) testFileDigestMatchesSystemSha256sumAtBoundaries
{
  int sizes[] = { 0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 65535, 65536, 65537, 131073 };
  int i;
  for (i = 0; i < (int)(sizeof sizes / sizeof sizes[0]); i++)
    {
      NSMutableData *d = [NSMutableData dataWithLength: sizes[i]];
      unsigned char *b = [d mutableBytes];
      NSString *f = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"blob%d", sizes[i]]];
      GTSToolResult *r;
      int k;
      for (k = 0; k < sizes[i]; k++) b[k] = (unsigned char)(k * 31 + 7);
      [d writeToFile: f atomically: YES];
      r = GTSRunTool(@"/usr/bin/sha256sum", [NSArray arrayWithObject: f], 10);
      XCTAssertEqual(r->status, 0);
      XCTAssertEqualObjects(GTSSHA256HexOfFile(f), [r->output substringToIndex: 64], @"size %d", sizes[i]);
      XCTAssertEqualObjects(GTSSHA256HexOfData(d), GTSSHA256HexOfFile(f), @"size %d", sizes[i]);
    }
}

- (void) testDomainMatchIsDerivedAndProducerFlagCrossChecked
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  GTSAppImageSidecar *s;
  /* Producer claims a match, but the domains differ. */
  [[d objectForKey: @"defaults"] setObject: @"org.example.Other" forKey: @"seedDomain"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertEqualObjects([s seedDomainMatchesRuntimeHint], [NSNumber numberWithBool: NO], @"ours, not the producer's");
  XCTAssertTrue([[[s warnings] componentsJoinedByString: @"|"] rangeOfString: @"says true"].location != NSNotFound,
    @"%@", [s warnings]);
  /* Wrongly typed flag: number 1 is not a JSON boolean. */
  [[d objectForKey: @"defaults"] setObject: @"org.example.App" forKey: @"seedDomain"];
  [[d objectForKey: @"defaults"] setObject: [NSNumber numberWithInt: 1] forKey: @"seedDomainMatchesRuntimeHint"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertEqualObjects([s seedDomainMatchesRuntimeHint], [NSNumber numberWithBool: YES]);
  XCTAssertTrue([[[s warnings] componentsJoinedByString: @"|"] rangeOfString: @"not a boolean"].location != NSNotFound);
}

- (void) testUnrecognisedHintSourceIsUnknown
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  GTSAppImageSidecar *s;
  [[d objectForKey: @"app"] setObject: @"guessedFromIcon" forKey: @"runtimeDomainHintSource"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertEqualObjects([s runtimeDomainHintSource], @"unknown");
  XCTAssertNil([s runtimeDomainHint]);
  XCTAssertNil([s seedDomainMatchesRuntimeHint]);
}

- (void) testUnknownSeedPolicyPromisesNothing
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  NSArray *policies = [NSArray arrayWithObjects: @"first-launch-only", [NSNull null], nil];
  NSEnumerator *e = [policies objectEnumerator];
  id pol;
  while ((pol = [e nextObject]) != nil)
    {
      GTSAppImageSidecar *s;
      [[d objectForKey: @"defaults"] setObject: [NSArray arrayWithObject:
        [NSDictionary dictionaryWithObjectsAndKeys: @"GSTheme", @"key", @"Gumdrop", @"value", pol, @"policy", nil]]
        forKey: @"seeds"];
      [self writeSidecar: d];
      s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
      XCTAssertEqual([s seededThemeStateForStoredValue: nil inDomain: @"org.example.App"], GTSSeedPolicyUnknown, @"%@", pol);
      XCTAssertEqual([s seededThemeStateForStoredValue: @"Gumdrop" inDomain: @"org.example.App"], GTSSeedPolicyUnknown);
      XCTAssertTrue([s isRemovalMeaningfulForKey: @"GSTheme"], @"no each-launch promise, so no claim either way");
      XCTAssertTrue([[s descriptionOfSeededThemeState: GTSSeedPolicyUnknown] rangeOfString: @"unknown"].location != NSNotFound);
    }
}

- (void) testNoHashBackendMeansBindingNotChecked
{
  GTSAppImageSidecar *s = [self loadBound];
  XCTAssertTrue(GTSSHA256IsAvailable(), @"this build links GnuTLS");
  GTSSHA256SetDisabledForTesting(YES);
  XCTAssertEqual([s bindingForAppImageAtPath: nil], GTSSidecarCheckUnavailable, @"never reported as Bound");
  XCTAssertNil(GTSSHA256HexOfFile(appimage));
  GTSSHA256SetDisabledForTesting(NO);
  XCTAssertEqual([s bindingForAppImageAtPath: nil], GTSSidecarBound);
}

- (void) testUnknownRuntimeDomainIsNotGuessed
{
  NSMutableDictionary *d = [self sidecarFor: [appimage lastPathComponent] sha: GTSSHA256HexOfFile(appimage)];
  GTSAppImageSidecar *s;
  [[d objectForKey: @"app"] setObject: @"unknown" forKey: @"runtimeDomainHintSource"];
  [[d objectForKey: @"app"] setObject: [NSNull null] forKey: @"runtimeDomainHint"];
  [[d objectForKey: @"defaults"] setObject: [NSNull null] forKey: @"seedDomainMatchesRuntimeHint"];
  [self writeSidecar: d];
  s = [GTSAppImageSidecar sidecarWithContentsOfFile: sidecar error: NULL];
  XCTAssertNil([s runtimeDomainHint]);
  XCTAssertNil([s seedDomainMatchesRuntimeHint], @"unknown, not false and not true");
}

/* AppRun: on every launch, `defaults read <domain> GSTheme`; write the
   packaged value only if absent. Walk several launches. */
- (void) testSeededThemeAcrossRepeatedLaunches
{
  GTSAppImageSidecar *s = [self loadBound];
  NSString *dom = @"org.example.App", *stored = nil;
  int launch;
  XCTAssertEqual([s seededThemeStateForStoredValue: stored inDomain: dom], GTSSeedAbsentWillApply);
  for (launch = 0; launch < 3; launch++)
    {
      if (stored == nil) stored = [s seededTheme];     /* what AppRun does */
      XCTAssertEqual([s seededThemeStateForStoredValue: stored inDomain: dom], GTSSeedInEffect);
    }
  stored = @"Adwaita";                                   /* user picks another theme */
  XCTAssertEqual([s seededThemeStateForStoredValue: stored inDomain: dom], GTSSeedOverriddenByUser);
  if (stored == nil) stored = [s seededTheme];          /* next launch: untouched */
  XCTAssertEqualObjects(stored, @"Adwaita");
  stored = nil;                                          /* user removes the key */
  XCTAssertEqual([s seededThemeStateForStoredValue: stored inDomain: dom], GTSSeedAbsentWillApply);
  if (stored == nil) stored = [s seededTheme];          /* next launch: it is back */
  XCTAssertEqual([s seededThemeStateForStoredValue: stored inDomain: dom], GTSSeedInEffect);
  XCTAssertFalse([s isRemovalMeaningfulForKey: @"GSTheme"]);
  XCTAssertTrue([s isRemovalMeaningfulForKey: @"GumdropMenuStyle"]);
  XCTAssertTrue([[s descriptionOfSeededThemeState: GTSSeedInEffect]
    rangeOfString: @"each launch"].location != NSNotFound);
  XCTAssertEqual([s seededThemeStateForStoredValue: @"Gumdrop" inDomain: @"App"], GTSSeedWrongDomain);
}

- (void) testReaderWritesNoDefaults
{
  NSString *root = [GTSDefaultsDomainStore defaultsRoot];
  NSArray *before = [[NSFileManager defaultManager] directoryContentsAtPath: root];
  GTSAppImageSidecar *s = [self loadBound];
  [s bindingForAppImageAtPath: nil];
  [s seededThemeStateForStoredValue: nil inDomain: @"org.example.App"];
  XCTAssertEqualObjects([[[NSFileManager defaultManager] directoryContentsAtPath: root]
    sortedArrayUsingSelector: @selector(compare:)], [before sortedArrayUsingSelector: @selector(compare:)]);
}
@end
