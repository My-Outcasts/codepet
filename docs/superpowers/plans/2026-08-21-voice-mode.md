# Voice Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A hands-free spoken conversation in the chat — tap the waveform, talk, Codepet talks back, and the whole exchange lands in the ordinary transcript.

**Architecture:** Two pure types carry the logic (`VoiceSession` for state, `SentenceSplitter` for what to speak next), and the two AVFoundation/Speech types sit behind protocols so no test touches audio hardware. Voice mode owns its **own** `AVAudioEngine` — the spike proved it cannot share `ChiptuneEngine`'s. Nothing about `sendChat` changes: a voice turn is an ordinary message.

**Tech Stack:** Swift 5, SwiftUI, macOS 26.2, XCTest. `Speech` and `AVFoundation` — both already linked (`SoundManager.swift` imports AVFoundation). **No new dependencies, no `functions/` change, no API cost.**

**Spec:** `docs/superpowers/specs/2026-08-21-voice-mode-design.md`. Read §3 (measured facts) and §7 (the spike's two findings) before Task 4 — that task is where both bite.

## Global Constraints

- **Swift only.** No file under `functions/` may be touched. Voice mode is entirely local macOS frameworks.
- **No test may call `speak()`, `start()` on an audio engine, or construct `SFSpeechRecognizer`.** The real types sit behind `SpeechListening` and `SpeakingVoice`; suites drive fakes. This is not style: on 21 Aug `PetMenuIcon` drew through `NSImage.lockFocus()`, which needs a window-server graphics context a headless XCTest host lacks, and it took six unrelated SSE streaming tests down with it. Audio wants a *microphone* — same hazard, worse.
- **Voice mode owns its own `AVAudioEngine`.** Measured: `setVoiceProcessingEnabled(true)` throws `-10849` (`kAudioUnitErr_Initialized`) on a running engine, and `ChiptuneEngine` starts lazily then stays running.
- **Enabling voice processing changes the input format to 7ch / 48kHz / deinterleaved.** Never tap `inputNode` directly for recognition — route through an `AVAudioMixerNode` with an explicit format. `AVAudioConverter(7ch→1ch)` constructs but reports `channelMap == [-1]`, so the obvious code compiles and feeds the recognizer silence.
- **New `.swift` files need no project-file edit** — `PBXFileSystemSynchronizedRootGroup`, membership follows the folder.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Test classes touching main-actor state are annotated `@MainActor`, as every existing suite is.
- **Chrome is bilingual, content is EN.** Every founder-visible string takes `_ lang: AppLanguage` and switches on `lang == .vi`. Follow `ApprovalTier.label(_:)`.
- **The room is unreachable by voice** (spec §5). `RoomOffer` is never called from any voice path.
- **Quit `codepet.app` before running tests** — a running instance holds the Firestore lock and kills the test host. Check `pgrep -x codepet`.
- **Count tests with `xcresulttool`**, never by grepping the log.

**Per-suite test command:**

```bash
cd /Users/monatruong/Developer/codepet-two-mode
xcodebuild test -project CodePet.xcodeproj -scheme codepet \
  -destination 'platform=macOS' \
  -only-testing:codepetTests/SUITE_NAME \
  CODE_SIGNING_ALLOWED=NO \
  -derivedDataPath build/dd-ci \
  -resultBundlePath build/task.xcresult 2>&1 | tail -25
xcrun xcresulttool get test-results summary --path build/task.xcresult | head -20
```

`-derivedDataPath build/dd-ci` is load-bearing: without it the unsigned test build overwrites the signed `codepet.app` in shared DerivedData and Firebase sign-in silently breaks for the next human launch.

**Full suite, required before the PR:** `./scripts/ci-test.sh` — currently **1581/1581 green**, so any red is yours.

**Signed build, for anything a human runs:**

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | grep -E "error:|BUILD"
open /Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app --args -CODEPET_TWO_MODE YES
```

## File structure

| File | Responsibility |
|---|---|
| `codepet/Models/VoiceSession.swift` | the four states and legal transitions. Pure |
| `codepet/Models/SentenceSplitter.swift` | growing reply text → complete sentences not yet spoken. Pure |
| `codepet/Models/VoiceTurn.swift` | silence-threshold arithmetic. Pure |
| `codepet/Models/PetVoice.swift` | pet id → voice name / rate / pitch. Pure |
| `codepet/Models/VoiceReplyDriver.swift` | reply text + isStreaming → sentences to speak. Pure |
| `codepet/Services/SpeakingVoice.swift` | protocol + `SpeechSpeaker` (`AVSpeechSynthesizer`) |
| `codepet/Services/SpeechListening.swift` | protocol + `SpeechListener` (`SFSpeechRecognizer` + own engine) |
| `codepet/Models/VoicePermission.swift` | mic + recognition authorisation state, and its copy |
| `codepet/Views/Copilot/VoiceModeOverlay.swift` | the takeover surface |
| `codepet/Info.plist` | two usage strings |
| `codepet/Views/Copilot/ChatComposer.swift` | the waveform button |

---

### Task 1: `VoiceSession` — the state machine

**Files:**
- Create: `codepet/Models/VoiceSession.swift`
- Create: `codepetTests/VoiceSessionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum VoiceState: Equatable { case idle, listening, thinking, speaking }`
  - `struct VoiceSession` with `var state: VoiceState` (private setter), `init()`
  - `mutating func apply(_ event: VoiceEvent) -> Bool` — returns whether the transition was legal
  - `enum VoiceEvent { case open, heardSilence, replyBegan, replyFinished, founderInterrupted, close }`
  - `var isActive: Bool` — `state != .idle`

- [ ] **Step 1: Write the failing test**

Create `codepetTests/VoiceSessionTests.swift`:

```swift
import XCTest
@testable import codepet

/// The loop from spec §4, as a value type.
///
/// It is a separate type rather than `@State` in the overlay for one reason: the
/// illegal transitions are the interesting ones, and a view cannot be asked what
/// it refuses to do. `apply` returns a Bool so a caller that fires an event at the
/// wrong moment — a late recognition callback, a synthesiser finishing after the
/// founder closed the overlay — is a no-op rather than a state corruption.
final class VoiceSessionTests: XCTestCase {

    func testStartsIdle() {
        XCTAssertEqual(VoiceSession().state, .idle)
        XCTAssertFalse(VoiceSession().isActive)
    }

    func testTheHappyLoop() {
        var s = VoiceSession()
        XCTAssertTrue(s.apply(.open));            XCTAssertEqual(s.state, .listening)
        XCTAssertTrue(s.apply(.heardSilence));    XCTAssertEqual(s.state, .thinking)
        XCTAssertTrue(s.apply(.replyBegan));      XCTAssertEqual(s.state, .speaking)
        XCTAssertTrue(s.apply(.replyFinished));   XCTAssertEqual(s.state, .listening)
    }

    /// Barge-in: the founder talks over the reply. Only legal while speaking —
    /// firing it while listening would restart a turn that is already running.
    func testBargeInFromSpeakingReturnsToListening() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.heardSilence); _ = s.apply(.replyBegan)
        XCTAssertTrue(s.apply(.founderInterrupted))
        XCTAssertEqual(s.state, .listening)
    }

    func testBargeInIsIgnoredWhenNotSpeaking() {
        var s = VoiceSession()
        _ = s.apply(.open)
        XCTAssertFalse(s.apply(.founderInterrupted), "interrupting nothing must be a no-op")
        XCTAssertEqual(s.state, .listening)
    }

    /// **The late-callback case, and why `apply` returns Bool.** A recognition or
    /// synthesis callback can arrive after the founder has closed the overlay. It
    /// must not reopen it.
    func testEventsAfterCloseAreRefused() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.heardSilence)
        XCTAssertTrue(s.apply(.close))
        XCTAssertEqual(s.state, .idle)
        for late in [VoiceEvent.replyBegan, .replyFinished, .heardSilence, .founderInterrupted] {
            XCTAssertFalse(s.apply(late), "\(late) reopened a closed session")
            XCTAssertEqual(s.state, .idle)
        }
    }

    func testSilenceIsIgnoredUnlessListening() {
        var s = VoiceSession()
        _ = s.apply(.open); _ = s.apply(.heardSilence)   // now thinking
        XCTAssertFalse(s.apply(.heardSilence), "a second silence must not re-send the turn")
        XCTAssertEqual(s.state, .thinking)
    }

    func testCloseIsLegalFromEveryState() {
        for setup: [VoiceEvent] in [[], [.open], [.open, .heardSilence],
                                    [.open, .heardSilence, .replyBegan]] {
            var s = VoiceSession()
            for e in setup { _ = s.apply(e) }
            _ = s.apply(.close)
            XCTAssertEqual(s.state, .idle, "close failed after \(setup)")
        }
    }

    func testOpeningAnOpenSessionIsRefused() {
        var s = VoiceSession()
        _ = s.apply(.open)
        XCTAssertFalse(s.apply(.open))
        XCTAssertEqual(s.state, .listening)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoiceSessionTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v1.xcresult 2>&1 | tail -20
```

Expected: test target does not build — `cannot find 'VoiceSession' in scope`. Per `scripts/ci-test.sh`, a non-building test target is normally a regression; here it is the expected red.

- [ ] **Step 3: Write minimal implementation**

Create `codepet/Models/VoiceSession.swift`:

```swift
// codepet/Models/VoiceSession.swift
import Foundation

/// Where a voice-mode conversation is — spec §4.
enum VoiceState: Equatable {
    /// No overlay. The mic is not running.
    case idle
    /// Mic live, recognition streaming partials, silence timer armed.
    case listening
    /// The turn was sent; `sendChat` is working. Nothing is captured.
    case thinking
    /// A reply is being read aloud, sentence by sentence.
    case speaking
}

/// What can happen to a voice session.
enum VoiceEvent: Equatable {
    /// The founder tapped the waveform.
    case open
    /// The silence threshold elapsed — the founder's turn is over.
    case heardSilence
    /// The first speakable sentence of the reply is ready.
    case replyBegan
    /// The synthesiser drained its queue and the reply is complete.
    case replyFinished
    /// The founder started talking over the reply.
    case founderInterrupted
    /// The founder dismissed the overlay.
    case close
}

/// The loop, as a value type.
///
/// **Why this is not just `@State` in the overlay.** The interesting behaviour is
/// what it REFUSES. Audio callbacks are asynchronous and arrive late: a recognition
/// result after the founder closed the overlay, a synthesiser `didFinish` for a
/// reply that was already interrupted. `apply` returns whether the transition was
/// legal so a late callback is a no-op instead of a reopened overlay with a dead
/// microphone — and a test can assert the refusal, which it cannot do to a view.
struct VoiceSession {
    private(set) var state: VoiceState = .idle

    init() {}

    var isActive: Bool { state != .idle }

    /// Apply `event`, returning `false` when it was not legal from the current
    /// state. A `false` return is expected and normal, not an error to log.
    @discardableResult
    mutating func apply(_ event: VoiceEvent) -> Bool {
        // Close always wins, from anywhere, including idle→idle being a no-op that
        // still counts as handled: the founder pressing ✕ twice is not a bug.
        if event == .close {
            let changed = state != .idle
            state = .idle
            return changed
        }
        switch (state, event) {
        case (.idle, .open):
            state = .listening;  return true
        case (.listening, .heardSilence):
            state = .thinking;   return true
        case (.thinking, .replyBegan):
            state = .speaking;   return true
        case (.speaking, .replyFinished),
             (.speaking, .founderInterrupted):
            // Both return to listening: a finished reply and an interrupted one
            // leave the founder holding the conversation either way.
            state = .listening;  return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoiceSessionTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v1.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v1.xcresult | head -20
```

Expected: 8 tests, 8 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/VoiceSession.swift codepetTests/VoiceSessionTests.swift
git commit -F - <<'MSG'
feat(voice): VoiceSession — the loop, and what it refuses

A value type rather than @State in the overlay, because the interesting
behaviour is the refusals and a view cannot be asked what it declines to do.

Audio callbacks arrive late by nature: a recognition result after the founder
closed the overlay, a synthesiser didFinish for a reply already interrupted.
`apply` returns whether the transition was legal, so a late callback is a no-op
instead of a reopened overlay holding a dead microphone.

Barge-in is legal only from .speaking — firing it while listening would restart
a turn already in flight. A second .heardSilence while thinking is refused for
the same reason: it would re-send and re-bill the turn.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 2: `SentenceSplitter` — what to speak next

The reply arrives as a *growing string*: `CompanyStore` assigns `chatMessages[i].text = streamedText` on every delta. So the overlay watches one value get longer and must decide, each time, which complete sentences are newly speakable.

**Files:**
- Create: `codepet/Models/SentenceSplitter.swift`
- Create: `codepetTests/SentenceSplitterTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct SentenceSplitter` with `init()`, `mutating func take(from full: String) -> [String]`, `mutating func flush(from full: String) -> [String]`, `mutating func reset()`
  - `static func speakable(_ raw: String) -> String` — strips markdown for speech

- [ ] **Step 1: Write the failing test**

Create `codepetTests/SentenceSplitterTests.swift`:

```swift
import XCTest
@testable import codepet

/// Turning a growing string into speakable sentences.
///
/// The input is not a stream of chunks — it is the SAME string, longer each time
/// (`chatMessages[i].text = streamedText`). So `take` is called repeatedly with a
/// superset of what it saw before and must return only what is newly complete.
/// Everything here is that contract.
final class SentenceSplitterTests: XCTestCase {

    func testHoldsBackAnIncompleteSentence() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Your pricing page"), [],
                       "a half sentence must never be spoken — it sounds like a fault")
    }

    func testEmitsOnceTerminated() {
        var s = SentenceSplitter()
        _ = s.take(from: "Your pricing page buries the price")
        XCTAssertEqual(s.take(from: "Your pricing page buries the price. And the CTA"),
                       ["Your pricing page buries the price."])
    }

    /// The core contract: repeated calls with a growing string never repeat output.
    func testNeverRepeatsASentence() {
        var s = SentenceSplitter()
        let full = "One. Two. Three."
        var out: [String] = []
        for end in stride(from: 1, through: full.count, by: 1) {
            out += s.take(from: String(full.prefix(end)))
        }
        XCTAssertEqual(out, ["One.", "Two.", "Three."])
    }

    func testHandlesQuestionsExclamationsAndNewlines() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "Why? Because!\nDone. "),
                       ["Why?", "Because!", "Done."])
    }

    // MARK: - Markdown, because replies are markdown

    func testStripsEmphasisAndBackticks() {
        XCTAssertEqual(SentenceSplitter.speakable("**bold** and `code` and _soft_"),
                       "bold and code and soft")
    }

    func testStripsHeadingHashesButKeepsTheWords() {
        XCTAssertEqual(SentenceSplitter.speakable("## Next steps"), "Next steps")
    }

    func testReadsLinksAsTheWordLink() {
        // Spelling out "h t t p s colon slash slash" is unbearable.
        let out = SentenceSplitter.speakable("See https://codepet.app/pricing for more")
        XCTAssertFalse(out.contains("https"))
        XCTAssertTrue(out.contains("link"))
    }

    /// **Fenced code is skipped entirely.** Reading `func viewDidLoad() {` aloud is
    /// noise, and a reply that is only code has nothing to say.
    func testSkipsFencedCodeBlocks() {
        let md = "Here is the fix.\n```swift\nlet x = 1\nprint(x)\n```\nThat should do it."
        let out = SentenceSplitter.speakable(md)
        XCTAssertFalse(out.contains("let x"))
        XCTAssertFalse(out.contains("print"))
        XCTAssertTrue(out.contains("Here is the fix."))
        XCTAssertTrue(out.contains("That should do it."))
    }

    func testAnUnclosedFenceDoesNotSwallowTheRestForever() {
        // Mid-stream, a fence opens before it closes. Everything after it is held
        // rather than spoken — but the text BEFORE it still speaks.
        let out = SentenceSplitter.speakable("Try this.\n```swift\nlet x = 1")
        XCTAssertTrue(out.contains("Try this."))
        XCTAssertFalse(out.contains("let x"))
    }

    func testResetClearsProgress() {
        var s = SentenceSplitter()
        _ = s.take(from: "One. Two.")
        s.reset()
        XCTAssertEqual(s.take(from: "One. Two."), ["One.", "Two."],
                       "reset must let the next reply start from nothing")
    }

    /// A reply that is only a code block yields nothing speakable, which the
    /// overlay reads as "no reply to speak" rather than speaking an empty string.
    func testACodeOnlyReplyIsSilent() {
        var s = SentenceSplitter()
        XCTAssertEqual(s.take(from: "```swift\nlet x = 1\n```\n"), [])
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/SentenceSplitterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v2.xcresult 2>&1 | tail -20
```

Expected: `cannot find 'SentenceSplitter' in scope`.

- [ ] **Step 3: Write it**

Create `codepet/Models/SentenceSplitter.swift`:

```swift
// codepet/Models/SentenceSplitter.swift
import Foundation

/// Decides what is newly speakable as a reply streams in — spec §5.
///
/// **The input is not chunks.** `CompanyStore` assigns
/// `chatMessages[i].text = streamedText` on every delta, so this is called
/// repeatedly with the SAME string, longer each time. It tracks how much it has
/// already emitted and returns only what has newly become a complete sentence.
///
/// Speaking half a sentence and then pausing sounds like a fault, which is why an
/// unterminated tail is always held back — even though that means the last sentence
/// of a reply only speaks once the stream ends with punctuation.
struct SentenceSplitter {
    /// Characters already emitted, counted against the SPEAKABLE rendering rather
    /// than the raw markdown, because the two lengths differ.
    private var consumed: Int = 0

    init() {}

    mutating func reset() { consumed = 0 }

    /// Complete sentences in `full` that have not been returned before.
    mutating func take(from full: String) -> [String] {
        let text = Self.speakable(full)
        guard text.count > consumed else { return [] }
        let fresh = String(text.dropFirst(consumed))

        var out: [String] = []
        var current = ""
        var emittedCount = 0
        var idx = fresh.startIndex
        while idx < fresh.endIndex {
            let ch = fresh[idx]
            current.append(ch)
            if Self.terminators.contains(ch) {
                // A terminator ends a sentence only when what follows is whitespace
                // or the end of what we have — otherwise "3.14" splits.
                let next = fresh.index(after: idx)
                let atEnd = next == fresh.endIndex
                let followedBySpace = !atEnd && fresh[next].isWhitespace
                if atEnd || followedBySpace {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.count > 1 { out.append(trimmed) }
                    emittedCount += current.count
                    current = ""
                }
            }
            idx = fresh.index(after: idx)
        }
        consumed += emittedCount
        return out
    }

    private static let terminators: Set<Character> = [".", "!", "?", "\n"]

    /// Markdown rendered for the ear.
    ///
    /// Fenced code is removed rather than read: `func viewDidLoad() {` aloud is
    /// noise. An UNCLOSED fence — which every streaming reply has, briefly — drops
    /// everything from the fence onward, so prose before it still speaks and the
    /// code never does.
    static func speakable(_ raw: String) -> String {
        var s = raw

        // Fenced blocks first, so their contents never reach the other rules.
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ",
                                   options: .regularExpression)
        if let openFence = s.range(of: "```") { s = String(s[s.startIndex..<openFence.lowerBound]) }

        // Links become the word, not the URL.
        s = s.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "https?://[^\\s]+", with: "link",
                                   options: .regularExpression)

        // Emphasis, inline code, headings, list bullets.
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "\\*\\*|__", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])[*_](?![A-Za-z0-9])", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "\\*(\\S[^*]*?)\\*", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "_(\\S[^_]*?)_", with: "$1",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s*", with: "",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "",
                                   options: .regularExpression)

        return s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
    }
}
```

**If a regex misbehaves, fix the regex, not the test.** The emphasis rules are the
fiddly ones — run the suite and iterate on the pattern until the assertions pass.
Do not relax an assertion to match a broken strip: `**bold**` reaching the
synthesiser as "asterisk asterisk bold" is the whole thing this prevents.

- [ ] **Step 4: Run it**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/SentenceSplitterTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v2.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v2.xcresult | head -20
```

