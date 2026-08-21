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
        // **Both axes ARE measurable, and both are measured** — see
        // `VoiceOverlayLayoutTests`. An earlier note here said `ImageRenderer`
        // "returns an image the size of any non-nil proposed dimension whatever the
        // view did with it", and that is false: it reports the *resolved* size on both
        // axes. **Do not repeat that claim in the other six `ImageRenderer` suites —
        // a sentence saying the framework cannot measure a filled dimension will
        // suppress a correct test somewhere else.**
        //
        // The real limitation is narrower: **the vertical fill is implemented twice
        // over** — by `maxHeight: .infinity` and, independently, by the two
        // `Spacer(minLength: 0)`s above, which take all offered height on their own.
        // So a height assertion is a property guard, not a modifier guard. Measured on
        // this branch against a 900×700 proposal:
        //
        //     frame + spacers          -> (900, 700)
        //     maxHeight deleted only   -> (900, 700)   still filling, via the spacers
        //     both deleted             -> (900, 368)   intrinsic, correctly reported
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
        // **The only teardown that covers a dismissal which is not the ✕.** `close()`
        // runs on the ✕ and nowhere else, and this overlay covers the pane rather than
        // the window — so ⌘B (`AppShellView`'s `showsCopilot && !collapsed`) and the
        // Developer pill (`TwoModeShellView` swapping `CopilotChatView` out) both
        // remove it without it ever being told. `SpeechListener`'s `isolated deinit`
        // still reaches `listener.stop()`, but `SpeechSpeaker.deinit` only restores
        // the SFX volume — it never calls `synth.stopSpeaking(at:)`, and
        // `AVSpeechSynthesizer`'s behaviour on dealloc mid-utterance is undocumented.
        // So: press ⌘B mid-sentence and the pet may keep talking with no surface left
        // to stop it, which is invariant 4's stated failure by a route the invariant
        // does not cover.
        //
        // **Not `close()`** — that writes `isPresented` during teardown.
        .onDisappear {
            voice.stopImmediately()
            listener.stop()
        }
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
            Text(Self.stateCaption(session.state, lang))
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
            Text(Self.privacyLine(lang, onDevice: listener.isOnDevice))
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

    /// **Spec §3, and it is a disclosure rather than a footnote.**
    ///
    /// **`onDevice` decides it, not `lang`.** This used to switch on the language
    /// alone and tell every English founder "nothing you say leaves it" — but
    /// `openRecognition` sets `requiresOnDeviceRecognition` from
    /// `recognizer.supportsOnDeviceRecognition` (`SpeechListening.swift`), and on a Mac
    /// where the en-US Assistant asset was never installed that is `false`: the audio
    /// goes to Apple's servers while the overlay says the opposite. Same shape as the
    /// `lang == .vi ? why : why` defect Task 5 caught — a decision that inspects one
    /// input and ignores the one that determines the answer.
    ///
    /// Vietnamese branches too, rather than being hard-coded to "sent to Apple":
    /// `SFSpeechRecognizer(vi-VN)` reports no on-device asset today (measured 21 Aug),
    /// but that is a fact about Apple's assets, not about the language, and a line
    /// that would still read "sent to Apple" the day the asset ships is the same
    /// defect pointing the other way.
    static func privacyLine(_ lang: AppLanguage, onDevice: Bool) -> String {
        if onDevice {
            return lang == .vi
                ? "Nhận dạng chạy trên chiếc Mac này. Không có gì bạn nói rời khỏi máy."
                : "Recognition runs on this Mac. Nothing you say leaves it."
        }
        return lang == .vi
            ? "Giọng nói của bạn được gửi tới Apple để nhận dạng."
            : "Your speech is sent to Apple for recognition. It does not stay on this Mac."
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

    /// The header line.
    ///
    /// **`.idle` is its own caption, and that is the whole point.** Two paths land in
    /// `.idle` with the overlay deliberately still on screen — `run()`'s catch, and
    /// `onFailure`'s fatal branch applying `.close` — and both of them set `failure`,
    /// so the transcript below is already reading "The microphone stopped: …". Folded
    /// in with `.listening`, as it was, the header said **"Listening"** directly above
    /// that: the founder told the microphone is live and dead in the same frame.
    ///
    /// No `failure` parameter, because it would be a guard that cannot fire:
    /// `failure != nil` is reachable in `.idle` and nowhere else. A failure raised
    /// while the pet is speaking is expected rather than broken and is not recorded
    /// (see `wire()`), and `close()` dismisses the overlay in the same breath.
    static func stateCaption(_ state: VoiceState, _ lang: AppLanguage) -> String {
        switch state {
        case .idle:      return lang == .vi ? "Đã dừng" : "Stopped"
        case .listening: return lang == .vi ? "Đang nghe" : "Listening"
        case .thinking:  return lang == .vi ? "Đang suy nghĩ" : "Thinking"
        case .speaking:  return lang == .vi ? "Đang trả lời" : "Answering"
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
            //
            // **But the listener is already dead by the time this runs, and returning
            // here used to be the end of it.** `endOfTask`'s `.fail` branch calls
            // `stop()` *before* `onFailure?(error)` — tap removed, voice processing
            // off, engine stopped, `isRunning == false` — and nothing ever restarted
            // it: `start()` was called once, in `run()`, and `endTurn()` early-returns
            // on `guard isRunning`. So a long reply whose own audio the voice
            // processing cancels out of the mic exhausted `RenewalBudget` on genuine
            // silence, fell through here, and left the founder in a `.listening`
            // overlay whose header read "Listening" with the orb at 0 — talking to a
            // microphone that was gone, with nothing shown and nothing logged.
            //
            // Still return, and still show nothing: closing mid-answer is wrong, and
            // restarting *here* re-enters the same silence-death loop and churns the
            // engine for the whole reply. `ensureListening` picks it up on the way
            // back to `.listening`, which is the first moment the overlay claims the
            // microphone is live.
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
            // **The mic may have died during the reply.** See `onFailure`'s
            // `.speaking` branch: this is the transition that makes the header say
            // "Listening", so it is where that has to become true again.
            do { try Self.ensureListening(listener, state: session.state) }
            catch {
                // The restart itself refused — that is a real, fatal failure, and it
                // takes the normal path rather than being swallowed a second time.
                listener.stop()
                failure = error
                session.apply(.close)
            }
        }
    }

    /// **The microphone is alive whenever the overlay claims to be listening.**
    ///
    /// A recognition failure raised while the pet was speaking is deliberately not
    /// shown (see `wire()`) — but `SpeechListener` has already fully torn itself down
    /// by then, and nothing else ever calls `start()` a second time. Without this the
    /// overlay returns to `.listening`, the header says so, and the founder talks into
    /// a dead microphone for the rest of the session with no error on screen.
    ///
    /// Static and taking the state explicitly so the rule is reachable from a test:
    /// everything inside a `View`'s private closures is not. Returns whether it
    /// actually restarted, so a test can tell "was already running" from "did nothing".
    @discardableResult
    static func ensureListening(_ listener: SpeechListening, state: VoiceState) throws -> Bool {
        // Only `.listening` makes the promise. `.speaking` deliberately tolerates a
        // dead request, and in `.idle`/`.thinking` the overlay claims nothing.
        guard state == .listening else { return false }
        // `isRunning` rather than a flag set by `onFailure`: it is the same fact, it
        // is already on the protocol, and a second copy of it is one more thing that
        // can disagree with the listener about whether the listener is running.
        guard !listener.isRunning else { return false }
        try listener.start()
        return true
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

        let toSend = text
        let language = lang
        // 1. Send what she said. `convenesRoom` is left at its default false: the
        //    room is unreachable by voice (spec §5) because a misheard sentence must
        //    never spend RoomOffer.credits.
        //
        //    **`turns += 1` is inside, after the await.** The flags checked below are
        //    checked again by `sendMessage` when this Task actually runs, so counting
        //    the turn out here counted one that could still be dropped. No real
        //    interleaving was constructed, so this is defensive — but it makes the
        //    credit line honest by construction rather than by argument, and the cost
        //    is that the count updates when the reply lands instead of when it is sent.
        Task {
            await companyStore.sendChat(toSend, language: language)
            turns += 1
        }
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
        // **The stream that just ended has to be OURS.** The overlay is openable at
        // any moment, including over a typed turn already in flight, and that seam is
        // what this guard closes:
        //
        // She sends a typed message; `isStreaming` is true. She taps the waveform —
        // the overlay opens in `.listening` with no `beginReply()` behind it. She
        // speaks: `onPartial` fills `partial` and stamps `lastSpeechAt`, and because
        // the state is `.listening` rather than `.speaking` this is not barge-in, so
        // the `SpeakingQueue` latch never closes. The 1.2s silence fires,
        // `endTurnIfSilent`'s `guard !isStreaming` correctly waits a tick. Then the
        // TYPED reply finishes, and ungated this fired `endOfReply()` on a queue that
        // had never begun a reply — and `SpeakingQueue` starts `accepting = true,
        // reported = false`, so a virgin queue drains and *reports*. `onFinishedAll`
        // then no-ops the illegal `.replyFinished` and unconditionally clears
        // `partial`, `lastSpeechAt` and `level`.
        //
        // **Her spoken question is erased mid-flight** — no message, no orb change,
        // no credit spent, and she has to say it all again. `VoicePermission
        // .canEnterVoiceMode` keeps her out of this situation; this keeps the
        // situation harmless if she is in it.
        guard Self.streamEndBelongsToVoiceTurn(session.state) else { return }
        speak(replyText, streaming: false)
        voice.endOfReply()
    }

    /// Whether `isStreaming` going false is the end of a reply **this overlay asked
    /// for**. Only `.thinking` and `.speaking` follow a `beginReply()`.
    ///
    /// Extracted so it can be tested: its failure is silent — an erased question and
    /// a founder repeating herself — and every other line of `replyStreamEnded` is
    /// unreachable from a test.
    static func streamEndBelongsToVoiceTurn(_ state: VoiceState) -> Bool {
        state == .thinking || state == .speaking
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
    /// `true` so the measured overlay renders the ordinary English disclosure. The
    /// copy itself is pinned against `privacyLine` directly, not against this.
    var isOnDevice: Bool { true }
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
