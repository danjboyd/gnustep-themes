include $(GNUSTEP_MAKEFILES)/common.make
include ../../gts-config.make

# gts-validate-schema: strict ThemeSettings.plist (schema v1) checker for
# theme owners. Foundation only; compiles the Kit sources in (no install).
#   obj/gts-validate-schema [-q] <ThemeSettings.plist | Name.theme>...
TOOL_NAME = gts-validate-schema
gts-validate-schema_OBJC_FILES = main.m $(wildcard ../../ThemeSettingsKit/GTS*.m)
gts-validate-schema_INCLUDE_DIRS = -I../../ThemeSettingsKit
gts-validate-schema_TOOL_LIBS += $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/tool.make
