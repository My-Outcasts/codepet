import SwiftUI
import Combine
import FirebaseFirestore

class CloudSyncService: ObservableObject {
    private var syncTimer: Timer?
    // Lazy so merely constructing this service (e.g. inside a view) doesn't spin
    // up Firestore — important so the test host can launch without Firebase.
    private lazy var db = Firestore.firestore()

    /// Save all app state to Firestore
    func saveToCloud(userId: String, appState: AppState) {
        guard !AppEnvironment.isRunningTests else { return }
        guard !ServerLoggingGate.isOptedOut else {
            print("[CloudSync] Skipped — account opted out of server logging")
            return
        }
        let userData: [String: Any] = [
            "totalXP": appState.totalXP,
            "userLevel": appState.userLevel,
            "currentTier": appState.currentTier,
            "streak": appState.streak,
            "activeChar": appState.activeChar,
            "completedLessons": appState.completedLessons,
            "completedChallenges": appState.completedChallenges,
            "displayName": appState.displayName,
            "onboardingComplete": appState.onboardingComplete,
            "difficultyLevel": appState.difficultyLevel,
            "skillLevel": appState.skillLevel,
            "dailyGoalMinutes": appState.dailyGoalMinutes,
            "energy": appState.petEnergy,
            "updatedAt": FieldValue.serverTimestamp(),
            "platform": "macos"
        ]

        db.collection("users").document(userId).setData(userData, merge: true) { error in
            if let error = error {
                print("[CloudSync] Save error: \(error.localizedDescription)")
            } else {
                print("[CloudSync] Saved data for user: \(userId)")
            }
        }
    }

    /// Load app state from Firestore
    func loadFromCloud(userId: String, appState: AppState, completion: @escaping (Bool) -> Void) {
        guard !AppEnvironment.isRunningTests else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        db.collection("users").document(userId).getDocument { snapshot, error in
            if let error = error {
                print("[CloudSync] Load error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let data = snapshot?.data() else {
                print("[CloudSync] No data found for user: \(userId)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            DispatchQueue.main.async {
                // Restore state from Firestore
                if let totalXP = data["totalXP"] as? Int {
                    appState.totalXP = totalXP
                }
                if let userLevel = data["userLevel"] as? Int {
                    appState.userLevel = userLevel
                }
                if let currentTier = data["currentTier"] as? Int {
                    appState.currentTier = currentTier
                }
                if let streak = data["streak"] as? Int {
                    appState.streak = streak
                }
                if let activeChar = data["activeChar"] as? String {
                    appState.activeChar = activeChar
                }
                if let completedLessons = data["completedLessons"] as? [String] {
                    appState.completedLessons = completedLessons
                }
                if let completedChallenges = data["completedChallenges"] as? [String] {
                    appState.completedChallenges = completedChallenges
                }
                if let displayName = data["displayName"] as? String {
                    appState.displayName = displayName
                }
                if let onboardingComplete = data["onboardingComplete"] as? Bool {
                    appState.onboardingComplete = onboardingComplete
                }
                if let difficultyLevel = data["difficultyLevel"] as? String {
                    appState.difficultyLevel = difficultyLevel
                }
                if let skillLevel = data["skillLevel"] as? String {
                    appState.skillLevel = skillLevel
                }
                if let dailyGoalMinutes = data["dailyGoalMinutes"] as? Int {
                    appState.dailyGoalMinutes = dailyGoalMinutes
                }
                if let energy = data["energy"] as? Int {
                    appState.petEnergy = energy
                }

                let hasData = data["onboardingComplete"] as? Bool == true ||
                              (data["activeChar"] as? String) != nil

                print("[CloudSync] Loaded data for user: \(userId), hasData: \(hasData)")
                completion(hasData)
            }
        }
    }

    /// Debounced save — waits 2 seconds after last change
    func scheduleSave(userId: String, appState: AppState) {
        guard !AppEnvironment.isRunningTests else { return }
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.saveToCloud(userId: userId, appState: appState)
        }
    }

    /// Cancel a pending debounced save (e.g. on account switch) so it can't fire
    /// after the active account's data has been swapped out.
    func cancelPendingSave() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
}

