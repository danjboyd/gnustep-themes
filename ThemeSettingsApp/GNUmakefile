include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

APP_NAME = ThemeSettings
ThemeSettings_OBJC_FILES = main.m $(wildcard ../ThemeSettingsKit/GTS*.m) $(wildcard ../ThemeSettingsUI/GTS*.m)
ThemeSettings_INCLUDE_DIRS = -I../ThemeSettingsKit -I../ThemeSettingsUI
ThemeSettings_MAIN_MODEL_FILE =
ThemeSettings_PRINCIPAL_CLASS = NSApplication
ThemeSettings_GUI_LIBS += $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/application.make
