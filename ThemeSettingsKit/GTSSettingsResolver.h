/* GTSSettingsResolver.h - what a setting's value is for one target
   (global, or one application), and where it comes from. Pure: works on
   snapshots, never touches defaults itself. */
#import <Foundation/Foundation.h>

@class GTSDomainSnapshot, GTSSettingDescriptor;

typedef enum {
  GTSValueExplicit,    /* stored in the target's own domain */
  GTSValueInherited,   /* target is an app; value comes from NSGlobalDomain */
  GTSValueInfoPlist,   /* target app's Info.plist supplies it */
  GTSValueDefault,     /* nothing set; theme's static default applies */
  GTSValueUnknown      /* decided at runtime (dynamic default) */
} GTSValueState;

@interface GTSResolvedValue : NSObject
{
@public   /* filled by GTSSettingsResolver only; read via accessors */
  GTSValueState _state;
  id _effectiveValue;
  id _explicitValue;
  id _globalValue;
  id _infoValue;
  NSString *_note;
  NSArray *_caveats;
}
- (GTSValueState) state;
- (id) effectiveValue;   /* nil when state is Unknown */
- (id) explicitValue;    /* in the target's own domain; nil = no override, reset disabled */
- (id) globalValue;      /* NSGlobalDomain value (app targets), for "inherits X" text */
- (id) infoValue;        /* target app's Info.plist value, if any */
- (NSString*) note;      /* human text for Unknown/Default (dynamic help etc.) */
/* Things the editor cannot see that could still change the running value:
   "argument" (launch arguments), "otherInfo" (another bundle's Info.plist). */
- (NSArray*) caveats;
- (BOOL) hasOverride;
@end

@interface GTSSettingsResolver : NSObject
{
  GTSDomainSnapshot *_global;
  GTSDomainSnapshot *_application;   /* nil when editing global */
  NSDictionary *_appInfo;
}
/* application nil => target is global. appInfo is the target app's Info
   dictionary (may be nil). */
- (id) initWithGlobal: (GTSDomainSnapshot*)global
          application: (GTSDomainSnapshot*)application
      applicationInfo: (NSDictionary*)appInfo;

- (BOOL) targetIsGlobal;
- (GTSResolvedValue*) resolveSetting: (GTSSettingDescriptor*)setting;

/* GSTheme resolution, independent of any setting: app domain, then global,
   then GNUstep's built-in default. effectiveValue is the stored GSTheme
   string, or "GNUstep" with state Default. */
- (GTSResolvedValue*) resolveThemeSelection;
@end
