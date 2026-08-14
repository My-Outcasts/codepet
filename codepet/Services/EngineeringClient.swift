import Foundation
import FirebaseAuth

/// The production `EngineeringRunning`: SSE over `URLSession.bytes`, through
/// the shared `SSEParser`.
///
/// Deliberately the same reading strategy as `VirtualCompanyClient` — there is
/// one working SSE reader in this codebase and a second one would be a second
/// place for the byte-buffering bugs to live.
///
/// Two things the relay does that this must survive:
///
/// - **`: heartbeat` comment frames** arrive every few seconds. `SSEParser`
///   drops comment lines, so they never reach the frame handler; a client that
///   treated one as a frame would spam the transcript.
/// - **A run paused on `requires_action` holds the connection open
///   indefinitely.** That is correct — the founder is the blocker — so there is
///   no idle timeout and no retry on silence. Adding one would abandon a paid
///   run that is simply waiting for someone to click Allow.
final class EngineeringClient: EngineeringRunning {

    private let base: URL
    private let session: URLSession
    private let idToken: () async throws -> String

    init(
        base: URL = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net")!,
        session: URLSession = .shared,
        idToken: (() async throws -> String)? = nil
    ) {
        self.base = base
        self.session = session
        self.idToken = idToken ?? {
            guard let token = try await Auth.auth().currentUser?.getIDToken() else {
                throw EngineeringError.unknown(401)
            }
            return token
        }
    }

    // MARK: - EngineeringRunning

    func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
        let body: [String: Any] = ["ask": ask]
        let started: [String: Any] = try await postJSON(path: "engStartRun", body: body)
        guard let runId = started["runId"] as? String, !runId.isEmpty else {
            throw EngineeringError.unknown(502)
        }
        // The stream is its own task: `start` returns as soon as the run
        // exists, so the caller can render a run id and a spinner rather than
        // waiting for a session that may run for an hour.
        Task { [weak self] in
            try? await self?.attach(runId: runId, onFrame: onFrame)
        }
        return runId
    }

    func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {
        var request = URLRequest(url: base.appending(path: "engStream")
            .appending(queryItems: [URLQueryItem(name: "runId", value: runId)]))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        if http.statusCode != 200 {
            // Drain before mapping: the body carries the handler's error code,
            // and the two 409s mean different things to the founder.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw Self.error(status: http.statusCode, body: data)
        }

        var parser = SSEParser()
        var lineBuffer: [UInt8] = []
        for try await byte in bytes {
            guard byte == UInt8(ascii: "\n") else {
                lineBuffer.append(byte)
                continue
            }
            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
            lineBuffer.removeAll(keepingCapacity: true)
            Self.deliver(parser.feedLines([line]), to: onFrame)
        }
        // A final line with no trailing newline, then a blank line to flush:
        // the relay always terminates a frame properly, but a truncated
        // connection must not swallow the last one it did send.
        if !lineBuffer.isEmpty {
            Self.deliver(parser.feedLines([String(bytes: lineBuffer, encoding: .utf8) ?? ""]), to: onFrame)
        }
        Self.deliver(parser.feedLines([""]), to: onFrame)
    }

    func send(runId: String, turn: EngineeringTurn) async throws {
        var body = turn.body
        body["runId"] = runId
        _ = try await postJSON(path: "engSendTurn", body: body) as [String: Any]
    }

    func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary {
        var request = URLRequest(url: base.appending(path: "engDiff")
            .appending(queryItems: [
                URLQueryItem(name: "runId", value: runId),
                URLQueryItem(name: "scope", value: scope.rawValue)
            ]))
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        guard http.statusCode == 200 else { throw Self.error(status: http.statusCode, body: data) }
        return try JSONDecoder().decode(EngDiffSummary.self, from: data)
    }

    /// Open the PR.
    ///
    /// Not `postJSON`, because one of `engShip`'s failures is not a failure to
    /// the founder. `pr_write_failed` is a 503 whose body carries `prNumber`
    /// and `prUrl`: the pull request WAS opened on GitHub and only Firestore's
    /// record of it did not land. Throwing that away would show a retry
    /// control for work that already happened, and the retry would ask GitHub
    /// to open a pull request that already exists.
    ///
    /// So a PR in the body wins over the status. The run document stays out of
    /// sync until the reconciler that does not exist yet catches up — but the
    /// founder is shown the truth, which is that their PR is open.
    func ship(runId: String) async throws -> EngShipResult {
        var request = URLRequest(url: base.appending(path: "engShip"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["runId": runId])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        if let result = Self.shipResult(from: json) { return result }
        guard http.statusCode == 200 else { throw Self.error(status: http.statusCode, body: data) }
        // 200 with no PR number is a contract the backend does not have.
        throw EngineeringError.unknown(502)
    }

    /// A PR in the body, whatever the status was.
    static func shipResult(from json: [String: Any]) -> EngShipResult? {
        guard let number = json["prNumber"] as? Int, number > 0 else { return nil }
        return EngShipResult(prNumber: number, prUrl: json["prUrl"] as? String ?? "")
    }

    func preview(runId: String) async throws -> EngPreviewState {
        var request = URLRequest(url: base.appending(path: "engPreview")
            .appending(queryItems: [URLQueryItem(name: "runId", value: runId)]))
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        guard http.statusCode == 200 else { throw Self.error(status: http.statusCode, body: data) }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return EngPreviewState.decode(json)
    }

    // MARK: - plumbing

    private func postJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await idToken())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EngineeringError.unknown(0) }
        guard http.statusCode == 200 else { throw Self.error(status: http.statusCode, body: data) }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Map a refusal to something the founder can act on.
    ///
    /// The handler's own `error` code is what separates the two 409s, so it is
    /// read out of the body rather than inferred from the status alone.
    static func error(status: Int, body: Data) -> EngineeringError {
        let code = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
        return EngineeringError.from(status: status, code: code)
    }

    private static func deliver(_ frames: [SSEFrame], to onFrame: (EngineeringFrame) -> Void) {
        for frame in frames {
            if let decoded = EngineeringFrame.decode(event: frame.event, data: Data(frame.data.utf8)) {
                onFrame(decoded)
            }
        }
    }
}
