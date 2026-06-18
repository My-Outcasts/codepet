import Foundation
import Combine
import os

/// Polls session_ends.jsonl (written by Claude Code SessionEnd hook) and
/// exposes the set of session_ids that have been explicitly closed.
@MainActor
final class SessionEndStore: ObservableObject {

    @Published private(set) var endedSessionIds: Set<String> = []

    private let fileURL: URL
    private let pollInterval: TimeInterval
    private var pollTimer: Timer?
    private var readOffset: UInt64 = 0
    private var lineBuffer = ""
    private let logger = Logger(subsystem: "app.murror.codepet", category: "SessionEndStore")

    init(
        fileURL: URL = RealHome.url
            .appendingPathComponent(".codepet/session_ends.jsonl"),
        pollInterval: TimeInterval = 1.5
    ) {
        self.fileURL = fileURL
        self.pollInterval = pollInterval
    }

    func start() {
        ensureFileExists()
        readOffset = 0
        readNewLines()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readNewLines() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Test/mock helper: mark a session as ended in-memory without touching the file.
    func seedMockEnded(_ sessionId: String) {
        endedSessionIds.insert(sessionId)
    }

    private func ensureFileExists() {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func currentFileSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    private func readNewLines() {
        ensureFileExists()
        let size = currentFileSize()
        if size < readOffset { readOffset = 0; lineBuffer = "" }
        guard size > readOffset else { return }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: readOffset) } catch { return }
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return }
        readOffset += UInt64(chunk.count)
        guard let text = String(data: chunk, encoding: .utf8) else { return }
        lineBuffer.append(text)

        var lines = lineBuffer.components(separatedBy: "\n")
        let trailing = lines.removeLast()
        lineBuffer = trailing

        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONDecoder().decode(SessionEndLine.self, from: data) else {
                logger.warning("skipping malformed session_end line")
                continue
            }
            endedSessionIds.insert(row.session_id)
        }
    }
}

private struct SessionEndLine: Decodable {
    let session_id: String
    let time: String
}
