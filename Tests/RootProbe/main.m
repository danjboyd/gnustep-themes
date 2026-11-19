/* gts-root-probe: prints the defaults root this runtime + environment
   resolves, read-only. Used to verify a child process' isolation BEFORE
   anything is written through the defaults tool. Writes nothing.
   With -home it prints NSHomeDirectory() instead (gnustep-base takes it
   from GNUSTEP_HOME, else the passwd entry; it ignores HOME). With
   -library it prints the user domain's Library folder, where user themes
   are looked up (Library/Themes). */
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *root;

  if (argc > 1 && strcmp(argv[1], "-home") == 0)
    root = NSHomeDirectory();
  else if (argc > 1 && strcmp(argv[1], "-library") == 0)
    root = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
  else
    root = GSDefaultsRootForUser(NSUserName());
  printf("%s\n", root ? [root fileSystemRepresentation] : "");
  [pool release];
  return root ? 0 : 1;
}
