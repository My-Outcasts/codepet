// codepet/Views/Copilot/VoiceComposer.swift
import SwiftUI

/// Voice mode, **in the composer** — spec §2 decision 5, reversing decision 2.
///
/// The composer grows in place and the chat stays visible: the live transcript sits
/// top-left reading like a draft, a bar waveform runs along the bottom, and ✕ and ✓ are
/// two small circles bottom-right. No takeover and no orb.
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
/// **This view owns no turn state, and that is the fix for the defect the move
/// introduced.** `session`/`partial`/`level`/`failure`/`driver`/`turns` live on
/// `CopilotChatView` as one `VoiceTurn`, handed down here as a `@Binding` — because the
/// composer slot is rendered from inside a three-way `if/else`, and the founder's own
/// first spoken turn in every thread flips that `if/else` (`CompanyStore.sendMessage`
/// appends her message synchronously, before its first await). Different branches are
/// different structural identities, so `@State` here was destroyed mid-turn and rebuilt
/// at `.idle`: the question was sent and charged and the pet said nothing. The whole
/// argument, and what each field costs when it resets, is on `VoiceTurn`.
///
/// **Five calls exist only because review proved defects against the audio services,
/// and every one of them fails SILENTLY if it is dropped.** Four of the five now live
/// on `VoiceTurn` with the state they mutate; they are annotated at their call sites
/// there rather than listed once, because a list at the top of a file is what someone
/// deletes a call under. What is left here is where each one is *reached from*:
///
/// 1. `voice.beginReply()` before the reply's **first** `enqueue` — inside
///    `VoiceTurnFlow.takeTurn`, reached from `sendTurn()` below.
/// 2. `voice.endOfReply()` when `isStreaming` goes false — `VoiceTurn.replyStreamEnded`,
///    reached from an `.onChange` on **`CopilotChatView`**, not on this body. It was on
///    this body, and that is the second half of the same defect: the History panel
///    removes this view while a reply is being spoken, so the observation went with it.
/// 3. `listener.endTurn()` on ✓ **and** on ✕ — `VoiceTurn.take` and `.discard`, both
///    reached from `controls` below.
/// 4. `voice.stopImmediately()` on close **and** when the pane goes away — `close()`
///    here, and `CopilotChatView`'s `.onDisappear`. **Deliberately not this view's
///    `.onDisappear`:** this view disappears on a branch flip and whenever History
///    opens, neither of which means voice mode is over.
/// 5. `listener.onFailure` rendered, gated on `state != .speaking` — `VoiceTurn.wire`.
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
    /// The whole turn, owned by `CopilotChatView`. See `VoiceTurn`.
    @Binding var turn: VoiceTurn
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

    /// The card's own inset. Stated because the §3 disclosure has to fit two lines of
    /// the width this leaves, and the test that checks that has to be measuring the
    /// same width the founder gets — see
    /// `VoiceComposerTests.testTheOffDeviceDisclosureFitsTwoLinesInTheDock`.
    static let horizontalPadding: CGFloat = 14

    private var cornerRadius: CGFloat { surface == .dock ? 16 : 12 }
    private var controlDiameter: CGFloat { surface == .dock ? 28 : 26 }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcriptSlot
            bottomRow
            disclosure
        }
        .padding(.horizontal, Self.horizontalPadding).padding(.top, 11).padding(.bottom, 10)
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
        // **Wire, then open the mic — and this runs again on every rebuild.** A branch
        // flip and a closed History panel both re-create this view, so neither half may
        // assume it is the first: `wire` re-installs the same closures against a binding
        // that was already writing through, and `openMic` is guarded by
        // `turn.micOpened`.
        //
        // The mic is opened HERE rather than in `startVoiceMode()` for one
        // founder-visible reason: `listener.start()` is a ~200ms synchronous engine
        // spin-up, and spec §2 wants the composer on screen reading `Connecting…` while
        // it happens. Started before `voiceMode = true` there would be no frame in
        // which `.idle` is ever seen.
        //
        // **The teardown is NOT here.** See `close()` and `CopilotChatView`'s
        // `.onDisappear` — a `.onDisappear` on this view fires on a branch flip and
        // would stop a microphone the next instance is about to keep using.
        .task {
            VoiceTurn.wire($turn, listener: listener, voice: voice)
            turn.openMic(listener)
        }
    }

    // MARK: - The text slot

    /// Top-left, reading like a draft (founder, 22 Aug). One slot for three sources;
    /// which one wins is `VoiceChrome.line`'s decision, not this view's, because the
    /// precedence is what replaced the takeover's separate caption row and its failure
    /// is silent — a founder told the mic is live and dead in the same frame.
    private var transcriptSlot: some View {
        let line = VoiceChrome.line(state: turn.session.state, partial: turn.partial,
                                    failure: turn.failure, lang)
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
        // that could disagree with it.
        //
        // **And nothing measures that the circles are in this row.** Deleting
        // `controls` changes the rendered height by nothing at all — `waveformToggle`
        // is the same `controlDiameter` tall — so the obvious guard is vacuous and was
        // measured to be (`VoiceComposerTests
        // .testTheComposersMeasuredHeightIsPinnedWithAndWithoutTheDisclosure` records
        // it: with `controls` commented out the whole suite went green). What IS
        // asserted is which controls this state is supposed to offer —
        // `VoiceChrome.controls(for:)`, in
        // `testTheCancelButtonIsOfferedOnlyWhileTheComposerIsConnecting` — and the
        // composer's total height, which goes red for a padding or slot change and
        // does NOT isolate this row. Voice mode that can hear her and can never send
        // is a state no test here can see.
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
    /// **Esc is attached HERE, and that is the whole of change 2** (founder, 22 Aug).
    /// Not a hidden button and not `.onExitCommand`: this Button already is the exit, so
    /// the key routes through the one `close()` that exists rather than through a second
    /// teardown that could forget `stopImmediately()` or `listener.stop()`. See
    /// `VoiceHotkey.exit`, and `VoiceTurn.leave` for why the pane's `.onDisappear` still
    /// has to carry the other half.
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
        .keyboardShortcut(VoiceHotkey.exit.key, modifiers: VoiceHotkey.exit.modifiers)
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
        let showsLevel = turn.session.state == .listening || turn.session.state == .speaking
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(VoiceWaveform.barHeights(level: showsLevel ? turn.level : 0)
                            .enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(accent.opacity(showsLevel ? 0.75 : 0.35))
                    .frame(width: 2.5, height: height)
            }
        }
        .animation(.easeOut(duration: 0.12), value: turn.level)
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
    ///
    /// **Which controls a state offers is `VoiceChrome.controls(for:)`, not an `if`
    /// here.** It was an `if session.state == .idle` inside this `@ViewBuilder`, where
    /// nothing could reach it — a pure state→copy mapping hidden in a view, which is
    /// exactly the shape `VoiceChrome.line` was extracted out of.
    @ViewBuilder private var controls: some View {
        let offered = VoiceChrome.controls(for: turn.session.state)
        HStack(spacing: 8) {
            // Before the mic is up (and after it has died) neither circle can do
            // anything: nothing has been heard, so ✓ is disabled and ✕ has nothing to
            // discard. The one useful control is out. Founder, 22 Aug: "`Cancel`
            // appears only during `Connecting…`".
            if offered.contains(.cancel) {
                Button(action: close) {
                    Text(VoiceChrome.label(for: .cancel, lang))
                        .font(CodepetTheme.inter(CodepetType.subheadline))
                        .foregroundStyle(CodepetTheme.mutedText)
                        .padding(.horizontal, 8)
                        .frame(height: controlDiameter)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(VoiceChrome.label(for: .cancel, lang))
                .accessibilityLabel(VoiceChrome.label(for: .cancel, lang))
            }
            if offered.contains(.discard) {
                circleButton(symbol: "xmark", label: VoiceChrome.label(for: .discard, lang),
                             filled: false, hotkey: .discard, action: discardTurn)
            }
            if offered.contains(.send) {
                circleButton(symbol: "checkmark", label: VoiceChrome.label(for: .send, lang),
                             filled: true, hotkey: .send, action: sendTurn)
            }
        }
    }

    /// **Whether a control — and the key on it — can do anything right now.**
    ///
    /// One expression for both, which is the point: ✓'s `.disabled` and ⌘⏎'s enablement
    /// were two separate things to get right, and a hotkey that fires while the button
    /// under it is greyed has nothing on screen to give it away. The rules themselves are
    /// `VoiceTurnFlow.canTakeTurn` and `VoiceChrome.controls(for:)`, reached through
    /// `VoiceHotkey.isEnabled` — see there for why `.discard` is gated on a different
    /// fact than `.send` and why `.exit` is gated on nothing.
    ///
    /// This replaced `turn.canSend(isBusy:)`, a one-line pass-through to the same
    /// `canTakeTurn` with no other consumer; keeping both would have been two names for
    /// one rule, and the hotkey would have read one of them while the button read the
    /// other.
    private func isEnabled(_ hotkey: VoiceHotkey) -> Bool {
        VoiceHotkey.isEnabled(hotkey, partial: turn.partial,
                              state: turn.session.state, isBusy: isBusy)
    }

    /// A turn already in flight, typed or spoken. `sendMessage` returns silently on
    /// either flag, so this is the difference between a disabled ✓ she can see and a
    /// tap that appears to do nothing.
    private var isBusy: Bool {
        companyStore.isStreaming || companyStore.isCompanionTyping
    }

    /// ✕ grey and outlined, ✓ blue and filled — founder, 22 Aug.
    ///
    /// **The hotkey and the disabled state come from one argument** (change 3, founder,
    /// 22 Aug: ⌘⏎ for ✓, ⌘⌫ for ✕). `hotkey` supplies the key equivalent AND, through
    /// `isEnabled`, whether the button is live — so ⌘⏎ cannot bypass the rule that greys
    /// ✓ while the transcript is empty or a turn is in flight. Two independent things
    /// then have to fail for a key to send nothing: SwiftUI does not fire a disabled
    /// Button's shortcut, and `VoiceTurnFlow.takeTurn` re-checks `canTakeTurn` at the
    /// send site anyway.
    private func circleButton(symbol: String, label: String, filled: Bool,
                              hotkey: VoiceHotkey,
                              action: @escaping () -> Void) -> some View {
        let enabled = isEnabled(hotkey)
        return Button(action: action) {
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
        .keyboardShortcut(hotkey.key, modifiers: hotkey.modifiers)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - The bottom-left slot

    /// **Spec §3's disclosure, and nothing else — the line is gone on 22 Aug otherwise.**
    ///
    /// This was `statusLine`: `~2 credits · on-device`, both of spec §2's two
    /// requirements Claude's composer does not have. The founder screenshotted it and
    /// asked for it removed. What survives, and why the credit count did not, is argued
    /// at `VoiceChrome.disclosure` — including why the off-device case is a privacy
    /// exception rather than an inconsistency, and why a failure suppresses it.
    ///
    /// **Unconditionally warning-coloured now, because there is only the warning case
    /// left.** The old ternary painted the on-device tag as `CodepetTokens.faint` grey
    /// chrome; with that branch gone, a `listener.isOnDevice` ternary here would be a
    /// second copy of the decision `VoiceChrome.disclosure` already made — and its grey
    /// arm would be unreachable.
    ///
    /// `.lineLimit(2)` and it is not slack: the escalated off-device sentence needs both
    /// lines at the dock's reading column, so it sits exactly on the limit. See
    /// `VoiceComposerTests.testTheOffDeviceDisclosureFitsTwoLinesInTheDock`, which is
    /// there because the default `.tail` truncation would cut the §3 disclosure
    /// mid-phrase with nothing on screen saying so.
    ///
    /// **This slot vanishing is what changed the composer's measured height** — 122pt to
    /// 99pt in the dock, re-measured 22 Aug. See
    /// `testTheComposersMeasuredHeightIsPinnedWithAndWithoutTheDisclosure`, which now pins
    /// both heights rather than one.
    @ViewBuilder private var disclosure: some View {
        if let text = VoiceChrome.disclosure(onDevice: listener.isOnDevice,
                                             failure: turn.failure, lang) {
            Text(text)
                .font(CodepetTheme.inter(CodepetType.footnote))
                .foregroundStyle(CodepetTheme.accentOrange)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Leaving, and the two taps

    /// Leaving voice mode, by the waveform toggle or by `Cancel`.
    ///
    /// **Not `.onDisappear`** — see `body`'s `.task` and `CopilotChatView`.
    private func close() {
        turn.leave(listener: listener, voice: voice)
        isActive = false
    }

    /// ✓: take the turn, then send it.
    private func sendTurn() {
        guard let toSend = turn.take(listener: listener, voice: voice, isBusy: isBusy)
        else { return }
        let language = lang
        // `convenesRoom` is left at its default false: the room is unreachable by
        // voice (spec §5) because a misheard sentence must never spend
        // `RoomOffer.credits`.
        //
        // Per-turn credit counting was removed 22 Aug along with the composer's credit
        // line — see spec §7 for the ordering knowledge this write site used to carry
        // (why a counter would belong here, inside the `Task`, after the `await`, if
        // one is ever reintroduced).
        Task {
            await companyStore.sendChat(toSend, language: language)
        }
    }

    /// ✕.
    private func discardTurn() {
        turn.discard(listener: listener)
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
    ///
    /// **`surface` is a parameter because `ChatSurface.defaultValue` is `.dock`.**
    /// Without it every render was the dock variant, and `cornerRadius`,
    /// `controlDiameter` and the card fill each have a `.twoMode` branch that no test
    /// had ever rendered.
    static func preview(state: VoiceState, partial: String,
                        failure: Error? = nil, onDevice: Bool = true,
                        surface: ChatSurface = .dock) -> some View {
        var turn = VoiceTurn()
        if state != .idle {
            turn.session.apply(.open)
            if state == .thinking || state == .speaking { turn.session.apply(.founderSentTurn) }
            if state == .speaking { turn.session.apply(.replyBegan) }
        }
        turn.partial = partial
        turn.failure = failure
        let listener = InertSpeechListening()
        listener.isOnDevice = onDevice
        return VoiceComposer(isActive: .constant(true),
                             turn: .constant(turn),
                             listener: listener,
                             voice: InertSpeakingVoice(),
                             accent: CodepetTheme.accentPurple)
            .environmentObject(previewStore)
            .environment(\.chatSurface, surface)
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
