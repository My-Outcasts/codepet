# Request: create a Developer ID Application certificate — Codepet (macOS)

**To:** the **Account Holder** of the *My Murror Inc* Apple Developer account
**Team ID:** `YL72VTKBR7`
**Send the certificate back to:** Truong Giang Nguyen Vu — giang@murror.app

---

> **STATUS — fulfilled 2026-09-22.** The certificate exists. It was created by the Account
> Holder from a **CSR generated on Giang's Mac**, so the private key never left that machine
> and Option 1's `.p12` hand-off below was never used. **Prefer the CSR route next time** —
> it is the Apple portal's own flow ("Choose File… select the certificate request file"), and
> the Account Holder limit is about who clicks *Create*, not about whose key it is.
>
> | | |
> |---|---|
> | Subject | `Developer ID Application: My Murror Inc (YL72VTKBR7)` |
> | Issuer | `Developer ID Certification Authority`, **OU=G2** |
> | Valid | 2026-09-22 → **2031-09-17** |
> | Serial | `6A3F310C8D1F25E123D309F78F8AF176` |
> | Public key SHA-256 | `6fd308e9…2befd3b` — matches the CSR, so it pairs with the private key already in the login keychain |
>
> Two things are still owed, and neither needs the Account Holder:
> 1. **Export a `.p12` backup** under a strong password into the company password vault. The
>    CSR route's one weakness is that the key exists on exactly one Mac, and a dead Mac cannot
>    be recovered from — there is no self-revoke to reclaim the slot (see Security notes).
> 2. **Notarization credentials**, which are a separate App Store Connect Team API key (role
>    Developer) and do **not** involve this signing key at all.

---

## Summary

Codepet (a macOS app, bundle ID `app.murror.codepet`) is about to ship as a direct download
from murror.app. For macOS to let people open it, the build has to be signed with a
**Developer ID Application** certificate and then submitted to Apple for notarization.

The *My Murror Inc* account did not have one until 2026-09-22 (see STATUS above). Creating
it takes about **5 minutes**; everything below is the record of how, kept for the next time.

---

## Why this has to come from you

Apple only lets the **Account Holder** create Developer ID certificates. No other role sees the
option — not even Admin.

This was checked on Giang's machine (Admin role): in Xcode ▸ Settings ▸ Accounts ▸ Manage
Certificates, the `+` menu offers only three items — *Apple Development*, *Apple Distribution*
and *Mac Installer Distribution*. There is no *Developer ID Application* entry. That is a
permissions limit, not a misconfiguration.

**The certificates we already have cannot be used instead.** The account holds *Apple
Distribution* and *Mac Installer Distribution*, which are the Mac App Store set. Codepet cannot
ship through the App Store: the App Store requires App Sandbox to be enabled, and Codepet needs
to launch external processes (`node`, the Claude Code CLI) as a core part of what it does —
turning the sandbox on stops every AI feature in the product from working. Developer ID is the
only technically viable route.

---

## Option 1 — Recommended: create the certificate and export a `.p12`

### Step 1. Create it

1. Open **Xcode ▸ Settings ▸ Accounts**
2. Select your Apple ID on the left. On the right, select the **My Murror Inc** team
3. Click **Manage Certificates…**
4. Click the **+** button in the bottom-left corner
5. Choose **Developer ID Application**

After a few seconds the certificate appears in the list, already installed in your keychain.

> **On limits:** Apple allows 5 Developer ID Application certificates per account, each valid
> for 5 years. Treat the cap as permanent: you **cannot** self-revoke a Developer ID
> certificate to free a slot (see Security notes below), so **never create one just to test
> the flow** — every attempt spends a slot until Apple's security team releases it.

