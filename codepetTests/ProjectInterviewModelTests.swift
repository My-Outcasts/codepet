// codepetTests/ProjectInterviewModelTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectInterviewModelTests: XCTestCase {
    func testShouldPromptOnlyWhenNoFounderBrief() {
        var p = Project(id: "/tmp/x", displayName: "x", brief: "", firstSeenAt: Date(), lastSeenAt: Date())
        XCTAssertTrue(ProjectInterviewModel.shouldPrompt(for: p))
        p.companyBrief = CompanyBrief(projectName: "x")
        XCTAssertFalse(ProjectInterviewModel.shouldPrompt(for: p))
    }

    func testBuildBriefMapsFieldsIncludingStageLabel() {
        let m = ProjectInterviewModel()
        m.founderName = "Mona"; m.role = "Founder"; m.projectName = "Codepet"
        m.oneLiner = "a recap tool"; m.audience = "devs"; m.stageIndex = 1
        let b = m.buildBrief()
        XCTAssertEqual(b.founderName, "Mona")
        XCTAssertEqual(b.projectName, "Codepet")
        XCTAssertEqual(b.stage, ProjectInterviewModel.stages[1])
        XCTAssertEqual(b.oneLiner, "a recap tool")
    }

    func testSubmitEnrichesAndPersists() async {
        let m = ProjectInterviewModel()
        m.projectName = "Codepet"; m.oneLiner = "a recap tool"
        let store = ProjectStore()
        let p = store.detectProject(cwd: "/tmp/x")!
        let api = EnrichStub(returning: CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool", summary: "Enriched."))
        let ok = await m.submit(projectId: p.id, store: store, api: api)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.companyBrief(for: p.id)?.summary, "Enriched.")
    }
}

/// Stub returning a fixed enriched brief. Conforms to ReflectionAPIClientProtocol;
/// trimmed to exactly the non-defaulted requirements (enrichBrief, fetchPlan,
/// fetchReferenceDistillation, synthesizeBrief, fetchDictionary all have
/// default-throw protocol extension implementations, so only enrichBrief is
/// overridden here for the fixed return value).
final class EnrichStub: ReflectionAPIClientProtocol {
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
