/* Control for screenshots.sh scenario M: a plain AppKit app that does NOT
   pin its theme. It logs the theme it starts with and every theme libs-gui
   activates afterwards, then quits after -GTSProbeSeconds (default 45). */
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSTheme.h>

@interface Probe : NSObject
@end
@implementation Probe
- (void) activated: (NSNotification*)n
{
  fprintf(stderr, "probe: theme now %s\n", [[[GSTheme theme] name] UTF8String]);
}
- (void) applicationDidFinishLaunching: (NSNotification*)n
{
  float s = [[NSUserDefaults standardUserDefaults] floatForKey: @"GTSProbeSeconds"];
  fprintf(stderr, "probe: started with theme %s\n", [[[GSTheme theme] name] UTF8String]);
  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(activated:)
                                               name: GSThemeDidActivateNotification object: nil];
  [NSApp performSelector: @selector(terminate:) withObject: nil afterDelay: s > 0 ? s : 45];
}
@end

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSApplication *app = [NSApplication sharedApplication];
  Probe *p = [Probe new];
  NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 200, 80)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [app setDelegate: p];
  [w orderFront: nil];
  [app run];
  [pool release];
  return 0;
}