Expected: 11 tests, 11 passed.

- [ ] **Step 5: Commit**

```bash
git add codepet/Models/SentenceSplitter.swift codepetTests/SentenceSplitterTests.swift
git commit -F - <<'MSG'
feat(voice): SentenceSplitter — speak as the reply streams, never half a sentence

The input is not a stream of chunks. CompanyStore assigns
`chatMessages[i].text = streamedText` on every delta, so this is called
repeatedly with the same string, longer each time. It tracks what it already
emitted and returns only what newly became complete.

An unterminated tail is always held back. Speaking half a sentence and then
pausing sounds like a fault — worse than the small delay of waiting for the
punctuation.

A terminator only ends a sentence when whitespace or the end follows it,
otherwise "3.14" and "e.g" split mid-number and mid-abbreviation.

Fenced code is removed rather than read: `func viewDidLoad() {` aloud is noise.
Every streaming reply briefly has an UNCLOSED fence, so an open fence drops
everything after it — prose before it still speaks, the code never does, and a
code-only reply is correctly silent rather than speaking an empty string.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 3: `VoiceTurn` and `PetVoice` — the two constants

Small, pure, and paired because neither is worth its own review gate.

**Files:**
- Create: `codepet/Models/VoiceTurn.swift`
- Create: `codepet/Models/PetVoice.swift`
- Create: `codepetTests/VoiceTurnTests.swift`
- Create: `codepetTests/PetVoiceTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `VoiceTurn.silenceThreshold: TimeInterval` (= 1.2)
  - `VoiceTurn.shouldEndTurn(lastSpeechAt: Date?, now: Date, threshold: TimeInterval) -> Bool`
  - `struct VoiceProfile: Equatable { let preferredVoices: [String]; let rate: Float; let pitch: Float }`
  - `PetVoice.profile(for petId: String?) -> VoiceProfile`

- [ ] **Step 1: Write both failing suites**

`codepetTests/VoiceTurnTests.swift`:

```swift
import XCTest
@testable import codepet

/// When is the founder's turn over? Pure arithmetic, extracted from the listener
/// so the one number the founder will complain about is testable without a mic.
final class VoiceTurnTests: XCTestCase {

    func testTheThresholdIsTheFoundersNumber() {
        XCTAssertEqual(VoiceTurn.silenceThreshold, 1.2, accuracy: 0.001)
    }

    func testSilenceShorterThanTheThresholdDoesNotEndTheTurn() {
        let now = Date()
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(-0.9),
                                               now: now,
                                               threshold: VoiceTurn.silenceThreshold))
    }

    func testSilencePastTheThresholdEndsIt() {
        let now = Date()
        XCTAssertTrue(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(-1.3),
                                              now: now,
                                              threshold: VoiceTurn.silenceThreshold))
    }

    /// **Nothing heard yet must never end a turn.** Otherwise opening the overlay
    /// and pausing to think sends an empty message and spends a credit.
    func testNoSpeechYetNeverEndsTheTurn() {
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: nil, now: Date(),
                                               threshold: VoiceTurn.silenceThreshold))
    }

    func testAClockThatWentBackwardsDoesNotEndTheTurn() {
        let now = Date()
        XCTAssertFalse(VoiceTurn.shouldEndTurn(lastSpeechAt: now.addingTimeInterval(5),
                                               now: now, threshold: VoiceTurn.silenceThreshold))
    }
}
```

`codepetTests/PetVoiceTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import codepet

/// Which of the 25 installed voices each pet gets.
///
/// No test asks the synthesiser to speak. These assert the MAPPING — that it is
/// total, that no two pets are indistinguishable, and that a missing voice falls
/// back rather than crashing.
final class PetVoiceTests: XCTestCase {

    /// **All SEVEN starters, from `PetCharacter.starters`.** An earlier draft of this
    /// plan listed six and dropped `null` — "The Chaos Gremlin", a real shipped
    /// character with its own `voiceGuide` and its own match score. It fell into
    /// `default` and got byte's exact profile: same voice, same rate, same pitch. The
    /// collision was invisible because `null` was missing from this very list, so
    /// `testNoTwoPetsSoundIdentical` never saw it. Derive from the roster, do not
    /// retype it.
    private let pets = PetCharacter.starters

    func testEveryPetHasAProfile() {
        for p in pets {
            let prof = PetVoice.profile(for: p)
            XCTAssertFalse(prof.preferredVoices.isEmpty, "\(p) has no voice candidates")
            XCTAssertGreaterThan(prof.rate, 0)
            XCTAssertGreaterThan(prof.pitch, 0)
        }
    }

    /// **No two pets may be indistinguishable.** If two share a voice, a rate AND a
    /// pitch, the founder hears one person — which defeats naming the speaker.
    func testNoTwoPetsSoundIdentical() {
        var seen = Set<String>()
        for p in pets {
            let prof = PetVoice.profile(for: p)
            let key = "\(prof.preferredVoices.first ?? "")|\(prof.rate)|\(prof.pitch)"
            XCTAssertTrue(seen.insert(key).inserted, "\(p) is indistinguishable from another pet")
        }
    }

    /// An unknown pet — or the host, which is nil — gets the neutral default rather
    /// than nothing. The overlay must never be voiceless.
    func testUnknownAndNilFallBackToTheHostProfile() {
        XCTAssertEqual(PetVoice.profile(for: nil), PetVoice.profile(for: "byte"))
        XCTAssertEqual(PetVoice.profile(for: "no-such-pet"), PetVoice.profile(for: "byte"))
    }

    /// The candidates are ordered, and the last one must be a voice macOS always
    /// has. `Samantha` ships with every install; the accented voices can be absent.
    func testEveryCandidateListEndsInAVoiceThatAlwaysExists() {
        for p in pets {
            XCTAssertEqual(PetVoice.profile(for: p).preferredVoices.last, "Samantha",
                           "\(p) has no guaranteed fallback voice")
        }
    }

    /// Rate must stay inside what AVSpeechUtterance accepts, or the setter clamps
    /// silently and the pets converge on one speed.
    func testRatesAreInsideTheSynthesisersRange() {
        for p in pets {
            let r = PetVoice.profile(for: p).rate
            XCTAssertGreaterThanOrEqual(r, AVSpeechUtteranceMinimumSpeechRate)
            XCTAssertLessThanOrEqual(r, AVSpeechUtteranceMaximumSpeechRate)
        }
    }

    /// **Pitch needs the same guard as rate, and for the same reason.**
    /// `pitchMultiplier` accepts 0.5…2.0 and clamps silently outside it, so a future
    /// edit to 3.0 would ship sounding wrong with a green suite. `testEveryPetHasAProfile`
    /// only asserts `pitch > 0`, which 3.0 passes.
    func testPitchesAreInsideTheSynthesisersRange() {
        for p in pets {
            let pitch = PetVoice.profile(for: p).pitch
            XCTAssertGreaterThanOrEqual(pitch, 0.5, "\(p) pitch clamps low")
            XCTAssertLessThanOrEqual(pitch, 2.0, "\(p) pitch clamps high")
        }
    }

    /// `pick` walks the preference list IN ORDER and takes the first available.
    /// Working in names is what makes this testable at all — see the doc comment on
    /// `pick`. Deleting the ordering (returning `available.first`, say) turns the
    /// second assertion red.
    func testPickTakesTheFirstAvailableInPreferenceOrder() {
        let crash = PetVoice.profile(for: "crash")   // ["Daniel", "Samantha"]
        XCTAssertEqual(PetVoice.pick(crash, from: ["Daniel", "Samantha"]), "Daniel")
        XCTAssertEqual(PetVoice.pick(crash, from: ["Samantha", "Daniel"]), "Daniel",
                       "order comes from the PROFILE, not from what the system lists first")
        XCTAssertEqual(PetVoice.pick(crash, from: ["Samantha"]), "Samantha",
                       "falls through to the guaranteed voice")
    }

    /// Nothing installed matches: return nil so the caller can let the synthesiser
    /// choose. Refusing to speak would be worse than speaking in the wrong voice.
    func testPickReturnsNilWhenNothingMatches() {
        XCTAssertNil(PetVoice.pick(PetVoice.profile(for: "crash"), from: []))
        XCTAssertNil(PetVoice.pick(PetVoice.profile(for: "crash"), from: ["Zarvox"]))
    }
}
```

- [ ] **Step 2: Run both and watch them fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoiceTurnTests -only-testing:codepetTests/PetVoiceTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v3.xcresult 2>&1 | tail -20
```

Expected: `cannot find 'VoiceTurn' in scope`, `cannot find 'PetVoice' in scope`.

- [ ] **Step 3: Write `VoiceTurn`**

```swift
// codepet/Models/VoiceTurn.swift
import Foundation

/// When the founder's turn is over.
///
/// Extracted from `SpeechListener` so the one number she is most likely to
/// complain about is adjustable and testable without a microphone.
enum VoiceTurn {
    /// Founder's call, 21 Aug — matches ChatGPT's feel. Spec §2, decision 3.
    ///
    /// Deliberately a single named constant: 1.2s is wrong for someone who pauses
    /// mid-thought and wrong for someone who talks fast, and no spike settles it.
    /// It needs the founder talking to the built thing.
    static let silenceThreshold: TimeInterval = 1.2

    /// Whether `now` is far enough past the last speech to end the turn.
    ///
    /// `nil` means nothing has been heard yet and NEVER ends a turn: otherwise
    /// opening the overlay and pausing to think would send an empty message and
    /// spend a credit on it. A `lastSpeechAt` in the future (clock adjustment,
    /// injected test date) is treated the same way.
    static func shouldEndTurn(lastSpeechAt: Date?, now: Date,
                              threshold: TimeInterval = silenceThreshold) -> Bool {
        guard let last = lastSpeechAt else { return false }
        let gap = now.timeIntervalSince(last)
        guard gap >= 0 else { return false }
        return gap >= threshold
    }
}
```

- [ ] **Step 4: Write `PetVoice`**

```swift
// codepet/Models/PetVoice.swift
import Foundation
// NO `import AVFoundation`. This file is pure — see the File-structure table.
// Rate and pitch are plain Floats on AVSpeechUtterance's scales; naming a voice
// is a String. Task 4 owns the one line that touches the framework.

/// A voice, a speed, and a pitch.
struct VoiceProfile: Equatable {
    /// In preference order. Resolution walks it and takes the first installed
    /// voice, so the list must end in one macOS always has.
    let preferredVoices: [String]
    let rate: Float
    let pitch: Float
}

/// Which of the installed voices each pet speaks with — spec §8.
///
/// **Keyed to `PetCharacter.voiceGuide`, which already exists.** That field
/// describes how each pet WRITES — "grizzled engineer who's seen production go
/// down at 3AM", "gentle, flowing… warm rhythm" — and is already sent to Claude to
/// shape its prose. Choosing the spoken voice from the same description keeps the
/// two from drifting into different characters.
///
/// **Not the novelty voices.** macOS also installs `Zarvox`, `Bubbles`, `Trinoids`.
/// Tempting for a pixel-art cast, and wrong: these pets give business advice.
///
/// Measured 21 Aug: 25 English voices installed, every one `default` quality. The
/// six named below are the human-sounding ones, across five accents and both
/// genders, so the cast is distinguishable by WHO is talking and not just by speed.
enum PetVoice {

    static func profile(for petId: String?) -> VoiceProfile {
        switch petId {
        case "crash":
            // Blunt, low, slightly fast. en-GB male reads as authoritative.
            return VoiceProfile(preferredVoices: ["Daniel", "Samantha"], rate: 0.52, pitch: 0.85)
        case "luna":
            // Gentle and flowing — the Irish lilt does most of the work.
            return VoiceProfile(preferredVoices: ["Moira", "Samantha"], rate: 0.46, pitch: 1.05)
        case "nova":
            // Punchy hype coach: fastest and highest.
            return VoiceProfile(preferredVoices: ["Karen", "Samantha"], rate: 0.56, pitch: 1.10)
        case "sage":
            // Measured, deliberate, "sentences that breathe" — the slowest.
            return VoiceProfile(preferredVoices: ["Rishi", "Samantha"], rate: 0.44, pitch: 0.95)
        case "glitch":
            // Clipped and irreverent.
            return VoiceProfile(preferredVoices: ["Tessa", "Samantha"], rate: 0.54, pitch: 1.08)
        case "null":
            // The Chaos Gremlin: "sentences zigzag — starts one thought, finishes
            // another." Fastest and highest, because the zigzag is carried by pace.
            // Junior is a young en-US voice — the only installed HUMAN voice that
            // reads as playful. Not Bahh/Boing/Jester, which are sound effects.
            return VoiceProfile(preferredVoices: ["Junior", "Kathy", "Samantha"], rate: 0.58, pitch: 1.15)
        default:
            // byte, the host — heard most often, so the most listenable. Also the
            // fallback for an unknown pet: the overlay must never be voiceless.
            return VoiceProfile(preferredVoices: ["Samantha"], rate: 0.50, pitch: 1.00)
        }
    }

    /// The first name in the profile's preference list that appears in `available`,
    /// or nil when none do — in which case the caller lets the synthesiser pick the
    /// system default rather than refusing to speak.
    ///
    /// **Takes names, not `AVSpeechSynthesisVoice`.** `AVSpeechSynthesisVoice` has
    /// no public initialiser that sets an arbitrary `name`, so a parameter of that
    /// type can only ever be fed the voices really installed on the machine running
    /// the test — which makes the preference-order walk untestable and pins this
    /// file to AVFoundation for no gain. Task 4 maps the returned name to a real
    /// voice; that one line is the only place the framework is needed.
    static func pick(_ profile: VoiceProfile, from available: [String]) -> String? {
        profile.preferredVoices.first { available.contains($0) }
    }
}
```

**Note on `rate`:** `AVSpeechUtteranceDefaultSpeechRate` is 0.5 on a 0…1 scale, not
1.0 — which is why these are around 0.5 rather than around 1.0. The spec's table
expresses them as multipliers for readability; these are the API's units.

- [ ] **Step 5: Run both, then commit**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoiceTurnTests -only-testing:codepetTests/PetVoiceTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v3.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v3.xcresult | head -20
```

Expected: 10 tests, 10 passed.

```bash
git add codepet/Models/VoiceTurn.swift codepet/Models/PetVoice.swift \
        codepetTests/VoiceTurnTests.swift codepetTests/PetVoiceTests.swift
git commit -F - <<'MSG'
feat(voice): the silence threshold and the per-pet voices, both as pure types

VoiceTurn exists so the one number the founder is most likely to complain about
is testable without a microphone. 1.2s is her call and no spike settles it — it
is wrong for someone who pauses mid-thought and wrong for someone who talks
fast, so it lives as one named constant.

Its important case is nil: nothing heard yet NEVER ends a turn. Otherwise
opening the overlay and pausing to think sends an empty message and spends a
credit on silence.

PetVoice is keyed to PetCharacter.voiceGuide, which already describes how each
pet writes and is already sent to Claude. Choosing the spoken voice from the same
description stops the written and spoken characters drifting apart.

Measured 21 Aug: 25 English voices, all `default` quality. The six chosen span
five accents and both genders, so the cast differs by WHO is speaking rather
than only by speed — a test asserts no two pets share a voice/rate/pitch triple.
Every candidate list ends in Samantha, which every macOS install has.

Deliberately not Zarvox, Bubbles or Trinoids. Tempting for a pixel-art cast, and
wrong: these pets give business advice.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 4: `SpeechListening` and `SpeakingVoice` — the audio, behind protocols

**This is the task where the spike's findings bite.** Read spec §7 first.

**Files:**
- Create: `codepet/Services/SpeakingVoice.swift`
- Create: `codepet/Services/SpeechListening.swift`
- Create: `codepetTests/SpeechFakesTests.swift`

**Interfaces:**
- Consumes: `VoiceProfile`, `PetVoice`, `VoiceTurn`, `SentenceSplitter`.
- Produces:
  - `protocol SpeakingVoice: AnyObject { var onFinishedAll: (() -> Void)? { get set }; func enqueue(_ sentence: String, profile: VoiceProfile); func stopImmediately(); var isSpeaking: Bool { get } }`
  - `final class SpeechSpeaker: NSObject, SpeakingVoice`
  - `protocol SpeechListening: AnyObject { var onPartial: ((String) -> Void)? { get set }; var onLevel: ((Float) -> Void)? { get set }; func start() throws; func stop(); var isRunning: Bool { get } }`
  - `final class SpeechListener: SpeechListening`
  - `enum VoiceAudioError: Error { case recognizerUnavailable, engineFailed(String) }`

- [ ] **Step 1: Write the failing test — fakes only**

Create `codepetTests/SpeechFakesTests.swift`:

```swift
import XCTest
@testable import codepet

/// **No test in this file touches audio hardware.** The protocols exist so the
/// suite can drive fakes, and this suite is the proof that the protocols are
/// sufficient — if a fake cannot express the behaviour the overlay needs, the
/// boundary is in the wrong place.
///
/// The rule is not style. On 21 Aug, `PetMenuIcon` drew a sprite through
/// `NSImage.lockFocus()`, which needs a window-server graphics context a headless
/// XCTest host lacks, and six unrelated SSE streaming tests began failing — a
/// stream test read `delta("You're ")` instead of `delta("Hello")`. AVFoundation
/// and Speech are the same hazard and worse: they want a microphone.
@MainActor
final class SpeechFakesTests: XCTestCase {

    final class FakeVoice: SpeakingVoice {
        var onFinishedAll: (() -> Void)?
        var spoken: [String] = []
        var stopped = 0
        var isSpeaking = false
        func enqueue(_ sentence: String, profile: VoiceProfile) {
            spoken.append(sentence); isSpeaking = true
        }
        func stopImmediately() { stopped += 1; isSpeaking = false }
        func finishAll() { isSpeaking = false; onFinishedAll?() }
    }

    final class FakeListener: SpeechListening {
        var onPartial: ((String) -> Void)?
        var onLevel: ((Float) -> Void)?
        var isRunning = false
        var startCount = 0
        func start() throws { startCount += 1; isRunning = true }
        func stop() { isRunning = false }
        func emit(_ partial: String) { onPartial?(partial) }
    }

    /// The protocol has to be able to express "speak these, then tell me you're done".
    func testTheVoiceProtocolCarriesQueueAndCompletion() {
        let v = FakeVoice()
        var finished = false
        v.onFinishedAll = { finished = true }
        v.enqueue("One.", profile: PetVoice.profile(for: "nova"))
        v.enqueue("Two.", profile: PetVoice.profile(for: "nova"))
        XCTAssertEqual(v.spoken, ["One.", "Two."])
        XCTAssertTrue(v.isSpeaking)
        v.finishAll()
        XCTAssertTrue(finished)
        XCTAssertFalse(v.isSpeaking)
    }

    /// Barge-in composed end to end from the pieces, with no audio: the founder
    /// speaks while the fake voice is mid-queue, the session moves, the voice stops.
    func testBargeInStopsTheVoiceAndReturnsToListening() {
        var session = VoiceSession()
        let voice = FakeVoice()
        let listener = FakeListener()
        _ = session.apply(.open); _ = session.apply(.heardSilence)
        voice.enqueue("A long reply that is still going.",
                      profile: PetVoice.profile(for: "byte"))
        _ = session.apply(.replyBegan)
        XCTAssertEqual(session.state, .speaking)

        listener.onPartial = { _ in
            if session.state == .speaking {
                voice.stopImmediately()
                _ = session.apply(.founderInterrupted)
            }
        }
        listener.emit("actually wait")

        XCTAssertEqual(voice.stopped, 1, "the voice kept talking over her")
        XCTAssertEqual(session.state, .listening)
    }

    /// The splitter and the queue together: a streaming reply speaks each sentence
    /// exactly once, and never a fragment.
    func testStreamingRepliesSpeakEachSentenceOnce() {
        var splitter = SentenceSplitter()
        let voice = FakeVoice()
        let profile = PetVoice.profile(for: "sage")
        let full = "First point. Second point. Third."
        for end in 1...full.count {
            for s in splitter.take(from: String(full.prefix(end))) {
                voice.enqueue(s, profile: profile)
            }
        }
        XCTAssertEqual(voice.spoken, ["First point.", "Second point.", "Third."])
    }

    /// A listener that fails to start must be visible, not silent — the overlay
    /// shows an error instead of a live-looking orb that hears nothing.
    func testAListenerThatCannotStartReportsIt() {
        final class DeadListener: SpeechListening {
            var onPartial: ((String) -> Void)?
            var onLevel: ((Float) -> Void)?
            var isRunning = false
            func start() throws { throw VoiceAudioError.recognizerUnavailable }
            func stop() {}
        }
        let l = DeadListener()
        XCTAssertThrowsError(try l.start())
        XCTAssertFalse(l.isRunning)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/SpeechFakesTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v4.xcresult 2>&1 | tail -20
```

Expected: `cannot find type 'SpeakingVoice' in scope`.

- [ ] **Step 3: Write `SpeakingVoice.swift`**

```swift
// codepet/Services/SpeakingVoice.swift
import AVFoundation
import Foundation

/// Reads sentences aloud, one after another, and says when it has run dry.
///
/// A protocol so the suite can drive a fake — see `SpeechFakesTests` for why that
/// is a hard rule here rather than a preference.
protocol SpeakingVoice: AnyObject {
    /// Called when the queue drains. The overlay turns this into `.replyFinished`.
    var onFinishedAll: (() -> Void)? { get set }
    var isSpeaking: Bool { get }
    /// Add one complete sentence. Never a fragment — see `SentenceSplitter`.
    func enqueue(_ sentence: String, profile: VoiceProfile)
    /// Stop mid-word. This is barge-in, so it cannot wait for the sentence to end.
    func stopImmediately()
}

/// `AVSpeechSynthesizer`, wrapped.
///
/// **Ducks the chiptune SFX while speaking** (spec §5). `ChiptuneEngine` is a
/// separate `AVAudioEngine` playing 8-bit sounds, and bleeps over a spoken sentence
/// is a mess. Volume is restored when the queue drains — including when it drains
/// because of barge-in, which is why the restore lives in one place.
final class SpeechSpeaker: NSObject, SpeakingVoice, AVSpeechSynthesizerDelegate {
    var onFinishedAll: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var queued = 0
    private var duckedFrom: Float?

    override init() {
        super.init()
        synth.delegate = self
    }

    var isSpeaking: Bool { synth.isSpeaking }

    func enqueue(_ sentence: String, profile: VoiceProfile) {
        let u = AVSpeechUtterance(string: sentence)
        // PetVoice.pick works in names so it stays testable; this is the ONE line
        // that turns a name into a voice. nil is fine — system default.
        let installed = AVSpeechSynthesisVoice.speechVoices()
        u.voice = PetVoice.pick(profile, from: installed.map(\.name))
            .flatMap { name in installed.first { $0.name == name } }
        u.rate = profile.rate
        u.pitchMultiplier = profile.pitch
        duckSFX()
        queued += 1
        synth.speak(u)
    }

    func stopImmediately() {
        queued = 0
        synth.stopSpeaking(at: .immediate)
        unduckSFX()
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queued = max(0, queued - 1)
        if queued == 0 {
            unduckSFX()
            onFinishedAll?()
        }
    }

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queued = max(0, queued - 1)
        if queued == 0 { unduckSFX() }
    }

    // MARK: - SFX ducking

    private func duckSFX() {
        guard duckedFrom == nil else { return }   // already ducked; don't stack
        let mixer = ChiptuneEngine.shared.sfxVolume
        duckedFrom = mixer
        ChiptuneEngine.shared.sfxVolume = 0
    }

    private func unduckSFX() {
        if let was = duckedFrom { ChiptuneEngine.shared.sfxVolume = was }
        duckedFrom = nil
    }
}
```

**`ChiptuneEngine` has no `sfxVolume` yet — add it.** In
`codepet/Managers/SoundManager.swift`, `sfxMixer` is `private`. Add the smallest
possible accessor rather than exposing the mixer:

```swift
    /// Read/write the SFX mixer's volume, so voice mode can duck bleeps while a
    /// sentence is being spoken. Deliberately not exposing `sfxMixer` itself: the
    /// only thing another subsystem needs is this one number.
    var sfxVolume: Float {
        get { sfxMixer.outputVolume }
        set { sfxMixer.outputVolume = newValue }
    }
```

- [ ] **Step 4: Write `SpeechListening.swift` — and mind the 7 channels**

```swift
// codepet/Services/SpeechListening.swift
import AVFoundation
import Foundation
import Speech

enum VoiceAudioError: Error {
    case recognizerUnavailable
    case engineFailed(String)
}

/// Streams what the founder is saying.
///
/// A protocol so the suite can drive a fake — the concrete type wants a microphone,
/// which no test may touch.
protocol SpeechListening: AnyObject {
    /// The running transcript so far. Called repeatedly with a growing string.
    var onPartial: ((String) -> Void)? { get set }
    /// Input level 0…1, for the orb.
    var onLevel: ((Float) -> Void)? { get set }
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

/// `SFSpeechRecognizer` over our own `AVAudioEngine`.
///
/// **Its own engine, measured.** `setVoiceProcessingEnabled(true)` throws `-10849`
/// (`kAudioUnitErr_Initialized`) on a running engine, and `ChiptuneEngine` starts
/// lazily then stays running — so sharing would mean stopping the SFX engine and
/// restarting it every time voice mode opens. Two engines were verified to run
/// simultaneously. Keeping the mic out of `ChiptuneEngine` also means sound effects
/// never require microphone permission.
///
/// **Voice processing changes the input format to 7ch / 48kHz / deinterleaved**, and
/// that is what a tap on `inputNode` receives. Feeding it straight to the recognizer
/// is the trap: `AVAudioConverter(7ch→1ch)` *constructs* — so the obvious code
/// compiles and looks right — but reports `channelMap == [-1]`, no valid source
/// mapping, and hands the recognizer silence. The failure mode is "voice mode hears
/// nothing" with no error to chase. So the input goes through an
/// `AVAudioMixerNode`, which downmixes, and the tap is on the mixer.
final class SpeechListener: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let downmix = AVAudioMixerNode()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    /// `contextualStrings` is why the locale is held: product nouns are exactly the
    /// words a general recognizer mishears.
    private let hints: [String]

    init(locale: Locale, hints: [String]) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
        self.hints = hints
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceAudioError.recognizerUnavailable
        }
        guard !isRunning else { return }

        // BEFORE start(), never after — see the -10849 note above.
        do { try engine.inputNode.setVoiceProcessingEnabled(true) }
        catch { throw VoiceAudioError.engineFailed("voice processing: \(error.localizedDescription)") }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // On-device in English; vi-VN has no asset and falls back to the network.
        // Requesting it is still correct: it is honoured where possible.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        req.contextualStrings = hints
        request = req

        engine.attach(downmix)
        // Connect at the INPUT's own format; the mixer does the downmix.
        engine.connect(engine.inputNode, to: downmix,
                       format: engine.inputNode.outputFormat(forBus: 0))
        let tapFormat = downmix.outputFormat(forBus: 0)
        downmix.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buf, _ in
            self?.request?.append(buf)
            self?.reportLevel(buf)
        }

        do { try engine.start() }
        catch { throw VoiceAudioError.engineFailed(error.localizedDescription) }

        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let result else { return }
            self?.onPartial?(result.bestTranscription.formattedString)
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        downmix.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
    }

    /// RMS, for the orb. Cheap on purpose — it runs per buffer on the audio thread.
    private func reportLevel(_ buf: AVAudioPCMBuffer) {
        guard let data = buf.floatChannelData?[0] else { return }
        let n = Int(buf.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = (sum / Float(n)).squareRoot()
        let level = min(1, rms * 12)   // empirical gain; speech RMS is small
        DispatchQueue.main.async { [weak self] in self?.onLevel?(level) }
    }
}
```

- [ ] **Step 5: Run the fakes suite, then commit**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/SpeechFakesTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v4.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v4.xcresult | head -20
```

