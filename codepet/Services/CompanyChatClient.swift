// codepet/Services/CompanyChatClient.swift
import Foundation
import FirebaseAuth
import os

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
    /// The founder's OWN open steps, which `complete_task` may offer to tick off. The opposite
    /// set to `runnable`: that is what Codepet can do, this is what only she can.
    let openTasks: [RunnableRef]
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
    /// Skill ids the founder has turned ON — the mirror of `envSetup`, and what
    /// makes a toggle mean something. Sent whole; the CF ignores any id it has
    /// not implemented, so the app never has to track which are real.
    let enabledSkills: [String]
    /// The department this turn belongs to (a `DepartmentCatalog` key), so the CF can put
    /// that department's real expertise in front of the model.
    ///
    /// Deliberately SEPARATE from `companionId`, because the two answer different questions
    /// and one of them used to answer neither. `companionId` is who speaks; this is what they
    /// know. They come apart in the case that proves they are not the same field: when the
    /// department's pet IS the founder's own companion, there is no visible handoff to
    /// announce — `actingSpecialist` returns nil, and it should — but the marketing question
    /// is still a marketing question and must still be answered with marketing expertise.
    /// Keying the expertise off the handoff would have silently dropped it for exactly those
    /// founders.
    ///
    /// nil when no department is in focus, which omits `dept_key` from the JSON entirely
    /// (Optional + synthesised `encodeIfPresent`) — an ordinary chat turn costs nothing.
    let deptKey: String?

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case language
        case companionId = "companion_id"
        case context
        case history
        case userMessage = "user_message"
        case runnable
        case openTasks = "open_tasks"
        case envSetup = "env_setup"
        case styleFragment = "style_fragment"
        case enabledSkills = "enabled_skills"
        case deptKey = "dept_key"
    }

    /// `runnable`/`envSetup`/`enabledSkills` default to empty and
    /// `styleFragment` to nil so existing call sites (and older tests built
    /// before these fields existed) keep compiling without every caller having
    /// to name them explicitly.
    init(companyId: String?, language: String, companionId: String, context: String,
         history: [ChatTurnDTO], userMessage: String, runnable: [RunnableRef] = [],
         openTasks: [RunnableRef] = [],
         envSetup: [SetupItemDTO] = [], styleFragment: String? = nil,
         enabledSkills: [String] = [], deptKey: String? = nil) {
        self.companyId = companyId
        self.language = language
        self.companionId = companionId
        self.context = context
        self.history = history
        self.userMessage = userMessage
        self.runnable = runnable
        self.openTasks = openTasks
        self.envSetup = envSetup
        self.styleFragment = styleFragment
        self.enabledSkills = enabledSkills
        self.deptKey = deptKey
    }
}

/// The wire shape of `add_task` — mirrors `NewTaskIntent` in companyChatCore.ts.
struct AddTaskDTO: Codable, Equatable {
    let title: String
    let detail: String?
    let dept: String?
    let owner: String?
}

/// The wire shape of one `draft_message` entry — mirrors `MessageDraftIntent` in
/// companyChatCore.ts. A drafted message is CONTENT, not an action: there is nothing to
/// confirm, so unlike the roadmap verbs it carries no intent/confirmation pair.
struct MessageDraftDTO: Codable, Equatable {
    let channel: String
    let to: String?
    let subject: String?
    let body: String

    /// The eyebrow the card shows. Falls back to a DM rather than an email, matching the
    /// backend's own default for an unrecognised channel.
    func eyebrow(_ lang: AppLanguage) -> String {
        switch channel {
        case "email": return lang == .vi ? "Email nháp" : "Email draft"
        case "text":  return lang == .vi ? "Tin nhắn" : "Text message"
        default:      return lang == .vi ? "Tin nhắn" : "Message"
        }
    }

