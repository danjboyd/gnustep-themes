include $(GNUSTEP_MAKEFILES)/common.make
include ../../gts-config.make

# Foundation-only check of a brand-new user (no defaults directory yet):
# the store must read and write there. Run by scripts/fresh-root-check.sh.
TOOL_NAME = gts-fresh-root
gts-fresh-root_OBJC_FILES = main.m $(wildcard ../../ThemeSettingsKit/GTS*.m)
gts-fresh-root_INCLUDE_DIRS = -I../../ThemeSettingsKit
gts-fresh-root_TOOL_LIBS += $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/tool.make