Expected: 4 tests, 4 passed. **Then run the whole suite** — this task adds a
property to `ChiptuneEngine`, which the sound tests touch:

```bash
pkill -x codepet 2>/dev/null; ./scripts/ci-test.sh 2>&1 | tail -12
```

Expected: 1581 + the new tests, 0 failed.

```bash
git add codepet/Services/SpeakingVoice.swift codepet/Services/SpeechListening.swift \
        codepet/Managers/SoundManager.swift codepetTests/SpeechFakesTests.swift
git commit -F - <<'MSG'
feat(voice): the audio, behind protocols, with the spike's two traps handled

SpeechListener owns its OWN AVAudioEngine, and that is measured rather than
preferred: setVoiceProcessingEnabled(true) throws -10849
(kAudioUnitErr_Initialized) on a running engine, and ChiptuneEngine starts
lazily then stays running. Sharing would mean stopping the SFX engine and
restarting it every time voice mode opens. Two engines were verified running
simultaneously. Keeping the mic out of ChiptuneEngine also means sound effects
never require microphone permission and a denial cannot break them.

The second trap is the one that would have shipped. Voice processing changes the
input format to 7ch 48kHz deinterleaved, and that is what a tap on inputNode
receives. AVAudioConverter(7ch -> 1ch 16k) CONSTRUCTS, so the obvious code
compiles and reviews clean, but reports channelMap == [-1] — no valid source
mapping — and would hand the recognizer silence. "Voice mode hears nothing" with
no error to chase. The input now goes through an AVAudioMixerNode, which
downmixes, and the tap is on the mixer.

Both concrete types sit behind protocols and no test constructs either. That is
not style: today PetMenuIcon drew through NSImage.lockFocus(), needing a graphics
context a headless host lacks, and took six unrelated SSE streaming tests down
with it. Audio wants a microphone — same hazard, worse.

SpeechSpeaker ducks the chiptune SFX while speaking, restoring in one place so
barge-in cannot leave the volume down. ChiptuneEngine gains a single sfxVolume
accessor rather than exposing its mixer.

contextualStrings carries the roster and pet names, because "Codepet", "nova"
and "glitch" are exactly what a general recognizer mishears.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 5: Permission — two prompts, and a button that says why

**Files:**
- Create: `codepet/Models/VoicePermission.swift`
- Modify: `codepet/Info.plist`
- Create: `codepetTests/VoicePermissionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum VoiceAvailability: Equatable { case ready, needsPermission, denied(String), unsupported(String) }`
  - `VoicePermission.availability(mic:recognition:hasRecognizer:) -> VoiceAvailability` — pure, takes raw statuses
  - `VoicePermission.help(_ availability:, _ lang:) -> String?`
  - `VoicePermission.offersButton(_ availability: VoiceAvailability) -> Bool` — whether the waveform is tappable at all

- [ ] **Step 1: Write the failing test**

```swift
import AVFoundation
import Speech
import XCTest
@testable import codepet

