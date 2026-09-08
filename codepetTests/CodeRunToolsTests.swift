import XCTest
@testable import codepet

/// A coding run's `--allowedTools` is the ONLY gate on that path — it passes no `--tools` —
/// so a tool missing from this list is denied, exactly as `WebSearch` was in the chat sidecar
/// (7 Sep). These pin both the list and the shell-argument shape.
final class CodeRunToolsTests: XCTestCase {

    /// The scoped default. This run edits a real project on the founder's disk, so the base
    /// list growing by accident is the failure worth catching.
    func testTheBaseListIsTheScopedSix() {
        XCTAssertEqual(CodeRunTools.base, ["Edit", "Write", "Read", "Bash", "Glob", "Grep"])
    }

    /// **Off must mean off.** Nothing may grant network reach to a file-editing run unless the
    /// founder turned the skill on — this is the assertion that makes the feature opt-in.
    func testWebSearchIsAbsentUnlessAskedFor() {
        XCTAssertFalse(CodeRunTools.allowed(webSearch: false).contains("WebSearch"))
        XCTAssertEqual(CodeRunTools.allowed(webSearch: false), CodeRunTools.base)
    }

    func testWebSearchIsPermittedWhenTheSkillIsOn() {
        XCTAssertTrue(CodeRunTools.allowed(webSearch: true).contains("WebSearch"))
    }

    /// **Appended, never substituted.** Permitting the search must not un-permit the editing
    /// tools — the mistake the sidecar's allow-list made from the other direction.
    func testEnablingSearchKeepsEveryEditingTool() {
        let withSearch = CodeRunTools.allowed(webSearch: true)
        for tool in CodeRunTools.base {
            XCTAssertTrue(withSearch.contains(tool), "enabling search dropped \(tool)")
        }
        XCTAssertEqual(withSearch.count, CodeRunTools.base.count + 1)
    }

    /// No duplicate even if the base list ever gains it — a repeated name is not a crash, but
    /// it makes the argument longer than it reads and hides the real contents.
    func testTheListHasNoDuplicates() {
        for on in [false, true] {
            let l = CodeRunTools.allowed(webSearch: on)
            XCTAssertEqual(Set(l).count, l.count, "duplicate tool with webSearch=\(on)")
        }
    }

    /// **The shell contract.** The value is interpolated into ONE quoted argument, so a stray
    /// space would be parsed as part of a tool name and silently deny that tool.
    func testTheArgumentIsCommaJoinedWithNoSpaces() {
        let arg = CodeRunTools.argument(CodeRunTools.allowed(webSearch: true))
        XCTAssertEqual(arg, "Edit,Write,Read,Bash,Glob,Grep,WebSearch")
        XCTAssertFalse(arg.contains(" "))
    }

    func testTheArgumentOmitsSearchWhenOff() {
        XCTAssertEqual(CodeRunTools.argument(CodeRunTools.allowed(webSearch: false)),
                       "Edit,Write,Read,Bash,Glob,Grep")
    }

    /// The toolkit id the store gates on must be the one the catalog actually ships, or the
    /// closure in `CompanyStore` silently reads false forever.
    func testTheWebResearchToolkitIdResolvesToARealCatalogItem() {
        XCTAssertNotNil(Toolkit.catalog.first { $0.id == Toolkit.webResearchId },
                        "web-research is not in the catalog under that id")
    }
}
