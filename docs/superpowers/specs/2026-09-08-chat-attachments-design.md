# Chat attachments: what she sees, and how much she can send

**Date:** 8 September 2026
**Status:** approved, not implemented
**Scope:** the founder's attachment experience in chat — the transcript echo, the composer,
the caps, and drag-and-drop. Links are explicitly NOT in this spec; see *Deferred*.

## Why this exists

Three defects reported on 8 September, all from one founder session with screenshots and
two screen recordings.

1. **Attachments reached the model and vanished from her own transcript.** She sent five
   screenshots; her bubble showed one sentence and no sign of them.
   *Root cause:* `CopilotMessage.attachments` was written by `CompanyStore.sendMessage` and
   read back by the same method to rebuild `history[].attachments` — a correct round trip
   with **no view reading the field**. `CopilotBubble` never drew it.
   *Status:* fixed ahead of this spec (`MessageAttachments.swift`, 7 tests passing,
   mutation-checked) — but that work exists **only as uncommitted files in the main
   checkout**, on a branch 125 commits behind. It is not on `main` and no CI has seen it.
   **Implementation step one is porting it onto this branch**, the way #131's fix had to be
   re-applied rather than copied when `main` had moved underneath it. Carried into this spec
   because everything below changes the view it introduced.

2. **A fourth image was discarded in silence.** She picked four; three appeared; nothing was
   said.
   *Root cause:* `AttachmentPicker.pickAndEncode` trims with `panel.urls.prefix(limit)`. Its
   `rejected` list collects only files that **failed to encode**, so a file removed by
   `prefix` is reported nowhere. `AttachmentBudget.admit` then sees three, accepts three, and
   `refusalMessage` returns nil. The `noticeRow` that would have explained it was never given
   anything to say.
   *This is not the cap working.* The panel offered her a fourth selection and then took it
   back without a word — the same shape as the enable-card that fired silently (7 Sep).

3. **The composer names files it cannot show.** Three filename pills
   (`IMG_4779.PNG  IMG  ×`) consume the whole row at 380pt and cannot answer the one question
   she has: *which* screenshot is that.

## Decisions

| Decision | Value | Why |
|---|---|---|
| Files per message | **10** (was 3) | The count is a sanity guard; `AttachmentBudget.maxTotalBase64Bytes` (20 MB) is the cap that actually protects the request. A downscaled screenshot is 1–3 MB, so bytes bind first in real use. |
| `ContextPin.max` | **3, unchanged** | A pin is grounding, a file is payload. They shared a ceiling only because they share a row. |
| Composer treatment | **Wrapping thumbnail tiles** | Everything attached stays visible in the control she is about to spend credits from. No hidden state behind a counter. |
| Transcript treatment | **Thumbnails above the text** | Already shipped. Same tile as the composer, so a file looks the same before and after sending. |
| Drag-and-drop | **In scope** | Lands on the same admit-and-explain pipeline this spec already rewrites. |
| Links | **Deferred** | Needs a transport decision, not a composer decision. See *Deferred*. |

## Architecture

Four units, each with one job.

### `AttachmentBudget` — the only thing that decides what is admitted

Already exists, already pure, already tested. This spec **removes its competitor**: the
picker's `prefix(limit)`. After this change there is exactly one place that can refuse a
file, and it returns a structured reason.

`admit` gains an overflow reason it does not have today: refusal by **count** as well as by
bytes. `refusalMessage` must name both, and must name the files — "3 attached; IMG_4782.PNG
and 1 more were not" is actionable, "some files were skipped" is not.

### `AttachmentPicker` — encodes, never decides

`pickAndEncode` stops trimming. The panel returns every selection; each is encoded; the whole
set goes to `admit`. `rejected` keeps its current meaning (unsupported type, unreadable,
over `maxBytes`) and is no longer overloaded with "silently over the count."

One guard: a pathological selection (hundreds of files) should not be base64-encoded before
being refused. Encoding walks the selection in order and stops once the accumulated ENCODED
bytes of the files kept so far exceed `maxTotalBase64Bytes` — the point past which no further
file can be admitted anyway. Every file the walk reached is still reported, so the founder is
told what was left out and why. This is a performance guard, not a second cap: it can only
stop early where `admit` would have refused everything after it regardless. The existing
per-file `maxBytes` check inside `encode` is unchanged and still runs first.

`encode(_ url:)` is already public. Drag-and-drop uses it directly, so the drop path and the
panel path converge before anything is decided.

### `MessageAttachments.swift` — one tile, two callers

Introduced this morning for the transcript. It grows a small seam rather than being copied:

- `AttachmentThumbnailCache` — unchanged. Decode-once, resample to 200px, keyed on
  `ChatAttachment.id` (`path#byteCount`, so an edited file re-decodes).
- `AttachmentTile` — the tile. Takes an optional `onRemove`; the composer passes one and gets
  a hover `×`, the transcript passes nil and gets a static thumbnail.
- `MessageAttachmentLayout.split` — unchanged. Images preview, everything else is a chip.

The composer's private `pill(icon:title:gloss:remove:)` stays for **pins**, which have no
pixels. It is not extended to files.

### `ChatComposer` — the drop target

`.onDrop(of: [.fileURL])` on the composer surface. A drop resolves URLs, encodes each through
`AttachmentPicker.encode`, and hands the set to `admit` — the same three calls the `+` menu
makes. A visible drop affordance while dragging (border highlight), because an invisible drop
target is indistinguishable from a broken one.

## Data flow

```
  + menu ─┐
          ├─→ AttachmentPicker.encode(url)* ─→ AttachmentBudget.admit ─┬─→ attachments
  drop ───┘                                                            └─→ attachNotice
                                                                            (noticeRow)
```

Both entry points converge before admission. Neither can drop a file without producing a
reason, which is the invariant this spec exists to establish.

## Error handling

Every refusal reaches `attachNotice`, which `pillRow` already renders and which already has a
dismiss button. The notice is assigned on every pick — including the empty string case, so a
clean pick clears a stale refusal. That behaviour exists today and is preserved.

Three refusal reasons must be distinguishable in the text: **unsupported type**, **over the
file count**, **over the total size**. A founder who hits the size cap and reads "10 files
max" will try again with nine and fail again.

## Testing

Pure units, mutation-tested — a test that passes with and without the rule it protects is not
protecting anything (`CLAUDE.md`, Working agreements).

- `admit` refuses by count and names the refused files; refuses by bytes and says so
  differently. Break each rule in turn and watch the specific test go red.
- `pickAndEncode` no longer trims: given more URLs than the cap, every one is encoded and
  handed to `admit` (the seam is the encode step, driven from fixture URLs — `encode` is
  already exposed for this).
- The tile split and the thumbnail cache are covered by `MessageAttachmentStripTests`.
- **Not unit-testable, verified by build and by hand:** the wrap layout, the hover `×`, the
  drop highlight, and "an images-only turn still draws". Stated rather than implied.

## Out of scope

- **Links.** A URL has no bytes to encode, so it is not an attachment; it must be fetched or
  handed to search. On the local Claude Code transport, `--tools` carries `WebSearch` and
  `Read` but **not `WebFetch`** — so "paste a URL and read that page" is a transport
  decision. Its own spec.
- **Persistence.** `CopilotMessage.attachments` is base64 in memory and its doc forbids
  writing it to Firestore. Thumbnails therefore vanish when a thread is reopened. Pre-existing,
  unchanged here, and a real decision someone should make deliberately.
- Click-to-enlarge, reordering, paste-to-attach.
