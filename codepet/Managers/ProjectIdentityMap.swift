import Foundation
import os

/// This machine's map from a local folder path to a project id, per signed-in account.
///
/// The path stays here and never reaches Firestore: it names a location on one machine and
/// means nothing on another. The id is what travels, and it is what `DecisionEntry.scope`
/// stores — which is the whole reason this indirection exists.
///
/// Keyed by account because a project id only means something inside one founder's
/// `companies/{uid}`. A single flat map cannot be right: cleared on sign-out, the same
/// founder coming back re-links their folder and mints a NEW id, orphaning every fact
/// scoped to the old one; kept across a switch, the next founder inherits bindings that
/// point at projects they cannot see. Two levels satisfies both, and sign-out becomes
/// `account = nil` — which destroys nothing.
///
/// `defaults` and `key` are injectable ONLY so a test can point an instance at its own
/// suite. The app always uses `.standard` with `cp_project_ids_v1`; a test writing there
/// could have its cleanup clobbered by a running app and eat real bindings.
// Deliberately `nonisolated`, not `@MainActor`. This type is a UserDefaults wrapper with no
// need for actor isolation, and a `@MainActor` class here would give it an isolated deinit —
// which on Xcode 26.2 stops its whole XCTest suite from executing (see CLAUDE.md landmine 3).
// Every one of its 11 tests would compile and never run. Only ever touched from the main
// actor in practice; if that ever stops being true, revisit this rather than the tests.
nonisolated final class ProjectIdentityMap {

    private let logger = Logger(subsystem: "app.murror.codepet", category: "ProjectIdentity")
    private let defaults: UserDefaults
    private let key: String

    /// The signed-in company id. Nil means nobody is signed in, and then nothing resolves
    /// and nothing binds — a fact cannot be scoped to a project no account owns.
    var account: String?

    /// companyId → (path → id). Many paths may point at one id within an account; that is
    /// the supported case, not an edge.
    private var byAccount: [String: [String: String]] = [:]

    init(defaults: UserDefaults = .standard, key: String = "cp_project_ids_v1") {
        self.defaults = defaults
        self.key = key
        load()
    }

    func id(forPath path: String) -> String? {
        guard let account else { return nil }
        return byAccount[account]?[normalize(path)]
    }

    /// Bind a path to a project id for the signed-in account, replacing any previous
    /// binding for that path.
    ///
    /// Rebinding is a real operation: a founder who moves a folder, or who corrects a
    /// wrong match, needs the old binding gone rather than kept alongside the new one.
    func bind(path: String, to id: String) {
        guard let account else { return }
        let p = normalize(path)
        let i = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !i.isEmpty else { return }
        byAccount[account, default: [:]][p] = i
        save()
        logger.info("Bound a local folder to project \(i, privacy: .public)")
    }

    /// Every local path currently bound to this id, within the signed-in account. Sorted
    /// for a stable read.
    func paths(for id: String) -> [String] {
        guard let account, let mine = byAccount[account] else { return [] }
        return mine.filter { $0.value == id }.keys.sorted()
    }

    /// Wipe every account's bindings. Not part of sign-out — that is `account = nil`, which
    /// keeps them. This exists for a deliberate full reset.
    func resetAll() {
        byAccount = [:]
        defaults.removeObject(forKey: key)
    }

    /// Re-read from disk, discarding anything held in memory.
    func reload() {
        byAccount = [:]
        load()
    }

    // MARK: - Private

    /// Trailing slashes only. Deliberately NOT resolving symlinks or case: that would need
    /// the filesystem, and this type stays answerable without one.
    private func normalize(_ path: String) -> String {
        var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return }
        byAccount = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(byAccount) else { return }
        defaults.set(data, forKey: key)
    }
}