> **⚠️ Choose the G2 Sub-CA.** Creating the certificate asks which intermediate to chain to,
> and **defaults to *Previous Sub-CA*** — which expires **2027-02-01**. *G2* runs to
> **2031-09-16**. "Previous" reads as the conservative option and is the trap: accepting the
> default yields a certificate with a few months of life that cannot be revoked to get the
> slot back. Whoever creates it has to switch this by hand.
>
> Verify it after importing — the expiry must read ~2031, not 2027:
>
> ```sh
> security find-certificate -c "Developer ID Application" -p \
>   | openssl x509 -noout -subject -issuer -dates
> ```

### Step 2. Export it as a `.p12`

1. Open **Keychain Access**
2. In the left column choose the **login** keychain, then the **My Certificates** category
   *(it must be "My Certificates" — that is the category that includes the private key)*
3. Find **Developer ID Application: My Murror Inc (YL72VTKBR7)**
4. Right-click it ▸ **Export "Developer ID Application: My Murror Inc…"**
5. Set the format to **Personal Information Exchange (.p12)** and save it as
   `developer-id-murror.p12`
6. Set a **password on the file** — please use a strong one, do not leave it blank
7. Enter your Mac login password when macOS asks permission to export the key

> **Check this before sending:** click the small triangle to the left of the certificate's name
> in Keychain Access. If a key entry appears underneath it, you are good — the `.p12` will
> contain the private key. If nothing appears, the exported file cannot sign anything and the
> export has to be redone.

### Step 3. Send it back

Send the **`.p12` file** and the **password** through **two different channels** — for example
the file by email and the password by message. Please do not put the password in the same email
as the file.

---

## Security notes (please read)

The `.p12` contains the **private key** of a signing certificate. Anyone holding both the file
and its password can sign software as *My Murror Inc*. So:

- Use a strong password and send it separately, as above
- Delete the file from Downloads and empty the Trash once it has been sent
- **Revocation is not a quick undo, and this doc used to say otherwise.** Apple: *"You can't
  revoke Developer ID or Pass Type ID certificates using your developer account. Instead, send
  a request to Apple at product-security@apple.com to revoke these types of certificates."* So
  a leak means emailing Apple and waiting an unknown length of time, and for the whole wait
  whoever holds the key can sign software that macOS trusts as *My Murror Inc*. **That is the
  real reason not to move a private key between machines** — there is no undo button
- **And a revocation, once granted, breaks installed copies.** Apple: *"Any Developer ID app
  signed with a certificate that has been revoked can no longer be installed nor launch if
  it's already installed."* Do not confuse this with **expiry**, which is harmless: an app
  built while the certificate was valid keeps launching forever after the certificate expires.
  An earlier version of this doc claimed notarized apps survive a *revocation*. They do not.
  (Apple's pages genuinely disagree here — two of three say only that users can no longer
  *install*. The Developer ID-specific page is the strict one, so plan for the strict reading)

---

## Option 2 — If you would rather not let the private key leave your machine

Two alternatives; either works:

**2a. Transfer the Account Holder role to Giang.** In App Store Connect ▸ **Users and Access**,
the current Account Holder can transfer the role to another team member. Note that an account
has exactly one Account Holder, so you would no longer hold that role afterwards. Once
transferred, Giang creates the certificate on his own machine and the private key never leaves
it.

**2b. Keep the certificate and sign the releases yourself.** The certificate stays on your
machine and you run the packaging command each time a new version ships. This is the safest
option for the key, but it puts you in the loop for every release — worth choosing only if
releases are rare.

---

## How to confirm it worked

After Giang imports the `.p12` (double-click the file, enter the password), this command in
Terminal:

```sh
security find-identity -v -p codesigning
```

should list:

```
Developer ID Application: My Murror Inc (YL72VTKBR7)
```

Once that line appears, we are done — the rest (packaging, notarization, publishing) is already
automated in the repo and needs nothing further from you.

---

## Reference

| Item | Value |
|---|---|
| Team name | My Murror Inc |
| Team ID | `YL72VTKBR7` |
| Bundle ID | `app.murror.codepet` |
| Certificate needed | Developer ID Application |
| Distribution channel | Direct download from murror.app (not the Mac App Store) |

Any questions, please contact giang@murror.app.
