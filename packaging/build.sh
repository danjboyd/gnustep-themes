#!/bin/sh
# Build step for gnustep-packager (packaging/package.manifest.json): the
# standalone editor. It compiles the Kit and UI sources in, so no shared
# libraries of ours need staging.
set -eu
make -C ThemeSettingsApp
