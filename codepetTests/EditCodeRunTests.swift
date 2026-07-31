import XCTest
@testable import codepet

final class EditCodeRunTests: XCTestCase {

    func test_needsPreview_showsForMultiFileOrBash_skipsSmall() {
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: false)) // small, safe → skip
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 2, needsBash: false))  // multi-file → show
        XCTAssertTrue(EditCodePlanner.needsPreview(plannedFiles: 1, needsBash: true))   // Bash → show
        XCTAssertFalse(EditCodePlanner.needsPreview(plannedFiles: 0, needsBash: false)) // nothing planned → skip
    }

    func test_backend_gitVsShadowFromLink() {
        let git = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: true)
        let plain = ProjectLink(path: "/p", isGitRepo: false, hasClaudeMd: false)
        if case .git = EditCodePlanner.backend(for: git) {} else { XCTFail("git repo → .git") }
        XCTAssertEqual(EditCodePlanner.backend(for: plain), .shadow)
    }

    func test_gitBackend_branchSlugFromAsk() {
        let link = ProjectLink(path: "/p", isGitRepo: true, hasClaudeMd: false)
        guard case let .git(branch) = EditCodePlanner.backend(for: link, ask: "Fix Signup!") else {
            return XCTFail("expected .git")
        }
        XCTAssertEqual(branch, "codepet/fix-signup")
    }
}
