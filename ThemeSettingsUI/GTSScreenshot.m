#import "GTSScreenshot.h"

BOOL GTSWriteWindowPNG(NSWindow *window, NSString *path)
{
  NSView *v = [window contentView];
  NSBitmapImageRep *rep;
  NSData *png;
  [window display];
  [v lockFocus];
  rep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect: [v bounds]] autorelease];
  [v unlockFocus];
  png = [rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]];
  return png != nil && [png writeToFile: path atomically: YES];
}
