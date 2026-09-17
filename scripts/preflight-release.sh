#!/usr/bin/env bash
#
# Check the two credentials a release needs, BEFORE spending a build on finding out.
#
#   ./scripts/preflight-release.sh
#
# WHY THIS EXISTS. `package-macos.sh` archives first and exports second, so a missing
# Developer ID certificate is discovered several minutes in, after a clean Release build has
# already run. Measured on this machine: the archive succeeds, then `xcodebuild
# -exportArchive` prints "No signing certificate \"Developer ID Application\" found" five
# times and exits. The message is fine; the timing is not. Both credentials are local and
# cost a second to check, so they are checked at the top.
#
# It also names what to DO. "No signing certificate found" is accurate and tells someone who
# has not read the release runbook nothing about why they cannot simply create one — on this
# account only the Account Holder can, which is a request to another human rather than a
# command to run. `docs/developer-id-request.md` is that request, written out.
#
# TESTABILITY. The two lookups are indirected through env vars so
# `scripts/test-preflight-release.sh` can feed fixtures instead of the real keychain. A
# preflight that can only be tested by revoking a certificate would never be tested.
set -uo pipefail

NOTARY_PROFILE="${NOTARY_PROFILE:-codepet-notary}"
TEAM_ID="${TEAM_ID:-YL72VTKBR7}"

# Overridable seams. Default to the real thing; tests point them at fixtures.
IDENTITY_CMD="${IDENTITY_CMD:-security find-identity -v -p codesigning}"
NOTARY_CMD="${NOTARY_CMD:-xcrun notarytool history --keychain-profile $NOTARY_PROFILE}"

fail=0

# ── 1. Developer ID Application certificate ───────────────────────────────────
# Grep for the leaf certificate by name. NOT just "Developer ID": the Apple intermediate CAs
# are called "Developer ID Certification Authority" and live in every keychain, so a looser
# match reports success on a machine that cannot sign anything. That is not hypothetical —
# it is what this machine looks like right now.
identities="$($IDENTITY_CMD 2>/dev/null)"
if printf '%s' "$identities" | grep -q "Developer ID Application"; then
  echo "   ✓ Developer ID Application certificate present"
else
  echo "✗ No \"Developer ID Application\" certificate in the keychain."
  echo ""
  echo "  This is the certificate that lets macOS open the app on someone else's Mac."
  echo "  The Apple Development certs on this machine are NOT a substitute: an app signed"
  echo "  with one runs only on Macs registered in the team's provisioning profile."
  echo ""
  echo "  On the My Murror Inc account ($TEAM_ID) only the ACCOUNT HOLDER can create it —"
  echo "  an Admin does not see the option in Xcode. The request to send them is written"
  echo "  out at docs/developer-id-request.md."
  fail=1
fi

# ── 2. Notarization credentials ───────────────────────────────────────────────
# Runs a real query rather than checking that a keychain item exists, because a profile that
# exists and no longer authenticates fails in exactly the same place as a missing one — at
# the end, after the .dmg has been built.
notary_out="$($NOTARY_CMD 2>&1)"
if printf '%s' "$notary_out" | grep -qE "No Keychain password item found|error: *Cannot|Unable to authenticate|HTTP status code: 401"; then
  echo "✗ Notarization profile \"$NOTARY_PROFILE\" is missing or no longer authenticates."
  echo ""
  echo "  Store it once with:"
  echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
  echo "      --apple-id \"<your-apple-id>\" --team-id \"$TEAM_ID\" \\"
  echo "      --password \"<app-specific-password>\""
  echo ""
  echo "  The app-specific password comes from appleid.apple.com ▸ Sign-In & Security."
  fail=1
else
  echo "   ✓ Notarization profile \"$NOTARY_PROFILE\" answers"
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Stopping before the build. Nothing above needs a build to fix."
  exit 1
fi

echo "   ✓ preflight passed — this machine can cut a release"
