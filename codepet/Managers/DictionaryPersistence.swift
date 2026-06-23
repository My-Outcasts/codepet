import Foundation
import Combine

/// Saves and restores the project-aware dictionary to UserDefaults so generated
/// cards and their provenance survive restarts. Same pattern as
/// `TipsPersistence`, with `cp_dict_` prefixed keys.
@MainActor
final class DictionaryPersistence {

    static let shared = DictionaryPersistence()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let entries = "cp_dict_entries"
        static let hasSavedBefore = "cp_dict_hasSavedBefore"
    }

    // MARK: - Save / Load

    func save(_ store: ProjectDictionaryStore) {
        defaults.set(true, forKey: Key.hasSavedBefore)
        if store.entries.isEmpty {
            defaults.removeObject(forKey: Key.entries)
        } else if let data = try? JSONEncoder().encode(store.entries) {
            defaults.set(data, forKey: Key.entries)
        }
    }

    func load(into store: ProjectDictionaryStore) {
        guard defaults.bool(forKey: Key.hasSavedBefore) else { return }
        if let data = defaults.data(forKey: Key.entries),
           let decoded = try? JSONDecoder().decode([String: DictionaryEntry].self, from: data) {
            store.entries = decoded
        }
    }

    // MARK: - Auto-save

    private var cancellable: AnyCancellable?

    /// Debounce-save the store after 1s of inactivity. Call once after `load`.
    func startAutoSave(_ store: ProjectDictionaryStore) {
        cancellable = store.objectWillChange
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self, weak store] _ in
                guard let self, let store else { return }
                self.save(store)
            }
    }

    // MARK: - Reset

    func resetAll() {
        defaults.removeObject(forKey: Key.entries)
        defaults.removeObject(forKey: Key.hasSavedBefore)
    }
}
