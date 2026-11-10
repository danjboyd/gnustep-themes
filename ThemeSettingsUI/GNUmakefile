include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

# Reusable editor library. Public interface: the editor class only (plus the
# umbrella header). GTSScreenshot/GTSScriptRunner are review/test tooling and
# stay out of the library; the standalone app and DemoNotes keep compiling
# their own copies from source (their build is unchanged).
LIBRARY_NAME = libThemeSettingsUI
VERSION = 0.1.0
libThemeSettingsUI_OBJC_FILES = GTSThemeSettingsEditor.m
libThemeSettingsUI_HEADER_FILES = ThemeSettingsUI.h GTSThemeSettingsEditor.h
libThemeSettingsUI_HEADER_FILES_INSTALL_DIR = ThemeSettingsUI
libThemeSettingsUI_INCLUDE_DIRS = -I../ThemeSettingsKit
libThemeSettingsUI_LIB_DIRS = -L../ThemeSettingsKit/$(GNUSTEP_OBJ_DIR)
# Explicit dependencies: Kit, AppKit (gnustep-gui), Foundation, runtime.
libThemeSettingsUI_LIBRARIES_DEPEND_UPON = -lThemeSettingsKit $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/library.make
