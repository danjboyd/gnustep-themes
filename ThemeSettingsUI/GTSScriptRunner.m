#import "GTSScriptRunner.h"
#import "GTSThemeSettingsEditor.h"
#import "GTSEditorModel.h"
#import "GTSScreenshot.h"

@implementation GTSScriptRunner

+ (void) runScript: (NSString*)script editor: (GTSThemeSettingsEditor*)editor window: (NSWindow*)window
{
  GTSScriptRunner *r = [[self alloc] init];   /* released when done */
  NSEnumerator *e = [[script componentsSeparatedByString: @";"] objectEnumerator];
  NSString *s;
  r->_editor = [editor retain];
  r->_window = [window retain];
  r->_steps = [[NSMutableArray alloc] init];
  while ((s = [e nextObject]) != nil)
    {
      s = [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
      if ([s length]) [r->_steps addObject: s];
    }
  [r performSelector: @selector(next) withObject: nil afterDelay: 1.0];
}

- (void) dealloc
{
  [_editor release]; [_window release]; [_steps release];
  [super dealloc];
}

- (void) next
{
  NSString *step;
  BOOL ok;
  if ([_steps count] == 0)
    {
      fprintf(stderr, "script: done, %d failed step(s)\n", _failures);
      [self autorelease];
      [NSApp terminate: nil];
      return;
    }
  step = [[[_steps objectAtIndex: 0] retain] autorelease];
  [_steps removeObjectAtIndex: 0];
  if ([step hasPrefix: @"wait "])
    {
      /* Let something outside the app happen (tests change GNOME's
         settings meanwhile); the next step runs after that many seconds. */
      double secs = [[step substringFromIndex: 5] doubleValue];
      fprintf(stderr, "script: %s -> ok\n", [step UTF8String]);
      [self performSelector: @selector(next) withObject: nil afterDelay: secs > 0 ? secs : 0.4];
      return;
    }
  if ([step hasPrefix: @"shot "])
    ok = GTSWriteWindowPNG(_window, [step substringFromIndex: 5]);
  else if ([step isEqual: @"log"])
    {
      fprintf(stderr, "script: message: %s\n", [[[_editor model] message] ? [[_editor model] message] : @"" UTF8String]);
      fprintf(stderr, "script: diagnostics: %s\n", [[[_editor model] diagnostics] ? [[_editor model] diagnostics] : @"" UTF8String]);
      ok = YES;
    }
  else
    ok = [_editor performScriptedAction: step];
  if (!ok) _failures++;
  fprintf(stderr, "script: %s -> %s\n", [step UTF8String], ok ? "ok" : "FAILED");
  [self performSelector: @selector(next) withObject: nil afterDelay: 0.4];
}
@end
