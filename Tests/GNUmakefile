include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

BUNDLE_NAME = ThemeSettingsKitTests
NEEDS_GUI = no
KIT_SOURCES = $(wildcard ../ThemeSettingsKit/GTS*.m)
ThemeSettingsKitTests_OBJC_FILES = $(KIT_SOURCES) $(wildcard *Tests.m) GTSTestSupport.m
ThemeSettingsKitTests_INCLUDE_DIRS = -I../ThemeSettingsKit -I. -I$(HOME)/GNUstep/Library/Headers
ThemeSettingsKitTests_LIB_DIRS = -L$(HOME)/GNUstep/Library/Libraries
ThemeSettingsKitTests_BUNDLE_LIBS += -lXCTest $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/bundle.make
