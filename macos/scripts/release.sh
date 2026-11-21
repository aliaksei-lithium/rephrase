#!/bin/bash
# Builds a Release archive and packages Rephrase.app into a DMG under macos/dist/.
#
# Signing: uses $CODESIGN_IDENTITY when set (for example "Developer ID Application: ..."),
# otherwise ad-hoc ("-"), which needs no Apple Developer account. Notarization runs only
# when NOTARY_PROFILE is set (a `xcrun notarytool store-credentials` profile).
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

IDENTITY="${CODESIGN_IDENTITY:--}"
DIST="dist"
ARCHIVE="$DIST/Rephrase.xcarchive"
STAGE="$DIST/root"
VERSION=$(awk -F': ' '/MARKETING_VERSION/{gsub(/"/,"",$2); print $2; exit}' project.yml)
DMG="$DIST/Rephrase-$VERSION.dmg"

rm -rf "$DIST"
mkdir -p "$STAGE"

echo "▸ Archiving Rephrase $VERSION (identity: $IDENTITY)…"
xcodebuild -project Rephrase.xcodeproj -scheme Rephrase -configuration Release \
    -destination 'platform=macOS' -archivePath "$ARCHIVE" archive \
    CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    ENABLE_HARDENED_RUNTIME=YES \
    2>&1 | grep -E "(error|warning): |^\*\* [A-Z]+ (SUCCEEDED|FAILED)" || true

APP="$ARCHIVE/Products/Applications/Rephrase.app"
[ -d "$APP" ] || { echo "The archive did not produce $APP" >&2; exit 1; }
codesign --verify --deep --strict "$APP" || { echo "The signed app does not verify." >&2; exit 1; }

cp -R "$APP" "$STAGE/Rephrase.app"
ln -s /Applications "$STAGE/Applications"

echo "▸ Building DMG…"
hdiutil create -volname "Rephrase" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "▸ Notarizing with profile $NOTARY_PROFILE…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

rm -rf "$STAGE"
echo "$DMG"
