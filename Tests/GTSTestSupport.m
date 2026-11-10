#import "GTSTestSupport.h"
#import "GTSDefaultsDomainStore.h"
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>

@implementation GTSToolResult
- (void) dealloc { [output release]; [errorOutput release]; [super dealloc]; }
- (NSString*) description
{
  return [NSString stringWithFormat: @"<status %d%s out=%@ err=%@>", status,
    timedOut ? " TIMEOUT" : "", output, errorOutput];
}
@end

NSString *GTSTestRoot(void)
{
  return [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_TEST_ROOT"];
}

NSString *GTSExamplesDir(void)
{
  return [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_EXAMPLES"];
}

#include <limits.h>

/* realpath() of the deepest existing ancestor, plus the remaining
   components, so a symlink anywhere in an existing prefix is resolved even
   when the tail does not exist yet. "." and ".." in the tail are kept so the
   caller can reject them. */
static NSString *
canonicalPath(NSString *path)
{
  NSString *head = path, *tail = @"";
  char buf[PATH_MAX];
  while ([head length] > 1 && realpath([head fileSystemRepresentation], buf) == NULL)
    {
      tail = [[head lastPathComponent] stringByAppendingPathComponent: tail];
      head = [head stringByDeletingLastPathComponent];
    }
  if (realpath([head fileSystemRepresentation], buf) == NULL)
    return nil;
  head = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: buf length: strlen(buf)];
  return [tail length] ? [head stringByAppendingPathComponent: tail] : head;
}

BOOL GTSPathIsInside(NSString *path, NSString *root)
{
  NSArray *p, *r;
  NSUInteger i;
  if (![path isAbsolutePath] || ![root isAbsolutePath]) return NO;
  path = canonicalPath(path);
  root = canonicalPath(root);
  if (path == nil || root == nil) return NO;
  p = [path pathComponents];
  r = [root pathComponents];
  if ([r count] < 2 || [p count] < [r count]) return NO;   /* never "/" */
  for (i = 0; i < [r count]; i++)
    if (![[p objectAtIndex: i] isEqual: [r objectAtIndex: i]]) return NO;
  for (i = [r count]; i < [p count]; i++)
    if ([[p objectAtIndex: i] isEqual: @".."]) return NO;
  return YES;
}

static void
refuse(NSString *why)
{
  fprintf(stderr, "REFUSING TO RUN: %s\n", [why UTF8String]);
  abort();
}

static NSString *
readAll(NSFileHandle *h)
{
  NSData *d = [h readDataToEndOfFile];
  return [[[NSString alloc] initWithData: d encoding: NSUTF8StringEncoding] autorelease];
}

GTSToolResult *GTSRunTool(NSString *path, NSArray *args, NSTimeInterval timeout)
{
  GTSToolResult *r = [[GTSToolResult new] autorelease];
  NSTask *t = [[NSTask new] autorelease];
  NSPipe *o = [NSPipe pipe], *e = [NSPipe pipe];
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: timeout];

  [t setLaunchPath: path];
  [t setArguments: args];
  [t setStandardOutput: o];
  [t setStandardError: e];
  [t setStandardInput: [NSFileHandle fileHandleWithNullDevice]];
  NS_DURING
    [t launch];
  NS_HANDLER
    r->status = -1;
    r->errorOutput = [[localException reason] copy];
    NS_VALUERETURN(r, GTSToolResult*);
  NS_ENDHANDLER
  while ([t isRunning] && [limit timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]];
  if ([t isRunning])
    {
      r->timedOut = YES;
      kill([t processIdentifier], SIGKILL);
    }
  [t waitUntilExit];                    /* reap */
  [[o fileHandleForWriting] closeFile];
  [[e fileHandleForWriting] closeFile];
  r->output = [readAll([o fileHandleForReading]) retain];
  r->errorOutput = [readAll([e fileHandleForReading]) retain];
  r->status = r->timedOut ? -1 : [t terminationStatus];
  return r;
}

void GTSRequireIsolatedDefaults(void)
{
  static BOOL checked = NO;
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *root = GTSTestRoot(), *actual, *probe, *child;
  GTSToolResult *r;

  if (checked) return;
  if ([root length] < 2 || ![root isAbsolutePath])
    refuse(@"GTS_TEST_ROOT is not set to an absolute path");
  actual = [GTSDefaultsDomainStore defaultsRoot];
  if (!GTSPathIsInside(actual, root))
    refuse([NSString stringWithFormat: @"defaults root %@ is not inside %@", actual, root]);

  /* Child processes: verify read-only, with the same runtime and config,
     before the first child write. */
  probe = [env objectForKey: @"GTS_ROOT_PROBE"];
  if ([probe length] == 0)
    refuse(@"GTS_ROOT_PROBE not set; cannot verify child isolation");
  r = GTSRunTool(probe, [NSArray array], 10);
  child = [[r->output stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
  if (r->status != 0 || !GTSPathIsInside(child, root))
    refuse([NSString stringWithFormat: @"child defaults root %@ (%@) is not inside %@", child, r, root]);
  [child release];
  checked = YES;
}

GTSToolResult *GTSRunDefaults(NSArray *args)
{
  NSString *tool = [[[NSProcessInfo processInfo] environment] objectForKey: @"GTS_DEFAULTS_TOOL"];
  GTSRequireIsolatedDefaults();
  return GTSRunTool(tool ? tool : @"/usr/bin/defaults", args, 20);
}

NSString *GTSMustRunDefaults(NSArray *args)
{
  GTSToolResult *r = GTSRunDefaults(args);
  if (r->status != 0)
    [NSException raise: NSInternalInconsistencyException
                format: @"defaults %@ failed: %@", [args componentsJoinedByString: @" "], r];
  return r->output;
}

NSString *GTSExternalRead(NSString *domain, NSString *key)
{
  GTSToolResult *r = GTSRunDefaults([NSArray arrayWithObjects: @"read", domain, key, nil]);
  NSString *prefix = [NSString stringWithFormat: @"%@ %@ ", domain, key];
  NSEnumerator *e;
  NSString *line;

  if (r->status == 2 && [r->errorOutput rangeOfString: @"couldn't read default"].location != NSNotFound)
    return nil;                          /* the tool's "missing" answer */
  if (r->status != 0)
    [NSException raise: NSInternalInconsistencyException
                format: @"defaults read %@ %@ failed: %@", domain, key, r];
  e = [[r->output componentsSeparatedByString: @"\n"] objectEnumerator];
  while ((line = [e nextObject]) != nil)
    if ([line hasPrefix: prefix])
      return [line substringFromIndex: [prefix length]];
  [NSException raise: NSInternalInconsistencyException
              format: @"defaults read %@ %@: unexpected output %@", domain, key, r];
  return nil;
}

NSString *GTSUniqueDomain(NSString *stem)
{
  static unsigned n = 0;
  return [NSString stringWithFormat: @"org.gts.test.%@.%d.%u", stem,
    [[NSProcessInfo processInfo] processIdentifier], ++n];
}
