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
/// **PROTOTYPE STATE, 21 Aug.** The controls, the picker, the pills and the caps are
/// all live. What is NOT wired is the last hop for pins and attachments — neither
/// reaches the model yet, because that needs `ChatContext.compose(pinned:)` and a
/// widened `ClaudeMessage.content` in `functions/`. Both are on the plan and neither
/// is in this change, which is why the `🌐 Web search` row is absent rather than
/// present and lying: a toggle that does not change the request is worse than none.
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
    /// What the founder pinned or attached for this message, when the surface offers
    /// it. Optional and nil by default — same additive rule as `tier`, so
    /// `DeveloperWorkPane` (whose context is its branch and its folder, not a
    /// marketing deliverable) passes nothing and renders exactly as before.
    var pins: Binding<[ContextPin]>? = nil
    var attachments: Binding<[ChatAttachment]>? = nil
    @Binding var selectedDept: Department?
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
                if showsDeptChips || selectedDept != nil { departmentControl }
                plusMenu
                voiceButton
                // "The tier lives in the composer, beside `+`" (§8.2) — the session
                // bar carries facts set once, the composer carries controls for the
                // NEXT instruction, and how much rope the next instruction gets is
                // exactly that.
                if let tier { tierMenu(tier) }
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
        let host = companyStore.company.companionId
        let armed = selectedDept
        return HStack(spacing: 0) {
            Menu {
                Button { selectedDept = nil } label: {
                    if armed == nil {
                        Label(DepartmentMenu.anyoneLabel(lang), systemImage: "checkmark")
                    } else {
                        Text(DepartmentMenu.anyoneLabel(lang))
                    }
                }
                Divider()
                ForEach(DepartmentMenu.rosterOrder) { dep in
                    Button { selectedDept = dep } label: { deptRow(dep, host: host) }
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
                    if let dep = armed,
                       let pet = DepartmentMenu.pet(for: dep, host: host),
                       let sprite = PetMenuIcon.image(pet) {
                        sprite
                    }
                    Text(armed.map { DepartmentMenu.armedLabel($0, host: host) }
                         ?? DepartmentMenu.restLabel(lang))
                        .font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(armed?.accent ?? CodepetTheme.bodyText)
                        .lineLimit(1)
                    if armed == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(CodepetTheme.mutedText)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, armed == nil ? 10 : 6)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if let dep = armed {
                Button { selectedDept = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(dep.accent)
                        .frame(width: 20, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(DepartmentMenu.clearHelp(lang))
            }
        }
        // The armed treatment is the retired chip's treatment, unchanged: two
        // treatments for one control would read as two features.
        .background(Capsule().fill(armed.map { $0.accent.opacity(0.15) } ?? CodepetTheme.surface))
        .overlay(Capsule().stroke(armed?.accent ?? CodepetTheme.hairline))
        .hoverAffordance(Capsule(), accent: armed?.accent ?? CodepetTheme.accentPurple)
    }

    /// One menu row: checkmark when armed, else the pet's sprite, then
    /// `crash · Engineering`.
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
    @ViewBuilder private func deptRow(_ dep: Department, host: String) -> some View {
        let on = selectedDept?.key == dep.key
        let title = DepartmentMenu.rowTitle(dep, host: host)
        if on {
            Label(title, systemImage: "checkmark")
        } else if let pet = DepartmentMenu.pet(for: dep, host: host),
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
    /// **PROTOTYPE STATE (21 Aug).** Pinning and attaching are live here — the picker
    /// runs, the pills appear, the caps hold. What is not wired is the last hop:
    /// neither reaches the model yet, because that needs `ChatContext.compose` and
    /// `functions/`. The `🌐 Web search` row is therefore absent rather than present
    /// and lying: a toggle that does not change the request is worse than no toggle.
    private var plusMenu: some View {
        Menu {
            Section(PlusMenu.bringInLabel(lang)) {
                if let atts = attachments {
                    let full = atts.wrappedValue.count >= ChatAttachment.max
                    Button {
                        let room = ChatAttachment.max - atts.wrappedValue.count
                        guard room > 0 else { return }
                        let picked = AttachmentPicker.pickAndEncode(limit: room)
                        var next = atts.wrappedValue
                        for a in picked.attachments { next = ChatAttachment.adding(a, to: next) }
                        atts.wrappedValue = next
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
            .disabled(!VoicePermission.canEnterVoiceMode(availability, isBusy: isBusy))
            .help(VoicePermission.help(availability, lang) ?? (lang == .vi ? "Chế độ giọng nói" : "Voice mode"))
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
#endif
