import SwiftUI

/// The chat composer — one reusable input surface used in BOTH the empty hero
/// and the docked active conversation. Owns no state: draft/mode live in the
/// parent (`CopilotChatView`) so the same value drives both placements.
///
/// Two controls, not four — spec `2026-08-21-composer-controls-design.md`.
/// `departmentControl` collapses all eight departments into one button (it replaced
/// three chips, a `•••` overflow, and a fourth chip that appeared only when the
/// selection came from that overflow), and `plusMenu` is the capability door: what
/// this turn gets to see, and how hard it should work.
///
/// **Wired, 22 Aug.** Pins reach the model through `ChatContext.compose(pinned:)` and
/// attachments through `CompanyChatRequest.attachments` — the last hop is
/// `CopilotChatView.send()`, which captures both before it clears the pills. The
/// `🌐 Web search` row is present at last, and it is honest for a reason worth
/// recording: it does not set a field on the request. Nothing on the wire reads one.
/// It toggles the `web-research` SKILL, which rides `enabled_skills` (already there,
/// already read) and is what `companyChat.ts` actually gates `WEB_SEARCH_TOOL` on.
///
/// The mode control still shapes the outgoing message via `ChatMode` (no backend
/// mode exists), and it is dock-only — `Ask` and `Developer` are places in the rail.
struct ChatComposer: View {
    @Binding var draft: String
    @Binding var mode: ChatMode
    var canSend: Bool
    var focus: FocusState<Bool>.Binding
    var placeholder: String
    var quickActions: [QuickAction]
    var accent: Color
    var accent2: Color
    var isBusy: Bool
    /// Whether the composer carries the departments control **at rest**.
    ///
    /// False on the two-mode hero, where `DepartmentRoster` sits directly above it:
    /// eight portraits are a better picker than one button, and the roster is where
    /// the founder LEARNS the cast (two-mode §4 puts it on the first screen).
    ///
    /// **It no longer means "hidden".** The original reason for hiding was that the
    /// chip row offered "the same three departments" without pets, so the roster was
    /// strictly better — both halves of that are false of `departmentControl`, which
    /// reaches all eight and carries the pet when armed. So an ARMED department is
    /// drawn here regardless of this flag: without that, picking from the roster lit
    /// up a roster chip and left the composer showing nothing, which is precisely the
    /// defect the retired promoted chip existed to patch. It also matters past the
    /// first screen — the roster is replaced by the transcript on send, and this
    /// control is the only thing that carries the selection forward.
    var showsDeptChips: Bool = true
    /// The approval tier, when the surface has one. Optional and nil by default, so
    /// the dock and every existing call site render exactly what they rendered
    /// before — the same additive rule `ChatSurface` follows.
    var tier: Binding<ApprovalTier>? = nil
    /// Which model and how much thinking the NEXT turn gets, when Codepet is running on the
    /// founder's own Claude plan. Optional and nil-by-default like `tier`, so every caller
    /// that does not pass it renders the composer it rendered before — and so the control is
    /// simply absent when the turn is going to the Cloud Function, where the founder has no
    /// say over the model anyway.
    var claudeModel: Binding<ClaudeCodeModel>? = nil
    var claudeEffort: Binding<ClaudeCodeEffort>? = nil
    /// What the founder pinned or attached for this message, when the surface offers
    /// it. Optional and nil by default — same additive rule as `tier`, so
    /// `DeveloperWorkPane` (whose context is its branch and its folder, not a
    /// marketing deliverable) passes nothing and renders exactly as before.
    var pins: Binding<[ContextPin]>? = nil
    var attachments: Binding<[ChatAttachment]>? = nil
    @Binding var selectedDept: Department?
    /// The department the router guessed from the draft, rendered tentatively. Distinct from
    /// `selectedDept` on purpose: an explicit pick must never be silently overwritten, and a
    /// guess must never look like a choice. Shown only when `selectedDept == nil`.
    ///
    /// One value, not three parallel optionals (`suggestedDept`/`suggestionTier`/
    /// `suggestionMatched`) — `DepartmentRouter.Suggestion` already bundles `deptKey`, `tier`
    /// and `matched`, so a missing tier on a present guess is impossible rather than papered
    /// over with `?? .topical`.
    var suggestion: DepartmentRouter.Suggestion?
    /// The founder refusing the guess. Clears it for the current draft; the owner decides how
    /// long the refusal holds.
    var onDismissSuggestion: () -> Void = {}
    var onSend: () -> Void
    var onQuickAction: (String) -> Void
    /// Convene the Virtual Company on the current draft. Defaulted so main's shell,
    /// which still reaches the room through its `.plan` pill, passes nothing.
    var onConveneRoom: () -> Void = {}
    /// Enter voice mode. `nil` by default, so `DeveloperWorkPane` and every existing
    /// call site render exactly as they do today — the same additive rule `tier`
    /// and `pins` follow.
    var onVoiceMode: (() -> Void)? = nil
    /// Whether voice mode can run, **computed by the owner and handed down**. `nil`
    /// means this surface has no voice mode at all, and pairs with `onVoiceMode` being
    /// nil — `voiceButton` needs both.
    ///
    /// Not read here from `VoicePermission.current`, which is where it used to come
    /// from: that constructs an `SFSpeechRecognizer` (an XPC handshake with the speech
    /// daemon) and this `body` is invalidated by every streamed token, since
    /// `companyStore` is an `@EnvironmentObject` and `chatMessages[i].text` is filled
    /// in place delta by delta. A 400-word reply built and tore down several hundred
    /// recognisers on the main actor while a stream was being parsed — and put an
    /// `SFSpeechRecognizer` one `ImageRenderer` test away from a headless XCTest host,
    /// which is the class of hazard that took six SSE tests down.
    ///
    /// It also has to be the owner's copy for a second reason: the owner is what
    /// *requests* the grants, so a refusal is only visible on this button if the
    /// answer comes from there. See `CopilotChatView.voiceAvailability`.
    var voiceAvailability: VoiceAvailability? = nil
    /// Start a capture — spec §10's second control. `nil` by default, so
    /// `DeveloperWorkPane` and the preview host render exactly as they do today: the same
    /// additive rule `onVoiceMode`, `tier` and `pins` follow. `micButton` needs this and
    /// `voiceAvailability` both, exactly as `voiceButton` does.
    var onRecord: RecordControl? = nil
    /// **Which voice control is already live, if either** — spec §10: *"The two controls
    /// must never run at once."*
    ///
    /// Handed down rather than inferred, because the fact this has to carry is not "the
    /// other surface is on screen". Both surfaces replace this one, so from here they are
    /// always invisible; the window that matters is `startVoiceMode()`'s two TCC dialogs,
    /// during which this composer is still up with a live mic button and voice mode is
    /// *about* to own the microphone. See `VoicePermission.canEnter` and
    /// `CopilotChatView.liveVoiceControl`, which reports a control as live from the moment
    /// its request starts.
    var liveVoiceControl: VoiceControlKind? = nil

