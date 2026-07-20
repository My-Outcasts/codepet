// codepetTests/RoadmapSectionModelTests.swift
import XCTest
@testable import codepet

@MainActor
final class RoadmapSectionModelTests: XCTestCase {
    func testDepartmentsInputCoversAllFourPillars() {
        let keys = RoadmapSectionModel.departmentsInput().map(\.key).sorted()
        XCTAssertEqual(keys, ["business", "engineering", "growth", "marketing"])
    }

    func testGeneratePersistsFetchedTasks() async {
        let store = ProjectStore()
        let id = store.detectProject(cwd: "/tmp/rmv")!.id
        let api = ScaffoldStub(returning: [RoadmapTask(id: "engineering-0", deptKey: .engineering, title: "Ship", detail: "d")])
        let model = RoadmapSectionModel()
        await model.generate(projectId: id, brief: CompanyBrief(projectName: "C"), stage: .building, store: store, api: api)
        XCTAssertEqual(store.roadmapTasks(for: id).map(\.title), ["Ship"])
    }
}

/// Stub returning fixed tasks; only scaffoldRoadmap implemented (others default-throw).
final class ScaffoldStub: ReflectionAPIClientProtocol {
    let out: [RoadmapTask]
    init(returning: [RoadmapTask]) { self.out = returning }
    func scaffoldRoadmap(brief: CompanyBrief, stage: ProjectStage, departments: [RoadmapDeptInput]) async throws -> [RoadmapTask] { out }
    func summarizeTurn(_ r: SummarizeTurnRequest) async throws -> SummarizeTurnResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeTurnStream(_ r: SummarizeTurnRequest) -> AsyncThrowingStream<NarrativeStreamEvent, Error> { .init { $0.finish() } }
    func summarizeSession(_ r: SummarizeSessionRequest) async throws -> SummarizeSessionResponse { throw ReflectionAPIError.malformedResponse }
    func summarizeSessionStream(_ r: SummarizeSessionRequest) -> AsyncThrowingStream<SessionSummaryStreamEvent, Error> { .init { $0.finish() } }
    func chatSessionStream(_ r: ChatSessionRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> { .init { $0.finish() } }
    func fetchGuidance(_ r: GenerateGuidanceRequest) async throws -> GenerateGuidanceResponse { throw ReflectionAPIError.malformedResponse }
}
