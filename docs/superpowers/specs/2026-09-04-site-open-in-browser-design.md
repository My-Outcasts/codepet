# The landing page cannot leave the app

**Status:** design, awaiting founder review.
**Date:** 2026-09-04
**Founder decision:** open it in the default browser. A real hosted URL is a separate project.

## The finding

A run can produce a genuine landing page, and `SiteViewer` renders it properly — but there is no
way out of the app. Verified: the viewer has exactly two affordances, a **Preview | Code**
picker and **Copy HTML** (`DeliverableViewers.swift:773-782`). The preview is
`SiteHTMLWebView(html:)`, an in-app `WKWebView` handed an HTML *string* built on demand by
`SiteViewer.buildHTML(payload)` (`:761`). Nothing is ever written to disk.

Grepped for an escape hatch: the only `NSWorkspace.shared.open` calls in the app are in Settings
and the Tips tab, all unrelated. There is no file export, no `.html` write, no URL.

So a founder can look at their page inside a 620pt-capped dock column, or paste raw markup onto
the clipboard and find somewhere to put it themselves. Reported by the founder as wanting the
link to *"not only display within the app but be accessible directly, like Claude or ChatGPT
do."*

## Design

An **Open in browser** action beside Copy HTML: write `html` to a file and hand it to
`NSWorkspace`.

- **Where it writes.** `FileManager.default.temporaryDirectory`, one file per deliverable id —
  `codepet-site-<deliverable-id>.html`. Derived from the id, not random and not timestamped, so
  opening the same page twice replaces one file instead of littering; and stable enough that a
  browser reload shows the current draft after a Redo.
- **Why temp and not Documents.** The founder did not ask to keep a file; they asked to see the
  page. A draft they have not approved should not deposit artifacts in their Documents folder.
  Save-as was offered and declined for now — noted below.
- **The write is fail-soft and reported.** On failure the action surfaces the existing error
  affordance rather than silently doing nothing; a button that sometimes does nothing is worse
  than one that says why.
- **Label.** en `Open in browser` / vi `Mở trong trình duyệt`, beside Copy HTML in the same row.
  Not "Open" alone — this card already has an **Open the live page** cue on the chat side
  (added 2026-09-04) which routes to this in-app viewer, and two different "Open"s meaning two
  different destinations on one path is the confusion worth avoiding.

**The pure part.** `SiteExport.fileURL(forDeliverableId:)` and
`SiteExport.write(html:to:) throws` are separated from the view, so the naming and the failure
path are testable without `NSWorkspace` and without a browser. The view holds only the
`NSWorkspace.shared.open` call, which is untestable by nature and should therefore be the only
untested line.

**A `file://` URL is not shareable, and the label must not imply it is.** This gets the founder
a real browser with a real page — zoom, devtools, print-to-PDF, a URL bar — and gets them
nothing they can send to another person. That is the honest boundary of this change.

## Explicitly out of scope

- **A hosted `https` URL.** This is what "view it through Google" ultimately implies, and it is
  a project rather than a fix: it needs storage, a URL scheme, a decision about whether an
  unapproved draft is publicly reachable, and an answer for what happens when the founder edits
  the page. Worth speccing on its own if shareable links are the real goal.
- **Save as…** Offered and declined. Trivial to add later on top of `SiteExport`, which is why
  the write is a separate seam from the open.
- **The other twelve deliverable kinds.** Only `.site` is a document a browser renders better
  than the app does. A doc or a checklist gains nothing from this.
- **Cleaning up temp files.** The OS reclaims its own temp directory; a cleanup path is code
  that can only fail.

## Tests

| Guard | Why |
| --- | --- |
| The filename is derived from the deliverable id | opening twice replaces, never litters |
| The filename is filesystem-safe for an arbitrary id | ids are UUIDs today, and `demo-mur-site` in fixtures — a future id with a slash must not escape the directory |
| Writing produces a file whose contents are exactly `buildHTML(payload)` | the browser must show the same page as the preview, not a re-derivation |
| A write into an unwritable location throws rather than traps | fail-soft; the founder sees an error, not a hang |
| The action appears only for `.site` | it is meaningless for the other kinds |
| The vi label is present and non-empty | the app ships bilingual; a missing translation shows an English string in a Vietnamese UI |

## Cost

~40 lines plus tests: one small `SiteExport` helper, one button in `SiteViewer`, two labels.