    /// What the card puts above the hairline: an email leads with its subject, everything
    /// else with who it is for. Empty when the model gave neither, and the card then skips
    /// the heading rather than showing a blank line.
    var heading: String {
        let subject = (subject ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if channel == "email", !subject.isEmpty { return subject }
        return (to ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Response body from the companyChat Cloud Function.
struct CompanyChatResponse: Codable {
    let reply: String
    let runTaskId: String?
    let nav: NavAction?
    let setup: SetupAction?
    let remember: [RememberedFact]?
    let completeTaskId: String?
    let addTask: AddTaskDTO?
    let drafts: [MessageDraftDTO]?

    enum CodingKeys: String, CodingKey {
        case reply
        case runTaskId = "run_task_id"
        case nav
        case setup
        case remember
        case completeTaskId = "complete_task_id"
        case addTask = "add_task"
        case drafts
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
    let completeTaskId: String?
    let addTask: AddTaskDTO?
    let drafts: [MessageDraftDTO]

    init(text: String, runTaskId: String? = nil, nav: NavAction? = nil,
         setup: SetupAction? = nil, remember: [RememberedFact] = [],
         completeTaskId: String? = nil, addTask: AddTaskDTO? = nil,
         drafts: [MessageDraftDTO] = []) {
        self.text = text
        self.runTaskId = runTaskId
        self.nav = nav
        self.setup = setup
        self.remember = remember
        self.completeTaskId = completeTaskId
        self.addTask = addTask
        self.drafts = drafts
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
    /// The two roadmap verbs. Independent of the run/nav/setup trio (like `remember`), because
    /// "I finished that, now draft the next one" is one honest turn — but exclusive of each other.
    let completeTaskId: String?
    let addTask: AddTaskDTO?
    /// The messages the companion wrote this turn. Independent of every verb above — content,
    /// not an action — so a turn may carry drafts alongside any of them.
    let drafts: [MessageDraftDTO]

    init(runTaskId: String? = nil, nav: NavAction? = nil, setup: SetupAction? = nil,
         remember: [RememberedFact] = [], completeTaskId: String? = nil,
         addTask: AddTaskDTO? = nil, drafts: [MessageDraftDTO] = []) {
        self.runTaskId = runTaskId
        self.nav = nav
        self.setup = setup
        self.remember = remember
        self.completeTaskId = completeTaskId
        self.addTask = addTask
        self.drafts = drafts
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
                                 setup: decoded.setup, remember: decoded.remember ?? [],
                                 completeTaskId: decoded.completeTaskId, addTask: decoded.addTask,
                                 drafts: decoded.drafts ?? [])
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

                    // Transport shape: an SSE stream that arrives as one buffered blob, or
                    // with a Content-Encoding an intermediate applied, is indistinguishable in
                    // the transcript from the model stopping early.
                    Self.streamLog.info("""
                        response \(http.statusCode, privacy: .public)                         type=\(http.value(forHTTPHeaderField: "Content-Type") ?? "-", privacy: .public)                         enc=\(http.value(forHTTPHeaderField: "Content-Encoding") ?? "-", privacy: .public)                         len=\(http.value(forHTTPHeaderField: "Content-Length") ?? "-", privacy: .public)
                        """)
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
                    var frameCount = 0
                    for try await byte in bytes {
                        if byte == UInt8(ascii: "\n") {
                            var line = String(bytes: lineBuffer, encoding: .utf8)
                            if line == nil {
                                // The whole line is discarded when this happens, so a delta's
                                // text vanishes without a trace. Never observed; logged because
                                // it would look exactly like the model stopping mid-sentence.
                                Self.streamLog.error("line not UTF-8 — \(lineBuffer.count, privacy: .public) bytes dropped")
                                line = ""
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                            frameCount += 1
                            for frame in parser.feedLines([line ?? ""]) {
                                Self.streamLog.info("frame \(frame.event, privacy: .public) — \(frame.data.count, privacy: .public) bytes")
                                try Self.handleStreamFrame(frame: frame, continuation: continuation)
                            }
                        } else {
                            lineBuffer.append(byte)
                        }
                    }
                    Self.streamLog.info("stream ended — \(frameCount, privacy: .public) lines read")
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

    /// Stream diagnostics. Every drop on this path used to be silent — an undecodable frame,
    /// a line that failed UTF-8, a stream that ended with no `done` — which is why a reply
    /// truncated mid-sentence could not be attributed to the model, the function, or this
    /// parser. Reported from the app twice on Aug 5 ("3. Give Encountered," and "…no sales
    /// pitch." Personal"), both unexplainable from code alone. Read with:
    ///   log show --last 15m --predicate 'subsystem == "app.murror.codepet"' --info
    static let streamLog = Logger(subsystem: "app.murror.codepet", category: "ChatStream")

    private static func handleStreamFrame(
        frame: SSEFrame,
        continuation: AsyncThrowingStream<CompanyChatStreamEvent, Error>.Continuation
    ) throws {
        guard let payload = frame.data.data(using: .utf8) else {
            streamLog.error("frame data not UTF-8 — event=\(frame.event, privacy: .public) dropped")
            return
        }
        switch frame.event {
        case "delta":
            struct DeltaPayload: Codable { let text: String }
            if let d = try? JSONDecoder().decode(DeltaPayload.self, from: payload) {
                continuation.yield(.delta(d.text))
            } else {
                // A dropped delta is invisible in the transcript: the text simply lacks that
                // fragment, which reads as the model having stopped there.
                streamLog.error("delta frame undecodable — \(payload.count, privacy: .public) bytes DROPPED")
            }
        case "done":
            struct DonePayload: Codable {
                let model: String
                let cacheHit: Bool
                let runTaskId: String?
                let nav: NavAction?
                let setup: SetupAction?
                let remember: [RememberedFact]?
                let completeTaskId: String?
                let addTask: AddTaskDTO?
                let drafts: [MessageDraftDTO]?
                enum CodingKeys: String, CodingKey {
                    case model; case cacheHit = "cache_hit"; case runTaskId = "run_task_id"
                    case nav; case setup; case remember
                    case completeTaskId = "complete_task_id"; case addTask = "add_task"
                    case drafts
                }
            }
            if let d = try? JSONDecoder().decode(DonePayload.self, from: payload) {
                let action = ChatDoneAction(runTaskId: d.runTaskId, nav: d.nav, setup: d.setup,
                                             remember: d.remember ?? [],
                                             completeTaskId: d.completeTaskId, addTask: d.addTask,
                                             drafts: d.drafts ?? [])
                continuation.yield(.done(model: d.model, cacheHit: d.cacheHit, action: action))
            } else {
                // Worse than a dropped delta: with no `done` the store falls back to the
                // non-streaming sender and REPLACES the text the founder just watched arrive.
                streamLog.error("done frame undecodable — \(payload.count, privacy: .public) bytes; the tail will fall back")
            }
        case "error":
            let parsed = try? JSONDecoder().decode(CompanyChatStreamErrorBody.self, from: payload)
            throw CompanyChatStreamError.http(status: 502, body: parsed)
        default:
            break
        }
    }
}
