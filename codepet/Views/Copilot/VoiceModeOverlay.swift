// codepet/Views/Copilot/VoiceModeOverlay.swift
import SwiftUI

/// Voice mode, the takeover — spec §2 decision 2, §4.
///
/// The surface that drives the feature: it owns the `VoiceSession`, holds the mic
/// open, sends the founder's turn through the ordinary `sendChat`, and reads the
/// reply aloud sentence by sentence as it streams. Everything said and heard lands
/// in the ordinary transcript; close the overlay and the exchange is there to
/// scroll, copy, retry and thumb (spec §1).
///
/// **Five calls here exist only because review proved defects against the audio
/// services, and every one of them fails SILENTLY if it is dropped.** They are
/// annotated at their call sites rather than listed once, because a list at the top
/// of a file is what someone deletes a call under:
///
/// 1. `voice.beginReply()` before the reply's **first** `enqueue` — not "on
///    `.replyBegan`", which is applied *when* the first sentence is enqueued and so
///    would leave the barge-in latch closed for sentence 1 of every post-interruption
///    reply. See `speak(_:streaming:)`.
/// 2. `voice.endOfReply()` when `isStreaming` goes false — `onFinishedAll` fires only
///    when the queue is empty AND this was called, because a mid-stream drain is
///    ordinary (a fenced code block is 5–15 seconds of nothing speakable). See
///    `replyStreamEnded()`.
/// 3. `listener.endTurn()` at the send site — one
///    `SFSpeechAudioBufferRecognitionRequest` transcribes all audio ever appended to
///    it and the listener stays running across turns so barge-in works, so without
///    this the second question arrives with the first glued to its front, sent and
///    charged, compounding all session. See `endTurnIfSilent()`.
/// 4. `voice.stopImmediately()` on close, before dismissing — otherwise ✕ mid-sentence
///    leaves the pet talking to an overlay that is gone, SFX still ducked to zero.
///    See `close()`.
/// 5. `listener.onFailure` rendered — `start()` returning does not mean recognition
///    works, so without this the founder watches a live-looking orb that never
///    produces a word. It is fatal in every state EXCEPT `.speaking`, where a
///    silence-terminated request is expected rather than broken. See `wire()`.
///
/// **The room is unreachable from here** (spec §5): `sendChat`'s `convenesRoom`
/// defaults to false and is deliberately not passed. Convening costs
/// `RoomOffer.credits` (~10) and a misheard sentence must never spend it.
struct VoiceModeOverlay: View {

    @Binding var isPresented: Bool
    let listener: SpeechListening
    let voice: SpeakingVoice

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var session: VoiceSession
    /// What recognition has heard this turn. Shown because a founder who cannot see
    /// what was heard will not trust the reply (spec §4).
    @State private var partial: String
    /// Stamped on every partial. `nil` means nothing has been heard, which never
    /// ends a turn — see `VoiceTurn.shouldEndTurn`.
    @State private var lastSpeechAt: Date?
    /// Mic (listening) or output (speaking) level, 0…1, for the orb.
    @State private var level: Float = 0
    /// Recognition died after `start()` returned. Rendered in place of the partial.
    @State private var failure: Error?
    @State private var driver = VoiceReplyDriver()
    /// Turns sent from this overlay. The running credit count is this × the per-turn
    /// price — spec §7: talking is much faster than typing, so voice mode is the
    /// feature that makes turns cheap to spend without noticing.
    @State private var turns = 0

    init(isPresented: Binding<Bool>, listener: SpeechListening, voice: SpeakingVoice) {
        self.init(isPresented: isPresented, listener: listener, voice: voice,
                  session: VoiceSession(), partial: "")
    }

    /// Seeded, for `preview` — `ImageRenderer` fires no `.onAppear` and no `.task`,
    /// so a host that armed itself in a lifecycle hook would measure the idle
    /// overlay and make every layout assertion vacuous.
    private init(isPresented: Binding<Bool>, listener: SpeechListening, voice: SpeakingVoice,
                 session: VoiceSession, partial: String) {
        _isPresented = isPresented
        self.listener = listener
        self.voice = voice
        _session = State(initialValue: session)
        _partial = State(initialValue: partial)
    }

    // MARK: - Cost

