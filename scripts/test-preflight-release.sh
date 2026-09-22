#!/usr/bin/env bash
#
# Tests for preflight-release.sh — the check that refuses to start a release build when the
# machine cannot finish one.
#
#   ./scripts/test-preflight-release.sh
#
# The three lookups it performs are indirected through $IDENTITY_CMD, $NOTARY_CMD and
# $PROFILE_DIR so this can feed fixtures. Without that seam the only way to test the
# failure path would be to revoke a certificate — so the failure path would never be tested, and the failure path is
# the entire point of a preflight.
#
# The fixtures are real output, not invented: the identity listings are the shape
# `security find-identity -v -p codesigning` prints on this machine, and the notary line is
# verbatim what `xcrun notarytool history` printed when no profile was stored.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/preflight-release.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# Fixtures are written as plain files, then referenced by path. (A heredoc inside a
# command substitution does not survive bash's parser here — it reads the body in the outer
# context and chokes on the first unquoted paren.)
mk() { cat > "$TMP/$1"; }

mk ids-dev-only <<'EOF'
  1) AAAA "Apple Development: Someone (U794VA7B66)"
  2) BBBB "3rd Party Mac Developer Installer: My Murror Inc (YL72VTKBR7)"
     2 valid identities found
EOF

# The trap this guards against: Apple ships intermediate CAs whose names BEGIN with
# "Developer ID". A substring match on "Developer ID" reports success on a machine that
# holds only those and no signing key at all — which is exactly what this machine looks
# like today, so a loose check would have passed here and failed at export.
mk ids-ca-only <<'EOF'
  1) AAAA "Apple Development: Someone (U794VA7B66)"
  2) CCCC "Developer ID Certification Authority"
     2 valid identities found
EOF

mk ids-with-devid <<'EOF'
  1) AAAA "Apple Development: Someone (U794VA7B66)"
  2) DDDD "Developer ID Application: My Murror Inc (YL72VTKBR7)"
     2 valid identities found
EOF

mk notary-missing <<'EOF'
Error: No Keychain password item found for profile: codepet-notary
EOF

mk notary-expired <<'EOF'
Error: HTTP status code: 401. Unable to authenticate
EOF

mk notary-ok <<'EOF'
Successfully received submission history.
  history
    --------------------------------------------------
EOF

# Profile fixtures are DIRECTORIES, because preflight inspects each profile separately.
# Only the strings it greps for matter, so these are not whole plists.
mkdir -p "$TMP/prof-good" "$TMP/prof-empty" "$TMP/prof-devonly" "$TMP/prof-otherapp"

cat > "$TMP/prof-good/devid.provisionprofile" <<'EOF'
<key>Name</key><string>Codepet Developer ID</string>
<key>ProvisionsAllDevices</key><true/>
<string>YL72VTKBR7.app.murror.codepet</string>
EOF

# The trap: this profile carries the right bundle id and is useless for distribution. It is
# the "Mac Team Provisioning Profile" Xcode makes for local development, and it is what an
# otherwise-blocked machine actually has. Matching on the bundle id alone passes here.
cat > "$TMP/prof-devonly/dev.provisionprofile" <<'EOF'
<key>Name</key><string>Mac Team Provisioning Profile: app.murror.codepet</string>
<key>ProvisionedDevices</key><array><string>00008103-000000000000000E</string></array>
<string>YL72VTKBR7.app.murror.codepet</string>
EOF

# A real Developer ID profile, for the wrong app. Guards the mirror-image mistake: matching
# on ProvisionsAllDevices without checking which bundle id it covers.
cat > "$TMP/prof-otherapp/other.provisionprofile" <<'EOF'
<key>Name</key><string>Something Else Developer ID</string>
<key>ProvisionsAllDevices</key><true/>
<string>YL72VTKBR7.app.murror.somethingelse</string>
EOF

PROF_GOOD="$TMP/prof-good"
PROF_EMPTY="$TMP/prof-empty"
PROF_DEVONLY="$TMP/prof-devonly"
PROF_OTHERAPP="$TMP/prof-otherapp"

DEV_ONLY="$TMP/ids-dev-only"
CA_ONLY="$TMP/ids-ca-only"
WITH_DEVID="$TMP/ids-with-devid"
NOTARY_MISSING="$TMP/notary-missing"
NOTARY_EXPIRED="$TMP/notary-expired"
NOTARY_OK="$TMP/notary-ok"

check() {
  local label="$1" expected="$2" ids="$3" notary="$4" profiles="${5:-$PROF_GOOD}" out actual
  out="$(IDENTITY_CMD="cat $ids" NOTARY_CMD="cat $notary" PROFILE_DIR="$profiles" \
         "$SCRIPT" 2>&1)"
  actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "  ✓ $label"
    pass=$((pass + 1))
  else
    echo "  ✗ $label — expected exit $expected, got $actual"
    printf '%s\n' "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
}

# Asserts the refusal actually SAYS the useful thing. An exit code alone would let the
# message rot into "error" while the test stayed green — and the message is most of the
# value here, because the fix is a request to another person, not a command.
says() {
  local label="$1" ids="$2" notary="$3" needle="$4" profiles="${5:-$PROF_GOOD}" out
  out="$(IDENTITY_CMD="cat $ids" NOTARY_CMD="cat $notary" PROFILE_DIR="$profiles" \
         "$SCRIPT" 2>&1)"
  if printf '%s' "$out" | grep -q "$needle"; then
    echo "  ✓ $label"
    pass=$((pass + 1))
  else
    echo "  ✗ $label — output did not mention '$needle'"
    fail=$((fail + 1))
  fi
}

echo "▸ preflight-release.sh"

check "refuses when there is no Developer ID cert"        1 "$DEV_ONLY"   "$NOTARY_OK"
check "is not fooled by the Developer ID CA certificates" 1 "$CA_ONLY"    "$NOTARY_OK"
check "refuses when the notary profile is missing"        1 "$WITH_DEVID" "$NOTARY_MISSING"
check "refuses when the notary profile no longer authenticates" 1 "$WITH_DEVID" "$NOTARY_EXPIRED"
check "refuses when BOTH are missing"                     1 "$DEV_ONLY"   "$NOTARY_MISSING"
check "passes when both are present"                      0 "$WITH_DEVID" "$NOTARY_OK"

says "points at the written request when the cert is missing" \
  "$DEV_ONLY" "$NOTARY_OK" "docs/developer-id-request.md"
says "gives the store-credentials command when notarization is missing" \
  "$WITH_DEVID" "$NOTARY_MISSING" "store-credentials"

check "refuses when there is no provisioning profile at all" \
  1 "$WITH_DEVID" "$NOTARY_OK" "$PROF_EMPTY"
check "refuses when the profile directory does not exist" \
  1 "$WITH_DEVID" "$NOTARY_OK" "$TMP/prof-nonexistent"
check "is not fooled by the DEVELOPMENT profile for the same bundle id" \
  1 "$WITH_DEVID" "$NOTARY_OK" "$PROF_DEVONLY"
check "is not fooled by a Developer ID profile for a DIFFERENT app" \
  1 "$WITH_DEVID" "$NOTARY_OK" "$PROF_OTHERAPP"

says "names the portal path when the profile is missing" \
  "$WITH_DEVID" "$NOTARY_OK" "Distribution ▸ Developer ID" "$PROF_EMPTY"
says "warns that double-clicking installs it where xcodebuild cannot see it" \
  "$WITH_DEVID" "$NOTARY_OK" "Device Management" "$PROF_EMPTY"

echo ""
if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail of $((pass + fail))"
  exit 1
fi
echo "All $pass test(s) passed."
