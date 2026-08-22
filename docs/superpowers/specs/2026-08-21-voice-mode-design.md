# Codepet — voice mode

**Status:** designed, approved by the founder 21 Aug 2026. Not built.
**Branch:** to be cut from `feat/composer-controls` (the composer control row this adds a button to
lives there, not on `main`).
**Scope:** Swift only. **No `functions/` change and no API cost** — both halves of voice mode are local
macOS frameworks. See §3.
**Relates to:** `2026-08-21-composer-controls-design.md` (the control row this joins). It does not amend
the SSE contract or the two-mode product design.

---

## 1. What this is, and what it is not

The founder pointed at ChatGPT's composer and named the **waveform** icon, not the mic beside it. Those
are two different features and the distinction is the whole scope of this spec:

| ChatGPT icon | Feature | In scope? |
|---|---|---|
| 🎤 mic | **Record** — press-and-hold, it becomes editable text, you still read the reply | ~~No~~ **YES, added 22 Aug — see §10** |
| ⦙⦙⦙ waveform | **Voice mode** — hands-free spoken conversation, it talks back | **Yes** |

A third thing was designed first and rejected as a misreading: a per-reply `▶ listen` button that has
each department's pet read its own answer aloud. That is a smaller, separate feature which happens to
share the speaking code; it is parked in §8, not built here.

**Voice mode is an input/output method, not a separate conversation.** Everything said and heard lands
in the ordinary transcript as ordinary messages. Close the overlay and the exchange is there to scroll,
copy, retry, and thumb — the same messages the same store produced. Nothing about `sendChat` changes.

## 2. What was decided, and by whom

Founder, 21 Aug 2026:

| # | Decision |
|---|---|
| 1 | **Voice mode**, the waveform — not dictation, and not the per-reply read-aloud |
| 2 | ~~The surface is a **takeover overlay**~~ **REVERSED 22 Aug — see below** |
| 5 | **Voice lives in the composer.** It grows in place; the chat stays visible. No overlay, no orb |
| 3 | ~~A turn ends after **1.2s of silence** — automatic, not hold-to-talk~~ **REVERSED 21 Aug, see below** |
| 4 | **A turn is sent only when the founder taps ✓.** ✕ discards it. Nothing auto-sends |

**Decision 3 was reversed after watching Claude's own voice mode**, and the reason is
that §4 of this spec had already argued against it without noticing.

This spec says the live transcript is shown because "recognition gets names and jargon
wrong, and a founder who cannot see what was heard will not trust the reply. Seeing it
wrong *before* it sends is the difference between a bug and a retype." Auto-sending
1.2s later means she cannot act on what she has just read. We had built the diagnosis
and no remedy.

It compounds with §7's own credit warning: voice makes turns cheap to spend without
noticing, and a misheard "Codepet", "nova" or a department name auto-sent and cost
0.25 credits with no way to stop it. ✕ is cheap insurance for exactly the words §7
predicts the recognizer will get wrong.

Measured from a screen recording of Claude's voice mode, 21 Aug: the composer holds a
live transcript and a level meter, with ✕ and ✓ available the entire time the founder
is speaking; the mic stays open through the reply, so barge-in still works; and
nothing is ever sent without the tap.

**Consequence: `VoiceTurn` and `silenceThreshold` lose their only consumer.** With an
explicit confirm there is no silence deadline, so there is no threshold left to feel
wrong — which was the one thing this spec said could only be settled by the founder
talking to the built thing. The type and its tests are deleted rather than left
unused; they are in git if a silence affordance is ever wanted.

**Decision 2 was reversed on 22 Aug**, after the founder compared the built takeover
against a recording of Claude's voice mode and said it was not working the same way.
It was right that it wasn't: we had matched Claude on the *logic* — explicit ✓/✕,
nothing auto-sends, mic open through the reply, spoken turns landing as ordinary
messages — and diverged on the surface, which is the part you actually see.

