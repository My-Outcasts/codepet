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

    /// The track's padding, and the ONE place it is written down.
    ///
    /// It used to be a `let inset: CGFloat = 15` inside the track's `GeometryReader`, which
    /// meant the labels — laid out separately — had no way to agree with it, and didn't.
    static let trackInset: CGFloat = 15

    /// The x of a point `f` (0...1) along the track, in the slider's coordinate space.
    static func x(atFraction f: CGFloat, width: CGFloat) -> CGFloat {
        trackInset + max(0, width - trackInset * 2) * f
    }

    /// The x of stage `i`'s major tick — and therefore of the label that names it.
    ///
    /// Ticks and labels both resolve through this, so they cannot drift apart again without
    /// someone deleting the call. That is the real repair; the label layout was only the
    /// symptom of the two geometries being written out twice.
    static func tickX(stage i: Int, width: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return trackInset }
        return x(atFraction: CGFloat(i) / CGFloat(count - 1), width: width)
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
                // web `.sb-track` is inset each side so the thumb never clips. The inset lives
                // on `StageSliderMath` because the labels below need the same number; it stays
                // 15 now the thumb is 18pt rather than 26.
                let inset = StageSliderMath.trackInset
                let w = max(0, geo.size.width - inset * 2)
                let frac = n > 1 ? CGFloat(stageIndex) / CGFloat(n - 1) : 0
                ZStack(alignment: .leading) {
                    // base track
                    Capsule().fill(OnboardingContent.Palette.well)
                        .frame(width: w, height: 3)
                        .position(x: inset + w / 2, y: 24)
                    // progress
                    Capsule()
                        .fill(LinearGradient(colors: [CodepetTheme.accentPurple, OnboardingContent.Palette.accentDeep],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, w * frac), height: 3)
                        .position(x: inset + (w * frac) / 2, y: 24)
                    // ticks
                    ForEach(0...((n - 1) * step), id: \.self) { t in
                        let tf = CGFloat(t) / CGFloat((n - 1) * step)
                        let isMajor = t % step == 0
                        let filled = tf <= frac + 0.001
                        Capsule()
                            .fill(filled ? (isMajor ? OnboardingContent.Palette.accentDeep : CodepetTheme.accentPurple)
                                         // The unfilled ticks were the ONE pair of hardcoded hexes in this
                                         // view. They are the web `StageBar`'s, chosen against onboarding's
                                         // light `#F7F5FC`; in dark mode they stayed tan against near-black
                                         // while every neighbouring colour moved. Light values unchanged.
                                         : Color.dyn(isMajor ? "#cbc3b2" : "#dad3c5",
                                                     isMajor ? "#443a63" : "#332c4d"))
                            .frame(width: isMajor ? 2.5 : 2, height: isMajor ? 18 : 9)
                            .position(x: inset + w * tf, y: 24)
                    }
                    // Thumb. 18pt rather than 26 with a 6pt glow: at the old size the halo
                    // covered the tick on either side of the one it points at, so the control
                    // obscured the very position it reports. The drag target is unchanged —
                    // the gesture is on the ZStack's `contentShape`, not on this circle.
                    Circle()
                        .fill(CodepetTheme.accentPurple)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .position(x: inset + w * frac, y: 24)
                }
                .frame(width: geo.size.width, height: 48)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        stageIndex = StageSliderMath.stageIndex(atX: v.location.x - inset, width: w, count: n)
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 48)
            .focusable(true)
            .onMoveCommand { dir in
                if dir == .right { stageIndex = min(n - 1, stageIndex + 1) }
                if dir == .left { stageIndex = max(0, stageIndex - 1) }
            }

            // Stage labels, each centred on the tick it names.
            //
            // This was an `HStack` of six equal-width cells across the FULL width, which is a
            // different geometry from the ticks: those are laid out across `width - inset * 2`
            // and start 15pt in. The two disagree by up to ~46pt at 1100pt wide, so "Launched"
            // sat nearly half a stage to the left of the tick it labels — the interior labels
            // drifted outward from the centre in both directions, and only the first and last
            // looked right, by the accident of being edge-aligned.
            //
            // The ends stay edge-aligned deliberately: centring "Just an idea" on a tick 15pt
            // from the edge would hang it off the left of the container.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                        let isEnd = (i == 0 || i == n - 1)
                        Text(s)
                            .font(CodepetTheme.body(10.5))
                            .foregroundColor(i == stageIndex ? OnboardingContent.Palette.accentDeep
                                                            : OnboardingContent.Palette.faint)
                            .fontWeight(i == stageIndex ? .bold : .regular)
                            .fixedSize()
                            // A full-width frame is how the ends align to the container edge
                            // without measuring the text; the interior labels are simply
                            // centred on their tick's x.
                            .frame(width: isEnd ? geo.size.width : nil,
                                   alignment: i == 0 ? .leading : .trailing)
                            .position(x: isEnd ? geo.size.width / 2
                                               : StageSliderMath.tickX(stage: i,
                                                                       width: geo.size.width,
                                                                       count: n),
                                      y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 14)

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
