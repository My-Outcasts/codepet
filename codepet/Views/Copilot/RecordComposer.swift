// codepet/Views/Copilot/RecordComposer.swift
import SwiftUI

/// **Record, in the composer** — spec §10, the second voice control, added 22 Aug.
///
/// Press and hold the mic in `ChatComposer` (or press ⌘D) and the composer grows in place
/// exactly as voice mode's does: the live transcript top-left in grey italic, a bar
/// waveform along the bottom, ✕ and ✓ bottom-right. Release stops capturing and the
/// transcript stays so it can be judged. **✓ puts the text into the composer's text field
/// as an editable draft. Nothing sends, and nothing is spoken back.**
///
/// **What this view cannot do, by construction rather than by discipline.** It takes no
/// `SpeakingVoice` and there is nothing in scope that could hand it one, so
/// `beginReply`/`enqueue`/`endOfReply`/`stopImmediately` are not reachable from this file
/// — spec §10's "`SpeakingVoice` never touched" is a compile-time property here. It also
/// takes no `CompanyStore` write path: ✓ hands its string up through `onDraft` and
/// `CopilotChatView` decides what happens to it, so `sendChat` is not reachable either.
/// **Record therefore spends no credits because there is no code path that could spend
/// one**, and the room stays unreachable (spec §5) for the same reason — it cannot send
/// at all, so it cannot convene anything.
///
/// **Why this is a sibling of `VoiceComposer` rather than a mode of it.** Every decision
/// the two share is already outside both views — `VoiceChrome.Line`'s precedence, the
/// control set, `VoiceWaveform.barHeights`, the §3 disclosure, the two metric constants
/// below — so what is duplicated here is layout, and layout is the one thing this suite
/// can measure on both surfaces and compare (see
/// `RecordComposerTests.testRecordAndVoiceModeMeasureTheSameHeight`). What would have been
/// duplicated the other way round is worse: threading an optional `voice` through
/// `VoiceComposer` puts `beginReply()` one nil-check away from a control whose defining
/// property is that it never speaks, and `VoiceComposer` is confirmed working on device
/// with its heights pinned.
///
/// **This view owns no capture state**, for `VoiceTurn`'s reason applied to `RecordTurn`:
/// the composer slot is rendered from inside `CopilotChatView`'s three-way `if/else`, and
/// a typed reply arriving while she dictates flips `chatMessages.isEmpty` under her.
/// `@State` here would be destroyed mid-sentence with nothing on screen saying so.
///
/// **The teardown is not here either.** `close()` runs on ✕/`Cancel`/Esc;
/// `CopilotChatView`'s `.onChange(of: recordMode)` and `.onDisappear` carry ⌘B and a mode
/// switch. A `.onDisappear` on *this* view would fire on a branch flip and on History
/// opening, stopping a microphone the next instance is about to keep using — the same
/// defect `VoiceComposer` records.
/// **The three ways `ChatComposer`'s mic button can start or stop a capture**, in one
/// value so the composer takes one optional rather than three.
///
/// Optional-and-nil-by-default at the call site, the additive rule `onVoiceMode`, `tier`
/// and `pins` all follow: `DeveloperWorkPane` and the preview host pass nothing and render
/// exactly as they do today.
///
/// **Three closures rather than one, because a press-and-hold and a keystroke are not the
/// same gesture** (spec §10: *"⌘D toggles; the mouse gesture holds"*). A `KeyEquivalent`
/// cannot be held down in SwiftUI, so the keyboard gets `toggle` — it starts, and the
/// stop half lives on `RecordComposer`'s own mic button, which is the only one of the two
/// surfaces on screen by then.
struct RecordControl {
    /// Mouse down on the mic — begin capturing. Fires repeatedly if she drags, so the
    /// receiver must be idempotent; `CopilotChatView.startRecord()` is.
    let press: () -> Void
    /// Mouse up — **release stops capturing** (spec §10). The transcript stays.
    let release: () -> Void
    /// ⌘D. Starts a capture; it cannot stop one, because by then this button is not on
    /// screen.
    let toggle: () -> Void
}

struct RecordComposer: View {

    /// Whether record is on. Owned by `CopilotChatView`, which swaps this view in for
    /// `ChatComposer`.
    @Binding var isActive: Bool
    /// The whole capture, owned by `CopilotChatView`. See `RecordTurn`.
    @Binding var turn: RecordTurn
    let listener: SpeechListening
    /// ⌘D's stop half, and the mic button's. Hoisted because `RecordTurn.endCapture` must
    /// also be reachable from the mouse gesture on `ChatComposer`, which is a different
    /// view — one funnel, so a release and a ⌘D cannot end a capture two different ways.
    var onStopCapture: () -> Void
    /// ✓. The string, trimmed. `CopilotChatView` merges it into `chatDraft` and collapses
    /// this surface — see `RecordFlow.merge`.
    var onDraft: (String) -> Void
    /// The companion's hue, for ✓ — handed down for `ChatComposer`'s reason: the composer
    /// does not get to decide whose product this is.
    var accent: Color = CodepetTheme.accentPurple