    /// 0.25 credits per spoken exchange — spec §7's "ten spoken exchanges is ~2.5
    /// credits in about two minutes", stated as the per-turn number so the line on
    /// screen and the spec cannot drift.
    static let creditsPerTurn = 0.25

    // MARK: - Body

    var body: some View {
        VStack(spacing: 22) {
            header
            Spacer(minLength: 0)
            orb
            transcript
            Spacer(minLength: 0)
            footer
        }
        .padding(28)
        // A takeover, not a panel: it covers the pane so the transcript is not
        // competing for attention with a conversation being held out loud.
        //
        // **The VERTICAL half of this is not testable and is not tested.**
        // `ImageRenderer` returns an image the size of any non-nil proposed
        // dimension whatever the view did with it (measured: a deliberately
        // non-filling overlay still reported 700pt of 700), so vertical fill is part
        // of the founder's visual handoff. The horizontal half IS measured, against
        // an unconstrained height — see `VoiceOverlayLayoutTests`.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        // The two observations that drive speech. On `body` rather than on a state
        // branch, so neither can be lost to whichever branch is on screen.
        .onChange(of: replyText) { _, text in
            speak(text, streaming: companyStore.isStreaming)
        }
        .onChange(of: companyStore.isStreaming) { was, now in
            if was && !now { replyStreamEnded() }
        }
        .task { await run() }
    }

    @ViewBuilder
    private var background: some View {
        if reduceTransparency {
            CodepetTheme.pageBackground
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack {
            Text(stateCaption)
                .font(CodepetTheme.inter(CodepetType.callout, weight: .medium))
                .foregroundStyle(CodepetTheme.mutedText)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Đóng chế độ giọng nói" : "Close voice mode")
            .accessibilityLabel(lang == .vi ? "Đóng chế độ giọng nói" : "Close voice mode")
        }
    }

    /// The focal point. `companionId` is the pet that signs the reply, so while
    /// `sage` is answering the orb is tinted `sage`'s hues rather than the account's
    /// — and `nil` while listening, because the founder is talking and nobody is
    /// answering yet.
    ///
    /// `isWorking` is the ONLY thing that drives the orb's own breathe, so handing it
    /// `.thinking` gives spec §4's "legibly not listening": on `.thinking` the scale
    /// is a fixed slow cycle, and on `.listening`/`.speaking` it tracks the level
    /// instead.
    private var orb: some View {
        CompanionOrb(size: 148, glow: true,
                     isWorking: session.state == .thinking,
                     companionId: session.state == .listening ? nil : speakingPet)
            .scaleEffect(levelScale)
            .animation(.easeOut(duration: 0.12), value: levelScale)
            .accessibilityHidden(true)
    }

    private var levelScale: CGFloat {
        guard session.state == .listening || session.state == .speaking else { return 1 }
        return 1 + 0.12 * CGFloat(min(max(level, 0), 1))
    }

    /// **Fixed height for two lines, and that is what the layout suite pins.** The
    /// partial grows word by word as she talks; a surface that reflows on every word
    /// moves the ✕ under her cursor mid-sentence.
    private var transcript: some View {
        Text(failure == nil ? partial : failureLine)
            .font(CodepetTheme.inter(CodepetType.body))
            .foregroundStyle(failure == nil ? CodepetTheme.bodyText : CodepetTheme.accentOrange)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.head)   // the newest words are the ones she is checking
            .frame(maxWidth: 520)
            .frame(height: 40, alignment: .top)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text(Self.privacyLine(lang))
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundStyle(CodepetTheme.mutedText)
            Text(Self.creditLine(turns: turns, lang))
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundStyle(CodepetTheme.mutedText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 520)
    }

    // MARK: - Copy

    /// **Spec §3, and it is a disclosure rather than a footnote.** In English
    /// recognition is on-device: nothing said in voice mode leaves the Mac, and the
    /// audio costs no credits. In Vietnamese it does leave, because
    /// `SFSpeechRecognizer(vi-VN)` reports `supportsOnDeviceRecognition == false`
    /// ("No Assistant asset for language vi-VN") — measured 21 Aug. That is not
    /// fixable by us, so it is stated.
    static func privacyLine(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Giọng nói của bạn được gửi tới Apple để nhận dạng."
            : "Recognition runs on this Mac. Nothing you say leaves it."
    }

