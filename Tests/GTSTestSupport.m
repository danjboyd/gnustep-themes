#import "GTSTestSupport.h"
#import "GTSDefaultsDomainStore.h"
#include <stdlib.h>
#include <stdio.h>

NSString *GTSTestRoot(void)
{
  return [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_TEST_ROOT"];
}

NSString *GTSExamplesDir(void)
{
  return [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_EXAMPLES"];
}

void GTSRequireIsolatedDefaults(void)
{
  static BOOL checked = NO;
  NSString *root = GTSTestRoot(), *actual;
  if (checked) return;
  actual = [GTSDefaultsDomainStore defaultsRoot];
  if ([root length] < 2 || ![root isAbsolutePath] || ![actual hasPrefix: root])
    {
      fprintf(stderr, "REFUSING TO RUN: defaults root %s is not under GTS_TEST_ROOT %s\n",
        [actual UTF8String], root ? [root UTF8String] : "(unset)");
      abort();
    }
  checked = YES;
}

NSString *GTSRunDefaults(NSArray *args)
{
  NSTask *t = [[NSTask new] autorelease];
  NSPipe *p = [NSPipe pipe];
  NSData *d;
  NSString *tool = [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_DEFAULTS_TOOL"];
  GTSRequireIsolatedDefaults();
  [t setLaunchPath: tool ? tool : @"/usr/bin/defaults"];
  [t setArguments: args];
  [t setStandardOutput: p];
  [t launch];
  d = [[p fileHandleForReading] readDataToEndOfFile];
  [t waitUntilExit];
  return [[[NSString alloc] initWithData: d encoding: NSUTF8StringEncoding] autorelease];
}

NSString *GTSExternalRead(NSString *domain, NSString *key)
{
  NSString *out = GTSRunDefaults([NSArray arrayWithObjects: @"read", domain, key, nil]);
  NSString *prefix = [NSString stringWithFormat: @"%@ %@ ", domain, key];
  NSEnumerator *e = [[out componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString *line;
  while ((line = [e nextObject]) != nil)
    if ([line hasPrefix: prefix])
      return [line substringFromIndex: [prefix length]];
  return nil;
}

NSString *GTSUniqueDomain(NSString *stem)
{
  static unsigned n = 0;
  return [NSString stringWithFormat: @"org.gts.test.%@.%d.%u", stem,
    [[NSProcessInfo processInfo] processIdentifier], ++n];
}
