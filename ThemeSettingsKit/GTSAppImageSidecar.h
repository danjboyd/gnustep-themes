/* GTSAppImageSidecar.h - reads gnustep-packager's <artifact-base>.themes.json
   (sidecar schema 1, PROVISIONAL: draft PR danjboyd/gnustep-packager#127,
   docs/appimage-theme-metadata.md at ec63a8c). Foundation only.

   Never runs, mounts or loads anything from the AppImage: the sidecar is the
   only input, and the AppImage file is only hashed to check the binding.
   Everything in the sidecar is untrusted text from the payload; it is shown,
   never executed. Nothing here writes defaults. */
#import <Foundation/Foundation.h>

@class GTSThemeSettingsSchema;

typedef enum {
  GTSSidecarBound,          /* file name and sha256 match the AppImage */
  GTSSidecarArtifactMissing,/* no AppImage at the path */
  GTSSidecarNameMismatch,   /* sidecar describes a differently named file */
  GTSSidecarHashMismatch,   /* same name, different bytes: AppImage changed */
  GTSSidecarUnreadable      /* AppImage exists but could not be hashed */
} GTSSidecarBinding;

typedef enum {
  GTSSettingsNone,          /* theme has no ThemeSettings.plist (settings null) */
  GTSSettingsInline,        /* parsed and usable */
  GTSSettingsNotInlined,    /* too large; NOT described, must not look complete */
  GTSSettingsMalformed,
  GTSSettingsUnavailable,   /* link left the payload or looped */
  GTSSettingsUnknownStatus  /* a status this reader doesn't know */
} GTSSidecarSettingsStatus;

typedef enum {
  GTSSeedNone,              /* package seeds no theme */
  GTSSeedAbsentWillApply,   /* key absent: AppRun writes the packaged value at next launch */
  GTSSeedInEffect,          /* stored value equals the packaged one */
  GTSSeedOverriddenByUser,  /* user chose another theme; it stays */
  GTSSeedWrongDomain        /* seed domain differs from (or can't be matched to) the app's domain */
} GTSSeededThemeState;

@interface GTSSidecarTheme : NSObject
{
@public
  NSString *_name, *_themeId, *_bundleId, *_version, *_shortVersion, *_origin;
  NSString *_infoStatus, *_bundledPath, *_executableStatus, *_settingsNote;
  GTSSidecarSettingsStatus _settingsStatus;
  GTSThemeSettingsSchema *_schema;
  NSString *_schemaProblem;
}
- (NSString*) name;
- (NSString*) themeId;          /* logical id; nil when absent */
- (NSString*) bundleId;
- (NSString*) version;
- (NSString*) shortVersion;
- (NSString*) origin;           /* "themeInputs" | "stage" | other text */
- (NSString*) infoStatus;       /* ok absent unavailable tooLarge malformed missing ... */
- (NSString*) bundledPath;      /* payload-relative; nil when missing */
- (GTSSidecarSettingsStatus) settingsStatus;
- (NSString*) settingsNote;
/* Only for GTSSettingsInline and a valid schema. */
- (GTSThemeSettingsSchema*) schema;
- (NSString*) schemaProblem;    /* why an inline schema was rejected */
/* YES only for inline + valid schema. notInlined/malformed/unavailable
   themes are NOT fully described. */
- (BOOL) isFullyDescribed;
/* Whether the theme's code works with any particular GNUstep build is never
   known from this file. Always NO; kept explicit for callers and UI. */
- (BOOL) isCompatibilityKnown;
@end

@interface GTSAppImageSidecar : NSObject
{
  NSString *_path;
  NSDictionary *_json;
  NSArray *_themes;
  NSArray *_warnings;
}
+ (id) sidecarWithContentsOfFile: (NSString*)path error: (NSError**)error;
- (NSString*) path;
- (NSArray*) warnings;          /* recoverable oddities, shown to the user */

/* Binding to an AppImage file. nil path => sidecar dir + appimage.fileName. */
- (NSString*) appImageFileName;
- (NSString*) appImageSha256;
- (GTSSidecarBinding) bindingForAppImageAtPath: (NSString*)appImagePath;
+ (NSString*) descriptionOfBinding: (GTSSidecarBinding)b;

/* App and domains. */
- (NSString*) packageId;
- (NSString*) runtimeDomainHint;          /* nil when unknown */
- (NSString*) runtimeDomainHintSource;    /* bundleIdentifier | processName | unknown */
- (NSString*) seedDomain;                 /* nil when nothing is seeded */
- (NSNumber*) seedDomainMatchesRuntimeHint; /* nil = unknown */

/* GSTheme sources. */
- (NSString*) seededTheme;                /* value of the GSTheme seed, or nil */
- (NSString*) seedPolicy;
- (NSString*) globalDefaultsTheme;        /* GlobalDefaults.plist value, or nil */
- (NSArray*) envEntries;                  /* dicts; informational only */
- (NSDictionary*) searchPolicy;

- (NSArray*) themes;                      /* GTSSidecarTheme */
- (GTSSidecarTheme*) themeNamed: (NSString*)name;

/* How a seeded GSTheme looks given the value currently stored in the app's
   domain (nil = absent). Pure; reads nothing. */
- (GTSSeededThemeState) seededThemeStateForStoredValue: (id)stored inDomain: (NSString*)domain;
- (NSString*) descriptionOfSeededThemeState: (GTSSeededThemeState)s;
/* "Remove" is not meaningful for a seeded key: AppRun writes it back at each
   launch. Choosing another theme is. */
- (BOOL) isRemovalMeaningfulForKey: (NSString*)key;
@end
