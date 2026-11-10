/* GTSSHA256.m - thin wrapper over a maintained SHA-256 (GnuTLS). */
#import "GTSSHA256.h"
#include <stdio.h>
#ifdef GTS_HAVE_GNUTLS
#include <gnutls/gnutls.h>
#include <gnutls/crypto.h>
#endif

static BOOL testDisabled = NO;

void
GTSSHA256SetDisabledForTesting(BOOL disabled)
{
  testDisabled = disabled;
}

BOOL
GTSSHA256IsAvailable(void)
{
#ifdef GTS_HAVE_GNUTLS
  return !testDisabled;
#else
  return NO;
#endif
}

#ifdef GTS_HAVE_GNUTLS
static NSString *
hex(const unsigned char *d, size_t n)
{
  NSMutableString *s = [NSMutableString stringWithCapacity: n * 2];
  size_t i;
  for (i = 0; i < n; i++) [s appendFormat: @"%02x", d[i]];
  return s;
}
#endif

NSString *
GTSSHA256HexOfData(NSData *data)
{
#ifdef GTS_HAVE_GNUTLS
  unsigned char d[32];
  if (!GTSSHA256IsAvailable()) return nil;
  if (gnutls_hash_fast(GNUTLS_DIG_SHA256, [data bytes], [data length], d) < 0) return nil;
  return hex(d, sizeof d);
#else
  return nil;
#endif
}

NSString *
GTSSHA256HexOfFile(NSString *path)
{
#ifdef GTS_HAVE_GNUTLS
  gnutls_hash_hd_t h;
  unsigned char buf[65536], d[32];
  size_t n;
  FILE *f;
  BOOL ok = YES;

  if (!GTSSHA256IsAvailable()) return nil;
  if ((f = fopen([path fileSystemRepresentation], "rb")) == NULL) return nil;
  if (gnutls_hash_init(&h, GNUTLS_DIG_SHA256) < 0) { fclose(f); return nil; }
  while ((n = fread(buf, 1, sizeof buf, f)) > 0)      /* streamed, never whole-file */
    if (gnutls_hash(h, buf, n) < 0) { ok = NO; break; }
  if (ferror(f)) ok = NO;
  fclose(f);
  gnutls_hash_deinit(h, d);
  return ok ? hex(d, sizeof d) : nil;
#else
  return nil;
#endif
}
