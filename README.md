# Codepet

**Codepet** is an AI coding companion for macOS. You adopt a pixel-art character that
guides you through learning to build with agentic coding tools — 7 characters, 16 skills,
one journey.

> Native SwiftUI app for macOS 13+. Built with Firebase (Auth + Firestore).

## Requirements

- macOS 13 or later
- Xcode 15 or later
- A Firebase project (the bundled `GoogleService-Info.plist` points at the Codepet project)

## Build & run

```sh
open CodePet.xcodeproj
# Select the "codepet" scheme → Run (⌘R)
```

Swift Package dependencies (Firebase iOS SDK) resolve automatically on first build; pinned
versions live in `CodePet.xcodeproj/.../Package.resolved`.

## Project layout

```
codepet/                 # All Swift source
  App/                   # @main entry, Firebase init, environment objects, router
  Models/                # App + game state, skill/lesson data
  Managers/              # Auth, persistence, sound, theme
  Services/              # Firestore cloud sync, MCP bridge
  Views/                 # SwiftUI screens (Home, Skills, Tips, Profile, Dictionary, …)
  Assets.xcassets/       # Pixel-art sprites, kingdom scenes, app icon
  Resources/Fonts/       # Minecraft pixel font + Inter
codepetTests/            # Unit tests
scripts/                 # macOS release tooling (notarized .dmg packaging)
CLAUDE.md                # Working instructions for AI coding agents
```

## Distribution

Codepet ships as a direct, notarized `.dmg` download (outside the Mac App Store). See
[`scripts/RELEASE.md`](scripts/RELEASE.md) for the full release runbook:

```sh
./scripts/package-macos.sh    # archive → Developer ID sign → notarize → staple → .dmg
./scripts/release-github.sh   # publish the .dmg to a GitHub Release
```

## License

© Codepet. All rights reserved.
