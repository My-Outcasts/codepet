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
}

/// The stage step's draggable ruler (web `StageBar` + `.rngticks` + `.obnote`).
/// Major ticks at each stage, minor ticks between; drag or ← → to change.
struct OnboardingStageSlider: View {
    @Binding var stageIndex: Int
    @State private var dragging = false

    private let stages = OnboardingContent.stages
    private var n: Int { stages.count }
    private let step = 4 // minor ticks between stages

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let w = geo.size.width
                let frac = n > 1 ? CGFloat(stageIndex) / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    // base track
                    Capsule().fill(OnboardingContent.Palette.well).frame(height: 3)
                    // progress
                    Capsule()
                        .fill(LinearGradient(colors: [CodepetTheme.accentPurple, OnboardingContent.Palette.accentDeep],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, w * frac), height: 3)
                    // ticks
                    ForEach(0...((n - 1) * step), id: \.self) { t in
                        let tf = CGFloat(t) / CGFloat((n - 1) * step)
                        let isMajor = t % step == 0
                        let filled = tf <= frac + 0.001
                        Capsule()
                            .fill(filled ? (isMajor ? OnboardingContent.Palette.accentDeep : CodepetTheme.accentPurple)
                                         : Color(hex: isMajor ? "#cbc3b2" : "#dad3c5"))
                            .frame(width: isMajor ? 2.5 : 2, height: isMajor ? 18 : 9)
                            .position(x: w * tf, y: 24)
                    }
                    // thumb
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().stroke(CodepetTheme.accentPurple, lineWidth: 3))
                        .overlay(Circle().fill(CodepetTheme.accentPurple).padding(6))
                        .frame(width: 26, height: 26)
                        .shadow(color: CodepetTheme.accentPurple.opacity(0.4), radius: 6, y: 4)
                        .position(x: w * frac, y: 24)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        stageIndex = StageSliderMath.stageIndex(atX: v.location.x, width: w, count: n)
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 48)
            .focusable(true)
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
