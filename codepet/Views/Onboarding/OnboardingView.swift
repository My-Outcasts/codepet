// codepet/Views/Onboarding/OnboardingView.swift
import SwiftUI

/// First-run cinematic onboarding — faithful English-only port of the web
/// `Onboarding` (8 steps 0–7). Replaces the 6-field CompanyOnboardingView at
/// first run; the reveal/scaffold is fail-open (scaffoldRoadmap CF undeployed).
struct OnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore

    struct ObDraft {
        var name = "", role = "", roleLabel = "", tech = ""
        var projName = "", oneLiner = "", audience = "", link = "", notes = ""
        var categories: [String] = []
        var stageIndex = OnboardingContent.defaultStageIndex
    }

    @State private var step = 0
    @State private var d = ObDraft()
    @State private var anShown = 0
    @State private var anDone = false
    @State private var reveal: OnboardingReveal = .empty
    @State private var slow = false

    private func brief() -> CompanyBrief {
        CompanyBrief(
            founderName: d.name.isEmpty ? nil : d.name,
            role: d.roleLabel.isEmpty ? nil : d.roleLabel,
            tech: OnboardingContent.tech.first(where: { $0.key == d.tech })?.label,
            stage: OnboardingContent.stages[d.stageIndex],
            projectName: d.projName.isEmpty ? nil : d.projName,
            oneLiner: d.oneLiner.isEmpty ? nil : d.oneLiner,
            notes: d.notes.isEmpty ? nil : d.notes,
            link: d.link.isEmpty ? nil : d.link,
            categories: d.categories.isEmpty ? nil : d.categories,
            audience: d.audience.isEmpty ? nil : d.audience
        )
    }

    var body: some View {
        Group {
            if step == 0 {
                OnboardingColdOpen(onStart: { step = 1 }, onSkip: skip)
            } else {
                card
            }
        }
        .background(CodepetTheme.pageBackground.ignoresSafeArea())
    }

    // Two-panel card: art left (42%), form right.
    private var card: some View {
        HStack(spacing: 0) {
            Image(OnboardingContent.stepArt[min(step, OnboardingContent.stepArt.count - 1)])
                .resizable().interpolation(.high).scaledToFill()
                .frame(width: 360)
                .frame(maxHeight: .infinity)
                .clipped()
                .id(step) // re-fade on step change
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    if step != 6 {
                        Button(action: { step = max(0, step - 1) }) {
                            Text("← Back").font(CodepetTheme.body(12)).foregroundColor(CodepetTheme.mutedText)
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Button(action: skip) {
                        Text("Skip onboarding →").font(CodepetTheme.body(12)).foregroundColor(CodepetTheme.mutedText)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                ScrollView { stepBody.frame(maxWidth: 600, alignment: .leading) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer.frame(maxWidth: 600)
            }
            .padding(.horizontal, 64).padding(.vertical, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(CodepetTheme.surface)
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 1:
            heading("First — what should I call you?", "I'll use it when I walk you through your company.")
            label("Your name")
            textField("e.g. Mona", text: $d.name)
        case 2:
            heading("Which best describes you?", "This shapes how I explain each department to you.")
            OnboardingOptionList(options: OnboardingContent.roles, selectedKey: Binding(
                get: { d.role },
                set: { k in d.role = k; d.roleLabel = OnboardingContent.roles.first(where: { $0.key == k })?.label ?? "" }))
        case 3:
            heading("How hands-on are you with the code?", "So I know how deep to go on the technical side.")
            OnboardingOptionList(options: OnboardingContent.tech, selectedKey: $d.tech)
        case 4:
            heading("Now — what are you building?",
                    "A name and one clear sentence — that line is what I read to tailor your whole plan. Everything else is optional but sharpens it.")
            label("Project name"); textField("e.g. Codepet", text: $d.projName)
            label("In one sentence, what is it?")
            textField("A macOS companion that helps founders run their company with AI", text: $d.oneLiner)
            label("What kind of product is it? (optional)")
            chips(OnboardingContent.categories, selected: d.categories) { c in
                if d.categories.contains(c) { d.categories.removeAll { $0 == c } } else { d.categories.append(c) }
            }
            label("Who's it for? (optional)")
            textField("e.g. solo founders shipping their first product", text: $d.audience)
            label("Link (optional — website, repo, or Figma)")
            textField("https://", text: $d.link)
            label("Anything else to read? (optional — paste a pitch, README, or notes)")
            TextEditor(text: $d.notes)
                .font(CodepetTheme.body(14)).frame(minHeight: 74)
                .scrollContentBackground(.hidden)   // hide TextEditor's default backing (macOS 13+)
                .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
        case 5:
            heading("Where are you today?", "This sets your starting point on the roadmap.")
            OnboardingStageSlider(stageIndex: $d.stageIndex)
        case 6:
            OnboardingAnalysisView(projectName: d.projName, shown: anShown, done: anDone)
        default:
            OnboardingRevealView(name: d.name, roleLabel: d.roleLabel, stageIndex: d.stageIndex, reveal: reveal)
        }
    }

    // Progress + primary action.
    @ViewBuilder private var footer: some View {
        let pct = CGFloat(step + 1) / CGFloat(OnboardingContent.total)
        HStack(spacing: 14) {
            if step != 6 || anDone {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OnboardingContent.Palette.well).frame(height: 5)
                        Capsule().fill(CodepetTheme.accentPurple).frame(width: geo.size.width * pct, height: 5)
                    }
                }.frame(width: 150, height: 5)
                Text("Step \(step + 1) of \(OnboardingContent.total)")
                    .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
            } else if slow {
                Text("Still building your company…")
                    .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
            }
            Spacer()
            primaryButton
        }
        .padding(.top, 22)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 1: bigButton("Continue", enabled: !d.name.trimmed.isEmpty) { step = 2 }
        case 2: bigButton("Continue", enabled: !d.role.isEmpty) { step = 3 }
        case 3: bigButton("Continue", enabled: !d.tech.isEmpty) { step = 4 }
        case 4: bigButton("Continue", enabled: !d.projName.trimmed.isEmpty && !d.oneLiner.trimmed.isEmpty) { step = 5 }
        case 5: bigButton("Analyze my project", enabled: true) { startAnalysis() }
        case 6: if anDone { bigButton("See what I found", enabled: true) { step = 7 } }
        default: bigButton("See my company", enabled: true) { finish() }
        }
    }

    // MARK: actions

    private func startAnalysis() {
        step = 6; anShown = 0; anDone = false; slow = false; reveal = .empty
        let token = companyStore.onboardingToken
        let capturedBrief = brief()
        // stream the lines
        Task { @MainActor in
            for i in 0..<OnboardingContent.analysisLines.count {
                anShown = i + 1
                try? await Task.sleep(nanoseconds: 640_000_000)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            anDone = true
        }
        // run the real (fail-open) scaffold in parallel; min-display already covered by the lines
        Task { @MainActor in
            let slowTimer = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if !anDone { slow = true }
            }
            reveal = await companyStore.scaffoldFromOnboarding(brief: capturedBrief, token: token)
            slowTimer.cancel()
            slow = false
        }
    }

    private func finish() {
        let token = companyStore.onboardingToken
        Task { await companyStore.finishOnboarding(brief: brief(), token: token) }
    }
    private func skip() { Task { await companyStore.skipOnboarding() } }

    // MARK: small view helpers

    private func heading(_ h: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(h).font(.system(size: 20, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
            Text(sub).font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
        }.padding(.bottom, 4)
    }
    private func label(_ t: String) -> some View {
        Text(t).font(CodepetTheme.body(12)).fontWeight(.semibold)
            .foregroundColor(CodepetTheme.primaryText).padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func textField(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .textFieldStyle(.plain).font(CodepetTheme.body(14))
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
    }
    private func chips(_ items: [String], selected: [String], toggle: @escaping (String) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80, maximum: 200), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { c in
                let sel = selected.contains(c)
                Button { toggle(c) } label: {
                    Text(c).font(CodepetTheme.body(13)).fontWeight(sel ? .semibold : .medium)
                        .foregroundColor(sel ? OnboardingContent.Palette.accentDeep : CodepetTheme.bodyText)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(sel ? OnboardingContent.Palette.accentTint : OnboardingContent.Palette.surface2))
                        .overlay(Capsule().stroke(sel ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }
    private func bigButton(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Text(title).font(CodepetTheme.body(13)).fontWeight(.semibold).foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.accentPurple))
                .opacity(enabled ? 1 : 0.38)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
