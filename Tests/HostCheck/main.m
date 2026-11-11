/* gts-host-check: a disposable AppKit host that drives the REAL
   GTSThemeSettingsEditor (its own controls and its apply: handler) and
   checks the callback contract:
     1. one attempt: legacy didApply first, then the outcome callback, both
        seeing the SAME captured outcome although the host switches target
        inside the first callback;
     2. Apply re-entered from a callback is ignored;
     3. an exception raised by a delegate propagates to the caller, and a
        later Apply still works (guard reset);
     4. invalid text still being typed gives a fresh Refused outcome through
        the outcome callback, no legacy callback, and the stored value is kept.
   Run only through scripts/screenshots.sh (GTS_SHOTS_ONLY=H): private Xvfb,
   verified scratch defaults. Prints CHECK lines; exit status = failures. */
#import <AppKit/AppKit.h>
#import "GTSThemeSettingsEditor.h"
#import "GTSEditorModel.h"
#import "GTSDefaultsDomainStore.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"

@interface GTSThemeSettingsEditor (HostCheck)
- (void) apply: (id)sender;     /* the Apply button's action */
@end

static int failures = 0;

static void
check(BOOL ok, NSString *what)
{
  fprintf(stderr, "CHECK %s: %s\n", ok ? "ok" : "FAILED", [what UTF8String]);
  if (!ok) failures++;
}

@interface HostDelegate : NSObject
{
@public
  GTSThemeSettingsEditor *editor;
  GTSEditorModel *model;
  NSString *domain;
  int mode;                 /* 1 capture, 2 nested, 3 raise, 4 invalid text, 0 plain */
  NSMutableArray *order;    /* callback names in call order */
  GTSApplyOutcome *seenByLegacy, *seenByOutcome;
  BOOL modelClearedBeforeOutcomeCallback;
}
@end

@implementation HostDelegate
- (void) themeSettingsEditorDidApply: (GTSThemeSettingsEditor*)e
{
  [order addObject: @"legacy"];
  ASSIGN(seenByLegacy, [model lastApplyOutcome]);
  if (mode == 1)
    [model setTargetGlobal];   /* host switches target: clears lastApplyOutcome */
}

- (void) themeSettingsEditor: (GTSThemeSettingsEditor*)e didFinishApplyWithOutcome: (GTSApplyOutcome*)o
{
  [order addObject: @"outcome"];
  ASSIGN(seenByOutcome, o);
  modelClearedBeforeOutcomeCallback = ([model lastApplyOutcome] == nil);
  if (mode == 2)
    [editor apply: nil];       /* nested Apply: must be ignored */
  if (mode == 3)
    [NSException raise: @"GTSHostCheckFailure" format: @"deliberate delegate failure"];
}
@end

static void
reset(HostDelegate *d, int mode)
{
  d->mode = mode;
  [d->order removeAllObjects];
  DESTROY(d->seenByLegacy);
  DESTROY(d->seenByOutcome);
  d->modelClearedBeforeOutcomeCallback = NO;
}

static void
retarget(HostDelegate *d)
{
  [d->model setTargetApplicationDomain: d->domain displayName: @"HostCheck" info: nil];
  [d->editor reloadFromModel];
}

/* The font-scale value currently stored in the host's scratch domain. */
static id
storedValue(HostDelegate *d)
{
  GTSDomainSnapshot *s = [[[[GTSDefaultsDomainStore alloc] init] autorelease]
    snapshotForDomain: d->domain error: NULL];
  return [s objectForKey: @"GnomeFontScale"];
}

/* Every NSControl under v, depth first. */
static void
collectControls(NSView *v, NSMutableArray *out)
{
  NSEnumerator *e = [[v subviews] objectEnumerator];
  NSView *sub;
  while ((sub = [e nextObject]) != nil)
    {
      if ([sub isKindOfClass: [NSControl class]]) [out addObject: sub];
      collectControls(sub, out);
    }
}

