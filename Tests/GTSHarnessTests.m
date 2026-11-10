/* The harness is part of the proof, so it is tested too. */
#import "GTSTestSupport.h"

@interface GTSHarnessTests : XCTestCase
@end

@implementation GTSHarnessTests

- (void) testContainmentNegativeControls
{
  NSString *root = GTSTestRoot();
  NSString *sibling = [root stringByAppendingString: @"X/user/Defaults"];
  NSString *link = [root stringByAppendingPathComponent: @"escape-link"];
  XCTAssertTrue(GTSPathIsInside([root stringByAppendingPathComponent: @"user/Defaults"], root));
  XCTAssertTrue(GTSPathIsInside(root, root));
  XCTAssertFalse(GTSPathIsInside(sibling, root), @"sibling with shared string prefix");
  XCTAssertFalse(GTSPathIsInside([root stringByAppendingPathComponent: @"../elsewhere"], root));
  XCTAssertFalse(GTSPathIsInside(@"relative/path", root));
  XCTAssertFalse(GTSPathIsInside(@"/", root));
  XCTAssertFalse(GTSPathIsInside(@"/etc", @"/"), @"root '/' is never accepted");
  [[NSFileManager defaultManager] createSymbolicLinkAtPath: link pathContent: @"/tmp"];
  XCTAssertFalse(GTSPathIsInside([link stringByAppendingPathComponent: @"x"], root),
    @"a symlink pointing outside does not count as inside");
  [[NSFileManager defaultManager] removeFileAtPath: link handler: nil];
}

- (void) testFailedChildIsReportedNotTreatedAsSuccess
{
  GTSToolResult *r = GTSRunTool(@"/bin/false", [NSArray array], 5);
  XCTAssertTrue(r->status != 0);
  XCTAssertFalse(r->timedOut);
  r = GTSRunTool(@"/nonexistent/tool", [NSArray array], 5);
  XCTAssertTrue(r->status != 0);
}

- (void) testHungChildIsBoundedAndReaped
{
  NSDate *start = [NSDate date];
  GTSToolResult *r = GTSRunTool(@"/bin/sleep", [NSArray arrayWithObject: @"30"], 1);
  XCTAssertTrue(r->timedOut);
  XCTAssertTrue(r->status != 0);
  XCTAssertTrue([[NSDate date] timeIntervalSinceDate: start] < 10);
}

- (void) testMissingKeyIsNilButToolFailureRaises
{
  NSString *d = GTSUniqueDomain(@"harness");
  BOOL raised = NO;
  XCTAssertNil(GTSExternalRead(d, @"Absent"));
  NS_DURING
    GTSMustRunDefaults([NSArray arrayWithObject: @"bogus-subcommand"]);
  NS_HANDLER
    raised = YES;
  NS_ENDHANDLER
  XCTAssertTrue(raised, @"a failing defaults command must not look like success");
}
@end
