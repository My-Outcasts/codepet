// codepet/Views/Copilot/VoiceComposer.swift
import SwiftUI

/// Voice mode, **in the composer** — spec §2 decision 5, reversing decision 2.
///
/// The composer grows in place and the chat stays visible: the live transcript sits
/// top-left reading like a draft, a bar waveform runs along the bottom, and ✕ and ✓ are
/// two small circles bottom-right. No overlay and no orb.
///
/// **The tradeoff is deliberate.** What is given up is focus; what is bought is being
/// able to see the conversation you are having — which matters more here than it does
/// for Claude, because a Codepet reply is signed by a department and a pet, and the
/// founder loses that context behind a takeover.
///
/// **What did NOT change with the surface.** The state machine (`VoiceSession`), the
/// speaking pipeline (`SentenceSplitter`/`VoiceReplyDriver`/`SpeakingQueue`/`PetVoice`),
/// the two audio services behind their protocols, and the five rules that carry the
/// invariants (`VoiceTurnFlow`) are all reused verbatim. Everything said and heard
/// still lands in the ordinary transcript as ordinary messages (spec §1); nothing about
/// `sendChat` changes.
///
/// **Five calls here exist only because review proved defects against the audio
/// services, and every one of them fails SILENTLY if it is dropped.** They are
/// annotated at their call sites rather than listed once, because a list at the top of
/// a file is what someone deletes a call under:
///
/// 1. `voice.beginReply()` before the reply's **first** `enqueue` — not "on
///    `.replyBegan`", which is applied *when* the first sentence is enqueued and so
///    would leave the barge-in latch closed for sentence 1 of every post-interruption
///    reply. See `speak(_:streaming:)` and `VoiceTurnFlow.takeTurn`.
/// 2. `voice.endOfReply()` when `isStreaming` goes false — `onFinishedAll` fires only
///    when the queue is empty AND this was called, because a mid-stream drain is
///    ordinary (a fenced code block is 5–15 seconds of nothing speakable). See
///    `replyStreamEnded()`.
/// 3. `listener.endTurn()` on ✓ **and** on ✕ — one
///    `SFSpeechAudioBufferRecognitionRequest` transcribes all audio ever appended to
///    it and the listener stays running across turns so barge-in works, so without
///    this the second question arrives with the first glued to its front, sent and
///    charged, compounding all session. See `VoiceTurnFlow.takeTurn` and
///    `.abandonTurn` — the same fact reached from ✕, where clearing only the view's
///    state leaves the live request holding the sentence she just rejected.
/// 4. `voice.stopImmediately()` on close **and** in `.onDisappear` — ⌘B and a mode
///    switch both remove this view without calling `close()`. See both.
/// 5. `listener.onFailure` rendered, gated on `state != .speaking` — `start()`
///    returning does not mean recognition works, and `endOfTask` stops the listener
///    *before* reporting, so swallowing the failure leaves a live-looking surface that
///    hears nothing. See `wire()`.
///
/// **The room is unreachable from here** (spec §5): `sendChat`'s `convenesRoom`
/// defaults to false and is deliberately not passed. Convening costs
/// `RoomOffer.credits` (~10) and a misheard sentence must never spend it.
///
/// **Nothing auto-sends** (spec §2 decision 4). A turn is taken when the founder taps
/// ✓ and discarded when she taps ✕; silence does nothing at all. There is no periodic
/// work in this file, and `SpeechFakesTests.testSilenceAloneNeverTakesTheTurn` is the
/// assertion anything that reintroduces a timer has to argue with.
struct VoiceComposer: View {

