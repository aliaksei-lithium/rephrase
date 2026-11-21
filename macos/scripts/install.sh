#!/bin/bash
# Builds Rephrase (Release) and installs it to ~/Applications, separate from the
# Debug build that `xcodebuild test` keeps replacing.
#
# Signing: macOS ties the Accessibility permission to the app's signature.
#   - Default: ad-hoc. Every install is a "new" app, so the old permission is reset
#     and you allow it again once after each install.
#   - REPHRASE_TEAM_ID=<team id>: signs with your Apple Development certificate
#     (Xcode > Settings > Accounts, a free Apple ID works). The permission then
#     survives reinstalls.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${REPHRASE_INSTALL_DIR:-$HOME/Applications}"
BUNDLE_ID="dev.rephrase.mac"
APP="build/release/Build/Products/Release/Rephrase.app"

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }
xcodegen generate --quiet

SIGN_ARGS=()
if [[ -n "${REPHRASE_TEAM_ID:-}" ]]; then
    SIGN_ARGS=(CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$REPHRASE_TEAM_ID" CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates)
fi

echo "Building Rephrase (Release)..."
xcodebuild -project Rephrase.xcodeproj -scheme Rephrase -configuration Release \
    -destination 'platform=macOS' -derivedDataPath build/release \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} build -quiet

requirement() { codesign -d -r- "$1" 2>&1 | grep '^designated' || true; }
old_req=""
[[ -d "$DEST/Rephrase.app" ]] && old_req="$(requirement "$DEST/Rephrase.app")"
new_req="$(requirement "$APP")"

# Quit every running copy, including Debug builds started from the build folder.
pkill -x Rephrase 2>/dev/null || true
sleep 0.5

mkdir -p "$DEST"
rm -rf "$DEST/Rephrase.app"
cp -R "$APP" "$DEST/"
echo "Installed $DEST/Rephrase.app"

if [[ "$old_req" != "$new_req" ]]; then
    # A stale entry looks enabled in System Settings but no longer matches the app.
    echo "The signature changed, so Rephrase's old Accessibility entry was reset. Allow it again when asked."
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

open "$DEST/Rephrase.app"
