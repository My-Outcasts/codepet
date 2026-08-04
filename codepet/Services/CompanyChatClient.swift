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

/// One currently-OFF toolkit item, sent alongside the request so the CF can
/// decide whether to suggest turning it on (`setup` in the reply). Mirrors
/// `Toolkit.catalog` items not yet in `company.enabledTools`.
struct SetupItemDTO: Codable, Equatable {
    let category: String
    let name: String
    let why: String?
}

/// A "go here" suggestion from byte — rendered as a tappable chip, never
/// auto-navigated (mirrors the web). `target` is an optional extra hint
/// (e.g. a department key) used only by some destinations.
struct NavAction: Codable, Equatable {
    let destination: String
    let target: String?
}

/// A "turn this on" suggestion from byte — rendered as a tappable enable
/// card. Resolved to a `ToolItem` via `Toolkit.find(category:name:)`.
struct SetupAction: Codable, Equatable {
    let category: String
    let name: String
}

/// One durable fact byte decided to remember — auto-merged into
/// `company.decisions` (no approval needed), then surfaced as a transient
/// "Noted" chip.
struct RememberedFact: Codable, Equatable {
    let topic: String
    let statement: String
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
    /// The founder's currently-OFF toolkit items — lets the CF decide whether
    /// to suggest enabling one (`setup` in the reply).
    let envSetup: [SetupItemDTO]
    /// The founder's tone preferences from Settings → AI, already composed into
    /// one prompt sentence by `AIStyle.promptFragment()`. `nil` when they've
    /// changed nothing — and because this is an Optional on a synthesised
    /// `encode(to:)` (which uses `encodeIfPresent`), nil omits `style_fragment`
    /// from the JSON entirely rather than sending "". That keeps the wire clean
    /// and makes the zero-cost default observable: no key, no prompt section,
    /// no tokens.
    let styleFragment: String?

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case history
        case userMessage = "user_message"
        case runnable
        case envSetup = "env_setup"
        case styleFragment = "style_fragment"
    }

    /// `runnable`/`envSetup` default to empty and `styleFragment` to nil so
    /// existing call sites (and older tests built before these fields existed)
    /// keep compiling without every caller having to name them explicitly.
    init(companyId: String?, language: String, companionId: String, context: String,
         history: [ChatTurnDTO], userMessage: String, runnable: [RunnableRef] = [],
         envSetup: [SetupItemDTO] = [], styleFragment: String? = nil) {
        self.companyId = companyId
        self.language = language
        self.companionId = companionId
        self.context = context
        self.history = history
        self.userMessage = userMessage
        self.runnable = runnable
        self.envSetup = envSetup
        self.styleFragment = styleFragment
    }
}

/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
    let runTaskId: String?
    let nav: NavAction?
    let setup: SetupAction?
    let remember: [RememberedFact]?

    enum CodingKeys: String, CodingKey {
        case reply
        case runTaskId = "run_task_id"
        case nav
        case setup
        case remember
    }
}

/// A companion reply — text plus optional actions (byte's run_task/nav/setup/remember).
/// navigate/setup/runTaskId are mutually exclusive (at most one is non-nil);
/// remember is orthogonal and can co-occur with any of them.
struct CompanyChatReply: Equatable {
    let text: String
    let runTaskId: String?
    let nav: NavAction?
    let setup: SetupAction?
    let remember: [RememberedFact]

    init(text: String, runTaskId: String? = nil, nav: NavAction? = nil,
         setup: SetupAction? = nil, remember: [RememberedFact] = []) {
        self.text = text
        self.runTaskId = runTaskId
        self.nav = nav
        self.setup = setup
        self.remember = remember
    }
}

// MARK: - Streaming

/// The actions a `done` frame (or the JSON fallback response) can carry.
/// `runTaskId`/`nav`/`setup` are mutually exclusive (≤1 non-nil); `remember`
/// is orthogonal and can co-occur with any of them.
struct ChatDoneAction: Equatable {
    let runTaskId: String?
    let nav: NavAction?
    let setup: SetupAction?
    let remember: [RememberedFact]

    init(runTaskId: String? = nil, nav: NavAction? = nil, setup: SetupAction? = nil,
         remember: [RememberedFact] = []) {
        self.runTaskId = runTaskId
        self.nav = nav
        self.setup = setup
        self.remember = remember
    }
}

/// One event from the companyChat SSE stream. Mirrors `ChatStreamEvent`
/// (ReflectionAPIClient's chatSessionStream) — same wire shapes, same
/// companionChat CF, just a different endpoint.
enum CompanyChatStreamEvent: Equatable {
    case delta(String)
    /// `action` mirrors the JSON response's `run_task_id`/`nav`/`setup`/`remember`.
    case done(model: String, cacheHit: Bool, action: ChatDoneAction)
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
        #if DEBUG
        if MockChat.enabled { return await MockChat.reply(req) }
        #endif
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
        return CompanyChatReply(text: reply, runTaskId: decoded.runTaskId, nav: decoded.nav,
                                 setup: decoded.setup, remember: decoded.remember ?? [])
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
        #if DEBUG
        if MockChat.enabled { return MockChat.stream(req) }
        #endif
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
                let nav: NavAction?
                let setup: SetupAction?
                let remember: [RememberedFact]?
                enum CodingKeys: String, CodingKey {
                    case model; case cacheHit = "cache_hit"; case runTaskId = "run_task_id"
                    case nav; case setup; case remember
                }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                let action = ChatDoneAction(runTaskId: d.runTaskId, nav: d.nav, setup: d.setup,
                                             remember: d.remember ?? [])
                continuation.yield(.done(model: d.model, cacheHit: d.cacheHit, action: action))
            }
        case "error":
            let parsed = try? JSONDecoder().decode(CompanyChatStreamErrorBody.self, from: payload)
            throw CompanyChatStreamError.http(status: 502, body: parsed)
        default:
            break
        }
    }
}
