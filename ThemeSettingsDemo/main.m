/* Demo host: an ordinary GNUstep app that embeds the SAME
   GTSThemeSettingsEditor as an in-app "Theme Settings" pane. The pane
   edits this app's own defaults domain by default; editing the settings
   for all applications is an explicit switch. */
#import <AppKit/AppKit.h>
#import "GTSThemeSettingsEditor.h"
#import "GTSEditorModel.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSScreenshot.h"
#import "GTSScriptRunner.h"
#import "GTSEditSession.h"
#import "GTSThemeSettingsSchema.h"

@interface GTSDemoHost : NSObject
{
  NSWindow *_main;
  NSPanel *_pane;
  NSButton *_globalSwitch;
  GTSEditorModel *_model;
  GTSThemeSettingsEditor *_editor;
}
@end

@implementation GTSDemoHost

- (NSString*) hostDomain
{
  /* The domain gnustep-base uses for this process. */
  NSString *d = [[NSBundle mainBundle] bundleIdentifier];
  return [d length] ? d : [[NSProcessInfo processInfo] processName];
}

- (GTSThemeCatalog*) catalog
{
  NSMutableArray *roots = [[[GTSThemeCatalog defaultSearchRoots] mutableCopy] autorelease];
  NSString *extra = [[NSUserDefaults standardUserDefaults] stringForKey: @"GTSExtraThemeRoot"];
  if ([extra length] > 0)
    [roots addObject: [GTSThemeSearchRoot rootWithPath: extra origin: GTSOriginLocal]];
  return [[[GTSThemeCatalog alloc] initWithSearchRoots: roots] autorelease];
}

- (void) targetHost
{
  [_model setTargetApplicationDomain: [self hostDomain] displayName: @"This application"
    info: [[NSBundle mainBundle] infoDictionary]];
}

- (void) openThemeSettings: (id)sender
{
  if (_pane == nil)
    {
      NSRect r = NSMakeRect(160, 80, 660, 600);
      NSView *ev;
      GTSDefaultsDomainStore *store = [[[GTSDefaultsDomainStore alloc]
        initWithHostDefaults: [NSUserDefaults standardUserDefaults]] autorelease];
      _model = [[GTSEditorModel alloc] initWithStore: store catalog: [self catalog]];
      NSLog(@"%@", [_model diagnostics]);   /* which defaults root, read/write state */
      [_model setHostDomain: [self hostDomain]];
      [self targetHost];
      _editor = [[GTSThemeSettingsEditor alloc] initWithModel: _model];
      [_editor setDelegate: self];

      _pane = [[NSPanel alloc] initWithContentRect: r
        styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
        backing: NSBackingStoreBuffered defer: NO];
      [_pane setTitle: @"Theme Settings"];
      _globalSwitch = [[NSButton alloc] initWithFrame: NSMakeRect(16, r.size.height - 36, 420, 24)];
      [_globalSwitch setButtonType: NSSwitchButton];
      [_globalSwitch setTitle: @"Change the settings for all applications instead"];
      [_globalSwitch setTarget: self];
      [_globalSwitch setAction: @selector(scopeChanged:)];
      [_globalSwitch setAutoresizingMask: NSViewMinYMargin];
      [[_pane contentView] addSubview: _globalSwitch];
      ev = [_editor view];
      [ev setFrame: NSMakeRect(0, 0, r.size.width, r.size.height - 44)];
      [[_pane contentView] addSubview: ev];
    }
  [_editor reloadFromModel];
  [_pane makeKeyAndOrderFront: self];
}

/* Structured outcome, not message text. The host's own reaction is
   logged here; a real app might offer "Restart now" for restart-level
   changes. It never re-applies. */
- (void) themeSettingsEditor: (GTSThemeSettingsEditor*)editor
     didFinishApplyWithOutcome: (GTSApplyOutcome*)o
{
  static const char *kinds[] = { "saved", "nothing-to-save", "saved-refresh-failed",
    "write-unknown", "conflict", "refused" };
  int req = [o receipt] ? [[o receipt] applyRequirement] : -1;
  fprintf(stderr, "host: apply outcome=%s wrote=%d needsReload=%d requirement=%s\n",
    kinds[[o kind]], [o didWrite], [o needsReload],
    req == GTSApplyRestart ? "restart" : req == GTSApplyNewWindows ? "newWindows"
      : req == GTSApplyLive ? "live" : "none");
}

- (void) scopeChanged: (id)sender
{
  if ([_model hasChanges]
    && NSRunAlertPanel(@"Unsaved changes", @"Discard the changes you have not applied?",
                       @"Discard", @"Keep editing", nil) != NSAlertDefaultReturn)
    {
      [sender setState: [sender state] == NSOnState ? NSOffState : NSOnState];
      return;
    }
  if ([sender state] == NSOnState) [_model setTargetGlobal];
  else [self targetHost];
  [_editor reloadFromModel];
}

- (void) applicationDidFinishLaunching: (NSNotification*)n
{
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSTextView *tv;
  NSString *shot;

  _main = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 120, 520, 360)
    styleMask: NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
    backing: NSBackingStoreBuffered defer: NO];
  [_main setTitle: @"Demo Notes"];
  tv = [[[NSTextView alloc] initWithFrame: [[_main contentView] bounds]] autorelease];
  [tv setString: @"A host application.\n\nTheme Settings… opens the shared theme settings pane "
    @"for this application."];
  [tv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [[_main contentView] addSubview: tv];
  [_main makeKeyAndOrderFront: self];

  if ([ud boolForKey: @"GTSOpenSettings"])
    [self openThemeSettings: self];
  shot = [ud stringForKey: @"GTSScreenshot"];
  if ([[ud stringForKey: @"GTSScript"] length] > 0 && _editor != nil)
    [GTSScriptRunner runScript: [ud stringForKey: @"GTSScript"] editor: _editor window: _pane];
  else if ([shot length] > 0)
    [self performSelector: @selector(screenshotAndQuit:) withObject: shot afterDelay: 1.5];
}

- (void) screenshotAndQuit: (NSString*)path
{
  NSWindow *w = _pane ? (NSWindow*)_pane : _main;
  BOOL ok = GTSWriteWindowPNG(w, path);
  fprintf(stderr, "screenshot %s: %s\n", ok ? "written" : "FAILED", [path UTF8String]);
  [NSApp terminate: self];
}
@end

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSApplication *app = [NSApplication sharedApplication];
  GTSDemoHost *h = [GTSDemoHost new];
  NSMenu *menu = [[NSMenu new] autorelease];
  [menu addItemWithTitle: @"Theme Settings…" action: @selector(openThemeSettings:) keyEquivalent: @","];
  [[menu itemAtIndex: 0] setTarget: h];
  [menu addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
  [app setMainMenu: menu];
  [app setDelegate: h];
  [app run];
  [h release];
  [pool release];
  return 0;
}