    /// The running count. Spelled out per turn as well as in total, because the
    /// number that surprises a founder is how many turns two minutes of talking is.
    static func creditLine(turns: Int, _ lang: AppLanguage) -> String {
        let spent = Double(turns) * creditsPerTurn
        // %g, not %.2f: 2.5 must read "2.5" and 0 must read "0", not "2.50"/"0.00".
        let amount = String(format: "%g", spent)
        return lang == .vi
            ? "\(turns) lượt · ~\(amount) tín dụng phiên này"
            : "\(turns) turns · ~\(amount) credits this session"
    }

    private var stateCaption: String {
        switch session.state {
        case .idle, .listening: return lang == .vi ? "Đang nghe" : "Listening"
        case .thinking:         return lang == .vi ? "Đang suy nghĩ" : "Thinking"
        case .speaking:         return lang == .vi ? "Đang trả lời" : "Answering"
        }
    }

    /// Founder-facing text for a recognition failure. `VoiceAudioError` deliberately
    /// carries no copy of its own — chrome is bilingual, so the words live here.
    private var failureLine: String {
        guard let failure else { return "" }
        switch failure {
        case VoiceAudioError.recognizerUnavailable:
            return lang == .vi
                ? "Không dùng được nhận dạng giọng nói lúc này."
                : "Speech recognition is not available right now."
        case VoiceAudioError.engineFailed(let why):
            return lang == .vi ? "Micro đã dừng: \(why)" : "The microphone stopped: \(why)"
        default:
            return failure.localizedDescription
        }
    }

    // MARK: - The reply being spoken

    /// The reply in flight — the newest companion message. Its text is filled in
    /// place, delta by delta, by `CompanyStore`, so this is the same string growing.
    private var replyText: String {
        companyStore.chatMessages.last { $0.role == .companion }?.text ?? ""
    }

    /// Whose voice speaks: whoever signs the reply (spec §5). `nil` is the host,
    /// which `PetVoice.profile` answers with byte's profile.
    private var speakingPet: String? {
        companyStore.chatMessages.last { $0.role == .companion }?.companionId
    }

    // MARK: - Lifecycle

