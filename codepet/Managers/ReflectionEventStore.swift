import Foundation
import Combine
import os

/// Polls ~/.codepet/events.jsonl (written by Claude Code hooks) and exposes
/// captured decision moments to the Reflection tab.
///
/// On app launch the store reads from the start of the file so prior
/// sessions remain visible across restarts. The in-memory list is capped at
/// `maxRetainedEvents` so very large historical files don't bloat memory.
///
/// Spec: docs/superpowers/specs/2026-05-04-claude-code-reflection-logging-design.md
@MainActor
final class ReflectionEventStore: ObservableObject {

    @Published private(set) var events: [CapturedEvent] = []

    /// Raw JSONL event tuples exposed for TurnAssembler — preserves type and full ISO time.
    @Published private(set) var rawJSONLEvents: [(type: String, isoTime: String, sessionId: String, text: String, cwd: String, path: String)] = []

    private let logURL: URL = RealHome.url
        .appendingPathComponent(".codepet/events.jsonl")
    private let pollInterval: TimeInterval = 1.5
    private let maxRetainedEvents = 500

    private var pollTimer: Timer?
    private var readOffset: UInt64 = 0
    private var lineBuffer = ""
    private let logger = Logger(subsystem: "app.murror.codepet", category: "Reflection")

    func start() {
        logger.info("ReflectionEventStore starting — logURL: \(self.logURL.path)")
        ensureFileExists()
        let exists = FileManager.default.fileExists(atPath: logURL.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? UInt64 ?? 0
        logger.info("  file exists: \(exists), size: \(size) bytes")
        // Read from offset 0 so historical events (sessions, turns, summaries)
        // from prior app launches are restored. NarrativeStore /
        // SessionSummaryStore / SessionEndStore all do the same. The
        // `maxRetainedEvents` cap below trims the in-memory window if the
        // file is very large.
        readOffset = 0
        events.removeAll()
        rawJSONLEvents.removeAll()
        lineBuffer = ""
        pollTimer?.invalidate()
        readNewLines()  // ingest the existing backlog synchronously on launch
        logger.info("  after initial read: \(self.events.count) events loaded")
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readNewLines() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - File I/O

    private func ensureFileExists() {
        let dir = logURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
    }

    private func currentFileSize() -> UInt64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        return (attrs?[.size] as? UInt64) ?? 0
    }

    private func readNewLines() {
        let size = currentFileSize()
        if size < readOffset {
            // File rotated or cleared — replay from start.
            readOffset = 0
            lineBuffer = ""
        }
        guard size > readOffset else { return }

        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
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

        var newEvents: [CapturedEvent] = []
        var newRawEntries: [(type: String, isoTime: String, sessionId: String, text: String, cwd: String, path: String)] = []
        let decoder = JSONDecoder()
        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let raw = try? decoder.decode(JSONLEvent.self, from: data) else {
                logger.warning("skipping malformed line")
                continue
            }
            newEvents.append(raw.toCapturedEvent())
            newRawEntries.append((
                type: raw.type,
                isoTime: raw.time,
                sessionId: raw.session_id ?? "",
                text: JSONLEvent.truncated(raw.text),
                cwd: raw.cwd ?? "",
                path: raw.path ?? ""
            ))
        }

        // Batch-publish once instead of per-line to minimize @Published churn
        guard !newEvents.isEmpty else { return }
        rawJSONLEvents.append(contentsOf: newRawEntries)
        events.append(contentsOf: newEvents)
        if events.count > maxRetainedEvents {
            events.removeFirst(events.count - maxRetainedEvents)
        }
        // NOTE: rawJSONLEvents is intentionally NOT capped — it is the source
        // TurnAssembler uses to build the full session list (ReflectionTab:68),
        // so trimming it would make older sessions disappear and chop large
        // sessions to a fragment. Measured event text is tiny (~0.16 MB for all
        // 3k+ events), so the unbounded array is not the memory concern.
    }

}

// MARK: - JSONL line schema

private struct JSONLEvent: Decodable {
    let time: String
    let type: String
    let session_id: String?
    let cwd: String?
    let text: String
    let tool_name: String?
    let path: String?

    func toCapturedEvent() -> CapturedEvent {
        CapturedEvent(
            time: Self.formatHHmm(time),
            isoTime: time,
            source: .claudeCode,
            text: Self.truncated(text),
            aiSummary: nil,
            trigger: nil,
            context: nil,
            isManualLog: false,
            cwd: cwd,
            path: path
        )
    }

    /// The Reflection tab is a narrative surface, not a full transcript viewer.
    /// Event bodies can be file diffs, whole file contents, or full command
    /// output — capping them keeps a long session from holding megabytes of raw
    /// text in memory. The marker makes truncation visible if anyone inspects it.
    static let maxEventTextLength = 4_000

    static func truncated(_ text: String) -> String {
        guard text.count > maxEventTextLength else { return text }
        return String(text.prefix(maxEventTextLength)) + "\n…(truncated)"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func formatHHmm(_ iso: String) -> String {
        guard let date = isoFormatter.date(from: iso) else { return iso }
        return displayFormatter.string(from: date)
    }
}
