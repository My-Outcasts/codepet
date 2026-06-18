#!/usr/bin/env bash
#
# Package Codepet for direct (non-App-Store) distribution:
#   archive → export (Developer ID) → .dmg → notarize → staple → verify
#
# The output .dmg is signed, notarized, and stapled — ready to host on the web
# (e.g. GitHub Releases) behind the "Download for macOS" button.
#
# ── ONE-TIME PREREQS ──────────────────────────────────────────────────────────
#   1. Paid Apple Developer Program membership.
#   2. A "Developer ID Application" certificate installed in your login keychain:
#        Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + Developer ID Application
#   3. Notarization credentials stored once as a keychain profile:
#        xcrun notarytool store-credentials "codepet-notary" \
#          --apple-id "YOU@APPLE.ID" --team-id "YL72VTKBR7" \
#          --password "APP_SPECIFIC_PASSWORD"
#      (or with an App Store Connect API key:)
#        xcrun notarytool store-credentials "codepet-notary" \
#          --key AuthKey_XXXX.p8 --key-id KEYID --issuer ISSUER_ID
#
# ── USAGE ─────────────────────────────────────────────────────────────────────
#   ./scripts/package-macos.sh
#   TEAM_ID=ABCDE12345 NOTARY_PROFILE=my-profile ./scripts/package-macos.sh
#
set -euo pipefail

# ── Config (override via env) ─────────────────────────────────────────────────
SCHEME="${SCHEME:-codepet}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-YL72VTKBR7}"
NOTARY_PROFILE="${NOTARY_PROFILE:-codepet-notary}"
VOL_NAME="${VOL_NAME:-Codepet}"

PROJECT="codepet.xcodeproj"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Codepet.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTS="scripts/ExportOptions.plist"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶︎ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

# ── 1. Archive ────────────────────────────────────────────────────────────────
echo "▶︎ Archiving ($CONFIGURATION)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  clean archive

# ── 2. Export with Developer ID (hardened runtime, notarization-ready) ─────────
echo "▶︎ Exporting (Developer ID)…"
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_OPTS" 2>/dev/null || true
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS"

APP_PATH="$(/bin/ls -d "$EXPORT_DIR"/*.app | head -1)"
APP_NAME="$(basename "$APP_PATH" .app)"
echo "   exported: $APP_PATH"
echo "▶︎ Signature / hardened-runtime check:"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|Runtime|TeamIdentifier" || true

# ── 3. Build the .dmg ─────────────────────────────────────────────────────────
DMG="$BUILD_DIR/${VOL_NAME}.dmg"
echo "▶︎ Building $DMG"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "$VOL_NAME" \
    --app-drop-link 480 170 \
    --icon "${APP_NAME}.app" 160 170 \
    --window-size 660 360 \
    "$DMG" "$APP_PATH"
else
  echo "   (create-dmg not found — using hdiutil. 'brew install create-dmg' gives a prettier window.)"
  STAGE="$BUILD_DIR/dmg-stage"
  rm -rf "$STAGE"; mkdir -p "$STAGE"
  cp -R "$APP_PATH" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

# ── 4. Notarize ───────────────────────────────────────────────────────────────
echo "▶︎ Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# ── 5. Staple (so it opens offline, no re-check) ──────────────────────────────
echo "▶︎ Stapling ticket…"
xcrun stapler staple "$DMG"

# ── 6. Verify Gatekeeper acceptance ───────────────────────────────────────────
echo "▶︎ Verifying…"
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" || true

echo ""
echo "✅ Done → $DMG"
echo "   Upload to your host (e.g. GitHub Releases) and point code-pet.com/download at it."
