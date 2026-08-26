import SwiftUI

/// The chat empty state: a centered, personalized hero greeting (time-of-day +
/// founder name, purple-gradient second line), the composer (injected so the
/// parent keeps ownership of draft/mode), and up to 3 LIVE roadmap cards
/// (beacon / needs-you / awaiting-approval) — or 3 prompt-starter cards that
/// fill the composer when there's no roadmap yet. Replaces the old
/// company-only greeting + static `QuickAction` pill row. The empty and active
/// states now share one flat `pageBackground` (filled by the shell), not an
/// ambient wash behind either.
///
/// DOCK ADAPTATION (380pt panel, ported from the full-width feat/chat-redesign
/// original): smaller orb (56 vs 78), smaller greeting type (22 vs 31), single-
/// column card grids (vs 2-col), no fixed 760pt column cap (fills the dock
/// width instead), and tighter horizontal padding (20 vs 40).
struct ChatEmptyState<Composer: View>: View {
    let state: ChatLandingState
    let onOpenRoadmap: () -> Void
    let onStarter: (String) -> Void
    /// Dock-sized: fills the available width rather than capping at the
    /// full-width chat's 760pt column.
    var columnWidth: CGFloat = .infinity
    /// Two-mode only: the beacon card's buttons. The dock's card is a link to the
    /// roadmap and passes nothing here.
    var beaconTasks: [RoadmapTask] = []
    var onBeacon: (BeaconOffer.Primary, RoadmapTask) -> Void = { _, _ in }
    /// The roster's armed department — the SAME binding the composer's chips read,
    /// so a pet armed here lights the chip down there rather than becoming a second,
    /// disagreeing selection.
    var selectedDept: Binding<Department?> = .constant(nil)
    var onDepartment: (Department) -> Void = { _ in }
    @ViewBuilder var composer: Composer

    @Environment(\.uiLanguage) private var lang
    @Environment(\.chatSurface) private var surface
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var companyStore: CompanyStore

    /// Which candidate the beacon is showing. `Something else` advances it; it is
    /// view state, not company state — skipping a suggestion is not a decision and
    /// must not be written anywhere.
    @State private var beaconIndex = 0

    var body: some View {
        switch surface {
        case .dock:    dockBody
        case .twoMode: heroBody
        }
    }

    // MARK: - The dock (main's shell) — unchanged

