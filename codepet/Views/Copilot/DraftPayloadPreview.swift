import SwiftUI

/// The deliverable itself, on the card, the moment it lands.
///
/// **Why this exists.** `draftCard` rendered `DraftPreview.plain(d.body)` under a `lineLimit`
/// and never read `d.payload` at all — every structured viewer existed and only the Library
/// mounted them. So Finance's pricing model, a four-input interactive model, arrived as a
/// truncated paragraph ending in `....`, and the landing page arrived as a sentence reading
/// *"The page is live in your Library — open it to see it rendered."*
///
/// That sentence is quoted here as history and no longer exists: it was the Murror fixture's
/// own prose body, and it survived this view landing — so the card told the founder to go and
/// look at a page it was already rendering ten pixels below, above a draft the card also said
/// was "Not saved yet". Seen in a founder recording on 4 Sep and cut from the fixture then.
///
/// That sentence was the whole problem in miniature: the card explained where the work was
/// instead of being it. Reported by the founder as *"each department's output should appear on
/// the card as soon as it's completed."*
///
/// **The dispatch is a pure static, not a `switch` buried in `body`.** The bug was in the
/// decision, not the layout, and a decision inside a `View`'s body is only testable by
/// rendering it. `hasStructuredPreview` is what `draftCard` asks before mounting this at all,
/// and what the suite pins.
struct DraftPayloadPreview: View {
    let deliverable: Deliverable
    /// Open the full viewer. Non-optional on purpose: a preview with no way through is the
    /// defect this parameter exists to make impossible to reintroduce.
    let onOpen: () -> Void

    @Environment(\.uiLanguage) private var lang

    /// Every structured preview routes to the full viewer.
    ///
    /// **The defect this records.** The preview rendered the landing page's brand, headline,
    /// accent and CTA — and had no tap target of its own. The card's only gesture sat on the
    /// title block ABOVE it, so a founder who clicked the thing that looks like a website got
    /// nothing at all. §1's own plan said "let Open reach the true render"; the render landed
    /// and the affordance did not.
    ///
    /// A constant rather than a per-kind switch, so a new payload kind cannot arrive
    /// un-openable — which is exactly how this one got missed.
    static let opensFullViewer = true

    /// A worded cue, for the one kind that needs one.
    ///
    /// **Only `.site`, and the asymmetry is deliberate.** A rendered page reads as *"this IS
    /// the page"*, so nothing on screen tells the founder that a fuller render sits behind it.
    /// A pricing model or a screens grid is visibly a summary of something bigger already, and
    /// labelling all seven would put more chrome about the deliverable on the card than the
    /// deliverable gets.
    ///
    /// It promises what `DeliverableDetailView` actually mounts — `SiteViewer`, a real web view
    /// of the page — and `hasStructuredPreview` gates this whole view on the same non-nil
    /// `payload.site` that viewer requires, so the cue cannot appear over a sheet showing prose.
    static func openCue(for kind: DeliverableKind, lang: AppLanguage) -> String? {
        guard kind == .site else { return nil }
        return lang == .vi ? "M\u{1EDF} trang th\u{1EAD}t" : "Open the live page"
    }

    /// **Capped, and deliberately not scrollable.** A card that scrolls inside a scrolling
    /// transcript is worse than one that truncates — two nested scroll views fight the
    /// trackpad — and the full viewer is already one tap away on the title block above.
    static let maxHeight: CGFloat = 180

    /// Whether there is real structure to show.
    ///
    /// **Keyed on the PAYLOAD, never on the kind alone.** Dispatching on kind would render an
    /// empty structured view whenever the payload did not arrive — three blank slider rows, a
    /// checklist with no items — and the founder cannot distinguish that from a broken card.
    /// Prose is the honest fallback for an absent payload.
    static func hasStructuredPreview(_ d: Deliverable) -> Bool {
        guard let p = d.payload else { return false }
        switch d.kind {
        case .site:      return p.site != nil
        case .sheet:     return p.sheet != nil
        case .screens:   return !(p.screens?.screens ?? []).isEmpty
        case .dms:       return !(p.messages ?? []).isEmpty
        case .checklist: return !(p.items ?? []).isEmpty
        case .doc:       return !(p.call ?? "").isEmpty || !(p.sections ?? []).isEmpty
        case .plan:      return !(p.goal ?? "").isEmpty
        default:         return false
        }
    }

