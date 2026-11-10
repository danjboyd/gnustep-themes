# Shared build settings. Included by every GNUmakefile that compiles
# ThemeSettingsKit sources. Maintained SHA-256 backend: GnuTLS, detected
# explicitly and linked explicitly (not relied on via gnustep-base).
GTS_GNUTLS := $(shell pkg-config --exists gnutls 2>/dev/null && echo yes)
ifeq ($(GTS_GNUTLS),yes)
ADDITIONAL_OBJCFLAGS += -DGTS_HAVE_GNUTLS $(shell pkg-config --cflags gnutls)
GTS_EXTRA_LIBS = $(shell pkg-config --libs gnutls)
else
$(warning gnutls not found: AppImage sidecar binding checks will be unavailable)
GTS_EXTRA_LIBS =
endif
