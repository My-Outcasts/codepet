# Codepet — handoff context (15 Oct 2026)

Audience: Astro and the Claude Code session Astro starts. Read `CLAUDE.md` alongside this;
it is the authority on architecture, the Virtual Company contract and the landmines. This
file covers what CLAUDE.md does not: the state of the repo today, what was in flight, and
what the team decided recently.

Verified against GitHub and git on 15 Oct 2026 unless marked otherwise.

## 1. Who and why

- Dominich (Giang) and Mona built Codepet through build 13. On 15 Oct Astro moved both to
  Murror (top priority): Dominich to safety & privacy / eval, Mona to marketing & branding.
- Astro takes Codepet, works on the product vision, and may hand it back later.
- Mona handed her Codepet work to Dominich, who consolidated both into this one handoff.
  **Nothing is in flight**: zero open PRs, every feature branch is merged.

## 2. Repo state

- Repo: `My-Outcasts/codepet`, work on `main` via PRs. `main` head at handoff: `d61f46d`
  (Merge #252, 13 Oct).
- Cloud Functions: `functions/` in this repo is the only deploy source (Firebase project
  `devpet-8f4b1`). They are deployed but **inert**: the Anthropic API key was deleted on
  26 Aug, and every AI call runs locally on the founder's own Claude Code plan
  (see "Running on the founder's Claude plan" in CLAUDE.md).
- Specs and plans: `docs/superpowers/specs/` and `docs/superpowers/plans/`. Newest specs:
  `2026-10-09-department-notebook-design.md`, `2026-10-09-suggest-room-design.md`,
  `2026-09-24-team-build-design.md`.

## 3. Builds and releases — read before cutting the next one

| Build | Where it went | Notes |
|---|---|---|
| 8 | **Public** — GitHub release `v1.0-build8` (5 Oct), live at code-pet.com/download | Latest public |
| 9 | Internal | Bump is on `main` (`CURRENT_PROJECT_VERSION = 9`) |
| 10, 12, 13 | Internal `.dmg`s, tested by Mona | Bumps live only on local branches `release/v1.0-build10/12/13` on Dominich's Mac — **never merged** |

Consequences:
- `main` still says build 9, but testers have build 13 installed. **The next build must be
  14 or higher**, or macOS treats it as older.
- Build 13 was cut from `ada4b3c` (= #246–#250). `main` now also has #251 and #252, which
  no build has shipped yet.
- Public release, in order: `./scripts/preflight-release.sh` → `./scripts/package-macos.sh`
  → `./scripts/release-github.sh`. The last one **publishes publicly at once** — the
  download page follows `releases/latest`. Details and the four traps from the first real
  run: CLAUDE.md "Shipping the app from the website", and `scripts/RELEASE.md`.
- Internal build for registered Macs: `./scripts/package-internal.sh` (no notarization;
  tester runs `xattr -dr com.apple.quarantine` once).
- Signing needs the Developer ID cert, which exists **only on Dominich's Mac** (private key
  never exported; a `.p12` backup to the company vault is still owed). To release from
  another Mac, either Dominich exports a `.p12` for you, or you create a new cert via CSR —
  and remember the cap is 5 and certs cannot be self-revoked. Notarization uses keychain
  profile `codepet-notary`, which also lives on that Mac.
- **Launching a release build is not a check until someone signs in** (landmine 7).

## 4. What the product does now (since build 8)

Full list: `SHIPPED-SINCE-BUILD-8.md`. The shape:

- **Departments behave like departments.** Asking one gets that department's role prompt and
  its own desk (#247); each keeps a notebook of the facts and decisions it learned (#248);
  Ask knows today's date (#249); a department can *offer* the room and the founder convenes
  it with one press (#250).
- **Room / meeting UI** is quieter: one card, departments side by side (#238), stances shown
  in words so a raw `do_not_proceed` never reaches the card (#251), lock-in leaves one
  receipt that names the pick (#241).
- **Team Build** waits for the founder's call before planning (#243), and chat knows the
  team took the request (#239).
- **Chat**: email/DM draft cards survive a relaunch (#242); remembered facts fold into one
  quiet line (#252); drafts can be discarded, not only approved (#220, #221).
- **First run**: plan grant asked at "Analyze" and the real roadmap awaited (#232); stage
  starts at "Just an idea" (#234).
- **Sales has its own pet**: Vega, the frog (#244).

## 5. Working on it

- Build: `xcodebuild build -scheme codepet -destination 'platform=macOS' -configuration Debug`.
  Anything signed-in needs a **signed** build (team `YL72VTKBR7`).
- After any change under `functions/src/`: `./scripts/build-sidecar.sh`, or the app reports
  the local runner missing.
- Tests: run per suite with `-only-testing:`. A full `xcodebuild test` exits 65 on Xcode
  26.2 because the XCTest host crashes when a `@MainActor ObservableObject` deallocates —
  a toolchain bug, not a regression. `cd functions && npm test` for the backend.
- Destructive or demo flows: prototype mode, e.g.
  `open codepet.app --args -CODEPET_MOCK_CHAT YES -CODEPET_DEMO_PROJECT murror`.
- `smoke/` holds the end-to-end smoke test that drives the real app (`smoke/smoke`).
- Working agreements the team followed: branch + PR, never commit to `main` directly;
  commit messages carry the why; every guard gets a test that goes red without it; verify
  each fix in the running app, not only in tests.

## 6. Decisions and direction to carry forward

- **Astro, 15 Oct, on the "run a whole company solo" mockups**
  (https://claude.ai/artifact/9zbiuQeahVNW6Xkd1pT1fg): *after onboarding, chat is the
  focus. Dashboard and everything else are secondary; reports, progress and all information
  have to show up in chat.* That mockup set (prompt → 8 departments → master plan → daily
  Today screen) is therefore **not approved** as designed. No code was written for it.
  Slack thread: https://murrorapp.slack.com/archives/C03LH1C680P/p1791969614969089
- Only PLAN mode convenes the room (cost: ~$0.20 per convened decision vs ~$0.005 otherwise).
  Any chat-first redesign should keep that gate (`ChatMode.convenesRoom`).
- Chained runs do not stop for approval; nothing is filed to the Library without the
  founder's approval. Both are founder decisions recorded in CLAUDE.md.

## 7. Open items

See `OPEN-ITEMS.md`.
