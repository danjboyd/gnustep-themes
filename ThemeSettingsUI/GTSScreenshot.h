/* GTSScreenshot.h - write a window's rendered content to a PNG, for
   reviewable screenshots from a private display. */
#import <AppKit/AppKit.h>
BOOL GTSWriteWindowPNG(NSWindow *window, NSString *path);
