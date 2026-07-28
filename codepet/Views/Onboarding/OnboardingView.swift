// codepet/Views/Onboarding/OnboardingView.swift
import SwiftUI

/// Pure layout maths for the onboarding chrome. The web sizes these fluidly (a
/// percentage or a CSS `clamp()`); the first native port froze them at the values
/// they happen to take at the ~860pt design width, which is why the flow degraded
/// as the window grew. Extracted for unit testing, like `StageSliderMath`.
enum OnboardingLayout {
    /// Web: `.ob-art { width: 42% }` — a straight percentage with no ceiling, so the
    /// art keeps its share of the window at any size. Only a lower bound is applied,
    /// to keep the panel legible (and the form solvent) at the 560pt minimum window.
    ///
    /// An upper clamp was tried and removed: capping at 620 put the panel at 24% of a
    /// 2560pt display, which is the same collapsed composition the fixed 360pt width
    /// caused — just less severe. Verified against a render, not arithmetic.
    static func artWidth(container: CGFloat) -> CGFloat {
        max(320, container * 0.42)
    }
    /// Web: `.ob-cold-in h1 { font-size: clamp(34px, 4vw, 52px) }`.
    static func coldHeadline(container: CGFloat) -> CGFloat {
        min(52, max(34, container * 0.04))
    }
    /// Web: `.ob-cold-in { margin-left: clamp(40px, 9vw, 150px) }`.
    static func coldLeading(container: CGFloat) -> CGFloat {
        min(150, max(40, container * 0.09))
    }
}