    @Environment(\.uiLanguage) private var lang
    @Environment(\.chatSurface) private var surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    // MARK: - Metrics

    /// **Borrowed from `VoiceComposer`, not restated.** Spec §10 asks for "the same
    /// chrome voice mode uses", and two constants that could disagree is how one surface
    /// ends up 6pt taller than the other with nothing saying which is right. The reasons
    /// for both numbers are on `VoiceComposer.transcriptHeight` and
    /// `.horizontalPadding`, and they apply here unchanged: a slot that reflowed as the
    /// transcript grew would move ✕ and ✓ out from under her pointer mid-sentence.
    private var cornerRadius: CGFloat { surface == .dock ? 16 : 12 }
    private var controlDiameter: CGFloat { surface == .dock ? 28 : 26 }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcriptSlot
            bottomRow
            disclosure
        }
        .padding(.horizontal, VoiceComposer.horizontalPadding)
        .padding(.top, 11).padding(.bottom, 10)
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
        // that was already writing through, and `openMic` is guarded by `turn.micOpened`.
        //
        // The mic is opened HERE rather than in `startRecord()` for the founder-visible
        // reason voice mode has: `listener.start()` is a ~200ms synchronous engine
        // spin-up, and the composer should be on screen reading `Connecting…` while it
        // happens.
        .task {
            RecordTurn.wire($turn, listener: listener)
            turn.openMic(listener)
        }
    }

    // MARK: - The text slot

    /// Top-left, reading like a draft — which here is literal: this text is about to
    /// become the draft. Which of three sources wins is `RecordChrome.line`'s decision,
    /// not this view's, because the precedence's failure is silent — a founder told the
    /// mic is live and dead in the same frame.
    private var transcriptSlot: some View {
        let line = RecordChrome.line(phase: turn.phase, partial: turn.partial,
                                     failure: turn.failure, lang)
        return Text(line.text)
            .font(CodepetTheme.inter(CodepetType.body))
            .italic(line.kind == .transcript)
            .foregroundStyle(line.kind == .failure ? CodepetTheme.accentOrange
                                                   : CodepetTheme.mutedText)
            .lineLimit(2)
            .truncationMode(.head)   // the newest words are the ones she is checking
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: VoiceComposer.transcriptHeight, alignment: .topLeading)
    }

    // MARK: - The waveform and the controls

    /// Waveform centred, the mic toggle leading and the controls trailing — a `ZStack`
    /// for `VoiceComposer`'s reason: in one `HStack` the bars would be centred in what is
    /// left over rather than in the composer.
    private var bottomRow: some View {
        ZStack {
            waveform
            HStack(spacing: 0) {
                micToggle
                Spacer(minLength: 0)
                controls
            }
        }
    }

    /// **The mic, lit — the glyph she pressed to get in, and ⌘D's stop half.**
    ///
    /// Live only while `.capturing`, because that is the only phase with a capture to
    /// stop. Once stopped it is disabled rather than quietly becoming a second exit: ✕ is
    /// the exit, and one control with two meanings is the ambiguity the takeover needed
    /// captions to paper over. `RecordChrome.toggleLabel` is what says which of the two
    /// it currently is, so a screen reader gets the same answer the tooltip does.
    private var micToggle: some View {
        let enabled = RecordHotkey.isEnabled(.toggle, partial: turn.partial, phase: turn.phase)
        return Button(action: onStopCapture) {
            Image(systemName: "mic.fill")
                .font(.system(size: surface == .dock ? 14 : 11, weight: .medium))
                .foregroundStyle(enabled ? accent : CodepetTheme.mutedText)
                .frame(width: controlDiameter, height: controlDiameter)
                .background(Circle().fill((enabled ? accent : CodepetTheme.mutedText)
                                            .opacity(0.15)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(RecordHotkey.toggle.key, modifiers: RecordHotkey.toggle.modifiers)
        .help(RecordChrome.toggleLabel(for: turn.phase, lang))
        .accessibilityLabel(RecordChrome.toggleLabel(for: turn.phase, lang))
    }

    /// The bar waveform. Heights come from `VoiceWaveform`, which is pure and asserted.
    ///
    /// **Flat in every phase but `.capturing`**, and that is a disclosure rather than a
    /// nicety: the microphone really is off once she has released (`RecordTurn.endCapture`
    /// calls `listener.stop()`), so bars that kept moving would be claiming the opposite
    /// of the one fact spec §3 is about.
    private var waveform: some View {
        let showsLevel = turn.phase == .capturing
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

    /// **The only two things that take or drop a capture**, as two small circles, the
    /// same pair voice mode draws.
    ///
    /// ✓ *disables* rather than disappearing: a control that comes and goes under her
    /// pointer while she is talking is the same defect the fixed-height transcript slot
    /// exists to avoid. Which controls a phase offers is `RecordChrome.controls`, not an
    /// `if` here — a pure phase→controls mapping hidden in a view is what
    /// `VoiceChrome.controls` was extracted out of.
    @ViewBuilder private var controls: some View {
        let offered = RecordChrome.controls(for: turn.phase, partial: turn.partial)
        HStack(spacing: 8) {
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
                .keyboardShortcut(RecordHotkey.exit.key, modifiers: RecordHotkey.exit.modifiers)
                .help(VoiceChrome.label(for: .cancel, lang))
                .accessibilityLabel(VoiceChrome.label(for: .cancel, lang))
            }
            if offered.contains(.discard) {
                // **✕ is also the exit here, which is why Esc is on it.** In voice mode ✕
                // discards a sentence and keeps listening, so it needed its own ⌘⌫ and
                // Esc belonged to the waveform toggle. Record's microphone is already off
                // by the time ✕ is worth pressing, so discarding and leaving are one
                // action — and `RecordHotkey` carries no ⌘⌫ rather than two keys for it.
                circleButton(symbol: "xmark", label: VoiceChrome.label(for: .discard, lang),
                             filled: false, hotkey: .exit, action: close)
            }
            if offered.contains(.send) {
                circleButton(symbol: "checkmark", label: VoiceChrome.label(for: .send, lang),
                             filled: true, hotkey: .send, action: takeDraft)
            }
        }
    }

    /// ✕ grey and outlined, ✓ blue and filled.
    ///
    /// **The hotkey and the disabled state come from one argument**, for
    /// `VoiceComposer.circleButton`'s reason: a key gated by one expression and a button
    /// greyed by another is exactly the drift `RecordHotkey.isEnabled` exists to prevent.
    private func circleButton(symbol: String, label: String, filled: Bool,
                              hotkey: RecordHotkey,
                              action: @escaping () -> Void) -> some View {
        let enabled = RecordHotkey.isEnabled(hotkey, partial: turn.partial, phase: turn.phase)
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

    /// **Spec §3's disclosure, unchanged and for the same reason** (spec §10): recognition
    /// is recognition. English is on-device, Vietnamese goes to Apple's servers because no
    /// `vi-VN` asset exists, and a founder dictating a confidential brief has exactly the
    /// same question as one speaking it.
    ///
    /// `VoiceChrome.disclosure` is reached rather than reimplemented, so both the 22 Aug
    /// amendment (nothing at all when on-device, the full sentence in warning colour when
    /// not) and the failure precedence apply here without a second copy that could
    /// disagree — and record can reach a failure the same way voice mode can, since
    /// `RecognitionWatchdog` fires on this listener too.
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

    /// ✕, `Cancel`, Esc. **Nothing is written anywhere** — that is what ✕ means here.
    private func close() {
        turn.leave(listener)
        isActive = false
    }

    /// ✓. Hands the trimmed text up and collapses; the merge into `chatDraft` and the
    /// caret are `CopilotChatView`'s, because that is where the store and the focus live.
    ///
    /// **There is no `sendChat` on this path and no `Task` around it.** ✓ in voice mode
    /// ends with `await companyStore.sendChat`; ✓ here ends with a string. That is the
    /// whole difference between the two controls, and it is one line in each file.
    private func takeDraft() {
        guard let text = turn.take() else { return }
        turn.leave(listener)
        onDraft(text)
        isActive = false
    }
}

#if DEBUG

// MARK: - Preview / measurement

extension RecordComposer {
    /// Seeded directly, because `ImageRenderer` fires neither `.onAppear` nor `.task`: a
    /// host that opened the capture in a lifecycle hook would measure a connecting
    /// composer and every assertion against it would be vacuous.
    ///
    /// **`surface` is a parameter because `ChatSurface.defaultValue` is `.dock`.** Without
    /// it every render is the dock variant, and `cornerRadius` and `controlDiameter` each
    /// have a `.twoMode` branch.
    ///
    /// Reuses `InertSpeechListening` from `VoiceComposer`'s previews: it does nothing at
    /// all, which is the requirement — **no test may start an audio engine or construct an
    /// `SFSpeechRecognizer`.**
    static func preview(phase: RecordPhase, partial: String,
                        failure: Error? = nil, onDevice: Bool = true,
                        surface: ChatSurface = .dock) -> some View {
        var turn = RecordTurn()
        turn.phase = phase
        turn.partial = partial
        turn.failure = failure
        let listener = InertSpeechListening()
        listener.isOnDevice = onDevice
        return RecordComposer(isActive: .constant(true),
                              turn: .constant(turn),
                              listener: listener,
                              onStopCapture: {},
                              onDraft: { _ in },
                              accent: CodepetTheme.accentPurple)
            .environment(\.chatSurface, surface)
    }
}

#Preview("RecordComposer (capturing, 520pt)") {
    RecordComposer.preview(phase: .capturing, partial: "add pricing for the beta")
        .frame(width: 520)
        .padding()
}

#Preview("RecordComposer (held, nothing heard)") {
    RecordComposer.preview(phase: .held, partial: "")
        .frame(width: 520)
        .padding()
}
#endif
