// codepet/Views/Onboarding/OnboardingStageSlider.swift
import SwiftUI

/// Pure mapping from a pointer x-position to the nearest stage index. Extracted
/// for unit testing; the view calls it on drag.
enum StageSliderMath {
    static func stageIndex(atX x: CGFloat, width: CGFloat, count: Int) -> Int {
        guard width > 0, count > 1 else { return 0 }
        let f = max(0, min(1, x / width))
        return Int((f * CGFloat(count - 1)).rounded())
    }

    /// Usable track span inside the thumb inset (web `.sb-track { inset: 0 15px }`).
    static func trackWidth(container: CGFloat, inset: CGFloat) -> CGFloat {
        max(1, container - inset * 2)
    }

    /// Centre x of a stage, in container coordinates. Drawing and hit-testing must both
    /// go through this + `trackWidth`; using the full width for one and the inset track
    /// for the other makes the thumb lag the cursor.
    static func centerX(forIndex index: Int, container: CGFloat, inset: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return inset }
        let track = trackWidth(container: container, inset: inset)
        let frac = CGFloat(index) / CGFloat(count - 1)
        return inset + track * frac
    }
}

/// The stage step's draggable ruler (web `StageBar` + `.rngticks` + `.obnote`).
/// Major ticks at each stage, minor ticks between; drag or ← → to change.
struct OnboardingStageSlider: View {
    @Binding var stageIndex: Int
    @State private var dragging = false
    @FocusState private var focused: Bool

    private let stages = OnboardingContent.stages
    private var n: Int { stages.count }
    private let step = 4 // minor ticks between stages
    /// Web `.sb-track { inset: 0 15px }` — half the 26pt thumb plus a little, so the
    /// thumb is fully inside the panel at both ends instead of being sliced by the edge.
    private let trackInset: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                // Everything is positioned against the inset track, not the full width;
                // the drag mapping below uses the same span so the thumb tracks the cursor.
                let track = StageSliderMath.trackWidth(container: geo.size.width, inset: trackInset)
                let frac = n > 1 ? CGFloat(stageIndex) / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    // base track
                    Capsule().fill(OnboardingContent.Palette.well)
                        .frame(width: track, height: 3)
                        .offset(x: trackInset)
                    // progress
                    Capsule()
                        .fill(LinearGradient(colors: [CodepetTheme.accentPurple, OnboardingContent.Palette.accentDeep],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, track * frac), height: 3)
                        .offset(x: trackInset)
                    // ticks
                    ForEach(0...((n - 1) * step), id: \.self) { t in
                        let tf = CGFloat(t) / CGFloat((n - 1) * step)
                        let isMajor = t % step == 0
                        let filled = tf <= frac + 0.001
                        Capsule()
                            .fill(filled ? (isMajor ? OnboardingContent.Palette.accentDeep : CodepetTheme.accentPurple)
                                         : (isMajor ? OnboardingContent.Palette.tickMajor
                                                    : OnboardingContent.Palette.tickMinor))
                            .frame(width: isMajor ? 2.5 : 2, height: isMajor ? 18 : 9)
                            .position(x: trackInset + track * tf, y: 24)
                    }
                    // thumb — focus shows here as a soft halo (web
                    // `.stagebar:focus-visible .sb-thumb { box-shadow: 0 0 0 5px … }`),
                    // never as a rectangle around the whole control.
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(CodepetTheme.accentPurple, lineWidth: 3))
                        .overlay(Circle().fill(CodepetTheme.accentPurple).padding(6))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if focused {
                                Circle()
                                    .stroke(CodepetTheme.accentPurple.opacity(0.18), lineWidth: 5)
                                    .frame(width: 31, height: 31)
                            }
                        }
                        .shadow(color: CodepetTheme.accentPurple.opacity(0.4), radius: 6, y: 4)
                        .position(x: trackInset + track * frac, y: 24)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        stageIndex = StageSliderMath.stageIndex(atX: v.location.x - trackInset,
                                                               width: track, count: n)
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 48)
            .focusable(true)
            .focused($focused)
            // Web `.stagebar { outline: none }` — suppress the system focus ring; the
            // thumb halo above is the focus affordance.
            .focusEffectDisabled()
            .onMoveCommand { dir in
                if dir == .right { stageIndex = min(n - 1, stageIndex + 1) }
                if dir == .left { stageIndex = max(0, stageIndex - 1) }
            }

            // stage labels
            HStack {
                ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                    Text(s)
                        .font(CodepetTheme.body(10))
                        .foregroundColor(i == stageIndex ? OnboardingContent.Palette.accentDeep : OnboardingContent.Palette.faint)
                        .fontWeight(i == stageIndex ? .bold : .regular)
                        .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : (i == n - 1 ? .trailing : .center))
                }
            }

            // active-stage note
            Text(OnboardingContent.stageNotes[stageIndex])
                .font(CodepetTheme.body(13))
                .foregroundColor(CodepetTheme.mutedText)
                .padding(.leading, 13)
                .overlay(Rectangle().fill(OnboardingContent.Palette.accentLine).frame(width: 2), alignment: .leading)
                .padding(.top, 10)
        }
    }
}