Measured from the recordings, 21-22 Aug. Claude's composer **grows in place**: the
live transcript sits top-left in grey italic reading like a draft, a thin horizontal
bar-waveform runs along the bottom, and ✕ (grey) with ✓ (blue, filled) sit
bottom-right. `Cancel` appears only during `Connecting…`. There is **no orb and no
overlay** — the conversation stays visible the whole time. State is carried by
placeholder text (`Connecting…` → transcript → `Listening…` → `Claude is speaking…`)
plus a warm glow at the bottom edge.

So the surface becomes: composer expands, chat visible, no orb. **The tradeoff being
given up is focus; what is bought is being able to see the conversation you are
having** — which matters more here than it does for Claude, because a Codepet reply
is signed by a department and a pet, and the founder loses that context behind a
takeover.

**What this does NOT change.** Every unit below the surface is surface-agnostic and
survives: `VoiceSession`, `SentenceSplitter`, `PetVoice`, `SpeakingQueue`,
`VoiceLevel`, `TurnTranscript`, `RenewalBudget`, `VoiceReplyDriver`,
`VoicePermission`, both audio services, and the five statics that carry the
invariants (`takeTurn`, `abandonTurn`, `ensureListening`,
`streamEndBelongsToVoiceTurn`, `replyEnded`). They take their inputs explicitly for
exactly this reason. `VoiceModeOverlay` and `VoiceOverlayLayoutTests` are deleted.

**Two pieces of chrome the composer must still carry**, because they are requirements
rather than decoration and Claude's own composer has neither:
- **The privacy line** (§3). English is on-device; Vietnamese goes to Apple's
  servers. It has to be visible, not a footnote.
- **The running credit count** (§7). Voice makes turns cheap to spend without
  noticing.
Both fit as one compact line inside the expanded composer — `2 credits · on-device` —
which is smaller than the overlay gave them but still legible and still not a
footnote.

Five further calls were made in the design and are open to reversal; each is stated with its reason in
§5 rather than buried in code. §5 formerly restated decision 3 so its constant lived somewhere findable;
that entry is now struck through, because decision 4 leaves no constant to find.

## 3. Everything below was measured, not assumed

Voice mode's feasibility rests on four facts about this Mac and this app. All four were checked before
the design was written, because each one could have killed a different part of it.

| Question | Answer | How |
|---|---|---|
| Can we cancel our own voice out of the mic? | **Yes** | `AVAudioEngine().inputNode.setVoiceProcessingEnabled(true)` returns without throwing and then reports `true`. This is Apple's AEC — without it, barge-in is impossible with speakers |
| Is speech recognition free and offline? | **English yes, Vietnamese no** | `SFSpeechRecognizer(en-US).supportsOnDeviceRecognition` is `true`; `vi-VN` returns a recognizer but reports `false`, logging *"No Assistant asset for language vi-VN"* |
| Are there usable voices? | **25 English, all `default` quality** | `AVSpeechSynthesisVoice.speechVoices()`. Named human voices: `Samantha`, `Daniel`, `Karen`, `Moira`, `Rishi`, `Tessa`. No `enhanced` or `premium` installed. **Vietnamese: exactly one — `Linh`** |
| Does the app already own the audio stack? | **Yes, partly** | `ChiptuneEngine` (`Managers/SoundManager.swift`) owns an `AVAudioEngine` with `sfxMixer` and `musicMixer` for the 8-bit sounds |

**Two consequences the founder must see in the UI, not discover.**

In **English** nothing leaves the Mac: recognition is on-device, synthesis is local, no network, no
credits for the audio. In **Vietnamese** her speech goes to Apple's servers, because no on-device asset
exists. That is a sentence in the composer, not a footnote.

And **the voices are `default` quality.** macOS can download `enhanced` and `premium` voices in System
Settings, and out of the box this will sound like classic Mac TTS — serviceable, not ChatGPT-grade. A
one-time nudge pointing at System Settings is honest; pretending otherwise is not.

