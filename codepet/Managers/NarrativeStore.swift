import Foundation
import Combine
import os

/// Polls narratives.jsonl (written by NarrativeEnricher) and exposes
/// narratives keyed by turn_id. Mirrors ReflectionEventStore polling pattern.
@MainActor
final class NarrativeStore: ObservableObject {

    @Published private(set) var narratives: [String: Narrative] = [:]

    /// Maps each narrative key (same keys as `narratives`) → the sessionId that
    /// produced it, so callers can attribute a narrative back to its project.
    @Published private(set) var sessionIds: [String: String] = [:]

    private let fileURL: URL
    private let pollInterval: TimeInterval
    private var pollTimer: Timer?
    private var readOffset: UInt64 = 0
    private var lineBuffer = ""
    private let logger = Logger(subsystem: "app.murror.codepet", category: "NarrativeStore")
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codepet/narratives.jsonl"),
        pollInterval: TimeInterval = 1.5
    ) {
        self.fileURL = fileURL
        self.pollInterval = pollInterval
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

    /// Append a narrative line. Used by NarrativeEnricher.
    func appendNarrative(turnId: String, sessionId: String, language: String, narrative: Narrative) throws {
        ensureFileExists()
        let payload = try encodeLine(turnId: turnId, sessionId: sessionId, language: language, narrative: narrative)
        let data = (payload + "\n").data(using: .utf8)!
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        // Key includes language so switching vi↔en triggers re-enrichment.
        let key = Self.narrativeKey(turnId: turnId, language: language)
        narratives[key] = narrative
        sessionIds[key] = sessionId
    }

    /// Look up a narrative for a specific turn and language.
    func narrative(forTurnId turnId: String, language: String) -> Narrative? {
        narratives[Self.narrativeKey(turnId: turnId, language: language)]
    }

    /// Backward-compat: look up by turnId alone (returns any language match).
    func narrative(forTurnId turnId: String) -> Narrative? {
        if let exact = narratives[turnId] { return exact }
        // Try with language suffixes
        for (key, value) in narratives where key.hasPrefix(turnId) {
            return value
        }
        return nil
    }

    static func narrativeKey(turnId: String, language: String) -> String {
        "\(turnId):\(language)"
    }

    private func encodeLine(turnId: String, sessionId: String, language: String, narrative: Narrative) throws -> String {
        let line = NarrativeLine(turnId: turnId, sessionId: sessionId, language: language, narrative: narrative)
        let data = try JSONEncoder().encode(line)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "NarrativeStore",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode narrative line as UTF-8"]
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

        // Batch-decode into a local dict, then merge once to minimize @Published churn
        var newEntries: [String: Narrative] = [:]
        var newSessionIds: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8) else { continue }
            do {
                let row = try decoder.decode(NarrativeLine.self, from: data)
                let lang = row.language ?? "en"
                let key = Self.narrativeKey(turnId: row.turn_id, language: lang)
                let narrative = row.toNarrative()
                newEntries[key] = narrative
                newSessionIds[key] = row.session_id
                // Also store under plain turn_id for backward compat.
                newEntries[row.turn_id] = narrative
                newSessionIds[row.turn_id] = row.session_id
            } catch {
                logger.warning("skipping malformed narrative line: \(error.localizedDescription)")
            }
        }
        if !newEntries.isEmpty {
            narratives.merge(newEntries) { _, new in new }
            sessionIds.merge(newSessionIds) { _, new in new }
        }
    }
}

private extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct NarrativeLine: Codable {
    let turn_id: String
    let session_id: String
    let generated_at: String
    let language: String?
    let title: String
    let what_you_wanted: String
    let what_happened: String
    let lesson: String
    let next_steps: String?
    let mood: String?
    let model: String
    let schema_version: Int

    init(turnId: String, sessionId: String, language: String, narrative: Narrative) {
        self.turn_id = turnId
        self.session_id = sessionId
        self.generated_at = ISO8601DateFormatter.shared.string(from: narrative.generatedAt)
        self.language = language
        self.title = narrative.title
        self.what_you_wanted = narrative.whatYouWanted
        self.what_happened = narrative.whatHappened
        self.lesson = narrative.lesson
        self.next_steps = narrative.nextSteps
        self.mood = narrative.mood
        self.model = narrative.model
        self.schema_version = narrative.schemaVersion
    }

    func toNarrative() -> Narrative {
        let date = ISO8601DateFormatter.shared.date(from: generated_at) ?? Date()
        return Narrative(
            title: title,
            whatYouWanted: what_you_wanted,
            whatHappened: what_happened,
            lesson: lesson,
            nextSteps: next_steps ?? "",
            mood: mood ?? "idle",
            model: model,
            generatedAt: date,
            schemaVersion: schema_version
        )
    }
}
