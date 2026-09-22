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
BUNDLE_ID="${BUNDLE_ID:-app.murror.codepet}"

# Overridable seams. Default to the real thing; tests point them at fixtures.
IDENTITY_CMD="${IDENTITY_CMD:-security find-identity -v -p codesigning}"
NOTARY_CMD="${NOTARY_CMD:-xcrun notarytool history --keychain-profile $NOTARY_PROFILE}"
# A DIRECTORY, not a command, unlike the two above. The check below has to reason about
# each profile separately: a machine can hold a development profile for this bundle id AND
# a Developer ID profile for a different one, and concatenating them would match both
# halves of the test and report success. Pointing tests at a directory of fixture files
# keeps that distinction testable.
PROFILE_DIR="${PROFILE_DIR:-$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles}"

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

# ── 3. Developer ID provisioning profile ──────────────────────────────────────
# Added after the first real release attempt, where preflight passed both checks above and
# the run then died in `-exportArchive` — two minutes of Release build later — on a third
# credential nobody had thought of. Catching that is this script's entire job.
#
# Two things make the failure hard to read, so this names both:
#
#   * `signingStyle: automatic` NEVER reads this directory. It mints a profile through
#     cloud signing instead, and on this account that answers 403. So a founder can have
#     the right profile sitting on disk and still be told "No profiles were found".
#     scripts/ExportOptions.plist uses `manual` for exactly this reason — do not change it
#     back.
#   * Double-clicking a .provisionprofile does NOT put it here. On macOS it installs into
#     System Settings ▸ Device Management, where xcodebuild cannot see it, and the profile
#     then shows up in the UI as installed while every build keeps failing.
#
# A copy lives at scripts/Codepet_Developer_ID.provisionprofile so a fresh clone needs one
# `cp` rather than a portal round-trip. It is not a secret — a provisioning profile carries
# the PUBLIC certificate, the team id and the entitlements, and nothing that can sign.
#
# `ProvisionsAllDevices` is what distinguishes a Developer ID profile from the development
# profile that also carries this bundle id. Matching on the bundle id alone reports success
# on a machine that can only build for registered Macs.
profile_found=""
if [ -d "$PROFILE_DIR" ]; then
  for f in "$PROFILE_DIR"/*.provisionprofile; do
    [ -f "$f" ] || continue
    if grep -qa "$TEAM_ID\.$BUNDLE_ID" "$f" && grep -qa "ProvisionsAllDevices" "$f"; then
      profile_found="$f"
      break
    fi
  done
fi

if [ -n "$profile_found" ]; then
  echo "   ✓ Developer ID provisioning profile for $BUNDLE_ID present"
else
  echo "✗ No Developer ID provisioning profile for \"$BUNDLE_ID\" where xcodebuild looks."
  echo ""
  echo "  The app declares keychain-access-groups, so a Developer ID build REQUIRES an"
  echo "  embedded provisioning profile. The certificate alone is not enough."
  echo ""
  echo "  A copy is committed to this repo, so on a fresh clone this is one command:"
  echo ""
  echo "      cp scripts/Codepet_Developer_ID.provisionprofile \\"
  echo "         \"$PROFILE_DIR/\""
  echo ""
  echo "  If that copy has expired, make a new one:"
  echo "    1. developer.apple.com/account ▸ Certificates, Identifiers & Profiles ▸ Profiles"
  echo "       ▸ + ▸ Distribution ▸ Developer ID ▸ App ID $BUNDLE_ID ▸ Download"
  echo "    2. COPY it into $PROFILE_DIR, and commit it here so the next machine is spared"
  echo ""
  echo "  Do NOT just double-click the file. Double-clicking installs it into"
  echo "  System Settings ▸ Device Management, which xcodebuild does not read. The profile"
  echo "  then shows as installed while every build keeps failing with:"
  echo "      No profiles for '$BUNDLE_ID' were found"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Stopping before the build. Nothing above needs a build to fix."
  exit 1
fi

echo "   ✓ preflight passed — this machine can cut a release"