/// Voice mode needs TWO grants — microphone and speech recognition — and either can
/// be refused independently. The mapping is pure so every combination is testable
/// without touching TCC, which a test cannot drive anyway.
final class VoicePermissionTests: XCTestCase {

    func testBothGrantedIsReady() {
        XCTAssertEqual(VoicePermission.availability(mic: .authorized,
                                                    recognition: .authorized,
                                                    hasRecognizer: true), .ready)
    }

    func testUndeterminedAsksRatherThanRefusing() {
        XCTAssertEqual(VoicePermission.availability(mic: .notDetermined,
                                                    recognition: .notDetermined,
                                                    hasRecognizer: true), .needsPermission)
    }

    /// **Either refusal is a refusal**, and the copy must name which one — "voice
    /// mode unavailable" with no reason is the thing that generates support mail.
    func testEitherDenialIsDeniedAndNamesWhich() {
        guard case .denied(let m1) = VoicePermission.availability(
            mic: .denied, recognition: .authorized, hasRecognizer: true) else {
            return XCTFail("mic denial not reported")
        }
        XCTAssertTrue(m1.lowercased().contains("microphone"), "got: \(m1)")

        guard case .denied(let m2) = VoicePermission.availability(
            mic: .authorized, recognition: .denied, hasRecognizer: true) else {
            return XCTFail("recognition denial not reported")
        }
        XCTAssertTrue(m2.lowercased().contains("speech"), "got: \(m2)")
    }

