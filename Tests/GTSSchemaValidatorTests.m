/* Strict schema v1 validator: every fixture in Tests/Fixtures/Schema has an
   expected result here (a new fixture without one fails the suite), and the
   example themes validate cleanly. Fixtures: scripts/make-schema-fixtures.py. */
#import "GTSTestSupport.h"
#import "GTSSchemaValidator.h"

@interface GTSSchemaValidatorTests : XCTestCase
@end

static NSString *
fixturesDir(void)
{
  return [[[GTSExamplesDir() stringByDeletingLastPathComponent]
    stringByAppendingPathComponent: @"Tests/Fixtures/Schema"] stringByStandardizingPath];
}

/* name -> substring of the one expected ERROR ("" = no findings at all;
   "W:" prefix = no errors, and a warning containing the rest). */
static NSDictionary *
expectations(void)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    @"", @"good",
    @"unsupported SchemaVersion 2", @"bad-version-2",
    @"SchemaVersion is not an integer", @"bad-version-fraction",
    @"missing ThemeIdentifier", @"bad-missing-theme-identifier",
    @"unknown Type float", @"bad-unknown-type",
    @"missing Unset", @"bad-missing-unset",
    @"dynamic Unset must not carry a Value", @"bad-dynamic-with-value",
    @"Unset.Value ribbon is not a valid value", @"bad-unset-value-invalid",
    @"Unset.Value 3 is not a valid value", @"bad-unset-value-out-of-range",
    @"Apply must be live, newWindows or restart", @"bad-apply",
    @"unknown scope user", @"bad-scope",
    @"duplicate Identifier skipped", @"bad-duplicate-identifier",
    @"Status Unstable is not public or unstable", @"bad-status-typo",
    @"DependsOn.Setting fx.colour is not another setting", @"bad-depends-dangling",
    @"DependsOn value purple", @"bad-depends-value",
    @"Overlaps entry fx.colour-scheme is not another setting", @"bad-overlaps-dangling",
    @"Group looks is not defined in Groups", @"bad-group-undefined",
    @"Minimum/Maximum must be numbers", @"bad-minmax-string",
    @"Minimum 2.5 is greater than Maximum 2.0", @"bad-min-gt-max",
    @"Key FxScale is also described by fx.scale", @"bad-duplicate-key",
    @"enum value Dark duplicates dark", @"bad-duplicate-enum-value",
    @"Values entry ribbon", @"bad-precedence-filter",
    @"empty Precedence", @"bad-precedence-empty",
    @"CaseInsensitive sometimes is not a boolean", @"bad-case-insensitive",
    @"GSTheme is theme selection", @"bad-gstheme-key",
    @"W:can never apply", @"warn-precedence-unreachable",
    @"W:unknown setting key Minumum", @"warn-unknown-key",
    nil];
}

static BOOL
anyFinding(NSArray *findings, BOOL errors, NSString *needle)
{
  NSEnumerator *e = [findings objectEnumerator];
  GTSSchemaFinding *f;
  while ((f = [e nextObject]) != nil)
    if ([f isError] == errors && [[f description] rangeOfString: needle].location != NSNotFound)
      return YES;
  return NO;
}

@implementation GTSSchemaValidatorTests

- (void) testEveryFixtureHasItsExpectedResult
{
  NSDictionary *want = expectations();
  NSArray *files = [[NSFileManager defaultManager] directoryContentsAtPath: fixturesDir()];
  NSEnumerator *e = [files objectEnumerator];
  NSString *file;
  NSUInteger seen = 0;
  XCTAssertTrue([files count] > 0, @"no fixtures in %@", fixturesDir());
  while ((file = [e nextObject]) != nil)
    {
      NSString *name = [file stringByDeletingPathExtension];
      NSString *expect = [want objectForKey: name];
      NSArray *f;
      NSUInteger errors;
      if (![[file pathExtension] isEqual: @"plist"]) continue;
      seen++;
      XCTAssertNotNil(expect, @"fixture %@ has no expectation", name);
      if (expect == nil) continue;
      f = [GTSSchemaValidator findingsForFile: [fixturesDir() stringByAppendingPathComponent: file]];
      errors = [GTSSchemaValidator errorCountInFindings: f];
      if ([expect length] == 0)
        XCTAssertEqual([f count], (NSUInteger)0, @"%@: %@", name, f);
      else if ([expect hasPrefix: @"W:"])
        {
          XCTAssertEqual(errors, (NSUInteger)0, @"%@: %@", name, f);
          XCTAssertTrue(anyFinding(f, NO, [expect substringFromIndex: 2]), @"%@: %@", name, f);
        }
      else
        {
          XCTAssertTrue(errors > 0, @"%@ must fail: %@", name, f);
          XCTAssertTrue(anyFinding(f, YES, expect), @"%@: want '%@', got %@", name, expect, f);
        }
    }
  XCTAssertEqual(seen, [want count], @"every expectation has a fixture");
}

- (void) testExampleThemesValidateCleanly
{
  NSEnumerator *e = [[NSArray arrayWithObjects: @"Adwaita", @"WinUITheme", @"Gumdrop", nil] objectEnumerator];
  NSString *n;
  while ((n = [e nextObject]) != nil)
    {
      NSString *p = [GTSExamplesDir() stringByAppendingPathComponent:
        [NSString stringWithFormat: @"%@.theme/Resources/ThemeSettings.plist", n]];
      NSArray *f = [GTSSchemaValidator findingsForFile: p];
      XCTAssertEqual([f count], (NSUInteger)0, @"%@: %@", n, f);
    }
}

- (void) testUnreadableFileIsAnError
{
  NSArray *f = [GTSSchemaValidator findingsForFile: @"/nonexistent/ThemeSettings.plist"];
  XCTAssertEqual([GTSSchemaValidator errorCountInFindings: f], (NSUInteger)1);
}
@end
