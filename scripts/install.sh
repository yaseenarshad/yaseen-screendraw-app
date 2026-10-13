#!/bin/bash
# Puts "build/Yaseen Screendraw.app" in /Applications and opens it.
#
# USAGE:
#   scripts/bundle.sh       First make the signed app.
#   scripts/install.sh      Then install it.
#
# The script quits the app that runs, replaces the app in /Applications, and
# opens the new one. It keeps no copy of the old app. The old versions are on
# the GitHub releases page.
#
# The script changes /Applications. For that reason the owner of the Mac runs
# it, not an agent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Yaseen Screendraw"
EXECUTABLE="YaseenScreendraw"
SOURCE="$ROOT/build/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"
# This finds each copy of the app that runs, also a copy outside /Applications.
RUNNING="/$APP_NAME.app/Contents/MacOS/$EXECUTABLE"

[ -d "$SOURCE" ] || { echo "error: $SOURCE is missing. Run scripts/bundle.sh first." >&2; exit 1; }
codesign --verify --deep --strict "$SOURCE"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")"

if pgrep -f "$RUNNING" >/dev/null; then
    echo "Quitting the app that runs."
    # This is the same as "Quit" in the menu of the app. The marks on the screen go away.
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    # Wait until the old app is gone.
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        pgrep -f "$RUNNING" >/dev/null || break
        sleep 0.5
    done
    if pgrep -f "$RUNNING" >/dev/null; then
        echo "error: $APP_NAME still runs after 10 seconds. Quit it from its menu bar icon, then run this script again." >&2
        exit 1
    fi
fi

rm -rf "$TARGET"
ditto "$SOURCE" "$TARGET"
codesign --verify --deep --strict "$TARGET"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"
open "$TARGET"
echo "Done. $APP_NAME $VERSION is in /Applications and is open."
