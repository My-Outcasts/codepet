import XCTest
@testable import codepet

/// CP-054, from Dominich's build 6 report (1 Oct): the Environment screen showed GitHub as
/// "✓ Connected" under Recommended and with a "Connect" button under Browse all, at the same
/// time. The two sections read different sources: Browse all asked the server whether a token
/// exists (`connectedProviders`), Recommended read the local `enabledTools` flag — which its own
/// button flipped without any consent flow. One rule now decides "on" for every surface.
final class ToolOnStateTests: XCTestCase {
    private func item(_ id: String, _ cat: ToolCategory) -> ToolItem {
        ToolItem(id: id, name: id, badge: "X", detail: "", category: cat,
                 recommended: true, why: nil, defaultOn: false)
    }

    func testAConnectorIsOnOnlyWhenTheServerHasAToken() {
        let gh = item("github", .connectors)
        XCTAssertFalse(ToolOnState.isOn(gh, enabled: ["github"], connected: []),
                       "a local flag must not make a connector read as connected")
        XCTAssertTrue(ToolOnState.isOn(gh, enabled: [], connected: ["github"]))
    }

    func testANonConnectorIsTheLocalFlag() {
        let skill = item("web-research", .skills)
        XCTAssertTrue(ToolOnState.isOn(skill, enabled: ["web-research"], connected: []))
        XCTAssertFalse(ToolOnState.isOn(skill, enabled: [], connected: ["web-research"]))
    }
}
