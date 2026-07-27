// codepet/Views/SecondBrain/SecondBrainView.swift
import SwiftUI

/// The Second Brain page — was the right half of the retired Overview toggle.
/// A thin wrapper: header plus the unchanged panel. Department rows still route
/// to `.company`, which is how Company stays reachable without a rail slot.
struct SecondBrainView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lang == .vi ? "Bộ não" : "Second Brain")
                    .font(CodepetTheme.title()).foregroundColor(CodepetTheme.primaryText)
                Text(lang == .vi ? "Những gì Codepet biết về công ty của bạn"
                                 : "What Codepet knows about your company")
                    .font(CodepetTheme.subtitle()).foregroundColor(CodepetTheme.mutedText)
            }
            .padding(.horizontal, 24).padding(.top, 22)

            SecondBrainPanel(data: SecondBrainData(company: companyStore.company), lang: lang,
                             onOpenDept: { key in
                                 companyStore.selectedDeptKey = key
                                 companyStore.select(.company)
                             })
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 24).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
