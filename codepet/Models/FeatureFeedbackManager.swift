import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Feature

/// A feature we collect first-experience feedback on. The prompt fires once,
/// ever, the first time the user finishes the feature, and is then suppressed
/// via a `cp_feedback_<key>_asked` UserDefaults flag.
enum FeedbackFeature: String, CaseIterable, Identifiable {
    case exercise
    case lesson
    case companionChat
    case reflection
    case skillMastered
    case projectHealth
    case dictionary

    var id: String { rawValue }

    /// UserDefaults key marking this feature's prompt as already shown.
    var askedKey: String { "cp_feedback_\(rawValue)_asked" }

    /// SF Symbol shown in the prompt's eyebrow row.
    var icon: String {
        switch self {
        case .exercise:      return "book.fill"
        case .lesson:        return "graduationcap.fill"
        case .companionChat: return "bubble.left.fill"
        case .reflection:    return "sparkles"
        case .skillMastered: return "trophy.fill"
        case .projectHealth: return "heart.text.square.fill"
        case .dictionary:    return "character.book.closed.fill"
        }
    }

    /// Short eyebrow label above the question.
    func eyebrow(_ language: AppLanguage) -> String {
        language == .vi ? "Đánh giá" : "Review rating"
    }

    /// The prompt's question, localized.
    func question(_ language: AppLanguage) -> String {
        switch self {
        case .exercise:
            return language == .vi ? "Bài tập đầu tiên thế nào?" : "How was your first exercise?"
        case .lesson:
            return language == .vi ? "Bài học đầu tiên thế nào?" : "How was your first lesson?"
        case .companionChat:
            return language == .vi ? "Trò chuyện với bạn đồng hành ra sao?" : "How was chatting with your companion?"
        case .reflection:
            return language == .vi ? "Phần nhìn lại phiên code thế nào?" : "How was your session reflection?"
        case .skillMastered:
            return language == .vi ? "Cảm giác thành thạo kỹ năng đầu tiên thế nào?" : "How did mastering your first skill feel?"
        case .projectHealth:
            return language == .vi ? "Phần Sức khoẻ dự án có hữu ích không?" : "How useful was the project health check?"
        case .dictionary:
            return language == .vi ? "Từ điển có dễ hiểu không?" : "Was the dictionary helpful?"
        }
    }
}

// MARK: - Manager

/// Drives the first-experience feedback toast. Registered as an
/// `@EnvironmentObject` in CodePetApp; feature completion hooks call
/// `requestIfFirstTime(_:)`, and the toast in MainTabView observes `pending`.
final class FeatureFeedbackManager: ObservableObject {
    /// The feature whose prompt is currently showing (nil = nothing). Only one
    /// prompt is shown at a time.
    @Published var pending: FeedbackFeature? = nil

    private let defaults: UserDefaults
    private lazy var db = Firestore.firestore()

    /// Small delay before presenting, so a completion celebration (exercise /
    /// lesson) can play first and the toast doesn't pop the instant they tap.
    private let presentDelay: TimeInterval = 1.0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Dev convenience: launch with `-resetFeedbackPrompts YES` (an Xcode
        // scheme argument) to clear every "already asked" flag on launch, so the
        // prompts re-fire naturally as you use features — no debug button needed.
        // Compiled out of release builds entirely.
        #if DEBUG
        if defaults.bool(forKey: "resetFeedbackPrompts") {
            debugResetAll()
        }
        #endif
    }

    /// Whether this feature's prompt has already been shown (so we never re-ask).
    func hasAsked(_ feature: FeedbackFeature) -> Bool {
        defaults.bool(forKey: feature.askedKey)
    }

    /// Show the feature's prompt the first time it's experienced. No-ops if it
    /// has already been asked, or if another prompt is currently pending. Marks
    /// the feature as asked immediately so it never fires twice.
    func requestIfFirstTime(_ feature: FeedbackFeature) {
        guard !hasAsked(feature), pending == nil else { return }
        defaults.set(true, forKey: feature.askedKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + presentDelay) { [weak self] in
            guard let self, self.pending == nil else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                self.pending = feature
            }
        }
    }

    /// Dismiss the current prompt without submitting.
    func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { pending = nil }
    }

    // MARK: - Debug helpers

    /// Immediately show a feature's prompt, ignoring the "already asked" flag.
    /// For testing the toast + Firestore submit without re-doing the feature.
    func debugShow(_ feature: FeedbackFeature) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            pending = feature
        }
    }

    /// Clear every "already asked" flag so the real first-experience triggers
    /// fire again on the next completion.
    func debugResetAll() {
        for feature in FeedbackFeature.allCases {
            defaults.removeObject(forKey: feature.askedKey)
        }
    }

    /// Write the feedback to the Firestore `feedback` collection, then dismiss.
    func submit(feature: FeedbackFeature, rating: Int, comment: String,
                authManager: AuthManager, appState: AppState) {
        let user = authManager.currentUser
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        var data: [String: Any] = [
            "feature": feature.rawValue,
            "rating": rating,
            "userId": user?.uid ?? "anonymous",
            "authMethod": authManager.authMethod ?? (authManager.isGuestMode ? "guest" : "none"),
            "displayName": user?.displayName ?? appState.displayName,
            "pet": appState.activeChar,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "platform": "macos",
            "timestamp": FieldValue.serverTimestamp()
        ]
        if let email = user?.email, !email.isEmpty { data["email"] = email }
        if !trimmed.isEmpty { data["comment"] = trimmed }

        if !AppEnvironment.isRunningTests {
            db.collection("feedback").addDocument(data: data) { error in
                if let error = error {
                    print("[Feedback] submit error: \(error.localizedDescription)")
                } else {
                    print("[Feedback] submitted \(feature.rawValue) rating=\(rating)")
                }
            }
        }
        dismiss()
    }
}
