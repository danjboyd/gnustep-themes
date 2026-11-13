/* gts-fresh-root <scratch-root>: with a defaults root that does not exist
   yet (a new user's first launch), the store must read NSGlobalDomain and
   write, read back and remove a key in a throwaway domain. Refuses unless
   the defaults root is inside <scratch-root> and absent at start.
   Exit 0 = pass, 1 = fail, 2 = refused (isolation). */
#import <Foundation/Foundation.h>
#import "GTSDefaultsDomainStore.h"
#include <stdio.h>

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *scratch, *root;
  GTSDefaultsDomainStore *s;
  GTSDomainSnapshot *snap;
  NSError *err = nil;
  int rc = 0;

  if (argc != 2) { fprintf(stderr, "usage: gts-fresh-root <scratch-root>\n"); return 2; }
  scratch = [[NSString stringWithUTF8String: argv[1]] stringByStandardizingPath];
  root = [[GTSDefaultsDomainStore defaultsRoot] stringByStandardizingPath];
  if (![scratch isAbsolutePath] || ![root hasPrefix: [scratch stringByAppendingString: @"/"]])
    { fprintf(stderr, "fresh-root: REFUSED: defaults root %s not inside %s\n", [root UTF8String], [scratch UTF8String]); return 2; }
  if ([[NSFileManager defaultManager] fileExistsAtPath: root])
    { fprintf(stderr, "fresh-root: REFUSED: %s already exists\n", [root UTF8String]); return 2; }

  s = [[[GTSDefaultsDomainStore alloc] init] autorelease];
  snap = [s snapshotForDomain: @"NSGlobalDomain" error: &err];
  if (snap == nil) { printf("FAIL read NSGlobalDomain in a new root: %s\n", [[err localizedDescription] UTF8String]); rc = 1; }
  else printf("ok read NSGlobalDomain in a new root (%lu keys)\n", (unsigned long)[[snap values] count]);

  err = nil;
  if (![s commitChanges: [NSDictionary dictionaryWithObject: @"Compact" forKey: @"GumdropSize"]
               toDomain: @"org.example.FreshRoot" baseline: nil conflicts: NULL error: &err])
    { printf("FAIL write in a new root: %s\n", [[err localizedDescription] UTF8String]); rc = 1; }
  else printf("ok write and read-back in a new root\n");

  err = nil;
  if (![s removeKey: @"GumdropSize" fromDomain: @"org.example.FreshRoot" baseline: nil conflicts: NULL error: &err])
    { printf("FAIL remove in a new root: %s\n", [[err localizedDescription] UTF8String]); rc = 1; }
  else printf("ok remove in a new root\n");
  [pool release];
  return rc;
}
