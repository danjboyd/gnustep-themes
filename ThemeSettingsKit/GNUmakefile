include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

LIBRARY_NAME = libThemeSettingsKit
VERSION = 0.1.0
libThemeSettingsKit_OBJC_FILES = $(wildcard GTS*.m)
libThemeSettingsKit_HEADER_FILES = ThemeSettingsKit.h $(wildcard GTS*.h)
libThemeSettingsKit_HEADER_FILES_INSTALL_DIR = ThemeSettingsKit
# Explicit dependencies: Foundation, runtime, GnuTLS (SHA-256; see gts-config.make).
libThemeSettingsKit_LIBRARIES_DEPEND_UPON += $(GTS_EXTRA_LIBS) $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/library.make
