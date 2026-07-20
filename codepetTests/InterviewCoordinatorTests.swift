// codepetTests/InterviewCoordinatorTests.swift
import XCTest
@testable import codepet

@MainActor
final class InterviewCoordinatorTests: XCTestCase {
    func testRequestActivatesOnlyWhenNoBrief() {
        let c = InterviewCoordinator()
        var p = Project(id: "/tmp/x", displayName: "x", brief: "", firstSeenAt: Date(), lastSeenAt: Date())
        c.request(p)
        XCTAssertEqual(c.active?.id, "/tmp/x")
        c.active = nil
        p.companyBrief = CompanyBrief(projectName: "x")
        c.request(p)
        XCTAssertNil(c.active, "should not prompt when a founder brief already exists")
    }
}
