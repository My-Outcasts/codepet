// codepetTests/RoomTypeScaleTests.swift
import XCTest
@testable import codepet

/// CP-036: the room cards set text at 25 distinct sizes (8.5, 9, 10, 11, 11.5, 12, 12.5, 13, 13.5,
/// 14, 14.5, 15, 16, 16.5, 24, …), two of them below the 10pt floor macOS reads as legible. They
/// now use the app's scale only (`CodepetType`, plus `DeliverableStyle.body` for reading prose):
/// title 15, prose 14, secondary 13, meta 12 / 11 / 10, and one 22 numeral.
final class RoomTypeScaleTests: XCTestCase {
    private static func source() -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("codepet/Views/Copilot/VirtualCompanyCards.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Every literal `inter(<size>` outside comments.
    private static func sizes() -> [Double] {
        let code = source().split(separator: "\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }.joined(separator: "\n")
        let re = try! NSRegularExpression(pattern: #"inter\(([0-9]+(?:\.[0-9]+)?)"#)
        return re.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap {
            Range($0.range(at: 1), in: code).flatMap { Double(code[$0]) }
        }
    }

    func testTheSourceWasFound() {
        XCTAssertFalse(Self.source().isEmpty, "VirtualCompanyCards.swift not found from #filePath")
        XCTAssertGreaterThan(Self.sizes().count, 20, "the regex stopped matching the font calls")
    }

    func testEverySizeIsOnTheScale() {
        let allowed = Set((CodepetType.all + [DeliverableStyle.body]).map(Double.init))
        let off = Self.sizes().filter { !allowed.contains($0) }
        XCTAssertEqual(off, [], "sizes off the scale: \(Set(off).sorted())")
    }

    func testNothingIsBelowTheTenPointFloor() {
        XCTAssertEqual(Self.sizes().filter { $0 < 10 }, [])
    }
}
