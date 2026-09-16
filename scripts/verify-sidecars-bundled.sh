#!/usr/bin/env bash
#
# Refuse to ship a Codepet.app that has no local runner inside it.
#
#   ./scripts/verify-sidecars-bundled.sh build/export/Codepet.app
#
# WHY THIS IS A SEPARATE FILE. It is the one part of `package-macos.sh` that can be tested
# without an Apple Developer ID, a notary profile, and a ten-minute archive — so it lives
# where `test-verify-sidecars.sh` can hand it a fixture and assert on the exit code. Inline
# in the packaging script it would be unreachable by any test, which for a guard means
# unverified.
#
# WHAT IT CATCHES. `build-sidecar.sh` writing the three bundles is not proof they reached
# the .app. Xcode's synchronized resource group performs that copy and is silent when it
# does not — it has dropped a file before over nothing but an extension it had an opinion
# about (see the header of build-sidecar.sh). The resulting app is not visibly broken: it
# launches, it looks right, and then `resolveSidecarPath` returns nil and the founder is
# told `localUnavailable` on every AI feature in the product. Discovering that from a
# public download page is the expensive way to discover it.
#
# `-s` and not `-f`: a zero-byte bundle is a failed esbuild run, and it passes an
# existence check while being just as dead at runtime.
set -euo pipefail

APP="${1:-}"
[ -n "$APP" ] || { echo "usage: $0 <path-to-.app>" >&2; exit 2; }
[ -d "$APP" ] || { echo "✗ not a bundle: $APP" >&2; exit 2; }

# The names are the ones Swift asks for by resource name + type, e.g.
# `bundle.path(forResource: "chatSidecar", ofType: "js")` in LocalChatStreamer. Renaming a
# bundle means editing that call site too, so this list is deliberately literal rather than
# globbed — a glob would happily pass a file no Swift code can find.
SIDECARS=(chatSidecar.js oneShotSidecar.js vcSidecar.js)

RES="$APP/Contents/Resources"
missing=()
for f in "${SIDECARS[@]}"; do
  [ -s "$RES/$f" ] || missing+=("$f")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "" >&2
  echo "✗ Refusing to package: sidecar bundle(s) missing or empty in the exported app" >&2
  for f in "${missing[@]}"; do echo "    - $f" >&2; done
  echo "  looked in: $RES" >&2
  echo "" >&2
  echo "  scripts/build-sidecar.sh writes these to codepet/Resources/. If they are there," >&2
  echo "  the bundler is fine and the Xcode resource copy is the suspect." >&2
  exit 1
fi

echo "   ✓ sidecars bundled: ${SIDECARS[*]}"
