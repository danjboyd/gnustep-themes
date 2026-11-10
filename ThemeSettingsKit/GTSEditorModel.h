/* GTSEditorModel.h - presentation model shared by every front end (standalone
   app, in-app pane, later SystemPreferences). Foundation only, so it is
   tested headless; the AppKit view just renders it. */
#import <Foundation/Foundation.h>

@class GTSDefaultsDomainStore, GTSDomainSnapshot, GTSThemeCatalog, GTSThemeRecord, GTSEditSession,
  GTSSettingDescriptor, GTSResolvedValue;

/* One entry of a choice list. value == nil means "no override" (removes the
   key: inherit / default / automatic). */
@interface GTSChoice : NSObject
{
  NSString *_title;
  id _value;
}
+ (id) choiceWithTitle: (NSString*)title value: (id)value;
- (NSString*) title;
- (id) value;
@end

@interface GTSSettingRow : NSObject
{
@public
  GTSSettingDescriptor *_setting;
  NSArray *_choices;
  NSInteger _selectedIndex;
  NSString *_title;
  NSString *_stateText;
  NSString *_note;
  BOOL _canReset;
  BOOL _isFreeForm;      /* string/number: text field instead of choices */
  NSString *_text;
  BOOL _readOnly;        /* metadata requires features this editor lacks */
}
- (GTSSettingDescriptor*) setting;
- (NSString*) title;
- (NSArray*) choices;
- (NSInteger) selectedIndex;
- (NSString*) stateText;   /* "Set here", "Inherited from all applications", ... */
- (NSString*) note;        /* help, overlaps, restart, caveats */
- (BOOL) canReset;
- (BOOL) isFreeForm;
- (NSString*) text;
- (BOOL) isReadOnly;
@end

@interface GTSEditorModel : NSObject
{
  GTSDefaultsDomainStore *_store;
  GTSThemeCatalog *_catalog;
  NSString *_appDomain;        /* nil = editing global */
  NSString *_appName;
  NSDictionary *_appInfo;
  GTSEditSession *_session;
  GTSDomainSnapshot *_globalBaseline;   /* for app targets */
  BOOL _showUnstable;
  NSString *_message;
  NSString *_hostDomain;       /* domain of the process showing the editor */
}
- (id) initWithStore: (GTSDefaultsDomainStore*)store catalog: (GTSThemeCatalog*)catalog;

/* Both return NO (see -message) if the domain cannot be read reliably;
   the editor then shows nothing editable. */
- (BOOL) setTargetGlobal;
/* displayName for UI; info = the app's Info dictionary (may be nil). */
- (BOOL) setTargetApplicationDomain: (NSString*)domain
                        displayName: (NSString*)name
                               info: (NSDictionary*)info;
/* The domain of the process hosting the editor (in-app pane), or nil for
   the standalone configurator. Only edits to the host's own domain can be
   confirmed as applied live; other processes may need a restart. */
- (void) setHostDomain: (NSString*)domain;
- (BOOL) isEditable;
- (BOOL) targetIsGlobal;
- (NSString*) targetTitle;
- (GTSEditSession*) session;

/* Theme selection */
- (NSArray*) themeChoices;
- (NSInteger) selectedThemeIndex;
- (NSString*) themeStateText;
- (GTSThemeRecord*) effectiveTheme;    /* theme whose settings are shown */
- (NSString*) themeNote;               /* provider, shadowing, missing metadata */
- (void) selectThemeChoiceAtIndex: (NSInteger)index;

/* Settings for the effective theme */
- (void) setShowsUnstableSettings: (BOOL)flag;
- (NSArray*) rows;
- (BOOL) selectChoiceAtIndex: (NSInteger)index forRow: (GTSSettingRow*)row;
- (BOOL) setText: (NSString*)text forRow: (GTSSettingRow*)row;
- (void) resetRow: (GTSSettingRow*)row;

/* Apply / Cancel */
- (BOOL) hasChanges;
- (BOOL) needsRestart;
- (BOOL) apply;          /* NO: see -message; on conflict the model rebased */
- (void) cancel;
- (BOOL) reload;         /* pick up external edits, keep staged changes */
- (NSString*) message;   /* last error/conflict/restart text, or nil */
@end
