# Testing Codepet from source

There is no signed build to hand out yet — the project has only `Apple Development`
certificates, which run on registered machines and nowhere else. Until a
distribution certificate exists, testers clone this repo and build it themselves.

Everything below was verified on 2026-08-05 by cloning this repo fresh from GitHub
at `a89f0d6` and building it. Where something is *not* verified, it says so.

## Before you start: two hard requirements

**macOS 26.2 or newer.** The deployment target is 26.2, so the app will not launch
on anything older even if it builds. Check with `sw_vers -productVersion`. This is
the requirement most likely to stop you, and no workaround exists short of lowering
the target for the whole project.

**Xcode 26.2 or newer**, for the same reason.

## Build it

```bash
git clone https://github.com/My-Outcasts/codepet.git
cd codepet
open CodePet.xcodeproj
```

Swift Package Manager resolves Firebase and GoogleSignIn on first open — a few
minutes, and it needs network. `Package.resolved` is committed, so everyone gets
the same versions.

Then press ⌘R. Whether that works depends on signing, below.

## Signing

The app must be signed. Firebase Auth fails at runtime in an unsigned build, so
`CODE_SIGNING_ALLOWED=NO` is not a shortcut — it produces an app that launches,
looks fine, and cannot log in.

### If you are in the MURROR team (YL72VTKBR7)

Nothing to do. Xcode picks the team up and ⌘R works.

### If you are not

You will hit one of these:

```
error: Signing for "codepet" requires a development team.
       Select a development team in the Signing & Capabilities editor.
```

```
error: No profiles for 'app.murror.codepet' were found
```

The bundle identifier `app.murror.codepet` belongs to team YL72VTKBR7, and no other
team can register it. So:

1. Select the `codepet` target → **Signing & Capabilities**
2. Set **Team** to your own (a free personal Apple ID team is enough to build and
   run locally)
3. Change **Bundle Identifier** to something unique, e.g. `dev.<yourname>.codepet`

Xcode generates a provisioning profile for the new identifier by itself. Do not
commit those two changes.

If the **Keychain Sharing** entitlement blocks profile generation, edit
`codepet/codepet.entitlements` and change the `keychain-access-groups` entry to
`$(AppIdentifierPrefix)<your new bundle id>`. Unverified — no one has needed it yet,
but it is the first place to look, because that entitlement currently names a third
identifier (`com.murror.codepet`) that matches neither the app nor anything else.

Changing the bundle identifier does not break Firebase. The committed
`GoogleService-Info.plist` already registers `com.murror.codepet` while the app ships
as `app.murror.codepet`, and email/password sign-in works in production regardless —
the API key and project id are what matter, not the identifier. You may see a
console warning about the inconsistency; ignore it.

## Signing in

**Use email/password.** Create an account from the app's sign-in screen.

Anonymous sign-in is disabled in the Firebase console, so there is no guest mode.

Google Sign-In is wired up (`AuthManager.swift`, `GoogleSignIn-iOS`), but Google's
OAuth client is tied to a bundle identifier, and this project's identifiers already
disagree with each other. Nobody has tested Google Sign-In after a bundle-id change.
If you want to find out, go ahead — but do not let it block you, use
email/password.

## What to test

The feature under active development is the **Virtual Company**: departments that
convene in the copilot chat and argue out a decision.

It does not trigger on every message. The router convenes a room only when your
question is a genuine trade-off with something real at stake — so ask one:

> Should we raise the price to $49 and lose the self-serve tier?

not

> What should I work on today?

You should see a room appear with two to four departments, each holding a position,
disagreeing in the open, and a synthesis at the end. If a room never appears, that
may be correct behaviour (the router has an escape hatch), not a bug — say what you
asked when you report it.

Six of the nine departments have been observed convening on production: product,
finance, engineering, design, support, legal. `marketing` and `sales` have not been
seen yet — reports involving them are especially useful.

**A convened decision costs roughly $0.20 of real API budget**, an ordinary chat
turn about $0.005. Please do not loop on it.

## Reporting

Include: your macOS version, whether you changed the bundle id, the exact question
you typed, and what appeared. For a crash, the Console.app log for `codepet`.

One thing to know when reading test output: the Xcode **test suite** crashes its own
host process on 26.2 — around 27 of ~970 tests never finish and `xcodebuild test`
exits 65 on a clean checkout. That is a toolchain bug, not the app. The app itself
is unaffected. Do not spend time on it.
