#!/bin/sh
# fresh-root-check.sh - a brand-new user's first launch: the defaults
# directory does not exist yet. gnustep-base's first -synchronize then
# reports NO; the store must still read and write. Runs the check tool with
# a private, owner-only GNUstep config (and GNUSTEP_HOME) in a scratch root
# and refuses unless that config is really in use.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
: "${GNUSTEP_MAKEFILES:=$(gnustep-config --variable=GNUSTEP_MAKEFILES)}"
export GNUSTEP_MAKEFILES
make -s -C "$here/Tests/FreshRoot" messages=no >/dev/null
master=$(gnustep-config --variable=GNUSTEP_CONFIG_FILE 2>/dev/null || true)
[ -r "${master:-}" ] || master=/etc/GNUstep/GNUstep.conf
r=$(mktemp -d "${TMPDIR:-/tmp}/gts-fresh.XXXXXX"); r=$(cd "$r" && pwd -P)
trap 'rm -rf "$r"' EXIT INT TERM
mkdir -p "$r/home"
{ grep -v '^GNUSTEP_USER' "$master" 2>/dev/null || true
  printf 'GNUSTEP_USER_CONFIG_FILE=%s/none.conf\nGNUSTEP_USER_DEFAULTS_DIR=%s/new/Defaults\nGNUSTEP_USER_DIR=%s/new\n' "$r" "$r" "$r"
} > "$r/GNUstep.conf"
chmod 700 "$r"; chmod 600 "$r/GNUstep.conf"
got=$(GNUSTEP_CONFIG_FILE="$r/GNUstep.conf" gnustep-config --variable=GNUSTEP_USER_DEFAULTS_DIR 2>/dev/null || true)
case "$got" in "$r"/*) ;; *) echo "fresh-root-check: could not isolate defaults (got '${got:-nothing}'); refusing" >&2; exit 2 ;; esac
GNUSTEP_HOME="$r/home" GNUSTEP_CONFIG_FILE="$r/GNUstep.conf" "$here/Tests/FreshRoot/obj/gts-fresh-root" "$r"
