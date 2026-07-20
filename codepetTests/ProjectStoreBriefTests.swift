// codepetTests/ProjectStoreBriefTests.swift
import XCTest
@testable import codepet

@MainActor
final class ProjectStoreBriefTests: XCTestCase {
    func testSetCompanyBriefPersistsAndComposesStringAndMarksUserOwned() {
        let store = ProjectStore()
        let project = store.detectProject(cwd: "/tmp/p1")!
        let id = project.id

        store.setCompanyBrief(projectId: id, brief: CompanyBrief(projectName: "Codepet", oneLiner: "a recap tool"))

        XCTAssertEqual(store.companyBrief(for: id)?.projectName, "Codepet")
        XCTAssertTrue(store.brief(for: id).contains("a recap tool."))
        XCTAssertFalse(store.briefDescriptionIsSynthesisWritable(projectPath: id))
    }
}
