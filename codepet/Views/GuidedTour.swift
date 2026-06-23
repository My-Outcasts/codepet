import SwiftUI
import Combine

// =============================================================================
// MARK: - Guided Tour: a character-narrated spotlight walkthrough
//
// Auto-runs the first time a user opens the Profile tab after onboarding (and
// re-runs from Profile → "Replay intro guide"). It dims the whole window and
// spotlights the *real* UI one feature at a time — switching tabs as it goes —
// with the chosen pet narrating. Auto-advances on a timer (pauses while the
// user hovers the caption) and offers Back / Next / Skip for self-pacing.
//
// Anchoring works by tagging real elements with `.tourAnchor(_:)`, which
// reports their frame up through a preference; the overlay (hosted in
// MainTabView) resolves each frame in its own coordinate space and cuts a hole
// in the dim layer over the current target.
// =============================================================================

/// Identifies a real on-screen element the tour can spotlight.
enum TourAnchorID: Hashable {
    case reflectionNav, tipsNav, dictionaryNav, profileAvatar
}

struct TourAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [TourAnchorID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourAnchorID: Anchor<CGRect>],
                       nextValue: () -> [TourAnchorID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    /// Tag this view as a tour target. Its frame is reported up to the overlay.
    func tourAnchor(_ id: TourAnchorID) -> some View {
        anchorPreference(key: TourAnchorPreferenceKey.self, value: .bounds) { [id: $0] }
    }

    /// Tag a sidebar nav button for the tabs the tour spotlights (no-op for the
    /// rest, which have no sidebar presence).
    @ViewBuilder
    func tourAnchor(forTab tab: AppState.Tab) -> some View {
        switch tab {
        case .reflection: self.tourAnchor(.reflectionNav)
        case .tips:       self.tourAnchor(.tipsNav)
        case .dictionary: self.tourAnchor(.dictionaryNav)
        default:          self
        }
    }
}

// MARK: - Stop model

struct TourStop: Identifiable {
    enum Kind { case welcome, spotlight, outro }
    let id = UUID()
    let kind: Kind
    /// Tab to switch to before showing this stop (nil = stay on the current tab).
    let tab: AppState.Tab?
    /// Element to spotlight (nil for the welcome / outro cards).
    let anchor: TourAnchorID?
    let title: String
    let body: String
}

// MARK: - Controller

