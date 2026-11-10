include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

APP_NAME = DemoNotes
DemoNotes_OBJC_FILES = main.m $(wildcard ../ThemeSettingsKit/GTS*.m) $(wildcard ../ThemeSettingsUI/GTS*.m)
DemoNotes_INCLUDE_DIRS = -I../ThemeSettingsKit -I../ThemeSettingsUI
DemoNotes_PRINCIPAL_CLASS = NSApplication
DemoNotes_GUI_LIBS += $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/application.make
