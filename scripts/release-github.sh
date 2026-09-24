#!/usr/bin/env bash
#
# Publish (or update) the GitHub Release that hosts Codepet.dmg.
#
# Host: My-Outcasts/codepet (PUBLIC → unauthenticated downloads work). Both download
# pages — murror.app/download (repo Murror/devpet-landing) and the GitHub Pages one in
# this repo — point at the `latest` permalink:
#     https://github.com/My-Outcasts/codepet/releases/latest/download/Codepet.dmg
# So this script just publishes the latest release with the .dmg attached; neither
# website is touched when a new version ships.
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

# ── The asset name is part of the public URL, so it is NOT free to change ─────
# `releases/latest/download/<name>` resolves `latest` to the newest tag and then looks for
# an asset by EXACT name — measured against a third-party repo: a real name answers 200, and
# a name that is not in the current release 404s even though `latest` resolved correctly.
#
# So every release must attach the asset under the same name or every printed link dies at
# once: the button on code-pet.com/download, the GitHub Pages page, RELEASE.md, and anything
# anyone has pasted into a chat. `gh`'s own releases show the failure mode — their assets
# embed the version (gh_2.101.0_macOS_amd64.zip), so their `latest/download/` permalink is
# broken by design for anyone who hardcodes a filename.
#
# $DMG is overridable, which is useful for pointing at a build elsewhere on disk and
# dangerous for renaming the asset. This allows the first and refuses the second.
ASSET_NAME="Codepet.dmg"
if [ "$(basename "$DMG")" != "$ASSET_NAME" ]; then
  echo "✗ Refusing to publish: the asset must be named $ASSET_NAME, got $(basename "$DMG")."
  echo ""
  echo "  The download URL is releases/latest/download/$ASSET_NAME and it matches by exact"
  echo "  filename. Publishing under another name breaks every link already printed —"
  echo "  the website button, the Pages site, the runbook, and any pasted into a chat."
  echo ""
  echo "  To publish a build from elsewhere on disk, keep the name:"
  echo "    DMG=/some/path/$ASSET_NAME ./scripts/release-github.sh"
  exit 1
fi

# Derive a tag from the Xcode version unless TAG is provided: v<marketing>-build<build>.
MKT="$(xcodebuild -showBuildSettings -scheme codepet 2>/dev/null | awk -F' = ' '/ MARKETING_VERSION /{gsub(/ /,"",$2);print $2; exit}')"
BUILD="$(xcodebuild -showBuildSettings -scheme codepet 2>/dev/null | awk -F' = ' '/ CURRENT_PROJECT_VERSION /{gsub(/ /,"",$2);print $2; exit}')"
TAG="${TAG:-v${MKT:-1.0}-build${BUILD:-1}}"
TITLE="Codepet ${MKT:-1.0} (build ${BUILD:-1})"

# ── Release notes ─────────────────────────────────────────────────────────────
# These used to end "on first launch right-click → Open", which is the instruction for an
# app Gatekeeper REFUSES. This build is signed with Developer ID, notarized, and stapled —
# `spctl -a -t open` answers `accepted / source=Notarized Developer ID` — so it opens by
# double-click like anything else. Worse, that bypass was removed in macOS 15: the reader
# would have followed a step that no longer exists, on an app that never needed it, and
# concluded it was untrusted.
#
# The deployment target belongs here for the opposite reason — it is the one thing that
# WILL stop someone, and nothing else tells them. `SwiftExplicitDependency` in the archive
# log resolves `-target-triple arm64-apple-macos26.2`.
MIN_MACOS="${MIN_MACOS:-26.2}"
NOTES="Direct download for macOS. Signed with a Developer ID certificate and notarized by Apple, so it opens like any other app — no right-click, no security warning.

**Requires macOS ${MIN_MACOS} or later.**

Install: open the .dmg and drag Codepet to Applications."

echo "▶︎ Repo:  $REPO"
echo "▶︎ Tag:   $TAG"
echo "▶︎ Asset: $DMG"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "▶︎ Release $TAG exists — replacing the .dmg asset…"
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --latest
else
  echo "▶︎ Creating release ${TAG}…"
  gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "$TITLE" \
    --notes "$NOTES" \
    --latest
fi

echo ""
echo "✅ Published. murror.app/download/Codepet.dmg now resolves to:"
echo "   https://github.com/$REPO/releases/latest/download/Codepet.dmg"
