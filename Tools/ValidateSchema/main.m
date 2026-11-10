/* gts-validate-schema [-q] <ThemeSettings.plist | Name.theme>...
   Prints every finding as "<path>: ERROR|WARNING: <where>: <message>" and a
   summary per file. -q prints errors only. Exit status: 0 = no errors in
   any file, 1 = errors found, 2 = usage. Never loads theme code. */
#import <Foundation/Foundation.h>
#import "GTSSchemaValidator.h"
#import "GTSThemeSettingsSchema.h"

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int i, status = 0, files = 0;
  BOOL quiet = NO;

  for (i = 1; i < argc; i++)
    {
      NSString *arg = [NSString stringWithUTF8String: argv[i]];
      NSString *path = arg;
      NSArray *findings;
      NSEnumerator *e;
      GTSSchemaFinding *f;
      NSUInteger errors, warnings;
      BOOL isDir = NO;

      if ([arg isEqual: @"-q"]) { quiet = YES; continue; }
      files++;
      if ([[NSFileManager defaultManager] fileExistsAtPath: arg isDirectory: &isDir] && isDir)
        path = [GTSThemeSettingsSchema schemaPathForThemeBundleAtPath: arg];
      if (path == nil)
        {
          printf("%s: ERROR: file: no ThemeSettings.plist in the bundle\n", [arg UTF8String]);
          status = 1;
          continue;
        }
      findings = [GTSSchemaValidator findingsForFile: path];
      errors = [GTSSchemaValidator errorCountInFindings: findings];
      warnings = [findings count] - errors;
      e = [findings objectEnumerator];
      while ((f = [e nextObject]) != nil)
        if ([f isError] || !quiet)
          printf("%s: %s\n", [path UTF8String], [[f description] UTF8String]);
      printf("%s: %lu error(s), %lu warning(s)\n", [path UTF8String],
        (unsigned long)errors, (unsigned long)warnings);
      if (errors > 0) status = 1;
    }
  if (files == 0)
    {
      fprintf(stderr, "usage: gts-validate-schema [-q] <ThemeSettings.plist | Name.theme>...\n");
      status = 2;
    }
  [pool release];
  return status;
}
