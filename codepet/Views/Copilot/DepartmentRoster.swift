// codepet/Views/Copilot/DepartmentRoster.swift
import SwiftUI

/// The cast, on the first screen.
///
/// Codepet's signature is that eight departments answer, each in the voice of a
/// pet — and until this, none of that existed until a founder happened to arm a
/// chip or a specialist happened to sign a reply. The empty hero showed an orb, a
/// greeting, and a void down to the composer.
///
/// The prototype's own words for why it sits here: "pets are the voice of each
/// department, so the cast is on the first screen rather than appearing for the
/// first time mid-run."
///
/// Codex fills the same space with four capability cards under an icon. This is
/// the same move with a better icon: theirs is a glyph for a verb, ours is the
/// character who will actually answer.
///
/// **Tapping arms, it does not send.** A tap selects the department in the
/// composer and focuses it, so the founder writes their own question — the same
/// thing clicking the composer's own chip does. The prototype sends "<Dept> —
/// where would you start?" on tap, which demos the handoff in one click but spends
/// a chat turn on a question the founder did not ask. Showing the cast should not
/// cost credits.
struct DepartmentRoster: View {
    /// The armed department, so a chip here and the identical chip in the composer
    /// can never disagree about what is selected.
    @Binding var selected: Department?
    let onPick: (Department) -> Void

    @Environment(\.uiLanguage) private var lang
    @EnvironmentObject private var companyStore: CompanyStore

    /// The prototype's `.roster` caps at 460px so eight chips wrap into a block
    /// rather than a single wide line. Three to a row at this width.
    private let columns = [GridItem(.adaptive(minimum: 148), spacing: 7, alignment: .leading)]

    var body: some View {
        VStack(spacing: 8) {
            Text(lang == .vi
                 ? "ĐỘI CỦA BẠN — MỖI PHÒNG BAN CÓ GIỌNG NÓI RIÊNG"
                 : "YOUR TEAM — EACH DEPARTMENT SPEAKS WITH ITS OWN VOICE")
                .font(CodepetTheme.inter(CodepetType.footnote))
                .tracking(1)
                .foregroundColor(CodepetTokens.faint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: columns, alignment: .center, spacing: 7) {
                ForEach(DepartmentCatalog.roster) { dep in
                    chip(dep)
                }
            }
        }
        .frame(maxWidth: 480)
    }

    /// Pet sprite, pet name, then the department it speaks for.
    ///
    /// The pet's name leads because that is what the reply will be signed with —
    /// `CopilotChatView.headerName` renders "Nova · Marketing" — so the chip and the
    /// answer read in the same order. Six pets cover eight departments (nova takes
    /// Marketing and Sales, glitch Operations and Legal), which is a fact about the
    /// cast worth showing rather than hiding: the repeat is the point, not a bug.
    private func chip(_ dep: Department) -> some View {
        let on = selected?.key == dep.key
        let pet = DepartmentCompanions.companionId(for: dep.key)
        return Button {
            onPick(dep)
        } label: {
            HStack(spacing: 6) {
                if let pet {
                    CharacterImage(pet, size: 16)
                } else {
                    // No mapped pet — Codepet answers. Show the orb rather
                    // than a gap, so the chip never promises a pet that won't appear.
                    CompanionOrb(size: 14, glow: false)
                }
                if let pet, let name = PetCharacter.all[pet]?.name {
                    Text(name)
                        .font(CodepetTheme.inter(CodepetType.subheadline, weight: .semibold))
                        .foregroundColor(on ? dep.accent : CodepetTheme.bodyText)
                }
                Text("· \(dep.name)")
                    .font(CodepetTheme.inter(CodepetType.subheadline))
                    .foregroundColor(on ? dep.accent : CodepetTokens.faint)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
            // The composer's chip states, exactly — this is the same control in a
            // different place, and two treatments would read as two features.
            .background(Capsule().fill(on ? dep.accent.opacity(0.15) : CodepetTokens.cardRaised))
            .overlay(Capsule().stroke(on ? dep.accent : CodepetTokens.cardEdge))
            .hoverAffordance(Capsule(), accent: dep.accent)
        }
        .buttonStyle(.plain)
        .help(dep.focus)
    }
}

#if DEBUG
private struct RosterPreviewHost: View {
    @State private var selected: Department?
    var body: some View {
        DepartmentRoster(selected: $selected, onPick: { selected = $0 })
            .padding(28)
            .frame(width: 720)
            .background(CodepetTheme.pageBackground)
            .environmentObject(CompanyStore())
    }
}

#Preview("DepartmentRoster") { RosterPreviewHost() }
#endif
