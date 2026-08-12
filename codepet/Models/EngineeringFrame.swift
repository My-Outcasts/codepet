import Foundation

/// One frame off the `engStream` relay.
///
/// These five are the complete set `engStream.ts` writes — `step`, `message`,
/// `approval`, `done`, `error` — and nothing else appears on that stream. The
/// relay also emits `: heartbeat` comment lines every few seconds; those carry
/// no event name and `SSEParser` drops them before they reach here.
///
/// Decoding NEVER throws. A frame this client does not recognise, or one whose
/// data is malformed, is dropped and the stream continues: a paid run that is
/// already in flight must not be abandoned because one frame was unreadable,
/// and the relay may gain frames before this client knows them.
enum EngineeringFrame: Equatable {
    case step(ExecStep)
    case message(String)
    case approval(EngApproval)
    case done(stopReason: String)
    case failure(String)

    static func decode(event: String, data: Data) -> EngineeringFrame? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        switch event {
        case "step":       return decodeStep(object)
        case "message":    return decodeMessage(object)
        case "approval":   return decodeApproval(object)
        case "done":       return .done(stopReason: object["stopReason"] as? String ?? "end_turn")
        case "error":      return .failure(object["error"] as? String ?? "stream_failed")
        default:           return nil
        }
    }

    // MARK: - per-frame decoding

    private static func decodeStep(_ object: [String: Any]) -> EngineeringFrame? {
        guard let id = object["id"] as? String, !id.isEmpty else { return nil }
        // `engEvents.ts` documents a completion marker as `{ id, label: "",
        // done: true }` — it completes an EARLIER step by id rather than adding
        // a row, so an empty label is valid here and must not be rejected.
        let label = object["label"] as? String ?? ""
        let done = object["done"] as? Bool ?? false
        // `.mono` because every one of these is a real tool call with a real
        // path or command behind it. `.normal` is for narration, which arrives
        // as a `message` frame instead.
        return .step(ExecStep(id: id, label: label, done: done, kind: .mono))
    }

    private static func decodeMessage(_ object: [String: Any]) -> EngineeringFrame? {
        guard let text = object["text"] as? String, !text.isEmpty else { return nil }
        return .message(text)
    }

    private static func decodeApproval(_ object: [String: Any]) -> EngineeringFrame? {
        guard let id = object["toolUseId"] as? String, !id.isEmpty else { return nil }
        let name = object["name"] as? String ?? "tool"
        return .approval(EngApproval(id: id, name: name, input: renderInput(object["input"])))
    }

    /// A tool's input, as something a founder can read and decide about.
    ///
    /// The wire carries an object — `{"command": "npm install stripe"}` for
    /// bash, other shapes for other tools. For bash the command IS the
    /// question being asked, so it is lifted out; showing
    /// `{"command":"npm install stripe"}` would make the founder read JSON to
    /// answer a yes/no. Anything else falls back to compact JSON with sorted
    /// keys, which is at least stable between renders.
    static func renderInput(_ raw: Any?) -> String {
        guard let dict = raw as? [String: Any] else {
            return raw.map { String(describing: $0) } ?? ""
        }
        if let command = dict["command"] as? String, !command.isEmpty { return command }
        if let path = dict["file_path"] as? String, !path.isEmpty { return path }
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }
}