⚠️ **The nudge was never built** — confirmed 22 Aug by checking the deleted overlay as well as the
composer, so it is a gap this spec opened and never closed rather than something the surface move lost.
It is not blocking: the voices work, they just sound dated. Recorded here so the next reader does not go
looking for it in code.

## 4. The loop

```
                 ┌──────────────────────────────────────────┐
                 │                                          │
   idle ──tap ⦙⦙⦙──▶ listening ─────tap ✓─────▶ thinking ────┤
     ▲                 ▲   ▲                                │
     │                 │   └── tap ✕ (discard, unspent)      │
  tap ⦙⦙⦙ (exit)       │                    reply streams    │
     │                 └──── she starts talking ────▼        │
     │                        (barge-in)        speaking ◀───┘
     └──────────────────────────────────────────────────┘
```

**Nothing leaves this loop without a tap.** ✓ sends, ✕ discards and returns to
listening with the credit unspent. Silence does nothing at all — the mic keeps
capturing until she decides, exactly as Claude's does.

**The waveform button is both the toggle and the exit**, so there is one ✕, not two.
An earlier draft of this diagram labelled the exit `tap ✕`, which was true of the
takeover overlay and became wrong when decision 5 moved voice into the composer: ✕
discards a sentence and never leaves voice mode. Retiring the second ✕ is also what
retired the captions those buttons used to need — with one ✕ on screen there is
nothing to disambiguate.

| State | What the founder sees | What is running |
|---|---|---|
| `listening` | live transcript in the composer, bar waveform tracking mic level, **✕ and ✓ beside it** | recognition task streaming partials. **No timer** — ✓ is the only thing that takes the turn |
| `thinking` | the status line says so, and the waveform stops tracking input — legibly *not* listening, so she knows the turn was taken | the ordinary `sendChat` — same path a typed message takes |
| `speaking` | status line says the pet is speaking | synthesiser working through a queue of complete sentences |

**This table described an orb until 22 Aug.** Decision 5 removed it: there is no orb,
and the composer's single status line carries what three rows of overlay used to. One
consequence, tested rather than incidental: a failure always outranks the caption, so
the line can never say "Connecting…" over a dead microphone.

**The partial transcript is shown for a reason.** Recognition gets names and jargon wrong, and a founder
who cannot see what was heard will not trust the reply. Seeing it wrong before it sends is the difference
between a bug and a retype.

## 5. The five design calls, plus the founder's threshold

**Speak sentence-by-sentence as the reply streams**, not when it finishes. A 400-word reply would
otherwise be fifteen seconds of silence followed by two minutes of monologue. `SentenceSplitter` turns
the stream into complete sentences; a half-sentence is never spoken.

**Barge-in is on.** It is what separates a conversation from a walkie-talkie, and §3 confirms the
echo canceller exists to make it possible. She speaks, the synthesiser stops mid-word, and the state
returns to `listening`.

**The room is unreachable by voice.** Convening costs `RoomOffer.credits` (~10) and a misheard sentence
must never spend it. `Convene the room` stays a deliberate click in the `＋` menu.

**Whose voice speaks:** whoever signs the reply — `CompanyStore.actingSpecialist ?? host` — reusing the
per-pet mapping from §8's parked design. This is not the feature; it is the only sensible answer to
"which of the 25 voices."

~~**1.2s of silence ends the turn**~~ — **reversed 21 Aug, see §2.** A turn is taken only when the
founder taps ✓, so there is no threshold left and `VoiceTurn` is deleted. **✓ is disabled while the
transcript is empty**, so a tap cannot send nothing, and ✕ discards without spending the credit.

**SFX duck while speaking.** `ChiptuneEngine.sfxMixer.outputVolume` drops and restores. Chiptune bleeps
over a spoken sentence is a mess, and this is a real coupling rather than a nicety.

## 6. Architecture

Four units and the surface that drives them. The split has one governing rule: **the pure parts get
real tests, and no test ever touches audio hardware.**