    /// No recognizer for the locale is a different thing from a refusal: nothing
    /// the founder can grant will fix it, so the button must not offer to ask.
    func testAMissingRecognizerIsUnsupportedNotDenied() {
        guard case .unsupported = VoicePermission.availability(
            mic: .authorized, recognition: .authorized, hasRecognizer: false) else {
            return XCTFail("a missing recognizer must be .unsupported")
        }
    }

    /// **The button's own rule, separate from the mapping.** `.needsPermission`
    /// must still OFFER the button — tapping it is what triggers the TCC prompt, so
    /// hiding it makes the permission unreachable and voice mode permanently dead.
    /// A refusal or an unsupported locale must not offer it: a dead click tells the
    /// founder nothing, where a disabled control with a reason tells her what to do.
    func testTheButtonIsOfferedWhenReadyOrUnasked() {
        XCTAssertTrue(VoicePermission.offersButton(.ready))
        XCTAssertTrue(VoicePermission.offersButton(.needsPermission))
        XCTAssertFalse(VoicePermission.offersButton(.denied("Microphone access is off.")))
        XCTAssertFalse(VoicePermission.offersButton(.unsupported("No recogniser.")))
    }

    func testHelpTextIsBilingualAndAbsentWhenReady() {
        XCTAssertNil(VoicePermission.help(.ready, .en))
        let en = VoicePermission.help(.denied("Microphone access is off."), .en)
        let vi = VoicePermission.help(.denied("Microphone access is off."), .vi)
        XCTAssertNotNil(en); XCTAssertNotNil(vi)
        XCTAssertNotEqual(en, vi, "help text is chrome and must be translated")
    }
}
```

- [ ] **Step 2: Run, fail, then write it**

```swift
// codepet/Models/VoicePermission.swift
import AVFoundation
import Foundation
import Speech

