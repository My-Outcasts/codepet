// codepetTests/MarkdownTableHeaderHeightTests.swift
import XCTest
import SwiftUI
import AppKit
@testable import codepet

/// Build 5, 28 Sep (CP-039): the Unit Economics cohort table is too wide to fit, so it scrolls —
/// and its wrapped header ("+ Fixed per-user (auth, push, DB, ~$0.15)") was clipped at the top,
/// its last line drawn over row 1's "$0.15".
///
/// A horizontal `ScrollView` asks its content for its IDEAL size (no width proposed). Each cell
/// answered with its one-line width capped by `.frame(maxWidth:)` — but a one-line HEIGHT — and
/// was then drawn at the cap, wrapped to three lines, in a row one line tall. So the ideal size
/// and the size the table actually draws at must agree.
@MainActor
final class MarkdownTableHeaderHeightTests: XCTestCase {

    private func table() -> MarkdownTableView {
        MarkdownTableView(
            header: ["Cohort", "Sessions / mo", "Monthly session COGS",
                     "+ Fixed per-user (auth, push, DB, ~$0.15)", "Total COGS / user"],
            alignments: [.leading, .trailing, .trailing, .trailing, .trailing],
            rows: [["Light", "4", "$0.53", "$0.15", "$0.68"],
                   ["Heavy", "30", "$3.96", "$0.15", "$4.11"]],
            inline: { Text($0) },
            maxCell: MarkdownTableView.fitCaps.last ?? 90)
    }

    func testTheIdealSizeIsTallEnoughForTheWrappedHeader() {
        // What the scroll view gets: the unproposed, ideal size.
        let ideal = NSHostingView(rootView: table()).fittingSize
        // What the table needs when it is drawn at that width.
        let drawn = NSHostingController(rootView: table())
            .sizeThatFits(in: CGSize(width: ideal.width, height: 10_000))
        XCTAssertGreaterThanOrEqual(ideal.height, drawn.height - 0.5,
            "ideal \(ideal) vs drawn \(drawn): the header row is measured one line tall and drawn three")
    }
}
