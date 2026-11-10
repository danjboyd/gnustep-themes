/* gts-external-host: smoke test of the INSTALLED interface. Uses only the
   umbrella headers and public API (no private categories), embeds the
   editor in a window, applies one change, and reports where the editor and
   model code were loaded from. Prints CHECK lines; exit status = failures. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#import <AppKit/AppKit.h>
#import <ThemeSettingsKit/ThemeSettingsKit.h>
#import <ThemeSettingsUI/ThemeSettingsUI.h>

static int failures = 0;
static void check(BOOL ok, NSString *what)
{
  fprintf(stderr, "CHECK %s: %s\n", ok ? "ok" : "FAILED", [what UTF8String]);
  if (!ok) failures++;
}

/* Path of the shared object that defines cls's -sel. */
static NSString *loadedFrom(Class cls, SEL sel)
{
  Dl_info info;
  IMP imp = [cls instanceMethodForSelector: sel];
  if (imp == NULL || dladdr((void*)imp, &info) == 0 || info.dli_fname == NULL) return @"?";
  return [[NSString stringWithUTF8String: info.dli_fname] stringByResolvingSymlinksInPath];
}

@interface Host : NSObject
{
@public
  GTSApplyOutcome *outcome;
  int calls;
}
@end
@implementation Host
- (void) themeSettingsEditor: (GTSThemeSettingsEditor*)e didFinishApplyWithOutcome: (GTSApplyOutcome*)o
{
  calls++;
  ASSIGN(outcome, o);
}
@end

int main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSUserDefaults *ud;
  NSString *lib, *domain, *ui, *kit;
  GTSThemeCatalog *catalog;
  GTSEditorModel *model;
  GTSThemeSettingsEditor *editor;
  GTSDomainSnapshot *s;
  NSWindow *w;
  Host *h;

  [NSApplication sharedApplication];
  ud = [NSUserDefaults standardUserDefaults];
  lib = [[ud stringForKey: @"GTSStageLib"] stringByResolvingSymlinksInPath];
  domain = [ud stringForKey: @"GTSHostDomain"];

  ui = loadedFrom([GTSThemeSettingsEditor class], @selector(reloadFromModel));
  kit = loadedFrom([GTSEditorModel class], @selector(lastApplyOutcome));
  fprintf(stderr, "external-host: editor code from %s\n", [ui UTF8String]);
  fprintf(stderr, "external-host: model code from %s\n", [kit UTF8String]);
  check([lib length] > 0 && [[ui stringByDeletingLastPathComponent] isEqual: lib]
    && [[ui lastPathComponent] hasPrefix: @"libThemeSettingsUI.so"], @"I editor loaded from the staged libThemeSettingsUI");
  check([lib length] > 0 && [[kit stringByDeletingLastPathComponent] isEqual: lib]
    && [[kit lastPathComponent] hasPrefix: @"libThemeSettingsKit.so"], @"I model loaded from the staged libThemeSettingsKit");

  catalog = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: [ud stringForKey: @"GTSExtraThemeRoot"] origin: GTSOriginLocal]]] autorelease];
  model = [[[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                         catalog: catalog] autorelease];
  check([model setTargetApplicationDomain: domain displayName: @"External host" info: nil],
    @"I target set to the host's scratch domain");
  editor = [[[GTSThemeSettingsEditor alloc] initWithModel: model] autorelease];
  h = [[Host new] autorelease];
  [editor setDelegate: h];
  w = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 660, 600)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [[w contentView] addSubview: [editor view]];
  [w makeKeyAndOrderFront: nil];

  check([editor performScriptedAction: @"choose adwaita.accent-color purple"], @"I staged a change through the editor's popup");
  check([editor performScriptedAction: @"apply"], @"I pressed Apply");
  check(h->calls == 1 && [h->outcome kind] == GTSApplyOutcomeSaved && [h->outcome didWrite],
    [NSString stringWithFormat: @"I one outcome callback, kind Saved (calls %d, kind %d)", h->calls, (int)[h->outcome kind]]);
  s = [[[[GTSDefaultsDomainStore alloc] init] autorelease] snapshotForDomain: domain error: NULL];
  check([[s objectForKey: @"GnomeThemeAccentColor"] isEqual: @"purple"],
    [NSString stringWithFormat: @"I fresh read-back GnomeThemeAccentColor = %@", [s objectForKey: @"GnomeThemeAccentColor"]]);

  fprintf(stderr, "external-host: %d failure(s)\n", failures);
  [w close];
  [pool release];
  return failures;
}
