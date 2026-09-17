#!/usr/bin/env bash
#
# Tests for verify-sidecars-bundled.sh — the guard that stops a sidecar-less Codepet.app
# from being packaged and published.
#
#   ./scripts/test-verify-sidecars.sh
#
# These exist because of the rule in CLAUDE.md: a guard with no test that goes red when the
# guard is deleted is not protecting anything. Delete the `missing` check in
# verify-sidecars-bundled.sh and cases 2, 3 and 4 below fail.
#
# No Xcode, no signing, no network: the fixtures are directories named `*.app`, which is all
# the guard actually inspects. That is why it runs on the ubuntu job.
set -uo pipefail

GUARD="$(cd "$(dirname "$0")" && pwd)/verify-sidecars-bundled.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

# Build a fixture .app. Every name in $2 gets a non-empty file; names in $3 get an empty one.
make_app() {
  local name="$1" present="$2" empty="${3:-}"
  local app="$TMP/$name.app"
  mkdir -p "$app/Contents/Resources"
  for f in $present; do echo "// bundled" > "$app/Contents/Resources/$f"; done
  for f in $empty;   do : > "$app/Contents/Resources/$f"; done
  echo "$app"
}

check() {
  local label="$1" expected="$2" app="$3"
  "$GUARD" "$app" >/dev/null 2>&1
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    echo "  ✓ $label"
    pass=$((pass + 1))
  else
    echo "  ✗ $label — expected exit $expected, got $actual"
    fail=$((fail + 1))
  fi
}

ALL="chatSidecar.js oneShotSidecar.js vcSidecar.js"

echo "▸ verify-sidecars-bundled.sh"

# 1. The shipping case: all three present and non-empty.
check "accepts an app with all three sidecars" 0 "$(make_app complete "$ALL")"

# 2. The bug this guard exists for. One missing bundle is enough to break the feature that
#    needs it while the other two keep working — so the app looks partly fine, which is
#    worse than wholly broken for diagnosis.
check "rejects an app missing vcSidecar.js" 1 \
  "$(make_app partial "chatSidecar.js oneShotSidecar.js")"

# 3. The clean-checkout case: build-sidecar.sh never ran at all.
check "rejects an app with no sidecars at all" 1 "$(make_app bare "")"

# 4. A failed esbuild run leaves a zero-byte file. It passes an existence test and is just
#    as dead at runtime, which is why the guard uses `-s` rather than `-f`.
check "rejects a zero-byte sidecar" 1 \
  "$(make_app truncated "chatSidecar.js oneShotSidecar.js" "vcSidecar.js")"

# 5. Usage errors exit 2, distinct from 1, so a caller can tell "you pointed me at nothing"
#    apart from "this app is not shippable".
check "exits 2 when the path is not a bundle" 2 "$TMP/does-not-exist.app"

echo ""
if [ "$fail" -gt 0 ]; then
  echo "FAILED: $fail of $((pass + fail))"
  exit 1
fi
echo "All $pass test(s) passed."
