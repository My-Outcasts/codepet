import XCTest
@testable import codepet

final class ReflectionAPIClientScaffoldTests: XCTestCase {
    private func client(_ status: Int, _ body: String) -> ReflectionAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
        return ReflectionAPIClient(session: URLSession(configuration: config)) { "t" }
    }

    func testMapsServerTasksToRoadmapTasks() async throws {
        let body = #"{"departments":[{"key":"engineering","tasks":[{"title":"Ship auth","detail":"Wire sign-in","who":"draft","kind":"build"}]}]}"#
        let tasks = try await client(200, body).scaffoldRoadmap(
            brief: CompanyBrief(projectName: "Codepet"), stage: .building,
            departments: [RoadmapDeptInput(key: "engineering", name: "Engineering", expertise: "ship")])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].deptKey, .engineering)
        XCTAssertEqual(tasks[0].title, "Ship auth")
        XCTAssertEqual(tasks[0].who, .draft)
        XCTAssertEqual(tasks[0].id, "engineering-0")
    }

    func testEmptyDepartmentsYieldsNoTasks() async throws {
        let tasks = try await client(200, #"{"departments":[]}"#).scaffoldRoadmap(
            brief: CompanyBrief(), stage: .idea, departments: [RoadmapDeptInput(key: "engineering", name: "E", expertise: "x")])
        XCTAssertTrue(tasks.isEmpty)
    }

    func testHTTPErrorThrows() async {
        do { _ = try await client(429, #"{"error":"daily_limit_reached"}"#).scaffoldRoadmap(
            brief: CompanyBrief(), stage: .idea, departments: [RoadmapDeptInput(key: "engineering", name: "E", expertise: "x")])
            XCTFail("expected throw") } catch { /* ok */ }
    }

    func testDuplicateDeptBlocksGetUniqueIds() async throws {
        let body = #"{"departments":[{"key":"engineering","tasks":[{"title":"Ship auth","detail":"Wire sign-in","who":"draft","kind":"build"}]},{"key":"engineering","tasks":[{"title":"Add tests","detail":"Cover auth","who":"draft","kind":"build"}]}]}"#
        let tasks = try await client(200, body).scaffoldRoadmap(
            brief: CompanyBrief(projectName: "Codepet"), stage: .building,
            departments: [RoadmapDeptInput(key: "engineering", name: "Engineering", expertise: "ship")])
        XCTAssertEqual(tasks.map(\.id), ["engineering-0", "engineering-1"])
    }
}
