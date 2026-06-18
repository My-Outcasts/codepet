import Foundation

/// Non-destructive per-account local storage.
///
/// The app's stores all read/write global `cp_*` UserDefaults keys. Previously,
/// signing in with a different account called `removePersistentDomain`, which
/// **permanently destroyed** the outgoing user's data (and there was no working
/// cloud backup). This vault fixes that: on account switch we *snapshot* the
/// outgoing account's keys into a per-uid vault and *restore* the incoming
/// account's snapshot. Nothing is ever deleted, so switching back and forth
/// preserves each account's data intact.
final class AccountDataStore {

    static let shared = AccountDataStore()
    private let defaults: UserDefaults

    /// `shared` uses `.standard`; tests inject an isolated suite so they don't
    /// touch the real app domain.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// One UserDefaults key holds every per-uid snapshot:
    ///   vaultKey → [uid: [appKey: plistValue]]
    private let vaultKey = "cp_account_vault"

    /// Keys that are NOT account-scoped data (device prefs, the account pointer,
    /// the vault itself). These are never snapshotted, cleared, or restored.
    private let preservedKeys: Set<String> = [
        "cp_currentUserId",
        "cp_account_vault",
        "cp_isDarkMode",
        "cp_soundEnabled",
        "cp_languagePersona",
        "cp_ui_language",
        "cp_demo_mode",
    ]

    /// Every live `cp_*` UserDefaults key that represents account-scoped data.
    private func accountDataKeys() -> [String] {
        defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("cp_") && !preservedKeys.contains($0) }
    }

    private func loadVault() -> [String: [String: Any]] {
        (defaults.dictionary(forKey: vaultKey) as? [String: [String: Any]]) ?? [:]
    }

    private func saveVault(_ vault: [String: [String: Any]]) {
        defaults.set(vault, forKey: vaultKey)
    }

    /// Snapshot the current working keys into the vault under `uid` (overwrites
    /// any prior snapshot for that uid with the current, fresher data).
    private func snapshotCurrentData(forUID uid: String) {
        var vault = loadVault()
        var snap: [String: Any] = [:]
        for key in accountDataKeys() {
            if let value = defaults.object(forKey: key) {
                snap[key] = value
            }
        }
        vault[uid] = snap
        saveVault(vault)
    }

    /// Remove all current account-scoped working keys (device prefs preserved).
    private func clearCurrentData() {
        for key in accountDataKeys() {
            defaults.removeObject(forKey: key)
        }
    }

    /// Restore `uid`'s snapshot into the working keys. Returns true if a snapshot
    /// existed for that account.
    @discardableResult
    private func restoreData(forUID uid: String) -> Bool {
        guard let snap = loadVault()[uid] else { return false }
        for (key, value) in snap {
            defaults.set(value, forKey: key)
        }
        return true
    }

    /// Whether the vault already holds a snapshot for an account.
    func hasSnapshot(forUID uid: String) -> Bool {
        loadVault()[uid] != nil
    }

    /// Switch the active account's local data **non-destructively**.
    ///
    /// - On a real switch (different `previousUID`): the outgoing account's data
    ///   is snapshotted, the working set is cleared, and the incoming account's
    ///   snapshot is restored (empty slate if it's a brand-new account).
    /// - On first run for an account (`previousUID == nil`): the existing working
    ///   keys are *adopted* as this account's data (snapshotted, NOT cleared).
    /// - Same account (`previousUID == uid`): no-op.
    ///
    /// - Returns: true if the incoming account had existing data restored.
    @discardableResult
    func activate(uid: String, previousUID: String?) -> Bool {
        if let old = previousUID, old != uid {
            snapshotCurrentData(forUID: old)
            clearCurrentData()
            return restoreData(forUID: uid)
        } else if previousUID == nil {
            // First account seen on this install — adopt existing data so it's
            // preserved (and attributed to this uid) when they later switch away.
            let hadData = !accountDataKeys().isEmpty
            snapshotCurrentData(forUID: uid)
            return hadData
        }
        // previousUID == uid → same account, leave working keys as-is.
        return true
    }
}