    /// Why the last pick was turned away, or nil. Local `@State` because it is
    /// ephemeral chrome with no owner outside this control, and because the rule it
    /// reports (`AttachmentBudget`) is pure and tested on its own — what lives here is
    /// only whether a sentence is on screen.
    ///
    /// Cleared by the next pick (a clean pick assigns nil) or by its own ✕. It does not
    /// clear on send: a refusal is about a file that never made it in, so the send that
    /// follows is not an answer to it.
    @State private var attachNotice: String?

    @EnvironmentObject private var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.chatSurface) private var surface
    @Environment(\.colorScheme) private var scheme

    private var restShadow: CodepetTheme.Shadow { CodepetTokens.shadowS(scheme == .dark) }

    var body: some View {
        switch surface {
        case .dock:    dockBody
        case .twoMode: twoModeBody
        }
    }

    /// The dock: chips on their own row (380pt cannot hold chips + controls), and
    /// the mode pill, which still drives `ChatMode` in main's shell.
    private var dockBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            pillRow

            ComposerField(placeholder: placeholder, text: $draft, focus: focus, onSend: onSend)

            // The dock keeps the active-project chip on its own row now that the
            // department chips it shared with are gone.
            if let link = companyStore.activeProjectLink {
                HStack(spacing: 6) { projectChip(link) }
            }

            HStack(spacing: 8) {
                departmentControl
                plusMenu
                micButton
                voiceButton
                modeMenu
                Spacer()
                sendButton
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CodepetTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(focus.wrappedValue ? 0.9 : 0.5),
                        lineWidth: focus.wrappedValue ? 1.5 : 1.2)
        )
        .codepetShadow(CodepetTheme.floatingShadow)
        .shadow(color: (focus.wrappedValue && !reduceTransparency) ? accent.opacity(0.28) : .clear, radius: 18)
        .opacity(isBusy ? 0.72 : 1.0)
    }

    /// The prototype's composer: input, then ONE control row — chips, `+`, send.
    /// No mode pill: `Ask` and `Developer` are places in the rail now, and a pill
    /// that re-asks the question the rail already answered is the exact confusion
    /// the two-mode design set out to end.
    ///
    /// The border is neutral at rest and accent only on focus. An always-accent
    /// outline (the dock's) makes the composer the loudest thing on a pane it no
    /// longer has to compete for attention in.
    private var twoModeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            pillRow

            ComposerField(placeholder: placeholder, text: $draft, focus: focus,
                          floor: ComposerMetrics.paneMinTextHeight, onSend: onSend)

            HStack(spacing: 7) {
                // `suggestion != nil` is the third condition and it carries the rail: a guess
                // is never made without the chip that shows it. The two-mode hero keeps its
                // clean rest state — no bare "Departments" button while nothing is picked or
                // guessed — but the moment the router has an opinion, the dashed chip appears
                // to state it. Suppressing the guess there instead (the earlier design) meant
                // the FIRST message of every new conversation silently got no pet.
                if showsDeptChips || selectedDept != nil || suggestion != nil { departmentControl }
                plusMenu
                micButton
                voiceButton
                // "The tier lives in the composer, beside `+`" (§8.2) — the session
                // bar carries facts set once, the composer carries controls for the
                // NEXT instruction, and how much rope the next instruction gets is
                // exactly that.
                if let tier { tierMenu(tier) }
                // Beside the tier for the same reason the tier is here: the session bar
                // carries facts set once, the composer carries controls for the NEXT
                // instruction — and which model answers it is exactly that.
                if let claudeModel, let claudeEffort {
                    modelMenu(claudeModel, claudeEffort)
                }
                Spacer(minLength: 8)
                sendButton
            }
        }
        .padding(.horizontal, 14).padding(.top, 11).padding(.bottom, 10)
        // The house card: `cardRaised` + `cardEdge` at radius 12 with `shadowS`,
        // the same object Tasks and Roadmap are built from. The edge carries the
        // accent ramp in both states — 0.35 at rest, 0.9 focused. An always-accent
        // outline at full strength did make the composer the loudest thing on the
        // pane, which is why this used to be cardEdge at rest; a third of the way up
        // on flat ground is the opposite problem, since cardEdge on cream is
        // invisible without an ambient wash behind it.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodepetTokens.cardRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // Both states are the same ramp at two opacities, not two different
                // treatments — one stroke definition cannot drift into reading as two
                // controls. Companion-hued: `accent` is `companionColor`, so brand
                // purple must not be hard-coded here.
                //
                // At rest this used to be `cardEdge`, which on cream is a hairline of
                // almost no value. The ambient wash had been doing that separating; with
                // flat ground the edge has to carry it.
                .stroke(CodepetTheme.ramp(accent, accent2)
                            .opacity(focus.wrappedValue ? 0.9 : 0.35),
                        lineWidth: 1)
        )
        .shadow(color: restShadow.color, radius: restShadow.radius, x: restShadow.x, y: restShadow.y)
        .shadow(color: (focus.wrappedValue && !reduceTransparency) ? accent.opacity(0.28) : .clear, radius: 16)
        .opacity(isBusy ? 0.62 : 1.0)
    }

    /// What the founder pinned or attached, above the field — Claude's attachment
    /// chips in Codepet's nouns.
    ///
    /// **Pins and attachments share one row and one cap**, because to the founder
    /// they are the same gesture: *this goes with my next message*. Two rows with
    /// two ceilings would be an implementation detail leaking into the UI.
    @ViewBuilder private var pillRow: some View {
        let pinList = pins?.wrappedValue ?? []
        let attList = attachments?.wrappedValue ?? []
        if !pinList.isEmpty || !attList.isEmpty || attachNotice != nil {
            VStack(alignment: .leading, spacing: 5) {
                if !pinList.isEmpty || !attList.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attList) { att in
                            pill(icon: att.icon, title: att.filename, gloss: att.gloss) {
                                attachments?.wrappedValue = ChatAttachment.removing(att, from: attList)
                            }
                        }
                        ForEach(pinList) { pin in
                            pill(icon: pin.icon, title: pin.title, gloss: pin.gloss) {
                                pins?.wrappedValue = ContextPin.removing(pin, from: pinList)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if let attachNotice { noticeRow(attachNotice) }
            }
        }
    }

    /// **A refused file has to say so here, in the composer, and this is why.**
    ///
    /// The cap it reports is on total base64 bytes, and the thing it prevents is a bare
    /// 413 from Cloud Run: the request never reaches `handleCompanyChat`, so there is no
    /// log line, no entry in the backend's drop table, and nothing anyone could look up
    /// afterwards. If the refusal were silent too, an oversized screenshot would be
    /// indistinguishable from the model choosing not to mention the picture.
    ///
    /// Outside the `Menu`, deliberately. A `Menu` flattens whatever it is handed to
    /// (title, image) and discards layout modifiers, so a two-line notice inside
    /// `plusMenu` would render as its first string and nothing else.
    private func noticeRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 9))
            Text(text)
                .font(CodepetTheme.inter(CodepetType.subheadline))
                .fixedSize(horizontal: false, vertical: true)
            Button { attachNotice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
            .help(lang == .vi ? "Bỏ qua" : "Dismiss")
            Spacer(minLength: 0)
        }
        .foregroundColor(CodepetTheme.mutedText)
    }

    private func pill(icon: String, title: String, gloss: String,
                      remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(title)
                .font(CodepetTheme.inter(CodepetType.subheadline, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Text(gloss)
                .font(CodepetTheme.inter(9, weight: .medium))
                .foregroundColor(CodepetTokens.faint)
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .foregroundColor(CodepetTheme.mutedText)
        .padding(.leading, 8).padding(.trailing, 4).frame(height: 22)
        .background(Capsule().fill(CodepetTokens.well))
        .overlay(Capsule().stroke(CodepetTokens.cardEdge))
        .frame(maxWidth: 210)
    }

    /// Departments, collapsed — spec §4.
    ///
    /// This replaces a row of three chips (two in the dock), a `•••` overflow, and a
    /// fourth chip that appeared only when the selection came from that overflow.
    /// The promoted chip existed because a choice made inside a menu was invisible;
    /// an armed BUTTON is visible, so the patch stops being needed.
    ///
    /// **One capsule, two hit targets.** The label opens the menu, the `✕` clears.
    /// A `✕` that only decorated would be worse than none, and SwiftUI gives a
    /// `Menu` its whole label as one target — hence an `HStack` of two controls
    /// sharing one background rather than a `Menu` with an overlay.
    private var departmentControl: some View {
        let armed = selectedDept
        // A guess only renders when the founder has not chosen. `shown` drives the label, the
        // sprite and the ✕; `armed` alone drives the SOLID treatment, so a suggestion and a
        // pick can never look alike.
        let activeSuggestion = armed == nil ? suggestion : nil
        let suggestedDept = activeSuggestion.flatMap { DepartmentCatalog.find($0.deptKey) }
        let shown = armed ?? suggestedDept
        return HStack(spacing: 0) {
            Menu {
                // Two acts, one row — the same rule the `✕` already follows: with nothing
                // armed, this row is refusing a GUESS (`onDismissSuggestion`), not picking
                // "Anyone" over a pick that already isn't there. Without this, clicking the
                // already-checked-looking "Anyone" row while a suggestion is showing did
                // nothing at all, and the guess survived a founder explicitly rejecting it.
                //
                // The `shown` guard is the other half, and it is why this row branches on
                // `shown` exactly as its own checkmark two lines below does. The `✕` gets the
                // guard for free — it is only BUILT when `shown != nil` — but this row is
                // always present, so branching on `armed` alone made an idle poke at the
                // already-checked "Anyone" refuse a guess that was never there: it set
                // `suggestionDismissed` and nilled `lastActedDeptKey`, killing carry-over and
                // suppressing routing for the rest of the draft. With nothing shown, "Anyone"
                // is already the answer and clicking it is a no-op.
                Button {
                    guard shown != nil else { return }
                    if armed == nil { onDismissSuggestion() } else { selectedDept = nil }
                } label: {
                    if shown == nil {
                        Label(DepartmentMenu.anyoneLabel(lang), systemImage: "checkmark")
                    } else {
                        Text(DepartmentMenu.anyoneLabel(lang))
                    }
                }
                Divider()
                ForEach(DepartmentMenu.rosterOrder) { dep in
                    Button { selectedDept = dep } label: { deptRow(dep, current: shown) }
                }
            } label: {
                HStack(spacing: 5) {
                    // `PetMenuIcon`, not `CharacterImage`. A `Menu`'s LABEL is
                    // flattened to `(title, image)` exactly like its rows are, and
                    // the image is sized from `NSImage.size` — so CharacterImage's
                    // explicit .frame(16) was discarded and the raw asset rendered
                    // at native size, swallowing the whole composer. The roster
                    // chips above use CharacterImage and are fine: they are plain
                    // Buttons, not Menu labels.
                    if let dep = shown,
                       let pet = DepartmentMenu.pet(for: dep),
                       let sprite = PetMenuIcon.image(pet) {
                        sprite
                    }
                    Text(shown.map { DepartmentMenu.armedLabel($0) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        // Same string as a pick, dimmed. Accepting a suggestion must change
                        // nothing on screen except the chip firming up — a suggestion that
                        // read differently would look like a second feature.
                        .foregroundColor(shown.map { $0.accent.opacity(armed == nil ? 0.75 : 1.0) }
                                         ?? CodepetTheme.bodyText)
                        .lineLimit(1)
                    if shown == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, shown == nil ? 10 : 6)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if let dep = shown {
                Button {
                    if armed == nil { onDismissSuggestion() } else { selectedDept = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(dep.accent)
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The `✕` dismisses a guess or clears a pick — two different acts, and the
                // tooltip has to say which. The innermost `.help()` wins over the capsule's,
                // so without this ternary the founder hovering the `✕` on a suggestion (the
                // control they reach for exactly when the guess looks wrong) read "Clear the
                // department" — a description of the OTHER act. The ternary makes it say
                // "Dismiss this suggestion". It does not restore the reason the pet was
                // suggested: that sentence lives on the capsule's own `.help` below, and
                // hovering the `✕` still shadows it.
                .help(armed == nil ? DepartmentMenu.dismissSuggestionHelp(lang)
                                    : DepartmentMenu.clearHelp(lang))
            }
        }
        // The armed treatment is the retired chip's treatment, unchanged. The suggested
        // treatment is the same two values weakened, and a DASHED stroke — the one visual
        // difference, carrying the whole "not yet real" meaning.
        .background(Capsule().fill(shown.map { $0.accent.opacity(armed == nil ? 0.07 : 0.15) }
                                   ?? CodepetTheme.surface))
        .overlay(
            Capsule().strokeBorder(
                shown?.accent ?? CodepetTheme.hairline,
                // `suggestedDept` alone is the whole dashed test: it is derived from
                // `activeSuggestion`, which is already nil whenever `armed != nil` (see its
                // definition above). So "a guess is showing" and "nothing is armed" are the
                // same condition here, and writing the second one out again would only
                // suggest they could disagree.
                style: suggestedDept != nil
                    ? StrokeStyle(lineWidth: 1, dash: [3, 2])
                    : StrokeStyle(lineWidth: 1)
            )
        )
        .hoverAffordance(Capsule(), accent: shown?.accent ?? CodepetTheme.accentPurple)
        .help(activeSuggestion.flatMap { s in
            suggestedDept.map { dep in
                DepartmentSuggestionLabel.help(tier: s.tier,
                                               matched: s.matched,
                                               pet: DepartmentMenu.pet(for: dep),
                                               department: dep, lang: lang)
            }
        } ?? "")
    }

    /// One menu row: checkmark when armed, else the pet's sprite, then
    /// `Nova · Marketing`.
    ///
    /// **The risk in spec §4 landed, and this is the fix.** `Image("char-crash")` in
    /// a menu icon slot renders the asset at its NATIVE pixel size — on screen the
    /// menu became a vertical slideshow of full-screen pixel faces, one per row.
    /// `PetMenuIcon` hands AppKit an `NSImage` whose `size` is already 16pt, which is
    /// the only sizing input a menu item reads; a SwiftUI `.frame()` here is dropped
    /// because the label is flattened to `(title, image)` rather than laid out.
    ///
    /// A missing sprite falls back to the text alone — still cast-signed, which is
    /// the part that matters. It does NOT fall back to a custom popover; that shape
    /// was considered and rejected 21 Aug for costing its own keyboard and dismiss
    /// handling.
    /// `current` is the EFFECTIVE department — a pick, or the guess standing in for one — not
    /// `selectedDept`. Reading the selection here would open the menu over a suggested chip
    /// saying "Anyone — Codepet routes it" while the chip beside it names a pet. Picking the
    /// already-checked suggested row is a normal pick: it writes `selectedDept`, which promotes
    /// the guess to a choice.
    @ViewBuilder private func deptRow(_ dep: Department,
                                      current: Department?) -> some View {
        let on = current?.key == dep.key
        let title = DepartmentMenu.rowTitle(dep)
        if on {
            Label(title, systemImage: "checkmark")
        } else if let pet = DepartmentMenu.pet(for: dep),
                  let sprite = PetMenuIcon.image(pet) {
            Label { Text(title) } icon: { sprite }
        } else {
            Text(title)
        }
    }

    /// The active coding-agent project — a quiet, always-visible reminder of which
    /// folder the agent will touch. Tap goes to the Environment link surface. Lifted
    /// out of the retired `deptChips` unchanged.
    private func projectChip(_ link: ProjectLink) -> some View {
        Button { companyStore.select(.environment) } label: {
            HStack(spacing: 4) {
                Image(systemName: link.isGitRepo ? "arrow.triangle.branch" : "folder")
                    .font(.system(size: 9))
                Text(Project.nameFromPath(link.path))
                    .font(CodepetTheme.inter(11, weight: .medium)).lineLimit(1)
            }
            .foregroundColor(CodepetTheme.mutedText)
            .padding(.horizontal, 8).frame(height: 26)
            .overlay(Capsule().stroke(CodepetTheme.hairline))
            .hoverAffordance(Capsule())
        }
        .buttonStyle(.plain).fixedSize()
        .help(link.path)
    }

    /// How much rope, per session.
    ///
    /// Every tier is listed, including the one the app cannot yet keep the promise
    /// of — disabled, with the reason. Hiding `Ask me` would leave the founder
    /// comparing three tiers in the design against two on screen and drawing their
    /// own conclusion about which one they were given; showing it enabled would be
    /// worse, because selecting "every command prompts" and getting a run that
    /// prompts for nothing is the most dangerous direction this control can be wrong in.
    /// Model + effort, in one control.
    ///
    /// Two levels rather than one flat list: the current generation and Auto sit at the top
    /// where a founder picks from them daily, and previous generations go behind a submenu
    /// because pinning one is a deliberate act, not a browse. Effort is its own submenu for
    /// the same reason — it is a second question, and flattening it into the model list
    /// would make a nine-item menu into a forty-item one.
    private func modelMenu(_ model: Binding<ClaudeCodeModel>,
                           _ effort: Binding<ClaudeCodeEffort>) -> some View {
        Menu {
            Button { model.wrappedValue = .inherit } label: {
                Label(ClaudeCodeModel.inherit.shortName + " — " + ClaudeCodeModel.inherit.note(lang),
                      systemImage: model.wrappedValue == .inherit ? "checkmark" : "")
            }
            Divider()
            ForEach(ClaudeCodeModel.current) { option in
                Button { model.wrappedValue = option } label: {
                    Label(option.shortName,
                          systemImage: model.wrappedValue == option ? "checkmark" : "")
                }
                .help(option.note(lang))
            }
            Divider()
            Menu(lang == .vi ? "Thế hệ trước" : "Older models") {
                ForEach(ClaudeCodeModel.older) { option in
                    Button { model.wrappedValue = option } label: {
                        Label(option.shortName,
                              systemImage: model.wrappedValue == option ? "checkmark" : "")
                    }
                }
            }
            Menu(lang == .vi ? "Mức suy nghĩ" : "Effort") {
                ForEach(ClaudeCodeEffort.choices) { level in
                    Button { effort.wrappedValue = level } label: {
                        Label(level.shortName,
                              systemImage: effort.wrappedValue == level ? "checkmark" : "")
                    }
                }
            }
        } label: {
            // ONE flat string, because a `Menu` flattens its label to `(title, image)` —
            // the trap `plusMenu` and `departmentControl` both document. An HStack here
            // rendered as the first Text and nothing else: no chevron of mine, no capsule,
            // and macOS drew its own indicator on the left instead.
            //
            // So the label is text, and the capsule and chevron are applied to the MENU
            // rather than inside it. That keeps one hit target, unlike `departmentControl`,
            // which needs two because its ✕ does something different.
            Text(labelText(model.wrappedValue, effort.wrappedValue))
                .font(CodepetTheme.inter(CodepetType.subheadline))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundColor(CodepetTheme.bodyText)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(CodepetTokens.well))
        .overlay(Capsule().stroke(CodepetTokens.cardEdge))
        .contentShape(Capsule())
        .help(lang == .vi ? "Model chạy trên gói Claude của bạn" : "The model your Claude plan answers with")
    }

    /// The composer label. Effort is appended only when it was actually chosen — printing
    /// "Auto" beside the model would add a word that says nothing on every turn.
    private func labelText(_ model: ClaudeCodeModel, _ effort: ClaudeCodeEffort) -> String {
        effort == .inherit ? model.shortName : "\(model.shortName) · \(effort.shortName)"
    }

    private func tierMenu(_ tier: Binding<ApprovalTier>) -> some View {
        Menu {
            ForEach(ApprovalTier.allCases) { option in
                Button { tier.wrappedValue = option } label: {
                    Label(option.label(lang)
                          + (option.isHonoured ? "" : (lang == .vi ? " — chưa có" : " — not yet")),
                          systemImage: option.icon)
                }
                .disabled(!option.isHonoured)
                .help(option.unavailableReason(lang) ?? option.detail(lang))
            }
            Divider()
            Text((lang == .vi ? "KHÔNG BAO GIỜ, Ở BẤT KỲ MỨC NÀO" : "NEVER, AT ANY TIER")
                 + "\n" + ApprovalTier.ceiling(lang))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tier.wrappedValue.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(tier.wrappedValue.label(lang))
                    .font(CodepetTheme.inter(CodepetType.subheadline))
            }
            .foregroundColor(tier.wrappedValue == .letItRun
                             ? CodepetTheme.accentOrange : CodepetTheme.bodyText)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(CodepetTokens.well))
            .overlay(Capsule().stroke(tier.wrappedValue == .letItRun
                                      ? CodepetTheme.accentOrange.opacity(0.45)
                                      : CodepetTokens.cardEdge))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tier.wrappedValue.detail(lang))
    }

    /// The capability door — spec §5. Two sections and a footer, every row captioned.
    ///
    /// `quickActions` no longer appears here. Those three are prompt STARTERS and
    /// they are already cards on the empty hero; the `+` was their second home, and a
    /// menu that mixes "say this for me" with "let the model see this" has no
    /// organising idea. `CopilotChatView` still builds them for the hero.
    ///
    /// **Wired (22 Aug).** Pinning and attaching now reach the model: pins through
    /// `ChatContext.compose(pinned:)`, attachments through `CompanyChatRequest.attachments`
    /// and `history[].attachments`. The `🌐 Web search` row is present because it can
    /// finally be honest — see its comment below, which is the whole argument.
    private var plusMenu: some View {
        Menu {
            Section(PlusMenu.bringInLabel(lang)) {
                if let atts = attachments {
                    let full = atts.wrappedValue.count >= ChatAttachment.max
                    Button {
                        let room = ChatAttachment.max - atts.wrappedValue.count
                        guard room > 0 else { return }
                        let picked = AttachmentPicker.pickAndEncode(limit: room)
                        // `AttachmentBudget` owns BOTH caps, so the file count and the
                        // total encoded size are decided in one pure place that a test
                        // can reach — and the store applies the same call at the wire.
                        let admission = AttachmentBudget.admit(picked.attachments,
                                                               to: atts.wrappedValue)
                        var next = atts.wrappedValue
                        for a in admission.accepted { next = ChatAttachment.adding(a, to: next) }
                        atts.wrappedValue = next
                        // Assigned every time, so a clean pick clears a stale refusal.
                        let lines = [AttachmentBudget.refusalMessage(admission, lang),
                                     AttachmentBudget.unsupportedMessage(picked.rejected, lang)]
                            .compactMap { $0 }
                        attachNotice = lines.isEmpty ? nil : lines.joined(separator: " ")
                    } label: {
                        menuRow(PlusMenu.attachLabel(lang),
                                full ? PlusMenu.attachFullDetail(lang)
                                     : PlusMenu.attachDetail(lang),
                                icon: "paperclip")
                    }
                    .disabled(full)
                }
                if let pins {
                    let full = pins.wrappedValue.count >= ContextPin.max
                    Menu {
                        ForEach(PlusMenu.recentLibrary(companyStore.company.library)) { d in
                            Button(d.title) {
                                pins.wrappedValue = ContextPin.adding(
                                    .deliverable(id: d.id, title: d.title),
                                    to: pins.wrappedValue)
                            }
                            .disabled(full)
                        }
                        Divider()
                        Button(PlusMenu.browseLibraryLabel(lang)) { companyStore.select(.library) }
                    } label: {
                        menuRow(PlusMenu.libraryLabel(lang), PlusMenu.libraryDetail(lang),
                                icon: "books.vertical")
                    }
                    Menu {
                        ForEach(PlusMenu.openTasks(companyStore.company.tasks)) { t in
                            Button(t.title) {
                                pins.wrappedValue = ContextPin.adding(
                                    .task(id: t.id, title: t.title), to: pins.wrappedValue)
                            }
                            .disabled(full)
                        }
                        Divider()
                        Button(PlusMenu.openRoadmapLabel(lang)) { companyStore.select(.roadmap) }
                    } label: {
                        menuRow(PlusMenu.taskLabel(lang), PlusMenu.taskDetail(lang), icon: "map")
                    }
                }
                // A toggle, not a picker: `memoryEnabled` is already the real gate on
                // the decisions block in `ChatContext.compose`.
                Button {
                    Task { await companyStore.updateFounderPrefs { $0.memoryEnabled.toggle() } }
                } label: {
                    menuRow(PlusMenu.knowsLabel(lang), PlusMenu.knowsDetail(lang),
                            icon: companyStore.company.founderPrefs.memoryEnabled
                                ? "checkmark" : "brain")
                }
                // **The 🌐 row, and it is a skill toggle rather than a request field.**
                //
                // The brief for this task specified `CompanyChatRequest.webSearch`. There is
                // nothing on the backend that reads it: `companyChat.ts` gates
                // `WEB_SEARCH_TOOL` on `skills.has("web-research")`, i.e. on the
                // `enabled_skills` array this request already carries. And because
                // `ChatRequestBody` is applied with an `as` cast, an unread `web_search` key
                // would be silently ignored — a toggle the founder flips that changes the
                // answer not at all, which is the exact thing the previous version of this
                // file removed the row to avoid. So this flips the real switch, and the tool
                // appears or disappears from the request because of it.
                Button {
                    Task { await companyStore.toggleTool(id: Toolkit.webResearchId) }
                } label: {
                    menuRow(PlusMenu.webSearchLabel(lang), PlusMenu.webSearchDetail(lang),
                            icon: companyStore.company.enabledTools.contains(Toolkit.webResearchId)
                                ? "checkmark" : "globe")
                }
                Menu {
                    Button(PlusMenu.changeFolderLabel(lang)) {
                        _ = ProjectLinker.pickAndLink(into: companyStore, language: lang)
                    }
                    Button(PlusMenu.openEnvironmentLabel(lang)) {
                        companyStore.select(.environment)
                    }
                } label: {
                    menuRow(PlusMenu.folderLabel(lang,
                                                 path: companyStore.activeProjectLink?.path),
                            PlusMenu.folderDetail(lang), icon: "folder")
                }
            }

            // Two-mode only, and this is a decision rather than an oversight: the
            // dock still reaches the room through its `.plan` mode pill
            // (`ChatMode.convenesRoom`), so a row here would be a SECOND door to one
            // ~10-credit act on the same surface. The pane has no mode pill, which is
            // why `RoomOffer` exists at all.
            if surface == .twoMode {
                Section(PlusMenu.goDeeperLabel(lang)) {
                    Button {
                        onConveneRoom()
                    } label: {
                        Label(RoomOffer.label(lang), systemImage: "person.3")
                    }
                    .disabled(!RoomOffer.canConvene(draft: draft) || isBusy)
                    .help(RoomOffer.detail(lang))
                    // The one visible caption, as a bare `Text` ITEM rather than part
                    // of a Button's label — `tierMenu` below already ships exactly
                    // this shape (a multi-line Text item under a Divider), so it is
                    // the one form in a menu known to render here. This is the row
                    // the founder had to ask about, and the only one where not
                    // knowing costs 10 credits.
                    Text(RoomOffer.detail(lang))
                }
            }

            Divider()
            Button {
                companyStore.select(.environment)
            } label: {
                menuRow(PlusMenu.setupLabel(lang), PlusMenu.setupDetail(lang), icon: "gearshape")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(width: surface == .dock ? 30 : 26,
                       height: surface == .dock ? 30 : 26)
                // Bare in the pane. Claude and Codex both draw their `+` as a glyph
                // with no container; ours was a fourth outlined pill in a row that
                // already had three, which is most of why the row read as heavy.
                .overlay(
                    surface == .dock
                        ? AnyView(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(CodepetTheme.hairline))
                        : nil
                )
                .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Voice mode — spec §1. `waveform` rather than `mic`: the mic glyph means
    /// dictation in both ChatGPT and Claude, and this is the other feature.
    ///
    /// **`isBusy` is in the gate, and `VoicePermission.canEnterVoiceMode` owns the
    /// rule.** Entering voice mode over a live typed turn cost the founder her first
    /// spoken question outright — see that function, where the sequence is written
    /// out. It is a one-line predicate whose failure is invisible on screen, so it is
    /// tested rather than inlined here.
    @ViewBuilder private var voiceButton: some View {
        if let onVoiceMode, let availability = voiceAvailability {
            Button(action: onVoiceMode) {
                Image(systemName: "waveform")
                    .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                    .frame(width: surface == .dock ? 30 : 26,
                           height: surface == .dock ? 30 : 26)
                    .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!VoicePermission.canEnter(.voiceMode, availability,
                                                isBusy: isBusy, live: liveVoiceControl))
            .help(VoicePermission.help(availability, lang) ?? (lang == .vi ? "Chế độ giọng nói" : "Voice mode"))
        }
    }

    /// **Record — spec §10's second control, and the glyph is the whole distinction.**
    /// `mic` means dictation in both ChatGPT and Claude; `waveform`, beside it, means the
    /// hands-free conversation. The founder named the waveform first and brought the mic
    /// back on 22 Aug after reading Claude's own tooltip: *"Press and hold to record ⌘D"*.
    ///
    /// **It is a `Button` for the keyboard and a gesture for the mouse.** ⌘D needs a
    /// control to hang off — a `.keyboardShortcut` on a bare `Image` does nothing — and
    /// press-and-hold needs the two edges a `Button` action does not give you. So the
    /// `Button` carries ⌘D and `RecordControl.toggle`, and a `DragGesture(minimumDistance:
    /// 0)` on top carries `press`/`release`.
    ///
    /// **`.simultaneousGesture`, and the click firing both paths is handled rather than
    /// hoped away.** A quick click can deliver the gesture's press and release *and* the
    /// `Button`'s action. That order is press → start, release → stop capturing, then the
    /// `Button` action → `startRecord()`, which is guarded on record not already being
    /// live and is therefore a no-op. (In practice this composer has been swapped out for
    /// `RecordComposer` by then and the action never arrives at all — both outcomes are
    /// safe, which is why the guard is not relying on which one happens.)
    ///
    /// **The gate is `VoicePermission.canEnter(.record, …)` and it deliberately ignores
    /// `isBusy`** — see `canEnterRecord`. A disabled SwiftUI view is not hit-tested, so
    /// the same expression that greys the glyph is what stops the gesture.
    @ViewBuilder private var micButton: some View {
        if let onRecord, let availability = voiceAvailability {
            let enabled = VoicePermission.canEnter(.record, availability,
                                                   isBusy: isBusy, live: liveVoiceControl)
            Button(action: onRecord.toggle) {
                Image(systemName: "mic")
                    .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                    .foregroundColor(CodepetTheme.bodyText)
                    .frame(width: surface == .dock ? 30 : 26,
                           height: surface == .dock ? 30 : 26)
                    .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .keyboardShortcut(RecordHotkey.toggle.key, modifiers: RecordHotkey.toggle.modifiers)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onRecord.press() }
                    .onEnded { _ in onRecord.release() }
            )
            .help(VoicePermission.help(availability, lang) ?? RecordChrome.micLabel(lang))
            .accessibilityLabel(RecordChrome.micLabel(lang))
        }
    }

    /// A menu row: icon, label, and the caption as a help tag only.
    ///
    /// **Captions on every row do not work, established on screen 21 Aug.** Two
    /// attempts failed: a `VStack` of two `Text`s rendered as one line, and a newline
    /// inside one `Text` fared no better. macOS flattens a `Button`'s label to
    /// `(title, image)` and keeps the first string. Captioning every row is an HTML
    /// pattern — ChatGPT can do it because its menu is a web page; `NSMenu` will not.
    ///
    /// So the founder's decision narrowed to the row that prompted it: only
    /// `Convene the room` carries a visible caption, and it does so as a bare `Text`
    /// ITEM rather than a label — see `plusMenu`. Everything else stands on its label,
    /// which is what a Mac menu does anyway. `.help()` stays because a tooltip costs
    /// nothing; it is not the answer, since nobody hovers a menu row before clicking.
    @ViewBuilder private func menuRow(_ title: String, _ detail: String,
                                      icon: String) -> some View {
        Label(title, systemImage: icon)
            .help(detail)
    }

    /// The mode control — the "streamline Let's build in" change: a `Menu` over
    /// `ChatMode.composerCases` (Ask/Plan/Build) bound to `$mode`. The composer
    /// only owns the selected mode; Build *routing* lives in the parent's
    /// `onSend`.
    ///
    /// `composerCases`, NOT `allCases`: `.engineering` exists in the model but
    /// has no workspace yet, and this menu is the whole reason a mode is
    /// reachable. See the doc comment on `ChatMode.composerCases`.
    private var modeMenu: some View {
        Menu {
            ForEach(ChatMode.composerCases) { m in
                Button(m.label(lang)) { mode = m }
            }
        } label: {
            HStack(spacing: 6) {
                Text(mode.label(lang)).font(CodepetTheme.inter(13))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(CodepetTheme.mutedText)
            }
            .foregroundColor(CodepetTheme.bodyText)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(CodepetTheme.hairline)
            )
            .hoverAffordance(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sendButton: some View {
        // 27pt in two-mode (the prototype's `.send`), 34 in the dock. The pane's
        // composer is a quiet strip at the bottom, not the hero's centrepiece.
        let d: CGFloat = surface == .dock ? 34 : 27
        return Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: surface == .dock ? 15 : 12, weight: .semibold))
                .foregroundColor(canSend ? CodepetTheme.onAccent(accent) : .white)
                .frame(width: d, height: d)
                .background(
                    Circle().fill(
                        canSend
                            ? AnyShapeStyle(CodepetTheme.ramp(accent, accent2))
                            : AnyShapeStyle(CodepetTheme.mutedText)
                    )
                    .shadow(color: canSend ? accent.opacity(0.55) : .clear, radius: 10)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }
}

#if DEBUG
private struct ChatComposerPreviewHost: View {
    /// Preselect a department to see the armed chip (sprite + accent) without running the app.
    var selected: Department? = nil
    /// Supply a suggestion to see the DASHED chip — the state the founder sees before they
    /// have chosen anything.
    var suggested: Department? = nil
    @State private var draft = ""
    @State private var mode: ChatMode = .ask
    @FocusState private var focused: Bool
    @State private var dept: Department? = nil
    var body: some View {
        ChatComposer(
            draft: $draft, mode: $mode, canSend: !draft.isEmpty,
            focus: $focused,
            placeholder: "Ask anything about your company…",
            quickActions: [
                QuickAction(title: "Run a task", systemImage: "checklist",
                            detail: "Ship a real deliverable from your roadmap."),
                QuickAction(title: "Review the roadmap", systemImage: "map",
                            detail: "See what's next and what's blocking launch."),
            ],
            accent: CodepetTheme.accentPurple, accent2: CodepetTheme.accentPink,
            isBusy: false, selectedDept: $dept,
            suggestion: suggested.map {
                DepartmentRouter.Suggestion(deptKey: $0.key, tier: .topical, matched: "layout")
            },
            onSend: {}, onQuickAction: { _ in }
        )
        .frame(width: 380)
        .padding()
        .environmentObject(CompanyStore())
        .onAppear { if dept == nil { dept = selected } }
    }
}

#Preview("ChatComposer (dock, 380pt)") { ChatComposerPreviewHost() }

/// Marketing armed: the chip carries Nova's sprite and Marketing's accent, and — because it came
/// from the ••• overflow rather than the two visible chips — it appears as its own chip beside
/// them. The two states to compare are this and the preview above, at the same 380pt dock width:
/// the row must not wrap or crowd the active-project chip once a sprite is in it.
#Preview("ChatComposer (Marketing armed)") {
    ChatComposerPreviewHost(selected: DepartmentCatalog.find("mkt"))
}

/// Design SUGGESTED, not picked: dashed stroke, fill at 0.07, label at 0.75. Compare against
/// the armed preview above — same chip, same string, same sprite. That comparison is the whole
/// visual design, and it is the one thing green tests cannot check.
#Preview("ChatComposer (Design suggested)") {
    ChatComposerPreviewHost(suggested: DepartmentCatalog.find("design"))
}
#endif
