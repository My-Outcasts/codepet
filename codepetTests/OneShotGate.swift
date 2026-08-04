// codepetTests/OneShotGate.swift
import Foundation

/// One-shot async gate for deterministically interleaving two concurrent `Task`s in a
/// test, without relying on timing (`Task.sleep`). `open()` is idempotent and safe to
/// call before or after `wait()`. Shared by `CompanyStoreFounderNameTests` and
/// `FounderPrefsPersistenceTests` (previously duplicated as `OneShotGate`/`PrefsGate`) —
/// both hydration-race regressions need the exact same harness, so one copy stays in sync.
final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        lock.lock()
        if opened { lock.unlock(); return }
        lock.unlock()
        await withCheckedContinuation { cont in
            lock.lock()
            if opened { lock.unlock(); cont.resume(); return }
            continuation = cont
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        opened = true
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume()
    }
}