| Unit | Responsibility | Depends on |
|---|---|---|
| `VoiceSession` | the state machine — the four states and which transitions are legal | nothing (pure) |
| `SentenceSplitter` | streaming reply text → complete sentences fit to speak | nothing (pure) |
| `SpeechListening` (protocol) + `SpeechListener` | `SFSpeechRecognizer` + engine tap, partial results, silence timer | Speech, AVFoundation |
| `SpeakingVoice` (protocol) + `SpeechSpeaker` | `AVSpeechSynthesizer` + a queue of sentences, stop-mid-word | AVFoundation |
| `VoiceTurnFlow` | the five rules that carry the invariants — surface-agnostic, taken as explicit inputs | nothing (pure) |
| `VoiceChrome` | what the founder reads: the privacy line, the credit count, the one text slot | nothing (pure) |
| `VoiceComposer` | the in-composer surface (§2 decision 5); owns a `VoiceSession`, reads the two protocols | SwiftUI |

**Why the protocol boundary is not optional here.** On 21 Aug, `PetMenuIcon` drew a sprite through
`NSImage.lockFocus()`, which needs a window-server graphics context a headless XCTest host does not
have. It destabilised the host badly enough that **six unrelated SSE streaming tests began failing** —
the tell was a stream test reading `delta("You're ")` instead of `delta("Hello")`. AVFoundation and
Speech are the same class of hazard, worse: they want a microphone and an audio device. So the real
frameworks sit behind `SpeechListening` and `SpeakingVoice`, the suite drives fakes, and `speak()` is
never called by a test.

## 7. Risks, in the order they will bite

**~~Two owners for the audio engine.~~ RESOLVED by spike, 21 Aug — voice mode owns its own engine.**

`setVoiceProcessingEnabled(true)` **throws `-10849`** (`kAudioUnitErr_Initialized`) when the engine is
already running, and `ChiptuneEngine` starts lazily then stays running. Sharing would mean stopping the
SFX engine, reconfiguring the input unit, and restarting it every time voice mode opens — killing sound
mid-playback. Two engines were then run simultaneously (output + mic-with-VP) and both reported
`isRunning == true`, so coexistence is fine.

It also helps that `ChiptuneEngine` never touches `inputNode`: keeping the mic out of the SFX engine
means sound effects never require microphone permission, and a denial cannot break them.

**And the spike found a landmine the design would have missed.** Enabling voice processing changes the
input format from **1ch to 7ch, 48kHz, deinterleaved** — that is what a tap actually receives. Feeding
that straight to `SFSpeechAudioBufferRecognitionRequest` is not safe: `AVAudioConverter(7ch 48k → 1ch
16k)` *constructs* but reports `channelMap == [-1]`, i.e. no valid source mapping, so the naive
conversion would most likely hand the recognizer silence — which fails as "voice mode hears nothing",
with no error to chase. The reliable path is an intermediate `AVAudioMixerNode` between `inputNode` and
the tap, with the downmix format stated explicitly rather than inherited.

