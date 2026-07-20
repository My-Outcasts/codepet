import XCTest
@testable import codepet

/// Records whether `synthesizeBrief` was ever invoked; every other
/// non-defaulted protocol requirement fails the test if called, since this
/// test exercises only `BriefSynthesizer.backfill`, which should call at
/// most `synthesizeBrief`.
final class NoCallAPIStub: ReflectionAPIClientProtocol {
    private(set) var wasCalled = false

    func summarizeTurn(_ request: SummarizeTurnRequest) async throws -> SummarizeTurnResponse {
        XCTFail("summarizeTurn should not be called")
        throw ReflectionAPIError.malformedResponse
    }

    func summarizeTurnStream(_ request: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> {
        XCTFail("summarizeTurnStream should not be called")
        return AsyncThrowingStream { $0.finish(throwing: ReflectionAPIError.malformedResponse) }
    }

    func summarizeSession(_ request: SummarizeSessionRequest) async throws -> SummarizeSessionResponse {
        XCTFail("summarizeSession should not be called")
        throw ReflectionAPIError.malformedResponse
    }

    func summarizeSessionStream(_ request: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> {
        XCTFail("summarizeSessionStream should not be called")
        return AsyncThrowingStream { $0.finish(throwing: ReflectionAPIError.malformedResponse) }
    }

    func chatSessionStream(_ request: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        XCTFail("chatSessionStream should not be called")
        return AsyncThrowingStream { $0.finish() }
    }

    func fetchGuidance(_ request: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse {
        XCTFail("fetchGuidance should not be called")
        throw ReflectionAPIError.malformedResponse
    }

    func synthesizeBrief(_ request: SynthesizeBriefRequest) async throws -> SynthesizeBriefResponse {
        wasCalled = true
        XCTFail("synthesizeBrief must not be called for an interviewed project")
        throw ReflectionAPIError.malformedResponse
    }
}

@MainActor
final class BriefSynthesizerDemotionTests: XCTestCase {

    private func makeSummarizedSession(path: String) -> Session {
        Session(
            id: "s1",
            turns: [],
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 100),
            summary: SessionSummary(
                sessionId: "s1",
                summary: "Worked on the interviewed project.",
                lesson: "Learned something.",
                generatedAt: Date(timeIntervalSince1970: 0),
                model: "claude-haiku-4-5-20251001",
                schemaVersion: 1
            ),
            projectPath: path,
            filePaths: []
        )
    }

    func testBackfillSkipsProjectsWithAFounderBrief() async {
        let api = NoCallAPIStub()
        let synth = BriefSynthesizer(api: api, minSessions: 1)
        let store = ProjectStore()
        let project = store.detectProject(cwd: "/tmp/interviewed")!
        store.setCompanyBrief(projectId: project.id, brief: CompanyBrief(projectName: "P", oneLiner: "x"))

        synth.backfill(sessions: [makeSummarizedSession(path: project.id)], projectStore: store, language: "en")

        // The synthesizer only fires an async Task when it decides to synthesize;
        // give any (incorrectly) scheduled work a beat to run before asserting.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(api.wasCalled, "synthesizer must not run for an interviewed project")
    }
}
