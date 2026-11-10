/* GTSThemeSettingsEditor.h - the reusable AppKit editor. One class, used
   unchanged by the standalone configurator, the in-app pane and (later)
   SystemPreferences. All decisions live in GTSEditorModel; this class only
   renders the model and forwards user actions to it. */
#import <AppKit/AppKit.h>

@class GTSEditorModel, GTSThemeSettingsEditor;

@protocol GTSThemeSettingsEditorDelegate
- (void) themeSettingsEditorDidApply: (GTSThemeSettingsEditor*)editor;
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
