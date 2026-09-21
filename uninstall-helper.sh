#!/bin/bash
# Removes lantern-helper — the root helper an earlier version installed to hold
# the charge — and makes sure charging is released. Lantern no longer uses it.
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run this with sudo:  sudo $0"
    exit 1
fi

LABEL=com.dominic.lantern.helper
BIN=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

# Stopping the helper releases the charge on its way out...
launchctl bootout "system/$LABEL" 2>/dev/null || true
# ...and this makes certain of it, whatever state it was in.
if [ -x "$BIN" ]; then "$BIN" --release; fi

rm -f "$BIN" "$PLIST"
echo "Removed. Charging is back to normal."
