import XCTest
@testable import codepet

/// CP-056, from Dominich's build 6 report (1 Oct; "known since build 4"): an approved Team Build's
/// project was filed in the Library as kind "Other". It now has a kind of its own, and a project
/// filed before this — stored as "other" with a folder on disk — reads as a Project on load.
final class ProjectKindTests: XCTestCase {
    func testAProjectHasItsOwnLabelAndAFolderIcon() {
        XCTAssertEqual(DeliverableKind.project.label(.en), "Project")
        XCTAssertEqual(DeliverableKind.project.label(.vi), "Dự án")
        XCTAssertEqual(DeliverableKind.project.icon, "folder")
    }

    func testAnOldProjectFiledAsOtherLoadsAsAProject() throws {
        let old = #"{"id":"p1","kind":"other","title":"Pants page","body":"b","projectPath":"/tmp/x"}"#
        XCTAssertEqual(try JSONDecoder().decode(Deliverable.self, from: Data(old.utf8)).kind, .project)
    }

    func testAnOtherWithNoFolderStaysOther() throws {
        let other = #"{"id":"o1","kind":"other","title":"t","body":"b"}"#
        XCTAssertEqual(try JSONDecoder().decode(Deliverable.self, from: Data(other.utf8)).kind, .other)
    }

    func testAProjectRoundTrips() throws {
        let d = Deliverable(id: "p1", kind: .project, title: "Pants page", body: "b", projectPath: "/tmp/x")
        let back = try JSONDecoder().decode(Deliverable.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.kind, .project)
        XCTAssertEqual(back.projectPath, "/tmp/x")
    }
}

/// The Library's own table: a project sorts under the "Builds" chip the web already had, with
/// its own tag and badge, instead of "Docs" / "Other" / "Dr".
final class ProjectKindLibraryTests: XCTestCase {
    func testAProjectSortsUnderBuildsWithItsOwnTagAndBadge() {
        XCTAssertEqual(Lib.bucket(.project), "Builds")
        XCTAssertEqual(Lib.tag(.project, .en), "project")
        XCTAssertEqual(Lib.tag(.project, .vi), "dự án")
        XCTAssertEqual(Lib.badge(.project), "Pj")
    }

    func testOtherIsUnchanged() {
        XCTAssertEqual(Lib.bucket(.other), "Docs")
        XCTAssertEqual(Lib.tag(.other, .en), "Other")
    }
}