> ### ⛔️ SUPERSEDED, 22 Aug — the mixer *was* the "voice mode hears nothing" bug
>
> Everything from here to the `mainMixerNode` warning below is kept as a record of how this went
> wrong. **The shipped conclusion is: tap `inputNode` directly, mono, at the input bus's own sample
> rate. There is no intermediate node.** A mixer whose output bus is connected to nothing is never
> rendered, so the tap on it fired ~10×/s at the correct frame count and every buffer was zero in
> every sample. Diagnosis: `.superpowers/sdd/voice-diagnosis.md`. Fix and verification:
> `.superpowers/sdd/tap-fix-report.md`.
>
> **The `channelMap == [-1]` measurement above is true. The inference drawn from it was not, and
> that inference is what produced the mixer.** Re-measured 22 Aug, `say` playing, mic authorised:
>
> | claim | measured 22 Aug | verdict |
> |---|---|---|
> | `AVAudioConverter(7ch→1ch)` constructs but reports `channelMap == [-1]` | constructs; `channelMap == [-1]` | **true, reproducible** |
> | …and therefore hands the recognizer silence | fed live 7ch buffers → 40 callbacks, **peak 0.000000**, while the same raw buffers read peak 0.666 | **true** |
> | …**therefore the input must go through an `AVAudioMixerNode`** | `inputNode.installTap(format: 1ch @ bus rate)` → 40/40 non-zero buffers, peak 0.19–0.81, five runs | **FALSE** |
>
> `installTap` performs the multi-channel → 1ch downmix itself. It was never necessary to reach for
> `AVAudioConverter`, so its (real) limitation never implied a mixer. **Tapping `inputNode` would have
> worked from the beginning.**
>
> This is the same failure shape as the tap-format claim two paragraphs down, and the section's own
> closing lesson — "measured a *property* and inferred behaviour from it" — described what was about to
> happen again. The rule that actually holds: **a graph change is verified by non-zero sample content
> with real sound in the room, never by a format dump and never by a callback count.** The
> `1ch/16000 → 0 callbacks` finding below is likewise real, reproducible, and a red herring.
>
> One property worth keeping, because it converts this whole class of mistake from silent to loud: a
> tap format at any rate other than the input bus's own makes `engine.start()` **throw `-10875`**
> (measured at 16000 and 44100), and `openMic` already catches, stores and renders a throw.

**"Stated explicitly" is the whole load-bearing phrase, and the first implementation still missed it.**
Task 4 shipped `engine.connect(input, to: downmix, format: input.outputFormat(forBus: 0))` and then
tapped `downmix.outputFormat(forBus: 0)` — reading the format back instead of setting it. `connect(_:to:format:)`
sets the **source's** output bus and makes the destination's *input* match; it says nothing about the
mixer's **output**. Measured on this Mac, 21 Aug:

| Bus | Format |
|---|---|
| `inputNode` output, VP on | 7 ch, 48000 Hz, Float32, deinterleaved |
| mixer **input** after that `connect` | 7 ch, 48000 Hz — a no-op restatement |
| mixer **output**, inherited — *what the first implementation tapped* | **2 ch, 44100 Hz** |

