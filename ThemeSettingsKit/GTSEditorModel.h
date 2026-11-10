/* GTSEditorModel.h - presentation model shared by every front end (standalone
   app, in-app pane, later SystemPreferences). Foundation only, so it is
   tested headless; the AppKit view just renders it. */
#import <Foundation/Foundation.h>

@class GTSAppImageSidecar, GTSApplyReceipt;

typedef enum {
  GTSApplyOutcomeSaved,               /* written and re-read */
  GTSApplyOutcomeNothingToSave,       /* nothing was staged */
  GTSApplyOutcomeSavedRefreshFailed,  /* written; re-read failed; reload before more edits */
  GTSApplyOutcomeWriteUnknown,        /* may or may not be on disk; edits stay staged; reload */
  GTSApplyOutcomeConflict,            /* not written: changed elsewhere (edits kept) */
  GTSApplyOutcomeRefused              /* not written: read-only/unreadable/invalid/needs reload */
} GTSApplyOutcomeKind;

/* Immutable record of ONE Apply attempt, owned by the model. Hosts read
   it; they never re-apply on its basis (the editor's Reload is the only
   way out of WriteUnknown / SavedRefreshFailed). */
@interface GTSApplyOutcome : NSObject
{
@public
  GTSApplyOutcomeKind _kind;
  GTSApplyReceipt *_receipt;
  NSError *_error;
  NSArray *_conflictKeys;
  BOOL _needsReload;
}
- (GTSApplyOutcomeKind) kind;
/* Saved / NothingToSave / SavedRefreshFailed only; carries the committed
   changes and their strongest Apply requirement (GTSApplyPolicy). */
- (GTSApplyReceipt*) receipt;
- (NSError*) error;            /* failure kinds; nil otherwise */
- (NSArray*) conflictKeys;     /* Conflict only */
- (BOOL) didWrite;             /* YES for Saved and SavedRefreshFailed */
- (BOOL) isOutcomeUnknown;     /* YES for WriteUnknown */
- (BOOL) needsReload;          /* session refuses Apply until Reload */
@end
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
  GTSAppImageSidecar *_sidecar; /* AppImage target (read-only) */
  NSString *_appImagePath;
  int _binding;                 /* GTSSidecarBinding */
  GTSDomainSnapshot *_roApp;    /* AppImage app domain, read only; nil = unknown */
  GTSApplyOutcome *_lastOutcome;
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
/* AppImage target described by its sidecar. ALWAYS read-only: nothing is
   staged or applied, the AppImage is only hashed (never mounted or run).
   Values are read from the app's defaults domain only when the sidecar is
   bound to the AppImage and names the domain. appImagePath nil = the file
   named by the sidecar, beside it. Returns NO if nothing usable is known. */
- (BOOL) setTargetAppImageSidecar: (GTSAppImageSidecar*)sidecar appImage: (NSString*)appImagePath;
- (BOOL) targetIsAppImage;
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
- (BOOL) apply;          /* NO: see -lastApplyOutcome; on conflict the model rebased */
/* The outcome of the most recent Apply, or nil. Cleared when it would be
   stale: a new edit is staged, Cancel, a successful Reload, or a target
   change. -message is display text only; hosts use this instead. */
- (GTSApplyOutcome*) lastApplyOutcome;
/* Apply after staging text still being typed: pairs is an array of
   (GTSSettingRow, NSString) two-element arrays. If any text is invalid,
   nothing is applied and a FRESH Refused outcome (GTSErrorInvalidArgument,
   naming the setting) is recorded, so every attempt has its own outcome. */
- (BOOL) applyWithPendingTexts: (NSArray*)pairs;
- (void) cancel;
- (BOOL) reload;         /* pick up external edits, keep staged changes */
- (NSString*) message;   /* last error/conflict/restart text, or nil */
@end
