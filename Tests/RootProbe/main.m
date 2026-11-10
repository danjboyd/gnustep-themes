/* gts-root-probe: prints the defaults root this runtime + environment
   resolves, read-only. Used to verify a child process' isolation BEFORE
   anything is written through the defaults tool. Writes nothing. */
#import <Foundation/Foundation.h>
#include <stdio.h>

int
main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *root = GSDefaultsRootForUser(NSUserName());
  printf("%s\n", root ? [root fileSystemRepresentation] : "");
  [pool release];
  return root ? 0 : 1;
}