So the recognizer was being handed **stereo 44.1kHz**, uncontrolled and machine-dependent. The format
argument to `installTap` does take effect — it is legal precisely because the mixer's output bus is
connected to nothing (`AVAudioNode.h`: "should only be done when attaching to an output bus which is not
connected to another node").

**But moving the bus format is not the same as audio flowing, and the first attempt at this fix proved
it the hard way.** Stating `1 ch / 16000 Hz` moves the bus to exactly that — and then **the tap never
fires again**. Measured 21 Aug with microphone authorisation confirmed (`AVCaptureDevice.authorizationStatus(for: .audio) == 3`),
two seconds per trial, voice processing on:

| Requested tap format | Resulting bus | Tap callbacks in 2s |
|---|---|---|
| inherited | 2 ch / 44100 | 19 — fires |
| **1 ch / 44100** | 1 ch / 44100 | **19 — fires** ✅ |
| **1 ch / 48000** | 1 ch / 48000 | **19 — fires** ✅ |
| 1 ch / **16000** | 1 ch / 16000 | **0 — silent** ❌ |
| 2 ch / 44100 | 2 ch / 44100 | 19 — fires |

**`AVAudioMixerNode` will downmix channels but will not resample on a tapped output bus.** Force the
channel count, inherit the sample rate:

```swift
let inherited = downmix.outputFormat(forBus: 0)
guard let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                    sampleRate: inherited.sampleRate,   // MUST inherit — 16k kills the tap
                                    channels: 1, interleaved: false) else { throw … }
```

Mono is the part the recognizer actually needs; `SFSpeechAudioBufferRecognitionRequest` accepts the
device rate. At 44100, `bufferSize: 4800` is 109ms, inside `AVAudioNode.h`'s documented `[100, 400] ms`.

**The lesson is bigger than the constant.** Two spikes in a row measured a *property* and inferred
behaviour from it: the first read `channelMap == [-1]` and predicted silence; the second read the bus
format and declared the fix good. Only counting tap callbacks distinguishes "configured" from "working".
Any future change to this graph must be verified by callback count, not by format inspection.

**Still unmeasured:** peak amplitude was 0.0000 in every trial, because nobody was speaking into the mic
in that environment. Frames flow; that the *voice* survives the 7→1 downmix needs one human saying a
sentence. That is a handoff, not a claim.

> **22 Aug: that paragraph was the bug, written down and explained away.** `peak == 0.0000 in every
> trial` was the defect itself, attributed to the room instead of to the graph. The very next trial with
> `say` playing would have caught it. **A zero peak is never "nobody was speaking" until you have made
> a noise and watched it stay zero.**

**Do not "fix" any of this by connecting the mixer to `mainMixerNode` to force a format.** That routes
the microphone to the speakers, and with voice processing on it builds a feedback loop.

> **22 Aug: right conclusion, wrong mechanism — and it no longer applies, since there is no mixer.**
> Measured: connecting the mixer onward to `mainMixerNode` fails `engine.start()` with **`-10875`**
> while voice processing is on. It never initialises, so it cannot route anything anywhere and there is
> no feedback loop to build. Dropping voice processing to make the graph render fails **`-10868`**, and
> would cost barge-in besides — voice processing is what cancels the pet's own speech out of the mic.

**Two TCC prompts on first use** — microphone and speech recognition — and the app has neither usage
string today (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` are absent from
`codepet/Info.plist`). The app is **not** sandboxed (`com.apple.security.app-sandbox` is `false`), so no
entitlement work is needed, but a denial must degrade to "voice mode unavailable, here is how to turn it
on" rather than a dead button.

**Credits.** Talking is much faster than typing, so voice mode is the feature that makes turns cheap to
spend without noticing. Ten spoken exchanges is ~2.5 credits in about two minutes. The composer carries a
running count for that reason.

**The silence threshold is a feel, not a fact.** 1.2s will be wrong for someone who pauses mid-thought
and wrong for someone who talks fast. One constant, tuned after use.

**Recognition quality on product nouns.** "Codepet", "byte", "nova", pet names, and department names are
exactly the words a general recognizer gets wrong. `SFSpeechRecognitionRequest.contextualStrings` accepts
a hint list and the roster is already enumerable — worth wiring from the start rather than discovering.

## 8. Not in this spec

**The per-reply read-aloud button.** A `▶ listen` in the existing action row (#96: copy/markdown/retry/
thumbs) that has each department's pet read its own answer, keyed to `PetCharacter.voiceGuide` — which
already describes each pet's written rhythm and maps onto voice, rate, and pitch almost mechanically:

| Pet | `voiceGuide` | Voice | Rate | Pitch |
|---|---|---|---|---|
| byte | glitchy fragments, deadpan | `Samantha` en-US | 1.00 | 1.00 |
| crash | "grizzled engineer… production down at 3AM" | `Daniel` en-GB | 1.05 | 0.85 |
| luna | "gentle, flowing… warm rhythm" | `Moira` en-IE | 0.92 | 1.05 |
| nova | "punchy… hype coach" | `Karen` en-AU | 1.12 | 1.10 |
| sage | "measured… sentences that breathe" | `Rishi` en-IN | 0.88 | 0.95 |
| glitch | "irreverent… hacker who reads philosophy" | `Tessa` en-ZA | 1.08 | 1.08 |
| null | "playful, unpredictable… sentences zigzag" | `Junior` en-US | 1.16 | 1.15 |

**This table listed six pets until 21 Aug and the roster has seven.** `null` — "The
Chaos Gremlin" — was missing, so the implementation gave it byte's exact profile:
same voice, same rate, same pitch. The test that exists to catch exactly that
(`testNoTwoPetsSoundIdentical`) could not, because it iterated the same six-name
list. The fix in the plan derives the list from `PetCharacter.starters` rather than
retyping it, so the roster cannot silently outgrow the voices again. `Junior` is the
only installed *human* voice that reads as playful — measured, 25 English voices, all
`default` quality. Not `Bahh`/`Boing`/`Jester`, which are sound effects.

Kept here because voice mode needs *a* voice and this table is the answer, and because the read-aloud
button is a cheap follow-up once `SpeechSpeaker` exists. **Deliberately not the novelty voices**
(`Zarvox`, `Bubbles`, `Trinoids`) — these pets give business advice.

**Multi-voice room playback** — four departments arguing aloud, then Chief of Staff synthesising. The
most appealing version of the idea and the largest: it needs sequencing, per-card controls, and an
interruption model. Its own spec, after this one ships.

**Vietnamese parity.** With one voice (`Linh`) and no on-device recognition, VI voice mode works but is
neither private nor cast-signed. Not fixable by us; stated rather than hidden.

## 9. Open

**Nothing blocking.** The one open question — shared or separate `AVAudioEngine` — was answered by spike
on 21 Aug: **separate**, because enabling voice processing on a running engine throws. See §7 for the
error code, the coexistence check, and the 7-channel format landmine the same spike surfaced.

~~One thing still unmeasured: whether 1.2s is the right silence threshold.~~ **Moot as of 21 Aug** —
decision 4 removed the threshold entirely. The question that replaced it is not a measurement either:
whether tapping ✓ every turn costs more than the misheard turns it prevents. That needs the founder
using it, and it is reversible in one place if the answer is yes.

---

## 10. Record — the second control, added 22 Aug

Dictation was scoped **out** of this spec on 21 Aug ("In scope? No"). The founder
brought it back in on 22 Aug after watching Claude's composer, where the mic's own
tooltip reads **"Press and hold to record ⌘D"**. Claude ships two controls, we had
built one.

**What it is.** Press and hold the mic (or press ⌘D) and speak. The composer shows the
same chrome voice mode uses — expanded box, live transcript, bar waveform, ✕ and ✓.
Release stops capturing; the transcript stays so it can be judged. **✓ puts the text
into the composer's text field as an editable draft. ✕ discards it.** Nothing sends,
and nothing is spoken back.

**Why it is nearly free.** Every piece already exists and is surface-agnostic:
`SpeechListener` and its protocol, `TurnTranscript`, `RenewalBudget`,
`VoicePermission`, and the two `Info.plist` usage strings. Record adds no audio work,
no new permission, and no new failure mode — it is a second consumer of a stack six
review rounds have already hardened.

**Three properties that distinguish it from voice mode, all of them requirements:**

| | Record | Voice mode |
|---|---|---|
| Entry | press-and-hold mic, or ⌘D | click the waveform |
| On ✓ | text into the field, **editable** | sent immediately |
| Credits | **none — it never sends** | 0.25 per turn |
| Speaks back | no | yes |
| `SpeakingVoice` | never touched | drives the reply |

**Record costs no credits, and that is worth stating rather than leaving implied.** It
does not call `sendChat`, so the credit line that voice mode carries has nothing to
count. A founder dictating a long brief and editing it before sending should pay for
one turn, not for the dictation.

**The two controls must never run at once.** They share one `SpeechListener` and one
recognition request, so entering either while the other is live has to be refused —
the same shape as `VoicePermission.canEnterVoiceMode(_:isBusy:)`, extended so each
control's rule is testable rather than inline.

**The privacy line applies unchanged** (§3). Recognition is recognition: English is
on-device, Vietnamese goes to Apple's servers. Record must say so in the same compact
line, because the founder dictating a confidential brief has exactly the same
question as the founder speaking one.

**Not in scope for record:** the room stays unreachable (§5) — record cannot send at
all, so it cannot convene anything; and no pet speaks, so `PetVoice` is untouched.

**Evidence for the ✕, from the founder's own recording.** She spoke, it transcribed as
*"Hey, mama"*, and Claude replied *"I think something might be getting lost in the
transcription there."* That turn was sent and charged before she could read it. Under
decision 4 it would have cost one tap of ✕ and nothing else.

