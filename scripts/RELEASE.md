# Codepet — macOS direct-download release runbook

How to cut a notarized `Codepet.dmg` for the **"Download for macOS"** button on
code-pet.com. This is direct distribution (Developer ID + notarization), **not**
the Mac App Store.

Current version: **1.0 (build 2)** — bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
in `codepet.xcodeproj` for each new build.

---

## One-time setup

1. **Apple Developer Program** — must be a paid membership (Team `YL72VTKBR7`,
   or whichever team is enrolled).
2. **Developer ID Application certificate** — Xcode ▸ Settings ▸ Accounts ▸
   *Manage Certificates* ▸ **+** ▸ *Developer ID Application*. (This is different
   from the "Apple Development" certs already on the machine.)
3. **Notarization credentials** stored once as a keychain profile named
   `codepet-notary`:
   ```sh
   xcrun notarytool store-credentials "codepet-notary" \
     --apple-id "YOU@APPLE.ID" --team-id "YL72VTKBR7" \
     --password "APP_SPECIFIC_PASSWORD"      # appleid.apple.com ▸ Sign-In & Security ▸ App-Specific Passwords
   ```
   *(or with an App Store Connect API key: `--key AuthKey_XXXX.p8 --key-id KEYID --issuer ISSUER_ID`)*
4. *(Optional, prettier DMG window)* `brew install create-dmg`.

---

## Cut a build

```sh
./scripts/package-macos.sh
```

This archives → exports with Developer ID (Hardened Runtime) → builds the `.dmg`
→ notarizes → staples → verifies. Output: `build/Codepet.dmg`.

Override defaults inline if needed:
```sh
TEAM_ID=ABCDE12345 NOTARY_PROFILE=my-profile ./scripts/package-macos.sh
```

---

## Host it (GitHub Releases)

One command publishes the `.dmg` to a GitHub Release on **`My-Outcasts/codepet`**
(public, so downloads need no auth):

```sh
./scripts/release-github.sh                 # tags v<marketing>-build<build>, e.g. v1.0-build2
# or: TAG=v1.0-build3 ./scripts/release-github.sh
```

Requires `gh auth status` to be logged in (with `repo` scope). The script
creates/updates the release, attaches `build/Codepet.dmg`, and marks it
**latest**, so this stable permalink always points at the newest build:

```
https://github.com/My-Outcasts/codepet/releases/latest/download/Codepet.dmg
```

The website button already points at **`code-pet.com/download/Codepet.dmg`**,
which 307-redirects to that permalink (see `next.config.ts` in devpet-landing).
So the button URL never changes — only run `release-github.sh` per build.

> Note: this creates a release/tag on the *remote* repo's default branch and
> uploads an asset. It does not push from the local app repo (which has separate
> git lineage), so it's safe to run from here.

---

## What users see (Gatekeeper first-open)

Because the app is notarized but distributed outside the App Store, macOS asks
the user to confirm the first launch. Put these steps on the download page:

1. Open **Codepet.dmg** and drag **Codepet** into **Applications**.
2. Open **Applications**, then **right-click Codepet ▸ Open**.
3. In the dialog, click **Open** once. (After this first time it launches
   normally.)

> If macOS says it "cannot be opened," go to **System Settings ▸ Privacy &
> Security**, scroll to the Codepet message, and click **Open Anyway**.

Because the build is notarized + stapled, no "unidentified developer" hard-block
should appear — only this one-time confirmation.

---

## Troubleshooting

- **Export fails / no Developer ID identity** — the Developer ID Application cert
  isn't installed or the team is wrong. Re-check step 2 / set `TEAM_ID`.
- **Notarization "Invalid"** — run `xcrun notarytool log <submission-id>
  --keychain-profile codepet-notary` to see which file/signature failed (usually
  a nested binary missing Hardened Runtime or a secure timestamp).
- **Verify manually**:
  ```sh
  spctl -a -t open --context context:primary-signature -v build/Codepet.dmg
  xcrun stapler validate build/Codepet.dmg
  ```
