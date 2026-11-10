/* GTSSchemaValidator.h - strict checker for ThemeSettings.plist (schema v1)
   for theme owners and CI. Foundation only; never loads theme code.

   Two layers, both reported as findings:
   1. The loader (GTSThemeSettingsSchema) is the ground truth for what an
      editor will do: a file it rejects, or a setting it skips (a loader
      "warning"), is an ERROR here, because the setting silently disappears
      from every editor.
   2. Strict checks for things the loader accepts without checking (it
      copies them or ignores them), where a mistake changes behaviour
      silently: dangling DependsOn/Overlaps/Group references, a Status typo
      that makes an entry public, non-numeric Minimum/Maximum, duplicate
      Keys or enum values, precedence filters naming values that do not
      exist. Unknown keys are WARNINGS (v1 readers ignore them; see
      docs/schema-v1.md "Compatibility").
   An empty error list means: v1 readers load every setting as written.
   It does not check that the theme really reads these keys. */
#import <Foundation/Foundation.h>

typedef enum {
  GTSFindingError = 0,
  GTSFindingWarning = 1
} GTSFindingSeverity;

@interface GTSSchemaFinding : NSObject
{
  GTSFindingSeverity _severity;
  NSString *_where;     /* setting Identifier, "Groups", or "file" */
  NSString *_message;
}
+ (id) findingWithSeverity: (GTSFindingSeverity)s where: (NSString*)where message: (NSString*)message;
- (GTSFindingSeverity) severity;
- (BOOL) isError;
- (NSString*) where;
- (NSString*) message;
@end

@interface GTSSchemaValidator : NSObject
/* Reads the file the way the loader does (text property list). */
+ (NSArray*) findingsForFile: (NSString*)path;
+ (NSArray*) findingsForPropertyList: (id)plist path: (NSString*)path;
+ (NSUInteger) errorCountInFindings: (NSArray*)findings;
@end