    /// Wires the callbacks, opens the mic, then runs the silence check.
    ///
    /// A `.task` rather than a `Timer` publisher: the view re-renders on every level
    /// callback, and a publisher rebuilt on each of those churns its subscription
    /// several times a second. Cancelled automatically when the overlay goes away.
    private func run() async {
        wire()
        do {
            try listener.start()
        } catch {
            // Nothing useful can happen without recognition, so this is terminal —
            // but it is SHOWN, not swallowed, and the overlay stays up to show it.
            failure = error
            return
        }
        session.apply(.open)

        // 4Hz. The threshold is 1.2s, so a quarter-second granularity is invisible
        // to the founder and costs a comparison.
        while !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            endTurnIfSilent()
        }
    }

    private func wire() {
        // Remember the text, stamp the time, and — while the pet is talking — treat
        // any speech as barge-in. The listener only calls this when the transcript
        // actually CHANGED (see `TurnTranscript.update`), so a recognizer re-reporting
        // a string it already reported cannot cut the pet off with words she has
        // already had answered.
        listener.onPartial = { text in
            lastSpeechAt = Date()
            partial = text
            if session.state == .speaking {
                voice.stopImmediately()
                session.apply(.founderInterrupted)
            }
        }

        listener.onLevel = { level = $0 }

        // Recognition died AFTER start() returned — permission revoked, the service
        // went away, or (vi-VN is server-side) the network dropped.
        // `SFSpeechRecognizer.isAvailable` reports SERVICE availability, not
        // authorisation, so a clean `start()` is no promise that a word will ever
        // arrive. Unshown, the founder watches a live-looking orb that hears nothing.
        listener.onFailure = { error in
            // **A failure while the pet is speaking is expected, not fatal.** Voice
            // processing cancels the pet's own audio out of the microphone — that is
            // what makes barge-in possible — so a recognition request opened at a
            // turn boundary and left running while the founder merely LISTENS hears
            // genuine silence. A buffer task that self-terminates on silence
            // (`kAFAssistantErrorDomain`, "no speech detected") then dies through no
            // fault of hers, renews, dies again, and exhausts `RenewalBudget`.
            // Closing on that would shut voice mode down mid-answer.
            //
            // The guard CAN fire because the listener stays running through
            // `.speaking` on purpose: barge-in needs the mic open while the pet talks.
            // Every other state is a real failure and must be shown.
            guard session.state != .speaking else { return }
            listener.stop()
            failure = error
            session.apply(.close)
        }

        // The reply is over: drained AND `endOfReply()` was called.
        voice.onFinishedAll = {
            // A reply with nothing speakable — an answer that is only a fenced code
            // block, which `SentenceSplitter.speakable` deletes entirely — never
            // reached `.speaking`, and `.replyFinished` is not legal from `.thinking`.
            // Step through it, or the overlay hangs in `.thinking` with the turn
            // taken, the mic shut, and nothing to wait for.
            if session.state == .thinking { session.apply(.replyBegan) }
            session.apply(.replyFinished)
            // A fresh turn: the previous turn's timestamp must not end this one
            // before she has said anything.
            partial = ""
            lastSpeechAt = nil
            level = 0
        }
    }

    /// ✕. **`stopImmediately()` first, then dismiss.** Without it the pet keeps
    /// talking to an overlay that is gone, with the chiptune SFX still ducked to zero
    /// for the rest of the process.
    private func close() {
        voice.stopImmediately()
        listener.stop()
        session.apply(.close)
        isPresented = false
    }

    // MARK: - The founder's turn

    /// The silence check, at 4Hz. On a true it does three things in this order: send
    /// what she said, tell the listener the turn is over, move to `.thinking`.
    private func endTurnIfSilent() {
        // No `failure == nil` here: a failure that is fatal applies `.close`, which
        // leaves `.idle`, so the state check already covers it. A second guard that
        // cannot fire is the thing this project's own rule forbids.
        guard session.state == .listening else { return }
        guard VoiceTurn.shouldEndTurn(lastSpeechAt: lastSpeechAt, now: Date()) else { return }

        let text = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            // Heard something, and it rendered to nothing. Re-arm rather than send:
            // `sendChat` would drop an empty string anyway, and this way the next
            // tick is not still holding a stale timestamp.
            lastSpeechAt = nil
            return
        }

        // **`sendMessage` returns silently while a turn is in flight** (its own
        // `guard !isCompanionTyping, !isStreaming`), which is reachable from here:
        // barge-in returns to `.listening` while the interrupted reply is still
        // streaming. Sending into that guard would take the turn, clear the
        // transcript, move to `.thinking` — and never get a reply, with the founder's
        // question gone. Waiting instead costs one more tick: `lastSpeechAt` is left
        // alone, so the next tick after the stream ends sends it.
        guard !companyStore.isStreaming, !companyStore.isCompanionTyping else { return }

        // A new reply starts from its first sentence. Without this the splitter's
        // count still stands against the PREVIOUS reply and the new one's opening
        // sentences are skipped as already spoken.
        driver.reset()
        // **Reopens the barge-in latch before anything is enqueued.** Also here
        // rather than only in `speak` because `endOfReply` on a queue that already
        // reported its previous reply finished is a no-op — a reply with nothing
        // speakable would then never fire `onFinishedAll` and the overlay would hang
        // in `.thinking`.
        voice.beginReply()
        turns += 1

        let toSend = text
        let language = lang
        // 1. Send what she said. `convenesRoom` is left at its default false: the
        //    room is unreachable by voice (spec §5) because a misheard sentence must
        //    never spend RoomOffer.credits.
        Task { await companyStore.sendChat(toSend, language: language) }
        // 2. Retire the recognition request. See the protocol's note: without this
        //    the next question arrives with this one glued to its front.
        listener.endTurn()
        // 3. Move to `.thinking` — the orb stops tracking level and breathes, so she
        //    can see the turn was taken.
        session.apply(.heardSilence)
        partial = ""
        lastSpeechAt = nil
        level = 0
    }

    // MARK: - Speaking the reply

    /// Feeds the driver and enqueues what comes back.
    ///
    /// Called from two `.onChange`es, in `attach(to:)` below: the growing reply text,
    /// and `isStreaming` going false. The second is the one that matters — see
    /// `replyStreamEnded`.
    private func speak(_ text: String, streaming: Bool) {
        guard session.state == .thinking || session.state == .speaking else {
            // `.listening` here is barge-in: the stream is still arriving and this is
            // still being called, and the rest of the interrupted reply must stay
            // unspoken. (`SpeakingQueue`'s latch would refuse it too; not relying on
            // one of the two is deliberate.)
            return
        }
        let sentences = driver.sentencesToSpeak(replyText: text, isStreaming: streaming)
        // Nothing speakable yet is ordinary — mid-sentence, or a fenced code block
        // that `speakable` deletes entirely. It is not the reply beginning.
        guard !sentences.isEmpty else { return }
        for sentence in sentences {
            voice.enqueue(sentence, profile: PetVoice.profile(for: speakingPet))
        }
        // Applied AFTER the enqueues, which is why `beginReply()` cannot be hung off
        // this event: `.replyBegan` is what moves `.thinking` → `.speaking`, so
        // "call beginReply on .replyBegan" reopens the latch one sentence too late
        // and drops sentence 1 of every post-barge-in reply.
        session.apply(.replyBegan)
    }

    /// `isStreaming` went false. **Flush, then `endOfReply()`.**
    ///
    /// The flush is the only thing that releases the reply's last sentence: `take`
    /// refuses a terminator that is merely the last character currently available,
    /// because mid-stream `"The price is $3."` is both a complete sentence and the
    /// first half of `"$3.14 today."`. Omit it and every reply loses its last
    /// sentence — with no exception and no log.
    ///
    /// `endOfReply()` is what lets `onFinishedAll` ever fire. It is NOT inferable
    /// from the queue draining: `speakable` deletes fenced code blocks entirely, so a
    /// 50-line snippet is 5–15 seconds with nothing to say. Treat that drain as the
    /// end and the overlay reopens the mic, arms the 1.2s timer, hears silence, and
    /// spends a credit on an empty turn while the real reply is still arriving.
    private func replyStreamEnded() {
        speak(replyText, streaming: false)
        voice.endOfReply()
    }
}