/// Whether voice mode can run right now, and why not.
enum VoiceAvailability: Equatable {
    case ready
    /// Not asked yet — the button should ask rather than look broken.
    case needsPermission
    /// Refused. The string names WHICH grant is missing.
    case denied(String)
    /// Nothing the founder can grant will help — no recognizer for this locale.
    case unsupported(String)
}

/// Maps the two TCC statuses onto one answer.
///
/// Pure, taking raw statuses, because a test cannot drive TCC and every
/// combination matters: either grant can be refused on its own, and a missing
/// recognizer is a third thing that looks like a refusal but is not.
enum VoicePermission {

    static func availability(mic: AVAuthorizationStatus,
                             recognition: SFSpeechRecognizerAuthorizationStatus,
                             hasRecognizer: Bool) -> VoiceAvailability {
        guard hasRecognizer else {
            return .unsupported("No speech recogniser for this language.")
        }
        if mic == .denied || mic == .restricted {
            return .denied("Microphone access is off.")
        }
        if recognition == .denied || recognition == .restricted {
            return .denied("Speech recognition is off.")
        }
        if mic == .notDetermined || recognition == .notDetermined {
            return .needsPermission
        }
        return (mic == .authorized && recognition == .authorized)
            ? .ready
            : .denied("Microphone access is off.")
    }

