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
| 🎤 mic | **Dictation** — speak, it becomes editable text, you still read the reply | No |
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
| 2 | The surface is a **takeover overlay**, not a panel that keeps the transcript visible |
| 3 | A turn ends after **1.2s of silence** — automatic, not hold-to-talk |

Five further calls were made in the design and are open to reversal; each is stated with its reason in
§5 rather than buried in code. §5 restates decision 3 alongside them, attributed, because the constant
it names has to live somewhere a reader will find it.

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
exists. That is a sentence in the overlay, not a footnote.

And **the voices are `default` quality.** macOS can download `enhanced` and `premium` voices in System
Settings, and out of the box this will sound like classic Mac TTS — serviceable, not ChatGPT-grade. A
one-time nudge pointing at System Settings is honest; pretending otherwise is not.

## 4. The loop

```
                 ┌──────────────────────────────────────────┐
                 │                                          │
   idle ──tap──▶ listening ──silence 1.2s──▶ thinking ──────┤
     ▲               ▲                                      │
     │               │                          reply streams│
   tap ✕             └────── she starts talking ─────▼       │
     │                        (barge-in)         speaking ◀──┘
     └────────────────────────────────────────────────┘
```

| State | What the founder sees | What is running |
|---|---|---|
| `listening` | orb pulsing with mic level, live partial transcript in small type beneath | recognition task streaming partials; silence timer armed |
| `thinking` | orb stops tracking level and breathes on a slow fixed cycle — legibly *not* listening, so she knows the turn was taken | the ordinary `sendChat` — same path a typed message takes |
| `speaking` | orb pulsing with output level | synthesiser working through a queue of complete sentences |

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

**1.2s of silence ends the turn** (founder's call). It lives as one named constant, because it is the
value most likely to feel wrong and need changing after real use.

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
| `VoiceModeOverlay` | the takeover surface; owns a `VoiceSession`, reads the two protocols | SwiftUI |

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

**Do not "fix" any of this by connecting the mixer to `mainMixerNode` to force a format.** That routes
the microphone to the speakers, and with voice processing on it builds a feedback loop.

**Two TCC prompts on first use** — microphone and speech recognition — and the app has neither usage
string today (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` are absent from
`codepet/Info.plist`). The app is **not** sandboxed (`com.apple.security.app-sandbox` is `false`), so no
entitlement work is needed, but a denial must degrade to "voice mode unavailable, here is how to turn it
on" rather than a dead button.

**Credits.** Talking is much faster than typing, so voice mode is the feature that makes turns cheap to
spend without noticing. Ten spoken exchanges is ~2.5 credits in about two minutes. The overlay carries a
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

One thing still unmeasured, deliberately: **whether 1.2s is the right silence threshold.** That is a
feel, not a fact, and no spike answers it — it needs the founder talking to the built thing. It lives as
one named constant for exactly that reason.
