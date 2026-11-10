# Minimal EXTERNAL host: built only against a staged prefix, never against
# this repo's sources. scripts/screenshots.sh (GTS_SHOTS_ONLY=I) copies this
# directory into its scratch root and runs:
#   make GTS_INCLUDE=<stage>/<LOCAL headers> GTS_LIB=<stage>/<LOCAL libraries>
# No gts-config.make, no -I to the source tree: if the installed headers or
# libraries are incomplete, this build fails.
include $(GNUSTEP_MAKEFILES)/common.make

ifeq ($(GTS_INCLUDE)$(GTS_LIB),)
$(error set GTS_INCLUDE and GTS_LIB to the staged prefix)
endif
TOOL_NAME = gts-external-host
gts-external-host_OBJC_FILES = main.m
gts-external-host_INCLUDE_DIRS = -I$(GTS_INCLUDE)
gts-external-host_LIB_DIRS = -L$(GTS_LIB)
gts-external-host_TOOL_LIBS = -lThemeSettingsUI -lThemeSettingsKit -lgnustep-gui
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import

include $(GNUSTEP_MAKEFILES)/tool.make
