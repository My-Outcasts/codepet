import XCTest
@testable import codepet

final class ProjectLinkSuggestionsTests: XCTestCase {
    private func proj(_ path: String) -> Project {
        Project(id: path, displayName: Project.nameFromPath(path), brief: "",
                firstSeenAt: Date(), lastSeenAt: Date())
    }

    func test_excludesActiveLink_capsAndPreservesOrder() {
        let detected = [proj("/a"), proj("/b"), proj("/c"), proj("/d"), proj("/e")]
        let out = ProjectLinkSuggestions.suggest(from: detected, excluding: "/b", max: 3)
        XCTAssertEqual(out.map(\.id), ["/a", "/c", "/d"])   // /b excluded, order kept, capped to 3
    }

    func test_nilActive_returnsCappedFront() {
        let detected = [proj("/a"), proj("/b")]
        XCTAssertEqual(ProjectLinkSuggestions.suggest(from: detected, excluding: nil, max: 4).map(\.id), ["/a", "/b"])
    }

    func test_empty() {
        XCTAssertTrue(ProjectLinkSuggestions.suggest(from: [], excluding: nil).isEmpty)
    }
}
