// codepetTests/ThreadSearchTests.swift
import XCTest
@testable import codepet

/// Guards on finding a conversation by name.
final class ThreadSearchTests: XCTestCase {

    private func thread(_ id: String, _ title: String?) -> ChatThread {
        ChatThread(id: id, title: title, messages: [],
                   createdAt: Date(), updatedAt: Date())
    }

    private var threads: [ChatThread] {
        [thread("1", "Growing Facebook page traffic"),
         thread("2", "Chuẩn bị launch sản phẩm trên Product Hunt"),
         thread("3", "Traffic growth strategy"),
         thread("4", nil)]
    }

    /// The reason this is not `lowercased().contains`. Half the titles here are
    /// Vietnamese, and lowercasing does nothing about diacritics — a founder typing
    /// `chuan` would be told nothing matched while looking straight at the row.
    func testSearchIgnoresVietnameseDiacritics() {
        XCTAssertEqual(ThreadSearch.matches(threads, query: "chuan", untitled: "New chat")
                        .map(\.id), ["2"])
        XCTAssertEqual(ThreadSearch.matches(threads, query: "san pham", untitled: "New chat")
                        .map(\.id), ["2"])
    }

    func testSearchIgnoresCase() {
        XCTAssertEqual(ThreadSearch.matches(threads, query: "FACEBOOK", untitled: "New chat")
                        .map(\.id), ["1"])
    }

    /// An untitled thread reads as "New chat" in the rail, so that is the string the
    /// founder can see and would type. Matching only the stored title would make the
    /// one row whose label is visible the one row that cannot be found.
    func testAnUntitledThreadIsFoundByTheLabelItShows() {
        XCTAssertEqual(ThreadSearch.matches(threads, query: "new chat", untitled: "New chat")
                        .map(\.id), ["4"])
    }

    /// An empty query matches everything, so the caller passes the field straight in
    /// rather than branching on empty.
    func testAnEmptyQueryMatchesEverythingAndIsNotSearching() {
        XCTAssertEqual(ThreadSearch.matches(threads, query: "", untitled: "x").count, 4)
        XCTAssertEqual(ThreadSearch.matches(threads, query: "   ", untitled: "x").count, 4)
        XCTAssertFalse(ThreadSearch.isSearching(""))
        XCTAssertFalse(ThreadSearch.isSearching("  \n "))
        XCTAssertTrue(ThreadSearch.isSearching("a"))
    }

    /// Order is preserved, so the rail's recency sort survives filtering.
    func testMatchesKeepTheOrderTheyCameIn() {
        XCTAssertEqual(ThreadSearch.matches(threads, query: "traffic", untitled: "x")
                        .map(\.id), ["1", "3"])
    }

    /// A query that matches nothing returns nothing rather than everything — the
    /// failure mode of a guard placed on the wrong side of the empty check.
    func testNoMatchesReturnsEmpty() {
        XCTAssertTrue(ThreadSearch.matches(threads, query: "zzzz", untitled: "x").isEmpty)
    }
}
