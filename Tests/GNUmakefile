include $(GNUSTEP_MAKEFILES)/common.make
include ../gts-config.make

# Where XCTest (gnustep/tools-xctest) is installed; CI sets XCTEST_PREFIX.
XCTEST_PREFIX ?= $(HOME)/GNUstep

BUNDLE_NAME = ThemeSettingsKitTests
NEEDS_GUI = no
KIT_SOURCES = $(wildcard ../ThemeSettingsKit/GTS*.m)
ThemeSettingsKitTests_OBJC_FILES = $(KIT_SOURCES) $(wildcard *Tests.m) GTSTestSupport.m
ThemeSettingsKitTests_INCLUDE_DIRS = -I../ThemeSettingsKit -I. -I$(XCTEST_PREFIX)/Library/Headers
ThemeSettingsKitTests_LIB_DIRS = -L$(XCTEST_PREFIX)/Library/Libraries
ThemeSettingsKitTests_BUNDLE_LIBS += -lXCTest $(GTS_EXTRA_LIBS)
ADDITIONAL_OBJCFLAGS += -Wall -Wno-import -Wno-unknown-pragmas

include $(GNUSTEP_MAKEFILES)/bundle.make
