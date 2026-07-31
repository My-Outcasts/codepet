// codepet/Views/Onboarding/OnboardingView.swift
import SwiftUI

/// First-run cinematic onboarding — faithful English-only port of the web
/// `Onboarding` (8 steps 0–7). Replaces the 6-field CompanyOnboardingView at
/// first run; the reveal/scaffold is fail-open (scaffoldRoadmap CF undeployed).
struct OnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState

    struct ObDraft {
        var name = "", role = "", roleLabel = "", tech = ""
        var projName = "", oneLiner = "", audience = "", link = "", notes = ""
        var categories: [String] = []
        var stageIndex = OnboardingContent.defaultStageIndex
        var pick = ""
    }

    @State private var step = 0
    @State private var d = ObDraft()
    @State private var anShown = 0
    @State private var anDone = false
    /// nil = the step-6 scaffold hasn't resolved yet; non-nil = resolved (a real
    /// summary, or `.empty` on fail-open). The step-7 gate waits for non-nil.
    @State private var reveal: OnboardingReveal?
    @State private var streamTask: Task<Void, Never>?
    @State private var scaffoldTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var skipHover = false

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
        .onAppear { if d.pick.isEmpty { d.pick = companyStore.company.companionId } }
    }

    // Two-panel card: art left (42% of the card, as on the web), form right.
    private var card: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                OnboardingArtPanel(step: step)
                    .frame(width: max(0, geo.size.width * 0.42))
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    // web `.ob-top` — Back only; Skip is pinned to the card's corner.
                    HStack {
                        if step != 6 {
                            Button(action: { step = max(0, step - 1) }) {
                                Text("← Back")
                                    .font(CodepetTheme.body(12.5))
                                    .foregroundColor(CodepetTheme.mutedText)
                                    .padding(.horizontal, 2).padding(.vertical, 6)
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: 600, minHeight: 22, alignment: .leading)

                    Group {
                        if step == 4 || step == 8 {   // tall: project + companion → top-align + scroll
                            ScrollView {
                                stepBody.frame(maxWidth: 600, alignment: .leading)
                                    .padding(.top, 8).padding(.bottom, 24)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {                       // vertically centered (.leading = leading + center-vertical)
                            stepBody.frame(maxWidth: 600, alignment: .leading)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }

                    footer.frame(maxWidth: 600)
                }
                .padding(.horizontal, 64).padding(.vertical, 46)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .topTrailing) {
                skipPill.padding(.top, 20).padding(.trailing, 24)
            }
        }
        .background(CodepetTheme.surface)
    }

    /// web `.ob .skip-pre` — a surface pill pinned to the top-right of the overlay.
    private var skipPill: some View {
        Button(action: skip) {
            Text("Skip onboarding →")
                .font(CodepetTheme.body(12, weight: .semibold))
                .foregroundColor(skipHover ? OnboardingContent.Palette.accentDeep : CodepetTheme.mutedText)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.surface))
                .overlay(Capsule().stroke(
                    skipHover ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline,
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { skipHover = h } }
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 1:
            heading("First — what should I call you?", "I'll use it when I walk you through your company.")
            label("Your name")
            ObTextField(placeholder: "e.g. Mona", text: $d.name, autofocus: true,
                        onSubmit: { if !d.name.trimmed.isEmpty { step = 2 } })
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
            label("Project name")
            ObTextField(placeholder: "e.g. Codepet", text: $d.projName)
            label("In one sentence, what is it?")
            ObTextField(placeholder: "A macOS companion that helps founders run their company with AI",
                        text: $d.oneLiner)
            label("What kind of product is it?", opt: "optional")
            chips(OnboardingContent.categories, selected: d.categories) { c in
                if d.categories.contains(c) { d.categories.removeAll { $0 == c } } else { d.categories.append(c) }
            }
            label("Who's it for?", opt: "optional")
            ObTextField(placeholder: "e.g. solo founders shipping their first product", text: $d.audience)
            label("Link", opt: "optional — website, repo, or Figma")
            ObTextField(placeholder: "https://", text: $d.link)
            label("Anything else to read?", opt: "optional — paste a pitch, README, or notes")
            ObTextEditor(placeholder: "Paste anything that helps me understand the product…", text: $d.notes)
        case 5:
            heading("Where are you today?", "This sets your starting point on the roadmap.")
            OnboardingStageSlider(stageIndex: $d.stageIndex)
        case 6:
            OnboardingAnalysisView(projectName: d.projName, shown: anShown, done: anDone)
        case 7:
            OnboardingRevealView(name: d.name, roleLabel: d.roleLabel, stageIndex: d.stageIndex, reveal: reveal ?? .empty)
        default:
            OnboardingCompanionStep(pickedId: $d.pick)
        }
    }

    // Progress + primary action.
    @ViewBuilder private var footer: some View {
        let pct = CGFloat(step + 1) / CGFloat(OnboardingContent.total)
        HStack(spacing: 14) {
            if step != 6 || (anDone && reveal != nil) {
                // web `.ob-prog` — 228px row: bar flexes, "Step n of m" keeps its width.
                HStack(spacing: 11) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(OnboardingContent.Palette.well).frame(height: 5)
                            Capsule().fill(CodepetTheme.accentPurple)
                                .frame(width: geo.size.width * pct, height: 5)
                                .animation(.easeOut(duration: 0.45), value: pct)
                        }
                        .frame(height: 5)
                    }
                    .frame(height: 5)
                    Text("Step \(step + 1) of \(OnboardingContent.total)")
                        .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
                        .fixedSize()
                }
                .frame(width: 228)
            } else if anDone {   // step 6, animation done but scaffold still resolving
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
        case 6: if anDone && reveal != nil { bigButton("See what I found", enabled: true) { step = 7 } }
        case 7: bigButton("Choose your companion", enabled: true) { step = 8 }
        default: bigButton("Start building", enabled: true) { finishWithCompanion() }
        }
    }

    // MARK: actions

    private func startAnalysis() {
        step = 6; anShown = 0; anDone = false; reveal = nil
        let token = companyStore.onboardingToken
        let capturedBrief = brief()
        streamTask?.cancel(); scaffoldTask?.cancel(); timeoutTask?.cancel()
        // Stream the analysis lines on a fixed cadence (the minimum display time).
        streamTask = Task { @MainActor in
            for i in 0..<OnboardingContent.analysisLines.count {
                anShown = i + 1
                try? await Task.sleep(nanoseconds: 640_000_000)
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            anDone = true
        }
        // Run the real (fail-open) scaffold in parallel; `reveal` stays nil until it
        // resolves so the step-7 gate waits for it (and "Still building…" can show).
        scaffoldTask = Task { @MainActor in
            let r = await companyStore.scaffoldFromOnboarding(brief: capturedBrief, token: token)
            if Task.isCancelled { return }
            reveal = r
        }
        // Hard safety net (mirrors the web's 20s timeout): never leave the founder stuck
        // on the analysis screen if the scaffold hangs. If no real reveal has arrived,
        // fall back to the empty (value-props) reveal so the step-7 gate can unlock.
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            if Task.isCancelled { return }
            if reveal == nil { reveal = .empty }
        }
    }

    private func finishWithCompanion() {
        streamTask?.cancel(); scaffoldTask?.cancel(); timeoutTask?.cancel()
        let token = companyStore.onboardingToken
        let id = d.pick.isEmpty ? companyStore.company.companionId : d.pick
        Task {
            await companyStore.setCompanion(id: id)
            appState.activeChar = id
            // Pass the store's current (already-enriched, by scaffoldFromOnboarding)
            // brief — NOT the local raw `brief()` draft — so finishOnboarding doesn't
            // clobber the enriched summary/audience/categories with unenriched values.
            // Steps 6-8 never edit brief fields, so company.brief is authoritative here;
            // if enrichment failed (fail-open) it already equals the raw brief, so this
            // is safe in all cases. EXCEPT: if "Start building" was reached while the
            // scaffold Task was still in-flight, the `scaffoldTask?.cancel()` above can
            // trip a cancellation guard in scaffoldFromOnboarding before it ever assigns
            // `company.brief = enriched`, leaving company.brief at its empty default.
            // Guard against persisting that empty brief (which would be worse than the
            // enrichment-clobber bug this fixed — it'd lose the user's step 1-5 inputs
            // too): fall back to the raw local draft whenever the store's brief carries
            // no signal.
            let finishBrief = companyStore.company.brief.hasAnySignal ? companyStore.company.brief : brief()
            await companyStore.finishOnboarding(brief: finishBrief, token: token, language: appState.uiLanguage)
        }
    }
    private func skip() {
        streamTask?.cancel(); scaffoldTask?.cancel(); timeoutTask?.cancel()
        Task { await companyStore.skipOnboarding() }
    }

    // MARK: small view helpers

    private func heading(_ h: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(h).font(CodepetTheme.body(20, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
            Text(sub).font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
        }.padding(.bottom, 4)
    }
    /// web `.ob label` (+ the lighter `.opt` run for "optional" hints).
    private func label(_ t: String, opt: String? = nil) -> some View {
        (Text(t)
            .font(CodepetTheme.body(12.5, weight: .semibold))
            .foregroundColor(CodepetTheme.primaryText)
         + (opt.map {
             Text(" \($0)")
                 .font(CodepetTheme.body(11.5, weight: .medium))
                 .foregroundColor(OnboardingContent.Palette.faint)
         } ?? Text(verbatim: "")))
            .padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func chips(_ items: [String], selected: [String], toggle: @escaping (String) -> Void) -> some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { c in
                let sel = selected.contains(c)
                Button { toggle(c) } label: {
                    Text(c).font(CodepetTheme.body(13)).fontWeight(sel ? .semibold : .medium)
                        .fixedSize()
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
            Text(title).font(CodepetTheme.body(13.5, weight: .semibold)).foregroundColor(.white)
                .padding(.horizontal, 22).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(CodepetTheme.accentPurple))
                .opacity(enabled ? 1 : 0.38)
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Onboarding chrome shared by the text inputs — web `.ob input.t` / `.ob textarea`:
/// surface-2 fill, hairline border, 12pt radius; on focus the border turns
/// accent-line with a 3px accent halo.
private struct ObFieldChrome: ViewModifier {
    let focused: Bool
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                focused ? OnboardingContent.Palette.accentLine : CodepetTheme.hairline, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 13.5).stroke(
                CodepetTheme.accentPurple.opacity(focused ? 0.12 : 0), lineWidth: 3)
                .padding(-1.5))
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Single-line onboarding input (web `.ob input.t`).
struct ObTextField: View {
    let placeholder: String
    @Binding var text: String
    var autofocus = false
    var onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(CodepetTheme.body(14))
            .foregroundColor(CodepetTheme.bodyText)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .modifier(ObFieldChrome(focused: focused))
            .onAppear {
                // Deferred so the field is mounted before focus moves to it.
                if autofocus { DispatchQueue.main.async { focused = true } }
            }
    }
}

/// Multi-line onboarding input (web `.ob textarea`) — same chrome, 74pt minimum,
/// with the web's placeholder (TextEditor has none of its own).
struct ObTextEditor: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text)
            .textEditorStyle(.plain)
            .font(CodepetTheme.body(14))
            .foregroundColor(CodepetTheme.bodyText)
            .focused($focused)
            .scrollContentBackground(.hidden)   // hide TextEditor's default backing
            .frame(minHeight: 74)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(CodepetTheme.body(14))
                        .foregroundColor(OnboardingContent.Palette.faint)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .modifier(ObFieldChrome(focused: focused))
    }
}
