# Request: create a Developer ID Application certificate — Codepet (macOS)

**To:** the **Account Holder** of the *My Murror Inc* Apple Developer account
**Team ID:** `YL72VTKBR7`
**Send the certificate back to:** Truong Giang Nguyen Vu — giang@murror.app

---

## Summary

Codepet (a macOS app, bundle ID `app.murror.codepet`) is about to ship as a direct download
from murror.app. For macOS to let people open it, the build has to be signed with a
**Developer ID Application** certificate and then submitted to Apple for notarization.

The *My Murror Inc* account does not have one yet. Creating it takes about **5 minutes**.

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
> for 5 years. If the menu says you have reached the limit, review the list at
> developer.apple.com/account/resources/certificates and revoke any that are no longer in use.

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
- If you ever suspect it has leaked, you can **revoke** the certificate at any time at
  developer.apple.com/account/resources/certificates. After revoking, a new one can simply be
  created — apps that were already notarized keep working

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
