/* GTSSHA256.h - small SHA-256 (FIPS 180-4) for binding an AppImage to its
   sidecar. gnustep-base 1.31 offers no SHA-256. Streams files in chunks. */
#import <Foundation/Foundation.h>

/* Lowercase hex digest of the data, or of the file (nil if unreadable). */
NSString *GTSSHA256HexOfData(NSData *data);
NSString *GTSSHA256HexOfFile(NSString *path);
