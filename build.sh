#!/bin/bash
# Build Pomo.app with the Command Line Tools (no Xcode), install it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Pomo.app
# Optional local signing config (gitignored): POMO_KEYCHAIN, POMO_KEYCHAIN_PASSWORD, POMO_SIGN_IDENTITY.
[ -f signing/env ] && . signing/env

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -swift-version 6 -O -target "$(uname -m)-apple-macosx14.0" \
    Sources/*.swift -o "$APP/Contents/MacOS/Pomo"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/*.wav Resources/Texture-*.png "$APP/Contents/Resources/"   # sounds: tools/make_sounds.py, textures: tools/make_textures.py
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/"

# Sign with a stable local identity if you have one (keeps notification permission across rebuilds);
# otherwise ad-hoc sign, which works fine but macOS may ask for notification permission again after a rebuild.
if [ -n "${POMO_SIGN_IDENTITY:-}" ] && [ -f "${POMO_KEYCHAIN:-}" ] \
   && security unlock-keychain -p "${POMO_KEYCHAIN_PASSWORD:-}" "$POMO_KEYCHAIN" 2>/dev/null; then
    codesign --force --options runtime --sign "$POMO_SIGN_IDENTITY" --keychain "$POMO_KEYCHAIN" "$APP"
else
    codesign --force --options runtime --sign - "$APP"
fi
codesign --verify --strict "$APP"

pkill -x Pomo 2>/dev/null && sleep 0.5 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Pomo.app"
cp -R "$APP" "$HOME/Applications/"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Pomo.app"
open "$HOME/Applications/Pomo.app"
echo "Installed ~/Applications/Pomo.app"
