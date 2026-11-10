/* GTSThemeCatalog.h - finds theme bundles and their ThemeSettings.plist
   without loading theme code. Search order mirrors GNUstep library search
   order, so a USER-directory theme shadows LOCAL/NETWORK/SYSTEM copies
   (and, for AppImages whose SYSTEM/LOCAL/NETWORK point into the payload, the
   bundled copy). Shadowed copies are kept and reported. */
#import <Foundation/Foundation.h>

@class GTSThemeSettingsSchema;

extern NSString * const GTSOriginUser;
extern NSString * const GTSOriginLocal;
extern NSString * const GTSOriginNetwork;
extern NSString * const GTSOriginSystem;
extern NSString * const GTSOriginApplication;   /* app-private, supplied by caller */
extern NSString * const GTSOriginExplicitPath;  /* GSTheme holds a full path */

/* GNUstep's built-in theme: selected when GSTheme is unset or "GNUstep". */
extern NSString * const GTSDefaultThemeName;

@interface GTSThemeSearchRoot : NSObject
{
  NSString *_path;
  NSString *_origin;
}
+ (id) rootWithPath: (NSString*)path origin: (NSString*)origin;
- (NSString*) path;      /* directory containing <Name>.theme bundles */
- (NSString*) origin;
@end

@interface GTSThemeRecord : NSObject
{
  NSString *_name;
  NSString *_path;
  NSString *_origin;
  NSDictionary *_info;
  GTSThemeSettingsSchema *_schema;
  NSError *_schemaError;
  NSArray *_shadowed;
  BOOL _available;
  NSString *_fingerprint;
}
- (NSString*) name;
- (NSString*) path;                 /* nil when unavailable */
- (NSString*) origin;
- (BOOL) isAvailable;               /* NO: selected by name but not found */
- (BOOL) isBuiltIn;                 /* GNUstep default theme, no bundle */
- (NSDictionary*) infoDictionary;   /* bundle Info plist, may be nil */
/* Three separate identities; none is derived from another.
   themeIdentifier: logical theme (ThemeSettings.plist), may be nil.
   bundleIdentifier/bundleVersion: package identity from the bundle's Info.
   descriptorFingerprint: digest of this copy's Info plist, ThemeSettings.plist
   and executable. It tells copies/forks apart that share the other two; it
   is NOT a full artifact integrity check (other resources are not covered).
   Location is the separate -path. */
- (NSString*) themeIdentifier;
- (NSString*) bundleIdentifier;
- (NSString*) bundleVersion;
- (NSString*) descriptorFingerprint;
- (GTSThemeSettingsSchema*) schema; /* nil: no or invalid metadata */
- (NSError*) schemaError;           /* why schema is nil, if it had a file */
- (NSArray*) shadowedRecords;       /* lower-priority same-name copies */
@end

@interface GTSThemeCatalog : NSObject
{
  NSArray *_roots;
  NSArray *_themes;        /* winning records, sorted by name */
  NSDictionary *_byName;
}
/* User, local, network, system Library/Themes for the current process
   configuration (honours GNUSTEP_CONFIG_FILE). */
+ (NSArray*) defaultSearchRoots;

/* Roots in priority order (first wins). */
- (id) initWithSearchRoots: (NSArray*)roots;
- (NSArray*) searchRoots;
- (NSArray*) themes;
- (GTSThemeRecord*) themeNamed: (NSString*)name;

/* Record for a GSTheme value as stored: nil/empty/"GNUstep" -> built-in,
   absolute path -> that bundle, name not found -> unavailable record. */
- (GTSThemeRecord*) recordForSelection: (NSString*)gsThemeValue;
@end
