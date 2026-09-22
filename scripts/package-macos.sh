#!/usr/bin/env bash
#
# Package Codepet for direct (non-App-Store) distribution:
#   sidecars → archive → export (Developer ID) → .dmg → SIGN the .dmg → notarize
#   → staple → verify with spctl
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
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

PROJECT="CodePet.xcodeproj"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Codepet.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTS="scripts/ExportOptions.plist"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── 0. Preflight ──────────────────────────────────────────────────────────────
# Both credentials this needs are local and cost a second to check, and without either one
# the run dies at step 3 or step 6 — several minutes of Release build later. Measured: the
# archive succeeds, then `-exportArchive` prints "No signing certificate \"Developer ID
# Application\" found" and stops. Checking first also lets the message name the FIX, which
# for the certificate is a request to the Account Holder rather than a command to run.
#
# SKIP_PREFLIGHT=1 for the case where the checks themselves are what is broken.
if [ "${SKIP_PREFLIGHT:-0}" != "1" ]; then
  echo "▶︎ Preflight…"
  ./scripts/preflight-release.sh
fi

echo "▶︎ Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

# ── 1. Bundle the sidecars ────────────────────────────────────────────────────
# MUST run before the archive. The three bundles are gitignored build output, so a clean
# checkout has none, and the synchronized resource group copies whatever is on disk at
# archive time — meaning a skipped build here silently produces an app with no local
# runner. That app launches fine and then tells the founder `localUnavailable` on every
# AI feature. Step 4 verifies the result rather than trusting this.
echo "▶︎ Building the sidecars…"
./scripts/build-sidecar.sh

# ── 2. Archive ────────────────────────────────────────────────────────────────
echo "▶︎ Archiving ($CONFIGURATION)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  clean archive

# ── 3. Export with Developer ID (hardened runtime, notarization-ready) ─────────
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

# ── 4. Guard: the sidecars are IN the app ─────────────────────────────────────
# Step 1 building them is not proof they shipped — the Xcode resource copy sits in between
# and is silent when it drops something. The check lives in its own script so that
# scripts/test-verify-sidecars.sh can exercise it without an archive or a signing identity.
./scripts/verify-sidecars-bundled.sh "$APP_PATH"

# ── 5. Build the .dmg ─────────────────────────────────────────────────────────
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

# ── 5b. Sign the .dmg ITSELF ──────────────────────────────────────────────────
# The app inside is signed and hardened, but a disk image is a separate code object and
# neither `create-dmg` nor `hdiutil` signs it. Nothing downstream notices: notarization
# still returns Accepted and the ticket still staples, so this script reported success
# while producing a file Gatekeeper refuses.
#
# Measured 2026-09-22, on the first .dmg this pipeline ever built:
#     xcrun notarytool submit  →  status: Accepted
#     xcrun stapler validate   →  The validate action worked!
#     spctl -a -t open         →  rejected   source=no usable signature
#
# Order matters. Signing has to happen BEFORE notarization, because re-signing a stapled
# image invalidates the ticket that was stapled to it.
echo "▶︎ Signing ${DMG}…"   # braces REQUIRED: bash swallows the following "…" into the name
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
codesign -dv --verbose=2 "$DMG" 2>&1 | grep -E "Authority=Developer ID|Timestamp" || true

# ── 6. Notarize ───────────────────────────────────────────────────────────────
echo "▶︎ Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# ── 7. Staple (so it opens offline, no re-check) ──────────────────────────────
echo "▶︎ Stapling ticket…"
xcrun stapler staple "$DMG"

# ── 8. Verify Gatekeeper acceptance ───────────────────────────────────────────
echo "▶︎ Verifying…"
xcrun stapler validate "$DMG"

# NO `|| true` HERE. This is the only check in the script that looks at the .dmg the way
# a stranger's Mac will, and it is the only one that caught the unsigned image above —
# every other step passed. Swallowing its exit code turns the last line of defence into a
# decoration, which is exactly what happened on the 2026-09-22 run.
spctl -a -t open --context context:primary-signature -vv "$DMG"

echo ""
echo "✅ Done → $DMG"
echo "   Next: ./scripts/release-github.sh  →  publishes it behind murror.app/download"