/* Text of the (only) editable field, and whether Apply is enabled. */
static NSString *
editableFieldText(GTSThemeSettingsEditor *editor)
{
  NSMutableArray *all = [NSMutableArray array];
  NSEnumerator *e;
  NSControl *c;
  collectControls([editor view], all);
  e = [all objectEnumerator];
  while ((c = [e nextObject]) != nil)
    if ([c isKindOfClass: [NSTextField class]] && [(NSTextField*)c isEditable])
      return [c stringValue];
  return nil;
}

static BOOL
applyButtonEnabled(GTSThemeSettingsEditor *editor)
{
  NSMutableArray *all = [NSMutableArray array];
  NSEnumerator *e;
  NSControl *c;
  collectControls([editor view], all);
  e = [all objectEnumerator];
  while ((c = [e nextObject]) != nil)
    if ([c isKindOfClass: [NSButton class]] && [[(NSButton*)c title] isEqual: @"Apply"])
      return [c isEnabled];
  return NO;
}

/* A Return key press, routed the way NSApp routes a key-down
   (gnustep-gui NSApplication.m -sendEvent:, NSKeyDown case): the key
   window's -performKeyEquivalent: first (where the default button
   answers), then the event's window -sendEvent: (the first responder,
   here the field editor). With no window manager the host window cannot
   become key, so that routing is replayed with the host window standing in
   for the key window; mainMenu/servicesMenu are nil here. Returns YES when
   the window really was key and NSApp routed the event itself. */
static BOOL
pressKey(NSWindow *w, NSString *key)
{
  NSEvent *ev = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint
    modifierFlags: 0 timestamp: 0 windowNumber: [w windowNumber] context: nil
    characters: key charactersIgnoringModifiers: key isARepeat: NO keyCode: 0];
  BOOL isKey;
  [w makeKeyWindow];
  isKey = ([NSApp keyWindow] == w);
  if (isKey)
    [NSApp sendEvent: ev];
  else if ([w performKeyEquivalent: ev] == NO)
    [w sendEvent: ev];
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
  fprintf(stderr, "host-check: key routed %s\n",
    isKey ? "by NSApp (window is key)" : "by replaying NSApp's key-down routing (window not key: no window manager)");
  return isKey;
}

