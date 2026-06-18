import Foundation
import Combine
import os

@MainActor
final class SessionChatStore: ObservableObject {

    @Published private(set) var threads: [String: SessionChatThread] = [:]

    /// Account-scoped on sign-in via `activate(uid:)`. Starts at the legacy
    /// global path only for the pre-sign-in window (no account known yet).
    private(set) var fileURL: URL
    private let saveDebounce: TimeInterval
    private let logger = Logger(subsystem: "app.murror.codepet", category: "SessionChatStore")
    private var saveWork: DispatchWorkItem?
    private static let ioQueue = DispatchQueue(
        label: "app.murror.codepet.SessionChatStore.io",
        qos: .utility
    )

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepet/session_chats.json"),
        saveDebounce: TimeInterval = 0.2
    ) {
        self.fileURL = fileURL
        self.saveDebounce = saveDebounce
        loadFromDisk()
    }

    deinit {
        saveWork?.cancel()
        saveWork = nil
    }

    // MARK: - Account scoping

    /// Per-account chat file so threads are isolated by uid — chat history must
    /// never leak between accounts that share the same Mac.
    static func fileURL(forUID uid: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepet/accounts/\(uid)/session_chats.json")
    }

    /// Point the store at `uid`'s own chat file: cancel any pending write for the
    /// outgoing account, drop its in-memory threads, and load the incoming
    /// account's history. Called from ContentView on every sign-in.
    func activate(uid: String) {
        let newURL = SessionChatStore.fileURL(forUID: uid)
        guard newURL != fileURL else { return }
        saveWork?.cancel()
        saveWork = nil
        fileURL = newURL
        loadFromDisk()
    }

    // MARK: - Public API

    func messages(for sessionId: String) -> [ChatMessage] {
        threads[sessionId]?.messages ?? []
    }

    func append(_ message: ChatMessage, to sessionId: String) {
        var thread = threads[sessionId] ?? SessionChatThread(
            sessionId: sessionId,
            messages: [],
            updatedAt: message.createdAt
        )
        thread.messages.append(message)
        thread.updatedAt = message.createdAt
        threads[sessionId] = thread
        scheduleSave()
    }

    func clear(_ sessionId: String) {
        threads.removeValue(forKey: sessionId)
        scheduleSave()
    }

    /// Returns the last N messages in chronological order. Used to build the
    /// `history` field of a chat request.
    func historySnapshot(for sessionId: String, lastN: Int = 10) -> [ChatMessage] {
        let all = messages(for: sessionId)
        guard all.count > lastN else { return all }
        return Array(all.suffix(lastN))
    }

    /// Synchronously flush any pending save. For tests.
    func flushForTests() {
        saveWork?.cancel()
        saveWork = nil
        let snapshot = threads
        let url = fileURL
        SessionChatStore.ioQueue.sync {
            self.writeSnapshot(snapshot, to: url)
        }
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([String: SessionChatThread].self, from: data)
            self.threads = decoded
        } catch CocoaError.fileReadNoSuchFile {
            // First run; no file yet.
            self.threads = [:]
        } catch {
            logger.error("Failed to load chat threads, starting fresh: \(String(describing: error))")
            self.threads = [:]
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = threads
        let debounce = saveDebounce
        // Capture the URL now so a mid-debounce account switch can't redirect
        // this write to the new account's file.
        let url = fileURL
        let work = DispatchWorkItem { [weak self] in
            self?.writeSnapshot(snapshot, to: url)
        }
        saveWork = work
        if debounce > 0 {
            SessionChatStore.ioQueue.asyncAfter(
                deadline: .now() + debounce,
                execute: work
            )
        } else {
            SessionChatStore.ioQueue.async(execute: work)
        }
    }

    private nonisolated func writeSnapshot(_ snapshot: [String: SessionChatThread], to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            // replaceItemAt requires an existing destination; a freshly-scoped
            // per-account file won't exist on its first write, so fall back to a
            // plain atomic write in that case.
            if FileManager.default.fileExists(atPath: url.path) {
                let tmp = url.appendingPathExtension("tmp")
                try data.write(to: tmp)
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            logger.error("Failed to save chat threads: \(String(describing: error))")
        }
    }
}
