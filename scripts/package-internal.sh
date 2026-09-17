#!/usr/bin/env bash
#
# Package Codepet for INTERNAL testing — registered Macs only, no notarization.
#
#   ./scripts/package-internal.sh
#
# ── WHAT THIS IS, AND WHAT IT IS NOT ─────────────────────────────────────────
# This is NOT the public download. It exists because the public download needs a
# Developer ID Application certificate that only the Apple account's Account Holder can
# create (see docs/developer-id-request.md), and that can take a while. This route needs
# nothing anyone here does not already have.
#
# The build is signed with an Apple Development certificate and carries the team's
# development provisioning profile, so it runs ONLY on the Macs listed in that profile.
# Everyone else gets "damaged or incomplete" — which is Gatekeeper refusing an unregistered
# device, not a broken build.
#
# ── WHY THIS IS USABLE WHERE AN UNSIGNED BUILD IS NOT ────────────────────────
# The app declares `keychain-access-groups` under $(AppIdentifierPrefix), which resolves
# only for a team-signed binary. An ad-hoc build cannot reach its keychain group, so
# Firebase auth fails and the tester is stuck on the sign-in screen with an app that looks
# broken. This build is team-signed and the profile grants `YL72VTKBR7.*`, so sign-in works.
# Verified: exported, launched from the exported path, stayed up, quit cleanly.
#
# ── ADDING A TESTER ──────────────────────────────────────────────────────────
# An ADMIN can do this — it does not need the Account Holder:
#   1. On their Mac:  ▸ About This Mac ▸ More Info ▸ System Report ▸ Hardware
#      Copy "Provisioning UDID" (or run: system_profiler SPHardwareDataType | grep Provisioning)
#   2. developer.apple.com/account/resources/devices ▸ + ▸ platform macOS ▸ paste the UDID
#   3. Re-run this script. `-allowProvisioningUpdates` regenerates the profile with the new
#      device baked in.
set -euo pipefail

SCHEME="${SCHEME:-codepet}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-YL72VTKBR7}"
VOL_NAME="${VOL_NAME:-Codepet Internal}"

PROJECT="CodePet.xcodeproj"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/internal.xcarchive"
EXPORT_DIR="$BUILD_DIR/internal-export"
EXPORT_OPTS="scripts/ExportOptions-development.plist"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▶︎ Cleaning"
rm -rf "$ARCHIVE" "$EXPORT_DIR"; mkdir -p "$BUILD_DIR"

# Same first step as the public pipeline, for the same reason: the bundles are gitignored
# build output, and a build without them tells the tester `localUnavailable` on every AI
# feature. A tester finding that reports it as a bug in the product.
echo "▶︎ Building the sidecars…"
./scripts/build-sidecar.sh

echo "▶︎ Archiving ($CONFIGURATION)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  -allowProvisioningUpdates \
  clean archive

echo "▶︎ Exporting (development)…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates

APP_PATH="$(/bin/ls -d "$EXPORT_DIR"/*.app | head -1)"

# Same guard the public pipeline uses. Nothing about this route makes a sidecar-less build
# less broken.
./scripts/verify-sidecars-bundled.sh "$APP_PATH"

# ── Who can actually run this ────────────────────────────────────────────────
# Printed rather than assumed. The single most likely support question is "it says the app
# is damaged", and the answer is almost always that the Mac is not on this list.
echo "▶︎ Runs on these registered Macs only:"
security cms -D -i "$APP_PATH/Contents/embedded.provisionprofile" > "$BUILD_DIR/.profile.plist" 2>/dev/null
python3 - "$BUILD_DIR/.profile.plist" <<'PY'
import plistlib, sys
d = plistlib.load(open(sys.argv[1], 'rb'))
devices = d.get('ProvisionedDevices') or []
for x in devices:
    print(f"     {x}")
print(f"   ({len(devices)} device(s); profile expires {d.get('ExpirationDate')})")
PY
rm -f "$BUILD_DIR/.profile.plist"

DMG="$BUILD_DIR/Codepet-internal.dmg"
echo "▶︎ Building $DMG"
STAGE="$BUILD_DIR/internal-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# A README inside the .dmg, because the quarantine step below cannot be discovered. A tester
# who hits "damaged or incomplete" with no note assumes the build is broken and stops.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Codepet — internal test build
=============================

This is an INTERNAL build. It runs only on Macs registered with the developer
account; it is not the public release.

INSTALL
  1. Drag Codepet into Applications.
  2. Open Terminal and run this ONCE:

       xattr -dr com.apple.quarantine /Applications/codepet.app

  3. Open Codepet normally.

WHY STEP 2
  Anything that arrives by download, AirDrop or chat is tagged "quarantined" by
  macOS. Public releases clear that by being notarized by Apple; this build is
  not notarized, so the tag is removed by hand instead. It is a one-time step.

IF IT SAYS "DAMAGED OR INCOMPLETE"
  That almost always means this Mac is not registered on the account, not that
  the download failed. Send your Provisioning UDID to giang@murror.app:

       system_profiler SPHardwareDataType | grep "Provisioning UDID"

BEFORE YOU START
  Codepet runs its AI work on your own Claude Code, so you need Claude Code
  installed and signed in, plus Node.js. Without them the app opens and tells
  you what is missing.
TXT

hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo ""
echo "✅ Done → $DMG"
echo "   Internal only. Testers must run the xattr line in READ ME FIRST.txt once."
echo "   The public download still needs a Developer ID cert — docs/developer-id-request.md"
