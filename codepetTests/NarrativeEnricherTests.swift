import XCTest
@testable import codepet

final class MockAPIClient: ReflectionAPIClientProtocol {
    func fetchGuidance(_ request: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse {
        throw URLError(.unsupportedURL)  // not exercised by these tests
    }
    var calls: [SummarizeTurnRequest] = []
    var response: SummarizeTurnResponse?
    var error: Error?
    var delay: TimeInterval = 0

    func summarizeTurn(_ request: SummarizeTurnRequest) async throws -> SummarizeTurnResponse {
        calls.append(request)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if let error = error { throw error }
        if let response = response { return response }
        return SummarizeTurnResponse(
            turnId: request.turnId,
            narrative: .init(title: "T", whatYouWanted: "w", whatHappened: "h", lesson: "l", nextSteps: "n", mood: "excited", detectedSkills: nil),
            model: "claude-haiku-4-5-20251001",
            cacheHit: false
        )
    }

    func summarizeSession(_ request: SummarizeSessionRequest) async throws -> SummarizeSessionResponse {
        if let error = error { throw error }
        return SummarizeSessionResponse(
            sessionId: request.sessionId,
            summary: .init(summary: "Mock session summary", lesson: "Mock lesson", briefUpdate: nil, projectOverview: nil),
            model: "claude-haiku-4-5-20251001"
        )
    }

    func summarizeTurnStream(_ request: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> {
        // NarrativeEnricher enriches via the streaming API, so record the call
        // here (synchronously, like summarizeTurn) — that's what the retry/count
        // assertions below verify. Snapshot mock config so the Task body doesn't
        // race on mutable state.
        calls.append(request)
        let delay = self.delay
        let error = self.error
        let response = self.response
        return AsyncThrowingStream { continuation in
            Task {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.yield(.started)
                let resp = response ?? SummarizeTurnResponse(
                    turnId: request.turnId,
                    narrative: .init(title: "T", whatYouWanted: "w", whatHappened: "h", lesson: "l", nextSteps: "n", mood: "excited", detectedSkills: nil),
                    model: "claude-haiku-4-5-20251001",
                    cacheHit: false
                )
                continuation.yield(.done(narrative: resp.narrative, model: resp.model, cacheHit: resp.cacheHit))
                continuation.finish()
            }
        }
    }

    func summarizeSessionStream(_ request: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if let error = self.error {
                    continuation.finish(throwing: error)
                    return
                }
                continuation.yield(.started)
                let summary = SummarizeSessionResponse.SummaryPayload(summary: "Mock session summary", lesson: "Mock lesson", briefUpdate: nil, projectOverview: nil)
                continuation.yield(.done(summary: summary, model: "claude-haiku-4-5-20251001", briefUpdate: nil, projectOverview: nil))
                continuation.finish()
            }
        }
    }

    func chatSessionStream(_ request: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
final class NarrativeEnricherTests: XCTestCase {
    var tmpURL: URL!
    var store: NarrativeStore!

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("enricher-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpURL = dir.appendingPathComponent("narratives.jsonl")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        store = NarrativeStore(fileURL: tmpURL, pollInterval: 0.1)
        store.start()
    }

    override func tearDown() async throws {
        store.stop()
        try? FileManager.default.removeItem(at: tmpURL.deletingLastPathComponent())
    }

    private func makeTurn(id: String = "s1:2026-05-05T09:00:00Z", includeEvents: Bool = true) -> Turn {
        let events: [CapturedEvent] = includeEvents ? [
            CapturedEvent(time: "09:00", source: .claudeCode, text: "Edit main.swift")
        ] : []
        return Turn(
            id: id,
            sessionId: "s1",
            startedAt: Date(),
            endedAt: Date(),
            prompt: "do the thing",
            rawEvents: events,
            narrative: nil,
            state: .summarizing,
            cwd: nil
        )
    }

    func testHappyPathPersistsNarrative() async {
        let api = MockAPIClient()
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        await enricher.enrich(turn: makeTurn())

        XCTAssertEqual(api.calls.count, 1)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNotNil(store.narratives["s1:2026-05-05T09:00:00Z"])
    }

    func testNetworkFailReturnsFailedNetwork() async {
        let api = MockAPIClient()
        api.error = ReflectionAPIError.network(URLError(.notConnectedToInternet))
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi", retryDelay: 0)

        let result = await enricher.enrich(turn: makeTurn())

        XCTAssertEqual(result, .failed(reason: .network))
        XCTAssertEqual(api.calls.count, 2)  // 1 attempt + 1 retry
    }

    func testQuotaReturnsFailedQuota() async {
        let api = MockAPIClient()
        api.error = ReflectionAPIError.http(
            status: 429,
            body: SummarizeTurnError(error: "daily_limit_reached", resetAt: "2026-05-06T00:00:00Z", limit: 50, detail: nil)
        )
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        let result = await enricher.enrich(turn: makeTurn())

        XCTAssertEqual(result, .failed(reason: .quota))
        XCTAssertEqual(api.calls.count, 1)  // no retry on quota
    }

    func testAuthErrorReturnsFailedAuth() async {
        let api = MockAPIClient()
        api.error = ReflectionAPIError.http(status: 401, body: nil)
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        let result = await enricher.enrich(turn: makeTurn())
        XCTAssertEqual(result, .failed(reason: .auth))
        XCTAssertEqual(api.calls.count, 1)
    }

    func testEnqueueProcessesSerially() async {
        let api = MockAPIClient()
        api.delay = 0.1
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await enricher.enrich(turn: self.makeTurn(id: "s1:t1")) }
            group.addTask { _ = await enricher.enrich(turn: self.makeTurn(id: "s1:t2")) }
        }

        XCTAssertEqual(api.calls.count, 2)
    }

    func testEmptyTurnSkipsEnrichment() async {
        let api = MockAPIClient()
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        let result = await enricher.enrich(turn: makeTurn(includeEvents: false))

        XCTAssertEqual(result, .ready, "Empty turns should return .ready without calling API")
        XCTAssertEqual(api.calls.count, 0, "No API call should be made for turns with no events")
    }

    func testReadOnlyBashTurnSkipsEnrichment() async {
        let api = MockAPIClient()
        let enricher = NarrativeEnricher(api: api, store: store, language: "vi")

        // Turn with only read-only bash events (git status, ls)
        let readOnlyTurn = Turn(
            id: "s1:2026-05-05T10:00:00Z",
            sessionId: "s1",
            startedAt: Date(),
            endedAt: Date(),
            prompt: "what's the status",
            rawEvents: [
                CapturedEvent(time: "10:00", source: .claudeCode, text: "Bash: git log --oneline && git status -s && ls *.html")
            ],
            narrative: nil,
            state: .summarizing,
            cwd: nil
        )

        let result = await enricher.enrich(turn: readOnlyTurn)

        XCTAssertEqual(result, .ready, "Read-only bash turns should skip enrichment")
        XCTAssertEqual(api.calls.count, 0, "No API call for read-only bash turns")
    }
}
