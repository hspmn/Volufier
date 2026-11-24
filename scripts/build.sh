#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
mkdir -p build
staging=$(mktemp -d "${TMPDIR:-/tmp}/volufier.XXXXXX")
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Volufier.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/DialFace.png "$bundle/Contents/Resources/"
xcrun --sdk macosx swiftc -swift-version 5 -target arm64-apple-macos13.0 -O \
    -module-cache-path build/ModuleCache Sources/*.swift -o "$bundle/Contents/MacOS/Volufier"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$bundle"
else
    codesign --force --sign - "$bundle"
fi
codesign --verify --strict "$bundle"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive="Volufier-$version-macOS-arm64.zip"
ditto -c -k --norsrc --noextattr --keepParent "$bundle" "$staging/$archive"
ditto --norsrc --noextattr "$bundle" build/Volufier.app
mv -f "$staging/$archive" "build/$archive"
echo "Built build/Volufier.app and build/$archive"