    private var dockBody: some View {
        VStack(spacing: 24) {
            CompanionOrb(size: 56)

            gradientGreeting
                .padding(.horizontal, 24)

            composer
                .frame(maxWidth: columnWidth)

            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - The two-mode hero

    /// Orb, greeting, and ONE card — the prototype's hero exactly. The composer is
    /// not here: it is docked at the bottom of the pane by `CopilotChatView`, which
    /// is what keeps the beacon's buttons above the fold instead of being pushed
    /// under a composer that grew.
    private var heroBody: some View {
        VStack(spacing: 10) {
            brandMark
            greeting
            if let offer = BeaconOffer.offer(for: beaconTask, in: beaconTasks,
                                             host: CodepetBrand.name, language: lang) {
                beaconCard(offer)
            }
            // The cast, under the one thing to do. Both fit: the chips are two or
            // three short rows, and on a board with no actionable task they carry
            // the screen on their own — which is the state the hero was emptiest in.
            DepartmentRoster(selected: selectedDept, onPick: onDepartment)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 14).padding(.bottom, 10)
    }

    /// Codepet's own mark, where the companion orb used to be.
    ///
    /// The hero says "What should we build for **Codepet** today?" — it is the
    /// product speaking, not a pet. And now that the roster below carries the cast,
    /// an orb here was the brand's only slot on the screen being spent on a
    /// character. Brand above, characters below.
    ///
    /// Three things taken from `CollapsedCopilotButton`, which learned each of them
    /// from founder review — do not re-derive them here:
    ///
    /// - `codepet-logo` is RGBA with a **fully transparent** background, so it
    ///   carries no ground of its own.
    /// - Its opaque glyph measures 646×826 in a 1024 canvas — taller than wide, with
    ///   only 9.7% vertical margin — so a fitted square renders the "C" at ~81% of
    ///   the box and reads as overflowing. The box is oversized against the ink it
    ///   is meant to produce: 64 here lands ~52pt of glyph, the orb's old diameter.
    /// - `.interpolation(.none)`, per the project rule that pixel art is never
    ///   smoothed.
    ///
    /// **No white disc.** The collapsed button puts one under the mark because a
    /// BUTTON needs a body to be findable on near-black; this is not a control, and
    /// at hero size a white disc punches a hole in a deliberately dark pane. The
    /// roadmap's root node already draws the bare mark, and the aura behind it here
    /// is the same device — it keeps the glyph from sitting flat and stands in for
    /// the bloom the orb used to cast.
    private var brandMark: some View {
        ZStack {
            Circle()
                // Radial, not `CodepetTheme.ramp` — a linear gradient cannot fill a
                // bloom without changing its shape. Same hue pair as the ramp, read
                // named directly — `brandRamp` was dropped after Task 2's review; purple reads first
                // because this is the logo's glow, not a companion's.
                .fill(RadialGradient(colors: [CodepetTheme.accentPurple.opacity(0.34),
                                              CodepetTheme.accentPink.opacity(0.18),
                                              .clear],
                                     center: .center, startRadius: 0, endRadius: 46))
                .frame(width: 92, height: 92)
                .blur(radius: 18)
                .allowsHitTesting(false)
            Image("codepet-logo")
                .resizable().interpolation(.none).scaledToFit()
                .frame(width: 64, height: 64)
        }
        .frame(height: 64)
        .accessibilityLabel(CodepetBrand.name)
    }

    /// The task the card is offering — the beacon, or wherever `Something else`
    /// has walked to. Clamped rather than wrapped: the list changes under this
    /// index whenever a task completes.
    private var beaconTask: RoadmapTask? {
        let candidates = BeaconOffer.candidates(beaconTasks)
        guard !candidates.isEmpty else { return nil }
        return candidates[beaconIndex % candidates.count]
    }

    /// Line 1: the question, with only the verb accented. Line 2: the greeting,
    /// smaller and muted. That order is the point — the app opens by asking for
    /// work, and who is signed in is the subordinate fact.
    private var greeting: some View {
        VStack(spacing: 3) {
            state.questionSegments.reduce(Text("")) { acc, seg in
                acc + Text(seg.text).foregroundStyle(
                    seg.accent ? CodepetTheme.accentPurple : CodepetTheme.primaryText)
            }
            .font(CodepetTheme.inter(CodepetType.title2, weight: .semibold))

            Text(state.greeting)
                .font(CodepetTheme.inter(CodepetType.body, weight: .medium))
                .foregroundColor(CodepetTheme.mutedText)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The tinted card: an eyebrow, the work, one line about who does it and where
    /// the founder's gate is, then the buttons. Left-aligned inside a centered
    /// hero — a title that wraps must not centre itself into a diamond.
    ///
    /// Built from `CodepetTokens`, not from the prototype's own numbers. The
    /// prototype mixes its tint with `color-mix` and draws the accent as a 4px
    /// inset shadow at radius 9; this app already has a house recipe for exactly
    /// this object — `accentTint` + `accentLine` at radius 12 with `shadowS`, and
    /// a 3pt capsule rail, which is what `landingCard` below (and every card on
    /// Tasks and Roadmap) is made of. A second card language in the same window
    /// would read as a different app.
    private func beaconCard(_ offer: BeaconOffer) -> some View {
        let hue = CodepetTheme.accentPurple
        let sh = CodepetTokens.shadowS(scheme == .dark)
        return HStack(alignment: .top, spacing: 0) {
            Capsule().fill(hue).frame(width: 3).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(offer.eyebrow.uppercased())
                    .font(CodepetTheme.inter(CodepetType.footnote, weight: .semibold)).tracking(0.5)
                    .foregroundColor(hue)
                Text(offer.title)
                    .font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .padding(.top, 4)
                Text(offer.detail)
                    .font(CodepetTheme.inter(CodepetType.callout))
                    .foregroundColor(CodepetTheme.mutedText)
                    .padding(.top, 3)
                HStack(spacing: 8) {
                    act(offer.primary.label, filled: true, hue: hue) {
                        if let task = beaconTask { onBeacon(offer.primary, task) }
                    }
                    if offer.canSkip {
                        act(lang == .vi ? "Việc khác" : "Something else", filled: false, hue: hue) {
                            beaconIndex += 1
                        }
                    }
                }
                .padding(.top, 10)
            }
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 400, alignment: .leading)
        .padding(.vertical, 12).padding(.trailing, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(CodepetTokens.accentTint))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CodepetTokens.accentLine, lineWidth: 1))
        .shadow(color: sh.color, radius: sh.radius, x: sh.x, y: sh.y)
    }

    /// The card's buttons. Filled = the accent capsule main uses for a primary
    /// action; ghost = `cardEdge`, the same outline every secondary control in the
    /// app carries. Both take `hoverAffordance`, which is not decoration here —
    /// `.plain` strips AppKit's pointer response and leaves a live control reading
    /// as a dead one.
    private func act(_ label: String, filled: Bool, hue: Color,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(CodepetTheme.inter(CodepetType.subheadline, weight: .semibold))
                .foregroundColor(filled ? CodepetTheme.onAccent(hue) : CodepetTheme.bodyText)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(filled ? hue : .clear))
                .overlay(filled ? nil : Capsule().stroke(CodepetTokens.cardEdge))
                .hoverAffordance(Capsule(), accent: hue)
        }
        .buttonStyle(.plain)
    }

    /// The dock's greeting: both lines at 22pt, the question in a purple→pink
    /// gradient. Kept as-is for `AppShellView`.
    private var gradientGreeting: some View {
        VStack(spacing: 4) {
            Text(state.greeting)
                .font(CodepetTheme.inter(CodepetType.title1, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(state.question)
                .font(CodepetTheme.inter(CodepetType.title1, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    gradient: Gradient(colors: [
                        CodepetTheme.primaryText, CodepetTheme.accentPurple, CodepetTheme.accentPink]),
                    startPoint: .leading, endPoint: .trailing))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Up to 3 live roadmap cards (beacon / needs-you / awaiting-approval),
    /// omitted when zero/nil, tapping through to the Roadmap — or 3
    /// composer-filling prompt starters when there's no roadmap yet. Single
    /// column at dock width (vs 2-col in the full-width original).
    private var cards: some View {
        Group {
            if state.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                    ForEach(starters, id: \.self) { starterCard($0) }
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                    if let b = state.beacon {
                        landingCard(eyebrow: lang == .vi ? "TIẾP THEO" : "DO THIS NEXT",
                                    value: b.title, hue: CodepetTheme.accentPurple, onTap: onOpenRoadmap)
                    }
                    if state.needsYouCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CẦN BẠN" : "NEEDS YOU",
                                    value: "\(state.needsYouCount)", hue: CodepetTheme.accentBlue, onTap: onOpenRoadmap)
                    }
                    if state.awaitingApprovalCount > 0 {
                        landingCard(eyebrow: lang == .vi ? "CHỜ DUYỆT" : "AWAITING APPROVAL",
                                    value: "\(state.awaitingApprovalCount)", hue: CodepetTheme.accentGold, onTap: onOpenRoadmap)
                    }
                }
            }
        }
        .frame(maxWidth: columnWidth)
    }

    private var starters: [String] {
        lang == .vi
            ? ["Soạn định vị của tôi", "Lên kế hoạch tuần này", "Xem lại bản tóm tắt"]
            : ["Draft my positioning", "Plan this week", "Review my brief"]
    }

    private func landingCard(eyebrow: String, value: String, hue: Color, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 0) {
                Capsule().fill(hue).frame(width: 3).padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow).font(CodepetTheme.inter(CodepetType.footnote, weight: .semibold))
                        .foregroundColor(hue).tracking(0.5)
                    Text(value).font(CodepetTheme.inter(CodepetType.title3, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText).lineLimit(2)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }.padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
            .hoverAffordance(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func starterCard(_ text: String) -> some View {
        Button { onStarter(text) } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 13)).foregroundColor(CodepetTheme.accentPurple)
                Text(text).font(CodepetTheme.inter(CodepetType.body, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                    .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CodepetTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CodepetTheme.hairline))
            .hoverAffordance(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("ChatEmptyState (dock)") {
    ChatEmptyState(
        state: ChatLandingState(company: .empty, now: Date(), language: .en),
        onOpenRoadmap: {}, onStarter: { _ in }
    ) { RoundedRectangle(cornerRadius: 16).fill(CodepetTheme.surface).frame(height: 76) }
        .frame(width: 380, height: 700).background(Color.black).environmentObject(CompanyStore())
}

/// The two-mode hero at pane width, with a board under it so the beacon card is
/// the real thing and not a mock — this is the one screen the native app cannot
/// be screenshotted for, so the preview is how it gets looked at.
#Preview("ChatEmptyState (two-mode hero)") {
    var company = CompanyState.empty
    company.brief.founderName = "Mona"
    company.tasks = [
        RoadmapTask(id: "t1", title: "Write your positioning one-pager",
                    detail: "", phase: .find, who: .does, dept: "mkt"),
        RoadmapTask(id: "t2", title: "Talk to 5 potential users",
                    detail: "", phase: .find, who: .you),
    ]
    return ChatEmptyState(
        state: ChatLandingState(company: company, now: Date(), language: .en),
        onOpenRoadmap: {}, onStarter: { _ in },
        beaconTasks: company.tasks, onBeacon: { _, _ in }
    ) { EmptyView() }
        .environment(\.chatSurface, .twoMode)
        .frame(width: 720, height: 460)
        .background(CodepetTheme.pageBackground)
        .environmentObject(CompanyStore())
}
#endif