    /// What to put under a disabled button. `nil` when there is nothing to say.
    ///
    /// Every branch names the fix. "Voice mode unavailable" with no reason is the
    /// message that generates support mail.
    static func help(_ availability: VoiceAvailability, _ lang: AppLanguage) -> String? {
        switch availability {
        case .ready:
            return nil
        case .needsPermission:
            return lang == .vi
                ? "Codepet sẽ xin quyền micro và nhận dạng giọng nói."
                : "Codepet will ask for microphone and speech recognition access."
        case .denied(let which):
            return lang == .vi
                ? "\(which) Mở System Settings › Privacy & Security để bật."
                : "\(which) Turn it on in System Settings › Privacy & Security."
        case .unsupported(let why):
            return lang == .vi ? why : why
        }
    }

    /// Whether the waveform button is tappable.
    ///
    /// `.needsPermission` counts as YES on purpose: tapping is what raises the TCC
    /// prompt, so a button hidden until permission is granted makes the permission
    /// unreachable and voice mode permanently dead. A refusal or a missing
    /// recogniser counts as NO, with `help` supplying the reason — a disabled
    /// control that explains itself beats a dead click that does not.
    static func offersButton(_ availability: VoiceAvailability) -> Bool {
        switch availability {
        case .ready, .needsPermission: return true
        case .denied, .unsupported:    return false
        }
    }

    /// Live statuses, for the view. Not called by tests.
    static func current(locale: Locale) -> VoiceAvailability {
        availability(mic: AVCaptureDevice.authorizationStatus(for: .audio),
                     recognition: SFSpeechRecognizer.authorizationStatus(),
                     hasRecognizer: SFSpeechRecognizer(locale: locale) != nil)
    }
}
```

- [ ] **Step 3: Add the two Info.plist strings**

`codepet/Info.plist` has neither today. Add both — macOS **crashes the app** on
first mic access if `NSMicrophoneUsageDescription` is absent, so this is not
cosmetic:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Codepet uses your microphone for voice mode, so you can talk to your company instead of typing.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Codepet turns your speech into text for voice mode. In English this happens entirely on your Mac.</string>
```

The second string's last sentence is deliberate and true: English recognition is
on-device, Vietnamese is not (spec §3). Do not copy that claim onto the mic string,
which covers both languages.

- [ ] **Step 4: Run and commit**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoicePermissionTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v5.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v5.xcresult | head -20
```

Expected: 5 tests, 5 passed.

```bash
git add codepet/Models/VoicePermission.swift codepet/Info.plist codepetTests/VoicePermissionTests.swift
git commit -F - <<'MSG'
feat(voice): two grants, and a button that says which one is missing

Voice mode needs microphone AND speech recognition, and either can be refused
alone. The mapping is pure, taking raw statuses, because a test cannot drive TCC
and every combination matters — including a third case that looks like a refusal
and is not: no recogniser for the locale is something no grant will fix, so the
button must not offer to ask.

Every branch names the fix. "Voice mode unavailable" with no reason is the
message that generates support mail.

Both Info.plist usage strings were absent, and NSMicrophoneUsageDescription is
not cosmetic — macOS terminates the app on first mic access without it.

The speech string says English recognition happens on the Mac, because it does
and Vietnamese does not. That claim is deliberately NOT on the microphone
string, which covers both languages.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
MSG
```

---

### Task 6: `VoiceModeOverlay` — the takeover

**Files:**
- Create: `codepet/Models/VoiceReplyDriver.swift`
- Create: `codepet/Views/Copilot/VoiceModeOverlay.swift`
- Create: `codepetTests/VoiceReplyDriverTests.swift`
- Create: `codepetTests/VoiceOverlayLayoutTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: `VoiceModeOverlay(isPresented: Binding<Bool>, listener: SpeechListening, voice: SpeakingVoice)`
  and `struct VoiceReplyDriver` with `init()`, `mutating func sentencesToSpeak(replyText: String, isStreaming: Bool) -> [String]`, `mutating func reset()`.

**Why the driver is its own file and its own suite.** The overlay is measured with
`ImageRenderer`, which answers *how big is it* and nothing else. Which sentences get
spoken, and when, is logic — it belongs in a plain unit suite where it can be
asserted directly. Putting it in `VoiceOverlayLayoutTests` would bury a correctness
test in a file whose every other assertion is a pixel measurement, and putting the
logic inline in a `.onChange` closure would make it untestable altogether, which is
what the first draft of this task did.

```swift
// codepet/Models/VoiceReplyDriver.swift
import Foundation

/// Turns "the reply text as it currently stands, and whether it is still arriving"
/// into the sentences to hand the synthesiser. One pure step, so the flush rule
/// below is testable rather than buried in a view closure.
struct VoiceReplyDriver {
    private var splitter = SentenceSplitter()

    mutating func sentencesToSpeak(replyText: String, isStreaming: Bool) -> [String] {
        isStreaming ? splitter.take(from: replyText) : splitter.flush(from: replyText)
    }

    mutating func reset() { splitter.reset() }
}
```

- [ ] **Step 1: Write the layout measurement**