#if DEBUG

// MARK: - Preview / measurement

/// Fakes for `VoiceModeOverlay.preview`, in the app target because `preview` is.
/// They do nothing: the layout suite measures a surface, and **no test may start an
/// audio engine or construct an `SFSpeechRecognizer`** — a headless XCTest host has
/// no microphone and no window-server graphics context, and the last thing that
/// reached for one took six unrelated SSE tests down with it.
final class InertSpeakingVoice: SpeakingVoice {
    var onFinishedAll: (() -> Void)?
    var isSpeaking: Bool { false }
    func beginReply() {}
    func enqueue(_ sentence: String, profile: VoiceProfile) {}
    func endOfReply() {}
    func stopImmediately() {}
}

final class InertSpeechListening: SpeechListening {
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?
    var isRunning: Bool { false }
    func start() throws {}
    func endTurn() {}
    func stop() {}
}

extension VoiceModeOverlay {
    /// **A `static let`, never a per-call `CompanyStore()`.** The XCTest host on
    /// Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates
    /// (CLAUDE.md landmine 3) — one that is never released cannot take the host with
    /// it, and the suite renders this several times.
    private static let previewStore = CompanyStore()

    /// Seeded directly, because `ImageRenderer` fires neither `.onAppear` nor
    /// `.task`: a host that opened the session in a lifecycle hook would measure the
    /// idle overlay and every assertion against it would be vacuous.
    ///
    /// The state is reached by driving the real machine rather than by writing to it,
    /// so a `state` this suite asks for that the transition table does not allow
    /// would show up here instead of being silently accepted.
    static func preview(state: VoiceState, partial: String) -> some View {
        var session = VoiceSession()
        if state != .idle {
            session.apply(.open)
            if state == .thinking || state == .speaking { session.apply(.heardSilence) }
            if state == .speaking { session.apply(.replyBegan) }
        }
        return VoiceModeOverlay(isPresented: .constant(true),
                                listener: InertSpeechListening(),
                                voice: InertSpeakingVoice(),
                                session: session,
                                partial: partial)
            .environmentObject(previewStore)
    }
}
#endif
