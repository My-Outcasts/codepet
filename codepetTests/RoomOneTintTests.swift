// codepetTests/RoomOneTintTests.swift
import XCTest
@testable import codepet

/// CP-036, second half: one accent per message, not competing ones. A landed room used to draw a
/// purple-tinted call card, an orange (or teal) disagreement headline under it, and department
/// chips with green / gold / orange outcome dots — purple, orange and gold at once. Agreed 29 Sep
/// to cut that down; the 6 Oct meeting redesign (mock approved, PR #238) then settled what is left:
///
/// - the call card is the quiet surface (`TeamQuietSurface`), not a tinted `MessageCard`;
/// - the real disagreement keeps ONE warm accent — orange, on its eyebrow and a 2pt rule — and no
///   other accent colour;
/// - there are no department chips at all, so no outcome dots (the names ride the confidence line,
///   and "How the team decided" opens the Stances tab).
///
/// The gold UNRESOLVED badge inside the call stays: it is the outcome, not decoration.
final class RoomOneTintTests: XCTestCase {
    private static func source() -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("codepet/Views/Copilot/VirtualCompanyCards.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// The code of one `private func <name>`, comments dropped: from its signature to the next
    /// member at the same indentation.
    private static func body(of name: String) -> String {
        let lines = source().components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("private func \(name)(") }) else { return "" }
        var out: [String] = []
        for line in lines[start...].dropFirst() {
            let isMember = line.hasPrefix("    ") && !line.hasPrefix("     ")
                && (line.contains(" func ") || line.contains(" var ") || line.contains("///")
                    || line.contains(" struct "))
            if isMember { break }
            if !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    private static var code: String {
        source().split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    func testBothFunctionsWereFound() {
        XCTAssertTrue(Self.body(of: "theCall").contains("TeamQuietSurface"))
        XCTAssertTrue(Self.body(of: "realDisagreement").contains("THE REAL DISAGREEMENT"))
    }

    func testTheCallIsNotATintedCard() {
        XCTAssertFalse(Self.body(of: "theCall").contains("MessageCard("), "the call is a tinted card again")
    }

    /// One warm accent on the disagreement, and nothing else competing with it.
    func testTheDisagreementUsesOnlyTheWarmAccent() {
        let body = Self.body(of: "realDisagreement")
        XCTAssertTrue(body.contains("accentOrange"), "the warm rule is gone")
        let others = ["accentTeal", "accentGold", "accentGreen", "accentPurple", "accentBlue", "accentPink"]
        XCTAssertEqual(others.filter { body.contains($0) }, [])
    }

    func testThereAreNoOutcomeChips() {
        XCTAssertFalse(Self.code.contains("RoomRecord.chips"), "department chips are back")
        XCTAssertFalse(Self.code.contains("outcomeColor"), "something colours by outcome again")
    }
}
