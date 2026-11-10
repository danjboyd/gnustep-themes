/* GTSScriptRunner.h - runs "-GTSScript" steps against an editor for
   reviewable screenshots: editor actions (see -performScriptedAction:),
   "shot <path>" and "log". Each step's result goes to stderr; the app
   terminates after the last step. A step that fails is reported, not
   skipped silently. */
#import <AppKit/AppKit.h>
@class GTSThemeSettingsEditor;

@interface GTSScriptRunner : NSObject
{
  GTSThemeSettingsEditor *_editor;
  NSWindow *_window;
  NSMutableArray *_steps;
  int _failures;
}
+ (void) runScript: (NSString*)script editor: (GTSThemeSettingsEditor*)editor window: (NSWindow*)window;
@end
