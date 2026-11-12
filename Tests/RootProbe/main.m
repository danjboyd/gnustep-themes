/* gts-root-probe: prints the defaults root this runtime + environment
   resolves, read-only. Used to verify a child process' isolation BEFORE
   anything is written through the defaults tool. Writes nothing.
   With -home it prints NSHomeDirectory() instead (gnustep-base takes it
   from GNUSTEP_HOME, else the passwd entry; it ignores HOME). */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *root = (argc > 1 && strcmp(argv[1], "-home") == 0)
    ? NSHomeDirectory() : GSDefaultsRootForUser(NSUserName());
  printf("%s\n", root ? [root fileSystemRepresentation] : "");
  [pool release];
  return root ? 0 : 1;
}
