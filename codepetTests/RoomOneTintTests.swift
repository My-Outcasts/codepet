// codepetTests/RoomOneTintTests.swift
import XCTest
@testable import codepet

/// CP-036, second half: one tinted card per message. In a landed room the call card is the one
/// tinted card. Under it, "THE REAL DISAGREEMENT" drew its headline in orange (teal when they
/// agreed), and each department chip had a green / gold / orange outcome dot, so the reply had
/// purple, orange and gold competing. Agreed 29 Sep: the disagreement section and the chips sit
/// on plain ink, and the chips lose their dots (a chip opens the Stances tab, which shows each
/// outcome). The gold UNRESOLVED badge inside the call card stays as the one warm accent.
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

    private let accents = ["accentOrange", "accentTeal", "accentGold", "accentGreen", "accentPurple"]

    func testBothFunctionsWereFound() {
        XCTAssertTrue(Self.body(of: "landedDisagreement").contains("THE REAL DISAGREEMENT"))
        XCTAssertTrue(Self.body(of: "recordChips").contains("RoomRecord.chips"))
    }

    func testTheDisagreementSectionUsesNoAccentColour() {
        let code = Self.body(of: "landedDisagreement")
        XCTAssertEqual(accents.filter { code.contains($0) }, [])
    }

    func testTheChipsHaveNoOutcomeDot() {
        let code = Self.body(of: "recordChips")
        XCTAssertFalse(code.contains("Circle()"), "a chip still draws a dot")
        XCTAssertFalse(code.contains("outcomeColor"), "a chip still colours by outcome")
        // Purple stays: it is the "How the team decided" link, the app's link colour.
        XCTAssertEqual(accents.filter { $0 != "accentPurple" && code.contains($0) }, [])
    }
}
