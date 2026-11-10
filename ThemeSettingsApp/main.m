/* Theme Settings - standalone configurator: global or one application. */
#import <AppKit/AppKit.h>
#import "GTSThemeSettingsEditor.h"
#import "GTSEditorModel.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSScreenshot.h"

@interface GTSConfigurator : NSObject
{
  NSWindow *_window;
  NSPopUpButton *_target;
  NSMutableArray *_appPaths;      /* parallel to popup items 1..n */
  GTSEditorModel *_model;
  GTSThemeSettingsEditor *_editor;
  NSInteger _lastTarget;
}
- (BOOL) selectApplicationAtPath: (NSString*)path;
@end

@implementation GTSConfigurator

- (NSArray*) installedApplications
{
  NSMutableArray *found = [NSMutableArray array];
  NSEnumerator *e = [NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
    NSAllDomainsMask, YES) objectEnumerator];
  NSString *dir;
  while ((dir = [e nextObject]) != nil)
    {
      NSEnumerator *f = [[[NSFileManager defaultManager] directoryContentsAtPath: dir] objectEnumerator];
      NSString *name;
      while ((name = [f nextObject]) != nil)
        if ([[name pathExtension] isEqual: @"app"])
          [found addObject: [dir stringByAppendingPathComponent: name]];
    }
  return found;
}

- (GTSThemeCatalog*) catalog
{
  NSMutableArray *roots = [[[GTSThemeCatalog defaultSearchRoots] mutableCopy] autorelease];
  NSString *extra = [[NSUserDefaults standardUserDefaults] stringForKey: @"GTSExtraThemeRoot"];
  if ([extra length] > 0)    /* demo/test: themes not installed system-wide */
    [roots addObject: [GTSThemeSearchRoot rootWithPath: extra origin: GTSOriginLocal]];
  return [[[GTSThemeCatalog alloc] initWithSearchRoots: roots] autorelease];
}

- (void) applicationDidFinishLaunching: (NSNotification*)n
{
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSRect frame = NSMakeRect(100, 100, 660, 680);
  NSView *content, *ev;
  NSTextField *l;
  NSEnumerator *e;
  NSString *path, *shot, *preset;

  _model = [[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                         catalog: [self catalog]];
  _editor = [[GTSThemeSettingsEditor alloc] initWithModel: _model];

  _window = [[NSWindow alloc] initWithContentRect: frame
    styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [_window setTitle: @"Theme Settings"];
  content = [_window contentView];

  l = [[[NSTextField alloc] initWithFrame: NSMakeRect(16, frame.size.height - 38, 60, 20)] autorelease];
  [l setStringValue: @"Target:"]; [l setEditable: NO]; [l setBezeled: NO]; [l setDrawsBackground: NO];
  [l setAutoresizingMask: NSViewMinYMargin];
  [content addSubview: l];
  _target = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(80, frame.size.height - 42, 380, 26) pullsDown: NO];
  [_target setAutoresizingMask: NSViewMinYMargin];
  [_target addItemWithTitle: @"All applications"];
  _appPaths = [[NSMutableArray alloc] init];
  e = [[self installedApplications] objectEnumerator];
  while ((path = [e nextObject]) != nil)
    {
      [_target addItemWithTitle: [[path lastPathComponent] stringByDeletingPathExtension]];
      [_appPaths addObject: path];
    }
  [_target addItemWithTitle: @"Other application…"];
  [_target setTarget: self];
  [_target setAction: @selector(targetChanged:)];
  [content addSubview: _target];

  ev = [_editor view];
  [ev setFrame: NSMakeRect(0, 0, frame.size.width, frame.size.height - 52)];
  [content addSubview: ev];

  preset = [ud stringForKey: @"GTSTargetApp"];     /* optional: start on an app */
  if ([preset length] > 0 && [self selectApplicationAtPath: preset])
    {
      NSUInteger i = [_appPaths indexOfObject: preset];
      if (i == NSNotFound)
        {
          [_appPaths addObject: preset];
          [_target insertItemWithTitle: [[preset lastPathComponent] stringByDeletingPathExtension]
                               atIndex: [_appPaths count]];
          i = [_appPaths count] - 1;
        }
      _lastTarget = i + 1;
      [_target selectItemAtIndex: _lastTarget];
    }
  else
    [_model setTargetGlobal];
  [_editor reloadFromModel];
  [_window makeKeyAndOrderFront: self];

  shot = [ud stringForKey: @"GTSScreenshot"];
  if ([shot length] > 0)
    [self performSelector: @selector(screenshotAndQuit:) withObject: shot afterDelay: 1.5];
}

- (BOOL) selectApplicationAtPath: (NSString*)path
{
  GTSApplicationIdentity *ident = [GTSDefaultsDomainStore applicationIdentityForBundleAtPath: path];
  NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
  if (![ident isEstablished]
    && NSRunAlertPanel(@"Confirm settings domain",
      @"%@ does not say which settings domain it uses (%@). Edit settings stored under \"%@\"?",
      @"Edit", @"Cancel", nil, name, [[ident problems] componentsJoinedByString: @"; "],
      [ident domain]) != NSAlertDefaultReturn)
    return NO;
  [_model setTargetApplicationDomain: [ident domain] displayName: name info: [ident infoDictionary]];
  return YES;
}

- (void) targetChanged: (id)sender
{
  NSInteger i = [sender indexOfSelectedItem];
  BOOL ok = YES;
  if ([_model hasChanges]
    && NSRunAlertPanel(@"Unsaved changes", @"Discard the changes you have not applied?",
                       @"Discard", @"Keep editing", nil) != NSAlertDefaultReturn)
    {
      [sender selectItemAtIndex: _lastTarget];
      return;
    }
  if (i == 0)
    [_model setTargetGlobal];
  else if (i <= (NSInteger)[_appPaths count])
    ok = [self selectApplicationAtPath: [_appPaths objectAtIndex: i - 1]];
  else
    {
      NSOpenPanel *op = [NSOpenPanel openPanel];
      [op setCanChooseDirectories: YES];
      [op setCanChooseFiles: NO];
      ok = [op runModalForTypes: nil] == NSOKButton
        && [self selectApplicationAtPath: [op filename]];
    }
  if (!ok)
    [sender selectItemAtIndex: _lastTarget];
  else
    _lastTarget = i;
  [_editor reloadFromModel];
}

- (void) screenshotAndQuit: (NSString*)path
{
  BOOL ok = GTSWriteWindowPNG(_window, path);
  fprintf(stderr, "screenshot %s: %s\n", ok ? "written" : "FAILED", [path UTF8String]);
  [NSApp terminate: self];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (id)sender { return YES; }
@end

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSApplication *app = [NSApplication sharedApplication];
  GTSConfigurator *c = [GTSConfigurator new];
  NSMenu *menu = [[NSMenu new] autorelease];
  [menu addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
  [app setMainMenu: menu];
  [app setDelegate: c];
  [app run];
  [c release];
  [pool release];
  return 0;
}
