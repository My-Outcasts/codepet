#!/usr/bin/env bash
#
# Publish (or update) the GitHub Release that hosts Codepet.dmg.
#
# Host: My-Outcasts/codepet (PUBLIC → unauthenticated downloads work). The
# website button points at code-pet.com/download/Codepet.dmg, which redirects
# (see devpet-landing next.config.ts) to:
#     https://github.com/My-Outcasts/codepet/releases/latest/download/Codepet.dmg
# So this script just publishes the latest release with the .dmg attached;
# the website URL never changes.
#
# NOTE: this only creates a release + uploads an asset on the REMOTE repo (a tag
# on its default branch). It does NOT push from / depend on the local app repo's
# git history.
#
# ── PREREQS ───────────────────────────────────────────────────────────────────
#   - gh CLI authenticated with `repo` scope:  gh auth status
#   - A notarized build at build/Codepet.dmg:  ./scripts/package-macos.sh
#
# ── USAGE ─────────────────────────────────────────────────────────────────────
#   ./scripts/release-github.sh                 # tag from app version → v1.0-build2
#   TAG=v1.0-build3 ./scripts/release-github.sh
#
set -euo pipefail

REPO="${REPO:-My-Outcasts/codepet}"
DMG="${DMG:-build/Codepet.dmg}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

[ -f "$DMG" ] || { echo "✗ $DMG not found — run ./scripts/package-macos.sh first."; exit 1; }

# Derive a tag from the Xcode version unless TAG is provided: v<marketing>-build<build>.
MKT="$(xcodebuild -showBuildSettings -scheme codepet 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION /{gsub(/ /,"",$2);print $2; exit}')"
BUILD="$(xcodebuild -showBuildSettings -scheme codepet 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION /{gsub(/ /,"",$2);print $2; exit}')"
TAG="${TAG:-v${MKT:-1.0}-build${BUILD:-1}}"
TITLE="Codepet ${MKT:-1.0} (build ${BUILD:-1})"

echo "▶︎ Repo:  $REPO"
echo "▶︎ Tag:   $TAG"
echo "▶︎ Asset: $DMG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "▶︎ Release $TAG exists — replacing the .dmg asset…"
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --latest
else
  echo "▶︎ Creating release $TAG…"
  gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "Direct macOS download (notarized). Install: open the .dmg, drag Codepet to Applications; on first launch right-click → Open." \
    --latest
fi

echo ""
echo "✅ Published. code-pet.com/download/Codepet.dmg now resolves to:"
echo "   https://github.com/$REPO/releases/latest/download/Codepet.dmg"
