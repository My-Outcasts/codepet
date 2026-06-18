import Foundation
import Combine
import os

/// Polls session_summaries.jsonl and exposes summaries keyed by sessionId.
/// Mirrors NarrativeStore polling pattern.
@MainActor
final class SessionSummaryStore: ObservableObject {

    @Published private(set) var summaries: [String: SessionSummary] = [:]

    private let fileURL: URL
    private let pollInterval: TimeInterval
    private var pollTimer: Timer?
    private var readOffset: UInt64 = 0
    private var lineBuffer = ""
    private let logger = Logger(subsystem: "app.murror.codepet", category: "SessionSummaryStore")
    private let decoder: JSONDecoder

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepet/session_summaries.jsonl"),
        pollInterval: TimeInterval = 1.5
    ) {
        self.fileURL = fileURL
        self.pollInterval = pollInterval
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
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

    /// Append a summary line to the JSONL file. Used by Cloud Function bridge (future).
    func appendSummary(_ summary: SessionSummary) throws {
        ensureFileExists()
        let payload = try encodeLine(summary: summary)
        let data = (payload + "\n").data(using: .utf8)!
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        // Update in-memory immediately; poll will see same line and overwrite (last-write-wins).
        summaries[summary.sessionId] = summary
    }

    /// Inject a mock summary for UI testing — in-memory only, doesn't touch the file.
    func seedMockSummary(_ summary: SessionSummary) {
        summaries[summary.sessionId] = summary
    }

    // MARK: - Private: encoding

    private func encodeLine(summary: SessionSummary) throws -> String {
        let line = SessionSummaryLine(summary: summary)
        let encoder = JSONEncoder()
        // We manage dates ourselves via ISO string in SessionSummaryLine
        let data = try encoder.encode(line)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "SessionSummaryStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode summary line as UTF-8"]
            )
        }
        return string
    }

    // MARK: - File I/O

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
        if size < readOffset {
            readOffset = 0
            lineBuffer = ""
        }
        guard size > readOffset else { return }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: readOffset) } catch {
            logger.warning("seek failed: \(error.localizedDescription)")
            return
        }
        guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return }
        readOffset += UInt64(chunk.count)
        guard let text = String(data: chunk, encoding: .utf8) else { return }
        lineBuffer.append(text)

        var lines = lineBuffer.components(separatedBy: "\n")
        let trailing = lines.removeLast()
        lineBuffer = trailing

        // Batch-decode then merge once to minimize @Published churn
        var newEntries: [String: SessionSummary] = [:]
        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let row = try decoder.decode(SessionSummaryLine.self, from: data)
                newEntries[row.session_id] = row.toSummary()
            } catch {
                logger.warning("skipping malformed summary line: \(error.localizedDescription)")
            }
        }
        if !newEntries.isEmpty {
            summaries.merge(newEntries) { _, new in new }
        }
    }
}

// MARK: - JSONL line codec

private extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct SessionSummaryLine: Codable {
    let session_id: String
    let summary: String
    let lesson: String
    let generated_at: String
    let model: String
    let schema_version: Int

    init(summary s: SessionSummary) {
        self.session_id = s.sessionId
        self.summary = s.summary
        self.lesson = s.lesson
        self.generated_at = ISO8601DateFormatter.shared.string(from: s.generatedAt)
        self.model = s.model
        self.schema_version = s.schemaVersion
    }

    func toSummary() -> SessionSummary {
        let date = ISO8601DateFormatter.shared.date(from: generated_at) ?? Date()
        return SessionSummary(
            sessionId: session_id,
            summary: summary,
            lesson: lesson,
            generatedAt: date,
            model: model,
            schemaVersion: schema_version
        )
    }
}