    /// Mirrors `SiteViewer.safeHex`'s validation, returning a `Color`.
    ///
    /// It validates hex **syntax**, not contrast — which is exactly why it cannot be trusted
    /// alone and why the fixture suite also asserts the accent's luminance. Here the job is
    /// narrower: a malformed value must not paint a broken swatch. Falls back to the house
    /// accent rather than to the viewer's own violet literal, so the card stays on-theme.
    static func safeAccent(_ hex: String) -> Color {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return CodepetTheme.accentPurple }
        let digits = s.dropFirst()
        guard digits.count == 6 || digits.count == 3,
              digits.allSatisfy(\.isHexDigit) else { return CodepetTheme.accentPurple }
        let six = digits.count == 3 ? String(digits.flatMap { [$0, $0] }) : String(digits)
        return Color(hex: six)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: Self.maxHeight, alignment: .top)
            if let cue = Self.openCue(for: deliverable.kind, lang: lang) {
                Text(cue)
                    .font(.pixelSystem(size: 11, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
            }
        }
        // `contentShape` before the gesture: the preview is a stack of shapes with gaps
        // between them, and without it the gaps are not part of the target — a click landing
        // between the headline and the swatch would do nothing, which is the same bug in
        // miniature. Matches the title block above: hover fill, pointing hand, tap opens.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .hoverAffordance(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .cursorOnHover(.pointingHand)
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Self.openCue(for: deliverable.kind, lang: lang)
                            ?? (lang == .vi ? "M\u{1EDF} b\u{1EA3}n \u{111}\u{1EA7}y \u{111}\u{1EE7}" : "Open the full deliverable"))
            .clipped()
    }

    @ViewBuilder
    private var content: some View {
        let p = deliverable.payload
        switch deliverable.kind {
        case .site:      if let s = p?.site { site(s) }
        case .sheet:     if let s = p?.sheet { sheet(s) }
        case .screens:   if let s = p?.screens { screens(s) }
        case .dms:       if let m = p?.messages { dms(m) }
        case .checklist: if let i = p?.items { checklist(i) }
        case .doc:       doc(call: p?.call ?? "", sections: p?.sections ?? [])
        case .plan:      plan(goal: p?.goal ?? "", steps: p?.steps ?? [], changes: p?.changes ?? [])
        default:         EmptyView()
        }
    }

    // MARK: - site

    /// The page's IDENTITY, not a picture of it.
    ///
    /// A `WKWebView` per message is the wrong price for a preview — heavy, asynchronous, and a
    /// transcript can hold many cards — and a pixel-accurate thumbnail would need an offscreen
    /// snapshot. Brand, headline, accent and CTA are the fields a founder recognises the page
    /// by; the title block above still opens the true render.
    private func site(_ s: SitePayload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !s.brand.isEmpty {
                Text(s.brand.uppercased())
                    .font(.pixelSystem(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(CodepetTheme.mutedText)
            }
            Text([s.headline, s.headlineHi].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.pixelSystem(size: 14.5, weight: .semibold))
                .foregroundColor(CodepetTheme.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !s.sub.isEmpty {
                Text(s.sub)
                    .font(.pixelSystem(size: 11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Self.safeAccent(s.accent))
                    .frame(width: 13, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(CodepetTheme.hairline))
                if !s.ctaPrimary.isEmpty {
                    Text(s.ctaPrimary)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(CodepetTheme.bodyText)
                }
            }
            .padding(.top, 1)
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(CodepetTheme.pageBackground))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(CodepetTheme.hairline))
    }

    // MARK: - sheet

    /// The four fixed inputs, read-only. `SheetPayload` is a pricing MODEL, not a generic
    /// table — never a fifth row.
    private func sheet(_ s: SheetPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sheetRow("Price", s.price, prefix: "$")
            sheetRow("Signups", s.waitlist)
            sheetRow("Convert", s.conversion, suffix: "%")
            sheetRow("Churn", s.churn, suffix: "%")
            if let summary = s.summary, !summary.isEmpty {
                Text(summary)
                    .font(.pixelSystem(size: 11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private func sheetRow(_ label: String, _ input: SheetInput,
                          prefix: String = "", suffix: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.pixelSystem(size: 11))
                .foregroundColor(CodepetTheme.mutedText)
                .frame(width: 52, alignment: .leading)
            Text("\(prefix)\(Self.trimmed(input.val))\(suffix)")
                .font(.pixelSystem(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(CodepetTheme.primaryText)
                .frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(CodepetTheme.hairline).frame(height: 3)
                    Circle()
                        .fill(CodepetTheme.accentPurple)
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, (geo.size.width - 8) * Self.fraction(input)))
                }
                .frame(height: 8)
            }
            .frame(height: 8)
        }
    }

    /// Guarded against a degenerate range: `max <= min` would divide by zero and NaN the offset,
    /// which SwiftUI renders as a dot pinned at the far left with no indication anything is
    /// wrong. `SheetInput` comes off the wire, so the range is not ours to trust.
    static func fraction(_ input: SheetInput) -> Double {
        let span = input.max - input.min
        guard span > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (input.val - input.min) / span))
    }

    /// `6.0` reads as a bug on a price row; `6` does not.
    static func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - screens

    private func screens(_ s: ScreensPayload) -> some View {
        HStack(alignment: .top, spacing: 7) {
            ForEach(Array(s.screens.prefix(4).enumerated()), id: \.offset) { _, screen in
                VStack(alignment: .leading, spacing: 3) {
                    if !screen.kick.isEmpty {
                        Text(screen.kick.uppercased())
                            .font(.pixelSystem(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundColor(CodepetTheme.accentPurple)
                    }
                    Text(screen.title)
                        .font(.pixelSystem(size: 11, weight: .semibold))
                        .foregroundColor(CodepetTheme.primaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(CodepetTheme.pageBackground))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(CodepetTheme.hairline))
            }
        }
    }

    // MARK: - dms

    private func dms(_ messages: [DmMessage]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let first = messages.first {
                Text(first.name)
                    .font(.pixelSystem(size: 11.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.primaryText)
                Text(first.msg)
                    .font(.pixelSystem(size: 11.5))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if messages.count > 1 {
                Text("\(messages.count) recipients")
                    .font(.pixelSystem(size: 10.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
            }
        }
    }

    // MARK: - checklist

    private func checklist(_ items: [ChecklistItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundColor(item.done ? CodepetTheme.accentTeal : CodepetTheme.hairline)
                    Text(item.t)
                        .font(.pixelSystem(size: 11.5))
                        .foregroundColor(CodepetTheme.bodyText)
                        .lineLimit(1)
                }
            }
            if items.count > 3 {
                Text("+\(items.count - 3) more")
                    .font(.pixelSystem(size: 10.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.accentPurple)
            }
        }
    }

    // MARK: - doc / plan

    private func doc(call: String, sections: [DocSection]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !call.isEmpty {
                Text(call)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !sections.isEmpty {
                Text(sections.prefix(4).map(\.h).joined(separator: " · "))
                    .font(.pixelSystem(size: 10.5, weight: .semibold))
                    .foregroundColor(CodepetTheme.mutedText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func plan(goal: String, steps: [String], changes: [PlanChange]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !goal.isEmpty {
                Text(goal)
                    .font(.pixelSystem(size: 12))
                    .foregroundColor(CodepetTheme.bodyText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(steps.count) steps · \(changes.count) changes")
                .font(.pixelSystem(size: 10.5, weight: .semibold))
                .foregroundColor(CodepetTheme.accentPurple)
        }
    }
}
