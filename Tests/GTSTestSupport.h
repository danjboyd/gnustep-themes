#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

/* Aborts the process unless GNUstep defaults are isolated under GTS_TEST_ROOT. */
void GTSRequireIsolatedDefaults(void);
NSString *GTSTestRoot(void);
NSString *GTSExamplesDir(void);
/* Run the system `defaults` tool as a separate process; returns stdout. */
NSString *GTSRunDefaults(NSArray *args);
/* Read one key through a separate process; nil if absent. */
NSString *GTSExternalRead(NSString *domain, NSString *key);
NSString *GTSUniqueDomain(NSString *stem);
