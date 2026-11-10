# Builds the two shared libraries (Kit first, then UI). The standalone app,
# DemoNotes and the tests have their own GNUmakefiles and are not part of
# this aggregate. Install only into a scratch prefix, e.g.
#   make install DESTDIR=/path/to/scratch GNUSTEP_INSTALLATION_DOMAIN=LOCAL
include $(GNUSTEP_MAKEFILES)/common.make
SUBPROJECTS = ThemeSettingsKit ThemeSettingsUI
include $(GNUSTEP_MAKEFILES)/aggregate.make