/// First-run cinematic onboarding — English-only port of the web `Onboarding`,
/// 8 steps 0–7: cold open → name → role → tech → project → stage → analysis → reveal.
/// Replaces the 6-field CompanyOnboardingView at first run; the reveal/scaffold is
/// fail-open (scaffoldRoadmap CF undeployed).
///
/// Deliberate divergence from the web: the web's 9th step, the companion picker, is
/// cut. Choosing a pet before meeting any of them is a decision without information,
/// and it sat between the reveal and getting to work. The company keeps its default
/// companion and the picker lives in Settings.
struct OnboardingView: View {
    @EnvironmentObject var companyStore: CompanyStore
    @EnvironmentObject var appState: AppState

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
    /// nil = the step-6 scaffold hasn't resolved yet; non-nil = resolved (a real
    /// summary, or `.empty` on fail-open). The step-7 gate waits for non-nil.
    @State private var reveal: OnboardingReveal?
    @State private var streamTask: Task<Void, Never>?
    @State private var scaffoldTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?
    @FocusState private var nameFocused: Bool

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
        .onChange(of: step) { newStep in
            // Autofocus the name field when entering step 1 (deferred so the field is mounted).
            if newStep == 1 { DispatchQueue.main.async { nameFocused = true } }
        }
    }

    /// Web `.ob-body.tall` — the project step top-aligns instead of centring.
    private var isTallStep: Bool { step == 4 }

    // Two-panel card, mirroring the web `.obcard`:
    //   `.ob-art  { flex: none; width: 42% }`      — proportional, not a fixed width
    //   `.ob-main { flex: 1; overflow: auto }`     — every step scrolls
    //   `.ob-top / .ob-body / .ob-foot { max-width: 600px }`
    // Skip is deliberately NOT in the top row: on the web it's `.skip-pre`, absolutely
    // positioned against the whole screen, so Back never gets pushed away from it.
    private var card: some View {
        GeometryReader { card in
            HStack(spacing: 0) {
                // `.ob-art span` — layers crossfade over 1.1s while the incoming one
                // settles from scale(1.07) to 1 over 7s. The web also drifts these with
                // the pointer; not ported (distracting in use).
                // The .id drives the ZStack transition, so only two layers are ever live.
                ZStack {
                    OnboardingArtLayer(
                        name: OnboardingContent.stepArt[min(step, OnboardingContent.stepArt.count - 1)],
                        width: OnboardingLayout.artWidth(container: card.size.width),
                        grade: OnboardingContent.stepGrade[min(step, OnboardingContent.stepGrade.count - 1)]
                    )
                    .id(step)
                    .transition(.opacity)
                }
                .animation(.easeInOut(duration: OnboardingMotion.artCrossfade), value: step)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    // `.ob-top` — Back only, held to the same 600pt measure as the body
                    // and footer so the controls stay with the content on a wide window.
                    HStack {
                        if step != 6 {
                            Button(action: { step = max(0, step - 1) }) {
                                Text("← Back").font(CodepetTheme.body(12)).foregroundColor(CodepetTheme.mutedText)
                            }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: 600)
                    .padding(.bottom, 8)

                    // `.ob-main { overflow: auto }` + `.ob-body { justify-content: center }`:
                    // the step column is centred while it fits and scrolls once it doesn't,
                    // so a long reveal (server-driven task count) can always reach the footer.
                    GeometryReader { area in
                        ScrollView {
                            // .id(step) gives each step fresh views so the `riseIn`
                            // stagger replays on advance, as new DOM nodes do on the web.
                            VStack(alignment: .leading, spacing: 0) { stepBody }
                                .id(step)
                                .frame(maxWidth: 600, alignment: .leading)
                                .frame(minHeight: area.size.height,
                                       alignment: isTallStep ? .top : .center)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    footer.frame(maxWidth: 600)
                }
                .padding(.horizontal, 64).padding(.vertical, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topTrailing) { skipPill }
        }
        .background(CodepetTheme.surface)
    }

    /// Web `.ob .skip-pre` — a pill pinned to the card's top-trailing corner.
    private var skipPill: some View {
        Button(action: skip) {
            Text("Skip onboarding →")
                .font(CodepetTheme.body(12)).fontWeight(.semibold)
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(CodepetTheme.surface))
                .overlay(Capsule().stroke(CodepetTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.top, 20).padding(.trailing, 24)
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 1:
            heading("First — what should I call you?", "I'll use it when I walk you through your company.")
            label("Your name")
            textField("e.g. Mona", text: $d.name)
                .focused($nameFocused)
                .onSubmit { if !d.name.trimmed.isEmpty { step = 2 } }
        case 2:
            heading("Which best describes you?", "This shapes how I explain each department to you.")
            OnboardingOptionList(options: OnboardingContent.roles, selectedKey: Binding(
                get: { d.role },
                set: { k in d.role = k; d.roleLabel = OnboardingContent.roles.first(where: { $0.key == k })?.label ?? "" }))
                .riseIn(delay: OnboardingMotion.stepRestDelay)
        case 3:
            heading("How hands-on are you with the code?", "So I know how deep to go on the technical side.")
            OnboardingOptionList(options: OnboardingContent.tech, selectedKey: $d.tech)
                .riseIn(delay: OnboardingMotion.stepRestDelay)
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
            .riseIn(delay: OnboardingMotion.stepRestDelay)
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
                .riseIn(delay: OnboardingMotion.stepRestDelay)
        case 5:
            heading("Where are you today?", "This sets your starting point on the roadmap.")
            OnboardingStageSlider(stageIndex: $d.stageIndex)
                .riseIn(delay: OnboardingMotion.stepRestDelay)
        case 6:
            OnboardingAnalysisView(projectName: d.projName, shown: anShown, done: anDone)
                .riseIn(delay: OnboardingMotion.stepRestDelay)
        default:   // 7 — the reveal is the last screen; "Start building" finishes here.
            OnboardingRevealView(name: d.name, roleLabel: d.roleLabel, stageIndex: d.stageIndex, reveal: reveal ?? .empty)
                .riseIn(delay: OnboardingMotion.stepRestDelay)
        }
    }

    // Progress + primary action.
    @ViewBuilder private var footer: some View {
        let pct = CGFloat(step + 1) / CGFloat(OnboardingContent.total)
        HStack(spacing: 14) {
            if step != 6 || (anDone && reveal != nil) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OnboardingContent.Palette.well).frame(height: 5)
                        Capsule().fill(CodepetTheme.accentPurple).frame(width: geo.size.width * pct, height: 5)
                    }
                }.frame(width: 150, height: 5)
                Text("Step \(step + 1) of \(OnboardingContent.total)")
                    .font(CodepetTheme.body(11)).foregroundColor(OnboardingContent.Palette.faint)
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
        default: bigButton("Start building", enabled: true) { finish() }
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

    private func finish() {
        streamTask?.cancel(); scaffoldTask?.cancel(); timeoutTask?.cancel()
        let token = companyStore.onboardingToken
        Task {
            // No companion picker in the flow any more, so nothing to persist here —
            // the company keeps its default companion. Still mirror it onto appState so
            // the app opens with the same character the store holds (Settings changes it).
            appState.activeChar = companyStore.company.companionId
            // Pass the store's current (already-enriched, by scaffoldFromOnboarding)
            // brief — NOT the local raw `brief()` draft — so finishOnboarding doesn't
            // clobber the enriched summary/audience/categories with unenriched values.
            // Steps 6-7 never edit brief fields, so company.brief is authoritative here;
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

    // `.ob-body > *` staggering: h2 at 40ms, p at .12s, everything after at .2s.
    private func heading(_ h: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(h).font(CodepetTheme.body(20, weight: .semibold)).foregroundColor(CodepetTheme.primaryText)
                .riseIn(delay: OnboardingMotion.stepHeadingDelay)
            Text(sub).font(CodepetTheme.body(14)).foregroundColor(CodepetTheme.bodyText)
                .riseIn(delay: OnboardingMotion.stepSubDelay)
        }.padding(.bottom, 4)
    }
    private func label(_ t: String) -> some View {
        Text(t).font(CodepetTheme.body(12)).fontWeight(.semibold)
            .foregroundColor(CodepetTheme.primaryText).padding(.top, 18).padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .riseIn(delay: OnboardingMotion.stepRestDelay)
    }
    private func textField(_ ph: String, text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .textFieldStyle(.plain).font(CodepetTheme.body(14))
            .padding(.horizontal, 14).padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(OnboardingContent.Palette.surface2))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CodepetTheme.hairline, lineWidth: 1))
            .riseIn(delay: OnboardingMotion.stepRestDelay)
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