static BOOL pressReturn(NSWindow *w) { return pressKey(w, @"\r"); }

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSUserDefaults *ud;
  NSString *root;
  GTSThemeCatalog *catalog;
  GTSEditorModel *model;
  GTSThemeSettingsEditor *editor;
  HostDelegate *d;
  NSWindow *w;
  NSString *colors[] = { @"purple", @"teal" };
  int i;

  [NSApplication sharedApplication];
  ud = [NSUserDefaults standardUserDefaults];
  root = [ud stringForKey: @"GTSExtraThemeRoot"];
  catalog = [[[GTSThemeCatalog alloc] initWithSearchRoots: [NSArray arrayWithObject:
    [GTSThemeSearchRoot rootWithPath: root origin: GTSOriginLocal]]] autorelease];
  model = [[[GTSEditorModel alloc] initWithStore: [[[GTSDefaultsDomainStore alloc] init] autorelease]
                                         catalog: catalog] autorelease];
  editor = [[[GTSThemeSettingsEditor alloc] initWithModel: model] autorelease];
  d = [[HostDelegate new] autorelease];
  d->editor = editor; d->model = model; d->order = [NSMutableArray array];
  d->domain = [ud stringForKey: @"GTSHostDomain"];
  [editor setDelegate: d];
  w = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 660, 600)
    styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
  [[w contentView] addSubview: [editor view]];
  [w makeKeyAndOrderFront: nil];
  retarget(d);

  /* 1. capture across a target switch in the legacy callback */
  reset(d, 1);
  check([editor performScriptedAction: @"choose adwaita.accent-color purple"], @"1 staged a change through the popup");
  [editor apply: nil];
  check([d->order isEqual: [NSArray arrayWithObjects: @"legacy", @"outcome", nil]],
    [NSString stringWithFormat: @"1 order legacy then outcome (%@)", [d->order componentsJoinedByString: @","]]);
  check(d->seenByLegacy != nil && d->seenByLegacy == d->seenByOutcome,
    @"1 both callbacks saw the same outcome object");
  check([d->seenByOutcome kind] == GTSApplyOutcomeSaved, @"1 outcome kind Saved");
  check(d->modelClearedBeforeOutcomeCallback,
    @"1 host's target switch cleared the model's outcome, yet the callback got the captured one");

  /* 2. nested Apply ignored */
  retarget(d);
  reset(d, 2);
  [editor performScriptedAction: @"choose adwaita.accent-color teal"];
  [editor apply: nil];
  check([d->order isEqual: [NSArray arrayWithObjects: @"legacy", @"outcome", nil]],
    [NSString stringWithFormat: @"2 nested Apply ignored: one callback pair (%@)", [d->order componentsJoinedByString: @","]]);

  /* 3. delegate exception propagates; later Apply still works */
  reset(d, 3);
  [editor performScriptedAction: @"choose adwaita.accent-color purple"];
  {
    BOOL raised = NO;
    @try { [editor apply: nil]; }
    @catch (NSException *x) { raised = [[x name] isEqual: @"GTSHostCheckFailure"]; }
    check(raised, @"3 delegate exception propagated to the caller");
  }
  reset(d, 0);
  for (i = 0; i < 2 && [d->order count] == 0; i++)
    {
      /* stage something different from what is stored, then apply */
      [editor performScriptedAction: [NSString stringWithFormat: @"choose adwaita.accent-color %@", colors[i]]];
      [editor apply: nil];
    }
  check([d->order containsObject: @"outcome"], @"3 a later Apply ran its callbacks (guard was reset)");

  /* 4. invalid text being typed: fresh Refused, outcome callback only, and
     the stored value survives (an emptied pending text would mean Reset) */
  reset(d, 0);
  check([editor performScriptedAction: @"type adwaita.font-scale 1.25"], @"4 typed a valid value");
  [editor apply: nil];
  check([d->seenByOutcome kind] == GTSApplyOutcomeSaved, @"4 valid typed value saved first");
  retarget(d);
  reset(d, 0);
  check([editor performScriptedAction: @"type adwaita.font-scale 3"], @"4 typed into the text field (uncommitted)");
  [editor apply: nil];
  check([d->order isEqual: [NSArray arrayWithObject: @"outcome"]],
    [NSString stringWithFormat: @"4 outcome callback only, no legacy (%@)", [d->order componentsJoinedByString: @","]]);
  check([d->seenByOutcome kind] == GTSApplyOutcomeRefused
    && [[d->seenByOutcome error] code] == GTSErrorInvalidArgument,
    [NSString stringWithFormat: @"4 fresh Refused/InvalidArgument (%@)", [[d->seenByOutcome error] localizedDescription]]);
  {
    GTSDomainSnapshot *s = [[[[GTSDefaultsDomainStore alloc] init] autorelease]
      snapshotForDomain: d->domain error: NULL];
    check([[s objectForKey: @"GnomeFontScale"] isEqual: @"1.25"],
      [NSString stringWithFormat: @"4 stored value kept (%@), invalid text not written or reset",
        [s objectForKey: @"GnomeFontScale"]]);
  }

  /* 5. control tags: the theme popup's tag is not shared by any row control,
     and choosing in the first row's popup never touches the theme popup */
  {
    NSMutableArray *all = [NSMutableArray array];
    NSEnumerator *e;
    NSControl *c, *theme = nil;
    NSInteger themeIndex = [model selectedThemeIndex], sameTag = 0, themePopups = 0;
    collectControls([editor view], all);
    e = [all objectEnumerator];
    while ((c = [e nextObject]) != nil)
      if ([c isKindOfClass: [NSPopUpButton class]] && sel_isEqual([c action], @selector(themeChanged:)))
        { theme = c; themePopups++; }
    e = [all objectEnumerator];
    while ((c = [e nextObject]) != nil)
      if (c != theme && theme != nil && [c tag] == [theme tag] && [c target] == editor)
        sameTag++;
    check(themePopups == 1 && sameTag == 0,
      [NSString stringWithFormat: @"5 theme popup tag %ld unique among editor controls (%ld popup(s), %ld clash(es))",
        (long)[theme tag], (long)themePopups, (long)sameTag]);
    retarget(d);
    check([editor performScriptedAction: @"choose adwaita.color-scheme force-dark"]
      && [model selectedThemeIndex] == themeIndex
      && [[(NSPopUpButton*)theme titleOfSelectedItem] isEqual:
           [[[model themeChoices] objectAtIndex: themeIndex] title]],
      @"5 first-row popup staged its own change; theme selection unchanged");
    [editor performScriptedAction: @"cancel"];
  }

  /* 6. Return while a free-form field is still being edited. NSApp offers
     the key to the key window's key equivalents first, so Apply (the
     default button, key equivalent Return) runs with the text uncommitted;
     the editor must pick that text up (pendingTexts), not lose it. */
  retarget(d);
  reset(d, 0);
  check([editor performScriptedAction: @"type adwaita.font-scale 1.5"], @"6 typed a valid value (uncommitted)");
  pressReturn(w);
  check([d->order isEqual: [NSArray arrayWithObjects: @"legacy", @"outcome", nil]]
    && [d->seenByOutcome kind] == GTSApplyOutcomeSaved
    && [[storedValue(d) description] isEqual: @"1.5"] && ![model hasChanges],
    [NSString stringWithFormat: @"6 one Return applied the typed text: Saved, stored %@ (callbacks: %@)",
      storedValue(d), [d->order componentsJoinedByString: @","]]);
  retarget(d);
  reset(d, 0);
  check([editor performScriptedAction: @"type adwaita.font-scale 3"], @"6 typed an invalid value (uncommitted)");
  pressReturn(w);
  {
    /* Invalid text stages nothing, so Apply is disabled and its key
       equivalent does not fire; Return goes to the field, whose action is
       refused. The typed text stays, selected, with the model's message;
       nothing is written. Leaving the field (Tab) restores the stored value. */
    NSString *shows = editableFieldText(editor);
    NSResponder *fr = [w firstResponder];
    NSRange sel = [fr isKindOfClass: [NSTextView class]] ? [(NSTextView*)fr selectedRange] : NSMakeRange(0, 0);
    check([d->order count] == 0 && !applyButtonEnabled(editor) && ![model hasChanges]
      && [[storedValue(d) description] isEqual: @"1.5"],
      [NSString stringWithFormat: @"6 invalid text on Return: Apply disabled, no callbacks, stored %@ kept (callbacks: %@)",
        storedValue(d), [d->order componentsJoinedByString: @","]]);
    check([shows isEqual: @"3"] && sel.location == 0 && sel.length == 1
      && [[model message] rangeOfString: @"outside"].location != NSNotFound,
      [NSString stringWithFormat: @"6 typed text kept and selected (field \"%@\", selection %lu+%lu in %@), message \"%@\"",
        shows, (unsigned long)sel.location, (unsigned long)sel.length,
        NSStringFromClass([fr class]), [model message]]);
    pressKey(w, @"\t");
    check([editableFieldText(editor) isEqual: @"1.5"] && [[storedValue(d) description] isEqual: @"1.5"],
      [NSString stringWithFormat: @"6 leaving the field restores the stored value (field \"%@\", stored %@)",
        editableFieldText(editor), storedValue(d)]);
  }

  fprintf(stderr, "host-check: %d failure(s)\n", failures);
  [pool release];
  return failures;
}
