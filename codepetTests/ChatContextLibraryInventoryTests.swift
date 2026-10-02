// codepetTests/ChatContextLibraryInventoryTests.swift
import XCTest
@testable import codepet

/// Build 6, bug #8: Ask said "the only thing in your Library is a 20-person target list" beside a
/// Library of ten. The model saw three ranked excerpts and the revisable subset, never the whole.
final class ChatContextLibraryInventoryTests: XCTestCase {
    private func item(_ i: Int, body: String = "body") -> Deliverable {
        Deliverable(id: "d\(i)", kind: .doc, title: "Doc \(i)", body: body,
                    createdAt: String(format: "2026-09-%02dT00:00:00Z", i + 1))
    }

    private func count(_ needle: String, in s: String) -> Int { s.components(separatedBy: needle).count - 1 }

    /// Every item reaches the context exactly once — excerpted or listed — and the count covers
    /// all of them. Goes red if the inventory is dropped from `compose`.
    func testComposeNamesEveryLibraryItemOnceWithTheCount() {
        let library = (0..<10).map { item($0) }
        let ctx = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [],
                                      library: library, query: "target list")
        XCTAssertTrue(ctx.contains("The founder's Library holds 10 filed items."))
        for i in 0..<10 { XCTAssertEqual(count("- Doc \(i) (doc)", in: ctx), 1, "Doc \(i)") }
    }

    /// An item with no body is still in the Library (a Team Build project, a site) — the excerpt
    /// ranker skips it, the inventory must not.
    func testAnItemWithNoBodyIsStillListed() {
        let out = ChatContext.composeLibraryInventory([item(1, body: "")])
        XCTAssertTrue(out.contains("holds 1 filed item."))
        XCTAssertTrue(out.contains("- Doc 1 (doc)"))
    }

    func testShownItemsAreCountedButNotRepeated() {
        let out = ChatContext.composeLibraryInventory([item(1), item(2)], shown: ["d2"])
        XCTAssertTrue(out.contains("holds 2 filed items."))
        XCTAssertTrue(out.contains("Besides the ones excerpted above"))
        XCTAssertTrue(out.contains("- Doc 1 (doc)"))
        XCTAssertFalse(out.contains("Doc 2"))
        XCTAssertTrue(ChatContext.composeLibraryInventory([item(1)], shown: ["d1"])
            .hasSuffix("Every one of them is excerpted above."))
    }

    func testNewestFirstAndCapped() throws {
        let library = (0..<28).map { item($0) } + (0..<5).map {
            Deliverable(id: "x\($0)", kind: .doc, title: "Old \($0)", body: "b", createdAt: "2026-01-01T00:00:00Z")
        }
        let out = ChatContext.composeLibraryInventory(library)
        XCTAssertTrue(out.contains("holds 33 filed items."))
        XCTAssertTrue(out.hasSuffix("- …and 3 more"))
        let newer = try XCTUnwrap(out.range(of: "- Doc 27"))
        let older = try XCTUnwrap(out.range(of: "- Doc 26"))
        XCTAssertLessThan(newer.lowerBound, older.lowerBound, "newest first")
    }

    func testAnEmptyLibraryAddsNothing() {
        XCTAssertEqual(ChatContext.composeLibraryInventory([]), "")
        XCTAssertFalse(ChatContext.compose(brief: CompanyBrief(), tasks: []).contains("Library holds"))
    }

    /// The product dossier (up to 6000 chars) goes LAST, so the backend's context clip trims it
    /// and not the company's state. Under the brief, with a 4000 cap, it pushed the Library,
    /// roadmap and decisions out of every chat turn for a founder with a linked folder.
    func testTheProductDossierComesAfterTheLibraryAndRoadmap() throws {
        let product = "ABOUT THE PRODUCT (read from the founder's own project folder — treat as fact):\n"
            + String(repeating: "x", count: 6000)
        let task = RoadmapTask(id: "t1", title: "Ship billing", detail: "", phase: .build, who: .does)
        let ctx = ChatContext.compose(brief: CompanyBrief(projectName: "Codepet"), tasks: [task],
                                      product: product, library: [item(1)], query: nil)
        let productAt = try XCTUnwrap(ctx.range(of: "ABOUT THE PRODUCT")).lowerBound
        for block in ["Library holds", "Roadmap progress", "Open tasks: Ship billing"] {
            let at = try XCTUnwrap(ctx.range(of: block), block).lowerBound
            XCTAssertLessThan(at, productAt, "\(block) must come before the dossier")
        }
    }
}
