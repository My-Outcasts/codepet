import XCTest
@testable import codepet

@MainActor
final class CompanyOnboardingModelTests: XCTestCase {
    func testBuildBriefMapsFieldsAndStage() {
        let m = CompanyOnboardingModel()
        m.founderName = "Mona"; m.role = "Founder"; m.projectName = "Codepet"
        m.oneLiner = "a recap tool"; m.audience = "devs"; m.stageIndex = 1
        let b = m.buildBrief()
        XCTAssertEqual(b.founderName, "Mona")
        XCTAssertEqual(b.projectName, "Codepet")
        XCTAssertEqual(b.oneLiner, "a recap tool")
        XCTAssertEqual(b.stage, CompanyOnboardingModel.stages[1])
    }

    func testSubmitEnrichesAndFinishes() async {
        let m = CompanyOnboardingModel()
        m.projectName = "Codepet"; m.oneLiner = "a recap tool"
        let store = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true })
        await store.hydrate(companyId: "u")
        let api = OnboardEnrichStub(returning: CompanyBrief(projectName: "Codepet", summary: "Enriched."))
        await m.submit(store: store, api: api)
        XCTAssertEqual(store.company.brief.summary, "Enriched.")
        XCTAssertFalse(store.isOnboarding)
    }

    func testSubmitFailOpenStillFinishes() async {
        let m = CompanyOnboardingModel(); m.projectName = "Codepet"
        let store = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true })
        await store.hydrate(companyId: "u")
        await m.submit(store: store, api: ThrowingEnrichStub())
        XCTAssertEqual(store.company.brief.projectName, "Codepet") // raw brief kept
        XCTAssertFalse(store.isOnboarding)
    }
}

/// Test stub returning a fixed enriched brief. Implements the protocol's
/// non-defaulted methods (summarize*/chat/fetchGuidance); the rest have
/// default-throw extensions.
private final class OnboardEnrichStub: ReflectionAPIClientProtocol {
    let out: CompanyBrief
    init(returning: CompanyBrief) { self.out = returning }
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief { out }
    func summarizeTurn(_ r: SummarizeTurnRequest) async throws -> SummarizeTurnResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeTurnStream(_ r: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> { .init { $0.finish() } }
    func summarizeSession(_ r: SummarizeSessionRequest) async throws -> SummarizeSessionResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeSessionStream(_ r: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> { .init { $0.finish() } }
    func chatSessionStream(_ r: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { .init { $0.finish() } }
    func fetchGuidance(_ r: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse { throw ReflectionAPIError.malformedResponse }
}

private final class ThrowingEnrichStub: ReflectionAPIClientProtocol {
    func enrichBrief(_ brief: CompanyBrief) async throws -> CompanyBrief { throw ReflectionAPIError.malformedResponse }
    func summarizeTurn(_ r: SummarizeTurnRequest) async throws -> SummarizeTurnResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeTurnStream(_ r: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> { .init { $0.finish() } }
    func summarizeSession(_ r: SummarizeSessionRequest) async throws -> SummarizeSessionResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeSessionStream(_ r: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> { .init { $0.finish() } }
    func chatSessionStream(_ r: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { .init { $0.finish() } }
    func fetchGuidance(_ r: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse { throw ReflectionAPIError.malformedResponse }
}
