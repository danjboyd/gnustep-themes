/* GTSThemeSettingsEditor.h - the reusable AppKit editor. One class, used
   unchanged by the standalone configurator, the in-app pane and (later)
   SystemPreferences. All decisions live in GTSEditorModel; this class only
   renders the model and forwards user actions to it. */
#import <AppKit/AppKit.h>

@class GTSEditorModel, GTSThemeSettingsEditor, GTSApplyOutcome;

/* Both methods are optional (checked with respondsToSelector:). */
@protocol GTSThemeSettingsEditorDelegate
/* Legacy: after an attempt that WROTE (Saved or SavedRefreshFailed). This
   is not proof that a reload or live application succeeded; for
   SavedRefreshFailed the outcome callback (needsReload) is the authority.
   Called before the outcome callback. */
- (void) themeSettingsEditorDidApply: (GTSThemeSettingsEditor*)editor;
/* After EVERY Apply attempt, including one refused before saving (invalid
   text being typed), with that attempt's outcome. The object is captured
   before any callback runs, so it never changes even if a callback edits
   or switches target (which clears [model lastApplyOutcome]). Re-entrant
   Apply from a callback is ignored. Hosts decide from the outcome,
   never from display text, and never re-apply on their own: the editor's
   Reload is the only recovery from WriteUnknown or SavedRefreshFailed. */
- (void) themeSettingsEditor: (GTSThemeSettingsEditor*)editor
     didFinishApplyWithOutcome: (GTSApplyOutcome*)outcome;
@end

@interface GTSThemeSettingsEditor : NSObject <NSTextFieldDelegate>
{
  GTSEditorModel *_model;
  NSView *_view;              /* root view handed to the host */
  NSView *_content;           /* flipped document view inside the scroll view */
  NSScrollView *_scroll;
  NSTextField *_message;
  NSButton *_apply, *_cancel, *_reload;
  NSArray *_rows;             /* GTSSettingRow, matches control tags */
  id _delegate;               /* not retained */
  BOOL _applying;             /* re-entrancy guard for apply: */
}
- (id) initWithModel: (GTSEditorModel*)model;
- (GTSEditorModel*) model;
- (NSView*) view;
- (void) setDelegate: (id)delegate;
/* Re-render everything from the model (after a target change, reload...). */
- (void) reloadFromModel;
/* Drives the editor's own controls the way a user would, for scripted
   screenshots and GUI checks. Actions: "choose <settingId> <value>",
   "type <settingId> <text>" (types into the field, does NOT commit),
   "reset <settingId>", "theme <name>", "apply", "cancel", "reload".
   Returns NO if the control is missing or disabled. */
- (BOOL) performScriptedAction: (NSString*)action;
@end
