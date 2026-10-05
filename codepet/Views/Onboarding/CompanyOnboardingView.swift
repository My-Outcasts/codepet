import SwiftUI

/// First-run founder interview, shown before the shell for a fresh account.
/// 6 steps → enrich → persist to companies/{uid}. Styled in CodepetTheme, VI/EN.
struct CompanyOnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @Environment(\.uiLanguage) private var uiLanguage
    @StateObject private var model = CompanyOnboardingModel()
    @State private var step = 0
    private let api: ReflectionAPIClientProtocol = ReflectionAPIClient()
    var prefillBrief: CompanyBrief? = nil
    var onDone: (() -> Void)? = nil
    /// Set by "Start a different business": Finish hands the brief here instead of finishing
    /// onboarding, and the sheet stays open with a message when it answers false (nothing
    /// changed). Planning a whole roadmap takes about a minute, so the button says so.
    var startsNewBusiness: ((CompanyBrief) async -> Bool)? = nil
    @State private var planning = false
    @State private var planFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(startsNewBusiness != nil
                 ? (uiLanguage == .vi ? "Một công ty mới" : "A new business")
                 : (uiLanguage == .vi ? "Chào mừng đến Codepet" : "Welcome to Codepet"))
                .font(.pixelSystem(size: 20, weight: .bold))
                .foregroundColor(CodepetTheme.primaryText)
            Text(uiLanguage == .vi ? "Kể cho tôi về công ty của bạn." : "Tell me about your company.")
                .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)

            switch step {
            case 0: field(uiLanguage == .vi ? "Tôi nên gọi bạn là gì?" : "What should I call you?", $model.founderName, "e.g. Mona")
            case 1: field(uiLanguage == .vi ? "Vai trò của bạn?" : "Which best describes you?", $model.role, "e.g. Founder")
            case 2: field(uiLanguage == .vi ? "Dự án tên gì?" : "What's it called?", $model.projectName, "e.g. Codepet")
            case 3: field(uiLanguage == .vi ? "Một câu mô tả?" : "In one line, what is it?", $model.oneLiner, "e.g. a recap tool for founders")
            case 4: field(uiLanguage == .vi ? "Dành cho ai?" : "Who is it for?", $model.audience, "e.g. solo founders")
            default:
                Text(uiLanguage == .vi ? "Giai đoạn?" : "What stage is it at?")
                    .font(.pixelSystem(size: 13, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
                Picker("", selection: $model.stageIndex) {
                    ForEach(Array(CompanyOnboardingModel.stages.enumerated()), id: \.offset) { i, s in Text(s).tag(i) }
                }.pickerStyle(.segmented).labelsHidden()
            }

            HStack {
                if let onDone {
                    Button(uiLanguage == .vi ? "Hủy" : "Cancel") { onDone() }
                        .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
                } else {
                    Button(uiLanguage == .vi ? "Bỏ qua" : "Skip") { Task { await companyStore.skipOnboarding() } }
                        .buttonStyle(.plain).foregroundColor(CodepetTheme.mutedText)
                }
                Spacer()
                if step < 5 {
                    Button(uiLanguage == .vi ? "Tiếp" : "Next") { step += 1 }
                        .buttonStyle(.plain).foregroundColor(CodepetTheme.accentPurple)
                } else if let start = startsNewBusiness {
                    Button(planning ? (uiLanguage == .vi ? "Đang lập lộ trình — khoảng một phút…" : "Planning your roadmap — about a minute…")
                                    : (uiLanguage == .vi ? "Bắt đầu" : "Start")) {
                        Task {
                            planning = true; planFailed = false
                            let ok = await start(model.buildBrief())
                            planning = false
                            if ok { onDone?() } else { planFailed = true }
                        }
                    }
                    .buttonStyle(.plain).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
                    .disabled(planning)
                } else {
                    Button(model.isSubmitting ? (uiLanguage == .vi ? "Đang lưu…" : "Saving…")
                                              : (uiLanguage == .vi ? "Hoàn tất" : "Finish")) {
                        Task { await model.submit(store: companyStore, api: api); onDone?() }
                    }
                    .buttonStyle(.plain).foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(CodepetTheme.accentPurple))
                    .disabled(model.isSubmitting)
                }
            }
            if planFailed {
                Text(uiLanguage == .vi
                     ? "Chưa lập được lộ trình mới — chưa có gì thay đổi. Thử lại nhé."
                     : "Couldn't plan the new roadmap — nothing has changed. Try again.")
                    .font(.pixelSystem(size: 12)).foregroundColor(CodepetTheme.mutedText)
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CodepetTheme.pageBackground)
        .task { if let b = prefillBrief { model.prefill(from: b) } }
    }

    private func field(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.pixelSystem(size: 14, weight: .bold)).foregroundColor(CodepetTheme.primaryText)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
        }
    }
}
