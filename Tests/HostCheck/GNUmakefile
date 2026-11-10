include $(GNUSTEP_MAKEFILES)/common.make
include ../../gts-config.make

# Disposable AppKit host that drives the real GTSThemeSettingsEditor and
# checks callback order, outcome capture, re-entry and exception reset.
TOOL_NAME = gts-host-check
gts-host-check_OBJC_FILES = main.m $(wildcard ../../ThemeSettingsKit/GTS*.m) $(wildcard ../../ThemeSettingsUI/GTS*.m)
gts-host-check_INCLUDE_DIRS = -I../../ThemeSettingsKit -I../../ThemeSettingsUI
gts-host-check_TOOL_LIBS += -lgnustep-gui $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/tool.make
