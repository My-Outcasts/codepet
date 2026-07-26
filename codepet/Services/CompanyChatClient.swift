// codepet/Services/CompanyChatClient.swift
import Foundation
import FirebaseAuth

/// One prior chat turn sent to the CF as history.
struct ChatTurnDTO: Codable, Equatable {
    let role: String   // "me" | "companion"
    let text: String
}

/// One task byte is allowed to run, sent alongside the request so the CF can
/// decide whether to set `run_task_id` in its reply. Mirrors the web's
/// `openTasks` shape — just `id` + `title`, no other roadmap fields needed.
struct RunnableRef: Codable, Equatable {
    let id: String
    let title: String
}

/// Request body for the companyChat Cloud Function.
struct CompanyChatRequest: Codable {
    let companyId: String?
    let language: String
    let companionId: String
    let context: String
    let history: [ChatTurnDTO]
    let userMessage: String
    let runnable: [RunnableRef]

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case history
        case userMessage = "user_message"
        case runnable
    }

    /// `runnable` defaults to empty so existing call sites (and older tests
    /// built before this field existed) keep compiling without every caller
    /// having to name it explicitly.
    init(companyId: String?, language: String, companionId: String, context: String,
         history: [ChatTurnDTO], userMessage: String, runnable: [RunnableRef] = []) {
        self.companyId = companyId
        self.language = language
        self.companionId = companionId
        self.context = context
        self.history = history
        self.userMessage = userMessage
        self.runnable = runnable
    }
}

/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
    let runTaskId: String?

    enum CodingKeys: String, CodingKey {
        case reply
        case runTaskId = "run_task_id"
    }
}

/// A companion reply — text plus an optional "run this task" action (byte's run_task).
struct CompanyChatReply: Equatable {
    let text: String
    let runTaskId: String?
}

// MARK: - Streaming

/// One event from the companyChat SSE stream. Mirrors `ChatStreamEvent`
/// (ReflectionAPIClient's chatSessionStream) — same wire shapes, same
/// companionChat CF, just a different endpoint.
enum CompanyChatStreamEvent: Equatable {
    case delta(String)
    /// `runTaskId` mirrors the JSON response's `run_task_id` — non-nil when byte
    /// decided to run one of the `runnable` tasks it was offered.
    case done(model: String, cacheHit: Bool, runTaskId: String?)
}

/// Small body decoded from an `event: error` frame or a non-200 HTTP response.
struct CompanyChatStreamErrorBody: Codable, Equatable {
    let error: String
    let detail: String?
}

/// Typed error for `CompanyChatClient.sendStream`, mirroring `ReflectionAPIError`.
enum CompanyChatStreamError: Error, Equatable {
    case notSignedIn
    case http(status: Int, body: CompanyChatStreamErrorBody?)
    case malformedResponse
}

/// Fail-open client for the (planned) companyChat Cloud Function. Returns the reply
/// on 200, `nil` on any error / non-200 / unreachable — callers never handle throws.
/// The CF is authored + deployed separately (node-22 bundle, like scaffoldRoadmap);
/// until then this returns nil and the chat shows an honest offline message.
enum CompanyChatClient {
    static let endpoint = URL(string: "https://us-central1-devpet-8f4b1.cloudfunctions.net/companyChat")!

    static func send(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        guard let token = try? await Auth.auth().currentUser?.getIDToken() else { return nil }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let body = try? JSONEncoder().encode(req) else { return nil }
        urlRequest.httpBody = body
        guard let (data, response) = try? await URLSession.shared.data(for: urlRequest),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanyChatResponse.self, from: data)
        else { return nil }
        let reply = decoded.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty else { return nil }
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId)
    }

    /// Streaming counterpart of `send(_:)` — hits the SAME companyChat endpoint
    /// but with `Accept: text/event-stream`, and yields incremental
    /// `CompanyChatStreamEvent`s as the CF streams its reply. Mirrors
    /// `ReflectionAPIClient.chatSessionStream` precisely (detached Task,
    /// `URLSession.bytes(for:)`, bytes fed through `SSEParser`, typed throw on
    /// non-200 or an `event: error` frame).
    ///
    /// `session` and `authTokenProvider` are injectable (as on
    /// `ReflectionAPIClient`) so tests can exercise the parsing logic against a
    /// mocked byte stream with no network. Unlike `ReflectionAPIClient`, this
    /// type carries no actor isolation — CompanyChatClient stays a plain enum
    /// with static functions so `sendStream` needs no `@MainActor`.
    static func sendStream(
        _ req: CompanyChatRequest,
        session: URLSession = .shared,
        authTokenProvider: (() async throws -> String)? = nil
    ) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        let capturedSession = session
        let capturedAuthTokenProvider = authTokenProvider ?? {
            guard let token = try? await Auth.auth().currentUser?.getIDToken() else {
                throw CompanyChatStreamError.notSignedIn
            }
            return token
        }
        let url = endpoint

        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let token = try await capturedAuthTokenProvider()

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.httpBody = try JSONEncoder().encode(req)

                    let (bytes, response) = try await capturedSession.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else {
                        throw CompanyChatStreamError.malformedResponse
                    }

                    if http.statusCode != 200 {
                        // Non-streaming error body. Read fully then throw.
                        var data = Data()
                        for try await byte in bytes {
                            data.append(byte)
                        }
                        let parsed = try? JSONDecoder().decode(CompanyChatStreamErrorBody.self, from: data)
                        throw CompanyChatStreamError.http(status: http.statusCode, body: parsed)
                    }

                    var parser = SSEParser()
                    var lineBuffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                            lineBuffer.removeAll(keepingCapacity: true)
                            for frame in parser.feedLines([line]) {
                                try Self.handleStreamFrame(frame: frame, continuation: continuation)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    // Flush leftover bytes (no trailing newline).
                    if !lineBuffer.isEmpty {
                        let line = String(bytes: lineBuffer, encoding: .utf8) ?? ""
                        for frame in parser.feedLines([line]) {
                            try Self.handleStreamFrame(frame: frame, continuation: continuation)
                        }
                    }
                    // Flush any final frame (server should always end with blank line, but be safe).
                    for frame in parser.feedLines([""]) {
                        try Self.handleStreamFrame(frame: frame, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func handleStreamFrame(
        frame: SSEFrame,
        continuation: AsyncThrowingStream<CompanyChatStreamEvent, Error>.Continuation
    ) throws {
        guard let payload = frame.data.data(using: .utf8) else { return }
        switch frame.event {
        case "delta":
            struct DeltaPayload: Codable { let text: String }
            if let d = try? JSONDecoder().decode(DeltaPayload.self, from: payload) {
                continuation.yield(.delta(d.text))
            }
        case "done":
            struct DonePayload: Codable {
                let model: String
                let cacheHit: Bool
                let runTaskId: String?
                enum CodingKeys: String, CodingKey {
                    case model; case cacheHit = "cache_hit"; case runTaskId = "run_task_id"
                }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                continuation.yield(.done(model: d.model, cacheHit: d.cacheHit, runTaskId: d.runTaskId))
            }
        case "error":
            let parsed = try? JSONDecoder().decode(CompanyChatStreamErrorBody.self, from: payload)
            throw CompanyChatStreamError.http(status: 502, body: parsed)
        default:
            break
        }
    }
}
