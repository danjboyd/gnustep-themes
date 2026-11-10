#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

/* YES if `path` is `root` or lies inside it, comparing symlink-resolved,
   standardized path components (so /a/rootX is not inside /a/root). */
BOOL GTSPathIsInside(NSString *path, NSString *root);

/* Aborts the process unless GNUstep defaults (this process AND a child
   probed read-only with the same runtime/config) resolve under GTS_TEST_ROOT. */
void GTSRequireIsolatedDefaults(void);
NSString *GTSTestRoot(void);
NSString *GTSExamplesDir(void);

@interface GTSToolResult : NSObject
{
@public
  int status;
  BOOL timedOut;
  NSString *output;
  NSString *errorOutput;
}
@end

/* Runs a tool with a time bound; the child is terminated and reaped on
   timeout. Never throws for a failing child. */
GTSToolResult *GTSRunTool(NSString *path, NSArray *args, NSTimeInterval timeout);
/* Runs the defaults tool (after isolation is verified). */
GTSToolResult *GTSRunDefaults(NSArray *args);
/* Same, but raises if the tool fails or times out. */
NSString *GTSMustRunDefaults(NSArray *args);
/* Reads one key through a separate process. nil only when the tool reports
   the key as missing; any other failure raises. */
NSString *GTSExternalRead(NSString *domain, NSString *key);
NSString *GTSUniqueDomain(NSString *stem);
