include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

LIBRARY_NAME = libThemeSettingsKit
libThemeSettingsKit_OBJC_FILES = $(wildcard GTS*.m)
libThemeSettingsKit_HEADER_FILES = $(wildcard GTS*.h)
libThemeSettingsKit_HEADER_FILES_INSTALL_DIR = ThemeSettingsKit
libThemeSettingsKit_LIBRARIES_DEPEND_UPON += $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/library.make
