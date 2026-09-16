import XCTest
@testable import codepet

final class SessionChatControllerTests: XCTestCase {

    @MainActor
    func testHappyPathPersistsUserAndPetMessages() async throws {
        let store = SessionChatStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            saveDebounce: 0
        )
        let api = StubAPI(events: [.delta("Hi "), .delta("there."), .done(model: "m", cacheHit: false)])
        let controller = SessionChatController(api: api, store: store)

        await controller.send(
            userText: "what?",
            sessionId: "s1",
            request: makeRequest()
        )

        let messages = store.messages(for: "s1")
        XCTAssertEqual(messages.map(\.role), [.user, .pet])
        XCTAssertEqual(messages[0].text, "what?")
        XCTAssertEqual(messages[1].text, "Hi there.")
        XCTAssertNil(controller.inFlightSessionId)
        XCTAssertEqual(controller.streamingText, "")
    }

    @MainActor
    func testCancelDuringStreamDoesNotPersistPetMessage() async throws {
        let store = SessionChatStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            saveDebounce: 0
        )
        let api = StubAPI(events: [.delta("partial"), .pause, .delta("more"), .done(model: "m", cacheHit: false)])
        let controller = SessionChatController(api: api, store: store)

        let sendTask = Task { @MainActor in
            await controller.send(userText: "x", sessionId: "s1", request: makeRequest())
        }
        // Wait until first delta lands.
        for _ in 0..<50 {
            if controller.streamingText.contains("partial") { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        controller.cancel()
        _ = await sendTask.value

        let messages = store.messages(for: "s1")
        XCTAssertEqual(messages.map(\.role), [.user])
        XCTAssertEqual(controller.streamingText, "")
        XCTAssertNil(controller.inFlightSessionId)
    }

    @MainActor
    func testErrorMidStreamSurfacesAndDoesNotPersistPetMessage() async {
        let store = SessionChatStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            saveDebounce: 0
        )
        let api = StubAPI(events: [.delta("hi"), .error(ReflectionAPIError.http(status: 502, body: nil))])
        let controller = SessionChatController(api: api, store: store)

        await controller.send(userText: "x", sessionId: "s1", request: makeRequest())

        XCTAssertNotNil(controller.error)
        XCTAssertEqual(store.messages(for: "s1").map(\.role), [.user])
    }

    /// **Finding 6 regression guard.** A blocked reason must reach the panel as founder-
    /// authored copy — `.blocked`, rendered verbatim — never folded into `.networkOrServer`,
    /// which the panel deliberately never shows raw. `installedProviders` is empty under
    /// XCTest (the probe is skipped in `init`), so a Claude-only surface with nothing
    /// installed resolves to `.needsClaudeCode` — a real, actionable sentence, not a debug
    /// dump.
    @MainActor
    func testBlockedReasonReachesThePanelVerbatim() async {
        let store = SessionChatStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            saveDebounce: 0
        )
        let api = StubAPI(events: [.error(ReflectionAPIError.blocked(.notGranted))])
        let controller = SessionChatController(api: api, store: store)

        await controller.send(userText: "x", sessionId: "s1", request: makeRequest())

        guard case .blocked(let message) = controller.error else {
            return XCTFail("expected .blocked, got \(String(describing: controller.error))")
        }
        // Founder-facing prose, not a diagnostic label.
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("networkOrServer"))
        // The panel's rendering renders `.blocked` verbatim — no fallback substitution.
        XCTAssertEqual(SessionChatPanel.errorText(controller.error!), message)
    }

    /// **Finding 6 regression guard, the other half.** A `String(describing:)` diagnostic
    /// (what a genuinely dropped connection produces) must NOT reach the founder verbatim —
    /// this is the exact regression: an `NSURLErrorDomain` dump rendered in the chat panel
    /// where "Could not reach your pet — try again." used to be. The controller may still
    /// carry the diagnostic string internally (for logging); the panel's copy must not show it.
    @MainActor
    func testDiagnosticErrorNeverReachesThePanelVerbatim() async {
        let store = SessionChatStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json"),
            saveDebounce: 0
        )
        let api = StubAPI(events: [.error(URLError(.networkConnectionLost))])
        let controller = SessionChatController(api: api, store: store)

        await controller.send(userText: "x", sessionId: "s1", request: makeRequest())

        guard case .networkOrServer(let message) = controller.error else {
            return XCTFail("expected .networkOrServer, got \(String(describing: controller.error))")
        }
        // The raw diagnostic is whatever `String(describing:)` produces for a `URLError` —
        // not founder prose, and specifically not the friendly fallback sentence.
        XCTAssertNotEqual(message, "Could not reach your pet — try again.")
        // The panel must show the generic fallback instead, never this diagnostic string.
        let rendered = SessionChatPanel.errorText(controller.error!)
        XCTAssertEqual(rendered, "Could not reach your pet — try again.")
        XCTAssertNotEqual(rendered, message)
    }

    // Helpers

    private func makeRequest() -> ChatSessionRequest {
        ChatSessionRequest(
            sessionId: "s1", language: "en", petPersona: nil,
            sessionContext: ChatSessionRequest.SessionContextDTO(
                userBrief: nil, summary: nil,
                turns: [.init(prompt: "x", whatYouWanted: nil, whatHappened: nil, lesson: nil, durationMinutes: nil, events: [])]
            ),
            history: [], userMessage: "what?"
        )
    }
}

// MARK: - Stub API

private enum StubEvent {
    case delta(String)
    case done(model: String, cacheHit: Bool)
    case error(Error)
    case pause   // 100ms pause to allow cancellation
}

private final class StubAPI: ReflectionAPIClientProtocol {
    func fetchGuidance(_ request: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse {
        throw URLError(.unsupportedURL)  // not exercised by these tests
    }
    let events: [StubEvent]
    init(events: [StubEvent]) { self.events = events }

    func summarizeTurn(_ request: SummarizeTurnRequest) async throws -> SummarizeTurnResponse {
        fatalError("not used")
    }
    func summarizeTurnStream(_ request: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> {
        fatalError("not used")
    }
    func summarizeSession(_ request: SummarizeSessionRequest) async throws -> SummarizeSessionResponse {
        fatalError("not used")
    }
    func summarizeSessionStream(_ request: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> {
        fatalError("not used")
    }

    func chatSessionStream(_ request: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for event in self.events {
                    if Task.isCancelled { break }
                    switch event {
                    case .delta(let text): continuation.yield(.delta(text))
                    case .done(let model, let cacheHit): continuation.yield(.done(model: model, cacheHit: cacheHit))
                    case .error(let err): continuation.finish(throwing: err); return
                    case .pause:
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }
}
