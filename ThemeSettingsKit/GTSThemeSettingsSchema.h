/* GTSThemeSettingsSchema.h - ThemeSettings.plist v1 model and loader.
   Foundation only. Never loads theme code. */
#import <Foundation/Foundation.h>

extern NSString * const GTSErrorDomain;
extern NSString * const GTSScopeGlobal;
extern NSString * const GTSScopeApplication;

/* Precedence source names */
extern NSString * const GTSSourceArgument;
extern NSString * const GTSSourceApplication;
extern NSString * const GTSSourceApplicationInfo;
extern NSString * const GTSSourceGlobal;
extern NSString * const GTSSourceOtherInfo;

enum {
  GTSErrorUnreadable = 1,
  GTSErrorInvalidSchema = 2,
  GTSErrorUnsupportedVersion = 3,
  GTSErrorConflict = 10,
  GTSErrorWriteFailed = 11,
  GTSErrorUnsafeDefaultsRoot = 12,
  GTSErrorUnreadableDomain = 13,
  GTSErrorInvalidArgument = 14,
  GTSErrorUnsupportedFeature = 15,
  GTSErrorUnsupportedBackend = 16,  /* defaults backend this store can't verify */
  GTSErrorNeedsReload = 17          /* outcome of an earlier write unknown; reload first */
};

typedef enum {
  GTSSettingTypeBool,
  GTSSettingTypeEnum,
  GTSSettingTypeString,
  GTSSettingTypeNumber
} GTSSettingType;

typedef enum {
  GTSUnsetStatic,   /* absence behaves as a known value */
  GTSUnsetDynamic   /* absence is decided at runtime; never a stored token */
} GTSUnsetBehavior;

/* Ordered weakest to strongest requirement. */
typedef enum {
  GTSApplyLive = 0,        /* theme observes the change in running apps */
  GTSApplyNewWindows = 1,  /* windows/panels/menus created after the change */
  GTSApplyRestart = 2      /* only a relaunch is guaranteed to show it */
} GTSApplyPolicy;

/* One entry of a setting's Precedence list. */
@interface GTSPrecedenceSource : NSObject
{
  NSString *_source;
  NSArray  *_values;   /* nil = any value from this source wins */
}
- (id) initWithSource: (NSString*)source values: (NSArray*)values;
- (NSString*) source;
- (NSArray*) values;
@end

@interface GTSSettingDescriptor : NSObject
{
  NSString       *_identifier;
  NSString       *_key;
  GTSSettingType  _type;
  NSArray        *_values;          /* array of dicts {Value, Title, Help} */
  BOOL            _caseInsensitive;
  NSArray        *_scopes;
  NSString       *_group;
  NSString       *_title;
  NSString       *_help;
  GTSUnsetBehavior _unsetBehavior;
  id              _unsetValue;
  NSString       *_unsetHelp;
  NSArray        *_precedence;      /* GTSPrecedenceSource */
  NSString       *_infoKey;
  GTSApplyPolicy  _apply;
  NSDictionary   *_dependsOn;
  NSArray        *_overlaps;
  BOOL            _unstable;
  NSNumber       *_minimum, *_maximum;
  NSArray        *_unsupportedFeatures;
}
/* Returns nil and appends to problems if the descriptor is invalid. */
+ (id) descriptorWithPropertyList: (NSDictionary*)plist
                         problems: (NSMutableArray*)problems;
- (NSString*) identifier;
- (NSString*) key;
- (GTSSettingType) type;
- (NSArray*) values;
- (NSArray*) allowedValues;          /* just the Value fields */
- (BOOL) isCaseInsensitive;
- (NSArray*) scopes;
- (BOOL) supportsScope: (NSString*)scope;
- (NSString*) group;
- (NSString*) title;
- (NSString*) help;
- (GTSUnsetBehavior) unsetBehavior;
- (id) unsetValue;
- (NSString*) unsetHelp;
- (NSArray*) precedence;
- (NSString*) infoKey;               /* key used for applicationInfo */
- (GTSApplyPolicy) applyPolicy;
- (NSDictionary*) dependsOn;
- (NSArray*) overlaps;
- (BOOL) isUnstable;
- (NSNumber*) minimum;               /* number settings, may be nil */
- (NSNumber*) maximum;
/* RequiredFeatures this reader does not implement. A setting with any is
   shown read-only: its semantics are not fully understood. */
- (NSArray*) unsupportedFeatures;
- (BOOL) isReadOnly;

/* nil if value may be stored for this setting, else a message. */
- (NSString*) problemWithValue: (id)value;
/* Value equality using this setting's type rules (bool spellings,
   case-insensitive enums). nil == nil. */
- (BOOL) value: (id)a isEqualToValue: (id)b;
/* Canonical stored form for a valid value (bools -> @"YES"/@"NO"). */
- (id) storedFormOfValue: (id)value;
@end

@interface GTSThemeSettingsSchema : NSObject
{
  NSString     *_path;
  NSString     *_bundlePath;
  NSInteger     _version;
  NSString     *_theme;
  NSString     *_themeIdentifier;
  NSArray      *_unsupportedFeatures;
  NSArray      *_groups;
  NSArray      *_settings;
  NSArray      *_warnings;
}
/* Looks for Resources/ThemeSettings.plist, Contents/Resources/ThemeSettings.plist
   or ThemeSettings.plist at the bundle root. */
+ (NSString*) schemaPathForThemeBundleAtPath: (NSString*)bundlePath;
+ (id) schemaForThemeBundleAtPath: (NSString*)bundlePath error: (NSError**)error;
+ (id) schemaWithContentsOfFile: (NSString*)path error: (NSError**)error;
+ (id) schemaWithPropertyList: (id)plist path: (NSString*)path error: (NSError**)error;

- (NSString*) path;
- (NSString*) bundlePath;
- (NSInteger) version;
- (NSString*) theme;
/* Logical theme identity (reverse DNS) declared by the theme. It names the
   theme, not an installation: forks and copies may share it. Package and
   artifact identity come from the bundle (see GTSThemeRecord). */
- (NSString*) themeIdentifier;
/* Top-level RequiredFeatures this reader does not implement; when non-empty
   every setting of this theme is read-only. */
- (NSArray*) unsupportedFeatures;
- (BOOL) isReadOnly;
/* Features this reader implements (RequiredFeatures values). */
+ (NSArray*) supportedFeatures;
- (NSArray*) groups;
- (NSArray*) settings;            /* GTSSettingDescriptor, file order */
- (NSArray*) publicSettings;      /* excludes Status = unstable */
- (NSArray*) warnings;            /* skipped/invalid entries, non-fatal */
- (GTSSettingDescriptor*) settingWithIdentifier: (NSString*)identifier;
- (GTSSettingDescriptor*) settingForKey: (NSString*)key;
/* Looks up Title/Help keys in ThemeSettings.strings of the bundle without
   loading its code; falls back to the literal. */
- (NSString*) localizedString: (NSString*)string;
@end
