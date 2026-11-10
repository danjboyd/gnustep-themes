/* GTSSHA256.h - SHA-256 for binding an AppImage to its sidecar, using a
   maintained implementation detected at build time (GnuTLS: build with
   -DGTS_HAVE_GNUTLS and link gnutls; see gts-config.make). Without one,
   hashing is unavailable: every function returns nil and callers must treat
   the binding as unchecked. Files are hashed in a streaming fashion. */
#import <Foundation/Foundation.h>

BOOL GTSSHA256IsAvailable(void);
/* Lowercase hex digest, or nil (unavailable backend / unreadable file). */
NSString *GTSSHA256HexOfData(NSData *data);
NSString *GTSSHA256HexOfFile(NSString *path);
/* TESTING ONLY: behave as if no backend were built in. */
void GTSSHA256SetDisabledForTesting(BOOL disabled);
