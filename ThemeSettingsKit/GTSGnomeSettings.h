/* GTSGnomeSettings.h - read GNOME's desktop interface settings
   (org.gnome.desktop.interface) for the editor's "Follow GNOME" switch.
   Read only: never writes GNOME settings. */
#import <Foundation/Foundation.h>

@interface GTSGnomeSettings : NSObject
/* Reads with the `gsettings` tool found on PATH. Each call runs it afresh,
   so the answer is GNOME's current value. */
+ (GTSGnomeSettings*) systemSettings;
/* The value of `key` in org.gnome.desktop.interface, without GVariant
   quotes, or nil if it cannot be read (no gsettings, no such key). */
- (NSString*) interfaceStringForKey: (NSString*)key;
@end

/* Fixed values, for tests. */
@interface GTSFixedGnomeSettings : GTSGnomeSettings
{
  NSDictionary *_values;
}
- (id) initWithValues: (NSDictionary*)values;
@end