/// Drives the tour: which stop is active, auto-advance timing, and pause. Owned
/// by MainTabView as a `@StateObject` and injected into the environment so the
/// Profile tab can start it and the overlay can render it.
final class TourController: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var index = 0
    /// 0…1 elapsed within the current spotlight stop (drives the progress bar).
    @Published private(set) var progress: Double = 0

    /// Invoked when the tour ends (finish or skip) — used to set the seen-flag.
    var onFinish: (() -> Void)?

    private(set) var stops: [TourStop] = []
    private var ticker: Timer?
    private var isPaused = false
    private let autoAdvance: TimeInterval = 6.0
    private let tick: TimeInterval = 0.05

    var currentStop: TourStop? {
        guard isActive, stops.indices.contains(index) else { return nil }
        return stops[index]
    }
    var isLast: Bool { index >= stops.count - 1 }

    func configure(character: PetCharacter, language: AppLanguage) {
        stops = TourController.makeStops(character: character, language: language)
    }

    func start() {
        guard !stops.isEmpty else { return }
        index = 0
        isPaused = false
        isActive = true
        beginStop()
    }

    func next() {
        if index + 1 < stops.count { index += 1; beginStop() } else { finish() }
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
        beginStop()
    }

    func finish() {
        stopTicker()
        isActive = false
        onFinish?()
    }

    /// Pause/resume auto-advance (called as the user hovers the caption).
    func setPaused(_ paused: Bool) {
        guard isActive else { return }
        isPaused = paused
        if paused {
            stopTicker()
        } else if currentStop?.kind == .spotlight {
            startTicker()
        }
    }

    private func beginStop() {
        progress = 0
        stopTicker()
        // Only spotlight stops auto-advance; welcome / outro wait for the user.
        if currentStop?.kind == .spotlight && !isPaused { startTicker() }
    }

    private func startTicker() {
        stopTicker()
        // Timer fires on the main run loop, so mutating @Published here is safe.
        ticker = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.progress = min(1, self.progress + self.tick / self.autoAdvance)
            if self.progress >= 1 { self.next() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: stop copy

    static func makeStops(character: PetCharacter, language: AppLanguage) -> [TourStop] {
        let vi = language == .vi
        func t(_ en: String, _ viText: String) -> String { vi ? viText : en }
        return [
            TourStop(kind: .welcome, tab: nil, anchor: nil,
                     title: character.name,
                     body: character.greeting.first ?? "..."),
            TourStop(kind: .spotlight, tab: .reflection, anchor: .reflectionNav,
                     title: t("Reflection", "Nhật ký"),
                     body: t("Your AI journal of every coding session. Code in Claude Code and I'll write up what you built, what worked, and what to try next.",
                             "Nhật ký AI cho mỗi phiên code. Bạn code trong Claude Code, mình sẽ tóm tắt lại bạn đã làm gì, điều gì hiệu quả và nên thử gì tiếp theo.")),
            TourStop(kind: .spotlight, tab: .tips, anchor: .tipsNav,
                     title: t("Tips", "Mẹo"),
                     body: t("Bite-size practice lessons and challenges. Earn XP and coins as you go — no editor needed to start.",
                             "Bài học và thử thách ngắn gọn. Kiếm XP và xu khi luyện tập — không cần mở editor.")),
            TourStop(kind: .spotlight, tab: .dictionary, anchor: .dictionaryNav,
                     title: t("Dictionary", "Từ điển"),
                     body: t("Stuck on a term? Look up any coding word here, grouped by topic and fully searchable.",
                             "Gặp thuật ngữ lạ? Tra bất kỳ từ nào về lập trình ở đây, phân theo chủ đề và tìm kiếm được.")),
            TourStop(kind: .spotlight, tab: .profile, anchor: .profileAvatar,
                     title: t("Profile", "Hồ sơ"),
                     body: t("Tap me up here anytime to open Profile — swap pets, change my voice, and manage your account.",
                             "Chạm vào mình ở đây bất cứ lúc nào để mở Hồ sơ — đổi pet, đổi giọng và quản lý tài khoản.")),
            TourStop(kind: .outro, tab: nil, anchor: nil,
                     title: character.name,
                     body: t("You're all set! Pick any tab and dive in — I'll be right here. ",
                             "Xong rồi! Chọn tab bất kỳ và bắt đầu thôi — mình luôn ở đây. ") + character.signatureEmojis),
        ]
    }
}

// MARK: - Overlay

/// The dim + spotlight + caption layer. Hosted full-window in MainTabView.
struct GuidedTourOverlay: View {
    /// Resolved frame of the current anchor in the overlay's coordinate space
    /// (nil while the target tab is still mounting, or for welcome / outro).
    let rect: CGRect?
    let containerSize: CGSize
    @ObservedObject var tour: TourController
    let character: PetCharacter
    @Environment(\.uiLanguage) private var uiLanguage

    private let ink = Color(hex: "#2D2B26")
    @State private var pulse = false

    var body: some View {
        ZStack {
            dimLayer
                .ignoresSafeArea()

            if let stop = tour.currentStop {
                switch stop.kind {
                case .welcome, .outro:
                    centeredCard(stop)
                        .position(x: containerSize.width / 2, y: containerSize.height / 2)
                case .spotlight:
                    if let rect = rect {
                        spotlightRing(rect)
                        captionCard(stop)
                            .frame(width: captionWidth)
                            .position(captionCenter(for: rect))
                    } else {
                        // Target tab still rendering — show the caption centered
                        // until its frame resolves, then it snaps to the element.
                        captionCard(stop)
                            .frame(width: captionWidth)
                            .position(x: containerSize.width / 2, y: containerSize.height / 2)
                    }
                }
            }
        }
        .onAppear { pulse = true }
    }

    // MARK: dim + spotlight

    private var dimLayer: some View {
        Group {
            if tour.currentStop?.kind == .spotlight, let rect = rect {
                Color.black.opacity(0.55)
                    .reverseMask {
                        RoundedRectangle(cornerRadius: 14)
                            .frame(width: rect.width + 16, height: rect.height + 16)
                            .position(x: rect.midX, y: rect.midY)
                    }
            } else {
                Color.black.opacity(0.55)
            }
        }
    }

    private func spotlightRing(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(character.color, lineWidth: 3)
            .frame(width: rect.width + 16, height: rect.height + 16)
            .scaleEffect(pulse ? 1.04 : 1.0)
            .shadow(color: character.color.opacity(0.6), radius: 10)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .allowsHitTesting(false)
    }

    // MARK: caption (spotlight stops)

    private let captionWidth: CGFloat = 320

    private func captionCard(_ stop: TourStop) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(tour.index)/\(tour.stops.count - 1)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ink.opacity(0.45))
                Spacer()
                skipButton
            }

            HStack(spacing: 10) {
                avatar(40)
                Text(stop.title)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(character.color)
            }

            Text(stop.body)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(ink.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Auto-advance progress.
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(character.color.opacity(0.15))
                    Capsule().fill(character.color)
                        .frame(width: g.size.width * tour.progress)
                }
            }
            .frame(height: 4)

            HStack {
                if tour.index > 0 {
                    Button(action: { tour.back() }) {
                        Text(uiLanguage == .vi ? "Quay lại" : "Back")
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: Color.white, foreground: ink.opacity(0.7), borderColor: ink.opacity(0.25),
                        paddingH: 14, paddingV: 8, blockSize: 2, steps: 2, borderWidth: 2, shadowOffset: 2,
                        font: .system(size: 12, weight: .semibold)))
                }
                Spacer()
                Button(action: { tour.next() }) {
                    Text(tour.isLast ? (uiLanguage == .vi ? "Xong" : "Done")
                                     : (uiLanguage == .vi ? "Tiếp →" : "Next →"))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: character.color, foreground: .white,
                    paddingH: 18, paddingV: 8, blockSize: 2, steps: 2, borderWidth: 2, shadowOffset: 2,
                    font: .system(size: 12, weight: .semibold)))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(character.color.opacity(0.5), lineWidth: 2))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onHover { tour.setPaused($0) }
    }

    // MARK: welcome / outro card

    private func centeredCard(_ stop: TourStop) -> some View {
        let isOutro = stop.kind == .outro
        return VStack(spacing: 16) {
            avatar(92)
            VStack(spacing: 4) {
                Text(stop.title)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(character.color)
                Text(character.badge)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(ink.opacity(0.55))
            }
            speechBubble(stop.body)
            if !isOutro {
                Text(uiLanguage == .vi
                     ? "Để mình dẫn bạn đi một vòng — chỉ khoảng một phút."
                     : "Let me show you around — about a minute.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(ink.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                if !isOutro {
                    Button(action: { tour.finish() }) {
                        Text(uiLanguage == .vi ? "Bỏ qua" : "Skip")
                    }
                    .buttonStyle(PixelButtonStyle(
                        fill: Color.white, foreground: ink.opacity(0.7), borderColor: ink.opacity(0.25),
                        paddingH: 16, paddingV: 9, blockSize: 2, steps: 2, borderWidth: 2, shadowOffset: 2,
                        font: .system(size: 13, weight: .semibold)))
                }
                Button(action: { isOutro ? tour.finish() : tour.next() }) {
                    Text(isOutro ? (uiLanguage == .vi ? "Bắt đầu thôi" : "Get started")
                                 : (uiLanguage == .vi ? "Bắt đầu" : "Start tour"))
                }
                .buttonStyle(PixelButtonStyle(
                    fill: character.color, foreground: .white,
                    paddingH: 20, paddingV: 9, blockSize: 2, steps: 2, borderWidth: 2, shadowOffset: 2,
                    font: .system(size: 13, weight: .semibold)))
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(character.color.opacity(0.5), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
    }

    // MARK: shared bits

    private var skipButton: some View {
        Button(action: { tour.finish() }) {
            Text(uiLanguage == .vi ? "Bỏ qua" : "Skip")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ink.opacity(0.5))
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(character.color.opacity(0.18))
            CharacterImage(character.id, size: size * 0.7)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22)
            .stroke(character.color.opacity(0.45), lineWidth: 2))
    }

    private func speechBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ink.opacity(0.85))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 360)
            .pixelBox(fill: character.color.opacity(0.12), borderColor: character.color,
                      shadowOffset: 2, blockSize: 2, steps: 2, borderWidth: 2)
    }

    // MARK: caption placement

    /// Place the caption beside the spotlight: to the right when the target is
    /// on the left half (the sidebar), otherwise to the left — clamped on-screen.
    private func captionCenter(for rect: CGRect) -> CGPoint {
        let estHeight: CGFloat = 230
        let placeRight = rect.midX < containerSize.width / 2
        let x = placeRight
            ? min(rect.maxX + 16 + captionWidth / 2, containerSize.width - captionWidth / 2 - 12)
            : max(rect.minX - 16 - captionWidth / 2, captionWidth / 2 + 12)
        let y = min(max(rect.midY, estHeight / 2 + 12), containerSize.height - estHeight / 2 - 12)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - reverse mask helper

extension View {
    /// Punch a hole shaped like `mask` out of this view.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
