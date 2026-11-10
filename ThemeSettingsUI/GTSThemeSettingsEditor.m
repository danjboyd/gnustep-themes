/* GTSThemeSettingsEditor.m */
#import "GTSThemeSettingsEditor.h"
#import "GTSEditorModel.h"
#import "GTSThemeCatalog.h"
#import "GTSThemeSettingsSchema.h"

/* Plain flipped container so rows lay out top-down. */
@interface GTSFlippedView : NSView
@end
@implementation GTSFlippedView
- (BOOL) isFlipped { return YES; }
@end

static const float kMargin = 16, kLabelW = 170, kControlW = 330, kResetW = 70, kGap = 8;

static NSTextField *
label(NSString *text, float size, BOOL bold, NSColor *color)
{
  NSTextField *t = [[[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)] autorelease];
  [t setStringValue: text ? text : @""];
  [t setEditable: NO];
  [t setSelectable: NO];
  [t setBezeled: NO];
  [t setDrawsBackground: NO];
  [t setFont: bold ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size]];
  if (color) [t setTextColor: color];
  return t;
}

/* Height a wrapping label needs at a given width (rough but stable). */
static float
wrappedHeight(NSString *text, float width, float size)
{
  NSDictionary *a = [NSDictionary dictionaryWithObject: [NSFont systemFontOfSize: size]
                                                forKey: NSFontAttributeName];
  NSEnumerator *e = [[text componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString *para;
  int lines = 0;
  while ((para = [e nextObject]) != nil)   /* each paragraph wraps on its own */
    lines += (int)([para sizeWithAttributes: a].width / (width - 8)) + 1;
  return lines * (size + 5) + 2;
}

@interface GTSThemeSettingsEditor (Private)
- (NSView*) firstPopup;
- (void) refreshButtons;
- (NSArray*) editableFields;
- (NSArray*) pendingTexts;
@end

@implementation GTSThemeSettingsEditor

- (id) initWithModel: (GTSEditorModel*)model
{
  NSRect frame = NSMakeRect(0, 0, kMargin * 2 + kLabelW + kControlW + kResetW + kGap * 2, 460);
  /* The editor only renders a GTSEditorModel. This class reference is also
     what records libThemeSettingsKit as a NEEDED dependency of the shared
     UI library (message sends alone would let --as-needed drop it). */
  if (![model isKindOfClass: [GTSEditorModel class]])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
                  format: @"GTSThemeSettingsEditor needs a GTSEditorModel"];
    }
  if ((self = [super init]) == nil) return nil;
  _model = [model retain];

  _view = [[NSView alloc] initWithFrame: frame];
  [_view setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

  _scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 64, frame.size.width, frame.size.height - 64)];
  [_scroll setHasVerticalScroller: YES];
  [_scroll setBorderType: NSNoBorder];
  [_scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  _content = [[GTSFlippedView alloc] initWithFrame: NSMakeRect(0, 0, frame.size.width - 20, 400)];
  [_scroll setDocumentView: _content];
  [_view addSubview: _scroll];

  _message = [label(@"", 11, NO, [NSColor darkGrayColor]) retain];
  [[_message cell] setWraps: YES];
  [_message setFrame: NSMakeRect(kMargin, 4, frame.size.width - 300, 56)];
  [_message setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
  [_view addSubview: _message];

  _reload = [[NSButton alloc] initWithFrame: NSMakeRect(frame.size.width - 270, 12, 80, 26)];
  [_reload setTitle: @"Reload"];
  [_reload setTarget: self];
  [_reload setAction: @selector(reload:)];
  [_reload setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
  [_view addSubview: _reload];

  _cancel = [[NSButton alloc] initWithFrame: NSMakeRect(frame.size.width - 182, 12, 80, 26)];
  [_cancel setTitle: @"Cancel"];
  [_cancel setTarget: self];
  [_cancel setAction: @selector(cancel:)];
  [_cancel setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
  [_view addSubview: _cancel];

  _apply = [[NSButton alloc] initWithFrame: NSMakeRect(frame.size.width - 94, 12, 80, 26)];
  [_apply setTitle: @"Apply"];
  [_apply setTarget: self];
  [_apply setAction: @selector(apply:)];
  [_apply setKeyEquivalent: @"\r"];
  [_apply setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
  [_view addSubview: _apply];

  [self reloadFromModel];
  return self;
}

- (void) dealloc
{
  [_model release]; [_view release]; [_content release]; [_scroll release];
  [_message release]; [_apply release]; [_cancel release]; [_reload release];
  [_rows release];
  [super dealloc];
}

- (GTSEditorModel*) model { return _model; }
- (NSView*) view { return _view; }
- (void) setDelegate: (id)delegate { _delegate = delegate; }

- (NSPopUpButton*) popupWithChoices: (NSArray*)choices selected: (NSInteger)sel frame: (NSRect)f
{
  NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame: f pullsDown: NO] autorelease];
  NSEnumerator *e = [choices objectEnumerator];
  GTSChoice *c;
  while ((c = [e nextObject]) != nil)
    [p addItemWithTitle: [c title]];
  if (sel >= 0 && sel < [p numberOfItems]) [p selectItemAtIndex: sel];
  return p;
}

- (void) reloadFromModel
{
  NSArray *subviews = [[[_content subviews] copy] autorelease];
  NSEnumerator *e = [subviews objectEnumerator];
  NSView *v;
  float width = [_content frame].size.width;
  float y = kMargin, x2 = kMargin + kLabelW + kGap, x3 = x2 + kControlW + kGap;
  NSTextField *t;
  NSPopUpButton *p;
  NSString *note;
  NSUInteger i;
  BOOL editable = [_model isEditable];

  while ((v = [e nextObject]) != nil)
    [v removeFromSuperview];

  /* Target */
  t = label([NSString stringWithFormat: @"Settings for: %@", [_model targetTitle]], 13, YES, nil);
  [t setFrame: NSMakeRect(kMargin, y, width - 2 * kMargin, 20)];
  [_content addSubview: t];
  y += 30;

  /* Theme selection (independent of every setting) */
  t = label(@"Theme", 12, YES, nil);
  [t setFrame: NSMakeRect(kMargin, y + 3, kLabelW, 20)];
  [_content addSubview: t];
  p = [self popupWithChoices: [_model themeChoices] selected: [_model selectedThemeIndex]
                       frame: NSMakeRect(x2, y, kControlW, 26)];
  [p setTarget: self];
  [p setAction: @selector(themeChanged:)];
  [p setEnabled: editable];
  [_content addSubview: p];
  {
    /* Seeded-theme states can be a sentence or two: wrap, don't clip. */
    float h = wrappedHeight([_model themeStateText], kControlW + kResetW, 10);
    t = label([_model themeStateText], 10, NO, [NSColor grayColor]);
    [[t cell] setWraps: YES];
    [t setFrame: NSMakeRect(x2, y + 27, kControlW + kResetW, h)];
    [_content addSubview: t];
    y += 30 + (h > 16 ? h : 16);
  }
  note = [_model themeNote];
  if ([note length] > 0)
    {
      float h = wrappedHeight(note, width - x2 - kMargin, 10);
      t = label(note, 10, NO, [NSColor darkGrayColor]);
      [[t cell] setWraps: YES];
      [t setFrame: NSMakeRect(x2, y, width - x2 - kMargin, h)];
      [_content addSubview: t];
      y += h + 4;
    }
  y += 8;

  /* Settings of the theme that applies to this target */
  ASSIGN(_rows, [_model rows]);
  if ([_rows count] > 0)
    {
      NSBox *sep = [[[NSBox alloc] initWithFrame: NSMakeRect(kMargin, y, width - 2 * kMargin, 1)] autorelease];
      [sep setBoxType: NSBoxSeparator];
      [_content addSubview: sep];
      y += 12;
    }
  for (i = 0; i < [_rows count]; i++)
    {
      GTSSettingRow *row = [_rows objectAtIndex: i];
      BOOL rowEditable = editable && ![row isReadOnly];
      NSButton *reset;

      t = label([row title], 12, NO, nil);
      [t setFrame: NSMakeRect(kMargin, y + 3, kLabelW, 20)];
      [_content addSubview: t];

      if ([row isFreeForm])
        {
          NSTextField *f = [[[NSTextField alloc] initWithFrame: NSMakeRect(x2, y, kControlW, 24)] autorelease];
          [f setStringValue: [row text] ? [row text] : @""];
          [[f cell] setPlaceholderString: [[[row choices] objectAtIndex: 0] title]];
          [f setTag: i];
          [f setTarget: self];
          [f setAction: @selector(textChanged:)];
          [f setDelegate: self];          /* stage on every keystroke, see controlTextDidChange: */
          [f setEnabled: rowEditable];
          [_content addSubview: f];
        }
      else
        {
          p = [self popupWithChoices: [row choices] selected: [row selectedIndex]
                               frame: NSMakeRect(x2, y, kControlW, 26)];
          [p setTag: i];
          [p setTarget: self];
          [p setAction: @selector(choiceChanged:)];
          [p setEnabled: rowEditable];
          [_content addSubview: p];
        }

      reset = [[[NSButton alloc] initWithFrame: NSMakeRect(x3, y, kResetW, 26)] autorelease];
      [reset setTitle: @"Reset"];
      [reset setTag: i];
      [reset setTarget: self];
      [reset setAction: @selector(resetRow:)];
      [reset setEnabled: rowEditable && [row canReset]];
      [_content addSubview: reset];

      t = label([row stateText], 10, NO, [NSColor grayColor]);
      [t setFrame: NSMakeRect(x2, y + 27, kControlW + kResetW, 16)];
      [_content addSubview: t];
      y += 44;
      if ([[row note] length] > 0)
        {
          float h = wrappedHeight([row note], width - x2 - kMargin, 10);
          t = label([row note], 10, NO, [NSColor darkGrayColor]);
          [[t cell] setWraps: YES];
          [t setFrame: NSMakeRect(x2, y, width - x2 - kMargin, h)];
          [_content addSubview: t];
          y += h;
        }
      y += 10;
    }

  [_content setFrameSize: NSMakeSize(width, y + kMargin)];
  [_content setNeedsDisplay: YES];
  [self refreshButtons];
}

/* Message + button state only; never rebuilds the rows, so an active
   field editor survives. */
- (void) refreshButtons
{
  [_message setStringValue: [_model message] ? [_model message] : @""];
  [_apply setEnabled: [_model isEditable] && [_model hasChanges]];
  [_cancel setEnabled: [_model hasChanges]];
}

/* Editable free-form fields (labels are NSTextFields too, but not editable). */
- (NSArray*) editableFields
{
  NSMutableArray *a = [NSMutableArray array];
  NSEnumerator *e = [[_content subviews] objectEnumerator];
  NSView *v;
  while ((v = [e nextObject]) != nil)
    if ([v isKindOfClass: [NSTextField class]] && [(NSTextField*)v isEditable])
      [a addObject: v];
  return a;
}

/* Text currently shown in a field, including uncommitted field-editor text. */
static NSString *
fieldText(NSTextField *f)
{
  /* Copy: the field editor's string is live storage and is emptied when
     editing ends (makeFirstResponder: nil), which would turn the typed text
     into "" -- i.e. a Reset -- before the model sees it. */
  NSText *ed = [f currentEditor];
  return [[(ed ? [ed string] : [f stringValue]) copy] autorelease];
}

/* Stage what every free-form field shows. NO if any value is invalid
   (the model's message says why); nothing is staged for that field. */
/* (row, visible text) for every editable field, including text still in
   the field editor. */
- (NSArray*) pendingTexts
{
  NSMutableArray *a = [NSMutableArray array];
  NSEnumerator *e = [[self editableFields] objectEnumerator];
  NSTextField *f;
  while ((f = [e nextObject]) != nil)
    [a addObject: [NSArray arrayWithObjects: [_rows objectAtIndex: [f tag]], fieldText(f), nil]];
  return a;
}

- (void) controlTextDidChange: (NSNotification*)n
{
  NSTextField *f = [n object];
  [_model setText: fieldText(f) forRow: [_rows objectAtIndex: [f tag]]];
  [self refreshButtons];
}

- (NSControl*) controlOfClass: (Class)c tag: (NSInteger)tag title: (NSString*)title
{
  NSEnumerator *e = [[_content subviews] objectEnumerator];
  NSView *v;
  while ((v = [e nextObject]) != nil)
    if ([v isKindOfClass: c] && (tag < 0 || [(NSControl*)v tag] == tag)
      && (title == nil || [[(NSButton*)v title] isEqual: title]))
      return (NSControl*)v;
  return nil;
}

- (NSInteger) rowIndexForSetting: (NSString*)ident
{
  NSUInteger i;
  for (i = 0; i < [_rows count]; i++)
    if ([[[[_rows objectAtIndex: i] setting] identifier] isEqual: ident]) return i;
  return -1;
}

- (BOOL) performScriptedAction: (NSString*)action
{
  NSArray *w = [action componentsSeparatedByString: @" "];
  NSString *verb = [w count] ? [w objectAtIndex: 0] : @"";
  NSControl *c = nil;

  if ([verb isEqual: @"apply"]) c = _apply;
  else if ([verb isEqual: @"cancel"]) c = _cancel;
  else if ([verb isEqual: @"reload"]) c = _reload;
  if (c != nil)
    {
      if (![c isEnabled]) return NO;
      [(NSButton*)c performClick: self];
      return YES;
    }
  if ([verb isEqual: @"theme"] && [w count] == 2)
    {
      NSArray *vals = [[_model themeChoices] valueForKey: @"value"];
      NSUInteger i = [vals indexOfObject: [w objectAtIndex: 1]];
      NSPopUpButton *p = (NSPopUpButton*)[self firstPopup];   /* theme popup is laid out first */
      if (i == NSNotFound || p == nil || ![p isEnabled]) return NO;
      [p selectItemAtIndex: i];
      [p sendAction: [p action] to: [p target]];
      return YES;
    }
  if ([verb isEqual: @"type"] && [w count] >= 3)
    {
      /* Click into the field and type, leaving the edit uncommitted. */
      NSInteger r = [self rowIndexForSetting: [w objectAtIndex: 1]];
      NSString *text = [[w subarrayWithRange: NSMakeRange(2, [w count] - 2)] componentsJoinedByString: @" "];
      NSEnumerator *e = [[self editableFields] objectEnumerator];
      NSTextField *f = nil, *x;
      NSText *ed;
      while ((x = [e nextObject]) != nil)
        if ([x tag] == r) f = x;
      if (r < 0 || f == nil || ![f isEnabled]) return NO;
      [[_view window] makeFirstResponder: f];
      ed = [f currentEditor];
      if (ed == nil) return NO;
      [ed selectAll: nil];
      [ed insertText: text];
      return YES;
    }
  if (([verb isEqual: @"choose"] && [w count] >= 3) || ([verb isEqual: @"reset"] && [w count] == 2))
    {
      NSInteger r = [self rowIndexForSetting: [w objectAtIndex: 1]];
      GTSSettingRow *row;
      if (r < 0) return NO;
      row = [_rows objectAtIndex: r];
      if ([verb isEqual: @"reset"])
        c = [self controlOfClass: [NSButton class] tag: r title: @"Reset"];
      else
        {
          NSString *val = [[w subarrayWithRange: NSMakeRange(2, [w count] - 2)] componentsJoinedByString: @" "];
          NSUInteger i, n = [[row choices] count];
          NSEnumerator *e = [[_content subviews] objectEnumerator];
          NSView *v;
          NSPopUpButton *p = nil;
          /* row popups come after the theme popup; match by tag */
          while ((v = [e nextObject]) != nil)
            if ([v isKindOfClass: [NSPopUpButton class]] && [(NSControl*)v tag] == r && v != [self firstPopup])
              p = (NSPopUpButton*)v;
          for (i = 0; i < n; i++)
            if ([[[[row choices] objectAtIndex: i] value] isEqual: val]) break;
          if (p == nil || i == n || ![p isEnabled]) return NO;
          [p selectItemAtIndex: i];
          [p sendAction: [p action] to: [p target]];
          return YES;
        }
      if (c == nil || ![c isEnabled]) return NO;
      [(NSButton*)c performClick: self];
      return YES;
    }
  return NO;
}

- (NSView*) firstPopup
{
  NSEnumerator *e = [[_content subviews] objectEnumerator];
  NSView *v;
  while ((v = [e nextObject]) != nil)
    if ([v isKindOfClass: [NSPopUpButton class]]) return v;
  return nil;
}

- (void) themeChanged: (id)sender
{
  [_model selectThemeChoiceAtIndex: [sender indexOfSelectedItem]];
  [self reloadFromModel];
}

- (void) choiceChanged: (id)sender
{
  GTSSettingRow *row = [_rows objectAtIndex: [sender tag]];
  [_model selectChoiceAtIndex: [sender indexOfSelectedItem] forRow: row];
  [self reloadFromModel];
}

- (void) textChanged: (id)sender
{
  GTSSettingRow *row = [_rows objectAtIndex: [sender tag]];
  [_model setText: [sender stringValue] forRow: row];
  [self reloadFromModel];
}

- (void) resetRow: (id)sender
{
  [_model resetRow: [_rows objectAtIndex: [sender tag]]];
  [self reloadFromModel];
}

- (void) apply: (id)sender
{
  GTSApplyOutcome *o;
  NSArray *pending;

  /* A host calling back into Apply from a callback is ignored: one attempt
     at a time, each with its own outcome. */
  if (_applying) return;
  _applying = YES;
  /* Reset the guard however we leave: an exception from the model, the view
     or a host callback must not disable Apply for good. Not swallowed. */
  @try
    {
      /* End editing, then hand every field's visible text to the model, which
         stages it or records a fresh Refused outcome (invalid text) and stops. */
      pending = [self pendingTexts];
      [[_view window] makeFirstResponder: nil];
      [_model applyWithPendingTexts: pending];
      /* Capture THIS attempt's outcome before any callback runs: a host that
         edits or switches target inside one callback must not change what the
         other receives. */
      o = [[[_model lastApplyOutcome] retain] autorelease];
      [self reloadFromModel];
      if (_delegate != nil)
        {
          /* Legacy: "something was written" (Saved or SavedRefreshFailed). It is
             NOT proof that reload or live application succeeded; the outcome is
             the authority. */
          if ([o didWrite] && [_delegate respondsToSelector: @selector(themeSettingsEditorDidApply:)])
            [_delegate themeSettingsEditorDidApply: self];
          if (o != nil && [_delegate respondsToSelector: @selector(themeSettingsEditor:didFinishApplyWithOutcome:)])
            [_delegate themeSettingsEditor: self didFinishApplyWithOutcome: o];
        }
    }
  @finally
    {
      _applying = NO;
    }
}

- (void) cancel: (id)sender
{
  [_model cancel];
  [self reloadFromModel];
}

- (void) reload: (id)sender
{
  [_model reload];
  [self reloadFromModel];
}
@end