Screen capture is denied in this environment (`screencapture` fails with *"could
not create image from display"*), so the *look* is a handoff to the founder — but
layout is measurable offscreen with `ImageRenderer`, which is how the composer row
was verified. Follow `MockFlowCaptionBarLayoutTests`.

```swift
#if DEBUG
import SwiftUI
import XCTest
@testable import codepet

/// Measures the overlay offscreen. The founder confirms how it LOOKS; these
/// assertions cover what a screenshot cannot: that it fills its host and that the
/// transcript line does not resize the surface as words arrive.
@MainActor
final class VoiceOverlayLayoutTests: XCTestCase {

    private func size(_ v: some View, w: CGFloat, h: CGFloat) -> CGSize {
        ImageRenderer(content: v.frame(width: w, height: h)).nsImage?.size ?? .zero
    }

    func testItFillsTheWindow() {
        let s = size(VoiceModeOverlay.preview(state: .listening, partial: ""), w: 900, h: 700)
        XCTAssertEqual(s.width, 900, accuracy: 2)
        XCTAssertEqual(s.height, 700, accuracy: 2)
    }

    /// **The partial transcript must not resize the surface.** It grows word by word
    /// as she talks; a surface that reflows on every word is unusable.
    func testAGrowingTranscriptDoesNotChangeTheSize() {
        let a = size(VoiceModeOverlay.preview(state: .listening, partial: "why"),
                     w: 900, h: 700)
        let b = size(VoiceModeOverlay.preview(
            state: .listening,
            partial: "why is onboarding losing people at step three and what should I do"),
                     w: 900, h: 700)
        XCTAssertEqual(a, b, "the overlay reflowed as she spoke")
    }

    func testEveryStateRenders() {
        for st in [VoiceState.listening, .thinking, .speaking] {
            let s = size(VoiceModeOverlay.preview(state: st, partial: "test"), w: 900, h: 700)
            XCTAssertGreaterThan(s.height, 100, "\(st) did not lay out")
        }
    }
}
#endif
```

- [ ] **Step 2: Build the overlay**

Key requirements, all from the spec:

- `CompanionOrb(size: 148, glow: true, isWorking: state == .thinking, companionId: speakingPet)` as the focal point. Verified signature — the `companionId:` override exists and takes a per-message specialist, so while `sage` is answering the orb is tinted `sage`'s hues rather than the account's. Pass `nil` while listening: the founder is talking, nobody is answering yet.
- Orb scale tracks `onLevel` while `.listening` and `.speaking`; on `.thinking` it breathes on a **fixed** slow cycle so it is legibly *not* listening (spec §4).
- The partial transcript beneath, in `CodepetTheme.inter(CodepetType.body)`, **fixed height for two lines** — that is what the layout test pins.
- One `✕` to close, and the running credit line.
- **The privacy line, when `lang == .vi`:** "Giọng nói của bạn được gửi tới Apple để nhận dạng." In English, the on-device line. Spec §3 requires this be visible, not a footnote.
- `.background(.ultraThinMaterial)` over the pane, honouring `accessibilityReduceTransparency` as the rest of the app does.
- A `static func preview(state:partial:)` for the tests, constructing the view with fakes.

Wiring, in the overlay's own state:

```swift
// listener.onPartial: remember the text, stamp the time, and — while speaking —
// treat any speech as barge-in.
listener.onPartial = { text in
    lastSpeechAt = Date()
    partial = text
    if session.state == .speaking {
        voice.stopImmediately()
        session.apply(.founderInterrupted)
    }
}
```

The silence check runs on a `Timer` at 4Hz asking `VoiceTurn.shouldEndTurn`, and on
a true it sends `partial` through `companyStore.sendChat` and applies
`.heardSilence`. Speaking is driven by observing the last message's text with
`.onChange`, feeding `SentenceSplitter.take(from:)` and enqueuing what comes back.

**And `flush(from:)` when the stream ends** — on `companyStore.isStreaming` going
false. `take` deliberately refuses to speak a sentence whose terminator is the last
character currently available, because mid-stream it cannot tell a pause from an
ending: `"The price is $3."` is a complete sentence and also the first half of
`"$3.14 today."`. That refusal means the final sentence of every reply is held back
until something tells the splitter the reply is over, which is what `flush` is. Omit
the flush call and every reply loses its last sentence.

**That omission must be made visible, because the type fails quiet.** Confirmed
while fixing Task 2: `take` cannot emit an unconfirmed sentence, so the splitter
fails *safe* against speaking half a thought — but a missing `flush` drops the final
sentence with **no exception and no log**. Nothing goes red; the suite stays green
and the app just stops finishing its sentences. `flush` is also not safe to call
speculatively: flush early, receive more text, and the continuation is silently
dropped. So `isStreaming → false` has to be one-way and exactly-once per reply.

Do not put that logic inline in a `.onChange` closure, where no test can reach it.
It goes in `VoiceReplyDriver` (defined in this task's **Files** block above), and
the overlay calls it. Write its suite as a whole file:

```swift
// codepetTests/VoiceReplyDriverTests.swift
import XCTest
@testable import codepet

/// The driver is one line of logic guarding a defect that is INVISIBLE to a suite
/// and audible to a human: drop the flush and every reply loses its last sentence,
/// silently. That asymmetry is the reason this file exists.
@MainActor
final class VoiceReplyDriverTests: XCTestCase {

    func testTheLastSentenceIsSpokenOnlyOnceStreamingStops() {
        var driver = VoiceReplyDriver()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: true),
                       ["One."], "mid-stream, 'Two.' may still be the head of 'Two.5 million'")
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       ["Two."], "the flush is the ONLY thing that releases the last sentence")
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       [], "flushing twice must not repeat it")
    }

    /// A second voice turn must not inherit the first one's progress. Without the
    /// reset, `emitted` still counts the previous reply's sentences and the new
    /// reply's opening sentences are skipped — the founder asks again and hears the
    /// answer start halfway through.
    func testResetLetsTheNextReplyStartFromItsFirstSentence() {
        var driver = VoiceReplyDriver()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "One. Two.", isStreaming: false),
                       ["One.", "Two."])
        driver.reset()
        XCTAssertEqual(driver.sentencesToSpeak(replyText: "Fresh. Reply.", isStreaming: false),
                       ["Fresh.", "Reply."], "reset must clear the sentence count")
    }
}
```

Replace the `flush` call with `take` and the second assertion of the first test goes
red; delete the `reset` body and the second test goes red. Those are the guards
CLAUDE.md asks for, and they are the difference between a defect the suite catches
and one only a human listening can hear.

**Verify both by deliberately breaking them** — swap `flush` for `take`, run, see
red, restore; then empty `reset`, run, see red, restore. Record both RED outputs in
the report. This plan has already shipped one guard whose test could not fail
(`PetVoice`'s six-name pet list, which omitted the same pet the code omitted), so
the check is not a formality here.

- [ ] **Step 3: Run, then commit**

```bash
xcodebuild test -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -only-testing:codepetTests/VoiceOverlayLayoutTests \
  -only-testing:codepetTests/VoiceReplyDriverTests \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build/dd-ci -resultBundlePath build/v6.xcresult 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path build/v6.xcresult | head -20
```

Expected: 5 tests, 5 passed — 3 layout, 2 driver. A layout failure is a real defect;
read the measured number in the message before touching a threshold. A driver
failure is a spoken-output defect, and the assertion messages say what breaks.

---

### Task 7: The waveform button, the full suite, and the PR

**Files:**
- Modify: `codepet/Views/Copilot/ChatComposer.swift` — the button
- Modify: `codepet/Views/Copilot/CopilotChatView.swift` — present the overlay
- Modify: `codepet/Models/AppLanguage.swift` — `speechLocale`

**Interfaces:**
- Consumes: `VoicePermission.offersButton(_:)` and `.help(_:_:)` (Task 5), `VoiceModeOverlay` (Task 6).
- Produces: `ChatComposer.onVoiceMode: (() -> Void)?` — nil by default, so `DeveloperWorkPane` and every existing call site render exactly as before.

- [ ] **Step 1: No new unit suite — and that is deliberate**

This task is wiring: a button that calls a closure, and an overlay presented from a
`@State` flag. The button's *rule* — when it is offered at all — was extracted into
`VoicePermission.offersButton(_:)` and tested in Task 5, precisely so this task does
not need a suite that re-asserts Task 5's mapping under a different name. A test that
passes whether or not this task's code exists is not protecting anything.

Verification here is Step 4's full suite plus the founder handoff in Step 5. If you
find yourself wanting a unit test, the thing worth testing is a rule that should live
in a pure type — extract it rather than testing the view.

- [ ] **Step 2: Add the button**

In `ChatComposer`, beside `plusMenu` in **both** `dockBody` and `twoModeBody`:

```swift
    /// Voice mode — spec §1. `waveform` rather than `mic`: the mic glyph means
    /// dictation in both ChatGPT and Claude, and this is the other feature.
    @ViewBuilder private var voiceButton: some View {
        if let onVoiceMode {
            let availability = VoicePermission.current(locale: lang.speechLocale)
            Button(action: onVoiceMode) {
                Image(systemName: "waveform")
                    .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                    .frame(width: surface == .dock ? 30 : 26,
                           height: surface == .dock ? 30 : 26)
                    .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!VoicePermission.offersButton(availability))
            .help(VoicePermission.help(availability, lang) ?? (lang == .vi ? "Chế độ giọng nói" : "Voice mode"))
        }
    }
```

`AppLanguage.speechLocale` does not exist — add it beside the enum:

```swift
    /// The locale for speech recognition. `vi-VN` has a recognizer but no on-device
    /// asset, which the overlay discloses; see the voice-mode spec §3.
    var speechLocale: Locale {
        Locale(identifier: self == .vi ? "vi-VN" : "en-US")
    }
```

- [ ] **Step 3: Present the overlay from `CopilotChatView`**

`@State private var voiceMode = false`, pass `onVoiceMode: { voiceMode = true }`
into the composer, and `.overlay { if voiceMode { VoiceModeOverlay(...) } }` on the
pane. Construct the real `SpeechListener(locale: lang.speechLocale, hints:)` with
hints from `DepartmentCatalog.roster.map(\.name) + PetCharacter.all.values.map(\.name) + ["Codepet"]`.

- [ ] **Step 4: Full suite, both targets**

```bash
pkill -x codepet 2>/dev/null; ./scripts/ci-test.sh 2>&1 | tail -14
```

Expected: `All N test(s) passed.` The baseline before this plan was **1581/1581**,
so any red is from this work. A `-only-testing:` branch is an untested branch — the
first full run on the composer branch found a real bug that six unrelated suites
paid for.

- [ ] **Step 5: Signed build, hand off, PR**

```bash
xcodebuild build -project CodePet.xcodeproj -scheme codepet -destination 'platform=macOS' \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=YL72VTKBR7 2>&1 | grep -E "error:|BUILD"
open /Users/monatruong/Library/Developer/Xcode/DerivedData/CodePet-furbrcwvotpbsbbntsynhhfqxdpq/Build/Products/Debug/codepet.app --args -CODEPET_TWO_MODE YES
```

**Then stop and hand off.** Four things only the founder can judge, and none of
them are testable here:

1. **Does 1.2s feel right?** One constant, `VoiceTurn.silenceThreshold`.
2. **Does barge-in actually work through the speakers?** The echo canceller was verified to *enable*; whether it cancels well enough that the app does not transcribe its own voice is an on-device question.
3. **Is the level gain right?** `rms * 12` is empirical; the orb may barely move or peg.
4. **Do the voices sound acceptable?** Every installed voice is `default` quality. If not, the fix is System Settings, not code — and that is the moment to decide whether the UI nudges her there.

```bash
git push -u origin <branch>
gh pr create --draft --base feat/two-mode-shell --title "Voice mode: talk to your company" --body "..."
```

Pushing a branch runs nothing — open a PR, even a draft, or CI never sees this.

---

## Self-Review

**Spec coverage.** §1 (voice mode, not dictation) → Task 7's `waveform` glyph choice. §2 decisions 1–3 → Tasks 7, 6, 3. §3's measured facts → Task 4's engine ownership and downmix, Task 5's Info.plist strings, Task 6's privacy line. §4's loop → Tasks 1 and 6. §5's six calls → sentence streaming (2), barge-in (1+4), room unreachable (nothing calls `RoomOffer` — verified by absence), whose voice (3), 1.2s (3), SFX ducking (4). §6's units → Tasks 1–4 and 6, same names. §7's risks → engine (4), TCC (5), credits (6's credit line), threshold (3), contextual strings (4).

**One spec item deliberately unbuilt:** §3's suggestion of a one-time nudge toward System Settings for better voices. It depends on the founder's judgment of the default voices after hearing them, which is Task 7's handoff item 4 — building it first would be guessing.

**Type consistency.** `VoiceProfile` (Task 3) is consumed with the same field names by `SpeakingVoice.enqueue(_:profile:)` (Task 4). `VoiceState`/`VoiceEvent` (Task 1) are used unchanged in Tasks 4 and 6. `VoiceAvailability` (Task 5) is compared with `== .ready` in Task 7, which requires the `Equatable` conformance Task 5 declares. `SentenceSplitter.take(from:)` is `mutating`, so Task 6 must hold it in a `@State` struct or a class — noted there.

**One name I invented and must be added, not assumed:** `AppLanguage.speechLocale` (Task 7 Step 2) and `ChiptuneEngine.sfxVolume` (Task 4 Step 3). Both have their code written in the step that needs them rather than being left as references.
