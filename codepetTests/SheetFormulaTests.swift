import XCTest
@testable import codepet

/// The Swift evaluator against the SAME cases jest runs (`sheetFormula.test.ts`). If the two
/// ever disagree, a sheet shows one number on screen and ships another in the server's `value`.
final class SheetFormulaTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Case: Decodable { let f: String; let value: Double? }
        let env: [String: Double]
        let cases: [Case]
    }

    private func fixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("functions/src/__tests__/fixtures/sheetFormulaCases.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    func testEverySharedCase() throws {
        let fx = try fixture()
        XCTAssertGreaterThan(fx.cases.count, 30, "the fixture did not load")
        for c in fx.cases {
            let node = SheetFormula.parse(c.f)
            if let want = c.value {
                let n = try XCTUnwrap(node, "should parse: \(c.f)")
                XCTAssertEqual(n.evaluate(fx.env), want, accuracy: 1e-9, c.f)
            } else {
                let readsUnknown = node.map { !$0.refs.isSubset(of: Set(fx.env.keys)) } ?? false
                XCTAssertTrue(node == nil || readsUnknown, "should be rejected: \(c.f)")
            }
        }
    }

    func testDisplayUsesTheViewerSymbols() {
        XCTAssertEqual(SheetFormula.display("round(a * b / 100) - c"), "round(a × b ÷ 100) − c")
    }
}
