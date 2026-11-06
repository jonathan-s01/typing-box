#!/bin/bash
# Builds Typing Box, installs it to /Applications, and opens it.
# Signs with "Typing Box Local Signing" if setup-signing.sh has been run,
# otherwise uses a temporary signature (Accessibility permission resets each build).
set -euo pipefail
cd "$(dirname "$0")"

APP="TypingBox.app"
SIGN_NAME="Typing Box Local Signing"

echo "Building..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -swift-version 5 -O *.swift -o "$APP/Contents/MacOS/TypingBox"
cp Info.plist "$APP/Contents/Info.plist"

if security find-certificate -c "$SIGN_NAME" >/dev/null 2>&1; then
    echo "Signing with \"$SIGN_NAME\"..."
    codesign --force --sign "$SIGN_NAME" "$APP"
else
    echo "No signing certificate found, using a temporary signature."
    echo "Run setup-signing.sh once so the Accessibility permission survives rebuilds."
    codesign --force --sign - "$APP"
fi

pkill -x TypingBox 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
echo "Installed to /Applications/$APP"
open "/Applications/$APP"
echo "Done."
