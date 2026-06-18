import Foundation

struct SSEFrame: Equatable {
    let event: String
    let data: String
}

/// Stateful Server-Sent Events line parser. Feed it lines (already split on
/// `\n`); it returns a list of completed frames each time a blank line
/// terminates a frame.
///
/// Implements the subset of the SSE spec we use:
/// - `event:` field (single per frame; defaults to "message")
/// - `data:` field (multiple lines joined with `\n`)
/// - blank line dispatches the accumulated frame
/// - lines starting with `:` are comments and ignored
/// - other field names (`id:`, `retry:`) are ignored
struct SSEParser {
    private var event: String = "message"
    private var dataLines: [String] = []

    mutating func feedLines<S: Sequence>(_ lines: S) -> [SSEFrame] where S.Element == String {
        var frames: [SSEFrame] = []
        for raw in lines {
            if let frame = feedLine(raw) {
                frames.append(frame)
            }
        }
        return frames
    }

    mutating func feedLine(_ line: String) -> SSEFrame? {
        if line.isEmpty {
            // Dispatch
            guard !dataLines.isEmpty || event != "message" else {
                reset()
                return nil
            }
            let frame = SSEFrame(event: event, data: dataLines.joined(separator: "\n"))
            reset()
            return frame
        }

        if line.hasPrefix(":") {
            return nil // comment
        }

        guard let colonIndex = line.firstIndex(of: ":") else {
            // No colon — treat the whole line as a field with empty value (spec).
            // We don't use any such fields, so ignore.
            return nil
        }

        let field = String(line[..<colonIndex])
        var value = String(line[line.index(after: colonIndex)...])
        if value.first == " " {
            value.removeFirst()
        }

        switch field {
        case "event":
            event = value
        case "data":
            dataLines.append(value)
        default:
            break  // ignore id, retry, unknown
        }
        return nil
    }

    private mutating func reset() {
        event = "message"
        dataLines.removeAll(keepingCapacity: true)
    }
}