    /// Whether voice mode is on. Owned by `CopilotChatView`, which swaps this view in
    /// for `ChatComposer` — the composer growing in place rather than an overlay
    /// covering the pane.
    @Binding var isActive: Bool
    let listener: SpeechListening
    let voice: SpeakingVoice
    /// The companion's hue, for ✓. Handed down for the same reason `ChatComposer` takes
    /// it: the composer does not get to decide whose product this is.
    var accent: Color = CodepetTheme.accentPurple

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.chatSurface) private var surface
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var session: VoiceSession
    /// What recognition has heard this turn. Shown because a founder who cannot see
    /// what was heard will not trust the reply (spec §4).
    @State private var partial: String
    /// Mic (listening) or output (speaking) level, 0…1, for the waveform.
    @State private var level: Float = 0
    /// Recognition died after `start()` returned. Takes the text slot — see
    /// `VoiceChrome.line`.
    @State private var failure: Error?
    @State private var driver = VoiceReplyDriver()
    /// Turns sent from this composer. The running credit count is this × the per-turn
    /// price — spec §7: talking is much faster than typing, so voice mode is the
    /// feature that makes turns cheap to spend without noticing.
    @State private var turns = 0

    init(isActive: Binding<Bool>, listener: SpeechListening, voice: SpeakingVoice,
         accent: Color = CodepetTheme.accentPurple) {
        self.init(isActive: isActive, listener: listener, voice: voice, accent: accent,
                  session: VoiceSession(), partial: "", failure: nil)
    }

    /// Seeded, for `preview` — `ImageRenderer` fires no `.onAppear` and no `.task`,
    /// so a host that armed itself in a lifecycle hook would measure a connecting
    /// composer and make every layout assertion vacuous.
    private init(isActive: Binding<Bool>, listener: SpeechListening, voice: SpeakingVoice,
                 accent: Color, session: VoiceSession, partial: String, failure: Error?) {
        _isActive = isActive
        self.listener = listener
        self.voice = voice
        self.accent = accent
        _session = State(initialValue: session)
        _partial = State(initialValue: partial)
        _failure = State(initialValue: failure)
    }

    // MARK: - Metrics

    /// **The expansion, and the reason it is a fixed slot rather than a growing one.**
    ///
    /// The transcript grows word by word as she talks, and a surface that reflows on
    /// every word moves ✕ and ✓ out from under her pointer mid-sentence. Two lines at
    /// `CodepetType.body`, which is also what makes the box visibly taller than the
    /// resting composer (`ComposerMetrics.paneMinTextHeight` is 24, the dock's floor is
    /// 21) — the growth spec §2 asks for falls out of the slot rather than being a
    /// second, independent constant that could disagree with it.
    static let transcriptHeight: CGFloat = 40

    private var cornerRadius: CGFloat { surface == .dock ? 16 : 12 }
    private var controlDiameter: CGFloat { surface == .dock ? 28 : 26 }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcriptSlot
            bottomRow
            statusLine
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 10)
        // The composer's own card, so this reads as the composer having grown rather
        // than as a different object in the composer's place. Accent-edged
        // unconditionally: the field is gone, so there is no focus ring left to say
        // that this strip is the thing currently listening to her.
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(surface == .dock ? CodepetTheme.surface : CodepetTokens.cardRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(accent.opacity(0.65), lineWidth: 1)
        )
        .shadow(color: reduceTransparency ? .clear : accent.opacity(0.22), radius: 16)
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
        // runs on the waveform toggle and nowhere else — so ⌘B (`AppShellView`'s
        // `showsCopilot && !collapsed`) and the Developer pill (`TwoModeShellView`
        // swapping `CopilotChatView` out) both remove this view without it ever being
        // told. `SpeechListener`'s `isolated deinit` still reaches `listener.stop()`,
        // but `SpeechSpeaker.deinit` only restores the SFX volume — it never calls
        // `synth.stopSpeaking(at:)`, and `AVSpeechSynthesizer`'s behaviour on dealloc
        // mid-utterance is undocumented. So: press ⌘B mid-sentence and the pet may keep
        // talking with no surface left to stop it, which is invariant 4's stated failure
        // by a route the invariant does not cover.
        //
        // **Not `close()`** — that writes `isActive` during teardown.
        .onDisappear {
            voice.stopImmediately()
            listener.stop()
        }
    }

    // MARK: - The text slot

    /// Top-left, reading like a draft (founder, 22 Aug). One slot for three sources;
    /// which one wins is `VoiceChrome.line`'s decision, not this view's, because the
    /// precedence is what replaced the takeover's separate caption row and its failure
    /// is silent — a founder told the mic is live and dead in the same frame.
    private var transcriptSlot: some View {
        let line = VoiceChrome.line(state: session.state, partial: partial,
                                    failure: failure, lang)
        return Text(line.text)
            .font(CodepetTheme.inter(CodepetType.body))
            .italic(line.kind == .transcript)
            .foregroundStyle(line.kind == .failure ? CodepetTheme.accentOrange
                                                   : CodepetTheme.mutedText)
            .lineLimit(2)
            .truncationMode(.head)   // the newest words are the ones she is checking
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Self.transcriptHeight, alignment: .topLeading)
    }

    // MARK: - The waveform and the controls

    /// Waveform centred, the toggle leading and the controls trailing — a `ZStack`
    /// rather than one `HStack`, because with the controls in the same row the bars
    /// would be centred in what is left over rather than in the composer.
    private var bottomRow: some View {
        ZStack {
            waveform
            HStack(spacing: 0) {
                waveformToggle
                Spacer(minLength: 0)
                controls
            }
        }
        // **No explicit height, deliberately.** The row is as tall as its tallest
        // control, which is the circles (26/28pt) against the waveform's 18pt ceiling.
        // A stated constant here would have been a second copy of `controlDiameter`
        // that could disagree with it — and, worse, it would hold the row's height up
        // after the circles were deleted, which is the one thing about this row that
        // fails silently: voice mode that can hear her and can never send. That is what
        // `VoiceComposerTests.testTheTurnCirclesAreOnTheSurface` measures.
    }

    /// **The exit, and it is where the founder pressed to get in.** `ChatComposer`'s
    /// waveform button is what opens voice mode; this is the same glyph in the same
    /// corner of the same card, lit — so leaving is the gesture that entered, pressed
    /// again, and the composer is never on screen without a visible way out.
    ///
    /// It also lets this surface carry ONE ✕. The takeover needed a caption under each
    /// of its two ✕s purely to tell "close voice mode" from "discard this sentence";
    /// giving the exit its own distinct glyph removes the ambiguity instead of
    /// labelling around it.
    private var waveformToggle: some View {
        Button(action: close) {
            Image(systemName: "waveform")
                .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: controlDiameter, height: controlDiameter)
                .background(Circle().fill(accent.opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(VoiceChrome.closeLabel(lang))
        .accessibilityLabel(VoiceChrome.closeLabel(lang))
    }

    /// The bar waveform. Heights come from `VoiceWaveform`, which is pure and asserted
    /// — the gain that feeds it had already been extracted for the same reason
    /// (`VoiceLevel`: a constant inline in an audio tap that no test could see).
    ///
    /// Flat during `.thinking`: nothing is being captured and nothing is being spoken,
    /// and spec §4 wants that legibly *not* listening.
    private var waveform: some View {
        let showsLevel = session.state == .listening || session.state == .speaking
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(VoiceWaveform.barHeights(level: showsLevel ? level : 0)
                            .enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(accent.opacity(showsLevel ? 0.75 : 0.35))
                    .frame(width: 2.5, height: height)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    /// **The only two things that take or drop a turn** (spec §2 decision 4), as two
    /// small circles rather than labelled buttons (founder, 22 Aug).
    ///
    /// ✓ *disables* rather than disappearing: a control that comes and goes under her
    /// pointer while she is talking is the same defect the fixed-height transcript slot
    /// exists to avoid. ✕ stays enabled with an empty transcript on purpose — it
    /// clears, and clearing nothing is harmless, where a disabled ✕ would grey out the
    /// moment she pauses to think and read as a composer that has stopped working.
    ///
    /// **There is only one ✕ on this surface, and that is a simplification the move
    /// bought.** The takeover carried two — one to close voice mode, one to discard a
    /// sentence — and needed a caption under each purely to tell them apart. The
    /// waveform button in the control row is the toggle now, so the ambiguity is gone
    /// rather than labelled around.
    @ViewBuilder private var controls: some View {
        // Before the mic is up (and after it has died) neither circle can do anything:
        // nothing has been heard, so ✓ is disabled and ✕ has nothing to discard. The
        // one useful control is out. Founder, 22 Aug: "`Cancel` appears only during
        // `Connecting…`".
        if session.state == .idle {
            Button(action: close) {
                Text(VoiceChrome.cancelLabel(lang))
                    .font(CodepetTheme.inter(CodepetType.subheadline))
                    .foregroundStyle(CodepetTheme.mutedText)
                    .padding(.horizontal, 8)
                    .frame(height: controlDiameter)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(VoiceChrome.cancelLabel(lang))
            .accessibilityLabel(VoiceChrome.cancelLabel(lang))
        } else {
            HStack(spacing: 8) {
                circleButton(symbol: "xmark", label: VoiceChrome.discardLabel(lang),
                             filled: false, enabled: true, action: discardTurn)
                circleButton(symbol: "checkmark", label: VoiceChrome.sendLabel(lang),
                             filled: true, enabled: canSend, action: sendTurn)
            }
        }
    }

    /// Whether ✓ can do anything right now. Reads the rule rather than restating it —
    /// see `VoiceTurnFlow.canTakeTurn`, which the send site checks again.
    private var canSend: Bool {
        VoiceTurnFlow.canTakeTurn(partial: partial, state: session.state, isBusy: isBusy)
    }

    /// A turn already in flight, typed or spoken. `sendMessage` returns silently on
    /// either flag, so this is the difference between a disabled ✓ she can see and a
    /// tap that appears to do nothing.
    private var isBusy: Bool {
        companyStore.isStreaming || companyStore.isCompanionTyping
    }

    /// ✕ grey and outlined, ✓ blue and filled — founder, 22 Aug.
    private func circleButton(symbol: String, label: String, filled: Bool,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled
                                 ? (enabled ? CodepetTheme.onAccent(accent) : .white)
                                 : CodepetTheme.mutedText)
                .frame(width: controlDiameter, height: controlDiameter)
                .background {
                    if filled {
                        Circle().fill(enabled ? AnyShapeStyle(accent)
                                              : AnyShapeStyle(CodepetTheme.mutedText.opacity(0.35)))
                    } else {
                        Circle().stroke(CodepetTheme.hairline)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - The compact line

    /// **Spec §2's two requirements Claude's composer does not have**: the privacy
    /// disclosure (§3) and the running credit count (§7), on one line. The escalation
    /// when the audio is not on-device is `VoiceChrome.statusLine`'s, and the colour
    /// follows it — a disclosure that her voice is leaving the Mac painted as grey
    /// chrome would be the footnote §3 forbids.
    private var statusLine: some View {
        Text(VoiceChrome.statusLine(turns: turns, onDevice: listener.isOnDevice, lang))
            .font(CodepetTheme.inter(CodepetType.footnote))
            .foregroundStyle(listener.isOnDevice ? CodepetTokens.faint
                                                 : CodepetTheme.accentOrange)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Wires the callbacks and opens the mic. **No periodic work** — every transition
    /// out of `.listening` is a tap or a callback from the listener, so a poll would
    /// have nothing to look at.
    private func run() async {
        wire()
        do {
            try listener.start()
        } catch {
            // Nothing useful can happen without recognition, so this is terminal —
            // but it is SHOWN, not swallowed, and the composer stays expanded to show
            // it. The state stays `.idle`, which is what puts `Cancel` under it.
            failure = error
            return
        }
        session.apply(.open)
    }

    private func wire() {
        // Remember the text and — while the pet is talking — treat any speech as
        // barge-in. The listener only calls this when the transcript actually CHANGED
        // (see `TurnTranscript.update`), so a recognizer re-reporting a string it
        // already reported cannot cut the pet off with words she has already had
        // answered.
        listener.onPartial = { text in
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
        // arrive. Unshown, the founder watches a composer that says "Listening…" and
        // hears nothing.
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
            // **But the listener is already dead by the time this runs.** `endOfTask`'s
            // `.fail` branch calls `stop()` *before* `onFailure?(error)` — tap removed,
            // voice processing off, engine stopped, `isRunning == false` — and nothing
            // ever restarts it: `start()` is called once, in `run()`, and `endTurn()`
            // early-returns on `guard isRunning`. So a long reply whose own audio the
            // voice processing cancels out of the mic exhausts `RenewalBudget` on
            // genuine silence, falls through here, and leaves the founder in a
            // `.listening` composer reading "Listening…" with the bars flat — talking
            // to a microphone that is gone, with nothing shown and nothing logged.
            //
            // Still return, and still show nothing: closing mid-answer is wrong, and
            // restarting *here* re-enters the same silence-death loop and churns the
            // engine for the whole reply. `VoiceTurnFlow.ensureListening` picks it up on
            // the way back to `.listening`, which is the first moment this surface
            // claims the microphone is live.
            guard session.state != .speaking else { return }
            listener.stop()
            failure = error
            session.apply(.close)
        }

        // The reply is over: drained AND `endOfReply()` was called.
        voice.onFinishedAll = {
            // The bars stop tracking anything. `onLevel` is what feeds them and the tap
            // fires ~10 times a second, so this is one frame of honesty and not a
            // latched value — which is why it is here and not inside `replyEnded`,
            // where a returned constant asserted against its own literal would be a
            // test that cannot fail.
            level = 0
            // Everything else — the stepping, the mic, and what must survive — is in
            // `VoiceTurnFlow.replyEnded`, which a test can drive. Only the failure path
            // stays here, because it writes `failure`.
            do {
                partial = try VoiceTurnFlow.replyEnded(session: &session, pending: partial,
                                                       listener: listener)
            } catch {
                // The restart itself refused — that is a real, fatal failure, and it
                // takes the normal path rather than being swallowed a second time.
                listener.stop()
                failure = error
                session.apply(.close)
            }
        }
    }

    /// Leaving voice mode. **`stopImmediately()` first, then collapse.** Without it the
    /// pet keeps talking to a composer that is gone, with the chiptune SFX still ducked
    /// to zero for the rest of the process.
    private func close() {
        voice.stopImmediately()
        listener.stop()
        session.apply(.close)
        isActive = false
    }

    // MARK: - The founder's turn

    /// ✓: take the turn, then send it.
    private func sendTurn() {
        guard let toSend = VoiceTurnFlow.takeTurn(partial: partial, session: &session,
                                                  listener: listener, voice: voice,
                                                  driver: &driver, isBusy: isBusy)
        else { return }
        partial = ""
        level = 0
        let language = lang
        // `convenesRoom` is left at its default false: the room is unreachable by
        // voice (spec §5) because a misheard sentence must never spend
        // `RoomOffer.credits`.
        //
        // **`turns += 1` is inside, after the await.** `sendMessage` checks
        // `isStreaming`/`isCompanionTyping` again when this Task actually runs, so
        // counting the turn out here counted one that could still be dropped. The cost
        // is that the count updates when the reply lands rather than when it is sent.
        Task {
            await companyStore.sendChat(toSend, language: language)
            turns += 1
        }
    }

    /// ✕. **No credit is spent and none is counted** — `turns` moves in exactly one
    /// place, `sendTurn()`'s Task, and nothing here goes near it.
    private func discardTurn() {
        VoiceTurnFlow.abandonTurn(listener)
        partial = ""
        level = 0
    }

    // MARK: - Speaking the reply

    /// Feeds the driver and enqueues what comes back.
    ///
    /// Called from two `.onChange`es on `body`: the growing reply text, and
    /// `isStreaming` going false. The second is the one that matters — see
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
    /// end and the composer reopens the mic and drops the bars to zero mid-reply, while
    /// the real reply is still arriving — and the session takes `.replyFinished`, which
    /// leaves `.speaking`, so the *rest* of the reply is then spoken from `.listening`,
    /// which `speak()` refuses outright: **the founder hears half an answer.**
    private func replyStreamEnded() {
        // **The stream that just ended has to be OURS.** Voice mode is openable at any
        // moment, including over a typed turn already in flight, and that seam is what
        // this guard closes:
        //
        // She sends a typed message; `isStreaming` is true. She taps the waveform —
        // the composer expands in `.listening` with no `beginReply()` behind it. She
        // speaks: `onPartial` fills `partial`, and because the state is `.listening`
        // rather than `.speaking` this is not barge-in, so the `SpeakingQueue` latch
        // never closes. `canTakeTurn`'s `isBusy` correctly holds ✓ disabled while the
        // typed reply streams, so her sentence is sitting on screen waiting for her
        // tap. Then the TYPED reply finishes, and ungated this fired `endOfReply()` on
        // a queue that had never begun a reply — and `SpeakingQueue` starts
        // `accepting = true, reported = false`, so a virgin queue drains and *reports*.
        // `onFinishedAll` then runs the whole reply-end path for a reply that was never
        // this surface's.
        //
        // **It used to erase her spoken question mid-flight** — no message, no credit
        // spent, and she had to say it all again. That half is fixed at the source:
        // `VoiceTurnFlow.replyEnded` no longer clears the transcript, and this guard is
        // no longer the only thing standing between her sentence and the bin.
        //
        // **It is still the right guard, and it still fires.** What is left ungated is
        // not cosmetic: `endOfReply()` marks the queue `reported`, `level` drops to
        // zero mid-sentence, and `ensureListening` runs against a `.listening` state it
        // was never asked about. Keeping it also means the two facts stay independent —
        // a later change that gives the reply-end path something new to reset does not
        // silently acquire this seam along with it. `VoicePermission.canEnterVoiceMode`
        // keeps her out of the situation; this keeps the situation harmless if she is
        // in it.
        guard VoiceTurnFlow.streamEndBelongsToVoiceTurn(session.state) else { return }
        speak(replyText, streaming: false)
        voice.endOfReply()
    }
}

#if DEBUG

// MARK: - Preview / measurement

/// Fakes for `VoiceComposer.preview`, in the app target because `preview` is. They do
/// nothing: the layout suite measures a surface, and **no test may start an audio
/// engine or construct an `SFSpeechRecognizer`** — a headless XCTest host has no
/// microphone and no window-server graphics context, and the last thing that reached
/// for one took six unrelated SSE tests down with it.
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
    /// Settable, because the whole finding behind `privacyLine(_:onDevice:)` is that
    /// this is a property of the installed assets and not of the language — and the
    /// status line's off-device branch is a different height on screen.
    var isOnDevice: Bool = true
    func start() throws {}
    func endTurn() {}
    func stop() {}
}

extension VoiceComposer {
    /// **A `static let`, never a per-call `CompanyStore()`.** The XCTest host on
    /// Xcode 26.2 crashes when a `@MainActor ObservableObject` deallocates
    /// (CLAUDE.md landmine 3) — one that is never released cannot take the host with
    /// it, and the suite renders this several times.
    private static let previewStore = CompanyStore()

    /// Seeded directly, because `ImageRenderer` fires neither `.onAppear` nor `.task`:
    /// a host that opened the session in a lifecycle hook would measure a connecting
    /// composer and every assertion against it would be vacuous.
    ///
    /// The state is reached by driving the real machine rather than by writing to it,
    /// so a `state` this suite asks for that the transition table does not allow would
    /// show up here instead of being silently accepted.
    static func preview(state: VoiceState, partial: String,
                        failure: Error? = nil, onDevice: Bool = true) -> some View {
        var session = VoiceSession()
        if state != .idle {
            session.apply(.open)
            if state == .thinking || state == .speaking { session.apply(.founderSentTurn) }
            if state == .speaking { session.apply(.replyBegan) }
        }
        let listener = InertSpeechListening()
        listener.isOnDevice = onDevice
        return VoiceComposer(isActive: .constant(true),
                             listener: listener,
                             voice: InertSpeakingVoice(),
                             accent: CodepetTheme.accentPurple,
                             session: session,
                             partial: partial,
                             failure: failure)
            .environmentObject(previewStore)
    }
}

#Preview("VoiceComposer (listening, 520pt)") {
    VoiceComposer.preview(state: .listening, partial: "add pricing for the beta")
        .frame(width: 520)
        .padding()
}

#Preview("VoiceComposer (connecting)") {
    VoiceComposer.preview(state: .idle, partial: "")
        .frame(width: 520)
        .padding()
}
#endif
