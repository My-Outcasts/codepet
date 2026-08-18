import SwiftUI

/// The chat composer — one reusable input surface used in BOTH the empty hero
/// and the docked active conversation. Owns no state: draft/mode live in the
/// parent (`CopilotChatView`) so the same value drives both placements.
///
/// Honesty notes: the `+` button is a quick-actions menu (NOT a file picker —
/// the app has no attachments), and the mode control shapes the outgoing message
/// via `ChatMode` (no backend mode exists).
///
/// DOCK ADAPTATION (380pt): `deptChips` shows the first 2 department chips (PR#39
/// showed 3) + the `•••` overflow menu, so the chip row + the active-project chip
/// fit inside the 380pt dock width.
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
    @Binding var selectedDept: Department?
    var onSend: () -> Void
    var onQuickAction: (String) -> Void

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
            ComposerField(placeholder: placeholder, text: $draft, focus: focus, onSend: onSend)

            deptChips

            HStack(spacing: 8) {
                quickActionsMenu
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
        VStack(alignment: .leading, spacing: 12) {
            ComposerField(placeholder: placeholder, text: $draft, focus: focus,
                          floor: ComposerMetrics.paneMinTextHeight, onSend: onSend)

            HStack(spacing: 7) {
                deptChips
                quickActionsMenu
                Spacer(minLength: 8)
                sendButton
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 11)
        // The house card: `cardRaised` + `cardEdge` at radius 12 with `shadowS`,
        // the same object Tasks and Roadmap are built from. Accent moves to the
        // edge only on focus — an always-accent outline (the dock's) made the
        // composer the loudest thing on a pane it no longer competes for.
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CodepetTokens.cardRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(focus.wrappedValue ? accent.opacity(0.65) : CodepetTokens.cardEdge,
                        lineWidth: 1)
        )
        .shadow(color: restShadow.color, radius: restShadow.radius, x: restShadow.x, y: restShadow.y)
        .shadow(color: (focus.wrappedValue && !reduceTransparency) ? accent.opacity(0.28) : .clear, radius: 16)
        .opacity(isBusy ? 0.62 : 1.0)
    }

    private var deptChips: some View {
        // Dock adaptation (380pt): 2 chips + overflow, not the prototype's 3 —
        // keeps the row + the active-project chip from overflowing the dock width.
        let visible = Array(DepartmentCatalog.roster.prefix(surface.visibleDeptChips))
        // A department chosen from the overflow menu isn't one of the visible
        // chips, so its selection was invisible. Surface it as its own chip.
        let overflowSelected: Department? = selectedDept.flatMap { sel in
            visible.contains(where: { $0.key == sel.key }) ? nil : sel
        }
        return HStack(spacing: 6) {
            ForEach(visible) { dep in
                chip(dep)
            }
            if let sel = overflowSelected {
                chip(sel)
            }
            // Two-mode folds the overflow into the `+` menu, the way the prototype's
            // single `+` does — one control, not a `•••` beside a `＋`.
            if surface == .dock {
                Menu {
                    deptOverflowItems
                } label: {
                    Text("•••").font(CodepetTheme.inter(12, weight: .semibold))
                        .foregroundColor(CodepetTheme.mutedText)
                        .padding(.horizontal, 10).frame(height: 26)
                        .overlay(Capsule().stroke(CodepetTheme.hairline))
                        .hoverAffordance(Capsule())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }

            // Active coding-agent project (2C-3): a quiet, always-visible reminder of
            // which folder the agent will touch. Tap → the Environment link surface.
            // Two-mode has no room for it beside three chips, and Developer's own
            // session bar names the repo, so it stays a dock affordance.
            if surface == .dock, let link = companyStore.activeProjectLink {
                Spacer(minLength: 8)
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
        }
    }

    /// A department chip. Selecting one summons that department's PET — and until the reply
    /// landed, nothing said so: the chip named a department, the answer arrived signed "Nova ·
    /// Marketing", and the founder had to send a message to find out who she had picked. The
    /// sprite rides the selected chip so the handoff is legible at the moment of choosing.
    ///
    /// Only the ON state carries it. A sprite on every chip would put four portraits in a row
    /// under the composer competing with the send button, and the pet is only a fact once the
    /// chip is armed. A department with no mapped companion (or one that IS the host — the same
    /// case `actingSpecialist` declines to hand off) shows the name alone, so the chip never
    /// promises a pet that won't appear.
    private func chip(_ dep: Department) -> some View {
        let on = selectedDept?.key == dep.key
        return Button {
            selectedDept = on ? nil : dep
        } label: {
            HStack(spacing: 5) {
                if on, let pet = chipPet(dep) {
                    // 18pt, not the 20-28pt used in the transcript: the chip row is 26pt tall,
                    // and these sprites are tall portraits fitted into a square frame, so the
                    // sprite reads as ~13pt wide. It is an identity cue next to the name it
                    // belongs to, not a thing to be recognised on its own.
                    CharacterImage(pet, size: 18)
                }
                Text(dep.name).font(CodepetTheme.inter(12, weight: .semibold))
                    .foregroundColor(on ? dep.accent : CodepetTheme.bodyText)
            }
            .padding(.horizontal, 10).frame(height: 26)
            // Off used to be `Color.clear`, which made the chip hard to select and
            // easy to deselect — the interior only existed once it was already on.
            // `surface` is what the composer sits on, so this reads identically at
            // rest while giving the off state a real interior.
            .background(Capsule().fill(on ? dep.accent.opacity(0.15) : CodepetTheme.surface))
            .overlay(Capsule().stroke(on ? dep.accent : CodepetTheme.hairline))
            .hoverAffordance(Capsule(), accent: dep.accent)
        }.buttonStyle(.plain)
    }

    /// The pet this chip summons, or nil when the turn would stay with the host. Goes through the
    /// SAME `specialistId` the send does (`CompanyStore.actingSpecialist`), so the chip can never
    /// promise a pet the reply then doesn't sign — see that function for why the rule has one home.
    private func chipPet(_ dep: Department) -> String? {
        DepartmentCompanions.specialistId(for: dep.key, host: companyStore.company.companionId)
    }

    /// The departments that don't have a visible chip. One list, two call sites —
    /// the dock's `•••` and two-mode's `+` — so the two can't drift apart.
    @ViewBuilder private var deptOverflowItems: some View {
        ForEach(DepartmentCatalog.roster.dropFirst(surface.visibleDeptChips)) { dep in
            Button {
                selectedDept = (selectedDept?.key == dep.key) ? nil : dep
            } label: {
                Label(dep.name, systemImage: selectedDept?.key == dep.key ? "checkmark" : "")
            }
        }
    }

    private var quickActionsMenu: some View {
        Menu {
            ForEach(quickActions) { qa in
                Button {
                    onQuickAction(qa.title)
                } label: {
                    Label(qa.title, systemImage: qa.systemImage)
                }
            }
            if surface == .twoMode {
                Divider()
                Section(lang == .vi ? "Phòng ban" : "Departments") { deptOverflowItems }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: surface == .dock ? 15 : 12, weight: .medium))
                .foregroundColor(CodepetTheme.bodyText)
                .frame(width: surface == .dock ? 30 : 26,
                       height: surface == .dock ? 30 : 26)
                // Bare in the pane. Claude and Codex both draw their `+` as a glyph with
                // no container; ours was a fourth outlined pill in a row that already had
                // three, which is most of why the control row read as heavy.
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
                            ? AnyShapeStyle(LinearGradient(
                                gradient: Gradient(colors: [accent, accent2]),
                                startPoint: .topLeading, endPoint: .bottomTrailing))
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
